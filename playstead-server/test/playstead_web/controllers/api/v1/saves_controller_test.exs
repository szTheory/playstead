defmodule PlaysteadWeb.Api.V1.SavesControllerTest do
  @moduledoc """
  Plan 04-04 task 1: the tracer's server half -- one save round-trips
  through the streamed upload and the idempotent metadata commit into a
  durable `save_revisions` row whose blob is readable back through
  `Playstead.Blobs` (D-16, D-26).
  """

  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Repo
  alias Playstead.Saves.Revision
  alias Playstead.Sync.ChangeJournal

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

  defp upload!(conn, token, bytes, command_id) do
    digest = repr_digest_header(bytes)

    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("repr-digest", digest)
    |> put_req_header("content-length", to_string(byte_size(bytes)))
    |> put(~p"/api/v1/saves/uploads/#{command_id}", bytes)
  end

  defp commit!(conn, token, idempotency_key, params) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> post(~p"/api/v1/saves/revisions", params)
  end

  test "one save round-trips: upload, commit, blob readable, journal entry appended", %{
    conn: conn
  } do
    {scope, _device, token} = paired()
    bytes = :crypto.strong_rand_bytes(32_768)
    sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    command_id = uuid_v7()
    revision_id = uuid_v7()

    upload_resp = upload!(build_conn(), token, bytes, command_id)
    upload_body = json_response(upload_resp, 200)
    assert upload_body["sha256"] == sha256
    assert upload_body["size_bytes"] == byte_size(bytes)

    commit_resp =
      commit!(build_conn(), token, "commit-#{System.unique_integer([:positive])}", %{
        "id" => revision_id,
        "command_id" => command_id,
        "content_key" => content_key()
      })

    body = json_response(commit_resp, 201)
    assert body["id"] == revision_id
    assert body["blob_sha256"] == sha256
    assert body["size_bytes"] == byte_size(bytes)

    revision = Repo.get_by(Revision, id: revision_id, user_id: scope.user.id)
    assert revision
    assert revision.blob_sha256 == sha256

    {:ok, stream} = Playstead.Blobs.stream(sha256)
    stored_bytes = stream |> Enum.into(<<>>)
    assert :crypto.hash(:sha256, stored_bytes) |> Base.encode16(case: :lower) == sha256

    entries = from(e in Playstead.Sync.Entry, where: e.user_id == ^scope.user.id) |> Repo.all()
    assert Enum.any?(entries, &(&1.entity_kind == "save" and &1.entity_id == revision_id))

    _ = conn
    _ = ChangeJournal
  end

  # WINDOWS #57: `adapter_id`/`adapter_version` are plumbed from the Mac
  # client through this endpoint, into the revision row, and out again in
  # the journal payload a second device reads. Every link existed and no
  # test anywhere asserted any of them, which is part of why the client
  # sent empty strings for months without anyone noticing.
  test "capture provenance survives the commit and reaches the journal payload", %{conn: conn} do
    {scope, _device, token} = paired()
    bytes = :crypto.strong_rand_bytes(32_768)
    command_id = uuid_v7()
    revision_id = uuid_v7()

    upload_resp = upload!(build_conn(), token, bytes, command_id)
    json_response(upload_resp, 200)

    commit_resp =
      commit!(build_conn(), token, "commit-#{System.unique_integer([:positive])}", %{
        "id" => revision_id,
        "command_id" => command_id,
        "content_key" => content_key(),
        "capture_method" => "session",
        "adapter_id" => "mgba",
        "adapter_version" => "0.10.5"
      })

    json_response(commit_resp, 201)

    revision = Repo.get_by(Revision, id: revision_id, user_id: scope.user.id)
    assert revision.adapter_id == "mgba"
    assert revision.adapter_version == "0.10.5"
    assert revision.capture_method == "session"

    entry =
      from(e in Playstead.Sync.Entry,
        where:
          e.user_id == ^scope.user.id and e.entity_kind == "save" and
            e.entity_id == ^revision_id
      )
      |> Repo.one()

    assert entry.payload["adapter_id"] == "mgba",
           "a second device learns provenance only through the journal payload"

    assert entry.payload["adapter_version"] == "0.10.5"

    _ = conn
  end

  test "replaying the same Idempotency-Key returns the original receipt with no second revision",
       %{conn: conn} do
    {scope, _device, token} = paired()
    bytes = :crypto.strong_rand_bytes(32_768)
    command_id = uuid_v7()
    revision_id = uuid_v7()
    key = "commit-#{System.unique_integer([:positive])}"

    upload_resp = upload!(build_conn(), token, bytes, command_id)
    json_response(upload_resp, 200)

    params = %{
      "id" => revision_id,
      "command_id" => command_id,
      "content_key" => content_key()
    }

    resp1 = commit!(build_conn(), token, key, params)
    body1 = json_response(resp1, 201)

    resp2 = commit!(build_conn(), token, key, params)
    body2 = json_response(resp2, 201)

    assert body1 == body2

    count =
      Repo.aggregate(
        from(r in Revision, where: r.user_id == ^scope.user.id and r.id == ^revision_id),
        :count
      )

    assert count == 1

    _ = conn
  end
end
