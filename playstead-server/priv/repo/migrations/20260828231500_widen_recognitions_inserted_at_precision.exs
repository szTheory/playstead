defmodule Playstead.Repo.Migrations.WidenRecognitionsInsertedAtPrecision do
  use Ecto.Migration

  def change do
    # Fix for a latent ordering bug this plan's re-identification pass
    # exposed: "the latest evidence row for a blob" is read by
    # `ORDER BY inserted_at DESC LIMIT 1` in several places
    # (`Playstead.Recognition`, `Playstead.Catalogue.Payload`). Second-
    # precision `utc_datetime` makes that order ambiguous whenever two
    # evidence rows for the same blob are written inside the same
    # second — exactly what happens when a reference match runs
    # immediately after the header-evidence provider did, as in a fast
    # automated re-identification pass. Widening to microsecond
    # precision makes "latest" unambiguous without adding a second sort
    # column to every existing query.
    alter table(:recognitions) do
      modify :inserted_at, :utc_datetime_usec, from: :utc_datetime
    end
  end
end
