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
