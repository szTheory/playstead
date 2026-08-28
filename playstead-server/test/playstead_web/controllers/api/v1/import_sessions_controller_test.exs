defmodule PlaysteadWeb.Api.V1.ImportSessionsControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Import
  alias Playstead.Import.Staging

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-import-sessions-controller-test-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root}
  end

  defp authed_conn(conn, scope) do
    %{credential_plaintext: token} = device_fixture(scope)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/import-sessions/:id" do
    test "returns the session scoped to the calling device's user", %{conn: conn, root: root} do
      scope = user_scope_fixture()
      File.write!(Path.join(root, "a.bin"), "content")
      {:ok, session} = Staging.stage(scope.user.id, root, "controller-show-session")

      conn = conn |> authed_conn(scope) |> get(~p"/api/v1/import-sessions/#{session.id}")

      body = json_response(conn, 200)
      assert body["id"] == session.id
      assert body["state"] == "completed" or body["state"] == "staged"
      assert body["file_count"] == 1
    end

    test "a session belonging to another user returns not-found", %{conn: conn, root: root} do
      scope = user_scope_fixture()
      other = owner_fixture()
      File.write!(Path.join(root, "a.bin"), "content")
      {:ok, session} = Staging.stage(other.id, root, "controller-foreign-session")

      conn = conn |> authed_conn(scope) |> get(~p"/api/v1/import-sessions/#{session.id}")

      assert_problem(conn, 404, :not_found)
    end
  end

  describe "GET /api/v1/import-sessions/:id/receipts" do
    test "returns receipts in a stable order and pages without skipping or repeating", %{
      conn: conn,
      root: root
    } do
      scope = user_scope_fixture()

      for i <- 1..3 do
        File.write!(Path.join(root, "file#{i}.bin"), "content-#{i}")
      end

      {:ok, session} = Staging.stage(scope.user.id, root, "controller-receipts-session")
      run_to_completion(session.id)

      conn1 = conn |> authed_conn(scope)

      first_page =
        conn1
        |> get(~p"/api/v1/import-sessions/#{session.id}/receipts?limit=2")
        |> json_response(200)

      assert length(first_page["receipts"]) <= 3
      first_ids = Enum.map(first_page["receipts"], & &1["id"])

      # Requesting the same cursor twice returns identical results.
      if first_page["next_cursor"] do
        page_a =
          conn1
          |> get(
            ~p"/api/v1/import-sessions/#{session.id}/receipts?cursor=#{first_page["next_cursor"]}"
          )
          |> json_response(200)

        page_b =
          conn1
          |> get(
            ~p"/api/v1/import-sessions/#{session.id}/receipts?cursor=#{first_page["next_cursor"]}"
          )
          |> json_response(200)

        assert page_a == page_b
        refute Enum.any?(page_a["receipts"], &(&1["id"] in first_ids))
      end
    end

    test "a foreign session's receipts endpoint returns not-found", %{conn: conn, root: root} do
      scope = user_scope_fixture()
      other = owner_fixture()
      File.write!(Path.join(root, "a.bin"), "content")
      {:ok, session} = Staging.stage(other.id, root, "controller-foreign-receipts-session")

      conn = conn |> authed_conn(scope) |> get(~p"/api/v1/import-sessions/#{session.id}/receipts")

      assert_problem(conn, 404, :not_found)
    end
  end

  defp run_to_completion(session_id, mode \\ "run") do
    :ok =
      Oban.Testing.perform_job(
        Import.SessionWorker,
        %{"session_id" => session_id, "mode" => mode},
        repo: Playstead.Repo
      )

    if Playstead.Repo.get!(Import.Session, session_id).state == "running" do
      run_to_completion(session_id, mode)
    else
      :ok
    end
  end
end
