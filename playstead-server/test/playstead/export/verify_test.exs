defmodule Playstead.Export.VerifyTest do
  use Playstead.DataCase, async: false

  import Playstead.ImportFixtures

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Export.{BagitWriter, Layout, Verifier}

  setup do
    File.mkdir_p!(LocalDisk.blob_path())

    tmp =
      Path.join(System.tmp_dir!(), "playstead-verify-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, target_dir: tmp}
  end

  defp put(bytes), do: Playstead.Blobs.put_stream([bytes], byte_size(bytes))

  defp write_one_member_bag!(target_dir) do
    bytes = random_bytes(1_024)
    {:ok, :stored, meta} = put(bytes)

    layout =
      Layout.plan([
        %{
          id: Ecto.UUID.generate(),
          system_id: "gba",
          display_title: "Verify Me",
          status: "complete",
          member_fingerprint: "fp-1",
          excluded: false,
          members: [
            %{
              ordinal: 0,
              role: "primary",
              required: true,
              declared_name: "game.gba",
              sha256: meta.sha256,
              size_bytes: meta.size_bytes
            }
          ]
        }
      ])

    {:ok, %{payload_entries: [entry]}} = BagitWriter.write_bag(target_dir, layout)
    entry
  end

  test "a clean bag verifies with zero mismatches", %{target_dir: target_dir} do
    write_one_member_bag!(target_dir)
    assert {:ok, %{checked: checked}} = Verifier.verify(target_dir)
    assert checked > 0
  end

  test "a payload file corrupted after writing is named as a mismatch and nothing is deleted", %{
    target_dir: target_dir
  } do
    entry = write_one_member_bag!(target_dir)
    payload_path = Path.join(target_dir, entry.relative)

    File.write!(payload_path, "corrupted bytes")

    assert {:error, {:mismatches, mismatches}} = Verifier.verify(target_dir)
    assert entry.relative in mismatches
    assert File.exists?(payload_path)
  end

  test "a missing payload file is reported as a mismatch rather than raising", %{
    target_dir: target_dir
  } do
    entry = write_one_member_bag!(target_dir)
    File.rm!(Path.join(target_dir, entry.relative))

    assert {:error, {:mismatches, mismatches}} = Verifier.verify(target_dir)
    assert entry.relative in mismatches
  end

  test "re-verifying an unmodified bag is idempotent", %{target_dir: target_dir} do
    write_one_member_bag!(target_dir)
    assert {:ok, _} = Verifier.verify(target_dir)
    assert {:ok, _} = Verifier.verify(target_dir)
  end
end
