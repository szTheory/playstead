defmodule Playstead.Catalogue do
  @moduledoc """
  The user-scoped logical catalogue context: `Playstead.Catalogue.AssetSet`
  and `Playstead.Catalogue.AssetMember`. `member_fingerprint/1` is the
  natural key that makes "no duplicate logical record" a database
  guarantee via the unique index on the user/fingerprint pair (D-37).

  Also owns display-title derivation (D-22) and system assignment with
  recorded provenance (D-19).
  """

  import Ecto.Query, warn: false

  alias Playstead.Accounts.Scope
  alias Playstead.AuditLog
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Formats.SystemId
  alias Playstead.Import.Receipt
  alias Playstead.Recognition.Evidence
  alias Playstead.Recognition.NoIntroName
  alias Playstead.Repo

  # D-22: control, bidirectional-override, and zero-width characters —
  # stripped from every display title regardless of source.
  @unsafe_chars ~r/[\x00-\x1F\x7F\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}-\x{2064}\x{FEFF}]/u
  @max_title_length 200

  @extension_systems %{
    ".gba" => :gba,
    ".gb" => :gb,
    ".gbc" => :gbc,
    ".nes" => :nes,
    ".sfc" => :snes,
    ".smc" => :snes,
    ".md" => :md,
    ".gen" => :md,
    ".cue" => :psx
  }

  @doc """
  D-19's precedence for the initial extension-based guess: a
  recognized ROM extension maps to its system, anything else (unknown
  extension, no extension) returns `nil` — an honest "no guess" rather
  than a default to `unknown`.
  """
  @spec extension_guess(String.t() | nil) :: atom() | nil
  def extension_guess(nil), do: nil

  def extension_guess(filename) do
    filename |> Path.extname() |> String.downcase() |> then(&Map.get(@extension_systems, &1))
  end

  @doc """
  D-19's full precedence: an extension guess is upgraded or
  contradicted by a header confirmation, and a user override beats
  both. Returns `{:ok, system_id, source}` when a single answer is
  reachable, or `{:confirmation_needed, %{extension: _, header: _}}`
  when the extension and the header disagree and no user override is
  present — a contradiction never silently picks a winner.
  """
  @spec assign_system(atom() | nil, {atom(), atom(), map()} | nil, atom() | nil) ::
          {:ok, atom(), :extension | :header | :user}
          | {:confirmation_needed, %{extension: atom(), header: atom()}}
  def assign_system(_extension_guess, _format_result, user_override)
      when not is_nil(user_override) do
    {:ok, user_override, :user}
  end

  def assign_system(extension_guess, {header_system, _tier, _evidence}, nil)
      when header_system != :unknown do
    cond do
      is_nil(extension_guess) -> {:ok, header_system, :header}
      extension_guess == header_system -> {:ok, header_system, :header}
      true -> {:confirmation_needed, %{extension: extension_guess, header: header_system}}
    end
  end

  def assign_system(extension_guess, _format_result, nil) when not is_nil(extension_guess) do
    {:ok, extension_guess, :extension}
  end

  def assign_system(nil, _format_result, nil), do: {:ok, :unknown, :extension}

  @doc """
  Writes a user-supplied system correction — always wins over any
  machine guess (D-19) — and records an audit entry. Never touches the
  append-only `recognitions` evidence table.
  """
  @spec override_system(AssetSet.t(), atom() | String.t(), pos_integer()) ::
          {:ok, AssetSet.t()} | {:error, term()}
  def override_system(%AssetSet{} = asset_set, system_id, user_id) when not is_nil(system_id) do
    system_id_str = to_string(system_id)

    unless SystemId.valid?(system_id_str) do
      raise ArgumentError, "not a registered system identifier: #{inspect(system_id)}"
    end

    Repo.transaction(fn ->
      changeset =
        Ecto.Changeset.change(asset_set, system_id: system_id_str, system_source: "user")

      with {:ok, updated} <- Repo.update(changeset),
           {:ok, _entry} <-
             AuditLog.record(user_id, :asset_set_system_overridden, %{
               subject: asset_set.id,
               system_id: system_id_str
             }) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  D-22's display-title derivation: the parsed No-Intro release title
  when `original_name` parses, otherwise the sanitized filename stem.
  A cartridge header title (if any) is never consulted here — it stays
  in recognition evidence only. Returns
  `{display_title, title_source, tags}`.
  """
  @spec display_title(String.t()) :: {String.t(), :filename_parsed | :filename_stem, map()}
  def display_title(original_name) when is_binary(original_name) do
    case NoIntroName.parse(original_name) do
      {:ok, %{title: title, tags: tags}} -> {sanitize_title(title), :filename_parsed, tags}
      :no_match -> {sanitize_title(filename_stem(original_name)), :filename_stem, %{}}
    end
  end

  @doc "The filename with its extension removed."
  @spec filename_stem(String.t()) :: String.t()
  def filename_stem(original_name) do
    original_name |> Path.basename() |> Path.rootname()
  end

  @doc """
  Normalizes `title` to NFC, strips control, bidirectional-override,
  and zero-width characters, and caps it at 200 code points (D-22).
  Rendering escaping is the caller's responsibility (framework HEEx
  escaping) — this function only shapes the stored value.
  """
  @spec sanitize_title(String.t()) :: String.t()
  def sanitize_title(title) when is_binary(title) do
    title
    |> String.normalize(:nfc)
    |> String.replace(@unsafe_chars, "")
    |> String.slice(0, @max_title_length)
  end

  @doc """
  D-37's natural key: the SHA-256 over the canonical sorted list of
  role-and-hash member pairs. Sorting makes the value independent of
  member insertion order; only `role` and `sha256` participate, so the
  vocabulary of roles and statuses can grow later without changing any
  existing fingerprint.
  """
  @spec member_fingerprint([%{role: String.t(), sha256: String.t() | nil}]) :: String.t()
  def member_fingerprint(members) when is_list(members) do
    canonical =
      members
      |> Enum.map(fn %{role: role, sha256: sha256} -> "#{role}:#{sha256}" end)
      |> Enum.sort()
      |> Enum.join("|")

    :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
  end

  @doc """
  Recomputes `asset_set`'s `member_fingerprint` and `status` from its
  current members (D-15, D-37) — called inside the same transaction as
  any membership change, so the fingerprint the reimport identity
  depends on is never stale. A set is `"complete"` when every required
  member carries a blob, `"incomplete"` otherwise.
  """
  @spec recompute_member_state(AssetSet.t()) :: {:ok, AssetSet.t()} | {:error, term()}
  def recompute_member_state(%AssetSet{} = asset_set) do
    rows =
      from(m in Playstead.Catalogue.AssetMember,
        left_join: b in Playstead.Blobs.Blob,
        on: b.id == m.blob_id,
        where: m.asset_set_id == ^asset_set.id,
        select: %{role: m.role, sha256: b.sha256, required: m.required}
      )
      |> Repo.all()

    fingerprint = member_fingerprint(Enum.map(rows, &Map.take(&1, [:role, :sha256])))

    status =
      if Enum.all?(rows, &(not &1.required or not is_nil(&1.sha256))),
        do: "complete",
        else: "incomplete"

    asset_set
    |> Ecto.Changeset.change(member_fingerprint: fingerprint, status: status)
    |> Repo.update()
  end

  @doc """
  Lists `scope`'s asset sets (D-26), newest first, excluding excluded
  (tombstoned) sets, each paired with its quiet `:identified` /
  `:unidentified` badge state — never an error styling for an
  unidentified asset, since a first adopter with hundreds of
  unrecognised files should see their library, not a wall of chores.
  Every query is scoped through `scope.user.id`; there is no code path
  here that can see, count, or hint at another user's holdings, even
  though the underlying blobs may be physically shared (D-13).
  """
  @spec list_assets(Scope.t(), keyword()) :: [
          %{asset_set: AssetSet.t(), identification_state: atom()}
        ]
  def list_assets(%Scope{user: user}, _opts \\ []) do
    from(a in AssetSet,
      where: a.user_id == ^user.id and is_nil(a.excluded_at),
      order_by: [desc: a.inserted_at],
      preload: [asset_members: :blob]
    )
    |> Repo.all()
    |> Enum.map(fn set -> %{asset_set: set, identification_state: identification_state(set)} end)
  end

  @doc """
  The IMPT-02 evidence detail for one of `scope`'s asset sets: the
  member list (with blobs preloaded so hash/size are directly
  readable), the latest recognition evidence per member blob (header
  fields are only ever shown for a `:signature`-tier match), and every
  import receipt this set's members produced — including a receipt
  whose asset has since been re-identified, so the outcome recorded at
  import is never silently rewritten by later evidence (D-25).

  Scoped strictly through `scope.user.id`: `{:error, :not_found}` for
  an id that does not belong to this user, indistinguishable from an
  id that does not exist at all.
  """
  @spec get_asset_detail(Scope.t(), Ecto.UUID.t()) :: {:ok, map()} | {:error, :not_found}
  def get_asset_detail(%Scope{user: user}, asset_set_id) do
    case Repo.get_by(AssetSet, id: asset_set_id, user_id: user.id) do
      nil ->
        {:error, :not_found}

      %AssetSet{} = asset_set ->
        asset_set = Repo.preload(asset_set, asset_members: :blob)

        blob_ids =
          asset_set.asset_members |> Enum.map(& &1.blob_id) |> Enum.reject(&is_nil/1)

        receipts =
          from(r in Receipt,
            where: r.asset_set_id == ^asset_set.id and r.user_id == ^user.id,
            order_by: [asc: r.inserted_at],
            preload: [:source_file]
          )
          |> Repo.all()

        {:ok,
         %{
           asset_set: asset_set,
           identification_state: identification_state(asset_set),
           evidence_by_blob: latest_evidence_by_blob(blob_ids),
           receipts: receipts
         }}
    end
  end

  # Quiet by design (D-26): no evidence at all, or every recorded
  # evidence row for this set's blobs reports `no_reference_installed`,
  # is `:unidentified` — never an error state, just a badge.
  defp identification_state(%AssetSet{asset_members: members}) when is_list(members) do
    blob_ids = members |> Enum.map(& &1.blob_id) |> Enum.reject(&is_nil/1)

    if blob_ids == [] do
      :unidentified
    else
      statuses =
        from(e in Evidence, where: e.blob_id in ^blob_ids, select: e.status) |> Repo.all()

      if Enum.any?(statuses, &(&1 != "no_reference_installed")) do
        :identified
      else
        :unidentified
      end
    end
  end

  defp identification_state(%AssetSet{}), do: :unidentified

  defp latest_evidence_by_blob([]), do: %{}

  defp latest_evidence_by_blob(blob_ids) do
    from(e in Evidence, where: e.blob_id in ^blob_ids, order_by: [desc: e.inserted_at])
    |> Repo.all()
    |> Enum.reduce(%{}, fn evidence, acc -> Map.put_new(acc, evidence.blob_id, evidence) end)
  end

  @doc """
  Excludes `asset_set` (D-27): sets `excluded_at`, then appends a
  `catalogue` tombstone entry inside the same transaction. Bytes are
  never touched — exclusion is a visibility change only.
  """
  @spec exclude_set(AssetSet.t(), pos_integer()) :: {:ok, AssetSet.t()} | {:error, term()}
  def exclude_set(%AssetSet{} = asset_set, user_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      with {:ok, updated} <-
             asset_set |> Ecto.Changeset.change(excluded_at: now) |> Repo.update(),
           {:ok, _entry} <-
             Playstead.Sync.ChangeJournal.tombstone(user_id, :catalogue, updated.id) do
        updated
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
