defmodule Playstead.Pairing.DeviceCredential do
  @moduledoc """
  A per-device opaque bearer credential (D-10). The plaintext is
  32 random bytes, returned exactly once at issuance/rotation and stored
  only as a SHA-256 hash. `fingerprint_prefix` is what the console shows
  — it never sees the token itself.

  Rotation is use-activated, never forced: `superseded_by_id` marks an
  old row as replaced while it keeps authenticating until the new
  credential is first used, at which point the old row is deleted.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "device_credentials" do
    belongs_to :device, Playstead.Pairing.Device
    field :token_hash, :string
    field :fingerprint_prefix, :string
    field :activated_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :superseded_by_id, :binary_id
    # D-20b: client-generated UUIDv7 natural key. Nil for
    # non-command-scoped issuance (initial pairing redemption).
    field :command_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(credential, attrs) do
    credential
    |> cast(attrs, [
      :device_id,
      :token_hash,
      :fingerprint_prefix,
      :activated_at,
      :superseded_by_id,
      :command_id
    ])
    |> validate_required([:device_id, :token_hash])
    |> unique_constraint(:token_hash)
    |> unique_constraint(:command_id)
  end

  @doc false
  def touch_last_used_changeset(credential, last_used_at) do
    change(credential, last_used_at: last_used_at)
  end

  @doc false
  def activate_changeset(credential, activated_at) do
    change(credential, activated_at: activated_at)
  end

  @doc false
  def supersede_changeset(credential, superseded_by_id) do
    change(credential, superseded_by_id: superseded_by_id)
  end

  @type t :: %__MODULE__{}
end
