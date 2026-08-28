defmodule PlaysteadWeb.Api.V1.BlobsControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp paired do
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)
    {scope, device, token}
  end

  defp repr_digest_header(bytes) do
    raw = :crypto.hash(:sha256, bytes)
    "sha-256=:#{Base.encode64(raw)}:"
  end

  defp uuid_v7 do
    <<r1::48, _::4, r2::12, _::2, r3::14, r4::48>> = :crypto.strong_rand_bytes(16)
    bin = <<r1::48, 7::4, r2::12, 2::2, r3::14, r4::48>>
    hex = Base.encode16(bin, case: :lower)
    <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> = hex
    "#{p1}-#{p2}-#{p3}-#{p4}-#{p5}"
  end

  defp upload!(conn, token, bytes) do
    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("idempotency-key", "up-#{System.unique_integer([:positive])}")
      |> put_req_header("repr-digest", repr_digest_header(bytes))
      |> put_req_header("content-length", to_string(byte_size(bytes)))
      |> put(~p"/api/v1/imports/uploads/#{uuid_v7()}", bytes)

    json_response(resp, 201)
  end

  describe "GET /api/v1/blobs/:sha256" do
    test "streams the exact bytes with an ETag equal to the hash", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(10_000)
      %{"sha256" => sha256} = upload!(conn, token, bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert resp.status == 200
      assert Enum.at(get_resp_header(resp, "etag"), 0) == sha256
      assert resp.resp_body == bytes
    end

    test "returns 404 for a hash the calling user holds no source file for", %{conn: conn} do
      {_scope, _device, token} = paired()

      resp =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{String.duplicate("0", 64)}")

      assert_problem(resp, 404, :not_found)
    end

    test "returns 404 for a blob another user holds but the caller does not", %{conn: conn} do
      {_scope_a, _device_a, token_a} = paired()
      {_scope_b, _device_b, token_b} = paired()
      bytes = random_bytes(500)
      %{"sha256" => sha256} = upload!(conn, token_a, bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert_problem(resp, 404, :not_found)
    end
  end
end
