defmodule PlaysteadWeb.UserSessionController do
  use PlaysteadWeb, :controller

  alias Playstead.Accounts
  alias PlaysteadWeb.UserAuth

  @doc """
  Password login (D-02, no magic link) and, when the requester is already
  authenticated as the same user, sudo-mode re-confirmation (D-06) — this
  is exactly the credential check `PlaysteadWeb.SudoLive` posts here, with
  a `user[return_to]` hidden field carrying the pending action back.

  Generic failure copy per UI-SPEC (does not distinguish an unknown email
  from a wrong password, to avoid user enumeration).
  """
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params
    already_authenticated_user = conn.assigns[:current_scope] && conn.assigns.current_scope.user

    if user = Accounts.get_user_by_password(email, password) do
      # A `return_to` from the sudo form wins; an absent/empty one must not
      # clobber the target `PlaysteadWeb.Plugs.SudoMode` already stored.
      conn =
        case user_params["return_to"] do
          return_to when is_binary(return_to) and return_to != "" ->
            put_session(conn, :user_return_to, return_to)

          _ ->
            conn
        end

      if already_authenticated_user && already_authenticated_user.id == user.id do
        Playstead.AuditLog.record(user.id, :sudo_confirmed, %{})
      end

      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
    else
      if already_authenticated_user do
        conn
        |> put_flash(
          :error,
          "That password didn't match."
        )
        |> redirect(to: ~p"/sudo")
      else
        conn
        |> put_flash(
          :error,
          "That password didn't match. Try again, or use the recovery option below if you're locked out."
        )
        |> put_flash(:email, String.slice(email, 0, 160))
        |> redirect(to: ~p"/log-in")
      end
    end
  end

  @doc """
  Logs in with a single-use recovery code instead of a password (D-05b).
  Single-owner in Phase 1, so the code is checked against "the" owner
  directly. Generic failure copy — does not reveal whether an owner
  account exists at all.
  """
  def create_via_recovery(conn, %{"recovery" => %{"code" => code}}) do
    with %Accounts.User{} = user <- Accounts.get_owner(),
         {:ok, user} <- Accounts.consume_recovery_code(user, code) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user)
    else
      _ ->
        conn
        |> put_flash(:error, "That recovery code didn't match, or was already used.")
        |> redirect(to: ~p"/log-in/recovery")
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
