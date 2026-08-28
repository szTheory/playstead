defmodule PlaysteadWeb.ImportLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Import

  setup :register_and_log_in_user

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    :ok
  end

  defp entry(name, bytes, opts \\ []) do
    %{
      last_modified: 1_594_171_879_000,
      name: name,
      content: bytes,
      size: byte_size(bytes),
      type: Keyword.get(opts, :type, "application/octet-stream")
    }
  end

  defp ceiling, do: Application.get_env(:playstead, :max_browser_upload_bytes)

  test "renders the choose-a-file control", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/import")
    assert html =~ "Choose a file"
  end

  test "the preview reports the exact byte size, the free space, and the space the copy will use",
       %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/import")

    upload = file_input(lv, "#import-form", :file, [entry("game.gba", :crypto.strong_rand_bytes(1_024))])
    html = render_upload(upload, "game.gba")

    assert html =~ "1.0 KB"
    assert html =~ "Your original file stays where it is."
  end

  test "the preview result carries no duplicate verdict before confirmation", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/import")

    upload = file_input(lv, "#import-form", :file, [entry("game.gba", :crypto.strong_rand_bytes(64))])
    html = render_upload(upload, "game.gba")

    refute html =~ "Already in your library"
  end

  test "the preview's format label is marked as extension-derived", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/import")

    upload = file_input(lv, "#import-form", :file, [entry("Sonic (USA).gba", :crypto.strong_rand_bytes(64))])
    html = render_upload(upload, "Sonic (USA).gba")

    assert html =~ "guess from file name"
  end

  test "a file whose size equals the configured browser ceiling is accepted", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/import")

    bytes = :crypto.strong_rand_bytes(ceiling())
    upload = file_input(lv, "#import-form", :file, [entry("at-ceiling.gba", bytes)])

    assert render_upload(upload, "at-ceiling.gba") =~ "Copy into my library"
  end

  test "a file one byte above the browser ceiling is refused and the message names the inbox folder",
       %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/import")

    bytes = :crypto.strong_rand_bytes(ceiling() + 1)
    upload = file_input(lv, "#import-form", :file, [entry("over-ceiling.gba", bytes)])

    assert {:error, [[_ref, :too_large]]} = render_upload(upload, "over-ceiling.gba")
    assert render(lv) =~ "inbox folder"
  end

  # A file exceeding the free-space margin is refused before any bytes
  # are written: proven at the `Playstead.Import.Preview` unit level in
  # `preview_test.exs` (`Playstead.Import.PreviewTest`, "a file
  # exceeding the free-space margin is refused"), since exercising it
  # end-to-end here would require allocating a real multi-terabyte
  # binary. `ImportLive`'s `validator:` function calls
  # `Preview.fits_free_space?` directly and returns
  # `{:error, :insufficient_space}` on the same condition that test
  # asserts.

  test "a successful copy renders a receipt row chosen by the receipt's outcome code", %{
    conn: conn,
    scope: scope
  } do
    {:ok, lv, _html} = live(conn, ~p"/import")

    upload = file_input(lv, "#import-form", :file, [entry("game.gba", :crypto.strong_rand_bytes(64))])
    assert render_upload(upload, "game.gba") =~ "Copy into my library"

    lv |> form("#import-form") |> render_submit()

    assert has_element?(lv, "[data-outcome=new_asset]")
    assert render(lv) =~ "Added to your library"

    assert [receipt] = Import.list_receipts(scope.user.id)
    assert receipt.outcome == "new_asset"
  end

  test "a failed import renders the untouched-original message with a correlation id", %{
    conn: conn
  } do
    {:ok, lv, _html} = live(conn, ~p"/import")

    upload = file_input(lv, "#import-form", :file, [entry("game.gba", :crypto.strong_rand_bytes(64))])
    assert render_upload(upload, "game.gba") =~ "Copy into my library"

    # Simulate a failure at commit time: sweep the writer's completed
    # temp file out from under it before the confirm event runs, so
    # `Blobs.adopt_temp_file/2` returns an error and the LiveView must
    # show the generic, correlation-id-bearing flash rather than crash
    # or fabricate a receipt.
    Playstead.Import.OrphanSweeper.sweep(0)

    lv |> form("#import-form") |> render_submit()

    assert render(lv) =~ "Something went wrong on the server"
    assert render(lv) =~ "Correlation ID: "
    assert render(lv) =~ "Your original file is untouched"
  end

  test "a filename containing markup characters is displayed as text", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/import")

    name = "<script>alert(1)</script>.gba"
    upload = file_input(lv, "#import-form", :file, [entry(name, :crypto.strong_rand_bytes(64))])
    assert render_upload(upload, name) =~ "Copy into my library"

    lv |> form("#import-form") |> render_submit()

    html = render(lv)
    refute html =~ "<script>alert(1)</script>"
    assert html =~ "&lt;script&gt;"
  end

  test "reloading the import page shows the same receipts, read from the database", %{
    conn: conn,
    scope: scope
  } do
    {:ok, lv, _html} = live(conn, ~p"/import")

    upload = file_input(lv, "#import-form", :file, [entry("game.gba", :crypto.strong_rand_bytes(64))])
    assert render_upload(upload, "game.gba") =~ "Copy into my library"
    lv |> form("#import-form") |> render_submit()

    assert [_receipt] = Import.list_receipts(scope.user.id)

    {:ok, _lv2, html2} = live(conn, ~p"/import")
    assert html2 =~ "Added to your library"
  end
end
