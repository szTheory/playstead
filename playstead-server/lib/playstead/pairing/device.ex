defmodule Playstead.Pairing.Device do
  @moduledoc """
  A paired device (D-10, D-11). `name` is owner-editable; `claimed_name`
  preserves what the client self-reported at pairing time and is never
  overwritten by a rename, so the console can always show both.

  `revoked_at` is a tombstone, never deleted — re-pairing after
  revocation always creates a brand-new row (D-11).
  """

  use Ecto.Schema
  import Ecto.Changeset

  # D-11 / UI-SPEC overflow contract: the rename input enforces this
  # ceiling so an owner-entered name can never exceed the truncation
  # contract the console's rename form and device list share.
  @max_name_length 100

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "devices" do
    field :user_id, :id
    field :name, :string
    field :claimed_name, :string
    field :platform, :string
    field :app_version, :string
    field :paired_at, :utc_datetime
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(device, attrs) do
    device
    |> cast(attrs, [:user_id, :name, :claimed_name, :platform, :app_version, :paired_at])
    |> validate_required([:user_id, :paired_at])
  end

  @doc "The maximum length enforced for an owner-entered rename."
  def max_name_length, do: @max_name_length

  @doc "Owner rename — writes only `name`, never `claimed_name` (D-11)."
  def rename_changeset(device, name) do
    device
    |> change(name: name)
    |> validate_length(:name, max: @max_name_length)
  end

  @doc """
  Device self-report refresh (D-20a's `PATCH /api/v1/devices/me`) —
  writes only the client's own claimed fields, mirroring the initial
  pairing-time declaration. Never touches the owner-editable `name`.
  """
  def self_report_changeset(device, attrs) do
    device
    |> cast(attrs, [:claimed_name, :app_version])
    |> validate_length(:claimed_name, max: @max_name_length)
  end

  @doc false
  def revoke_changeset(device, revoked_at) do
    change(device, revoked_at: revoked_at)
  end

  @doc false
  def touch_last_seen_changeset(device, last_seen_at) do
    change(device, last_seen_at: last_seen_at)
  end

  @type t :: %__MODULE__{}
end
