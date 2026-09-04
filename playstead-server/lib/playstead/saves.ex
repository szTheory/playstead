defmodule Playstead.Saves do
  @moduledoc """
  The user-scoped saves bounded context (D-25, D-26): save lines and
  their immutable revision DAG. Every public function takes the owning
  user id (or scopes through it) and every query filters on it, the
  same discipline `Playstead.Curation` follows.

  `commit_revision/3` performs D-26's exact four-step commit order
  inside one `Ecto.Multi`, never a separate transaction: resolve-or-
  insert the save line, commit the pending blob through
  `Playstead.Blobs` (never through the store directly, never
  reimplementing the store's own durable-write discipline), insert the
  `save_revisions` row, then
  append the `save` journal entry through the same `ChangeJournal` call
  `Playstead.Curation` uses. The idempotency receipt itself is written
  by `Playstead.Idempotency.execute/4` around the whole thing at the
  controller layer, exactly like `PlaysteadWeb.Api.V1.CurationController`
  -- this context knows nothing of idempotency receipts, and it knows
  nothing of CAS layout: `blobs` learns nothing about saves either.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs
  alias Playstead.Repo
  alias Playstead.Saves.{Branches, PendingUpload, Revision, Save}
  alias Playstead.Sync.{ChangeJournal, SavePayload}

  # D-16: how long a streamed-upload's blob digest stays claimable by a
  # matching metadata commit before it is considered abandoned. A sweep
  # job for expired rows is out of scope for this plan (T-04-04-07).
  @pending_upload_ttl_seconds 3600

  # D-13: the only loud cap that can turn away a commit outright -- more
  # than this many simultaneous heads on one line.
  @max_branch_heads 32

  # D-28: keep-everything-forever backstops. These never refuse a
  # commit and never delete anything; a future saves-owned attention
  # source (plan 04-10) surfaces a crossing as pressure, not an error.
  @revision_count_backstop 100_000
  @storage_bytes_backstop 21_474_836_480

  @doc "The branch-head cap (D-13): a commit that would create a head beyond this is refused."
  @spec max_branch_heads() :: pos_integer()
  def max_branch_heads, do: @max_branch_heads

  @doc "The per-user revision-count backstop (D-28): surfaced as attention, never enforced here."
  @spec revision_count_backstop() :: pos_integer()
  def revision_count_backstop, do: @revision_count_backstop

  @doc "The per-user storage-bytes backstop (D-28): surfaced as attention, never enforced here."
  @spec storage_bytes_backstop() :: pos_integer()
  def storage_bytes_backstop, do: @storage_bytes_backstop

  @doc """
  Records that `command_id`'s streamed upload (already committed into
  the CAS by the caller) produced `blob_sha256`/`size_bytes`, so the
  metadata-commit half can find it without the client resending the
  digest. Idempotent: re-uploading the same `command_id` (e.g. a
  retried PUT) replaces the pointer with the latest result.
  """
  @spec record_pending_upload(pos_integer(), binary(), binary(), String.t(), non_neg_integer()) ::
          {:ok, PendingUpload.t()} | {:error, term()}
  def record_pending_upload(user_id, device_id, command_id, blob_sha256, size_bytes) do
    attrs = %{
      id: command_id,
      user_id: user_id,
      device_id: device_id,
      blob_sha256: blob_sha256,
      size_bytes: size_bytes,
      expires_at: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(@pending_upload_ttl_seconds, :second)
    }

    %PendingUpload{}
    |> PendingUpload.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:blob_sha256, :size_bytes, :expires_at, :updated_at]},
      conflict_target: [:id],
      returning: true
    )
  end

  @doc """
  Commits one revision for `user_id`, captured by `device`, per
  `attrs` (string-keyed, mirroring the other contexts' controller
  boundary). `attrs` must include `"command_id"` (naming the
  already-uploaded pending blob), `"id"` (the client-supplied revision
  id), and `"content_key"`; `"save_kind"` and `"slot"` default to
  `"battery"`/`"0"` (D-10). Returns `{:error, :not_found}` if
  `command_id` names no live pending upload for this user.
  """
  @spec commit_revision(pos_integer(), map(), map()) :: {:ok, Revision.t()} | {:error, term()}
  def commit_revision(user_id, device, attrs) do
    with {:ok, pending} <- fetch_pending_upload(user_id, get(attrs, "command_id")) do
      content_key = get(attrs, "content_key")
      save_kind = get(attrs, "save_kind") || "battery"
      slot = get(attrs, "slot") || "0"
      revision_id = get(attrs, "id") || Ecto.UUID.generate()
      line_id = Ecto.UUID.generate()
      parent_revision_id = get(attrs, "parent_revision_id")
      base_sha256 = get(attrs, "base_sha256")
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      line_changeset =
        Save.create_changeset(%Save{}, %{
          id: line_id,
          user_id: user_id,
          content_key: content_key,
          save_kind: save_kind,
          slot: slot
        })

      Ecto.Multi.new()
      # `returning: true` is load-bearing (mirrors `Curation.add_favorite/3`):
      # the primary key is client-generated, not autogenerated, so a
      # conflict must hand back the pre-existing line's real id, not the
      # id this call happened to try.
      |> Ecto.Multi.insert(:line, line_changeset,
        on_conflict: {:replace, [:updated_at]},
        conflict_target: [:user_id, :content_key, :save_kind, :slot],
        returning: true
      )
      # P5-WR-001 shape (Curation): a per-line advisory lock so a
      # concurrent cap-check-then-insert for the same line serializes
      # behind whichever request acquires it first, rather than racing
      # on a plain read-then-write of the current heads.
      |> Ecto.Multi.run(:lock, fn repo, %{line: line} -> acquire_cap_lock(repo, :save_line, line.id) end)
      |> Ecto.Multi.run(:blob, fn _repo, _changes ->
        if Blobs.exists?(pending.blob_sha256) do
          {:ok, pending}
        else
          {:error, {:save_revision_digest_mismatch, "The uploaded blob could not be found."}}
        end
      end)
      # D-13: the only rejection in this path. A parent unknown to the
      # server is reachable only by client outbox mis-ordering; it is
      # retried (409 + Retry-After), never surfaced to the user, and
      # the same commit succeeds once the parent has been committed.
      |> Ecto.Multi.run(:parent, fn _repo, _changes -> resolve_parent(user_id, parent_revision_id) end)
      |> Ecto.Multi.run(:outcome, fn _repo, %{line: line, parent: parent} ->
        commit_outcome(
          user_id,
          device,
          line,
          parent,
          parent_revision_id,
          pending,
          revision_id,
          base_sha256,
          attrs,
          now
        )
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{outcome: revision}} -> {:ok, revision}
        {:error, _step, reason, _changes} -> {:error, reason}
      end
    end
  end

  defp resolve_parent(_user_id, nil), do: {:ok, nil}

  defp resolve_parent(user_id, parent_revision_id) do
    case Repo.get_by(Revision, id: parent_revision_id, user_id: user_id) do
      nil ->
        {:error,
         {:save_parent_unknown, "The named parent revision is not yet known to the server."}}

      %Revision{} = parent ->
        {:ok, parent}
    end
  end

  # D-30's rule composes with D-04's client promotion policy rather
  # than replacing it: same digest from the same origin device as the
  # named parent is confirmation, not history -- bump the parent
  # in place. Same digest from a different origin device is genuine
  # independent evidence and inserts a new revision sharing the blob.
  defp commit_outcome(
         user_id,
         device,
         line,
         parent,
         parent_revision_id,
         pending,
         revision_id,
         base_sha256,
         attrs,
         now
       ) do
    if confirmable?(parent, pending, device) do
      confirm_existing(parent, now)
    else
      with :ok <- check_branch_cap(user_id, line.id, parent_revision_id) do
        insert_revision(
          user_id,
          device,
          line,
          parent,
          parent_revision_id,
          pending,
          revision_id,
          base_sha256,
          attrs,
          now
        )
      end
    end
  end

  defp confirmable?(nil, _pending, _device), do: false

  defp confirmable?(%Revision{} = parent, pending, device) do
    parent.blob_sha256 == pending.blob_sha256 and parent.origin_device_id == device.id
  end

  defp confirm_existing(%Revision{} = parent, now) do
    parent
    |> Ecto.Changeset.change(last_confirmed_at: now, confirm_count: (parent.confirm_count || 0) + 1)
    |> Repo.update()
  end

  defp check_branch_cap(user_id, line_id, parent_revision_id) do
    head_ids = user_id |> Branches.heads(line_id) |> MapSet.new(& &1.id)

    prospective_count =
      if parent_revision_id && MapSet.member?(head_ids, parent_revision_id) do
        MapSet.size(head_ids)
      else
        MapSet.size(head_ids) + 1
      end

    if prospective_count > @max_branch_heads do
      {:error, {:save_branch_limit_exceeded, "This save line has reached its branch limit."}}
    else
      :ok
    end
  end

  defp insert_revision(
         user_id,
         device,
         line,
         parent,
         parent_revision_id,
         pending,
         revision_id,
         base_sha256,
         attrs,
         now
       ) do
    changeset =
      Revision.create_changeset(%Revision{}, %{
        id: revision_id,
        user_id: user_id,
        save_line_id: line.id,
        parent_revision_id: parent_revision_id,
        blob_sha256: pending.blob_sha256,
        size_bytes: pending.size_bytes,
        origin_device_id: device.id,
        device_captured_at: get(attrs, "device_captured_at"),
        recorded_at: now,
        capture_method: get(attrs, "capture_method"),
        adapter_id: get(attrs, "adapter_id"),
        adapter_version: get(attrs, "adapter_version"),
        save_format: get(attrs, "save_format"),
        format_confidence: get(attrs, "format_confidence"),
        play_session_id: get(attrs, "play_session_id"),
        base_sha256: base_sha256,
        base_matched: base_matched?(base_sha256, parent),
        device_reported_now: get(attrs, "device_reported_now"),
        device_clock_offset_ms: get(attrs, "device_clock_offset_ms"),
        device_monotonic_ms: get(attrs, "device_monotonic_ms"),
        origin: get(attrs, "origin")
      })

    case Repo.insert(changeset) do
      {:ok, revision} ->
        case ChangeJournal.append(user_id, :save, revision.id, SavePayload.build(revision, line)) do
          {:ok, _entry} -> {:ok, revision}
          {:error, reason} -> {:error, reason}
        end

      {:error, %Ecto.Changeset{} = changeset} ->
        classify_revision_changeset(changeset)
    end
  end

  # D-13: a committed revision is immutable -- an `id` primary-key
  # conflict is an attempt to modify one, not a generic validation
  # failure.
  defp classify_revision_changeset(changeset) do
    if Enum.any?(changeset.errors, fn {field, _} -> field == :id end) do
      {:error, {:save_revision_immutable, "A committed revision cannot be modified."}}
    else
      {:error, changeset}
    end
  end

  # D-12: nil when there is no base to compare (no submitted digest, or
  # no parent to compare it against); otherwise a plain equality check
  # against the named parent's stored blob digest. A mismatch is
  # recorded, never rejected -- the caller proceeds regardless.
  defp base_matched?(nil, _parent), do: nil
  defp base_matched?(_base_sha256, nil), do: false
  defp base_matched?(base_sha256, %Revision{blob_sha256: parent_sha256}), do: base_sha256 == parent_sha256

  @doc """
  A save line's revisions (ordered by server `recorded_at`) and its
  derived branch heads, scoped strictly to `user_id`. Returns
  `{:error, :not_found}` for a line outside the caller's scope --
  never a distinct "forbidden" outcome, so existence is not confirmed
  to a caller who does not own the line.
  """
  @spec get_history(pos_integer(), binary()) ::
          {:ok, %{line: Save.t(), revisions: [Revision.t()], heads: [Revision.t()]}}
          | {:error, :not_found}
  def get_history(user_id, save_line_id) do
    case Repo.get_by(Save, id: save_line_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      %Save{} = line ->
        revisions =
          from(r in Revision,
            where: r.user_id == ^user_id and r.save_line_id == ^save_line_id,
            order_by: [asc: r.recorded_at]
          )
          |> Repo.all()

        {:ok, %{line: line, revisions: revisions, heads: Branches.heads(user_id, save_line_id)}}
    end
  end

  # P5-WR-001 shape (`Curation`): a Postgres transaction-scoped
  # advisory lock keyed on `{resource, key}` so a concurrent
  # cap-check-then-insert for the same resource serializes behind
  # whichever request acquires it first. Released automatically at
  # transaction commit/rollback.
  defp acquire_cap_lock(repo, resource, key) do
    repo.query!("SELECT pg_advisory_xact_lock($1)", [:erlang.phash2({resource, key})])
    {:ok, :locked}
  end

  @doc "Fetches the live (unexpired) pending upload for `user_id`/`command_id`."
  @spec fetch_pending_upload(pos_integer(), binary() | nil) ::
          {:ok, PendingUpload.t()} | {:error, :not_found}
  def fetch_pending_upload(_user_id, nil), do: {:error, :not_found}

  def fetch_pending_upload(user_id, command_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from(p in PendingUpload,
        where: p.id == ^command_id and p.user_id == ^user_id and p.expires_at > ^now
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      %PendingUpload{} = pending -> {:ok, pending}
    end
  end

  @doc "Fetches a revision (owned by `user_id`) by its id, or `nil`."
  @spec get_revision(pos_integer(), binary()) :: Revision.t() | nil
  def get_revision(user_id, revision_id) do
    Repo.get_by(Revision, id: revision_id, user_id: user_id)
  end

  defp get(attrs, key) when is_map(attrs), do: Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
end
