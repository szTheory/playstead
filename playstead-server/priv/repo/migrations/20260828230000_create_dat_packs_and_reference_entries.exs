defmodule Playstead.Repo.Migrations.CreateDatPacksAndReferenceEntries do
  use Ecto.Migration

  def change do
    # D-18, T-02-63: full pack provenance is not bookkeeping — it is the
    # only defensible position for a product that never ships or fetches
    # reference data itself. `file_sha256` is unique so importing the
    # same pack twice is a lookup, never a duplicate insert (D-18's
    # "installing a pack later never rewrites history" starts here: the
    # pack record itself is idempotent on its own bytes).
    create table(:dat_packs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, on_delete: :delete_all), null: false

      add :source, :string
      add :retrieved_at, :utc_datetime
      add :upstream_version, :string
      add :file_sha256, :string, null: false
      add :license_claim, :string, null: false
      add :license_note, :string
      add :transform_version, :string, null: false

      add :entry_count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:dat_packs, [:user_id, :file_sha256])

    create constraint(:dat_packs, :license_claim_must_be_known,
             check:
               "license_claim IN ('public_domain', 'share_alike', 'all_rights_reserved', 'unstated', 'other')"
           )

    # D-18, D-20: each entry carries the digests a reference pack
    # publishes (Logiqx DATs hash headerless — the CRC32/MD5/SHA-1
    # already stored on `blobs` and `blob_fingerprints` are what these
    # are matched against). `size_bytes` is metadata only, never used to
    # size an allocation (T-02-61) — stored exactly as declared, for
    # display and audit only.
    create table(:reference_entries, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :dat_pack_id, references(:dat_packs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :crc32, :string
      add :md5, :string
      add :sha1, :string
      add :size_bytes, :bigint

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:reference_entries, [:dat_pack_id])
    create index(:reference_entries, [:crc32])
    create index(:reference_entries, [:md5])
    create index(:reference_entries, [:sha1])
  end
end
