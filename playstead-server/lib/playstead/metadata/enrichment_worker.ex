defmodule Playstead.Metadata.EnrichmentJob do
  @moduledoc false
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "metadata_enrichment_jobs" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :provider, :string, default: "igdb"
    field :query_fingerprint, :string
    field :policy_revision, :string
    field :mode, :string
    field :state, :string, default: "queued"
    field :progress, :map, default: %{}
    field :results, :map, default: %{}
    field :request_estimate, :integer, default: 1
    field :byte_estimate, :integer, default: 0
    field :storage_estimate, :integer, default: 0
    field :attempt_count, :integer, default: 0
    field :last_error, :string
    field :retry_after_at, :utc_datetime
    field :cancel_requested_at, :utc_datetime
    field :started_at, :utc_datetime
    field :finished_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :user_id,
      :asset_set_id,
      :provider,
      :query_fingerprint,
      :policy_revision,
      :mode,
      :state,
      :progress,
      :results,
      :request_estimate,
      :byte_estimate,
      :storage_estimate,
      :attempt_count,
      :last_error,
      :retry_after_at,
      :cancel_requested_at,
      :started_at,
      :finished_at
    ])
    |> validate_required([
      :user_id,
      :asset_set_id,
      :provider,
      :query_fingerprint,
      :policy_revision,
      :mode,
      :state
    ])
    |> validate_inclusion(:mode, ["minimal", "balanced", "gallery", "prepare"])
    |> validate_inclusion(:state, [
      "queued",
      "running",
      "partial",
      "complete",
      "canceled",
      "error"
    ])
    |> validate_number(:request_estimate, greater_than: 0, less_than_or_equal_to: 9)
    |> validate_number(:byte_estimate, greater_than_or_equal_to: 0)
    |> validate_number(:storage_estimate, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:asset_set_id)
    |> unique_constraint([:user_id, :asset_set_id, :provider, :query_fingerprint],
      name: :metadata_enrichment_jobs_active_unique
    )
  end
end

defmodule Playstead.Metadata.EnrichmentRetryError do
  @moduledoc false
  defexception [:delay_seconds, :message]
end

defmodule Playstead.Metadata.EnrichmentWorker do
  @moduledoc "Persistent, consent-gated provider enrichment with coalescing and finite work limits."
  use Oban.Worker,
    queue: :metadata,
    max_attempts: 8,
    unique: [keys: [:job_id], states: [:available, :scheduled, :executing]]

  import Ecto.Query, warn: false

  alias Playstead.{Catalogue.AssetSet, Repo}

  alias Playstead.Metadata.{
    Consent,
    EnrichmentJob,
    EnrichmentRetryError,
    ProviderPolicy,
    RequestBudget
  }

  alias Playstead.Metadata.Providers.IGDB

  @active_states ["queued", "running"]
  @queue_limit 8
  @per_user_job_limit 2
  @max_images 8
  @max_attempts 8
  @first_backoff 1
  @max_backoff 3_600

  @doc "Enqueue a coalesced job for an explicitly consented game."
  def enqueue(user_id, asset_set_id, mode, opts \\ []) do
    mode = normalize_mode(mode)

    with {:ok, asset_id} <- Ecto.UUID.cast(asset_set_id),
         {:ok, asset, authorization} <- owned_consent(user_id, asset_id),
         :ok <- validate_enqueue_mode(mode, opts) do
      Repo.transaction(fn ->
        # Serialize cap checks for a user across application nodes.
        Repo.query!("SELECT id FROM users WHERE id = $1 FOR UPDATE", [user_id])
        # Serialize the global finite-queue check across different owners too.
        Repo.query!("SELECT id FROM metadata_request_budgets WHERE id = 1 FOR UPDATE")
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        key =
          fingerprint(
            authorization.title,
            authorization.system,
            mode,
            authorization.consent.revision,
            ProviderPolicy.revision()
          )

        existing = active_job(user_id, asset.id, key)
        if existing, do: Repo.rollback({:existing, existing})

        active_total =
          Repo.aggregate(from(j in EnrichmentJob, where: j.state in ^@active_states), :count)

        if active_total >= @queue_limit, do: Repo.rollback(:queue_full)

        estimate = estimate(mode, opts)

        attrs = %{
          user_id: user_id,
          asset_set_id: asset.id,
          provider: "igdb",
          query_fingerprint: key,
          policy_revision: ProviderPolicy.revision(),
          mode: mode,
          state: "queued",
          progress: %{requests_completed: 0, images_completed: 0, image_errors: []},
          results: %{},
          request_estimate: estimate.requests,
          byte_estimate: estimate.bytes,
          storage_estimate: estimate.storage,
          inserted_at: now,
          updated_at: now
        }

        job =
          case %EnrichmentJob{} |> EnrichmentJob.changeset(attrs) |> Repo.insert() do
            {:ok, job} -> job
            {:error, changeset} -> Repo.rollback(changeset)
          end

        case Oban.insert(new(%{job_id: job.id})) do
          {:ok, _oban_job} -> job
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, job} -> {:ok, job}
        {:error, {:existing, job}} -> {:ok, job}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_request}
    end
  end

  @doc "Enqueue explicitly selected games after checking the displayed aggregate estimate."
  def prepare(user_id, selected_asset_ids, displayed_estimate, opts \\ []) do
    mode = normalize_mode(Keyword.get(opts, :profile_mode, "balanced"))

    with true <- is_list(selected_asset_ids) and length(selected_asset_ids) in 1..@max_images,
         ids <- Enum.uniq(selected_asset_ids),
         true <- length(ids) == length(selected_asset_ids),
         true <- mode in ["minimal", "balanced"],
         estimates <- Enum.map(ids, fn _id -> estimate(mode, count: @max_images) end),
         total <- total_estimate(estimates),
         true <- total == normalize_estimate(displayed_estimate),
         {:ok, jobs} <- enqueue_selected(user_id, ids, Keyword.put(opts, :profile_mode, mode)) do
      {:ok,
       %{
         jobs: jobs,
         estimate:
           Map.merge(total, %{
             mode: mode,
             selected_games: length(ids),
             disclosed_fields: ["title", "system"]
           })
       }}
    else
      false -> {:error, :estimate_mismatch}
      {:error, _} = error -> error
      _ -> {:error, :invalid_selection}
    end
  end

  def estimate_preparation(user_id, selected_asset_ids, mode \\ "balanced") do
    mode = normalize_mode(mode)

    with true <- is_list(selected_asset_ids) and length(selected_asset_ids) in 1..@max_images,
         ids <- Enum.uniq(selected_asset_ids),
         true <- length(ids) == length(selected_asset_ids),
         true <- mode in ["minimal", "balanced"],
         :ok <- validate_selected_consent(user_id, ids) do
      per_game = estimate(mode, count: @max_images)

      {:ok,
       %{
         selected_games: length(ids),
         disclosed_fields: ["title", "system"],
         mode: mode,
         requests: per_game.requests * length(ids),
         bytes: per_game.bytes * length(ids),
         storage: per_game.storage * length(ids)
       }}
    else
      false -> {:error, :invalid_selection}
      {:error, _} = error -> error
      _ -> {:error, :invalid_selection}
    end
  end

  def status(user_id, job_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(job_id),
         %EnrichmentJob{} = job <-
           Repo.one(from j in EnrichmentJob, where: j.id == ^uuid and j.user_id == ^user_id) do
      {:ok, job}
    else
      _ -> {:error, :not_found}
    end
  end

  def cancel(user_id, job_id) do
    case status(user_id, job_id) do
      {:ok, %EnrichmentJob{state: state} = job} when state in @active_states ->
        job =
          Repo.update!(
            EnrichmentJob.changeset(job, %{
              state: "canceled",
              cancel_requested_at: now(),
              finished_at: now()
            })
          )

        cancel_oban_job(job.id)
        Playstead.Metadata.ProviderMediaCache.purge(user_id, job.asset_set_id)
        {:ok, job}

      {:ok, job} ->
        {:ok, job}

      error ->
        error
    end
  end

  def cancel_for_asset(user_id, asset_set_id) do
    Repo.all(
      from j in EnrichmentJob,
        where:
          j.user_id == ^user_id and j.asset_set_id == ^asset_set_id and j.state in ^@active_states
    )
    |> Enum.each(fn job ->
      Repo.update!(
        EnrichmentJob.changeset(job, %{
          state: "canceled",
          last_error: "consent_revoked",
          cancel_requested_at: now(),
          finished_at: now()
        })
      )

      cancel_oban_job(job.id)
    end)

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job_id" => job_id}, attempt: attempt} = oban_job) do
    case Repo.get(EnrichmentJob, job_id) do
      nil -> :ok
      %EnrichmentJob{state: "canceled"} -> :ok
      job -> if claim_user_slot(job), do: execute(job, oban_job, attempt, []), else: {:snooze, 1}
    end
  end

  @doc false
  def perform(%Oban.Job{args: %{"job_id" => job_id}, attempt: attempt} = oban_job, opts) do
    case Repo.get(EnrichmentJob, job_id) do
      nil ->
        :ok

      %EnrichmentJob{state: "canceled"} ->
        :ok

      job ->
        if claim_user_slot(job), do: execute(job, oban_job, attempt, opts), else: {:snooze, 1}
    end
  end

  @impl Oban.Worker
  def backoff(%Oban.Job{unsaved_error: %{reason: %EnrichmentRetryError{delay_seconds: delay}}}) do
    max(@first_backoff, min(@max_backoff, delay + jitter(delay)))
  end

  def backoff(%Oban.Job{attempt: attempt}) do
    base = min(@max_backoff, trunc(:math.pow(2, max(0, attempt - 1))))
    max(@first_backoff, base + jitter(base))
  end

  @doc false
  def request_estimate(mode, count \\ 1), do: estimate(normalize_mode(mode), count: count)

  defp execute(job, oban_job, attempt, opts) do
    job =
      Repo.update!(
        EnrichmentJob.changeset(job, %{
          state: "running",
          started_at: job.started_at || now(),
          attempt_count: attempt
        })
      )

    with :ok <- ensure_not_canceled(job.id),
         {:ok, _authorization} <- Consent.authorize(job.user_id, job.asset_set_id),
         :ok <- RequestBudget.wait_for_slot(),
         {:ok, authorization} <- Consent.authorize(job.user_id, job.asset_set_id),
         {:ok, candidates} <-
           provider(opts).search(authorization.title, authorization.system, provider_opts(opts)),
         candidates <- Enum.map(candidates, &apply_media_policy(&1, job.mode)),
         :ok <- ensure_not_canceled(job.id),
         {:ok, authorization} <- Consent.authorize(job.user_id, job.asset_set_id),
         {:ok, evidence} <-
           Consent.persist_provider_evidence(
             job.user_id,
             job.asset_set_id,
             authorization.consent.revision,
             candidates
           ),
         {:ok, results, image_errors} <- fetch_images(job, authorization, candidates, opts) do
      state = if image_errors == [], do: "complete", else: "partial"
      refreshed = Repo.get!(EnrichmentJob, job.id)

      Repo.update!(
        EnrichmentJob.changeset(refreshed, %{
          state: state,
          results: %{evidence_ids: Enum.map(evidence, & &1.id), media: results},
          progress: %{
            requests_completed: 1 + length(results),
            images_completed: length(results),
            image_errors: image_errors
          },
          last_error: if(image_errors == [], do: nil, else: "some_media_unavailable"),
          finished_at: now()
        })
      )

      :ok
    else
      {:error, :consent_required} ->
        stop_for_consent(job)

      {:error, :consent_stale} ->
        stop_for_consent(job)

      {:error, :canceled} ->
        :ok

      {:error, {:retry_after, seconds}} ->
        retry_job(job, oban_job, seconds, "provider_rate_limited")

      {:error, :provider_unavailable} ->
        retry_job(job, oban_job, nil, "provider_unavailable")

      {:error, reason} ->
        fail_job(job, reason)
    end
  rescue
    error in [EnrichmentRetryError] ->
      reraise error, __STACKTRACE__

    error ->
      require Logger

      Logger.error("metadata enrichment worker failed: #{inspect(error.__struct__)}")

      fail_job(job, :worker_exception)
  end

  defp fetch_images(%EnrichmentJob{mode: mode}, _authorization, _candidates, _opts)
       when mode in ["minimal", "balanced"], do: {:ok, [], []}

  defp fetch_images(job, _authorization, candidates, opts) do
    refs =
      candidates
      |> Enum.flat_map(&(get_in(&1, [:media_references, :images]) || []))
      |> Enum.take(@max_images)

    Enum.reduce_while(refs, {:ok, [], []}, fn ref, {:ok, stored, errors} ->
      with :ok <- ensure_not_canceled(job.id),
           {:ok, _current} <- Consent.authorize_image(job.user_id, job.asset_set_id),
           {:ok, _current} <- Consent.authorize(job.user_id, job.asset_set_id),
           {:ok, object} <-
             Playstead.Metadata.ProviderMediaCache.fetch(
               job.user_id,
               job.asset_set_id,
               ref.image_id,
               ref.size,
               opts
             ) do
        {:cont,
         {:ok, [Map.take(object, [:id, :image_id, :size, :sha256, :size_bytes]) | stored], errors}}
      else
        {:error, :image_rights_unverified} ->
          {:cont, {:ok, stored, errors ++ ["image_rights_unverified"]}}

        {:error, :canceled} ->
          {:halt, {:error, :canceled}}

        {:error, {:retry_after, _seconds}} = error ->
          {:halt, error}

        {:error, :provider_unavailable} = error ->
          {:halt, error}

        {:error, reason} ->
          {:cont, {:ok, stored, errors ++ [to_string(reason)]}}
      end
    end)
  end

  defp apply_media_policy(candidate, "minimal"),
    do: Map.put(candidate, :media_references, %{images: []})

  defp apply_media_policy(candidate, "balanced") do
    images = get_in(candidate, [:media_references, :images]) || []
    cover = Enum.find(images, &(&1.role == "cover"))
    screenshot = Enum.find(images, &(&1.role == "screenshot"))
    selected = Enum.reject([cover, screenshot], &is_nil/1)
    Map.put(candidate, :media_references, %{images: selected})
  end

  defp apply_media_policy(candidate, _mode) do
    images = get_in(candidate, [:media_references, :images]) || []
    Map.put(candidate, :media_references, %{images: Enum.take(images, @max_images)})
  end

  defp retry_job(job, oban_job, retry_after, reason) do
    delay = retry_after || min(@max_backoff, trunc(:math.pow(2, max(0, oban_job.attempt - 1))))

    reason =
      if reason in ["provider_rate_limited", "provider_unavailable"],
        do: reason,
        else: "worker_exception"

    if oban_job.attempt >= @max_attempts do
      Repo.update!(
        EnrichmentJob.changeset(Repo.get!(EnrichmentJob, job.id), %{
          state: "error",
          last_error: reason,
          finished_at: now()
        })
      )

      :ok
    else
      Repo.update!(
        EnrichmentJob.changeset(Repo.get!(EnrichmentJob, job.id), %{
          state: "queued",
          last_error: reason,
          retry_after_at: DateTime.add(now(), min(@max_backoff, max(1, delay)), :second),
          finished_at: nil
        })
      )

      {:error, EnrichmentRetryError.exception(delay_seconds: delay, message: reason)}
    end
  end

  defp fail_job(job, reason) do
    Repo.update!(
      EnrichmentJob.changeset(Repo.get!(EnrichmentJob, job.id), %{
        state: "error",
        last_error: to_string(reason),
        finished_at: now()
      })
    )

    :ok
  end

  defp stop_for_consent(job) do
    Repo.update!(
      EnrichmentJob.changeset(Repo.get!(EnrichmentJob, job.id), %{
        state: "canceled",
        last_error: "consent_revoked",
        finished_at: now()
      })
    )

    Playstead.Metadata.ProviderMediaCache.purge(job.user_id, job.asset_set_id)
    :ok
  end

  defp ensure_not_canceled(job_id) do
    if Repo.exists?(
         from j in EnrichmentJob,
           where: j.id == ^job_id and (j.state == "canceled" or not is_nil(j.cancel_requested_at))
       ),
       do: {:error, :canceled},
       else: :ok
  end

  defp owned_consent(user_id, asset_id) do
    with %AssetSet{} = asset <-
           Repo.one(from a in AssetSet, where: a.id == ^asset_id and a.user_id == ^user_id),
         {:ok, authorization} <- Consent.authorize(user_id, asset.id) do
      {:ok, asset, authorization}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  defp claim_user_slot(job) do
    case Repo.transaction(fn ->
           Repo.query!("SELECT id FROM users WHERE id = $1 FOR UPDATE", [job.user_id])

           running =
             Repo.aggregate(
               from(j in EnrichmentJob,
                 where: j.user_id == ^job.user_id and j.state == "running" and j.id != ^job.id
               ),
               :count
             )

           if running < @per_user_job_limit do
             Repo.update!(
               EnrichmentJob.changeset(job, %{
                 state: "running",
                 started_at: job.started_at || now()
               })
             )

             :ok
           else
             Repo.rollback(:busy)
           end
         end) do
      {:ok, :ok} -> true
      _ -> false
    end
  end

  defp validate_selected_consent(user_id, ids) do
    Enum.reduce_while(ids, :ok, fn id, :ok ->
      case owned_consent(user_id, id) do
        {:ok, _asset, _authorization} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp active_job(user_id, asset_id, key),
    do:
      Repo.one(
        from j in EnrichmentJob,
          where:
            j.user_id == ^user_id and j.asset_set_id == ^asset_id and j.query_fingerprint == ^key and
              j.state in ^@active_states,
          limit: 1
      )

  defp validate_enqueue_mode(mode, _opts) when mode in ["minimal", "balanced", "gallery"], do: :ok

  defp validate_enqueue_mode("prepare", opts),
    do:
      if(opts[:explicit] == true and is_map(opts[:estimate]),
        do: :ok,
        else: {:error, :explicit_estimate_required}
      )

  defp validate_enqueue_mode(_, _), do: {:error, :invalid_mode}

  defp enqueue_selected(user_id, ids, opts) do
    mode = normalize_mode(Keyword.get(opts, :profile_mode, "balanced"))

    Enum.reduce_while(ids, {:ok, []}, fn id, {:ok, jobs} ->
      case enqueue(
             user_id,
             id,
             mode,
             opts
           ) do
        {:ok, job} -> {:cont, {:ok, jobs ++ [job]}}
        error -> {:halt, error}
      end
    end)
  end

  defp normalize_mode(mode) when mode in [:minimal, :balanced, :gallery, :prepare],
    do: Atom.to_string(mode)

  defp normalize_mode(mode) when is_binary(mode), do: mode
  defp normalize_mode(_), do: nil

  defp estimate(mode, opts) do
    count = Keyword.get(opts, :count, 1)
    requests = if mode in ["gallery", "prepare"], do: 1 + min(@max_images, max(1, count)), else: 1
    image_count = requests - 1
    bytes = if mode in ["gallery", "prepare"], do: image_count * 12 * 1_048_576, else: 1_048_576

    storage =
      if mode in ["gallery", "prepare"],
        do: min(32 * 1_048_576, image_count * 8 * 1_048_576),
        else: 0

    %{requests: requests, bytes: bytes, storage: storage}
  end

  defp normalize_estimate(%{"requests" => r, "bytes" => b, "storage" => s}),
    do: %{requests: r, bytes: b, storage: s}

  defp normalize_estimate(%{requests: r, bytes: b, storage: s}),
    do: %{requests: r, bytes: b, storage: s}

  defp normalize_estimate(_), do: nil

  defp total_estimate(estimates),
    do:
      Enum.reduce(estimates, %{requests: 0, bytes: 0, storage: 0}, fn e, acc ->
        Map.new(acc, fn {k, v} -> {k, v + Map.fetch!(e, k)} end)
      end)

  defp fingerprint(title, system, mode, consent_revision, policy_revision),
    do:
      :crypto.hash(
        :sha256,
        Enum.join([title, system, mode, to_string(consent_revision), policy_revision], "\0")
      )
      |> Base.encode16(case: :lower)

  defp provider(opts), do: Keyword.get(opts, :provider, IGDB)

  defp provider_opts(opts),
    do:
      Keyword.take(opts, [
        :transport,
        :test_pid,
        :client_id,
        :access_token,
        :result,
        :before_return,
        :images
      ])

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp jitter(value), do: if(value <= 1, do: 0, else: :rand.uniform(max(1, div(value, 4))))

  defp cancel_oban_job(job_id) do
    case Repo.one(
           from j in Oban.Job,
             where:
               j.worker == ^to_string(__MODULE__) and
                 fragment("?->>'job_id' = ?", j.args, ^job_id),
             order_by: [desc: j.id],
             limit: 1
         ) do
      %Oban.Job{id: id} -> Oban.cancel_job(id)
      _ -> :ok
    end
  end
end
