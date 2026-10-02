defmodule Playstead.Operations.DiagnosticBundleTest do
  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Playstead.Operations.DiagnosticBundle
  alias Playstead.Repo

  @forbidden ~w(secret-rom-name.sfc /private/roms database://password auth-token cookie header emulator-output deadbeef)

  defp paired do
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)
    {device, token}
  end

  defp request_bundle(conn, token, params, key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", key)
    |> post(~p"/api/v1/operations/diagnostic-bundles", params)
  end

  defp request_bundle(conn, token, params),
    do: request_bundle(conn, token, params, "diagnostic-key")

  test "a failed diagnostic request reuses its boundary correlation ID in the RFC 9457 response",
       %{conn: conn} do
    {_device, token} = paired()

    response = request_bundle(conn, token, %{"correlation_id" => "missing-correlation"})
    problem = assert_problem(response, 404, :not_found)

    assert problem["correlation_id"] ==
             response |> Plug.Conn.get_resp_header("x-correlation-id") |> List.first()
  end

  test "a durable recovery record preserves a supplied opaque correlation ID" do
    correlation_id = Ecto.UUID.generate()

    destination =
      Path.join(System.tmp_dir!(), "playstead-diagnostic-#{System.unique_integer([:positive])}")

    assert {:ok, _record_id} =
             Playstead.Recovery.request_backup(%{
               destination: destination,
               kind: :full,
               correlation_id: correlation_id
             })

    assert {:ok, %{correlation_id: ^correlation_id, subsystem: "recovery", state: "planned"}} =
             DiagnosticBundle.for_correlation(correlation_id)
  end

  test "an owner receives only an allowlisted, bounded diagnostic projection and replay is durable",
       %{conn: conn} do
    {device, token} = paired()
    key = "diagnostic-#{System.unique_integer([:positive])}"

    response = request_bundle(conn, token, %{}, key)
    assert response.status == 201
    body = json_response(response, 201)
    encoded = Jason.encode!(body)

    assert body["schema"] == "playstead.diagnostic-bundle.v1"
    assert is_binary(body["expires_at"])
    assert byte_size(encoded) <= DiagnosticBundle.max_bytes()
    refute Enum.any?(@forbidden, &String.contains?(encoded, &1))

    replay = request_bundle(conn, token, %{}, key)
    assert replay.status == 201
    assert replay.resp_body == response.resp_body

    assert 1 =
             Repo.aggregate(
               from(r in Playstead.Idempotency.Receipt,
                 where: r.device_id == ^device.id and r.idempotency_key == ^key
               ),
               :count
             )
  end

  test "an expired diagnostic receipt is never replayed as a live bundle", %{conn: conn} do
    {device, token} = paired()
    key = "expired-diagnostic-#{System.unique_integer([:positive])}"

    assert request_bundle(conn, token, %{}, key).status == 201

    receipt =
      Repo.get_by!(Playstead.Idempotency.Receipt,
        device_id: device.id,
        idempotency_key: key
      )

    expires_at = DateTime.utc_now() |> DateTime.add(-1) |> DateTime.truncate(:second)
    Repo.update!(Ecto.Changeset.change(receipt, expires_at: expires_at))

    assert request_bundle(conn, token, %{}, key).status == 201

    replacement =
      Repo.get_by!(Playstead.Idempotency.Receipt,
        device_id: device.id,
        idempotency_key: key
      )

    refute replacement.id == receipt.id
  end

  test "a request without device authorization never receives diagnostic evidence", %{conn: conn} do
    response = post(conn, ~p"/api/v1/operations/diagnostic-bundles", %{})
    assert_problem(response, 401, :unauthorized)
  end
end
