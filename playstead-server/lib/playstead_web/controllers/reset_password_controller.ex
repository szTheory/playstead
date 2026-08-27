defmodule PlaysteadWeb.ResetPasswordController do
  @moduledoc """
  Consumes the single-use `:password_reset` token minted by
  `Playstead.Release.reset_owner_password/0` (D-05a). A second visit or an
  expired token is rejected with the same generic copy — see
  `Playstead.Accounts.reset_password_with_token/2`.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Accounts

  def edit(conn, %{"token" => token}) do
    render_form(conn, token, nil)
  end

  def update(conn, %{"token" => token, "user" => user_params}) do
    case Accounts.reset_password_with_token(token, user_params) do
      {:ok, {_user, _expired_tokens}} ->
        conn
        |> put_flash(:info, "Password reset. You can log in with your new password now.")
        |> redirect(to: ~p"/log-in")

      {:error, :invalid_or_expired} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render_error(
          "This reset link has expired or was already used. Run the reset command again."
        )

      {:error, %Ecto.Changeset{}} ->
        render_form(conn, token, "That password didn't meet the requirements. Try again.")
    end
  end

  defp render_form(conn, token, error) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, form_html(token, error))
  end

  defp render_error(conn, message) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(:unprocessable_entity, error_html(message))
  end

  defp form_html(token, error) do
    """
    <!DOCTYPE html>
    <html><head><title>Reset password</title></head>
    <body style="background:#0F172A;color:#F1F5F9;font-family:Inter,sans-serif;display:flex;align-items:center;justify-content:center;min-height:100vh;margin:0;">
      <div style="width:100%;max-width:28rem;background:#1E293B;padding:2rem;border-radius:0.5rem;">
        <h1>Reset your password</h1>
        #{if error, do: "<p style=\"color:#EF4444;\">#{Phoenix.HTML.html_escape(error) |> Phoenix.HTML.safe_to_string()}</p>", else: ""}
        <form method="post" action="/reset/#{Phoenix.HTML.html_escape(token) |> Phoenix.HTML.safe_to_string()}">
          <input type="hidden" name="_csrf_token" value="#{Plug.CSRFProtection.get_csrf_token()}" />
          <label>New password<br/><input type="password" name="user[password]" autocomplete="new-password" required minlength="12" /></label><br/><br/>
          <label>Confirm password<br/><input type="password" name="user[password_confirmation]" autocomplete="new-password" required minlength="12" /></label><br/><br/>
          <button type="submit">Set new password</button>
        </form>
      </div>
    </body></html>
    """
  end

  defp error_html(message) do
    """
    <!DOCTYPE html>
    <html><head><title>Reset password</title></head>
    <body style="background:#0F172A;color:#F1F5F9;font-family:Inter,sans-serif;">
      <p>#{Phoenix.HTML.html_escape(message) |> Phoenix.HTML.safe_to_string()}</p>
      <p><a href="/log-in" style="color:#38BDF8;">Back to log in</a></p>
    </body></html>
    """
  end
end
