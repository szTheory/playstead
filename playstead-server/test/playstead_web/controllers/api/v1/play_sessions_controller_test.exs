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

  # P6-WR-001: every other curation controller test file has an explicit
  # cross-user negative test for its mutating endpoints; this one only
  # covered POST. `delete_play_session/2` already scopes its lookup by
  # both `id` and `user_id` (Repo.get_by(PlaySession, id: session_id,
  # user_id: user_id)) and, like every other delete-shaped curation
  # endpoint (remove_favorite/2, dequeue/2), treats "no matching row"
  # as an idempotent no-op success rather than a distinguishable 404 —
  # so the response here is 200, matching that established pattern.
  # The invariant this test protects is that the other user's row is
  # actually left untouched, not merely that the HTTP status is some
  # particular code: if this ever regressed to authorizing by id alone
  # (dropping the `user_id` scope), the session would actually be
  # deleted here and this assertion would catch it.
  test "DELETE for another user's play session does not delete their row", %{conn: conn} do
    {_scope, _device, token} = paired()
    other = owner_fixture()
    other_asset_set = asset_set_fixture(other.id)

    {:ok, other_session} =
      Curation.record_play_session(other.id, %{
        id: Ecto.UUID.generate(),
        asset_set_id: other_asset_set.id,
        started_at: DateTime.utc_now()
      })

    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", unique_key("del"))
      |> delete(~p"/api/v1/play-sessions/#{other_session.id}")

    other_asset_set_id = other_asset_set.id

    assert json_response(resp, 200)
    assert [%{asset_set_id: ^other_asset_set_id}] = Curation.list_recent(other.id)
  end
end
