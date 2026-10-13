defmodule Playstead.Recovery.VerifierTest do
  use ExUnit.Case, async: true

  alias Playstead.Recovery.Verifier

  test "rejects a missing parent and a cyclic parent chain before publication" do
    full = %{"id" => "full", "kind" => "full", "parent" => nil}

    incremental = %{
      "id" => "incremental",
      "kind" => "incremental",
      "parent" => %{"receipt_id" => "full"}
    }

    assert :ok = Verifier.verify_chain([full, incremental])
    assert {:error, :missing_parent} = Verifier.verify_chain([incremental])

    cyclic = %{"id" => "full", "kind" => "incremental", "parent" => %{"receipt_id" => "full"}}
    assert {:error, :parent_cycle} = Verifier.verify_chain([cyclic])
  end

  test "requires an incremental inventory to be complete and ordered" do
    assert {:error, :incomplete_inventory} =
             Verifier.verify_incremental_coverage(
               [%{"sha256" => "a"}],
               [%{"sha256" => "a"}, %{"sha256" => "b"}],
               []
             )

    assert :ok =
             Verifier.verify_incremental_coverage(
               [%{"sha256" => "a"}, %{"sha256" => "b"}],
               [%{"sha256" => "a"}],
               ["b"]
             )
  end
end
