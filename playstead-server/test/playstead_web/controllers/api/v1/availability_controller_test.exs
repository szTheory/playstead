defmodule PlaysteadWeb.Api.V1.AvailabilityControllerTest do
  @moduledoc """
  Plan 03-13 (LIBR-02 gap closure): `PUT /api/v1/devices/me/availability`.
  """

  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Availability

  defp paired do
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)
    {scope, device, token}
  end

  defp report!(conn, token, entries, idempotency_key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> put(~p"/api/v1/devices/me/availability", %{"entries" => entries})
  end

  defp unique_key(prefix), do: "#{prefix}-#{System.unique_integer([:positive])}"

  test "PUT devices/me/availability stores the reported facts", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    entries = [%{"asset_set_id" => asset_set.id, "verified" => true, "download_percent" => 100}]
    resp = report!(conn, token, entries, unique_key("avail"))

    assert json_response(resp, 200)

    facts = Availability.facts_for_user(scope.user.id)
    assert facts[asset_set.id].verified == true
  end

  test "repeating the request with the same Idempotency-Key produces one stored row set", %{
    conn: conn
  } do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    key = unique_key("avail")

    entries = [%{"asset_set_id" => asset_set.id, "verified" => true}]

    resp1 = report!(conn, token, entries, key)
    body1 = json_response(resp1, 200)

    resp2 = report!(conn, token, entries, key)
    body2 = json_response(resp2, 200)

    assert body1 == body2
    facts = Availability.facts_for_user(scope.user.id)
    assert map_size(facts) == 1
  end

  test "requires authentication", %{conn: conn} do
    resp =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", unique_key("avail"))
      |> put(~p"/api/v1/devices/me/availability", %{"entries" => []})

    assert resp.status in [401, 422]
  end

  test "an out-of-range download_percent is rejected with a validation error", %{conn: conn} do
    {scope, _device, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    entries = [%{"asset_set_id" => asset_set.id, "download_percent" => 150}]
    resp = report!(conn, token, entries, unique_key("avail"))

    assert_problem(resp, 422, :validation_failed)
  end
end
