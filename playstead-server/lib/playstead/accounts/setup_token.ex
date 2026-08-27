defmodule Playstead.Accounts.SetupToken do
  @moduledoc """
  The single-use setup-token row backing D-03's bootstrap. Only its hash is
  ever persisted — the plaintext exists only in memory long enough to be
  printed to stdout (or, under `PLAYSTEAD_SETUP_TOKEN`, is never persisted
  in plaintext at all).

  `Playstead.Setup.mint_token/0` keeps at most one row alive at a time —
  minting again (e.g. on a container restart before an owner exists)
  replaces the prior row rather than accumulating stale valid tokens.
  """

  use Ecto.Schema

  schema "setup_tokens" do
    field :token_hash, :binary
    field :consumed_at, :utc_datetime

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
