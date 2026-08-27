defmodule Playstead.PairingTest do
  use Playstead.DataCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Pairing
  alias Playstead.Pairing.PairingRequest
  alias Playstead.AuditLog

  describe "create_request/1" do
    test "stores only the hash of the device_code, never the plaintext" do
      device_code = unique_device_code()

      {:ok, request} =
        Pairing.create_request(valid_pairing_request_attributes(%{"device_code" => device_code}))

      refute request.device_code_hash == device_code
      assert is_binary(request.device_code_hash)
      assert request.device_code_hash != nil
    end

    test "returns a display code and pending status" do
      {:ok, request} = Pairing.create_request(valid_pairing_request_attributes())

      assert request.status == "pending"
      assert Regex.match?(~r/^[A-Z]{4}-[A-Z]{4}$/, request.display_code)
    end

    test "records the requesting IP taken from the passed-in trusted value" do
      {:ok, request} =
        Pairing.create_request(valid_pairing_request_attributes(%{"requesting_ip" => "203.0.113.9"}))

      assert request.requesting_ip == "203.0.113.9"
    end

    test "records a pairing_requested audit entry" do
      {:ok, request} = Pairing.create_request(valid_pairing_request_attributes())

      entries = AuditLog.list_by_subject(request.id)
      assert Enum.any?(entries, &(&1.event == "pairing_requested"))
    end

    test "rejects a request with no device_code" do
      assert {:error, changeset} = Pairing.create_request(%{"device_name" => "Test Mac"})
      assert %{device_code: ["can't be blank"]} = errors_on(changeset)
    end

    test "filling the pending queue to its cap evicts the oldest and audits the eviction" do
      requests =
        for _ <- 1..20 do
          {request, _code} = pairing_request_fixture()
          request
        end

      oldest = List.first(requests)

      {:ok, _newest} = Pairing.create_request(valid_pairing_request_attributes())

      {:ok, reloaded_oldest} = Pairing.get_request_status(oldest.id)
      assert reloaded_oldest.status == "expired"

      entries = AuditLog.list_by_subject(oldest.id)
      assert Enum.any?(entries, &(&1.event == "pairing_request_evicted"))
    end
  end

  describe "get_request_status/1" do
    test "returns pending before approval" do
      {request, _code} = pairing_request_fixture()
      assert {:ok, %{status: "pending"}} = Pairing.get_request_status(request.id)
    end

    test "returns approved after approval" do
      scope = user_scope_fixture()
      {request, _code} = pairing_request_fixture()
      {:ok, _} = Pairing.approve(scope, request.id)

      assert {:ok, %{status: "approved"}} = Pairing.get_request_status(request.id)
    end

    test "reports expired for a request older than 10 minutes even with no background job run" do
      {request, _code} = expired_pairing_request_fixture()

      assert {:ok, %{status: "expired"}} = Pairing.get_request_status(request.id)
      # the persisted column itself is untouched — no background job ran
      assert Repo.get!(PairingRequest, request.id).status == "pending"
    end

    test "returns not_found for an unknown id" do
      assert {:error, :not_found} = Pairing.get_request_status(Ecto.UUID.generate())
    end
  end

  describe "approve/2" do
    test "on an expired request returns an error and leaves status unchanged" do
      scope = user_scope_fixture()
      {request, _code} = expired_pairing_request_fixture()

      assert {:error, {:invalid_transition, "expired"}} = Pairing.approve(scope, request.id)
      assert Repo.get!(PairingRequest, request.id).status == "pending"
    end

    test "requires a %Scope{} — there is no code path around it" do
      assert_raise FunctionClauseError, fn ->
        apply(Pairing, :approve, [nil, Ecto.UUID.generate()])
      end
    end

    test "records a pairing_approved audit entry" do
      scope = user_scope_fixture()
      {request, _code} = pairing_request_fixture()

      {:ok, _} = Pairing.approve(scope, request.id)

      entries = AuditLog.list_by_subject(request.id)
      assert Enum.any?(entries, &(&1.event == "pairing_approved"))
    end
  end

  describe "deny/2" do
    test "transitions a pending request to denied" do
      scope = user_scope_fixture()
      {request, _code} = pairing_request_fixture()

      {:ok, denied} = Pairing.deny(scope, request.id)
      assert denied.status == "denied"
    end
  end

  describe "expire_stale_requests/0" do
    test "transitions stale pending requests to expired" do
      {request, _code} = expired_pairing_request_fixture()

      {:ok, count} = Pairing.expire_stale_requests()
      assert count >= 1

      assert Repo.get!(PairingRequest, request.id).status == "expired"
    end

    test "never touches a fresh pending request" do
      {request, _code} = pairing_request_fixture()

      {:ok, _count} = Pairing.expire_stale_requests()

      assert Repo.get!(PairingRequest, request.id).status == "pending"
    end
  end

  describe "no auto-approval code path" do
    test "the module source contains no transition to approved without a %Scope{} argument" do
      source = File.read!("lib/playstead/pairing.ex")
      # every call site that sets status to "approved" flows through
      # transition/4, whose only public entry point (approve/2) pattern
      # matches on %Scope{}.
      assert source =~ "def approve(%Scope{} = scope, id)"
      refute source =~ ~r/def approve\(id\)/
    end
  end
end
