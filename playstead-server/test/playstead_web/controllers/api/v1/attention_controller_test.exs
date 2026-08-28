defmodule PlaysteadWeb.Api.V1.AttentionControllerTest do
  @moduledoc """
  D-30: the cursor-paginated attention list and the idempotent resolve
  endpoint. Scoping is strict enough that a foreign item is refused as
  not-found, never forbidden (T-02-41).
  """
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Attention
  alias Playstead.Blobs
  alias Playstead.Import

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp authed_conn(conn, scope) do
    %{credential_plaintext: token} = device_fixture(scope)
    put_req_header(conn, "authorization", "Bearer #{token}")
  end

  defp fabricate_item(scope) do
    bytes = :crypto.strong_rand_bytes(64)
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        scope.user.id,
        %{original_name: "big.bin", origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta},
        format_bytes: bytes,
        quarantine_size_cap_bytes: 10
      )

    Attention.list_items(scope.user.id)
    |> Map.fetch!("quarantined")
    |> hd()
    |> Map.put(:receipt, receipt)
  end

  describe "GET /api/v1/attention" do
    test "lists items scoped to the calling user, cursor-paginated", %{conn: conn} do
      scope = user_scope_fixture()
      item = fabricate_item(scope)

      conn = conn |> authed_conn(scope) |> get(~p"/api/v1/attention")
      body = json_response(conn, 200)

      assert Enum.any?(body["items"], &(&1["id"] == item.id))
    end

    test "requesting the same cursor twice returns an identical body", %{conn: conn} do
      scope = user_scope_fixture()
      fabricate_item(scope)

      conn1 = conn |> authed_conn(scope) |> get(~p"/api/v1/attention")
      body1 = json_response(conn1, 200)

      conn2 = conn |> authed_conn(scope) |> get(~p"/api/v1/attention")
      body2 = json_response(conn2, 200)

      assert body1 == body2
    end
  end

  describe "POST /api/v1/attention/:id/resolve" do
    test "excluding an item via the API resolves it", %{conn: conn} do
      scope = user_scope_fixture()
      item = fabricate_item(scope)

      conn =
        conn
        |> authed_conn(scope)
        |> put_req_header("idempotency-key", "resolve-#{System.unique_integer([:positive])}")
        |> post(~p"/api/v1/attention/#{item.id}/resolve", %{"resolution" => "retain_as_custom"})

      body = json_response(conn, 200)
      assert body["status"] == "ok"
    end

    test "a repeated resolve with the same idempotency key returns the original receipt", %{
      conn: conn
    } do
      scope = user_scope_fixture()
      item = fabricate_item(scope)
      key = "resolve-#{System.unique_integer([:positive])}"
      %{credential_plaintext: token} = device_fixture(scope)

      conn1 =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("idempotency-key", key)
        |> post(~p"/api/v1/attention/#{item.id}/resolve", %{"resolution" => "retain_as_custom"})

      body1 = json_response(conn1, 200)

      conn2 =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("idempotency-key", key)
        |> post(~p"/api/v1/attention/#{item.id}/resolve", %{"resolution" => "retain_as_custom"})

      body2 = json_response(conn2, 200)
      assert body1 == body2
    end

    test "resolving another user's item returns not-found", %{conn: conn} do
      scope = user_scope_fixture()
      other_scope = user_scope_fixture()
      item = fabricate_item(other_scope)

      conn =
        conn
        |> authed_conn(scope)
        |> put_req_header("idempotency-key", "resolve-#{System.unique_integer([:positive])}")
        |> post(~p"/api/v1/attention/#{item.id}/resolve", %{"resolution" => "retain_as_custom"})

      assert_problem(conn, 404, :not_found)
    end
  end
end
