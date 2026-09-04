defmodule Playstead.Repo.Migrations.AddSaveLineageFieldsAndParents do
  use Ecto.Migration

  def change do
    # D-12: recorded base evidence. A mismatch is recorded, never
    # rejected -- base_matched is derived at commit time and the
    # commit proceeds regardless of its value.
    #
    # D-15: device-claimed time is stored as evidence only, never
    # orderable. device_clock_offset_ms separates clock error from
    # queue delay; device_monotonic_ms is a device-local counter, also
    # never orderable across devices.
    #
    # D-30: same-device byte-identical capture bumps last_confirmed_at
    # / confirm_count on the existing head rather than creating a new
    # revision.
    alter table(:save_revisions) do
      add :base_sha256, :string
      add :base_matched, :boolean
      add :device_reported_now, :utc_datetime_usec
      add :device_clock_offset_ms, :integer
      add :device_monotonic_ms, :bigint
      add :origin, :string
      add :last_confirmed_at, :utc_datetime_usec
      add :confirm_count, :integer, null: false, default: 0
    end

    # D-48: a resolution revision names every divergent head as a
    # parent, exactly one with role "chosen" and the rest
    # "acknowledged". The ordinary single-parent case keeps using
    # save_revisions.parent_revision_id directly -- this table exists
    # for the N-way case a single column cannot express.
    create table(:save_revision_parents) do
      add :revision_id, references(:save_revisions, type: :binary_id, on_delete: :delete_all),
        null: false

      add :parent_revision_id,
          references(:save_revisions, type: :binary_id, on_delete: :nilify_all),
          null: false

      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:save_revision_parents, [:revision_id, :parent_revision_id])
    create index(:save_revision_parents, [:parent_revision_id])
  end
end
