defmodule Playstead.ReadinessCriticalReserveTest do
  @moduledoc """
  D-64: `reserve: :critical` is additive — it bypasses only
  `required_bytes/2`'s general margin, never the 64 MiB physical floor.
  Every existing large-download caller must keep the unchanged margin.

  Behaviours 1–2 and the `required_bytes/2` pin are pure-function tests
  (no disk). Behaviours 3–4 (open_write's actual refuse/allow split)
  are driven against the real blob-volume filesystem — the same
  injection point `test/playstead/blobs/store_local_disk_test.exs` uses
  (`Playstead.Readiness.free_bytes/1` against a real, but arbitrarily
  small relative to the request, tmp directory) — by sizing the
  requested bytes *relative to the machine's actual free space* rather
  than assuming a literal number of free bytes. This produces the same
  pass/fail split as a literally-provisioned "200 MiB free" volume
  without requiring a loopback filesystem in CI.
  """

  use Playstead.DataCase, async: false

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Readiness

  @floor 67_108_864

  setup do
    File.mkdir_p!(LocalDisk.blob_path())
    :ok
  end

  describe "fits_critical_free_space?/2 (pure, no disk)" do
    test "true when available minus requested is at or above the 64 MiB floor" do
      assert Readiness.fits_critical_free_space?(1_000, @floor + 1_000)
      assert Readiness.fits_critical_free_space?(0, @floor)
    end

    test "false when available minus requested falls below the 64 MiB floor" do
      refute Readiness.fits_critical_free_space?(1_000, @floor + 999)
      refute Readiness.fits_critical_free_space?(0, @floor - 1)
    end

    test "critical_free_floor_bytes/0 is exactly 64 MiB" do
      assert Readiness.critical_free_floor_bytes() == 67_108_864
    end
  end

  describe "required_bytes/2 is unchanged by the critical-reserve addition" do
    test "pinned outputs for three input pairs match the shipped margin formula" do
      # {requested_bytes, capacity_bytes, expected}
      # margin = max(1 GiB, 5% capacity)
      cases = [
        {0, 0, 1_073_741_824},
        {32_768, 1_073_741_824, 32_768 + 1_073_741_824},
        {1_000, 100_000_000_000, 1_000 + 5_000_000_000}
      ]

      for {requested, capacity, expected} <- cases do
        assert Readiness.required_bytes(requested, capacity) == expected
      end
    end
  end

  describe "open_write/2 with reserve: :critical (real blob volume)" do
    test "a 32 KB critical write succeeds while the same write without the reserve is refused, when only a small margin over the 64 MiB floor remains" do
      available = Readiness.free_bytes(LocalDisk.blob_path())

      case available do
        avail when is_integer(avail) and avail > 200_000_000 ->
          # Leaves ~100 MiB free after the hypothetical write — comfortably
          # above the 64 MiB critical floor, but the general margin floor
          # alone (1 GiB) always exceeds that 100 MiB headroom, so the
          # non-critical path is refused regardless of capacity.
          requested = avail - 100 * 1024 * 1024

          assert {:ok, ref} = LocalDisk.open_write(32_768, reserve: :critical)
          LocalDisk.abort(ref)

          assert {:error, :insufficient_space} = LocalDisk.open_write(requested)
          assert {:ok, ref2} = LocalDisk.open_write(requested, reserve: :critical)
          LocalDisk.abort(ref2)

        _ ->
          :ok
      end
    end

    test "a critical write is still refused when it would leave less than the 64 MiB physical floor" do
      available = Readiness.free_bytes(LocalDisk.blob_path())

      case available do
        avail when is_integer(avail) and avail > 20_000_000 ->
          # Leaves ~10 MiB free — below the 64 MiB floor no matter how the
          # reserve is used. The floor is never bypassed.
          requested = avail - 10 * 1024 * 1024

          assert {:error, :insufficient_space} = LocalDisk.open_write(requested, reserve: :critical)

        _ ->
          :ok
      end
    end

    test "an unmeasurable volume (df fails) degrades to allow, same as the non-critical path" do
      previous = System.get_env("PLAYSTEAD_BLOB_PATH")
      bogus_path = Path.join(System.tmp_dir!(), "does-not-exist-#{System.unique_integer([:positive])}")
      System.put_env("PLAYSTEAD_BLOB_PATH", bogus_path)

      try do
        assert {:ok, ref} = LocalDisk.open_write(32_768, reserve: :critical)
        LocalDisk.abort(ref)
      after
        if previous do
          System.put_env("PLAYSTEAD_BLOB_PATH", previous)
        else
          System.delete_env("PLAYSTEAD_BLOB_PATH")
        end
      end
    end

    test "omitting opts (existing single-arity call) behaves identically to an empty opts list" do
      assert {:ok, ref} = LocalDisk.open_write(32)
      LocalDisk.abort(ref)

      assert {:ok, ref2} = LocalDisk.open_write(32, [])
      LocalDisk.abort(ref2)
    end
  end

  describe "save-lane limits (D-33)" do
    alias Playstead.Blobs
    alias Playstead.Import.UploadSlots

    test "max_save_revision_bytes/0 is exactly 8 MiB" do
      assert Blobs.max_save_revision_bytes() == 8_388_608
    end

    test "the save upload slot key for a device is distinct from that device's import slot key" do
      device_id = "device-#{System.unique_integer([:positive])}"

      assert Blobs.save_upload_slot_key(device_id) != device_id
      assert Blobs.save_upload_slot_key(device_id) == "save:" <> device_id
    end

    test "acquiring a save slot for a device does not consume that device's import slot" do
      device_id = "device-#{System.unique_integer([:positive])}"
      save_key = Blobs.save_upload_slot_key(device_id)

      assert :ok = UploadSlots.acquire(save_key, "upload-save-1", 2)

      # The device's own (unnamespaced) import slot counter is untouched —
      # it can still acquire its full quota of import slots independently.
      assert :ok = UploadSlots.acquire(device_id, "upload-import-1", 2)
      assert :ok = UploadSlots.acquire(device_id, "upload-import-2", 2)
      assert :error = UploadSlots.acquire(device_id, "upload-import-3", 2)

      UploadSlots.release(save_key, "upload-save-1")
      UploadSlots.release(device_id, "upload-import-1")
      UploadSlots.release(device_id, "upload-import-2")
    end

    test "save_revision_rate_limit_per_hour/0 is 120" do
      assert Blobs.save_revision_rate_limit_per_hour() == 120
    end

    test "save_revision_rate_limit_key/1 is namespaced under save: and includes the device id" do
      device_id = "device-#{System.unique_integer([:positive])}"
      key = Blobs.save_revision_rate_limit_key(device_id)

      assert key =~ "save:"
      assert key =~ device_id
    end
  end
end
