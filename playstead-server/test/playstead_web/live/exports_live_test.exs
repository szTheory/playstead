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

    html = lv |> element("#export-library") |> render_click()
    assert html =~ "Writing your games as files"

    [export] = Export.list_exports(scope.user.id)
    assert :ok = perform_job(Worker, %{"export_id" => export.id})

    html = render(lv)
    assert html =~ export.target_name
  end
end
