defmodule PlaysteadWeb.StaticFontsTest do
  use PlaysteadWeb.ConnCase, async: true

  # 01-UI-SPEC: Inter and JetBrains Mono are part of the contract (JetBrains
  # Mono is a correctness requirement for character-by-character code
  # comparison), so the server must ship them itself — no system-font or
  # CDN dependency. The browser suite proves they load; this proves they
  # are served at all, from `priv/static/fonts` via `Plug.Static`.
  @fonts ~w(InterVariable.woff2 JetBrainsMono-Regular.woff2 JetBrainsMono-SemiBold.woff2)

  for font <- @fonts do
    test "serves /fonts/#{font} as font/woff2 without authentication", %{conn: conn} do
      conn = get(conn, "/fonts/#{unquote(font)}")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["font/woff2"]
      assert byte_size(conn.resp_body) > 10_000
    end
  end

  test "every @font-face in app.css points at a font that is actually shipped" do
    css = File.read!("assets/css/app.css")

    referenced =
      Regex.scan(~r|url\("/fonts/([^"]+)"\)|, css)
      |> Enum.map(fn [_, file] -> file end)

    assert referenced != []

    for file <- referenced do
      assert File.exists?(Path.join("priv/static/fonts", file)),
             "app.css references /fonts/#{file} but priv/static/fonts/#{file} is missing"
    end
  end

  test "the vendored fonts ship with their OFL licenses" do
    assert File.exists?("priv/static/fonts/LICENSE-Inter.txt")
    assert File.exists?("priv/static/fonts/LICENSE-JetBrainsMono.txt")
  end
end
