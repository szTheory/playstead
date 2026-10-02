defmodule Playstead.Recovery.UpgradeTest do
  use ExUnit.Case, async: true

  alias Playstead.Recovery.Upgrade

  @backup %{
    "receipt_id" => "backup-1",
    "verified_at" => "2026-09-20T00:00:00Z",
    "independence" => "operator_attested",
    "verification" => %{"state" => "verified"}
  }

  @preflight %{
    prior_digest: "sha256:" <> String.duplicate("a", 64),
    target_digest: "sha256:" <> String.duplicate("b", 64),
    backup: @backup,
    capacity: %{state: :green},
    schema: %{state: :compatible, prior_can_read_target: true},
    integrity: %{database: :green, blobs: :green},
    correlation_id: "upgrade-correlation"
  }

  test "preflight records immutable evidence before permitting an update" do
    assert {:ok, receipt} = Upgrade.preflight(@preflight)
    assert receipt["state"] == "ready"
    assert receipt["prior_release_digest"] == @preflight.prior_digest
    assert receipt["backup_receipt_id"] == "backup-1"
    assert receipt["action"] == "controlled_compose_update"
  end

  test "refuses an update without an independently verified backup" do
    assert {:error, receipt} =
             Upgrade.preflight(%{@preflight | backup: %{"receipt_id" => "backup-1"}})

    assert receipt["code"] == "upgrade_preflight_backup_unverified"
    assert receipt["action"] == "blocked"
  end

  test "refuses incompatible schemas and insufficient capacity" do
    assert {:error, schema} = Upgrade.preflight(%{@preflight | schema: %{state: :incompatible}})
    assert schema["code"] == "upgrade_preflight_schema_incompatible"

    assert {:error, capacity} = Upgrade.preflight(%{@preflight | capacity: %{state: :blocked}})
    assert capacity["code"] == "upgrade_preflight_capacity_blocked"
  end

  test "selects app-only rollback only with compatibility and both integrity checks" do
    assert {:ok, receipt} = Upgrade.rollback_branch(@preflight)
    assert receipt["branch"] == "app_only"

    assert {:ok, fallback} =
             Upgrade.rollback_branch(%{
               @preflight
               | integrity: %{database: :green, blobs: :failed}
             })

    assert fallback["branch"] == "clean_room_database_and_blobs"
    assert fallback["restore_proof"] == "playstead.restore"
  end

  test "replays a prior decision without changing its evidence" do
    assert {:ok, receipt} = Upgrade.preflight(@preflight)
    assert {:ok, ^receipt} = Upgrade.preflight(@preflight, receipt)

    assert {:error, conflict} =
             Upgrade.preflight(
               %{@preflight | target_digest: "sha256:" <> String.duplicate("c", 64)},
               receipt
             )

    assert conflict["code"] == "upgrade_preflight_replay_conflict"
  end
end
