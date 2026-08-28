defmodule Playstead.Repo.Migrations.AddAssetMemberOrdinalUniqueIndex do
  use Ecto.Migration

  def change do
    # D-15/IMPT-04 concurrency: a unique index over the asset set and
    # ordinal is the collision authority that makes "two imports racing
    # to complete the same set converge on one row per ordinal" a
    # database guarantee rather than a read-then-write race.
    create unique_index(:asset_members, [:asset_set_id, :ordinal])
  end
end
