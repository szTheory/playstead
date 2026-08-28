defmodule Playstead.Recognition.DatPackImporter do
  @moduledoc """
  Reads an administrator-supplied reference pack, hashes it, parses it
  under `Playstead.Recognition.LogiqxHandler`'s hard caps, and records
  its full provenance (D-18). Nothing here ever reaches the network —
  the pack's bytes come from a local path the caller already has (an
  uploaded file), and no pack is ever fetched, bundled, or committed to
  the repository.

  Importing the same pack twice is a no-op on the second call: packs
  are keyed on their own file hash, so a duplicate upload returns the
  existing record rather than duplicating its entries.
  """

  alias Playstead.AuditLog
  alias Playstead.Blobs.MultiHash
  alias Playstead.Recognition.{DatPack, LogiqxHandler, ReferenceEntry}
  alias Playstead.Repo

  @default_transform_version "1"

  @doc """
  Imports the pack at `path` for `user_id`. `provenance` may carry
  `:source`, `:retrieved_at`, `:upstream_version`, `:license_claim`
  (required, one of `Playstead.Recognition.DatPack.license_claims/0`),
  `:license_note`, and `:transform_version` (defaults to the current
  importer version).

  Returns `{:ok, dat_pack}` on success (whether newly imported or
  already present), or `{:error, reason}` for a hostile or malformed
  pack — in which case nothing is stored, not even a partial entry
  list.
  """
  @spec import_pack(pos_integer(), String.t(), map()) ::
          {:ok, DatPack.t()} | {:error, term()}
  def import_pack(user_id, path, provenance) when is_integer(user_id) and is_binary(path) do
    with {:ok, binary} <- LogiqxHandler.read_capped(path) do
      file_sha256 = MultiHash.sha256_of(binary)

      case Repo.get_by(DatPack, user_id: user_id, file_sha256: file_sha256) do
        %DatPack{} = existing ->
          {:ok, existing}

        nil ->
          with {:ok, entries} <- LogiqxHandler.parse_binary(binary) do
            insert_pack(user_id, file_sha256, entries, provenance)
          end
      end
    end
  end

  defp insert_pack(user_id, file_sha256, entries, provenance) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      user_id: user_id,
      source: provenance[:source],
      retrieved_at: provenance[:retrieved_at] || now,
      upstream_version: provenance[:upstream_version],
      file_sha256: file_sha256,
      license_claim: to_string(provenance[:license_claim]),
      license_note: provenance[:license_note],
      transform_version: provenance[:transform_version] || @default_transform_version,
      entry_count: length(entries)
    }

    Repo.transaction(fn ->
      with {:ok, dat_pack} <- %DatPack{} |> DatPack.create_changeset(attrs) |> Repo.insert(),
           {:ok, _entries} <- insert_entries(dat_pack, entries),
           {:ok, _audit} <-
             AuditLog.record(user_id, :reference_pack_imported, %{
               subject: dat_pack.id,
               source: dat_pack.source,
               upstream_version: dat_pack.upstream_version,
               file_sha256: dat_pack.file_sha256,
               license_claim: dat_pack.license_claim,
               entry_count: dat_pack.entry_count
             }) do
        dat_pack
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp insert_entries(_dat_pack, []), do: {:ok, []}

  defp insert_entries(dat_pack, entries) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(entries, fn entry ->
        %{
          id: Ecto.UUID.generate(),
          dat_pack_id: dat_pack.id,
          name: entry.name || "unnamed",
          crc32: entry.crc32,
          md5: entry.md5,
          sha1: entry.sha1,
          size_bytes: entry.size_bytes,
          inserted_at: now
        }
      end)

    {count, _} = Repo.insert_all(ReferenceEntry, rows)
    {:ok, count}
  end

  @doc """
  Removes `dat_pack` and its `reference_entries` (audited, D-18).
  Recognition evidence carries no foreign key to a pack or its
  entries, so removing a pack never touches, reorders, or deletes a
  single `Playstead.Recognition.Evidence` row — history stays intact.
  """
  @spec remove_pack(DatPack.t(), pos_integer()) :: {:ok, DatPack.t()} | {:error, term()}
  def remove_pack(%DatPack{} = dat_pack, user_id) do
    Repo.transaction(fn ->
      with {:ok, deleted} <- Repo.delete(dat_pack),
           {:ok, _audit} <-
             AuditLog.record(user_id, :reference_pack_removed, %{
               subject: dat_pack.id,
               file_sha256: dat_pack.file_sha256
             }) do
        deleted
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc "Lists `user_id`'s installed packs, newest first."
  @spec list_packs(pos_integer()) :: [DatPack.t()]
  def list_packs(user_id) do
    import Ecto.Query, only: [from: 2]

    Repo.all(from(p in DatPack, where: p.user_id == ^user_id, order_by: [desc: p.inserted_at]))
  end
end
