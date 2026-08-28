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
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs.Blob
  alias Playstead.Import.SourceFile
  alias Playstead.Recognition.{Evidence, HeaderEvidence}
  alias Playstead.Repo

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
end
