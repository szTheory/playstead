defmodule Playstead.AuditLog.Entry do
  @moduledoc """
  A single append-only audit log row (D-05a, D-12, T-01-18). Rows are
  never updated or deleted — `Playstead.AuditLog.record/3` is the only
  write path in the application.
  """

  use Ecto.Schema
  import Ecto.Changeset

  schema "audit_log_entries" do
    field :event, :string
    field :subject, :string
    field :metadata, :map, default: %{}
    belongs_to :user, Playstead.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def changeset(entry, attrs) do
    entry
    |> cast(attrs, [:user_id, :event, :subject, :metadata])
    |> validate_required([:event])
  end
end
