defmodule PlaysteadWeb.RecoveryDocsControllerTest do
  use PlaysteadWeb.ConnCase, async: true

  test "GET /docs/recovery serves the live docs/RECOVERY.md as markdown, unauthenticated", %{
    conn: conn
  } do
    expected_body = File.read!(Path.join(File.cwd!(), "docs/RECOVERY.md"))

    conn = get(conn, ~p"/docs/recovery")

    assert conn.status == 200

    assert conn
           |> get_resp_header("content-type")
           |> Enum.any?(&String.contains?(&1, "text/markdown")),
           "expected a text/markdown content type"

    # Proves the served bytes are the file's bytes, not a fixture that can drift.
    assert conn.resp_body == expected_body

    assert conn.resp_body =~ "Locked out?"
    assert conn.resp_body =~ "docker compose exec app bin/playstead eval"
  end
end
