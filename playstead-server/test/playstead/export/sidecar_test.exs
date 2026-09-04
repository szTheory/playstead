defmodule Playstead.Export.SidecarTest do
  use Playstead.DataCase, async: false

  import Playstead.ImportFixtures

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Export.{BagitWriter, SavesPlan, Sidecar, Verifier}

  setup do
    File.mkdir_p!(LocalDisk.blob_path())

    tmp =
      Path.join(System.tmp_dir!(), "playstead-sidecar-#{System.unique_integer([:positive])}")

    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, target_dir: tmp}
  end

  defp put(bytes), do: Playstead.Blobs.put_stream([bytes], byte_size(bytes))

  defp ts(offset_seconds), do: DateTime.add(~U[2026-01-01 00:00:00Z], offset_seconds, :second)

  defp revision(sha256, size_bytes, overrides) do
    Map.merge(
      %{
        id: Ecto.UUID.generate(),
        sha256: sha256,
        size_bytes: size_bytes,
        recorded_at: ts(0),
        save_kind: "system_save",
        is_head: true,
        branch_key: nil
      },
      Map.new(overrides)
    )
  end

  defp set_plan(overrides) do
    Map.merge(
      %{
        set_id: Ecto.UUID.generate(),
        relative_dir: "gba/Test Game",
        system_id: "gba",
        display_title: "Test Game",
        status: "complete",
        member_fingerprint: "fp-1",
        members: []
      },
      Map.new(overrides)
    )
  end

  test "the root sidecar carries a saves marker with branches always present" do
    root = Sidecar.root()
    assert root["saves"]["kind"] == "saves"
    assert root["saves"]["branches"] == []
    refute root["saves"]["kind"] == "reserved"
  end

  test "a linear line serialises as a single-element branches list, never a bare flat entry list" do
    {sha256, _} = digest_and_content()
    saves_plan = SavesPlan.plan([revision(sha256, 32_768, [])], primary_basename: "game.gba")
    sidecar = Sidecar.set(set_plan(saves_plan: saves_plan))

    assert [%{"branch" => nil, "revisions" => [_one]}] = sidecar["saves"]["branches"]
    refute Map.has_key?(sidecar["saves"], "entries")
  end

  test "a diverged line serialises as a multi-element branches list" do
    {sha_a, _} = digest_and_content()
    {sha_b, _} = digest_and_content()

    left = revision(sha_a, 32_768, branch_key: "left-fork")
    right = revision(sha_b, 32_768, branch_key: "right-fork")

    saves_plan = SavesPlan.plan([left, right], primary_basename: "game.gba")
    sidecar = Sidecar.set(set_plan(saves_plan: saves_plan))

    assert length(sidecar["saves"]["branches"]) == 2
    assert sidecar["saves"]["drop_in"] == nil
  end

  test "a set with no revisions serialises branches as an empty list, and the saves key is present" do
    saves_plan = SavesPlan.plan([])
    sidecar = Sidecar.set(set_plan(saves_plan: saves_plan))

    assert sidecar["saves"]["branches"] == []
    assert sidecar["saves"]["kind"] == "saves"
  end

  test "a set plan carrying no :saves_plan key at all still emits a well-formed saves entry" do
    sidecar = Sidecar.set(set_plan(%{}))

    assert sidecar["saves"]["kind"] == "saves"
    assert sidecar["saves"]["branches"] == []
  end

  test "saves.txt lists every exported revision with digest, size, origin, and branch, matching sidecar order",
       %{target_dir: target_dir} do
    {sha_a, _bytes_a} = digest_and_content()
    {sha_b, _bytes_b} = digest_and_content()

    left = revision(sha_a, 32_768, recorded_at: ts(0), branch_key: "left-fork")
    right = revision(sha_b, 32_768, recorded_at: ts(1), branch_key: "right-fork")

    saves_plan = SavesPlan.plan([left, right], primary_basename: "game.gba")

    layout = %{
      sets: [
        set_plan(
          saves_plan: saves_plan,
          members: []
        )
      ],
      quarantine: []
    }

    {:ok, _} = BagitWriter.write_bag(target_dir, layout)

    saves_txt_path = Path.join([target_dir, "tags", "gba", "Test Game", "saves.txt"])
    assert File.exists?(saves_txt_path)

    content = File.read!(saves_txt_path)
    assert content =~ "Test Game"
    assert content =~ "Branch a"
    assert content =~ "Branch b"
    assert content =~ String.slice(sha_a, 0, 8)
    assert content =~ String.slice(sha_b, 0, 8)
  end

  test "a revision whose bytes never uploaded is absent from the payload manifest but present in the sidecar as missing",
       %{target_dir: target_dir} do
    fake_sha256 = :crypto.hash(:sha256, "never-uploaded") |> Base.encode16(case: :lower)
    missing = revision(fake_sha256, 32_768, bytes: :missing)

    saves_plan = SavesPlan.plan([missing], primary_basename: "game.gba")

    layout = %{
      sets: [set_plan(saves_plan: saves_plan)],
      quarantine: []
    }

    {:ok, _} = BagitWriter.write_bag(target_dir, layout)

    manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    refute manifest =~ fake_sha256
    refute File.exists?(Path.join(target_dir, "fetch.txt"))

    sidecar_path = Path.join([target_dir, "tags", "gba", "Test Game", "playstead-set.json"])
    {:ok, decoded} = Sidecar.parse(File.read!(sidecar_path))

    [%{"revisions" => [rev]}] = decoded["saves"]["branches"]
    assert rev["bytes"] == "missing"
    assert rev["sha256"] == fake_sha256
    assert rev["path"] == nil
  end

  test "sha256sum -c over an exported manifest succeeds on a bag containing a missing-bytes revision",
       %{target_dir: target_dir} do
    {present_sha256, _bytes} = digest_and_content()
    fake_sha256 = :crypto.hash(:sha256, "still never uploaded") |> Base.encode16(case: :lower)

    present = revision(present_sha256, 32_768, recorded_at: ts(0))
    missing = revision(fake_sha256, 32_768, recorded_at: ts(1), bytes: :missing)

    saves_plan = SavesPlan.plan([present, missing], primary_basename: "game.gba")

    layout = %{
      sets: [set_plan(saves_plan: saves_plan)],
      quarantine: []
    }

    {:ok, _} = BagitWriter.write_bag(target_dir, layout)

    assert {:ok, %{checked: checked}} = Verifier.verify(target_dir)
    assert checked > 0
  end

  test "the sidecar carries the reconstruction fields a future reimport would need (round-trip door stays open)" do
    {sha256, _} = digest_and_content()
    r = revision(sha256, 32_768, [])
    saves_plan = SavesPlan.plan([r], primary_basename: "game.gba")
    sidecar = Sidecar.set(set_plan(saves_plan: saves_plan))

    [%{"revisions" => [entry]}] = sidecar["saves"]["branches"]

    for key <- ["seq", "sha256", "size_bytes", "bytes", "path"] do
      assert Map.has_key?(entry, key), "missing reconstruction field #{key}"
    end
  end

  defp digest_and_content do
    bytes = random_bytes(1_024)
    {:ok, :stored, meta} = put(bytes)
    {meta.sha256, bytes}
  end
end
