defmodule Playstead.Import do
  @moduledoc """
  The import pipeline context: turns one uploaded/read source file into
  a `Playstead.Import.SourceFile` row, a `Playstead.Blobs.Blob` (when
  new — already committed by `Playstead.Blobs.put_stream/3` before
  `import_single/3` is ever called), a minimal `Playstead.Catalogue.AssetSet`/
  `AssetMember`, and a `Playstead.Import.Receipt` — all in one
  transaction (D-11, D-24).

  Recognition is not wired in this plan: every set created here reports
  `system_source: nil` with no evidence rows; plan 02-03 fills in the
  providers behind the same seam.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs
  alias Playstead.Catalogue
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Formats
  alias Playstead.Import.{Outcome, Receipt, Session, SessionWorker, SourceFile}
  alias Playstead.Recognition
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  # D-15: a single-file import is a one-member set whose sole member is
  # the game's primary content — "primary" is in the frozen role
  # vocabulary `Playstead.Catalogue.AssetMember` validates against.
  @tracer_member_role "primary"

  @doc """
  Imports one already-committed blob as a source file for `user_id`,
  writing the source file, a minimal single-member asset set (or
  reusing the existing one when `member_fingerprint` already matches
  one of this user's sets), and the durable receipt — all in one
  transaction, plus one `catalogue` change-journal entry.

  `source_file_attrs` must include `:original_name`, `:origin`, and
  `:size_bytes`. `store_result` is the `{status, blob_meta}` tuple
  `Playstead.Blobs.put_stream/3` returned (`status` is `:stored` or
  `:existing`; `blob_meta` carries `:blob_id`, `:sha256`, `:size_bytes`).

  `opts[:format_bytes]` is the leading bytes of the file (plan 02-03's
  recognition seam): when provided, `Playstead.Formats.identify/2` and
  `Playstead.Recognition.recognize_and_record/3` run against them and
  their result informs the asset set's system assignment, display
  title, and (for `:patched`/`:possible_variant`/recognition-detected
  `:alias`) the receipt outcome. Omitted, the pipeline behaves exactly
  as plan 02-02 left it — no format identification and no recognition
  evidence row.
  """
  @spec import_single(pos_integer(), map(), {:stored | :existing, map()}, keyword()) ::
          {:ok, Receipt.t()} | {:error, term()}
  def import_single(user_id, source_file_attrs, store_result, opts \\ [])

  def import_single(user_id, source_file_attrs, {_status, blob_meta}, opts) do
    format_bytes = Keyword.get(opts, :format_bytes)
    format_result = identify_format(format_bytes, source_file_attrs[:original_name])

    Repo.transaction(fn ->
      with {:ok, source_file} <- insert_source_file(user_id, source_file_attrs, blob_meta),
           recognition_facts <- %{
             blob_id: blob_meta.blob_id,
             sha256: blob_meta.sha256,
             bytes: format_bytes,
             exclude_source_file_id: source_file.id
           },
           {recognition_result, _evidence} <-
             Recognition.recognize_and_record(user_id, recognition_facts, format_result),
           outcome <-
             determine_outcome(
               user_id,
               blob_meta.blob_id,
               source_file_attrs[:origin],
               recognition_result
             ),
           {:ok, asset_set} <-
             find_or_create_asset_set(user_id, blob_meta, source_file_attrs, format_result),
           {:ok, receipt} <- insert_receipt(user_id, source_file, asset_set, blob_meta, outcome),
           {:ok, _entry} <- ChangeJournal.append(user_id, :catalogue, receipt.id, %{}) do
        receipt
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp identify_format(nil, _filename), do: nil
  defp identify_format(bytes, filename), do: Formats.identify(bytes, filename)

  defp insert_source_file(user_id, attrs, blob_meta) do
    attrs =
      attrs
      |> Map.take([:original_name, :origin, :relative_path, :size_bytes, :mtime])
      |> Map.merge(%{user_id: user_id, blob_id: blob_meta.blob_id})

    Repo.insert(SourceFile.create_changeset(%SourceFile{}, attrs))
  end

  # D-13: duplicate status is evaluated within the calling user's own
  # records only. A `source_files` row referencing this blob owned by
  # a *different* user must never change this user's outcome.
  #
  # `recognition_result` (D-17, plan 02-03) refines the outcome for the
  # cases the byte-duplicate check alone cannot see: a patch file, or a
  # possible-variant/alias header match. Absent format bytes (plan
  # 02-02 callers), `recognition_result` reports `:no_reference_installed`
  # and this falls through to the original duplicate-count logic
  # unchanged.
  defp determine_outcome(user_id, blob_id, origin, recognition_result) do
    count =
      from(sf in SourceFile, where: sf.user_id == ^user_id and sf.blob_id == ^blob_id)
      |> Repo.aggregate(:count)

    cond do
      count > 1 and origin == "reimport" -> :alias
      count > 1 -> :exact_duplicate
      recognition_result && recognition_result.status == :patched -> :patched
      recognition_result && recognition_result.status == :possible_variant -> :variant
      recognition_result && recognition_result.status == :alias -> :alias
      true -> :new_asset
    end
  end

  # Uses Repo.insert_all/3 with on_conflict: :nothing rather than
  # Repo.insert/2 + catching a unique_constraint error: a failed
  # Repo.insert on a *composite* unique constraint still leaves the
  # ambient Postgres transaction aborted for any query that follows it
  # in the same transaction (this function already runs inside
  # import_single/3's transaction) — insert_all with on_conflict never
  # raises, so there is nothing to recover from. `conflict_target`
  # names the exact index; the affected-row count (0 vs 1) is how we
  # learn whether this call created the set or found an existing one.
  defp find_or_create_asset_set(user_id, blob_meta, source_file_attrs, format_result) do
    fingerprint =
      Catalogue.member_fingerprint([%{role: @tracer_member_role, sha256: blob_meta.sha256}])

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {display_title, title_source, _tags} =
      Catalogue.display_title(source_file_attrs[:original_name])

    {system_id, system_source} = resolve_system(source_file_attrs[:original_name], format_result)

    attrs = %{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      member_fingerprint: fingerprint,
      display_title: display_title,
      title_source: to_string(title_source),
      system_id: system_id,
      system_source: system_source,
      status: "active",
      inserted_at: now,
      updated_at: now
    }

    {count, _} =
      Repo.insert_all(AssetSet, [attrs],
        on_conflict: :nothing,
        conflict_target: [:user_id, :member_fingerprint]
      )

    asset_set = Repo.get_by!(AssetSet, user_id: user_id, member_fingerprint: fingerprint)

    if count == 1 do
      insert_tracer_member(asset_set, blob_meta, source_file_attrs)
    end

    {:ok, asset_set}
  end

  defp resolve_system(_filename, nil), do: {nil, nil}

  defp resolve_system(filename, format_result) do
    extension_guess = Catalogue.extension_guess(filename)

    case Catalogue.assign_system(extension_guess, format_result, nil) do
      {:ok, system_id, source} -> {to_string(system_id), to_string(source)}
      {:confirmation_needed, _detail} -> {nil, nil}
    end
  end

  defp insert_tracer_member(asset_set, blob_meta, source_file_attrs) do
    Repo.insert!(
      AssetMember.create_changeset(%AssetMember{}, %{
        asset_set_id: asset_set.id,
        ordinal: 0,
        role: @tracer_member_role,
        required: true,
        blob_id: blob_meta.blob_id,
        declared_name: source_file_attrs[:original_name]
      })
    )
  end

  defp insert_receipt(user_id, source_file, asset_set, blob_meta, outcome, reason \\ nil) do
    Repo.insert(
      Receipt.create_changeset(%Receipt{}, %{
        user_id: user_id,
        source_file_id: source_file.id,
        blob_id: blob_meta.blob_id,
        asset_set_id: asset_set && asset_set.id,
        outcome: to_string(outcome),
        reason: reason,
        sha256: blob_meta.sha256,
        size_bytes: blob_meta.size_bytes
      })
    )
  end

  @doc """
  Adopts a browser upload's already-hashed, already-written temporary
  file into the blob store and imports it exactly like any other
  already-committed blob (D-01a). `writer_meta` is the map
  `Playstead.Import.HashingWriter.meta/1` returned on a successful
  close: `%{path: tmp_path, digests: digest_map}`. Reads the source
  bytes' declared origin as `"browser"`, distinguishing it from the
  API path's `"api_upload"` and the reimport path's `"reimport"`.
  """
  @spec import_upload(pos_integer(), String.t(), map(), keyword()) ::
          {:ok, Receipt.t()} | {:error, term()}
  def import_upload(user_id, original_name, writer_meta, opts \\ []) do
    with {:ok, status, blob_meta} <-
           Blobs.adopt_temp_file(writer_meta.path, writer_meta.digests) do
      source_file_attrs = %{
        original_name: original_name,
        origin: "browser",
        size_bytes: writer_meta.digests.size_bytes
      }

      import_single(user_id, source_file_attrs, {status, blob_meta}, opts)
    end
  end

  @doc """
  Imports a PSX CUE descriptor and any of its referenced binary
  companions submitted alongside it, as one ordered multi-file asset
  set (IMPT-04, D-15). `track_names` is the parsed CUE track table
  (`Playstead.Formats.Validators.PsxCue`'s `evidence.files`, in
  declared order); `companions` maps a declared name present in
  `track_names` to the `{status, blob_meta}` `Playstead.Blobs.put_stream/3`
  returned for it. A name in `track_names` absent from `companions`
  becomes a required member with no blob and the whole set's receipt
  reports `:incomplete_set`, naming the missing member.

  Two concurrent imports of the identical descriptor (same fingerprint
  because both compute it over the same known bytes and the same
  still-missing members) converge on one asset set via the same
  `on_conflict` pattern `import_single/4` uses.
  """
  @spec import_descriptor_set(pos_integer(), map(), {:stored | :existing, map()}, [String.t()], %{
          optional(String.t()) => {:stored | :existing, map()}
        }) :: {:ok, %{asset_set: AssetSet.t(), receipts: [Receipt.t()]}} | {:error, term()}
  def import_descriptor_set(
        user_id,
        descriptor_attrs,
        {_status, descriptor_meta},
        track_names,
        companions \\ %{}
      ) do
    Repo.transaction(fn ->
      with {:ok, descriptor_source_file} <-
             insert_source_file(user_id, descriptor_attrs, descriptor_meta),
           companion_files <- insert_companion_source_files(user_id, companions),
           asset_set <-
             find_or_create_descriptor_set(
               user_id,
               descriptor_attrs,
               descriptor_meta,
               track_names,
               companion_files
             ),
           missing <- Enum.reject(track_names, &Map.has_key?(companion_files, &1)),
           outcome <- if(missing == [], do: :new_asset, else: :incomplete_set),
           reason <- if(missing == [], do: nil, else: "missing: " <> Enum.join(missing, ", ")),
           {:ok, descriptor_receipt} <-
             insert_receipt(
               user_id,
               descriptor_source_file,
               asset_set,
               descriptor_meta,
               outcome,
               reason
             ),
           {:ok, _entry} <- ChangeJournal.append(user_id, :catalogue, asset_set.id, %{}),
           {:ok, companion_receipts} <-
             insert_companion_receipts(user_id, asset_set, companion_files) do
        %{asset_set: asset_set, receipts: [descriptor_receipt | companion_receipts]}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_companion_source_files(user_id, companions) do
    Map.new(companions, fn {name, {_status, meta}} ->
      attrs = %{original_name: name, origin: "upload", size_bytes: meta.size_bytes}
      {:ok, source_file} = insert_source_file(user_id, attrs, meta)
      {name, {source_file, meta}}
    end)
  end

  defp insert_companion_receipts(user_id, asset_set, companion_files) do
    receipts =
      Enum.map(companion_files, fn {_name, {source_file, meta}} ->
        {:ok, receipt} = insert_receipt(user_id, source_file, asset_set, meta, :new_asset)
        receipt
      end)

    {:ok, receipts}
  end

  defp find_or_create_descriptor_set(
         user_id,
         descriptor_attrs,
         descriptor_meta,
         track_names,
         companion_files
       ) do
    fingerprint_members =
      [%{role: "descriptor", sha256: descriptor_meta.sha256}] ++
        Enum.map(track_names, fn name ->
          case Map.get(companion_files, name) do
            {_source_file, meta} -> %{role: "track", sha256: meta.sha256}
            nil -> %{role: "track", sha256: nil}
          end
        end)

    fingerprint = Catalogue.member_fingerprint(fingerprint_members)
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {display_title, title_source, _tags} =
      Catalogue.display_title(descriptor_attrs[:original_name])

    status = if track_names -- Map.keys(companion_files) == [], do: "complete", else: "incomplete"

    attrs = %{
      id: Ecto.UUID.generate(),
      user_id: user_id,
      member_fingerprint: fingerprint,
      display_title: display_title,
      title_source: to_string(title_source),
      system_id: "psx",
      system_source: "extension",
      status: status,
      inserted_at: now,
      updated_at: now
    }

    {count, _} =
      Repo.insert_all(AssetSet, [attrs],
        on_conflict: :nothing,
        conflict_target: [:user_id, :member_fingerprint]
      )

    asset_set = Repo.get_by!(AssetSet, user_id: user_id, member_fingerprint: fingerprint)

    if count == 1 do
      insert_descriptor_members(
        asset_set,
        descriptor_attrs,
        descriptor_meta,
        track_names,
        companion_files
      )
    end

    asset_set
  end

  defp insert_descriptor_members(
         asset_set,
         descriptor_attrs,
         descriptor_meta,
         track_names,
         companion_files
       ) do
    Repo.insert!(
      AssetMember.create_changeset(%AssetMember{}, %{
        asset_set_id: asset_set.id,
        ordinal: 0,
        role: "descriptor",
        required: true,
        blob_id: descriptor_meta.blob_id,
        declared_name: descriptor_attrs[:original_name]
      })
    )

    track_names
    |> Enum.with_index(1)
    |> Enum.each(fn {name, ordinal} ->
      blob_id =
        case Map.get(companion_files, name) do
          {_source_file, meta} -> meta.blob_id
          nil -> nil
        end

      Repo.insert!(
        AssetMember.create_changeset(%AssetMember{}, %{
          asset_set_id: asset_set.id,
          ordinal: ordinal,
          role: "track",
          required: true,
          blob_id: blob_id,
          declared_name: name
        })
      )
    end)
  end

  @doc """
  Attaches a previously-missing companion to whichever of `user_id`'s
  incomplete asset sets has a required member named `declared_name`
  with no blob yet (D-15). Uses a guarded `UPDATE ... WHERE blob_id IS
  NULL` as its collision authority rather than a read-then-write check,
  so two concurrent attach attempts for the same member converge on
  one row: the loser's guarded update affects zero rows, and if the
  bytes it was attaching are the same ones the winner already attached,
  it reports success without creating a second row. Recomputes the
  set's member fingerprint and status inside the same transaction.
  """
  @spec attach_companion(pos_integer(), String.t(), map(), {:stored | :existing, map()}) ::
          {:ok, Receipt.t()} | {:error, term()}
  def attach_companion(user_id, declared_name, source_file_attrs, {_status, meta}) do
    Repo.transaction(fn ->
      with {:ok, source_file} <- insert_source_file(user_id, source_file_attrs, meta),
           {:ok, member} <- find_and_attach_member(user_id, declared_name, meta),
           asset_set <- Repo.get!(AssetSet, member.asset_set_id),
           {:ok, updated_set} <- Catalogue.recompute_member_state(asset_set),
           {:ok, receipt} <- insert_receipt(user_id, source_file, updated_set, meta, :new_asset),
           {:ok, _entry} <- ChangeJournal.append(user_id, :catalogue, updated_set.id, %{}) do
        receipt
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp find_and_attach_member(user_id, declared_name, meta) do
    query =
      from(m in AssetMember,
        join: s in AssetSet,
        on: s.id == m.asset_set_id,
        where: s.user_id == ^user_id and m.declared_name == ^declared_name and is_nil(m.blob_id),
        select: m
      )

    case Repo.one(query) do
      nil ->
        {:error, :no_matching_incomplete_member}

      member ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)

        {affected, _} =
          Repo.update_all(
            from(m in AssetMember, where: m.id == ^member.id and is_nil(m.blob_id)),
            set: [blob_id: meta.blob_id, updated_at: now]
          )

        if affected == 1 do
          {:ok, %{member | blob_id: meta.blob_id}}
        else
          current = Repo.get!(AssetMember, member.id)

          if current.blob_id == meta.blob_id do
            {:ok, current}
          else
            {:error, :already_attached_different_blob}
          end
        end
    end
  end

  @doc """
  Lists `user_id`'s import receipts, newest first (the console's
  receipt list, D-24/D-25). Every receipt read back here is exactly
  what was written at import time — the receipt's own `outcome` never
  changes even if the asset's current recognition state later improves
  (D-25's terminal-outcome guarantee).
  """
  @spec list_receipts(pos_integer(), keyword()) :: [Receipt.t()]
  def list_receipts(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    from(r in Receipt,
      where: r.user_id == ^user_id,
      order_by: [desc: r.inserted_at],
      limit: ^limit,
      preload: [:source_file, :asset_set]
    )
    |> Repo.all()
  end

  @doc """
  Whether `user_id` already holds content matching `sha256`/`size_bytes`
  (D-10's precheck, so the Mac client can avoid sending bytes the
  server already has). Scoped strictly to the calling user — a global
  "exists" answer would let one user probe another's library by hash
  (D-13).
  """
  @spec present_for_user?(pos_integer(), String.t(), non_neg_integer()) :: boolean()
  def present_for_user?(user_id, sha256, size_bytes) do
    from(sf in SourceFile,
      join: b in assoc(sf, :blob),
      where: sf.user_id == ^user_id and b.sha256 == ^sha256 and b.size_bytes == ^size_bytes
    )
    |> Repo.exists?()
  end

  @doc "The frozen outcome-code module, re-exported for callers that only need `Playstead.Import`."
  defdelegate outcome_codes(), to: Outcome, as: :all

  # --- session import (plan 02-05, D-05, D-06, D-08) --------------------

  @doc """
  Completes a source-file row already inserted at staging time (task 1)
  — the session worker's per-file commit path. Unlike `import_single/4`,
  no new `source_files` row is created; the existing staged row is
  updated in place with `store_result`'s blob id, in the same
  transaction as the asset-set/receipt/change-journal writes.
  """
  @spec complete_staged_file(pos_integer(), SourceFile.t(), {:stored | :existing, map()}, keyword()) ::
          {:ok, Receipt.t()} | {:error, term()}
  def complete_staged_file(user_id, %SourceFile{} = source_file, {_status, blob_meta}, opts \\ []) do
    format_bytes = Keyword.get(opts, :format_bytes)
    format_result = identify_format(format_bytes, source_file.original_name)

    Repo.transaction(fn ->
      with {:ok, source_file} <-
             Repo.update(SourceFile.complete_changeset(source_file, blob_meta.blob_id)),
           recognition_facts <- %{
             blob_id: blob_meta.blob_id,
             sha256: blob_meta.sha256,
             bytes: format_bytes,
             exclude_source_file_id: source_file.id
           },
           {recognition_result, _evidence} <-
             Recognition.recognize_and_record(user_id, recognition_facts, format_result),
           outcome <-
             determine_outcome(user_id, blob_meta.blob_id, source_file.origin, recognition_result),
           {:ok, asset_set} <-
             find_or_create_asset_set(
               user_id,
               blob_meta,
               %{original_name: source_file.original_name},
               format_result
             ),
           {:ok, receipt} <- insert_receipt(user_id, source_file, asset_set, blob_meta, outcome),
           {:ok, _entry} <- ChangeJournal.append(user_id, :catalogue, receipt.id, %{}) do
        receipt
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Records a session file that could not be safely copied — a disk-full
  condition (the whole session pauses rather than continuing into
  thousands of failures) or an I/O error reading the source — as a
  `:failed_safely` receipt, and marks the row `"failed"`.
  """
  @spec record_failed_file(pos_integer(), SourceFile.t(), String.t()) ::
          {:ok, Receipt.t()} | {:error, term()}
  def record_failed_file(user_id, %SourceFile{} = source_file, reason) do
    Repo.transaction(fn ->
      with {:ok, source_file} <-
             Repo.update(SourceFile.staging_state_changeset(source_file, "failed", reason)),
           {:ok, receipt} <-
             insert_receipt(
               user_id,
               source_file,
               nil,
               %{blob_id: nil, sha256: nil, size_bytes: source_file.size_bytes},
               :failed_safely,
               reason
             ) do
        receipt
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Fetches a session strictly scoped to its owning user (D-13/T-02-38), or `nil`."
  @spec get_owned_session(pos_integer(), String.t()) :: Session.t() | nil
  def get_owned_session(user_id, session_id) do
    Repo.get_by(Session, id: session_id, user_id: user_id)
  end

  @doc "Starts (or restarts) processing a staged session — enqueues the unique per-session job."
  @spec start_session(pos_integer(), String.t()) :: {:ok, Oban.Job.t()} | {:error, :not_found}
  def start_session(user_id, session_id) do
    case get_owned_session(user_id, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        session |> Session.control_changeset("run") |> Repo.update!()
        SessionWorker.enqueue(session_id, "run")
    end
  end

  @doc """
  Requests a cooperative pause (D-06). The control decision lives on
  the session row and is re-read by the worker between files — it is
  never the global Oban queue pause, which would freeze every other
  session sharing the queue.
  """
  @spec pause_session(pos_integer(), String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def pause_session(user_id, session_id) do
    case get_owned_session(user_id, session_id) do
      nil -> {:error, :not_found}
      session -> session |> Session.control_changeset("pause") |> Repo.update()
    end
  end

  @doc "Resumes a paused session by re-enqueuing the same unique per-session job."
  @spec resume_session(pos_integer(), String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def resume_session(user_id, session_id) do
    case get_owned_session(user_id, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        {:ok, session} = session |> Session.control_changeset("run") |> Repo.update()
        SessionWorker.enqueue(session_id, "run")
        {:ok, session}
    end
  end

  @doc """
  Re-queues only the rows whose last attempt failed and are still under
  the bounded retry limit, then re-enqueues the session job.
  """
  @spec retry_failed(pos_integer(), String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def retry_failed(user_id, session_id) do
    case get_owned_session(user_id, session_id) do
      nil ->
        {:error, :not_found}

      session ->
        requeue_failed_rows(session_id)
        {:ok, session} = session |> Session.control_changeset("run") |> Repo.update()
        SessionWorker.enqueue(session_id, "run")
        {:ok, session}
    end
  end

  defp requeue_failed_rows(session_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    from(sf in SourceFile,
      where:
        sf.import_session_id == ^session_id and sf.staging_state == "failed" and
          sf.attempt_count < 3
    )
    |> Repo.update_all(set: [staging_state: "pending", updated_at: now])
  end

  @doc """
  Cancels a session (D-07): keeps every copy already made, marks the
  remaining rows skipped, and records an audit entry. Applied
  immediately when no job is currently running; otherwise requests the
  cooperative control the running worker honours between files.
  """
  @spec cancel_session(pos_integer(), String.t()) :: {:ok, Session.t()} | {:error, :not_found}
  def cancel_session(user_id, session_id) do
    case get_owned_session(user_id, session_id) do
      nil ->
        {:error, :not_found}

      %Session{state: "running"} = session ->
        session |> Session.control_changeset("cancel") |> Repo.update()

      session ->
        SessionWorker.apply_cancel(session)
    end
  end

  @doc "The session's current requested control value."
  @spec control(Session.t()) :: String.t()
  def control(%Session{requested_control: control}), do: control

  @doc "Lists `user_id`'s import sessions, most recently updated first."
  @spec list_sessions(pos_integer()) :: [Session.t()]
  def list_sessions(user_id) do
    from(s in Session, where: s.user_id == ^user_id, order_by: [desc: s.updated_at])
    |> Repo.all()
  end

  @doc """
  Cursor-paginated receipts for one session (D-13/T-02-38), ordered by
  insertion timestamp with the row id as a deterministic tiebreak so
  two receipts written in the same microsecond still have exactly one
  correct order.
  """
  @spec list_session_receipts(pos_integer(), String.t(), keyword()) :: %{
          entries: [Receipt.t()],
          next_cursor: String.t() | nil
        }
  def list_session_receipts(user_id, session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    after_cursor = Keyword.get(opts, :after_cursor)

    base =
      from(r in Receipt,
        join: sf in SourceFile,
        on: sf.id == r.source_file_id,
        where: r.user_id == ^user_id and sf.import_session_id == ^session_id,
        order_by: [asc: r.inserted_at, asc: r.id],
        limit: ^(limit + 1)
      )

    query =
      case decode_receipt_cursor(after_cursor) do
        {:ok, {inserted_at, id}} ->
          from(r in base,
            where: r.inserted_at > ^inserted_at or (r.inserted_at == ^inserted_at and r.id > ^id)
          )

        :error ->
          base
      end

    rows = Repo.all(query)
    {page, has_more} = if length(rows) > limit, do: {Enum.take(rows, limit), true}, else: {rows, false}

    next_cursor =
      if has_more do
        last = List.last(page)
        encode_receipt_cursor(last.inserted_at, last.id)
      else
        nil
      end

    %{entries: page, next_cursor: next_cursor}
  end

  defp encode_receipt_cursor(inserted_at, id) do
    Base.url_encode64("#{DateTime.to_iso8601(inserted_at)}|#{id}", padding: false)
  end

  defp decode_receipt_cursor(nil), do: :error

  defp decode_receipt_cursor(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [iso, id] <- String.split(decoded, "|", parts: 2),
         {:ok, inserted_at, _offset} <- DateTime.from_iso8601(iso) do
      {:ok, {inserted_at, id}}
    else
      _ -> :error
    end
  end

  @doc """
  Reads a bag directory's `manifest-sha256.txt` and imports every listed
  payload file back through `import_single/3` (D-37). Identity follows
  the member fingerprint: when the reimported member set matches an
  existing set for this user, `determine_outcome/3` reports `:alias`
  (new `source_file` rows only, zero new blobs, zero new asset sets);
  otherwise a fresh set is created, restored with the same member
  role/ordinal/required shape `find_or_create_asset_set/3` always
  produces for this tracer's single-member sets.
  """
  @spec reimport_folder(pos_integer(), String.t()) :: {:ok, [Receipt.t()]} | {:error, term()}
  def reimport_folder(user_id, bag_dir) do
    manifest_path = Path.join(bag_dir, "manifest-sha256.txt")

    case File.read(manifest_path) do
      {:ok, content} -> reimport_entries(user_id, bag_dir, parse_manifest(content))
      {:error, reason} -> {:error, reason}
    end
  end

  defp reimport_entries(user_id, bag_dir, entries) do
    result =
      Enum.reduce_while(entries, {:ok, []}, fn %{sha256: sha256, relative: relative},
                                               {:ok, acc} ->
        payload_path = Path.join(bag_dir, relative)

        case import_bag_member(user_id, payload_path, sha256) do
          {:ok, receipt} -> {:cont, {:ok, [receipt | acc]}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)

    case result do
      {:ok, receipts} -> {:ok, Enum.reverse(receipts)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp import_bag_member(user_id, payload_path, expected_sha256) do
    size = File.stat!(payload_path).size
    stream = File.stream!(payload_path, [], 1_048_576)

    with {:ok, status, meta} <-
           Playstead.Blobs.put_stream(stream, size, expected_sha256: expected_sha256) do
      import_single(
        user_id,
        %{
          original_name: Path.basename(payload_path),
          origin: "reimport",
          size_bytes: meta.size_bytes
        },
        {status, meta}
      )
    end
  end

  defp parse_manifest(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [sha256, relative] = String.split(line, "  ", parts: 2)
      %{sha256: sha256, relative: relative}
    end)
  end
end
