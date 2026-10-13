defmodule Playstead.Metadata.ConsentTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Metadata.Consent
  alias Playstead.Metadata.ProviderPolicy
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Repo

  defmodule TransportSpy do
    def post(url, headers, body, opts) do
      send(opts[:test_pid], {:provider_called, url, headers, body})

      {:ok,
       %Req.Response{
         status: 200,
         body: [
           %{
             "id" => 42,
             "name" => "Fixture Game",
             "platforms" => [%{"id" => 24, "name" => "Game Boy Advance"}]
           }
         ]
       }}
    end
  end

  test "disabled and stale consent make zero provider requests and image access fails closed" do
    owner = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id, %{system_id: "gba", title_source: "filename"})
    assert {:ok, preview} = Consent.preview(owner.id, asset_set.id)
    assert preview.enabled == false
    assert preview.provider == "igdb"
    assert preview.terms_url == "https://legal.twitch.com/legal/developer-agreement/"
    assert preview.image_fetch_allowed == false

    refute ProviderPolicy.image_fetch_allowed?(%{
             image_terms_revision: "unverified-terms",
             image_grant_scope: "private_single_owner"
           })

    assert {:error, :consent_required} = Consent.authorize(owner.id, asset_set.id)

    assert {:error, :consent_required} =
             Consent.search(owner.id, asset_set.id, transport: TransportSpy, test_pid: self())

    refute_receive {:provider_called, _, _, _}

    assert {:ok, consent} =
             Consent.enable(owner.id, asset_set.id, %{
               "title" => asset_set.display_title,
               "system" => asset_set.system_id,
               "disclosure_revision" => Consent.disclosure_revision()
             })

    assert consent.enabled
    assert {:ok, authorized} = Consent.authorize(owner.id, asset_set.id)
    assert authorized.title == asset_set.display_title
    assert authorized.system == asset_set.system_id

    assert {:ok, [evidence]} =
             Consent.search(owner.id, asset_set.id,
               client_id: "test-client",
               access_token: "test-token",
               transport: TransportSpy,
               test_pid: self()
             )

    assert_receive {:provider_called, "https://api.igdb.com/v4/games", headers, body}
    assert {"client-id", "test-client"} in headers
    assert {"authorization", "Bearer test-token"} in headers

    assert body ==
             ~s(search "Fixture Game"; fields id,name,summary,platforms.id,platforms.name,cover.image_id,screenshots.image_id; where platforms = 24; limit 10;)

    assert evidence.external_id == 42
    assert evidence.match_kind == "suggestion"
    assert evidence.terms_url =~ "developer-agreement"
    assert evidence.license_expires_at == nil
    assert {:error, :image_rights_unverified} = Consent.authorize_image(owner.id, asset_set.id)

    Repo.update!(
      Ecto.Changeset.change(%AssetSet{} = Repo.get!(AssetSet, asset_set.id),
        display_title: "Corrected title"
      )
    )

    assert {:error, :consent_stale} =
             Consent.search(owner.id, asset_set.id, transport: TransportSpy, test_pid: self())

    refute_receive {:provider_called, _, _, _}

    assert {:ok, _disabled} = Consent.disable(owner.id, asset_set.id)
    assert {:error, :consent_required} = Consent.authorize(owner.id, asset_set.id)

    assert {:ok, media} =
             Playstead.Metadata.PrivateMedia.create(
               owner.id,
               asset_set.id,
               "private authored image notes",
               "text/plain"
             )

    assert {:ok, "private authored image notes"} =
             Playstead.Metadata.PrivateMedia.fetch_original(owner.id, asset_set.id, media.id)
  end

  test "consent is owner-scoped and the disclosure records filename-derived title warning" do
    owner = user_scope_fixture().user
    other = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id, %{system_id: "gba", title_source: "filename"})

    assert {:error, :not_found} = Consent.authorize(other.id, asset_set.id)
    assert {:ok, preview} = Consent.preview(owner.id, asset_set.id)
    assert preview.query_preview == asset_set.display_title
    assert preview.title_warning == "filename_derived_title"
  end

  test "authenticated provider routes expose disclosure and reject another owner's asset", %{
    conn: conn
  } do
    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)
    asset_set = asset_set_fixture(owner.user.id, %{system_id: "gba", title_source: "filename"})
    other = user_scope_fixture()
    other_asset = asset_set_fixture(other.user.id, %{system_id: "gba"})

    assert conn |> get("/api/v1/metadata/#{asset_set.id}/provider") |> response(401)

    denied =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/metadata/#{other_asset.id}/provider")

    PlaysteadWeb.ApiCase.assert_problem(denied, 404, :not_found)

    consented =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "igdb-consent-#{System.unique_integer([:positive])}")
      |> put_req_header("content-type", "application/json")
      |> post("/api/v1/metadata/#{asset_set.id}/provider/consent", %{
        "title" => asset_set.display_title,
        "system" => asset_set.system_id,
        "disclosure_revision" => Consent.disclosure_revision()
      })

    assert json_response(consented, 200)["enabled"]

    preview =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/metadata/#{asset_set.id}/provider")
      |> json_response(200)

    assert preview["query_preview"] == asset_set.display_title
    assert preview["title_warning"] == "filename_derived_title"
    assert preview["image_fetch_allowed"] == false
    assert preview["license_expires_at"] == nil

    now = DateTime.utc_now() |> DateTime.truncate(:second)
    cache_root = Path.join(Playstead.Blobs.Store.LocalDisk.blob_path(), "provider-media-cache")
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)
    blocked_key = "#{owner.user.id}/#{asset_set.id}/blocked.png"
    blocked_path = Path.join(cache_root, blocked_key)
    File.mkdir_p!(blocked_path)

    on_exit(fn ->
      if is_nil(previous_root),
        do: Application.delete_env(:playstead, :metadata_provider_cache_root),
        else: Application.put_env(:playstead, :metadata_provider_cache_root, previous_root)

      File.rm_rf!(cache_root)
    end)

    blocked =
      Repo.insert!(%Playstead.Metadata.ProviderMediaCache.Object{
        user_id: owner.user.id,
        asset_set_id: asset_set.id,
        provider: "igdb",
        image_id: "blocked",
        size: "cover_small",
        object_key: blocked_key,
        sha256: String.duplicate("d", 64),
        size_bytes: 9,
        pinned: false,
        legally_refetchable: true,
        cache_expires_at: DateTime.add(now, 60, :second),
        license_expires_at: nil,
        last_accessed_at: now
      })

    assert {:error, {:revoked_cache_cleanup_failed, revoked}} =
             Consent.disable(owner.user.id, asset_set.id)

    refute revoked.enabled
    assert {:error, :consent_required} = Consent.authorize(owner.user.id, asset_set.id)
    assert Repo.get(Playstead.Metadata.ProviderMediaCache.Object, blocked.id)
    assert Playstead.Metadata.ProviderMediaCache.usage(owner.user.id).used_bytes == 9

    revoked_response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header(
        "idempotency-key",
        "igdb-revoke-#{System.unique_integer([:positive])}"
      )
      |> delete("/api/v1/metadata/#{asset_set.id}/provider/consent")

    assert revoked_response.status == 200

    response_body = json_response(revoked_response, 200)

    assert %{
             "provider" => "igdb",
             "enabled" => false,
             "revision" => revision,
             "cache_cleanup" => %{"status" => "failed", "retryable" => true}
           } = response_body

    assert is_integer(revision)

    assert Map.keys(response_body) |> Enum.sort() ==
             ~w(cache_cleanup enabled provider revision)

    File.rm_rf!(blocked_path)
    assert {:ok, %{enabled: false}} = Consent.disable(owner.user.id, asset_set.id)
    refute Repo.get(Playstead.Metadata.ProviderMediaCache.Object, blocked.id)
    assert Playstead.Metadata.ProviderMediaCache.usage(owner.user.id).used_bytes == 0
  end

  test "provider selection returns an owner-scoped evidence UUID that can be reset explicitly", %{
    conn: conn
  } do
    previous_stub = Application.get_env(:playstead, :metadata_provider_test_stub)
    previous_pid = Application.get_env(:playstead, :metadata_provider_test_pid)
    Application.put_env(:playstead, :metadata_provider_test_stub, true)
    Application.put_env(:playstead, :metadata_provider_test_pid, self())

    on_exit(fn ->
      if is_nil(previous_stub),
        do: Application.delete_env(:playstead, :metadata_provider_test_stub),
        else: Application.put_env(:playstead, :metadata_provider_test_stub, previous_stub)

      if is_nil(previous_pid),
        do: Application.delete_env(:playstead, :metadata_provider_test_pid),
        else: Application.put_env(:playstead, :metadata_provider_test_pid, previous_pid)
    end)

    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)

    asset =
      asset_set_fixture(owner.user.id, %{system_id: "gba", display_title: "Local Fixture Game"})

    assert {:ok, _} =
             Consent.enable(owner.user.id, asset.id, %{
               "title" => asset.display_title,
               "system" => asset.system_id,
               "disclosure_revision" => Consent.disclosure_revision()
             })

    results =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header(
        "idempotency-key",
        "metadata-search-#{System.unique_integer([:positive])}"
      )
      |> post("/api/v1/metadata/#{asset.id}/provider/search", %{})
      |> json_response(200)

    [candidate] = results["results"]
    assert candidate["external_id"] == 7409
    assert {:ok, evidence_uuid} = Ecto.UUID.cast(candidate["id"])
    assert_receive {:metadata_test_provider_request, query}
    assert query =~ ~s(search "Local Fixture Game";)
    refute query =~ asset.id
    refute query =~ "sha256"

    selected =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "metadata-reset-#{System.unique_integer([:positive])}")
      |> post("/api/v1/metadata/#{asset.id}/reset-provider", %{
        "field" => "title",
        "base_revision" => 0,
        "evidence_id" => evidence_uuid
      })
      |> json_response(201)

    assert selected["selections"]["title"] == "Local Fixture Game"
    assert selected["field_sources"]["title"]["source"] == "provider"
    assert selected["field_sources"]["title"]["evidence_id"] == evidence_uuid
  end
end
