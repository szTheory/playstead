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
  alias Playstead.Saves.{Branches, PendingUpload, Revision, RevisionParent, Save}
  alias Playstead.Sync.{ChangeJournal, Entry, SavePayload}

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

  # A synthetic marker `type` distinguishing an acknowledgment journal
  # entry from an ordinary `"revision"` save payload (D-17 additive
  # discipline: an unrecognized `type` is safe for an older client to
  # ignore). Never written to `save_revisions`/`save_revision_parents`
  # -- acknowledging must never make any head non-a-head, so it cannot
  # be represented as a DAG edge (any `save_revision_parents` row
  # necessarily disqualifies its `parent_revision_id` from `heads/2`).
  @fork_acknowledged_type "fork_acknowledged"

  @doc """
  Resolves a divergence on `save_line_id` by choosing `chosen_head_id`
  among its current heads (D-48). Appends one new resolution revision
  whose bytes are the chosen side's -- resolved through the CAS by
  digest, so it adds zero new blob bytes -- and one `RevisionParent`
  row per divergent head: exactly one with role `"chosen"`, every
  other with role `"acknowledged"`. Nothing is moved, rewritten, or
  deleted: every pre-existing head still exists afterward, simply no
  longer a head (each is now referenced as the new revision's parent,
  the same way any ordinary child revision retires its parent).

  Two devices independently resolving the same fork while offline both
  succeed when they arrive: each appends its own resolution revision
  naming the same original heads as parents, and the two resolution
  revisions coexist as siblings -- the retained-revision set is the
  union either way, with no compare-and-swap race.
  """
  @spec resolve_divergence(pos_integer(), map(), binary(), binary()) ::
          {:ok, Revision.t()} | {:error, term()}
  def resolve_divergence(user_id, device, save_line_id, chosen_head_id) do
    Repo.transaction(fn ->
      with {:ok, line} <- fetch_owned_line(user_id, save_line_id),
           heads <- Branches.heads(user_id, save_line_id),
           {:ok, chosen} <- find_head(heads, chosen_head_id),
           {:ok, revision} <- insert_resolution_revision(user_id, device, line, chosen),
           :ok <- insert_parent_edges(revision.id, heads, chosen_head_id),
           {:ok, _entry} <-
             ChangeJournal.append(user_id, :save, revision.id, SavePayload.build(revision, line)) do
        revision
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  "Keep both" (D-52): appends an acknowledgment marker naming
  `save_line_id`'s current heads, so this exact fork is never re-raised
  as needing a decision. Moves nothing, deletes nothing -- every head
  stays a head, forever if the user never resolves it (unresolved-
  forever is a supported, first-class outcome).
  """
  @spec acknowledge_divergence(pos_integer(), map(), binary()) ::
          {:ok, %{save_line_id: binary(), head_ids: [binary()]}} | {:error, term()}
  def acknowledge_divergence(user_id, _device, save_line_id) do
    with {:ok, _line} <- fetch_owned_line(user_id, save_line_id) do
      head_ids = user_id |> Branches.heads(save_line_id) |> Enum.map(& &1.id) |> Enum.sort()

      case ChangeJournal.append(user_id, :save, save_line_id, %{
             type: @fork_acknowledged_type,
             save_line_id: save_line_id,
             head_ids: head_ids
           }) do
        {:ok, _entry} -> {:ok, %{save_line_id: save_line_id, head_ids: head_ids}}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  Whether `save_line_id` has more than one head and the current head
  set has not been acknowledged (`acknowledge_divergence/3`) or
  already resolved down to one head. A fork acknowledged as keep-both
  is not reported as needing a decision, even though its heads remain
  heads (D-52).
  """
  @spec needs_divergence_decision?(pos_integer(), binary()) :: boolean()
  def needs_divergence_decision?(user_id, save_line_id) do
    heads = Branches.heads(user_id, save_line_id)
    length(heads) > 1 and not fork_acknowledged?(user_id, save_line_id, heads)
  end

  defp fetch_owned_line(user_id, save_line_id) do
    case Repo.get_by(Save, id: save_line_id, user_id: user_id) do
      nil -> {:error, :not_found}
      %Save{} = line -> {:ok, line}
    end
  end

  defp find_head(heads, chosen_head_id) do
    case Enum.find(heads, &(&1.id == chosen_head_id)) do
      nil ->
        {:error,
         {:validation_failed, "chosen_head_id is not a current head of this save line."}}

      %Revision{} = chosen ->
        {:ok, chosen}
    end
  end

  defp insert_resolution_revision(user_id, device, line, %Revision{} = chosen) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    changeset =
      Revision.create_changeset(%Revision{}, %{
        id: Ecto.UUID.generate(),
        user_id: user_id,
        save_line_id: line.id,
        parent_revision_id: chosen.id,
        blob_sha256: chosen.blob_sha256,
        size_bytes: chosen.size_bytes,
        origin_device_id: device.id,
        recorded_at: now,
        capture_method: "resolution",
        origin: "resolution"
      })

    Repo.insert(changeset)
  end

  # One `RevisionParent` row per divergent head (D-48) -- including the
  # chosen one, so the full N-way parentage is fully described by this
  # table alone, not split between it and the plain `parent_revision_id`
  # column. `on_conflict: :nothing` is defensive: `revision.id` is
  # always fresh here, but a replayed effect (outside the normal
  # idempotency-receipt guard) must never raise on a duplicate edge.
  defp insert_parent_edges(revision_id, heads, chosen_head_id) do
    Enum.reduce_while(heads, :ok, fn head, :ok ->
      role = if head.id == chosen_head_id, do: "chosen", else: "acknowledged"

      changeset =
        RevisionParent.create_changeset(%RevisionParent{}, %{
          revision_id: revision_id,
          parent_revision_id: head.id,
          role: role
        })

      case Repo.insert(changeset,
             on_conflict: :nothing,
             conflict_target: [:revision_id, :parent_revision_id]
           ) do
        {:ok, _row} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp fork_acknowledged?(user_id, save_line_id, heads) do
    head_ids = heads |> Enum.map(& &1.id) |> Enum.sort()

    query =
      from(e in Entry,
        where:
          e.user_id == ^user_id and e.entity_kind == "save" and e.entity_id == ^save_line_id and
            fragment("?->>'type' = ?", e.payload, ^@fork_acknowledged_type),
        order_by: [desc: e.seq],
        limit: 1
      )

    case Repo.one(query) do
      nil -> false
      %Entry{payload: payload} -> Enum.sort(Map.get(payload, "head_ids", [])) == head_ids
    end
  end

  defp get(attrs, key) when is_map(attrs), do: Map.get(attrs, key) || Map.get(attrs, String.to_atom(key))
end
