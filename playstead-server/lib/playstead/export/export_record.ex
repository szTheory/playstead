defmodule Playstead.Export.ExportRecord do
  @moduledoc """
  The durable export record (D-33, D-36, D-38, D-40): scope, target,
  counts, byte totals, status, per-file verification result, sidecar
  schema identifier, generator version, timings, and the last
  verification time. `status` moves through `writing` -> `verifying`
  -> `verified` | `verification_failed`; a verification failure names
  every mismatching file in `mismatched_files` rather than deleting
  anything.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(writing verifying verified verification_failed)
  @scopes ~w(set library)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "exports" do
    field :user_id, :id
    field :scope, :string
    field :scope_asset_set_id, :binary_id
    field :target_name, :string

    field :status, :string, default: "writing"
    field :set_count, :integer, default: 0
    field :file_count, :integer, default: 0
    field :total_bytes, :integer, default: 0

    field :sidecar_schema_id, :string
    field :generator_version, :string

    field :mismatched_files, {:array, :string}, default: []

    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :last_verified_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  @doc "The frozen set of persisted export statuses."
  def statuses, do: @statuses

  @doc false
  def create_changeset(export, attrs) do
    export
    |> cast(attrs, [:id, :user_id, :scope, :scope_asset_set_id, :target_name])
    |> validate_required([:id, :user_id, :scope, :target_name])
    |> validate_inclusion(:scope, @scopes)
    |> put_change(:status, "writing")
    |> put_change(:started_at, DateTime.utc_now())
  end

  @doc false
  def status_changeset(export, status) when status in @statuses do
    change(export, status: status)
  end

  @doc false
  def counts_changeset(export, attrs) do
    cast(export, attrs, [
      :set_count,
      :file_count,
      :total_bytes,
      :sidecar_schema_id,
      :generator_version
    ])
  end

  @doc false
  def verified_changeset(export) do
    now = DateTime.utc_now()

    change(export,
      status: "verified",
      mismatched_files: [],
      finished_at: export.finished_at || now,
      last_verified_at: now
    )
  end

  @doc false
  def reverified_ok_changeset(export) do
    change(export, status: "verified", mismatched_files: [], last_verified_at: DateTime.utc_now())
  end

  @doc false
  def verification_failed_changeset(export, mismatched_files) do
    now = DateTime.utc_now()

    change(export,
      status: "verification_failed",
      mismatched_files: mismatched_files,
      finished_at: export.finished_at || now,
      last_verified_at: now
    )
  end

  @doc false
  def verifying_changeset(export) do
    change(export, status: "verifying")
  end

  @type t :: %__MODULE__{}
end
