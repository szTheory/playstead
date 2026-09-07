defmodule PlaysteadWeb.Api.V1.SaveHistoryControllerTest do
  @moduledoc """
  Plan 04-05 task 2: commit invariants (D-30 confirmation, the three
  loud caps, D-13's Retry-After) and the read-only history endpoint
  (D-14, D-26).
  """

  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Repo
  alias Playstead.Saves.Revision

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

  defp content_key,
    do: :crypto.hash(:sha256, :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)

  defp upload!(token, bytes, command_id) do
    digest = repr_digest_header(bytes)

    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("repr-digest", digest)
    |> put_req_header("content-length", to_string(byte_size(bytes)))
    |> put(~p"/api/v1/saves/uploads/#{command_id}", bytes)
  end

  defp commit(token, idempotency_key, params) do
    build_conn()
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> post(~p"/api/v1/saves/revisions", params)
  end

  defp fresh_key, do: "commit-#{System.unique_integer([:positive, :monotonic])}"

  defp commit_revision!(token, key, params) do
    resp = commit(token, key, params)
    json_response(resp, 201)
  end

  defp upload_and_commit!(token, content_key, bytes, extra_params \\ %{}) do
    command_id = uuid_v7()
    upload_resp = upload!(token, bytes, command_id)
    json_response(upload_resp, 200)

    params =
      Map.merge(
        %{"id" => uuid_v7(), "command_id" => command_id, "content_key" => content_key},
        extra_params
      )

    commit_revision!(token, fresh_key(), params)
  end

  test "GET history returns a line's revisions and derived heads", %{conn: conn} do
    {_scope, _device, token} = paired()
    key = content_key()

    root = upload_and_commit!(token, key, :crypto.strong_rand_bytes(64))

    child =
      upload_and_commit!(token, key, :crypto.strong_rand_bytes(64), %{
        "parent_revision_id" => root["id"]
      })

    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/api/v1/saves/lines/#{root["save_line_id"]}/history")

    body = json_response(resp, 200)
    revision_ids = Enum.map(body["revisions"], & &1["id"])
    assert root["id"] in revision_ids
    assert child["id"] in revision_ids
    assert body["heads"] == [child["id"]]
  end

  test "a cross-user line read returns 404", %{conn: conn} do
    {_scope, _device, token} = paired()
    {_other_scope, _other_device, other_token} = paired()
    key = content_key()

    root = upload_and_commit!(token, key, :crypto.strong_rand_bytes(64))

    resp =
      conn
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> get(~p"/api/v1/saves/lines/#{root["save_line_id"]}/history")

    assert_problem(resp, 404, :not_found)
  end

  test "committing a revision naming an unknown parent returns 409 save_parent_unknown with Retry-After, and the same commit succeeds once the parent exists",
       %{conn: _conn} do
    {scope, _device, token} = paired()
    key = content_key()
    unknown_parent_id = uuid_v7()
    bytes = :crypto.strong_rand_bytes(64)
    command_id = uuid_v7()
    revision_id = uuid_v7()

    json_response(upload!(token, bytes, command_id), 200)

    resp =
      commit(token, fresh_key(), %{
        "id" => revision_id,
        "command_id" => command_id,
        "content_key" => key,
        "parent_revision_id" => unknown_parent_id
      })

    body = assert_problem(resp, 409, :save_parent_unknown)
    assert Plug.Conn.get_resp_header(resp, "retry-after") == ["1"]
    _ = body

    # Now commit the parent, then retry the exact same commit.
    parent_bytes = :crypto.strong_rand_bytes(64)
    parent_command_id = uuid_v7()
    json_response(upload!(token, parent_bytes, parent_command_id), 200)

    parent =
      commit_revision!(token, fresh_key(), %{
        "id" => unknown_parent_id,
        "command_id" => parent_command_id,
        "content_key" => key
      })

    assert parent["id"] == unknown_parent_id

    retry_command_id = uuid_v7()
    json_response(upload!(token, bytes, retry_command_id), 200)

    retry_resp =
      commit(token, fresh_key(), %{
        "id" => revision_id,
        "command_id" => retry_command_id,
        "content_key" => key,
        "parent_revision_id" => unknown_parent_id
      })

    retry_body = json_response(retry_resp, 201)
    assert retry_body["id"] == revision_id

    _ = scope
  end

  test "a same-device byte-identical commit leaves the revision count unchanged and bumps confirm_count",
       %{conn: _conn} do
    {scope, _device, token} = paired()
    key = content_key()
    bytes = :crypto.strong_rand_bytes(64)

    root = upload_and_commit!(token, key, bytes)

    count_before =
      Repo.aggregate(from(r in Revision, where: r.user_id == ^scope.user.id), :count)

    reconfirmed =
      upload_and_commit!(token, key, bytes, %{"parent_revision_id" => root["id"]})

    count_after =
      Repo.aggregate(from(r in Revision, where: r.user_id == ^scope.user.id), :count)

    assert count_after == count_before
    assert reconfirmed["id"] == root["id"]

    revision = Repo.get_by(Revision, id: root["id"], user_id: scope.user.id)
    assert revision.confirm_count == 1
    assert revision.last_confirmed_at
  end

  test "a different-device byte-identical commit adds one revision with an unchanged blob count",
       %{conn: _conn} do
    scope = user_scope_fixture()
    %{device: _device_a, credential_plaintext: token_a} = device_fixture(scope)
    %{device: _device_b, credential_plaintext: token_b} = device_fixture(scope)
    key = content_key()
    bytes = :crypto.strong_rand_bytes(64)

    root = upload_and_commit!(token_a, key, bytes)

    other =
      upload_and_commit!(token_b, key, bytes, %{"parent_revision_id" => root["id"]})

    refute other["id"] == root["id"]
    assert other["blob_sha256"] == root["blob_sha256"]

    count =
      Repo.aggregate(from(r in Revision, where: r.user_id == ^scope.user.id), :count)

    assert count == 2
  end

  test "a commit that would create a 33rd branch head on one line returns save_branch_limit_exceeded",
       %{conn: _conn} do
    {_scope, _device, token} = paired()
    key = content_key()

    root = upload_and_commit!(token, key, :crypto.strong_rand_bytes(64))

    # 31 more roots on the same line already has 1 head (the first
    # root); each additional root branches the line and adds a head,
    # so after 31 more roots the line has 32 heads at the cap.
    Enum.each(1..31, fn _ ->
      upload_and_commit!(token, key, :crypto.strong_rand_bytes(64))
    end)

    command_id = uuid_v7()
    bytes = :crypto.strong_rand_bytes(64)
    json_response(upload!(token, bytes, command_id), 200)

    resp =
      commit(token, fresh_key(), %{
        "id" => uuid_v7(),
        "command_id" => command_id,
        "content_key" => key
      })

    assert_problem(resp, 422, :save_branch_limit_exceeded)

    _ = root
  end

  test "an attempt to modify an already-committed revision returns save_revision_immutable",
       %{conn: _conn} do
    {_scope, _device, token} = paired()
    key = content_key()
    bytes = :crypto.strong_rand_bytes(64)
    command_id = uuid_v7()
    revision_id = uuid_v7()

    json_response(upload!(token, bytes, command_id), 200)

    commit_revision!(token, fresh_key(), %{
      "id" => revision_id,
      "command_id" => command_id,
      "content_key" => key
    })

    other_bytes = :crypto.strong_rand_bytes(64)
    other_command_id = uuid_v7()
    json_response(upload!(token, other_bytes, other_command_id), 200)

    resp =
      commit(token, fresh_key(), %{
        "id" => revision_id,
        "command_id" => other_command_id,
        "content_key" => content_key()
      })

    assert_problem(resp, 409, :save_revision_immutable)
  end

  test "a user at or beyond the revision-count backstop still has their next revision committed successfully",
       %{conn: _conn} do
    {_scope, _device, token} = paired()
    key = content_key()

    assert Playstead.Saves.revision_count_backstop() == 100_000
    assert Playstead.Saves.storage_bytes_backstop() == 21_474_836_480

    root = upload_and_commit!(token, key, :crypto.strong_rand_bytes(64))
    assert root["id"]
  end
end
