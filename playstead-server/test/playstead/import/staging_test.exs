defmodule Playstead.Import.StagingTest do
  use Playstead.DataCase, async: true

  alias Playstead.Import.{SourceFile, Staging}
  alias Playstead.Repo

  import Playstead.AccountsFixtures

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    root =
      Path.join(System.tmp_dir!(), "playstead-staging-test-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    user = owner_fixture()
    {:ok, root: root, user: user}
  end

  describe "preview/2" do
    test "reports file count, total bytes, and counts for recognized, unknown, and archive files",
         %{root: root} do
      File.write!(Path.join(root, "unknown.xyz"), "not a rom")
      File.write!(Path.join(root, "archive.zip"), <<0x50, 0x4B, 0x03, 0x04, 0, 0>>)

      preview = Staging.preview(root)

      assert preview.file_count == 2
      assert preview.total_bytes > 0
      assert preview.histogram.archive == 1
      assert preview.histogram.unknown == 1
    end

    test "lists a file above the configured per-file limit", %{root: root} do
      max = Application.get_env(:playstead, :max_upload_bytes)
      File.write!(Path.join(root, "huge.bin"), :binary.copy(<<0>>, max + 1))
      File.write!(Path.join(root, "small.bin"), "ok")

      preview = Staging.preview(root)

      assert Enum.any?(preview.over_limit_files, &(&1.relative_path == "huge.bin"))
      refute Enum.any?(preview.over_limit_files, &(&1.relative_path == "small.bin"))
    end

    test "creates no blob rows", %{root: root} do
      File.write!(Path.join(root, "game.gba"), "abc")

      Staging.preview(root)

      assert Repo.aggregate(Playstead.Blobs.Blob, :count) == 0
    end
  end

  describe "stage/3" do
    test "stages an empty folder as a completed session with zero files", %{
      root: root,
      user: user
    } do
      {:ok, session} = Staging.stage(user.id, root, "session-empty")

      assert session.file_count == 0
      assert session.state == "completed"
    end

    test "creates one source-file row per scanned file in relative-path order", %{
      root: root,
      user: user
    } do
      File.write!(Path.join(root, "b.bin"), "b")
      File.write!(Path.join(root, "a.bin"), "a")

      {:ok, session} = Staging.stage(user.id, root, "session-order")

      rows =
        from(sf in SourceFile,
          where: sf.import_session_id == ^session.id,
          order_by: sf.inserted_at
        )
        |> Repo.all()

      assert Enum.map(rows, & &1.relative_path) == ["a.bin", "b.bin"]
      assert Enum.all?(rows, &(&1.staging_state == "pending"))
    end

    test "refuses a folder above the session file cap before writing any row", %{
      root: root,
      user: user
    } do
      Application.put_env(:playstead, :max_session_files, 1)
      on_exit(fn -> Application.put_env(:playstead, :max_session_files, 250_000) end)

      File.write!(Path.join(root, "a.bin"), "a")
      File.write!(Path.join(root, "b.bin"), "b")

      assert {:error, :import_session_too_large} =
               Staging.stage(user.id, root, "session-too-large")

      assert Repo.aggregate(Playstead.Import.Session, :count) == 0
    end
  end
end
