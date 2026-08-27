defmodule Playstead.Repo.Migrations.CreateIdempotencyReceipts do
  use Ecto.Migration

  def change do
    # D-20a: the unique index on {device_id, idempotency_key} is the
    # concurrency primitive — a racing retry's insert of the in-flight
    # marker fails against it, which is what produces 409 rather than a
    # second effect (Playstead.Idempotency.execute/4).
    create table(:idempotency_receipts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :device_id, references(:devices, type: :binary_id, on_delete: :delete_all), null: false

      add :idempotency_key, :string, null: false
      add :request_fingerprint, :string, null: false
      add :response_status, :integer
      add :response_body, :text
      add :state, :string, null: false, default: "in_flight"
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:idempotency_receipts, [:device_id, :idempotency_key])
    create index(:idempotency_receipts, [:expires_at])
  end
end
