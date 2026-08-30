defmodule Playstead.Recognition do
  @moduledoc """
  The recognition context: dispatches to the configured
  `Playstead.Recognition.Provider` (the built-in
  `Playstead.Recognition.HeaderEvidence` in this phase) and records its
  result as an append-only `Playstead.Recognition.Evidence` row.

  This module owns the alias/possible-variant detection queries so the
  provider itself stays pure and DB-free — `recognize_and_record/3`
  pre-computes those signals from the database, then hands them to the
  provider as ordinary facts.

  `reidentify/2` is the separate, later-run entry point for
  `Playstead.Recognition.ReferenceMatch` (D-18): installing a pack does
  not re-run the live import pipeline, it re-scans the existing
  library for blobs a reference pack can now name.
  """

  import Ecto.Query, warn: false

  alias Playstead.Attention
  alias Playstead.Blobs
  alias Playstead.Blobs.{Blob, BlobFingerprint, Fingerprints}
  alias Playstead.Catalogue.{AssetSet, Payload}
  alias Playstead.Formats
  alias Playstead.Import.SourceFile
  alias Playstead.Recognition.{DatPack, Evidence, HeaderEvidence, ReferenceMatch}
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  @provider HeaderEvidence

  @doc """
  Recognizes one file for `user_id` and records the result as a new
  evidence row. `file_facts` must include `:blob_id` and `:sha256`; it
  may include `:bytes` (leading bytes, for patch detection) and
  `:exclude_source_file_id` (the source file just inserted for this
  import, so alias detection does not match against itself).
  `format_evidence` is the `{system_id, tier, evidence}` tuple
  `Playstead.Formats.identify/2` produced, or `nil`.

  Returns `{result, evidence_row}`. Never updates or deletes an
  existing evidence row — a second call for the same blob simply
  inserts another one.
  """
  @spec recognize_and_record(pos_integer(), map(), {atom(), atom(), map()} | nil) ::
          {Playstead.Recognition.Provider.result(), Evidence.t()}
  def recognize_and_record(user_id, file_facts, format_evidence) do
    facts =
      file_facts
      |> Map.put(:alias?, alias_exists?(user_id, file_facts))
      |> Map.put(:variant_match, variant_match(format_evidence, file_facts))

    result = @provider.recognize(facts, format_evidence)
    {:ok, evidence_row} = insert_evidence(file_facts, result)
    {result, evidence_row}
  end

  @doc """
  Whether `user_id` has any `Playstead.Recognition.DatPack` installed —
  a single existence query, since the overwhelmingly common case is no
  pack at all. This is the discriminator between `unrecognized`'s two
  quiet reasons (D-26): a supported format with no pack installed is
  `no_reference_installed`; a supported format with a pack installed
  that matches nothing is `no_match`.
  """
  @spec packs_installed?(pos_integer()) :: boolean()
  def packs_installed?(user_id) do
    from(p in DatPack, where: p.user_id == ^user_id) |> Repo.exists?()
  end

  defp alias_exists?(_user_id, %{blob_id: nil}), do: false

  defp alias_exists?(user_id, facts) do
    exclude_id = facts[:exclude_source_file_id]

    query =
      from(sf in SourceFile, where: sf.user_id == ^user_id and sf.blob_id == ^facts.blob_id)

    query = if exclude_id, do: where(query, [sf], sf.id != ^exclude_id), else: query

    Repo.exists?(query)
  end

  # D-17: a possible variant is different bytes sharing a header
  # serial/game-code on the same system — never scoped to "same user"
  # (unlike alias), since the header fact itself is a property of the
  # bytes, not of who owns them.
  defp variant_match({system, _tier, evidence}, facts) when system != :unknown do
    key = evidence[:game_code] || evidence[:serial]

    if key && facts[:sha256] do
      query =
        from(r in Evidence,
          join: b in Blob,
          on: b.id == r.blob_id,
          where:
            fragment("(?->>'game_code') = ?", r.evidence, ^key) or
              fragment("(?->>'serial') = ?", r.evidence, ^key),
          where: b.sha256 != ^facts.sha256,
          limit: 1
        )

      if Repo.exists?(query), do: key
    end
  end

  defp variant_match(_format_evidence, _facts), do: nil

  defp insert_evidence(file_facts, result) do
    %Evidence{}
    |> Evidence.create_changeset(%{
      blob_id: file_facts[:blob_id],
      asset_set_id: file_facts[:asset_set_id],
      provider_name: @provider.name(),
      provider_version: @provider.version(),
      status: to_string(result.status),
      confidence: result.confidence && to_string(result.confidence),
      reference_name: result.reference_name,
      evidence: stringify(result.evidence)
    })
    |> Repo.insert()
  end

  defp stringify(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_string(k), stringify_value(v)} end)
  end

  defp stringify_value(v) when is_atom(v) and not is_nil(v) and not is_boolean(v),
    do: to_string(v)

  defp stringify_value(v), do: v

  # --- reference-pack re-identification (D-18) --------------------------

  @doc """
  Re-scans `user_id`'s existing library through
  `Playstead.Recognition.ReferenceMatch`. Every blob not already
  matched by a reference pack is checked against installed reference
  entries; a match appends a new evidence row, promotes the asset's
  current identification state (a fresh catalogue journal entry is
  emitted only for that asset), and resolves any open attention item a
  match can settle. Content that stays unmatched is left exactly as
  quiet as it was — no evidence row, no journal entry, no attention
  item. Returns the count of assets newly identified in this pass.
  """
  @spec reidentify(pos_integer(), keyword()) :: %{identified: non_neg_integer()}
  def reidentify(user_id, _opts \\ []) do
    user_id
    |> unmatched_candidates()
    |> Enum.reduce(%{identified: 0}, fn {asset_set, blob}, acc ->
      fingerprints = fingerprints_for(blob)

      case ReferenceMatch.match(blob, fingerprints) do
        {:match, entry} ->
          promote(user_id, asset_set, blob, entry)
          %{acc | identified: acc.identified + 1}

        :no_match ->
          acc
      end
    end)
  end

  # Lazy backfill (plan 02-10): a blob imported before the fingerprint
  # writer existed has no `blob_fingerprints` rows. Computing the
  # missing fingerprint here — only for a blob a newly installed pack
  # is actually being checked against — back-fills precisely the set
  # that matters, at the moment it matters, with no new job, no queue,
  # and no scheduling. A blob nobody ever tries to identify never pays
  # the cost. Skipped entirely when rows already exist, so installing
  # a second pack never re-reads a blob the first pack already
  # fingerprinted.
  defp fingerprints_for(%Blob{} = blob) do
    case Repo.all(from(f in BlobFingerprint, where: f.blob_id == ^blob.id)) do
      [] ->
        backfill_fingerprint(blob)
        Repo.all(from(f in BlobFingerprint, where: f.blob_id == ^blob.id))

      rows ->
        rows
    end
  end

  defp backfill_fingerprint(%Blob{id: blob_id, sha256: sha256}) do
    case Blobs.read_leading(sha256) do
      {:ok, bytes} ->
        format_result = Formats.identify(bytes)
        Fingerprints.ensure_headerless(blob_id, format_result)

      {:error, :not_found} ->
        :ok
    end
  end

  # One `{asset_set, blob}` pair per member with a blob, excluding any
  # blob a reference pack has already matched — reidentify only ever
  # does new work, so installing a second pack never re-processes what
  # the first pack already settled.
  defp unmatched_candidates(user_id) do
    asset_sets =
      from(a in AssetSet,
        where: a.user_id == ^user_id and is_nil(a.excluded_at),
        preload: [asset_members: :blob]
      )
      |> Repo.all()

    already_matched_blob_ids =
      from(e in Evidence, where: e.provider_name == ^ReferenceMatch.name(), select: e.blob_id)
      |> Repo.all()
      |> MapSet.new()

    for asset_set <- asset_sets,
        member <- asset_set.asset_members,
        not is_nil(member.blob_id),
        not MapSet.member?(already_matched_blob_ids, member.blob_id) do
      {asset_set, member.blob}
    end
    |> Enum.uniq_by(fn {asset_set, blob} -> {asset_set.id, blob.id} end)
  end

  defp promote(user_id, asset_set, blob, entry) do
    variant? = latest_status(blob.id) == "possible_variant"
    result = ReferenceMatch.recognize(%{reference_entry: entry, variant?: variant?}, nil)

    {:ok, _evidence} =
      %Evidence{}
      |> Evidence.create_changeset(%{
        blob_id: blob.id,
        asset_set_id: asset_set.id,
        provider_name: ReferenceMatch.name(),
        provider_version: ReferenceMatch.version(),
        status: to_string(result.status),
        confidence: to_string(result.confidence),
        reference_name: result.reference_name,
        evidence: stringify(result.evidence)
      })
      |> Repo.insert()

    emit_catalogue_journal(user_id, asset_set.id)
    Attention.resolve_for_asset_set(user_id, asset_set.id)
    :ok
  end

  defp latest_status(blob_id) do
    from(e in Evidence, where: e.blob_id == ^blob_id, order_by: [desc: e.inserted_at], limit: 1)
    |> Repo.one()
    |> case do
      %Evidence{status: status} -> status
      nil -> nil
    end
  end

  defp emit_catalogue_journal(user_id, asset_set_id) do
    fresh = Repo.get!(AssetSet, asset_set_id) |> Repo.preload(asset_members: :blob)
    ChangeJournal.append(user_id, :catalogue, fresh.id, Payload.build(fresh))
  end
end
