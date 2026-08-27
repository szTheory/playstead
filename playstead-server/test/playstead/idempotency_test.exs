defmodule Playstead.IdempotencyTest do
  use Playstead.DataCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures
  import Playstead.IdempotencyFixtures

  alias Playstead.Idempotency
  alias Playstead.Idempotency.Receipt

  setup do
    scope = user_scope_fixture()
    %{device: device} = device_fixture(scope)
    %{device: device}
  end

  describe "fingerprint/1" do
    test "is stable for identical inputs and differs for a different body" do
      base = %{method: "PATCH", path: "/api/v1/devices/me", body: %{"a" => 1, "b" => 2}}
      reordered = %{method: "PATCH", path: "/api/v1/devices/me", body: %{"b" => 2, "a" => 1}}
      different = %{method: "PATCH", path: "/api/v1/devices/me", body: %{"a" => 999}}

      assert Idempotency.fingerprint(base) == Idempotency.fingerprint(reordered)
      assert Idempotency.fingerprint(base) != Idempotency.fingerprint(different)
    end
  end

  describe "execute/4" do
    test "runs the effect and records a completed receipt in one transaction", %{device: device} do
      key = unique_idempotency_key()
      fp = "fp"

      assert {:ok, 200, %{ok: true}} =
               Idempotency.execute(device.id, key, fp, fn -> {:ok, 200, %{ok: true}} end)

      receipt = Repo.get_by(Receipt, device_id: device.id, idempotency_key: key)
      assert receipt.state == "complete"
      assert receipt.response_status == 200
      assert Jason.decode!(receipt.response_body) == %{"ok" => true}
    end

    test "a racing insert against the same key loses and returns {:error, :conflict}", %{
      device: device
    } do
      key = unique_idempotency_key()
      in_flight_receipt_fixture(device_id: device.id, idempotency_key: key, request_fingerprint: "fp")

      assert {:error, :conflict} =
               Idempotency.execute(device.id, key, "fp", fn -> {:ok, 200, %{}} end)
    end

    test "leaves exactly one effect row after a first request plus a replay lookup", %{
      device: device
    } do
      key = unique_idempotency_key()

      assert {:ok, 201, _} =
               Idempotency.execute(device.id, key, "fp", fn ->
                 {:ok, _} = Playstead.Repo.insert(%Playstead.AuditLog.Entry{event: "test_effect"})
                 {:ok, 201, %{done: true}}
               end)

      # Fetching classifies the repeat as a replay rather than
      # re-invoking the effect.
      assert {:ok, :replay, _receipt} = Idempotency.fetch(device.id, key, "fp")

      count =
        Playstead.AuditLog.Entry
        |> Playstead.Repo.all()
        |> Enum.count(&(&1.event == "test_effect"))

      assert count == 1
    end
  end

  describe "fetch/3" do
    test "returns :fresh when no receipt exists", %{device: device} do
      assert {:ok, :fresh} = Idempotency.fetch(device.id, unique_idempotency_key(), "fp")
    end

    test "returns a replay for a complete receipt with a matching fingerprint", %{device: device} do
      receipt = complete_receipt_fixture(device_id: device.id, request_fingerprint: "fp")
      assert {:ok, :replay, ^receipt} = Idempotency.fetch(device.id, receipt.idempotency_key, "fp")
    end

    test "returns :mismatch for a complete receipt with a different fingerprint", %{
      device: device
    } do
      receipt = complete_receipt_fixture(device_id: device.id, request_fingerprint: "fp-a")

      assert {:error, :mismatch} =
               Idempotency.fetch(device.id, receipt.idempotency_key, "fp-b")
    end

    test "returns :in_flight for an in-flight receipt", %{device: device} do
      receipt = in_flight_receipt_fixture(device_id: device.id)
      assert {:error, :in_flight} = Idempotency.fetch(device.id, receipt.idempotency_key, "fp")
    end

    test "the same key from a different device is a distinct request", %{device: device} do
      other_scope = user_scope_fixture()
      %{device: other_device} = device_fixture(other_scope)

      receipt = complete_receipt_fixture(device_id: device.id, request_fingerprint: "fp")

      assert {:ok, :fresh} = Idempotency.fetch(other_device.id, receipt.idempotency_key, "fp")
    end
  end

  describe "prune_expired/0" do
    test "removes a receipt past the retention horizon and leaves a fresh one", %{device: device} do
      expired = expired_receipt_fixture(device_id: device.id)
      fresh = complete_receipt_fixture(device_id: device.id)

      assert {:ok, 1} = Idempotency.prune_expired()

      assert Repo.get(Receipt, expired.id) == nil
      assert Repo.get(Receipt, fresh.id) != nil
    end
  end
end
