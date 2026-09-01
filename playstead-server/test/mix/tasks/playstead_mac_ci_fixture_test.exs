defmodule Mix.Tasks.Playstead.MacCiFixtureTest do
  use Playstead.DataCase, async: false

  alias Mix.Tasks.Playstead.MacCiFixture
  alias Playstead.Accounts.Scope
  alias Playstead.Catalogue
  alias Playstead.Pairing

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

  test "adds a distinct second sentinel without replacing the first" do
    fixture = MacCiFixture.provision!()
    second = MacCiFixture.add_second_sentinel!(fixture.owner)

    assert second.title == "Playstead CI Sentinel Two"
    refute second.asset_set_id == fixture.sentinel.asset_set_id

    assert Catalogue.list_assets(Scope.for_user(fixture.owner))
           |> Enum.map(& &1.asset_set.display_title)
           |> Enum.sort() == ["Playstead CI Sentinel One", "Playstead CI Sentinel Two"]
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
