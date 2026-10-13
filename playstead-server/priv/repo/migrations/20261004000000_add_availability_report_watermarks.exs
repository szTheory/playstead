defmodule Playstead.Repo.Migrations.AddAvailabilityReportWatermarks do
  use Ecto.Migration

  def change do
    create table(:device_availability_report_watermarks, primary_key: false) do
      add :device_id,
          references(:devices, type: :binary_id, on_delete: :delete_all),
          primary_key: true

      add :accepted_report_sequence, :bigint, null: false

      timestamps(type: :utc_datetime)
    end

    create constraint(:device_availability_report_watermarks, :accepted_report_sequence_positive,
             check: "accepted_report_sequence > 0"
           )
  end
end
