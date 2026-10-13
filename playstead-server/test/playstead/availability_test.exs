defmodule Playstead.AvailabilityTest do
  @moduledoc """
  Plan 03-13 (LIBR-02 gap closure): `Playstead.Availability`'s
  full-replacement report semantics and any-device merge.
  """

  use Playstead.DataCase, async: true

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Availability

  defp paired do
    scope = user_scope_fixture()
    %{device: device} = device_fixture(scope)
    {scope, device}
  end

  test "replace_for_device stores a report and facts_for_user merges it" do
    {scope, device} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    assert {:ok, :replaced} =
             Availability.replace_for_device(device, [
               %{"asset_set_id" => asset_set.id, "verified" => true, "download_percent" => 100}
             ])

    facts = Availability.facts_for_user(scope.user.id)
    assert facts[asset_set.id].verified == true
    assert facts[asset_set.id].download_percent == 100
  end

  test "replace_for_device fully replaces a device's prior rows" do
    {scope, device} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    Availability.replace_for_device(device, [
      %{"asset_set_id" => asset_set.id, "downloading" => true, "download_percent" => 40}
    ])

    Availability.replace_for_device(device, [])

    facts = Availability.facts_for_user(scope.user.id)
    refute Map.has_key?(facts, asset_set.id)
  end

  test "a report naming another user's asset set is rejected -- no row is written for it" do
    {_scope, device} = paired()
    other = Playstead.AccountsFixtures.owner_fixture()
    other_asset_set = asset_set_fixture(other.id)

    assert {:ok, :replaced} =
             Availability.replace_for_device(device, [
               %{"asset_set_id" => other_asset_set.id, "verified" => true}
             ])

    facts = Availability.facts_for_user(other.id)
    assert facts == %{}
  end

  test "a download_percent outside 0..100 is rejected rather than clamped" do
    {scope, device} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    assert {:error, _reason} =
             Availability.replace_for_device(device, [
               %{"asset_set_id" => asset_set.id, "download_percent" => 150}
             ])

    facts = Availability.facts_for_user(scope.user.id)
    assert facts == %{}
  end

  test "a report above the bounded entry count is rejected outright" do
    {_scope, device} = paired()

    entries = for _ <- 1..5001, do: %{"asset_set_id" => Ecto.UUID.generate()}

    assert {:error, :too_many_entries} = Availability.replace_for_device(device, entries)
  end

  test "facts_for_user merges any-device-true and max-percent across a user's devices" do
    scope = user_scope_fixture()
    %{device: device_a} = device_fixture(scope)
    %{device: device_b} = device_fixture(scope, %{"device_name" => "Second Mac"})
    asset_set = asset_set_fixture(scope.user.id)

    Availability.replace_for_device(device_a, [
      %{"asset_set_id" => asset_set.id, "downloading" => true, "download_percent" => 30}
    ])

    Availability.replace_for_device(device_b, [
      %{"asset_set_id" => asset_set.id, "downloading" => false, "download_percent" => 80}
    ])

    facts = Availability.facts_for_user(scope.user.id)
    assert facts[asset_set.id].downloading == true
    assert facts[asset_set.id].download_percent == 80
  end

  test "facts_for_user returns facts only -- never a computed ladder rank" do
    {scope, device} = paired()
    asset_set = asset_set_fixture(scope.user.id)

    Availability.replace_for_device(device, [
      %{"asset_set_id" => asset_set.id, "verified" => true}
    ])

    facts = Availability.facts_for_user(scope.user.id)
    refute Map.has_key?(facts[asset_set.id], :state)
    refute Map.has_key?(facts[asset_set.id], :rank)
    refute Map.has_key?(facts[asset_set.id], :availability_state)
  end
end

defmodule Playstead.AvailabilitySequenceConcurrencyTest do
  @moduledoc """
  WR-07 sequence ordering under independent Postgres connections.

  The automatic sandbox mode gives each report its own committed transaction,
  so these tests exercise PostgreSQL's per-device upsert serialization rather
  than a shared test transaction.
  """

  use ExUnit.Case, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playstead.{Availability, Repo}

  @cleanup_tables ~w(device_availability_report_watermarks device_asset_availability asset_sets change_journal_entries idempotency_receipts capability_declarations device_credentials devices pairing_requests audit_log_entries recovery_codes setup_tokens users_tokens users)

  setup_all do
    Sandbox.mode(Repo, :auto)

    on_exit(fn ->
      Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  setup do
    on_exit(fn ->
      Sandbox.mode(Repo, :auto)
      Repo.query!("TRUNCATE #{Enum.join(@cleanup_tables, ", ")} RESTART IDENTITY CASCADE")
    end)
  end

  test "concurrent sequence-bearing replacements from an empty watermark keep the highest state" do
    scope = user_scope_fixture()
    %{device: device} = device_fixture(scope)
    older_asset = asset_set_fixture(scope.user.id, %{display_title: "Older report"})
    newer_asset = asset_set_fixture(scope.user.id, %{display_title: "Newer report"})
    parent = self()
    start_ref = make_ref()

    tasks =
      [
        {2, [%{"asset_set_id" => older_asset.id, "downloading" => true}]},
        {3, [%{"asset_set_id" => newer_asset.id, "verified" => true}]}
      ]
      |> Enum.map(fn {sequence, entries} ->
        Task.async(fn ->
          send(parent, {:ready, sequence})

          receive do
            {:start, ^start_ref} -> Availability.replace_for_device(device, entries, sequence)
          after
            5_000 -> raise "the concurrent report was never released"
          end
        end)
      end)

    assert_receive {:ready, 2}, 5_000
    assert_receive {:ready, 3}, 5_000
    Enum.each(tasks, &send(&1.pid, {:start, start_ref}))

    results = Enum.map(tasks, &Task.await(&1, 5_000))

    assert Enum.all?(results, fn
             {:ok, :replaced} -> true
             {:error, {:validation_failed, _detail}} -> true
             _ -> false
           end)

    facts = Availability.facts_for_user(scope.user.id)
    assert facts[newer_asset.id].verified
    refute Map.has_key?(facts, older_asset.id)
    assert accepted_sequence(device.id) == 3
  end

  test "a lower sequence reaching replacement after a higher report commits is rejected" do
    scope = user_scope_fixture()
    %{device: device} = device_fixture(scope)
    asset_set = asset_set_fixture(scope.user.id)

    assert {:ok, :replaced} =
             Availability.replace_for_device(
               device,
               [%{"asset_set_id" => asset_set.id, "verified" => true}],
               9
             )

    assert {:error, {:validation_failed, _detail}} =
             Availability.replace_for_device(
               device,
               [%{"asset_set_id" => asset_set.id, "downloading" => true}],
               8
             )

    assert Availability.facts_for_user(scope.user.id)[asset_set.id].verified
    refute Availability.facts_for_user(scope.user.id)[asset_set.id].downloading
    assert accepted_sequence(device.id) == 9
  end

  defp accepted_sequence(device_id) do
    case Repo.query!(
           "SELECT accepted_report_sequence FROM device_availability_report_watermarks WHERE device_id = $1",
           [Ecto.UUID.dump!(device_id)]
         ).rows do
      [[sequence]] -> sequence
      [] -> nil
    end
  end
end
