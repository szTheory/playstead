defmodule Playstead.AccountsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Playstead.Accounts` context.

  D-02: there is no magic-link or email-confirmation flow to fixture here —
  `owner_fixture/1` creates a fully confirmed owner directly, the same way
  `Playstead.Setup.claim/2` does.
  """

  import Ecto.Query

  alias Playstead.Accounts
  alias Playstead.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"
  def valid_user_password, do: "hello world!"

  def valid_owner_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      email: unique_user_email(),
      password: valid_user_password(),
      password_confirmation: valid_user_password()
    })
  end

  @doc """
  Registers an owner account directly (the same path `Playstead.Setup.claim/2`
  uses). `confirmed_at` is set at creation — there is no confirmation step.
  """
  def owner_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_owner_attributes()
      |> Accounts.register_owner()

    user
  end

  def user_scope_fixture do
    user = owner_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def set_password(user) do
    {:ok, {user, _expired_tokens}} =
      Accounts.update_user_password(user, %{password: valid_user_password()})

    user
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Playstead.Repo.update_all(
      from(t in Accounts.UserToken,
        where: t.token == ^token
      ),
      set: [authenticated_at: authenticated_at]
    )
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Playstead.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end
end
