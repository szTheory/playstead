defmodule Playstead.Recognition.ReferenceMatch do
  @moduledoc """
  The reference-pack recognition provider (D-16, D-18, D-20): an
  ordinary implementation of `Playstead.Recognition.Provider`, not a
  second pipeline. `match/2` is the actual digest lookup — it compares
  a blob's own stored digests and its headerless-offset fingerprints
  (`Playstead.Blobs.BlobFingerprint`) against installed reference
  entries. Both digest kinds are needed because reference packs hash
  content without its console header (D-20); matching therefore reads
  only rows already in the database and never re-opens a blob's bytes
  from the object store.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs.{Blob, BlobFingerprint}
  alias Playstead.Recognition.ReferenceEntry
  alias Playstead.Repo

  @behaviour Playstead.Recognition.Provider

  @impl true
  def name, do: "reference_match"

  @impl true
  def version, do: "1"

  @doc """
  `facts` carries `:reference_entry` (the matched
  `Playstead.Recognition.ReferenceEntry`, precomputed by the caller via
  `match/2`, or `nil`) and `:variant?` (precomputed: was there already
  a possible-variant reading for this blob before this match?). Only a
  reference match may promote a possible-variant reading to a certain
  one — header evidence alone never does (D-17).
  """
  @impl true
  def recognize(%{reference_entry: nil}, _format_evidence) do
    %{status: :no_match, confidence: nil, reference_name: nil, evidence: %{}}
  end

  def recognize(%{reference_entry: %ReferenceEntry{} = entry} = facts, _format_evidence) do
    status = if facts[:variant?], do: :variant, else: :matched

    %{
      status: status,
      confidence: :exact,
      reference_name: entry.name,
      evidence: %{
        dat_pack_id: entry.dat_pack_id,
        crc32: entry.crc32,
        md5: entry.md5,
        sha1: entry.sha1
      }
    }
  end

  @doc """
  Looks for a `Playstead.Recognition.ReferenceEntry` matching `blob`'s
  own stored digests, or (failing that) any of `fingerprints`'
  headerless-offset digests — the reason a headerless-offset match can
  succeed where the full-file digest alone would not. Tries the most
  collision-resistant digest first (SHA-1), then MD5, then CRC32.
  Reads only `reference_entries` rows; never touches the blob store.
  """
  @spec match(Blob.t(), [BlobFingerprint.t()]) :: {:match, ReferenceEntry.t()} | :no_match
  def match(%Blob{} = blob, fingerprints \\ []) do
    digest_sets = [
      %{sha1: blob.sha1, md5: blob.md5, crc32: blob.crc32}
      | Enum.map(fingerprints, &Map.take(&1, [:sha1, :md5, :crc32]))
    ]

    Enum.find_value(digest_sets, :no_match, fn digests ->
      case find_entry(digests) do
        %ReferenceEntry{} = entry -> {:match, entry}
        nil -> nil
      end
    end)
  end

  # Tries SHA-1, then MD5, then CRC32, in that order of collision
  # resistance — the first present digest that finds a row wins.
  defp find_entry(digests) when is_map(digests) do
    lookup_by(:sha1, digests[:sha1]) || lookup_by(:md5, digests[:md5]) ||
      lookup_by(:crc32, digests[:crc32])
  end

  defp lookup_by(_field, nil), do: nil

  defp lookup_by(:sha1, sha1) do
    Repo.one(from(e in ReferenceEntry, where: e.sha1 == ^sha1, limit: 1))
  end

  defp lookup_by(:md5, md5) do
    Repo.one(from(e in ReferenceEntry, where: e.md5 == ^md5, limit: 1))
  end

  defp lookup_by(:crc32, crc32) do
    Repo.one(from(e in ReferenceEntry, where: e.crc32 == ^crc32, limit: 1))
  end
end
