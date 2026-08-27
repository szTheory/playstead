defmodule Playstead.Accounts.RecoveryCode do
  @moduledoc """
  A single-use recovery code (D-05b). Each code is its own row, hashed
  with the same bcrypt mechanism as passwords, so individual codes can be
  consumed independently — there is no single hashed blob covering the
  whole set. Plaintext is returned exactly once, from
  `Playstead.Accounts.generate_recovery_codes/1`, and never stored.
  """

  use Ecto.Schema

  schema "recovery_codes" do
    field :code_hash, :string, redact: true
    field :consumed_at, :utc_datetime
    belongs_to :user, Playstead.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
