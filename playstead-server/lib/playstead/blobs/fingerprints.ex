defmodule Playstead.Blobs.Fingerprints do
  @moduledoc """
  The production writer for headerless-offset fingerprints (D-20,
  plan 02-10 gap closure): `ensure_headerless/2` maps a
  `Playstead.Formats.identify/2` result to at most one
  `Playstead.Blobs.BlobFingerprint` kind and, when one applies,
  computes and stores it.

  D-20 states the headerless fingerprints are computed in the same
  streaming pass as SHA-256, "once the header is seen". This module
  computes them in a second, bounded seek-and-read after commit
  instead. The reason is architectural: the streaming pass lives
  inside the storage adapter, and teaching the adapter to recognize an
  iNES magic or an SNES checksum complement would push format
  knowledge across the `Playstead.Blobs.Store` seam D-12 exists to
  hold. The cost is one extra read of an NES or SNES object, which are
  small, and only for files where a header was actually detected — the
  default-on read-back verify (D-11) already re-reads every committed
  object once, so this is not a new class of work. Reversible: the
  rows are derived data reproducible from the bytes at any time, so
  moving the computation into the streaming pass later needs no
  migration and no backfill of anything but the rows themselves.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs
  alias Playstead.Blobs.{Blob, BlobFingerprint}
  alias Playstead.Repo

  @nes_kind "nes_header_skip16"
  @nes_offset 16
  @snes_kind "snes_copier_skip512"
  @snes_offset 512

  @doc """
  Writes at most one `blob_fingerprints` row for `blob_id`, derived
  from `format_result` (the `{system, tier, evidence}` tuple
  `Playstead.Formats.identify/2` produced, or `nil`). Returns the
  number of rows written (`0` or `1`).

  A NES signature match (`system == :nes`) always implies the 16-byte
  iNES header is present, so it maps to `#{@nes_kind}` at offset
  `#{@nes_offset}`. An SNES structure match (`system == :snes`) whose
  evidence carries a true `copier_header` maps to `#{@snes_kind}` at
  offset `#{@snes_offset}` — an SNES match with no copier header maps
  to nothing. Every other format result — a GBA, GB, MD, or PSX match,
  a container, and `:unknown` — maps to no kind and this function
  returns `0` without touching the store.

  Idempotent by construction: the unique index on
  `{blob_id, kind}` plus `on_conflict: :nothing` means a repeated call
  for the same blob and kind (e.g. a re-import whose CAS commit
  returns `:existing`) leaves exactly one row. Uses `Repo.insert_all`
  rather than a changeset insert for the same reason
  `LocalDisk.insert_blob_row/2` does: this can run inside
  `Playstead.Import`'s ambient transaction, and a failed constrained
  `Repo.insert` would leave that Postgres transaction aborted for
  every later query in it. On an error reading the digest (an
  unreadable object is a separate fault with its own path), returns
  `0` and leaves no row — it must never fail an import.
  """
  @spec ensure_headerless(binary(), {atom(), atom(), map()} | nil) :: non_neg_integer()
  def ensure_headerless(blob_id, format_result) do
    case fingerprint_kind(format_result) do
      nil -> 0
      {kind, offset} -> write_fingerprint(blob_id, kind, offset)
    end
  end

  defp fingerprint_kind({:nes, _tier, _evidence}), do: {@nes_kind, @nes_offset}

  defp fingerprint_kind({:snes, _tier, %{copier_header: true}}),
    do: {@snes_kind, @snes_offset}

  defp fingerprint_kind(_format_result), do: nil

  defp write_fingerprint(blob_id, kind, offset) do
    case Repo.get(Blob, blob_id) do
      nil ->
        0

      %Blob{sha256: sha256} ->
        case Blobs.digest_from_offset(sha256, offset) do
          {:ok, digests} ->
            insert_row(blob_id, kind, offset, digests)

          {:error, _reason} ->
            0
        end
    end
  end

  defp insert_row(blob_id, kind, offset, digests) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      id: Ecto.UUID.generate(),
      blob_id: blob_id,
      kind: kind,
      offset: offset,
      crc32: digests.crc32,
      md5: digests.md5,
      sha1: digests.sha1,
      inserted_at: now,
      updated_at: now
    }

    {count, _} =
      Repo.insert_all(BlobFingerprint, [attrs],
        on_conflict: :nothing,
        conflict_target: [:blob_id, :kind]
      )

    count
  end
end
