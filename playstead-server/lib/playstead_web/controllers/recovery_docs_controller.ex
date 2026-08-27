defmodule PlaysteadWeb.RecoveryDocsController do
  @moduledoc """
  Serves `docs/RECOVERY.md` (D-05) at `/docs/recovery` — the destination
  of the login screen's "Locked out?" link.
  """

  use PlaysteadWeb, :controller

  # Compiled directly into the module so this route works unchanged from a
  # release, where `docs/` (unlike `priv/`) isn't necessarily copied
  # alongside the release's own file layout.
  @recovery_doc File.read!(Path.join(File.cwd!(), "docs/RECOVERY.md"))

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/markdown")
    |> send_resp(200, @recovery_doc)
  end
end
