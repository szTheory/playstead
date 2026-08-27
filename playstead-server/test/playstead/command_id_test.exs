defmodule Playstead.CommandIdTest do
  use Playstead.DataCase, async: true
  use Oban.Testing, repo: Playstead.Repo

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.{CommandId, Pairing}
  alias Playstead.Pairing.DeviceCredential

  # A well-formed UUIDv7 (version nibble 7, variant nibble in 8-b).
  defp v7, do: "018f4d2e-1c1a-7c3e-89ab-0242ac120002"
  defp v4, do: Ecto.UUID.generate()

  describe "valid_v7?/1" do
    test "returns false for a v4 UUID and true for a v7 UUID" do
      refute CommandId.valid_v7?(v4())
      assert CommandId.valid_v7?(v7())
    end

    test "returns false for a malformed string and a non-string" do
      refute CommandId.valid_v7?("not-a-uuid")
      refute CommandId.valid_v7?(nil)
      refute CommandId.valid_v7?(12345)
    end
  end

  describe "cast/1" do
    test "returns {:ok, normalized} for a valid v7 and :error otherwise" do
      assert {:ok, downcased} = CommandId.cast(String.upcase(v7()))
      assert downcased == v7()
      assert CommandId.cast(v4()) == :error
      assert CommandId.cast("garbage") == :error
    end
  end

  describe "rotate_credential/2 with command_id — convergence" do
    setup do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      %{device: device}
    end

    test "replaying the same command_id after deleting the idempotency receipt still converges to one effect row",
         %{device: device} do
      command_id = v7()

      {:ok, %{fingerprint_prefix: fp1}} = Pairing.rotate_credential(device, command_id)

      # Simulate the idempotency receipt (task 2) having expired/been
      # deleted — the natural-key layer must still converge on its own.
      Playstead.Repo.delete_all(Playstead.Idempotency.Receipt)

      {:ok, %{fingerprint_prefix: fp2}} = Pairing.rotate_credential(device, command_id)

      assert fp1 == fp2

      count =
        DeviceCredential
        |> Playstead.Repo.all()
        |> Enum.count(&(&1.command_id == command_id))

      assert count == 1
    end

    test "enqueuing the same command twice results in exactly one Oban job", %{device: device} do
      command_id = v7()

      {:ok, _} = Pairing.rotate_credential(device, command_id)
      {:ok, _} = Pairing.rotate_credential(device, command_id)

      jobs =
        Oban.Job
        |> Playstead.Repo.all()
        |> Enum.filter(&(&1.worker == "Playstead.Pairing.RotationAuditWorker"))
        |> Enum.filter(&(&1.args["command_id"] == command_id))

      assert length(jobs) == 1
    end

    test "a malformed command_id is rejected with invalid_command_id and produces no effect", %{
      device: device
    } do
      before_count = Playstead.Repo.aggregate(DeviceCredential, :count)

      assert {:error, {:invalid_command_id, _}} = Pairing.rotate_credential(device, "not-a-uuid")

      assert Playstead.Repo.aggregate(DeviceCredential, :count) == before_count
    end
  end
end
