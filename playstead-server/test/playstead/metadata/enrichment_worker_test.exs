defmodule Playstead.Metadata.EnrichmentWorkerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures

  alias Playstead.Metadata.{Consent, EnrichmentWorker}
  alias Playstead.Repo

  defmodule ProviderFake do
    def search(title, system, opts) do
      send(opts[:test_pid], {:provider_call, title, system})
      if is_function(opts[:before_return], 0), do: opts[:before_return].()

      Keyword.get(opts, :result, {:ok, [candidate(title, system, opts)]})
    end

    def candidate(title, system, opts \\ []) do
      %{
        external_id: 42,
        title: title,
        platform_id: 24,
        platform: "Game Boy Advance",
        provider: "igdb",
        provider_version: "v4",
        confidence: :high,
        match_kind: :suggestion,
        attribution: "IGDB test fixture",
        terms_url: "https://example.test/terms",
        policy_revision: "igdb-test-policy",
        cache_expires_at:
          DateTime.add(DateTime.utc_now(), 86_400, :second) |> DateTime.truncate(:second),
        license_expires_at: nil,
        media_references: %{images: Keyword.get(opts, :images, [])}
      }
      |> Map.put(
        :platform,
        if(system == "gb",
          do: "Game Boy",
          else: if(system == "gbc", do: "Game Boy Color", else: "Game Boy Advance")
        )
      )
    end
  end

  defmodule ImageTransportReject do
    def get(url, _limit, opts) do
      send(opts[:test_pid], {:image_request, url})
      {:ok, %{status: 404, body: <<>>, mime: "image/jpeg", license_expires_at: nil}}
    end
  end

  test "coalesces consented browse into one durable job and records its resumable state" do
    owner = user_scope_fixture().user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})

    assert {:ok, _consent} =
             Consent.enable(owner.id, asset.id, %{
               "title" => asset.display_title,
               "system" => asset.system_id,
               "disclosure_revision" => Consent.disclosure_revision()
             })

    assert {:ok, job} = EnrichmentWorker.enqueue(owner.id, asset.id, :balanced)
    assert job.state in ["queued", "running"]
    assert {:ok, same_job} = EnrichmentWorker.enqueue(owner.id, asset.id, :balanced)
    assert same_job.id == job.id
    assert {:ok, reloaded} = EnrichmentWorker.status(owner.id, job.id)
    assert reloaded.id == job.id
  end

  test "cancels queued work durably and remains canceled after status reload" do
    owner = user_scope_fixture().user
    asset = consented_asset(owner.id)
    assert {:ok, job} = EnrichmentWorker.enqueue(owner.id, asset.id, :gallery)

    assert {:ok, canceled} = EnrichmentWorker.cancel(owner.id, job.id)
    assert canceled.state == "canceled"
    assert canceled.cancel_requested_at
    assert {:ok, reloaded} = EnrichmentWorker.status(owner.id, job.id)
    assert reloaded.state == "canceled"
  end

  test "stores only policy-selected image references for minimal and balanced metadata" do
    owner = user_scope_fixture().user

    refs = [
      %{image_id: "cover-1", size: "cover_big", role: "cover"},
      %{image_id: "shot-1", size: "screenshot_med", role: "screenshot"},
      %{image_id: "shot-2", size: "screenshot_med", role: "screenshot"}
    ]

    for {mode, expected_roles} <- [{:minimal, []}, {:balanced, ["cover", "screenshot"]}] do
      asset = consented_asset(owner.id)
      assert {:ok, job} = EnrichmentWorker.enqueue(owner.id, asset.id, mode)
      candidate = ProviderFake.candidate(asset.display_title, asset.system_id, images: refs)

      assert :ok =
               EnrichmentWorker.perform(%Oban.Job{args: %{"job_id" => job.id}, attempt: 1},
                 provider: ProviderFake,
                 test_pid: self(),
                 result: {:ok, [candidate]}
               )

      evidence =
        Repo.one!(
          from e in Playstead.Metadata.ProviderEvidence, where: e.asset_set_id == ^asset.id
        )

      roles = Enum.map(evidence.media_references["images"], & &1["role"])
      assert roles == expected_roles
    end
  end

  test "requires selected IDs and a matching visible estimate before bulk enqueue" do
    owner = user_scope_fixture().user
    assets = for _ <- 1..2, do: consented_asset(owner.id)
    ids = Enum.map(assets, & &1.id)

    assert {:ok, estimate} = EnrichmentWorker.estimate_preparation(owner.id, ids)
    assert estimate.selected_games == 2
    assert estimate.mode == "balanced"
    assert estimate.disclosed_fields == ["title", "system"]
    assert estimate.requests == 2
    assert estimate.bytes == 2 * 1_048_576
    assert estimate.storage == 0

    assert {:error, :estimate_mismatch} =
             EnrichmentWorker.prepare(owner.id, ids, %{requests: 2, bytes: 0, storage: 0})

    assert {:ok, %{jobs: jobs, estimate: ^estimate}} =
             EnrichmentWorker.prepare(owner.id, ids, estimate)

    assert length(jobs) == 2
  end

  test "does not make a later provider request after consent is revoked during lookup" do
    owner = user_scope_fixture().user
    asset = consented_asset(owner.id)
    assert {:ok, job} = EnrichmentWorker.enqueue(owner.id, asset.id, :gallery)
    oban_job = %Oban.Job{args: %{"job_id" => job.id}, attempt: 1}

    assert :ok =
             EnrichmentWorker.perform(oban_job,
               provider: ProviderFake,
               test_pid: self(),
               before_return: fn -> assert {:ok, _} = Consent.disable(owner.id, asset.id) end
             )

    assert_receive {:provider_call, _, "gba"}
    refute_receive {:image_request, _}
    assert {:ok, persisted} = EnrichmentWorker.status(owner.id, job.id)
    assert persisted.state == "canceled"
    assert persisted.last_error == "consent_revoked"
  end

  test "429 retry-after is honored and transient failures retain queued work" do
    owner = user_scope_fixture().user
    asset = consented_asset(owner.id)
    assert {:ok, job} = EnrichmentWorker.enqueue(owner.id, asset.id, :minimal)
    oban_job = %Oban.Job{args: %{"job_id" => job.id}, attempt: 1}

    assert {:error, %Playstead.Metadata.EnrichmentRetryError{delay_seconds: 12}} =
             EnrichmentWorker.perform(oban_job,
               provider: ProviderFake,
               test_pid: self(),
               result: {:error, {:retry_after, 12}}
             )

    assert {:ok, persisted} = EnrichmentWorker.status(owner.id, job.id)
    assert persisted.state == "queued"
    assert persisted.last_error == "provider_rate_limited"
    assert DateTime.diff(persisted.retry_after_at, DateTime.utc_now(), :second) >= 11

    assert EnrichmentWorker.backoff(%Oban.Job{
             attempt: 1,
             unsaved_error: %{reason: %Playstead.Metadata.EnrichmentRetryError{delay_seconds: 12}}
           }) >= 12
  end

  test "permanent media rejection leaves partial results durable for later reads" do
    previous_terms = Application.get_env(:playstead, :igdb_private_image_terms_revision)
    Application.put_env(:playstead, :igdb_private_image_terms_revision, "terms-test-v1")

    on_exit(fn ->
      if is_nil(previous_terms),
        do: Application.delete_env(:playstead, :igdb_private_image_terms_revision),
        else: Application.put_env(:playstead, :igdb_private_image_terms_revision, previous_terms)
    end)

    owner = user_scope_fixture().user
    asset = consented_asset(owner.id)

    consent =
      Repo.one!(
        from c in Playstead.Metadata.ProviderConsent,
          where: c.user_id == ^owner.id and c.asset_set_id == ^asset.id
      )

    Repo.update!(
      Ecto.Changeset.change(consent,
        image_terms_revision: "terms-test-v1",
        image_grant_scope: "private_single_owner"
      )
    )

    cache_root =
      Path.join(
        System.tmp_dir!(),
        "playstead-provider-cache-test-#{System.unique_integer([:positive])}"
      )

    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)
    on_exit(fn -> File.rm_rf!(cache_root) end)

    image = %{image_id: "fixture-image", size: "cover_big", role: "cover"}
    candidate = ProviderFake.candidate(asset.display_title, "gba", images: [image])
    assert {:ok, job} = EnrichmentWorker.enqueue(owner.id, asset.id, :gallery)

    assert :ok =
             EnrichmentWorker.perform(%Oban.Job{args: %{"job_id" => job.id}, attempt: 1},
               provider: ProviderFake,
               test_pid: self(),
               result: {:ok, [candidate]},
               transport: ImageTransportReject
             )

    assert_receive {:image_request,
                    "https://images.igdb.com/igdb/image/upload/t_cover_big/fixture-image.jpg"}

    assert {:ok, persisted} = EnrichmentWorker.status(owner.id, job.id)
    assert persisted.state == "partial"
    assert persisted.progress["image_errors"] == ["provider_image_rejected"]
    assert persisted.results["evidence_ids"] != []
  end

  defp consented_asset(user_id) do
    asset = asset_set_fixture(user_id, %{system_id: "gba"})

    assert {:ok, _} =
             Consent.enable(user_id, asset.id, %{
               "title" => asset.display_title,
               "system" => asset.system_id,
               "disclosure_revision" => Consent.disclosure_revision()
             })

    asset
  end
end
