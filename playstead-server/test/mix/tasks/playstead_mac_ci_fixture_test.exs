defmodule Mix.Tasks.Playstead.MacCiFixtureTest do
  use Playstead.DataCase, async: false

  alias Mix.Tasks.Playstead.MacCiFixture
  alias Playstead.Blobs
  alias Playstead.Accounts.Scope
  alias Playstead.Catalogue
  alias Playstead.Pairing
  alias Playstead.Sync.Snapshot

  setup do
    blob_root =
      Path.join(
        System.tmp_dir!(),
        "playstead-mac-ci-fixture-#{System.unique_integer([:positive])}"
      )

    previous = System.get_env("PLAYSTEAD_BLOB_PATH")
    System.put_env("PLAYSTEAD_BLOB_PATH", blob_root)

    on_exit(fn ->
      File.rm_rf!(blob_root)

      if previous do
        System.put_env("PLAYSTEAD_BLOB_PATH", previous)
      else
        System.delete_env("PLAYSTEAD_BLOB_PATH")
      end
    end)

    :ok
  end

  test "provisions the owner and exact public synthetic sentinel through production contexts" do
    fixture = MacCiFixture.provision!()

    assert fixture.sentinel.title == "Playstead CI Sentinel One"
    assert is_binary(fixture.sentinel.asset_set_id)
    assert fixture.sentinel.byte_size > 0

    [entry] = Catalogue.list_assets(Scope.for_user(fixture.owner))
    assert entry.asset_set.id == fixture.sentinel.asset_set_id
    assert entry.asset_set.display_title == fixture.sentinel.title
  end

  test "exact approval accepts only the sole pending request with matching public claims" do
    fixture = MacCiFixture.provision!()
    device_code = "fixture-device-code-that-never-leaves-this-test"

    {:ok, request} =
      Pairing.create_request(%{
        "device_code" => device_code,
        "device_name" => MacCiFixture.device_label(),
        "platform" => "macOS CI",
        "app_version" => "1",
        "capabilities" => %{},
        "requesting_ip" => "127.0.0.1"
      })

    approved =
      MacCiFixture.approve_exact!(fixture.owner, %{
        request_id: request.id,
        display_code: request.display_code,
        device_label: MacCiFixture.device_label()
      })

    assert approved.id == request.id
    assert approved.display_code == request.display_code
    assert approved.status == "approved"
    assert Pairing.list_pending_requests(Scope.for_user(fixture.owner)) == []
  end

  test "the prepared sentinel is in the first paired snapshot before any download" do
    fixture = MacCiFixture.provision!()
    {:ok, request} = pairing_request("snapshot-fixture-device-code")

    MacCiFixture.approve_exact!(fixture.owner, %{
      request_id: request.id,
      display_code: request.display_code,
      device_label: MacCiFixture.device_label()
    })

    {:ok, page} = Snapshot.read(fixture.owner.id)
    assert [entry] = page.catalogue
    assert entry.id == fixture.sentinel.asset_set_id
    assert entry.display_title == fixture.sentinel.title
    assert is_binary(page.cursor) and byte_size(page.cursor) > 0
    refute page.has_more
    assert page.next_after_id == nil
  end

  test "approval fails closed when any request identity claim differs or the queue is not sole" do
    fixture = MacCiFixture.provision!()
    owner = fixture.owner

    {:ok, request} = pairing_request("first-device-code")

    assert_raise ArgumentError, ~r/display code/, fn ->
      MacCiFixture.approve_exact!(owner, %{
        request_id: request.id,
        display_code: "WRONG",
        device_label: MacCiFixture.device_label()
      })
    end

    {:ok, _other} = pairing_request("second-device-code")

    assert_raise ArgumentError, ~r/sole pending/, fn ->
      MacCiFixture.approve_exact!(owner, %{
        request_id: request.id,
        display_code: request.display_code,
        device_label: MacCiFixture.device_label()
      })
    end
  end

  test "approve-sole approves the sole pending request by display code and device label alone" do
    fixture = MacCiFixture.provision!()
    {:ok, request} = pairing_request("sole-approval-device-code")

    approved =
      MacCiFixture.approve_sole!(fixture.owner, %{
        display_code: request.display_code,
        device_label: MacCiFixture.device_label()
      })

    assert approved.id == request.id
    assert approved.status == "approved"
    assert Pairing.list_pending_requests(Scope.for_user(fixture.owner)) == []
  end

  test "approve-sole fails closed on a display code mismatch or a non-sole queue" do
    fixture = MacCiFixture.provision!()
    owner = fixture.owner

    {:ok, _request} = pairing_request("sole-mismatch-device-code")

    assert_raise ArgumentError, ~r/display code/, fn ->
      MacCiFixture.approve_sole!(owner, %{
        display_code: "WRONG",
        device_label: MacCiFixture.device_label()
      })
    end

    {:ok, _second} = pairing_request("sole-second-device-code")

    assert_raise ArgumentError, ~r/sole pending/, fn ->
      MacCiFixture.approve_sole!(owner, %{
        display_code: "WRONG",
        device_label: MacCiFixture.device_label()
      })
    end
  end

  test "adds a distinct second sentinel without replacing the first" do
    fixture = MacCiFixture.provision!()
    second = MacCiFixture.add_second_sentinel!(fixture.owner)

    assert second.title == "Playstead CI Sentinel Two"
    refute second.asset_set_id == fixture.sentinel.asset_set_id

    assert Catalogue.list_assets(Scope.for_user(fixture.owner))
           |> Enum.map(& &1.asset_set.display_title)
           |> Enum.sort() == ["Playstead CI Sentinel One", "Playstead CI Sentinel Two"]
  end

  test "provision resets a prior snapshot test's second sentinel from later mirrors" do
    fixture = MacCiFixture.provision!()
    second = MacCiFixture.add_second_sentinel!(fixture.owner)

    assert Catalogue.list_assets(Scope.for_user(fixture.owner))
           |> Enum.map(& &1.asset_set.display_title)
           |> Enum.sort() == ["Playstead CI Sentinel One", "Playstead CI Sentinel Two"]

    {:ok, second_detail} =
      Catalogue.get_asset_detail(Scope.for_user(fixture.owner), second.asset_set_id)

    [second_member] = second_detail.asset_set.asset_members
    second_sha256 = second_member.blob.sha256

    reprovisioned = MacCiFixture.provision!()

    assert reprovisioned.sentinel.asset_set_id == fixture.sentinel.asset_set_id

    assert Catalogue.list_assets(Scope.for_user(fixture.owner))
           |> Enum.map(& &1.asset_set.display_title) == ["Playstead CI Sentinel One"]

    assert {:error, :not_found} =
             Catalogue.get_asset_detail(Scope.for_user(fixture.owner), second.asset_set_id)

    assert {:ok, _stat} = Blobs.stat(second_sha256)
    {:ok, page} = Snapshot.read(fixture.owner.id)
    assert [snapshot_sentinel] = page.catalogue
    assert snapshot_sentinel.display_title == "Playstead CI Sentinel One"
  end

  defp pairing_request(device_code) do
    Pairing.create_request(%{
      "device_code" => device_code,
      "device_name" => MacCiFixture.device_label(),
      "platform" => "macOS CI",
      "app_version" => "1",
      "capabilities" => %{},
      "requesting_ip" => "127.0.0.1"
    })
  end
end
