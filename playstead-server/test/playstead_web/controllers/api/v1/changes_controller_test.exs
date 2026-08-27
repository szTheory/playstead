defmodule PlaysteadWeb.Api.V1.ChangesControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Pairing
  alias Playstead.Repo
  alias Playstead.Sync.{Compaction, Cursor, Entry}

  defp authed_conn(conn, token) do
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  describe "GET /api/v1/changes" do
    test "with no cursor returns the feed from the beginning with a next cursor", %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)
      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed")

      conn = conn |> authed_conn(token) |> get(~p"/api/v1/changes")

      assert %{"entries" => entries, "cursor" => cursor, "has_more" => false} =
               json_response(conn, 200)

      assert length(entries) >= 1
      assert is_binary(cursor)
      assert {:ok, _seq} = Cursor.decode(cursor)
    end

    test "with a valid cursor returns only entries after it, in order, with a next cursor", %{
      conn: conn
    } do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      conn1 = conn |> authed_conn(token) |> get(~p"/api/v1/changes")
      %{"cursor" => baseline_cursor} = json_response(conn1, 200)

      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed")

      conn2 = conn |> authed_conn(token) |> get(~p"/api/v1/changes?cursor=#{baseline_cursor}")
      assert %{"entries" => [entry], "has_more" => false} = json_response(conn2, 200)
      assert entry["entity_kind"] == "device"
      assert entry["payload"]["name"] == "Renamed"
    end

    test "two identical requests with the same cursor return identical bodies and change no server state",
         %{conn: conn} do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)
      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed")

      count_before = Repo.aggregate(Entry, :count)

      conn1 = conn |> authed_conn(token) |> get(~p"/api/v1/changes")
      body1 = json_response(conn1, 200)

      conn2 = conn |> authed_conn(token) |> get(~p"/api/v1/changes")
      body2 = json_response(conn2, 200)

      assert body1 == body2
      assert Repo.aggregate(Entry, :count) == count_before
    end

    test "a tampered cursor returns 400 with code cursor_invalid", %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      conn = conn |> authed_conn(token) |> get(~p"/api/v1/changes?cursor=not-a-real-cursor")

      assert_problem(conn, 400, :cursor_invalid)
    end

    test "a cursor before the compaction boundary returns 410 with code cursor_expired", %{
      conn: conn
    } do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      # A real cursor the client actually holds (not `nil` — a genuine
      # position from an earlier response).
      conn1 = conn |> authed_conn(token) |> get(~p"/api/v1/changes")
      %{"cursor" => stale_cursor} = json_response(conn1, 200)

      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed one")
      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed two")

      # Force every existing entry out of the retention window so the
      # compaction sweep removes them, moving the surviving boundary
      # past the stale cursor.
      old_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-(Compaction.horizon() + 1) * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      Repo.update_all(Entry, set: [inserted_at: old_timestamp])

      # Leave one fresh entry behind so there is a well-defined surviving boundary.
      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed three")

      {:ok, _removed} = Compaction.run()

      conn = conn |> authed_conn(token) |> get(~p"/api/v1/changes?cursor=#{stale_cursor}")

      assert_problem(conn, 410, :cursor_expired)
    end

    test "a cursor exactly at the surviving boundary still returns 200 after compaction runs", %{
      conn: conn
    } do
      scope = user_scope_fixture()
      %{device: device, credential_plaintext: token} = device_fixture(scope)

      conn1 = conn |> authed_conn(token) |> get(~p"/api/v1/changes")
      %{"cursor" => surviving_boundary_cursor} = json_response(conn1, 200)

      {:ok, _} = Pairing.rename_device(scope, device.id, "Renamed")

      old_timestamp =
        DateTime.utc_now()
        |> DateTime.add(-(Compaction.horizon() + 1) * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)

      {:ok, seq} = Cursor.decode(surviving_boundary_cursor)

      from(e in Entry, where: e.seq < ^seq)
      |> Repo.update_all(set: [inserted_at: old_timestamp])

      {:ok, _removed} = Compaction.run()

      conn2 =
        conn |> authed_conn(token) |> get(~p"/api/v1/changes?cursor=#{surviving_boundary_cursor}")

      assert %{"entries" => [_entry], "has_more" => false} = json_response(conn2, 200)
    end

    test "writes no rows to any table", %{conn: conn} do
      scope = user_scope_fixture()
      %{credential_plaintext: token} = device_fixture(scope)

      count_before = Repo.aggregate(Entry, :count)
      conn |> authed_conn(token) |> get(~p"/api/v1/changes")
      assert Repo.aggregate(Entry, :count) == count_before
    end
  end
end
