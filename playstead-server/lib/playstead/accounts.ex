defmodule Playstead.Accounts do
  @moduledoc """
  The Accounts context.

  D-01/D-02: this is a household-ready, single-owner account model.
  Authentication is password-only — there is no magic-link, email
  confirmation, or email-change flow anywhere in this module (see
  `test/playstead_web/no_mailer_test.exs` for the standing regression
  guard). The owner account is created exactly once, through
  `Playstead.Setup.claim/2`, which calls `register_owner/1` below.
  """

  import Ecto.Query, warn: false
  alias Playstead.Repo

  alias Playstead.Accounts.{User, UserToken, RecoveryCode}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  Returns the user for a correct password, `nil` for an incorrect one, and
  `nil` (via `Bcrypt.no_user_verify/0`, to avoid a timing side-channel) when
  no user matches the email at all.

  ## Examples

      iex> get_user_by_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## Owner registration (D-01, D-02, D-03, D-04)

  @doc """
  Returns `true` once an owner account exists, `false` on an empty database.

  This is the property `/setup` (`Playstead.Setup`) uses to decide whether
  to render the wizard or 404 permanently (D-03).
  """
  def owner_exists? do
    Repo.exists?(from u in User, where: u.role == :owner)
  end

  @doc """
  Creates the owner account.

  The resulting user's `role` is `:owner` and `confirmed_at` is set at
  creation — there is no confirmation email to wait on (D-02). This is
  called exactly once, from inside `Playstead.Setup.claim/2`'s
  once-only transaction.

  ## Examples

      iex> register_owner(%{email: "owner@example.com", password: "a very long password"})
      {:ok, %User{}}

      iex> register_owner(%{email: "invalid", password: "short"})
      {:error, %Ecto.Changeset{}}

  """
  def register_owner(attrs) do
    %User{}
    |> User.owner_registration_changeset(attrs)
    |> Repo.insert()
  end

  ## Recovery codes (D-05b)

  @doc """
  Generates `count` single-use recovery codes for `user` (default 10),
  each stored as its own bcrypt-hashed row so codes can be consumed
  independently. Returns the plaintext codes — this is the ONLY public
  function that ever does; there is no later retrieval path.

  Called once, inside `Playstead.Setup.claim/2`'s transaction.
  """
  def generate_recovery_codes(user, count \\ 10) do
    for _ <- 1..count do
      code = Playstead.Codes.random_code()

      %RecoveryCode{user_id: user.id, code_hash: Bcrypt.hash_pwd_salt(code)}
      |> Repo.insert!()

      code
    end
  end

  @doc """
  Consumes a single-use recovery code for `user`. Returns `{:ok, user}` and
  permanently marks the matching row consumed, or `{:error, :invalid_code}`
  for a wrong or already-consumed code. Calls `Bcrypt.no_user_verify/0` on
  the no-match path to avoid a timing side-channel between "wrong code"
  and "no unconsumed codes left".
  """
  def consume_recovery_code(user, code) when is_binary(code) do
    candidate =
      RecoveryCode
      |> where([r], r.user_id == ^user.id and is_nil(r.consumed_at))
      |> Repo.all()
      |> Enum.find(&Bcrypt.verify_pass(code, &1.code_hash))

    case candidate do
      nil ->
        Bcrypt.no_user_verify()
        {:error, :invalid_code}

      row ->
        {count, _} =
          Repo.update_all(
            from(r in RecoveryCode, where: r.id == ^row.id and is_nil(r.consumed_at)),
            set: [consumed_at: DateTime.utc_now(:second)]
          )

        if count == 1, do: {:ok, user}, else: {:error, :invalid_code}
    end
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Playstead.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  Used by plan 01-03's email-free recovery paths (the release-command reset
  and recovery-code login) — not yet wired to a route in this plan.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end
end
