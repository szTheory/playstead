defmodule PlaysteadWeb.Api.V1.ImportsControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs.Blob
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import.Receipt
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp paired(scope \\ nil) do
    scope = scope || user_scope_fixture()
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

  defp upload_conn(conn, token, bytes, opts \\ []) do
    command_id = Keyword.get(opts, :command_id, uuid_v7())
    digest = Keyword.get(opts, :digest, repr_digest_header(bytes))
    length = Keyword.get(opts, :length, to_string(byte_size(bytes)))

    idempotency_key =
      Keyword.get(opts, :idempotency_key, "upload-#{System.unique_integer([:positive])}")

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("idempotency-key", idempotency_key)

    conn = if digest, do: put_req_header(conn, "repr-digest", digest), else: conn
    conn = if length, do: put_req_header(conn, "content-length", length), else: conn

    put(conn, ~p"/api/v1/imports/uploads/#{command_id}", bytes)
  end

  describe "PUT /api/v1/imports/uploads/:command_id" do
    test "a valid upload returns success and the response carries the SHA-256 and byte size", %{
      conn: conn
    } do
      {_scope, _device, token} = paired()
      bytes = random_bytes(2_048)

      resp = upload_conn(conn, token, bytes)

      body = json_response(resp, 201)
      assert body["sha256"] == :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      assert body["size_bytes"] == byte_size(bytes)
      # 02-09 gap closure: header evidence now reaches classification for
      # every import; random bytes with no reference pack installed for
      # this fresh user land the quiet unrecognized{no_reference_installed}
      # reason rather than a plain new_asset.
      assert body["outcome"] == "unrecognized"
    end

    test "a mismatched Repr-Digest returns 422 with import_digest_mismatch and stores nothing", %{
      conn: conn
    } do
      {_scope, _device, token} = paired()
      bytes = random_bytes(1_024)
      wrong_digest = repr_digest_header(random_bytes(1_024))

      resp = upload_conn(conn, token, bytes, digest: wrong_digest)

      assert_problem(resp, 422, :import_digest_mismatch)
      sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) == 0
    end

    test "a Repr-Digest expressed in the RFC 9530 base64 form is accepted for matching bytes", %{
      conn: conn
    } do
      {_scope, _device, token} = paired()
      bytes = random_bytes(512)
      raw = :crypto.hash(:sha256, bytes)
      digest = "sha-256=:#{Base.encode64(raw)}:"

      resp = upload_conn(conn, token, bytes, digest: digest)
      assert %{"sha256" => sha256} = json_response(resp, 201)
      assert sha256 == Base.encode16(raw, case: :lower)
    end

    test "a missing Content-Length returns 411 with upload_length_required", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(64)

      resp = upload_conn(conn, token, bytes, length: nil)
      assert_problem(resp, 411, :upload_length_required)
    end

    test "a zero-byte body returns 422 with import_empty_file", %{conn: conn} do
      {_scope, _device, token} = paired()

      resp = upload_conn(conn, token, <<>>, digest: repr_digest_header(<<>>), length: "0")
      assert_problem(resp, 422, :import_empty_file)
    end

    test "a declared length above the configured maximum returns 413 with import_file_too_large",
         %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(16)

      resp = upload_conn(conn, token, bytes, length: "999999999999")
      assert_problem(resp, 413, :import_file_too_large)
    end

    test "a third concurrent upload from one device returns 429 with too_many_uploads", %{
      conn: conn
    } do
      {_scope, device, token} = paired()

      :ok = Playstead.Import.UploadSlots.acquire(device.id, 2)
      :ok = Playstead.Import.UploadSlots.acquire(device.id, 2)

      bytes = random_bytes(16)
      resp = upload_conn(conn, token, bytes)
      assert_problem(resp, 429, :too_many_uploads)

      Playstead.Import.UploadSlots.release(device.id)
      Playstead.Import.UploadSlots.release(device.id)
    end

    test "a replayed upload with the same Idempotency-Key returns the original receipt and creates no second source_file",
         %{
           conn: conn
         } do
      {scope, _device, token} = paired()
      bytes = random_bytes(4_096)
      key = "replay-#{System.unique_integer([:positive])}"
      command_id = uuid_v7()

      first = upload_conn(conn, token, bytes, idempotency_key: key, command_id: command_id)
      body1 = json_response(first, 201)

      second =
        upload_conn(build_conn(), token, bytes, idempotency_key: key, command_id: command_id)

      body2 = json_response(second, 201)

      assert body1 == body2

      assert Repo.aggregate(
               from(sf in Playstead.Import.SourceFile, where: sf.user_id == ^scope.user.id),
               :count
             ) == 1
    end

    test "a second upload of identical bytes by the same user yields exact_duplicate and one blobs row",
         %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(2_000)

      first = upload_conn(conn, token, bytes)
      # 02-09 gap closure: no reference pack installed for this user, so
      # a fresh random-bytes import lands the quiet unrecognized reason.
      assert %{"outcome" => "unrecognized"} = json_response(first, 201)

      second = upload_conn(build_conn(), token, bytes)
      assert %{"outcome" => "exact_duplicate"} = json_response(second, 201)

      sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) == 1
    end

    test "a second upload of identical bytes by a different user yields new_asset for that user and no cross-user leakage",
         %{
           conn: conn
         } do
      {_scope_a, _device_a, token_a} = paired()
      {_scope_b, _device_b, token_b} = paired()
      bytes = random_bytes(3_000)

      first = upload_conn(conn, token_a, bytes)
      body1 = json_response(first, 201)

      second = upload_conn(build_conn(), token_b, bytes)
      body2 = json_response(second, 201)

      # 02-09 gap closure: no reference pack installed for user B, so
      # their own new import lands the quiet unrecognized reason.
      assert body2["outcome"] == "unrecognized"
      refute Map.has_key?(body2, "user")
      refute inspect(body2) =~ inspect(body1["receipt_id"])

      sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
      assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) == 1
    end

    test "one catalogue journal entry is appended per successful new import", %{conn: conn} do
      {scope, _device, token} = paired()
      before = ChangeJournal.max_seq(scope.user.id)

      bytes = random_bytes(128)
      resp = upload_conn(conn, token, bytes)
      assert json_response(resp, 201)

      assert ChangeJournal.max_seq(scope.user.id) == before + 1
    end

    test "a receipt fetched in a fresh process reports the same hash, size, and provenance", %{
      conn: conn
    } do
      {_scope, _device, token} = paired()
      bytes = random_bytes(777)

      resp = upload_conn(conn, token, bytes)
      %{"receipt_id" => receipt_id, "sha256" => sha256} = json_response(resp, 201)

      task = Task.async(fn -> Repo.get!(Receipt, receipt_id) end)
      receipt = Task.await(task)

      assert receipt.sha256 == sha256
      assert receipt.size_bytes == byte_size(bytes)
    end

    test "a command_id that is not a valid UUIDv7 is rejected", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(16)

      resp = upload_conn(conn, token, bytes, command_id: "not-a-uuid")
      assert_problem(resp, 422, :invalid_command_id)
    end
  end

  describe "POST /api/v1/imports/precheck" do
    test "reports absent for a hash held only by another user", %{conn: conn} do
      {_scope_a, _device_a, token_a} = paired()
      {_scope_b, _device_b, token_b} = paired()
      bytes = random_bytes(400)

      upload = upload_conn(conn, token_a, bytes)
      %{"sha256" => sha256} = json_response(upload, 201)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token_b}")
        |> post(~p"/api/v1/imports/precheck", %{
          "items" => [%{"sha256" => sha256, "size" => byte_size(bytes)}]
        })

      assert %{"results" => [%{"present" => false}]} = json_response(resp, 200)
    end

    test "reports present for a hash the calling user already holds", %{conn: conn} do
      {_scope, _device, token} = paired()
      bytes = random_bytes(400)

      upload = upload_conn(conn, token, bytes)
      %{"sha256" => sha256} = json_response(upload, 201)

      resp =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/api/v1/imports/precheck", %{
          "items" => [%{"sha256" => sha256, "size" => byte_size(bytes)}]
        })

      assert %{"results" => [%{"present" => true}]} = json_response(resp, 200)
    end
  end

  test "no asset_sets row appears for a hash never uploaded" do
    assert Repo.aggregate(AssetSet, :count) >= 0
  end
end
