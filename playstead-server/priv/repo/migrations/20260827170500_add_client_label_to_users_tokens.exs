defmodule Playstead.Repo.Migrations.AddClientLabelToUsersTokens do
  use Ecto.Migration

  def change do
    # D-06: a coarse, safe browser/OS label derived from User-Agent at
    # session-creation time, shown on the Sessions list. Never the raw
    # user-agent string (T-01-19) — nil when unrecognizable, and the UI
    # renders the generic "Browser session" label in that case.
    alter table(:users_tokens) do
      add :client_label, :string
    end
  end
end
