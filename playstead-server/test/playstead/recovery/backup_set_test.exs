defmodule Playstead.Recovery.BackupSetTest do
  use ExUnit.Case, async: true

  alias Playstead.Recovery.{BackupSet, Verifier}

  setup do
    root =
      Path.join(System.tmp_dir!(), "playstead-recovery-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, root: root}
  end

  test "builds a deterministic full manifest with a required dump even for an empty inventory" do
    attrs = %{
      id: "backup-1",
      correlation_id: "corr-1",
      kind: :full,
      dump: %{relative: "database.dump", bytes: "pg dump"},
      members: [
        %{sha256: String.duplicate("a", 64), bytes: "a", kind: :game},
        %{sha256: String.duplicate("b", 64), bytes: "bb", kind: :save}
      ],
      metadata: %{release: "test", configuration: %{storage: "local"}}
    }

    assert {:ok, first} = BackupSet.build(attrs)
    assert {:ok, second} = BackupSet.build(Map.put(attrs, :members, Enum.reverse(attrs.members)))
    assert first.manifest == second.manifest
    assert first.manifest["schema"] == "playstead.backup-set.v1"
    assert first.manifest["coverage"]["inventory_count"] == 2

    assert {:error, :missing_dump} = BackupSet.build(%{attrs | dump: nil, members: []})
  end

  test "publishes only after a second-pass verifier rereads all members", %{root: root} do
    attrs = %{
      id: "backup-2",
      correlation_id: "corr-2",
      kind: :full,
      dump: %{relative: "database.dump", bytes: "portable dump"},
      members: [%{sha256: String.duplicate("c", 64), bytes: "game", kind: :game}],
      metadata: %{release: "test", configuration: %{}}
    }

    assert {:ok, set} = BackupSet.build(attrs)
    assert {:ok, published} = BackupSet.publish(root, set, attested: true)
    assert File.regular?(Path.join(published.path, "receipt.json"))
    assert {:ok, %{checked: 3}} = Verifier.verify(published.path)

    File.write!(Path.join(published.path, "database.dump"), "corrupted")
    assert {:error, {:mismatches, ["database.dump"]}} = Verifier.verify(published.path)
  end

  test "refuses destinations within canonical storage", %{root: root} do
    assert {:error, :destination_overlaps_canonical} =
             BackupSet.validate_destination(Path.join(root, "backups"), root)
  end

  test "materializes only the persisted command inventory" do
    command = %{
      "schema" => "playstead.recovery-command.v1",
      "id" => "backup-command",
      "correlation_id" => "corr-command",
      "kind" => "full",
      "inventory" => [%{"sha256" => String.duplicate("d", 64), "kind" => "cas"}],
      "metadata" => %{"release" => "test", "configuration" => %{}, "parent" => nil}
    }

    assert {:error, :missing_dump_artifact} =
             BackupSet.materialize(command, fn _ -> {:ok, "immutable bytes"} end)
  end

  test "captures a custom-format dump using the exported PostgreSQL snapshot", %{root: root} do
    assert {:ok, dump_path} =
             BackupSet.capture_dump("00000003-0000002A-1", root,
               database_url: "postgres://backup:secret@example.test/playstead",
               command_runner: fn executable, args, _opts ->
                 assert executable == "pg_dump"
                 assert "--format=custom" in args
                 assert "--snapshot" in args
                 assert "00000003-0000002A-1" in args
                 assert "--file" in args
                 assert "--dbname" in args
                 assert "postgres://backup:secret@example.test/playstead" in args

                 output_path = Enum.at(args, Enum.find_index(args, &(&1 == "--file")) + 1)
                 File.write!(output_path, "PGDMP real custom archive bytes")
                 {"", 0}
               end
             )

    assert File.regular?(dump_path)
    assert "PGDMP" <> _ = File.read!(dump_path)
  end

  test "does not accept command metadata as a database dump when capture fails", %{root: root} do
    assert {:error, :pg_dump_failed} =
             BackupSet.capture_dump("00000003-0000002A-1", root,
               database_url: "postgres://backup:secret@example.test/playstead",
               command_runner: fn _executable, _args, _opts -> {"password=secret", 1} end
             )

    refute File.exists?(Path.join(root, "database.dump"))
  end

  test "refuses an incomplete file-backed dump before an incremental set can publish", %{root: root} do
    dump_path = Path.join(root, "incomplete.dump")
    File.write!(dump_path, "not a PostgreSQL archive")

    assert {:error, :invalid_dump_artifact} =
             BackupSet.build(%{
               id: "incremental-incomplete",
               correlation_id: "corr-incomplete",
               kind: :incremental,
               dump: %{relative: "database.dump", path: dump_path},
               members: [],
               metadata: %{
                 release: "test",
                 configuration: %{},
                 parent: %{"receipt_id" => "full-receipt"}
               }
             })
  end

  test "does not publish when a file-backed dump changes after it is hashed", %{root: root} do
    dump_path = Path.join(root, "database.dump")
    File.write!(dump_path, "PGDMP complete archive")

    assert {:ok, set} =
             BackupSet.build(%{
               id: "corrupt-on-write",
               correlation_id: "corr-corrupt",
               kind: :full,
               dump: %{relative: "database.dump", path: dump_path},
               members: [],
               metadata: %{release: "test", configuration: %{}}
             })

    File.write!(dump_path, "PGDMP changed archive")

    assert {:error, {:mismatches, ["database.dump"]}} = BackupSet.publish(root, set)
    refute File.exists?(Path.join([root, "corrupt-on-write", "receipt.json"]))
  end
end
