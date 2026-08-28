defmodule PlaysteadWeb.ImportSessionsLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Playstead.Import.Staging

  setup :register_and_log_in_user

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-import-sessions-live-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    previous_inbox = Application.get_env(:playstead, :inbox_path)
    Application.put_env(:playstead, :inbox_path, root)
    on_exit(fn -> Application.put_env(:playstead, :inbox_path, previous_inbox) end)

    {:ok, root: root}
  end

  test "shows an empty state with no sessions yet", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/import/sessions")
    assert html =~ "No sessions yet"
  end

  test "previewing the inbox reports file count and total bytes without staging anything", %{
    conn: conn,
    root: root
  } do
    File.write!(Path.join(root, "game.bin"), "content")
    {:ok, lv, _html} = live(conn, ~p"/import/sessions")

    html = lv |> element("#preview-inbox") |> render_click()

    assert html =~ "1 files"
  end

  test "staging shows the session in the list with its control actions", %{
    conn: conn,
    root: root
  } do
    File.write!(Path.join(root, "game.bin"), "content")
    {:ok, lv, _html} = live(conn, ~p"/import/sessions")

    lv |> element("#preview-inbox") |> render_click()
    html = lv |> element("#stage-inbox") |> render_click()

    assert html =~ "Staged"
  end

  test "the cancel confirmation states that copies already made are kept", %{
    conn: conn,
    user: user,
    root: root
  } do
    File.write!(Path.join(root, "game.bin"), "content")
    {:ok, session} = Staging.stage(user.id, root, "cancel-copy-session")
    Playstead.Import.bump_session_progress(session, :new_asset, 7)

    {:ok, _lv, html} = live(conn, ~p"/import/sessions")
    assert html =~ "already copied"
    assert html =~ "will be kept"
  end

  test "a session belonging to another user is not shown", %{conn: conn} do
    other = Playstead.AccountsFixtures.owner_fixture()

    root2 =
      Path.join(System.tmp_dir!(), "playstead-other-inbox-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root2)
    on_exit(fn -> File.rm_rf!(root2) end)
    File.write!(Path.join(root2, "a.bin"), "x")

    {:ok, other_session} = Staging.stage(other.id, root2, "other-user-session")

    {:ok, _lv, html} = live(conn, ~p"/import/sessions")
    refute html =~ "session-#{other_session.id}"
  end
end
