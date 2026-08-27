defmodule PlaysteadWeb.RecoveryCodesController do
  @moduledoc """
  Regenerates the owner's recovery codes (D-05b). Reachable only through
  the `:require_sudo` pipeline (see `PlaysteadWeb.Router`) — the
  destructive-confirmation copy lives client-side per the UI-SPEC
  Copywriting Contract; this action performs the regeneration itself.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Accounts

  def regenerate(conn, _params) do
    user = conn.assigns.current_scope.user
    codes = Accounts.regenerate_recovery_codes(user)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, codes_html(codes))
  end

  defp codes_html({:ok, codes}) do
    items = Enum.map_join(codes, "", &"<li><code>#{&1}</code></li>")

    """
    <!DOCTYPE html>
    <html><head><title>New recovery codes</title></head>
    <body style="background:#0F172A;color:#F1F5F9;font-family:Inter,sans-serif;">
      <h1>Your new recovery codes</h1>
      <p>Save these somewhere safe — they are shown only once. Your old codes no longer work.</p>
      <ul style="font-family:'JetBrains Mono',monospace;">#{items}</ul>
      <p><a href="/settings/sessions" style="color:#38BDF8;">Back to Sessions</a></p>
    </body></html>
    """
  end
end
