defmodule PlaysteadWeb.Api.V1.SavesLimitsTest do
  @moduledoc """
  Gap closure for CR-02 (04-REVIEW-server.md): D-33's save-lane limits
  are defined in `Playstead.Blobs` but were never invoked in
  production. Every test here drives an ENDPOINT and asserts a
  REFUSAL -- never a constant's value or a key's string shape, which
  is exactly the shape that let this defect read as implemented for
  nine plans (WINDOWS #37).
  """

  use PlaysteadWeb.ApiCase, async: false

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Blobs
  alias Playstead.Import.UploadSlots
  alias Playstead.RateLimiter

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

  defp content_key, do: :crypto.hash(:sha256, :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)

  defp upload!(conn, token, bytes, command_id, opts \\ []) do
    digest = repr_digest_header(bytes)
    length = Keyword.get(opts, :length, to_string(byte_size(bytes)))

    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/octet-stream")
    |> put_req_header("repr-digest", digest)
    |> put_req_header("content-length", length)
    |> put(~p"/api/v1/saves/uploads/#{command_id}", bytes)
  end

  defp commit!(conn, token, idempotency_key, params) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", idempotency_key)
    |> post(~p"/api/v1/saves/revisions", params)
  end

  defp upload_and_commit!(token, device_id) do
    bytes = :crypto.strong_rand_bytes(64)
    command_id = uuid_v7()
    revision_id = uuid_v7()

    upload_resp = upload!(build_conn(), token, bytes, command_id)
    json_response(upload_resp, 200)

    commit!(build_conn(), token, "commit-#{device_id}-#{System.unique_integer([:positive])}", %{
      "id" => revision_id,
      "command_id" => command_id,
      "content_key" => content_key()
    })
  end

  describe "the save-revision rate limit is enforced on the commit path (D-33/CR-02)" do
    test "a device that has already used its full hourly budget is refused with a registered problem code",
         %{conn: _conn} do
      {_scope, device, token} = paired()

      # Pre-consume the full hourly budget directly against the same
      # bucket the controller checks, so the test doesn't need to make
      # 120 real HTTP round-trips to prove the enforcement path.
      key = Blobs.save_revision_rate_limit_key(device.id)
      limit = Blobs.save_revision_rate_limit_per_hour()

      for _ <- 1..limit do
        {:allow, _} = RateLimiter.hit(key, :timer.hours(1), limit)
      end

      resp = upload_and_commit!(token, device.id)
      assert_problem(resp, 429, :rate_limited)
    end

    test "a device under its hourly budget is not refused by the rate limit", %{conn: _conn} do
      {_scope, device, token} = paired()

      resp = upload_and_commit!(token, device.id)
      assert %{"id" => _id} = json_response(resp, 201)
    end

    test "the limit-th request in the window still succeeds; only the one past it is refused",
         %{conn: _conn} do
      {_scope, device, token} = paired()

      key = Blobs.save_revision_rate_limit_key(device.id)
      limit = Blobs.save_revision_rate_limit_per_hour()

      # Consume every slot but one directly against the bucket.
      for _ <- 1..(limit - 1) do
        {:allow, _} = RateLimiter.hit(key, :timer.hours(1), limit)
      end

      # The limit-th request goes through the real endpoint and must succeed.
      resp_at_limit = upload_and_commit!(token, device.id)
      assert %{"id" => _id} = json_response(resp_at_limit, 201)

      # The next one is over budget and must be refused.
      resp_over_limit = upload_and_commit!(token, device.id)
      assert_problem(resp_over_limit, 429, :rate_limited)
    end
  end

  describe "the declared-size cap is enforced before bytes are streamed (D-33)" do
    test "a declared length above max_save_revision_bytes/0 is refused with save_revision_too_large" do
      {_scope, _device, token} = paired()
      bytes = :crypto.strong_rand_bytes(64)
      oversized_length = to_string(Blobs.max_save_revision_bytes() + 1)

      resp =
        upload!(build_conn(), token, bytes, uuid_v7(), length: oversized_length)

      assert_problem(resp, 413, :save_revision_too_large)
    end
  end

  describe "the save-upload concurrency slot is namespaced and applied (D-33/CR-02)" do
    test "a save upload does not consume or contend with the imports upload budget for the same device" do
      {_scope, device, token} = paired()

      # Fill the device's plain (import-namespaced) upload budget directly.
      assert :ok = UploadSlots.acquire(device.id, "import-held-1", 2)
      assert :ok = UploadSlots.acquire(device.id, "import-held-2", 2)

      # A save upload for the SAME device must still succeed -- it
      # spends from "save:" <> device.id, a different budget entirely.
      resp = upload!(build_conn(), token, :crypto.strong_rand_bytes(64), uuid_v7())
      assert json_response(resp, 200)

      UploadSlots.release(device.id, "import-held-1")
      UploadSlots.release(device.id, "import-held-2")
    end

    test "a third concurrent save upload for one device is refused with too_many_uploads" do
      {_scope, device, token} = paired()
      save_bucket = Blobs.save_upload_slot_key(device.id)

      assert :ok = UploadSlots.acquire(save_bucket, "held-1", 2)
      assert :ok = UploadSlots.acquire(save_bucket, "held-2", 2)

      resp = upload!(build_conn(), token, :crypto.strong_rand_bytes(64), uuid_v7())
      assert_problem(resp, 429, :too_many_uploads)

      UploadSlots.release(save_bucket, "held-1")
      UploadSlots.release(save_bucket, "held-2")
    end

    test "a refused save upload does not leak its slot -- a device at the cap can upload once a slot frees" do
      {_scope, device, token} = paired()
      save_bucket = Blobs.save_upload_slot_key(device.id)

      assert :ok = UploadSlots.acquire(save_bucket, "held-1", 2)
      assert :ok = UploadSlots.acquire(save_bucket, "held-2", 2)

      refused = upload!(build_conn(), token, :crypto.strong_rand_bytes(64), uuid_v7())
      assert_problem(refused, 429, :too_many_uploads)

      UploadSlots.release(save_bucket, "held-1")

      allowed = upload!(build_conn(), token, :crypto.strong_rand_bytes(64), uuid_v7())
      assert json_response(allowed, 200)

      UploadSlots.release(save_bucket, "held-2")
    end

    test "retrying the same command_id while the first attempt's slot is still held does not consume a second slot" do
      {_scope, device, token} = paired()
      save_bucket = Blobs.save_upload_slot_key(device.id)
      command_id = uuid_v7()

      # Simulate the first attempt's in-flight slot, held under this
      # exact command_id (as the real plug would hold it mid-stream).
      assert :ok = UploadSlots.acquire(save_bucket, command_id, 2)
      assert :ok = UploadSlots.acquire(save_bucket, "other-in-flight", 2)

      # A retried request for the SAME command_id must not need a third
      # slot -- the plug dedupes on it, so this goes through even
      # though the device's 2-slot budget is otherwise fully spent.
      resp = upload!(build_conn(), token, :crypto.strong_rand_bytes(64), command_id)
      assert json_response(resp, 200)

      UploadSlots.release(save_bucket, command_id)
      UploadSlots.release(save_bucket, "other-in-flight")
    end
  end
end
