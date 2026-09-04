defmodule PlaysteadWeb.ExportsLiveTest do
  use PlaysteadWeb.ConnCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Phoenix.LiveViewTest

  alias Playstead.Export
  alias Playstead.Export.Worker

  setup :register_and_log_in_user

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  test "shows an empty state with no exports yet", %{conn: conn} do
    {:ok, _lv, html} = live(conn, ~p"/exports")
    assert html =~ "No exports yet"
  end

  test "the page states plainly that a same-disk copy is not a backup, never that an export is safe",
       %{
         conn: conn
       } do
    {:ok, _lv, html} = live(conn, ~p"/exports")
    assert html =~ "is not a backup"
    refute html =~ "is safe"
  end

  test "exporting the whole library shows it in the export history", %{conn: conn, scope: scope} do
    {:ok, lv, _html} = live(conn, ~p"/exports")

    html = lv |> form("#export-actions form") |> render_submit()
    assert html =~ "Writing your games as files"

    [export] = Export.list_exports(scope.user.id)
    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    html = render(lv)
    assert html =~ export.target_name
  end

  describe "the saves-scope control (D-57, plan 04-10)" do
    test "the saves-scope control appears exactly once on the exports surface", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/exports")

      assert Regex.scan(~r/id="saves-scope-select"/, html) |> length() == 1
    end

    test "it defaults to all-revisions scope", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/exports")

      assert html =~ ~r/<option value="all"[^>]*>All save versions<\/option>/
    end

    test "choosing a scope persists it on the enqueued ExportRecord, and a re-enqueue reproduces it",
         %{conn: conn, scope: scope} do
      {:ok, lv, _html} = live(conn, ~p"/exports")

      lv
      |> form("#export-actions form", %{saves_scope: "none"})
      |> render_submit()

      [export] = Export.list_exports(scope.user.id)
      assert export.saves_scope == "none"

      # Re-enqueuing (the worker re-running against the same export_id,
      # e.g. after a crash or a retry) reads the persisted scope again
      # rather than a default -- the scope survives the round trip.
      assert :ok = perform_job(Worker, %{"export_id" => export.id})
      reloaded = Export.get_export(scope.user.id, export.id)
      assert reloaded.saves_scope == "none"
    end
  end
end
