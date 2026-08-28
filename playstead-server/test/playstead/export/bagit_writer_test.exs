defmodule Playstead.Export.BagitWriterTest do
  use Playstead.DataCase, async: false

  import Playstead.ImportFixtures

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Export.{BagitWriter, Layout, Sidecar}

  setup do
    File.mkdir_p!(LocalDisk.blob_path())

    tmp =
      Path.join(System.tmp_dir!(), "playstead-bagit-writer-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, target_dir: tmp}
  end

  defp put(bytes), do: Playstead.Blobs.put_stream([bytes], byte_size(bytes))

  defp set_layout(members) do
    Layout.plan([
      %{
        id: Ecto.UUID.generate(),
        system_id: "gba",
        display_title: "Test Game",
        status: "complete",
        member_fingerprint: "fp-1",
        excluded: false,
        members: members
      }
    ])
  end

  test "writes a genuinely RFC 8493 bag with sidecars and a payload-only manifest", %{
    target_dir: target_dir
  } do
    bytes = random_bytes(4_096)
    {:ok, :stored, meta} = put(bytes)

    layout =
      set_layout([
        %{
          ordinal: 0,
          role: "primary",
          required: true,
          declared_name: "game.gba",
          sha256: meta.sha256,
          size_bytes: meta.size_bytes
        }
      ])

    assert {:ok, %{target_dir: ^target_dir}} = BagitWriter.write_bag(target_dir, layout)

    for name <-
          ~w(bagit.txt bag-info.txt manifest-sha256.txt tagmanifest-sha256.txt playstead-bag.json) do
      assert File.exists?(Path.join(target_dir, name))
    end

    manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    lines = String.split(manifest, "\n", trim: true)
    assert length(lines) == 1
    assert [line] = lines
    assert line =~ ~r/^[0-9a-f]{64}  data\/.+$/

    [manifest_sha256, relative] = String.split(line, "  ", parts: 2)
    assert manifest_sha256 == meta.sha256
    assert File.read!(Path.join(target_dir, relative)) == bytes

    # The per-set sidecar is a tag file, not payload — never appears in
    # the payload manifest.
    refute manifest =~ "playstead-set.json"

    assert File.exists?(Path.join([target_dir, "tags", "gba", "Test Game", "playstead-set.json"]))
  end

  test "the root sidecar carries the schema identifier, no timestamps, and reserves saves", %{
    target_dir: target_dir
  } do
    layout = set_layout([])
    assert {:ok, _} = BagitWriter.write_bag(target_dir, layout)

    {:ok, decoded} = Sidecar.parse(File.read!(Path.join(target_dir, "playstead-bag.json")))
    assert decoded["schema"] == Sidecar.schema_id()
    refute Map.has_key?(decoded, "timestamp")
    refute Map.has_key?(decoded, "generated_at")
    assert decoded["saves"]["entries"] == []
  end

  test "a sidecar with an unknown major schema version is ignored rather than parsed" do
    content = ~s({"schema":"playstead-bag/99.0"})
    assert Sidecar.parse(content) == :ignore
  end

  test "the second-pass fsync-then-rename write path never leaves a temp sibling behind", %{
    target_dir: target_dir
  } do
    bytes = random_bytes(512)
    {:ok, :stored, meta} = put(bytes)

    layout =
      set_layout([
        %{
          ordinal: 0,
          role: "primary",
          required: true,
          declared_name: "game.gba",
          sha256: meta.sha256,
          size_bytes: meta.size_bytes
        }
      ])

    assert {:ok, _} = BagitWriter.write_bag(target_dir, layout)

    tmp_files =
      target_dir
      |> Path.join("**/*.tmp-*")
      |> Path.wildcard()

    assert tmp_files == []
  end

  test "refuses a non-empty target without this export's own marker", %{target_dir: target_dir} do
    File.write!(Path.join(target_dir, "unrelated.txt"), "pre-existing")
    layout = set_layout([])

    assert {:error, :target_not_empty} = BagitWriter.write_bag(target_dir, layout)
    assert File.read!(Path.join(target_dir, "unrelated.txt")) == "pre-existing"
  end
end
