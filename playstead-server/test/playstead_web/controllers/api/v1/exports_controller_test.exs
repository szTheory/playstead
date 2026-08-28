defmodule PlaysteadWeb.Api.V1.ExportsControllerTest do
  use PlaysteadWeb.ApiCase, async: false
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Export
  alias Playstead.Export.Worker
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    File.rm_rf!(Export.export_root())
    File.mkdir_p!(Export.export_root())
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

  defp create_export!(conn, token, params) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", "exp-#{System.unique_integer([:positive])}")
    |> post(~p"/api/v1/exports", params)
  end

  test "POST /api/v1/exports creates a durable export record and enqueues the worker", %{
    conn: conn
  } do
    {scope, _device, token} = paired()
    bytes = random_bytes(1_000)
    %{"sha256" => sha256} = upload!(conn, token, bytes)

    asset_set = Repo.get_by!(Playstead.Catalogue.AssetSet, user_id: scope.user.id)

    resp =
      create_export!(conn, token, %{
        "asset_set_id" => asset_set.id,
        "target_name" => "export-#{System.unique_integer([:positive])}"
      })

    body = json_response(resp, 201)
    assert body["status"] == "writing"
    assert_enqueued(worker: Worker, args: %{export_id: body["id"]})

    assert :ok = perform_job(Worker, %{"export_id" => body["id"]})

    show_resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/exports/#{body["id"]}")

    show_body = json_response(show_resp, 200)
    assert show_body["status"] == "verified"

    manifest_resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/exports/#{body["id"]}/manifest")

    assert manifest_resp.status == 200
    assert manifest_resp.resp_body =~ sha256
  end

  test "GET /api/v1/exports/:id/manifest is byte-identical to the written manifest file", %{
    conn: conn
  } do
    {scope, _device, token} = paired()
    bytes = random_bytes(1_000)
    upload!(conn, token, bytes)

    asset_set = Repo.get_by!(Playstead.Catalogue.AssetSet, user_id: scope.user.id)

    resp =
      create_export!(conn, token, %{
        "asset_set_id" => asset_set.id,
        "target_name" => "export-#{System.unique_integer([:positive])}"
      })

    body = json_response(resp, 201)
    assert :ok = perform_job(Worker, %{"export_id" => body["id"]})

    export = Export.get_export(scope.user.id, body["id"])
    on_disk = File.read!(Path.join(Export.target_dir(export.target_name), "manifest-sha256.txt"))

    manifest_resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/exports/#{body["id"]}/manifest")

    assert manifest_resp.resp_body == on_disk
  end

  test "GET /api/v1/exports/:id returns 404 for an export another user owns", %{conn: conn} do
    {scope_a, _device_a, token_a} = paired()
    bytes = random_bytes(500)
    upload!(conn, token_a, bytes)
    asset_set = Repo.get_by!(Playstead.Catalogue.AssetSet, user_id: scope_a.user.id)

    resp =
      create_export!(conn, token_a, %{
        "asset_set_id" => asset_set.id,
        "target_name" => "export-#{System.unique_integer([:positive])}"
      })

    body = json_response(resp, 201)

    {_scope_b, _device_b, token_b} = paired()

    other_resp =
      conn
      |> put_req_header("authorization", "Bearer #{token_b}")
      |> get(~p"/api/v1/exports/#{body["id"]}")

    assert other_resp.status == 404
  end

  test "a folder written using only the API manifest and blob endpoints is byte-identical to the server-written export",
       %{conn: conn} do
    {scope, _device, token} = paired()
    bytes = random_bytes(4_096)
    upload!(conn, token, bytes)
    asset_set = Repo.get_by!(Playstead.Catalogue.AssetSet, user_id: scope.user.id)
    target_name = "export-#{System.unique_integer([:positive])}"

    resp =
      create_export!(conn, token, %{"asset_set_id" => asset_set.id, "target_name" => target_name})

    body = json_response(resp, 201)
    assert :ok = perform_job(Worker, %{"export_id" => body["id"]})

    server_manifest = File.read!(Path.join(Export.target_dir(target_name), "manifest-sha256.txt"))

    manifest_resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/exports/#{body["id"]}/manifest")

    assert manifest_resp.resp_body == server_manifest

    client_dir =
      Path.join(
        System.tmp_dir!(),
        "playstead-client-writer-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(client_dir)
    on_exit(fn -> File.rm_rf!(client_dir) end)

    File.write!(Path.join(client_dir, "manifest-sha256.txt"), manifest_resp.resp_body)

    for line <- String.split(manifest_resp.resp_body, "\n", trim: true) do
      [sha256, relative] = String.split(line, "  ", parts: 2)

      blob_resp =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/api/v1/blobs/#{sha256}")

      dest = Path.join(client_dir, relative)
      File.mkdir_p!(Path.dirname(dest))
      File.write!(dest, blob_resp.resp_body)
    end

    for line <- String.split(server_manifest, "\n", trim: true) do
      [_sha256, relative] = String.split(line, "  ", parts: 2)

      assert File.read!(Path.join(client_dir, relative)) ==
               File.read!(Path.join(Export.target_dir(target_name), relative))
    end
  end
end
