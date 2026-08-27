defmodule PlaysteadWeb.UserSessionController do
  use PlaysteadWeb, :controller

  alias Playstead.Accounts
  alias PlaysteadWeb.UserAuth

  @doc """
  Password login only — D-02 strips every magic-link and email-confirmation
  code path. Generic failure copy per UI-SPEC (does not distinguish an
  unknown email from a wrong password, to avoid user enumeration).
  """
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_password(email, password) do
      conn
      |> put_flash(:info, "Welcome back!")
      |> UserAuth.log_in_user(user, user_params)
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

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
