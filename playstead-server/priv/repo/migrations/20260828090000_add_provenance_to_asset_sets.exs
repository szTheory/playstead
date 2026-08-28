defmodule Playstead.Repo.Migrations.AddProvenanceToAssetSets do
  use Ecto.Migration

  def change do
    # D-37: records how a reimported set's identity was decided when it
    # was not a fingerprint match — a claimed sidecar identifier that
    # was rejected (foreign owner, malformed) or reused, or a note that
    # this set was derived from an export of a named title because it
    # was neither a fingerprint match nor a strict subset. Never
    # consulted to decide identity itself; recorded for visibility only.
    alter table(:asset_sets) do
      add :provenance, :map, null: false, default: %{}
    end
  end
end
