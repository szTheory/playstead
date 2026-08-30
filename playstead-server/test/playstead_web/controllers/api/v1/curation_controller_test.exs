defmodule PlaysteadWeb.Api.V1.CurationControllerTest do
  @moduledoc """
  Plan 03-04 task 1: the idempotent REST intent for favorites.
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

  defp favorite!(conn, token, asset_set_id, idempotency_key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> put(~p"/api/v1/curation/favorites/#{asset_set_id}", %{})
  end

  defp unfavorite!(conn, token, asset_set_id, idempotency_key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> delete(~p"/api/v1/curation/favorites/#{asset_set_id}")
  end

  defp unique_key(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "PUT favorites/:asset_set_id creates a favorite and journal entry", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    resp = favorite!(conn, token, asset_set.id, unique_key("fav"))
    body = json_response(resp, 200)

    assert body["asset_set_id"] == asset_set.id
    assert [_] = Curation.list_favorites(scope.user.id)
  end

  test "repeating the request with the same Idempotency-Key produces no second effect", %{
    conn: conn
  } do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    key = unique_key("fav")

    resp1 = favorite!(conn, token, asset_set.id, key)
    body1 = json_response(resp1, 200)

    resp2 = favorite!(conn, token, asset_set.id, key)
    body2 = json_response(resp2, 200)

    assert body1 == body2
    assert [_] = Curation.list_favorites(scope.user.id)
  end

  test "DELETE favorites/:asset_set_id removes the favorite", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    _ = favorite!(conn, token, asset_set.id, unique_key("fav"))

    resp = unfavorite!(conn, token, asset_set.id, unique_key("unfav"))
    assert json_response(resp, 200)

    assert Curation.list_favorites(scope.user.id) == []
  end

  test "favoriting another user's asset set returns 404", %{conn: conn} do
    {_scope, _device, token} = paired()
    other = owner_fixture()
    asset_set = asset_set_fixture(other.id)

    resp = favorite!(conn, token, asset_set.id, unique_key("fav"))
    assert_problem(resp, 404, :not_found)
  end

  test "GET /api/v1/snapshot includes the curation branch with favorites", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    _ = favorite!(conn, token, asset_set.id, unique_key("fav"))

    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/snapshot")

    body = json_response(resp, 200)
    assert [entry] = body["curation"]
    assert entry["type"] == "favorite"
    assert entry["asset_set_id"] == asset_set.id
  end

  test "GET /api/v1/snapshot has an empty curation branch for a user with no curation rows", %{
    conn: conn
  } do
    {_scope, _device, token} = paired()

    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/snapshot")

    body = json_response(resp, 200)
    assert body["curation"] == []
  end
end
