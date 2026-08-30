defmodule PlaysteadWeb.Api.V1.PlaySessionsControllerTest do
  @moduledoc """
  Plan 03-04 task 3: the idempotent play-session REST intent (D-07).
  """

  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Curation

  defp paired do
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)
    {scope, device, token}
  end

  defp unique_key(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  defp post_session!(conn, token, params, idempotency_key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> post(~p"/api/v1/play-sessions", params)
  end

  test "POST creates a play session", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    resp =
      post_session!(
        conn,
        token,
        %{
          "asset_set_id" => asset_set.id,
          "started_at" => DateTime.to_iso8601(DateTime.utc_now())
        },
        unique_key("sess")
      )

    body = json_response(resp, 201)
    assert body["asset_set_id"] == asset_set.id
    assert [%{asset_set_id: _}] = Curation.list_recent(scope.user.id)
  end

  test "POST for another user's asset set returns 404", %{conn: conn} do
    {_scope, _device, token} = paired()
    other = owner_fixture()
    asset_set = asset_set_fixture(other.id)

    resp =
      post_session!(
        conn,
        token,
        %{
          "asset_set_id" => asset_set.id,
          "started_at" => DateTime.to_iso8601(DateTime.utc_now())
        },
        unique_key("sess")
      )

    assert_problem(resp, 404, :not_found)
  end

  test "DELETE removes a play session", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    create_resp =
      post_session!(
        conn,
        token,
        %{
          "asset_set_id" => asset_set.id,
          "started_at" => DateTime.to_iso8601(DateTime.utc_now())
        },
        unique_key("sess")
      )

    session_id = json_response(create_resp, 201)["id"]

    delete_resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", unique_key("del"))
      |> delete(~p"/api/v1/play-sessions/#{session_id}")

    assert json_response(delete_resp, 200)
    assert Curation.list_recent(scope.user.id) == []
  end
end
