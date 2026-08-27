defmodule Playstead.Setup do
  @moduledoc """
  Setup-token bootstrap and the once-only owner-claim transition (D-03).

  There is never an unauthenticated first-visit claim window: a valid
  setup token is required before an owner account can be created, and
  `/setup` 404s permanently once one exists (enforced at the router by
  `PlaysteadWeb.Plugs.RequireSetupOpen`, driven by
  `Playstead.Accounts.owner_exists?/0`).
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Playstead.Accounts
  alias Playstead.Accounts.SetupToken
  alias Playstead.Repo

  @env_override "PLAYSTEAD_SETUP_TOKEN"
  @token_bytes 32

  @doc """
  Runs at boot, after the Repo starts. A no-op once an owner exists.

  Otherwise mints a fresh setup token — replacing any prior unconsumed
  token, so a container restart before setup never leaves two valid
  tokens alive — and either:

    * prints the plaintext to stdout in an unmissable banner (the
      `docker compose logs` moment), or
    * silently adopts `PLAYSTEAD_SETUP_TOKEN` when that env var is set,
      the documented automation override, which is never printed since
      the operator who set it already knows its value.
  """
  @spec mint_token() :: :ok
  def mint_token do
    if Accounts.owner_exists?() do
      :ok
    else
      case System.get_env(@env_override) do
        value when is_binary(value) and value != "" ->
          replace_active_token(value)
          :ok

        _ ->
          token = generate_token()
          replace_active_token(token)
          print_banner(token)
          :ok
      end
    end
  end

  @doc """
  Verifies a setup token against the currently active (unconsumed)
  row, in constant time. Returns `:ok` or `{:error, :invalid_or_expired}`.

  This is a convenience check for the wizard's first step (immediate
  field feedback) — the load-bearing, race-safe verification happens
  inside `claim/2`'s transaction.
  """
  @spec verify_token(String.t()) :: :ok | {:error, :invalid_or_expired}
  def verify_token(token) when is_binary(token) do
    hash = hash_token(token)

    query = from(t in SetupToken, where: t.token_hash == ^hash and is_nil(t.consumed_at))

    case Repo.one(query) do
      nil -> {:error, :invalid_or_expired}
      _ -> :ok
    end
  end

  @doc """
  The once-only owner-claim transition (D-03, D-04, D-05b), OPER-02's
  concurrency edge probe.

  Verifies the token, registers the owner, consumes the token, and
  generates recovery codes — all inside one `Ecto.Multi`. The token is
  consumed via an `UPDATE ... WHERE consumed_at IS NULL` guarded by the
  transaction: Postgres serializes two concurrent claims at that row, so
  exactly one succeeds and the loser gets `{:error, :token_already_used}`
  rather than a second owner being created. If owner registration fails
  validation, the whole transaction (including the token consumption)
  rolls back, so a real typo doesn't burn the token.

  Returns `{:ok, %{user: user, recovery_codes: [String.t()]}}` or
  `{:error, :invalid_or_expired | :token_already_used | Ecto.Changeset.t()}`.
  """
  @spec claim(String.t(), map()) ::
          {:ok, %{user: Playstead.Accounts.User.t(), recovery_codes: [String.t()]}}
          | {:error, :invalid_or_expired | :token_already_used | Ecto.Changeset.t()}
  def claim(token, owner_attrs) do
    hash = hash_token(token)

    multi =
      Multi.new()
      |> Multi.run(:setup_token, fn repo, _changes ->
        case repo.get_by(SetupToken, token_hash: hash) do
          nil -> {:error, :invalid_or_expired}
          setup_token -> {:ok, setup_token}
        end
      end)
      |> Multi.run(:consumed, fn repo, %{setup_token: setup_token} ->
        {count, _} =
          repo.update_all(
            from(t in SetupToken, where: t.id == ^setup_token.id and is_nil(t.consumed_at)),
            set: [consumed_at: DateTime.utc_now(:second)]
          )

        if count == 1, do: {:ok, :consumed}, else: {:error, :token_already_used}
      end)
      |> Multi.run(:user, fn _repo, _changes -> Accounts.register_owner(owner_attrs) end)
      |> Multi.run(:recovery_codes, fn _repo, %{user: user} ->
        {:ok, Accounts.generate_recovery_codes(user)}
      end)

    case Repo.transaction(multi) do
      {:ok, %{user: user, recovery_codes: codes}} ->
        {:ok, %{user: user, recovery_codes: codes}}

      {:error, :setup_token, reason, _changes} ->
        {:error, reason}

      {:error, :consumed, reason, _changes} ->
        {:error, reason}

      {:error, :user, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp generate_token do
    @token_bytes
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  defp hash_token(token), do: :crypto.hash(:sha256, token)

  # Exactly one active (unconsumed-or-otherwise) setup token exists at a
  # time — minting again replaces it rather than accumulating rows.
  defp replace_active_token(token) do
    Repo.delete_all(SetupToken)
    Repo.insert!(%SetupToken{token_hash: hash_token(token)})
  end

  defp print_banner(token) do
    IO.puts("""

    ============================================================
    Playstead setup token (use once, in the setup wizard at /setup):

    #{token}

    ============================================================
    """)
  end
end
