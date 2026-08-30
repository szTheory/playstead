defmodule Playstead.Repo.Migrations.AddBlobFingerprintsUniqueKind do
  use Ecto.Migration

  def change do
    # Plan 02-10: a blob has at most one fingerprint row per kind
    # (`nes_header_skip16`, `snes_copier_skip512`). The unique index is
    # what makes `Playstead.Blobs.Fingerprints.ensure_headerless/2`'s
    # `on_conflict: :nothing` idempotent under a repeated import of
    # identical bytes — the existing `index(:blob_fingerprints, [:blob_id])`
    # is left in place; it still serves `reidentify/2`'s per-blob lookup.
    create unique_index(:blob_fingerprints, [:blob_id, :kind])
  end
end
