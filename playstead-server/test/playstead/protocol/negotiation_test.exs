defmodule Playstead.Protocol.NegotiationTest do
  use Playstead.DataCase, async: true

  import Playstead.PairingFixtures
  import Playstead.AccountsFixtures

  alias Playstead.Protocol.Negotiation

  @server_ranges %{
    protocol: %{min: "1.0.0", max: "1.2.0"},
    app: %{min: "1.0.0", max: "1.0.0"},
    cache: %{min: "1.0.0", max: "1.0.0"},
    transfer: %{min: "1.0.0", max: "1.0.0"},
    adapter: %{min: "1.0.0", max: "1.0.0"},
    save: %{min: "1.0.0", max: "1.0.0"}
  }

  defp full_hello(protocol_range) do
    %{
      "protocol" => %{"min" => protocol_range.min, "max" => protocol_range.max},
      "app" => %{"min" => "1.0.0", "max" => "1.0.0"},
      "cache" => %{"min" => "1.0.0", "max" => "1.0.0"},
      "transfer" => %{"min" => "1.0.0", "max" => "1.0.0"},
      "adapter" => %{"min" => "1.0.0", "max" => "1.0.0"},
      "save" => %{"min" => "1.0.0", "max" => "1.0.0"}
    }
  end

  describe "verdict/2 — range combinations" do
    test "client-newer with overlap is compatible" do
      hello = full_hello(%{min: "1.1.0", max: "1.3.0"})
      assert %{verdict: :compatible} = Negotiation.verdict(hello, @server_ranges)
    end

    test "server-newer with overlap is compatible" do
      hello = full_hello(%{min: "0.9.0", max: "1.0.5"})
      assert %{verdict: :compatible} = Negotiation.verdict(hello, @server_ranges)
    end

    test "exact-overlap (identical ranges) is compatible" do
      hello = full_hello(%{min: "1.0.0", max: "1.2.0"})
      assert %{verdict: :compatible} = Negotiation.verdict(hello, @server_ranges)
    end

    test "no-overlap on the required protocol namespace, client too old, is incompatible" do
      hello = full_hello(%{min: "0.1.0", max: "0.5.0"})
      assert %{verdict: :incompatible, remedy: remedy} = Negotiation.verdict(hello, @server_ranges)
      assert remedy.side_too_old == :client
      assert remedy.who_must_act == "user"
      assert remedy.minimum_required == "1.0.0"
      assert is_binary(remedy.detail_url)
    end

    test "no-overlap on the required protocol namespace, server too old, is incompatible" do
      hello = full_hello(%{min: "2.0.0", max: "2.5.0"})
      assert %{verdict: :incompatible, remedy: remedy} = Negotiation.verdict(hello, @server_ranges)
      assert remedy.side_too_old == :server
      assert remedy.who_must_act == "server_admin"
      assert remedy.minimum_required == "2.0.0"
    end

    test "optional-unsupported namespace degrades to compatible_with_limits, not incompatible" do
      hello =
        full_hello(%{min: "1.0.0", max: "1.0.0"})
        |> Map.put("adapter", %{"min" => "2.0.0", "max" => "2.5.0"})

      assert %{verdict: :compatible_with_limits, ignored: ["adapter"]} =
               Negotiation.verdict(hello, @server_ranges)
    end

    test "unknown capability key produces the same verdict as the same hello without it" do
      base = full_hello(%{min: "1.0.0", max: "1.0.0"})
      with_unknown = Map.put(base, "quantum_teleport", %{"min" => "9.9.9", "max" => "9.9.9"})

      assert Negotiation.verdict(base, @server_ranges) ==
               Negotiation.verdict(with_unknown, @server_ranges)
    end
  end

  describe "store_declaration/2" do
    test "repeating an identical hello leaves exactly one declaration row" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      capabilities = full_hello(%{min: "1.0.0", max: "1.0.0"})

      {:ok, _} = Negotiation.store_declaration(device.id, capabilities)
      {:ok, _} = Negotiation.store_declaration(device.id, capabilities)

      count =
        Playstead.Protocol.CapabilityDeclaration
        |> Playstead.Repo.all()
        |> Enum.count(&(&1.device_id == device.id))

      assert count == 1
    end

    test "two concurrent identical hellos leave exactly one declaration row" do
      scope = user_scope_fixture()
      %{device: device} = device_fixture(scope)
      capabilities = full_hello(%{min: "1.0.0", max: "1.0.0"})

      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Playstead.Repo, parent, self())
            Negotiation.store_declaration(device.id, capabilities)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      count =
        Playstead.Protocol.CapabilityDeclaration
        |> Playstead.Repo.all()
        |> Enum.count(&(&1.device_id == device.id))

      assert count == 1
    end
  end
end
