defmodule PlaysteadWeb.Api.V1.BlobsControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Import.SourceFile
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  # The uploads endpoint rejects an empty file outright (import_empty_file),
  # so a zero-length blob owned by a user is seeded directly through the
  # storage seam + a source_file row rather than through /uploads — this
  # is a fixture-only bypass of the import pipeline's own validation, not
  # a new production entry point for empty content.
  defp owned_zero_length_blob!(user_id) do
    {:ok, :stored, meta} = Playstead.Blobs.put_stream([<<>>], 0)

    {:ok, _source_file} =
      Repo.insert(
        SourceFile.create_changeset(%SourceFile{}, %{
          user_id: user_id,
          blob_id: meta.blob_id,
          original_name: "empty.bin",
          origin: "test-fixture",
          size_bytes: 0
        })
      )

    meta.sha256
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
    test "streams the exact bytes with a quoted ETag equal to the hash", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(10_000)
      %{"sha256" => sha256} = upload!(conn, token, bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert resp.status == 200
      assert Enum.at(get_resp_header(resp, "etag"), 0) == "\"#{sha256}\""
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

    test "accept-ranges is bytes on the unranged response", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(500)
      %{"sha256" => sha256} = upload!(conn, token, bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert Enum.at(get_resp_header(resp, "accept-ranges"), 0) == "bytes"
    end
  end

  describe "GET /api/v1/blobs/:sha256 with Range: bytes=N-" do
    test "concatenating a truncated GET and a subsequent ranged GET reassembles the original bytes",
         %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(10_000)
      %{"sha256" => sha256} = upload!(conn, token, bytes)
      n = 4_000

      full_resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      truncated = binary_part(full_resp.resp_body, 0, n)

      range_resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("range", "bytes=#{n}-")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert range_resp.status == 206
      reassembled = truncated <> range_resp.resp_body
      assert Base.encode16(:crypto.hash(:sha256, reassembled), case: :lower) == sha256
    end

    test "returns 206 with Content-Range and exactly the remaining bytes for a mid-file N",
         %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(10_000)
      %{"sha256" => sha256} = upload!(conn, token, bytes)
      n = 4_000
      size = byte_size(bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("range", "bytes=#{n}-")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert resp.status == 206
      assert Enum.at(get_resp_header(resp, "content-range"), 0) == "bytes #{n}-#{size - 1}/#{size}"
      assert byte_size(resp.resp_body) == size - n
    end

    test "quoted ETag on a 206 response matches the sha256", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(10_000)
      %{"sha256" => sha256} = upload!(conn, token, bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("range", "bytes=100-")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert Enum.at(get_resp_header(resp, "etag"), 0) == "\"#{sha256}\""
    end

    test "a ranged GET as a user with no source_file for the blob returns 404", %{conn: conn} do
      {_scope_a, _device_a, token_a} = paired()
      {_scope_b, _device_b, token_b} = paired()
      bytes = random_bytes(500)
      %{"sha256" => sha256} = upload!(conn, token_a, bytes)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> put_req_header("range", "bytes=0-10")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert_problem(resp, 404, :not_found)
    end
  end

  describe "GET /api/v1/blobs/:sha256 — frozen Range/If-Range/416/HEAD contract" do
    setup %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(10_000)
      %{"sha256" => sha256} = upload!(conn, token, bytes)
      %{token: token, sha256: sha256, bytes: bytes, size: byte_size(bytes)}
    end

    defp get_range(token, sha256, range_value) do
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("range", range_value)
      |> get(~p"/api/v1/blobs/#{sha256}")
    end

    test "bytes=0-0 returns 206 with a one-byte body at the exact lower edge", %{
      token: token,
      sha256: sha256,
      bytes: bytes,
      size: size
    } do
      resp = get_range(token, sha256, "bytes=0-0")

      assert resp.status == 206
      assert Enum.at(get_resp_header(resp, "content-range"), 0) == "bytes 0-0/#{size}"
      assert resp.resp_body == binary_part(bytes, 0, 1)
    end

    test "bytes=<size>- (first byte at or past end) returns 416 with problem+json", %{
      token: token,
      sha256: sha256,
      size: size
    } do
      resp = get_range(token, sha256, "bytes=#{size}-")

      body = assert_problem(resp, 416, :range_not_satisfiable)
      assert Enum.at(get_resp_header(resp, "content-range"), 0) == "bytes */#{size}"
      assert Enum.at(get_resp_header(resp, "content-type"), 0) =~ "application/problem+json"
      assert body["code"] == "range_not_satisfiable"
    end

    test "an over-long last byte position is clamped to the final byte", %{
      token: token,
      sha256: sha256,
      size: size
    } do
      resp = get_range(token, sha256, "bytes=#{size - 1}-#{size + 100}")

      assert resp.status == 206
      assert Enum.at(get_resp_header(resp, "content-range"), 0) == "bytes #{size - 1}-#{size - 1}/#{size}"
      assert byte_size(resp.resp_body) == 1
    end

    test "bytes=0-9,20-29 (multi-range) collapses to the full 200 body", %{
      token: token,
      sha256: sha256,
      bytes: bytes
    } do
      resp = get_range(token, sha256, "bytes=0-9,20-29")

      assert resp.status == 200
      assert resp.resp_body == bytes
    end

    for malformed <- ["bytes=abc", "bytes=-", "xyz=0-5"] do
      test "Range: #{malformed} degrades to the full 200 body rather than raising", %{
        token: token,
        sha256: sha256,
        bytes: bytes
      } do
        resp = get_range(token, sha256, unquote(malformed))

        assert resp.status == 200
        assert resp.resp_body == bytes
      end
    end

    test "If-Range mismatch serves the full 200 body even with a Range header present", %{
      token: token,
      sha256: sha256,
      bytes: bytes
    } do
      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("range", "bytes=100-")
        |> put_req_header("if-range", "\"#{String.duplicate("f", 64)}\"")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert resp.status == 200
      assert resp.resp_body == bytes
    end

    test "If-Range match honors the Range header and returns 206", %{
      token: token,
      sha256: sha256
    } do
      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> put_req_header("range", "bytes=100-")
        |> put_req_header("if-range", "\"#{sha256}\"")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert resp.status == 206
    end

    test "HEAD returns the same status, ETag, Accept-Ranges, and Content-Length as GET with an empty body",
         %{token: token, sha256: sha256, size: size} do
      get_resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      head_resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> head(~p"/api/v1/blobs/#{sha256}")

      assert head_resp.status == get_resp.status
      assert get_resp_header(head_resp, "etag") == get_resp_header(get_resp, "etag")
      assert get_resp_header(head_resp, "accept-ranges") == get_resp_header(get_resp, "accept-ranges")
      assert Enum.at(get_resp_header(head_resp, "content-length"), 0) == Integer.to_string(size)
      assert head_resp.resp_body == ""
    end

    test "HEAD for an unowned blob returns 404", %{sha256: sha256} do
      {_scope_b, _device_b, token_b} = paired()

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> head(~p"/api/v1/blobs/#{sha256}")

      assert_problem(resp, 404, :not_found)
    end
  end

  describe "GET /api/v1/blobs/:sha256 — zero-length blob" do
    test "a zero-length blob with a Range header returns 416", %{conn: conn} do
      {_scope, device, token} = paired()
      sha256 = owned_zero_length_blob!(device.user_id)
      _ = conn

      resp = get_range(token, sha256, "bytes=0-")

      assert_problem(resp, 416, :range_not_satisfiable)
      assert Enum.at(get_resp_header(resp, "content-range"), 0) == "bytes */0"
    end

    test "a zero-length blob with no Range header returns 200 with an empty body", %{conn: conn} do
      {_scope, device, token} = paired()
      sha256 = owned_zero_length_blob!(device.user_id)
      _ = conn

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      assert resp.status == 200
      assert resp.resp_body == ""
    end
  end
end
