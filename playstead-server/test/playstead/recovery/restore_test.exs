defmodule Playstead.Recovery.RestoreTest do
  use ExUnit.Case, async: true

  alias Playstead.Recovery.{BackupSet, ComposeRunner, Restore}

  setup do
    root = Path.join(System.tmp_dir!(), "playstead-restore-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root}
  end

  test "restores only a published verified receipt chain into generated isolated resources", %{
    root: root
  } do
    backup_root = Path.join(root, "backups")
    target_root = Path.join(root, "restore-target")

    {:ok, set} =
      BackupSet.build(%{
        id: "full-restore",
        correlation_id: "restore-correlation",
        kind: :full,
        dump: %{relative: "database.dump", bytes: "portable dump"},
        members: [%{sha256: String.duplicate("a", 64), bytes: "game bytes", kind: :game}],
        metadata: %{release: "test", configuration: %{storage: "local"}}
      })

    {:ok, published} = BackupSet.publish(backup_root, set, attested: true)

    assert {:ok, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               stage_runner: fn
                 :cas, target ->
                   ca = Path.join(target["root"], "caddy-root-ca.pem")
                   :ok = File.write(ca, "parser fixture CA")
                   :ok = File.chmod(ca, 0o600)
                   :ok

                 _stage, _target ->
                   :ok
               end
             )

    assert receipt["state"] == "verified"
    assert receipt["stages"] == ["chain", "preflight", "database", "cas", "manifest", "api"]
    assert receipt["target"]["project"] != "playstead"
    assert File.regular?(Path.join(target_root, "restore-receipt.json"))
  end

  test "records a failed database stage and never calls subsequent stages", %{root: root} do
    published = publish_fixture!(root, "failed-stage")
    target_root = Path.join(root, "restore-target")

    assert {:error, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               stage_runner: fn
                 :database, _target -> {:error, :restore_rejected}
                 _stage, _target -> :ok
               end
             )

    assert receipt["failed_stage"] == "database"
    assert receipt["code"] == "restore_database_failed"
    assert receipt["stages"] == ["chain", "preflight"]

    assert Jason.decode!(File.read!(Path.join(target_root, "restore-receipt.json")))["state"] ==
             "failed"
  end

  test "refuses a canonical Compose identity before creating the target", %{root: root} do
    published = publish_fixture!(root, "canonical-overlap")
    target_root = Path.join(root, "restore-target")

    assert {:error, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead-restore-canonical",
               identity: "playstead-restore-canonical",
               target_root: target_root
             )

    assert receipt["failed_stage"] == "preflight"
    assert receipt["code"] == "restore_preflight_canonical_resource_overlap"
    refute File.exists?(target_root)
  end

  test "rejects corrupt receipts and canonical mount adjacency before any target write", %{
    root: root
  } do
    published = publish_fixture!(root, "corrupt-receipt")
    File.write!(Path.join(published.path, "receipt.json"), "{}")

    assert {:error, receipt} =
             Restore.run_chain([published.path],
               target_root: Path.join(root, "unused-target"),
               canonical_project: "playstead"
             )

    assert receipt["failed_stage"] == "chain"
    refute File.exists?(Path.join(root, "unused-target"))

    valid = publish_fixture!(root, "mount-adjacency")
    canonical = Path.join(root, "canonical")
    target_root = Path.join(canonical, "restore-child")

    assert {:error, mount_receipt} =
             Restore.run_chain([valid.path],
               canonical_project: "playstead",
               canonical_roots: [canonical],
               target_root: target_root
             )

    assert mount_receipt["code"] == "restore_preflight_canonical_mount_overlap"
    refute File.exists?(target_root)
  end

  test "refuses replayed Compose identities even when a caller changes the target path", %{
    root: root
  } do
    published = publish_fixture!(root, "identity-replay")
    identity = "playstead-restore-replay"

    assert {:ok, _} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               identity: identity,
               identity_root: root,
               target_root: Path.join(root, "first-target"),
               stage_runner: fn
                 :cas, target ->
                   ca = Path.join(target["root"], "caddy-root-ca.pem")
                   :ok = File.write(ca, "command-parser fixture CA")
                   :ok = File.chmod(ca, 0o600)
                   :ok

                 _stage, _target ->
                   :ok
               end
             )

    assert {:error, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               identity: identity,
               identity_root: root,
               target_root: Path.join(root, "second-target")
             )

    assert receipt["code"] == "restore_preflight_identity_reused"
    refute File.exists?(Path.join(root, "second-target"))
  end

  test "uses the concrete Compose runner by default and orders pg_restore before custody proof",
       %{
         root: root
       } do
    published = publish_fixture!(root, "concrete-runner")
    target_root = Path.join(root, "restore-target")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:command, command, args})
      {"", 0}
    end

    assert {:ok, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               command_executor: executor,
               api_probe: fn _target -> :ok end
             )

    assert receipt["state"] == "verified"
    assert_receive {:command, "docker", ["compose" | _]}
    assert_receive {:command, "docker", ["compose" | _]}
    assert Enum.member?(receipt["stages"], "database")
    assert Enum.member?(receipt["stages"], "api")
  end

  test "stages the verified custom archive in the isolated database before pg_restore", %{
    root: root
  } do
    published = publish_fixture!(root, "archive-staging")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:command, command, args})
      {"", 0}
    end

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               command_executor: executor,
               api_probe: fn _target -> :ok end
             )

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "cp",
                      _archive,
                      "db:/tmp/database.dump"
                    ]}

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "exec",
                      "-T",
                      "db",
                      "pg_restore" | restore_args
                    ]}

    assert List.last(restore_args) == "/tmp/database.dump"
  end

  test "waits until the exact isolated restore database accepts an authenticated query", %{
    root: root
  } do
    published = publish_fixture!(root, "database-readiness")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:command, command, args})
      {"", 0}
    end

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               command_executor: executor,
               api_probe: fn _target -> :ok end
             )

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "exec",
                      "-T",
                      "db",
                      "psql",
                      "-U",
                      "playstead_restore",
                      "-d",
                      "playstead_restore",
                      "-v",
                      "ON_ERROR_STOP=1",
                      "-c",
                      "SELECT 1"
                    ]}
  end

  test "shields every restore Compose command from exported canonical variables", %{root: root} do
    published = publish_fixture!(root, "restore-command-environment")
    parent = self()

    executor = fn command, args, opts ->
      send(parent, {:command, command, args, opts})
      {"", 0}
    end

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               command_executor: executor,
               api_probe: fn _target -> :ok end
             )

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "config",
                      "--quiet"
                    ], command_options}

    assert {"POSTGRES_USER", "playstead_restore"} in command_options[:env]
    assert {"POSTGRES_DB", "playstead_restore"} in command_options[:env]
  end

  test "replaces canonical Caddy port bindings with one loopback-only restore binding", %{
    root: root
  } do
    published = publish_fixture!(root, "loopback-port-override")
    target_root = Path.join(root, "restore-target")

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               command_executor: fn _command, _args, _opts -> {"", 0} end,
               api_probe: fn _target -> :ok end
             )

    override = File.read!(Path.join(target_root, "compose.restore.yml"))
    assert override =~ "ports: !override"
    assert override =~ ~r/127\.0\.0\.1:\d+:80/
    assert override =~ ~r/127\.0\.0\.1:\d+:443/
    assert override =~ ~s(CADDY_HTTP_PORT: "80")
    assert override =~ ~s(CADDY_HTTPS_PORT: "443")

    assert override =~
             ~r/networks:\n  default:\n    ipam:\n      config:\n        - subnet: 10\.253\.\d+\.0\/24/
  end

  test "generates a session key long enough for the restored browser session", %{root: root} do
    published = publish_fixture!(root, "browser-session-key")
    target_root = Path.join(root, "restore-target")

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               command_executor: fn _command, _args, _opts -> {"", 0} end,
               api_probe: fn _target -> :ok end
             )

    session_key =
      target_root
      |> Path.join(".restore.env")
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.find_value(fn
        "SECRET_KEY_BASE=" <> value -> value
        _ -> nil
      end)

    assert is_binary(session_key)
    assert byte_size(session_key) >= 64
  end

  test "sets localhost as the restored release's public Phoenix host", %{root: root} do
    published = publish_fixture!(root, "liveview-origin")
    target_root = Path.join(root, "restore-target")

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: target_root,
               command_executor: fn _command, _args, _opts -> {"", 0} end,
               api_probe: fn _target -> :ok end
             )

    assert File.read!(Path.join(target_root, ".restore.env")) =~ "PHX_HOST=localhost\n"
  end

  test "waits for the isolated proxy and copies only its CA before the API proof", %{root: root} do
    published = publish_fixture!(root, "proxy-ca")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:command, command, args})
      {"", 0}
    end

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               command_executor: executor,
               api_probe: fn _target -> :ok end
             )

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "exec",
                      "-T",
                      "caddy",
                      "caddy",
                      "version"
                    ]}

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "cp",
                      "caddy:/data/caddy/pki/authorities/local/root.crt",
                      _ca_path
                    ]}
  end

  test "repairs copied CAS-object ownership for the isolated non-root app", %{root: root} do
    bytes = "restored game bytes"
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:command, command, args})
      {"", 0}
    end

    published =
      publish_fixture!(root, "cas-ownership", [
        %{sha256: sha256(bytes), bytes: bytes, kind: :game}
      ])

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               command_executor: executor,
               api_probe: fn _target -> :ok end
             )

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "cp",
                      _hydrated_objects,
                      "app:/app/blobs/objects"
                    ]}

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "exec",
                      "-T",
                      "--user",
                      "0:0",
                      "app",
                      "chown",
                      "-R",
                      "nobody:nogroup",
                      "/app/blobs/objects"
                    ]}
  end

  test "mints the target-only API credential through the running isolated release", %{root: root} do
    published = publish_fixture!(root, "api-rpc")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:command, command, args})

      if command == "docker" and "rpc" in args,
        do: {"target-only-token-that-is-long-enough", 0},
        else: {"", 0}
    end

    assert {:ok, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               command_executor: executor
             )

    assert_receive {:command, "docker",
                    [
                      "compose",
                      "--project-name",
                      _project,
                      "--env-file",
                      _env,
                      "-f",
                      "docker-compose.yml",
                      "-f",
                      _override,
                      "exec",
                      "-T",
                      "app",
                      "bin/playstead",
                      "rpc",
                      _code
                    ]}
  end

  test "does not issue Docker commands when preflight rejects the target", %{root: root} do
    published = publish_fixture!(root, "preflight-before-docker")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:unexpected_command, command, args})
      {"", 0}
    end

    assert {:error, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead-restore-live",
               identity: "playstead-restore-live",
               target_root: Path.join(root, "target"),
               command_executor: executor
             )

    assert receipt["code"] == "restore_preflight_canonical_resource_overlap"
    refute_receive {:unexpected_command, _, _}
  end

  test "refuses occupied requested loopback ports before issuing Docker commands", %{root: root} do
    published = publish_fixture!(root, "occupied-port")
    {:ok, listener} = :gen_tcp.listen(0, [:binary, ip: {127, 0, 0, 1}, active: false])
    {:ok, {{127, 0, 0, 1}, occupied_port}} = :inet.sockname(listener)
    parent = self()

    on_exit(fn -> :gen_tcp.close(listener) end)

    executor = fn command, args, _opts ->
      send(parent, {:unexpected_command, command, args})
      {"", 0}
    end

    assert {:error, receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               target_root: Path.join(root, "restore-target"),
               ports: %{"http" => occupied_port, "https" => occupied_port + 1},
               command_executor: executor
             )

    assert receipt["code"] == "restore_preflight_port_collision"
    refute_receive {:unexpected_command, _, _}
    refute File.exists?(Path.join(root, "restore-target"))
  end

  test "does not publish a handoff after a failed custody stage", %{root: root} do
    published = publish_fixture!(root, "handoff-failure")
    target_root = Path.join(root, "restore-target")

    assert {:error, _receipt} =
             Restore.run_chain([published.path],
               canonical_project: "playstead",
               target_root: target_root,
               stage_runner: fn
                 :cas, _target -> {:error, :missing_object}
                 _stage, _target -> :ok
               end
             )

    refute File.exists?(Path.join(target_root, "server-handoff.json"))
  end

  test "retains a verified chain only at a fresh absolute target and prints a handoff", %{
    root: root
  } do
    published = publish_fixture!(root, "retained-chain")
    target_root = Path.join(root, "retained-target") |> Path.expand()
    handoff = Path.join(target_root, "server-handoff.json")

    assert {:ok, receipt, output} =
             Restore.retain([published.path],
               target_root: target_root,
               handoff_output: handoff,
               canonical_project: "playstead",
               canonical_roots: [Path.join(root, "canonical")],
               stage_runner: fn
                 :cas, target ->
                   ca = Path.join(target["root"], "caddy-root-ca.pem")
                   :ok = File.write(ca, "command-parser fixture CA")
                   :ok = File.chmod(ca, 0o600)
                   :ok

                 _stage, _target ->
                   :ok
               end
             )

    assert receipt["state"] == "verified"
    assert output =~ "PLAYSTEAD_RECOVERY_RESTORE_HANDOFF="
    assert output =~ "prove-recovery-known-playable.sh --prepare"
    assert File.regular?(handoff)
    assert {:ok, stat} = File.stat(handoff)
    assert rem(stat.mode, 0o1000) == 0o600
  end

  test "retained mode refuses fixture, relative, reused, and canonical inputs before Docker", %{
    root: root
  } do
    published = publish_fixture!(root, "retained-refusal")
    target_root = Path.join(root, "target") |> Path.expand()
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:unexpected_command, command, args})
      {"", 0}
    end

    for opts <- [
          [compose_fixture: true],
          [target_root: "relative", handoff_output: "relative/server-handoff.json"],
          [target_root: target_root, handoff_output: Path.join(target_root, "wrong.json")],
          [
            target_root: target_root,
            handoff_output: Path.join(target_root, "server-handoff.json"),
            canonical_roots: [target_root]
          ]
        ] do
      assert {:error, _} =
               Restore.retain(
                 [published.path],
                 Keyword.merge(
                   [canonical_project: "playstead", command_executor: executor],
                   opts
                 )
               )
    end

    refute_receive {:unexpected_command, _, _}
    refute File.exists?(target_root)
  end

  test "cleanup refuses mismatched handoff before Docker or target deletion", %{root: root} do
    target_root = Path.join(root, "retained-target")
    File.mkdir_p!(target_root)
    File.write!(Path.join(target_root, "server-handoff.json"), "{}")
    parent = self()

    executor = fn command, args, _opts ->
      send(parent, {:unexpected_command, command, args})
      {"", 0}
    end

    assert {:error, _} =
             Restore.cleanup(
               target_root: target_root,
               handoff_output: Path.join(target_root, "server-handoff.json"),
               command_executor: executor
             )

    assert File.dir?(target_root)
    refute_receive {:unexpected_command, _, _}
  end

  test "failed fixture cleanup is confined to its exact generated Compose target", %{root: root} do
    project = "playstead-restore-failure-123"
    target_root = Path.join(root, "failed-target")
    File.mkdir_p!(target_root)
    env_path = Path.join(target_root, ".restore.env")
    compose_path = Path.join(target_root, "compose.restore.yml")
    File.write!(env_path, "PLAYSTEAD_COMPOSE_PROJECT=#{project}\n")
    File.write!(compose_path, "services: {}\n")
    File.chmod!(env_path, 0o600)
    File.chmod!(compose_path, 0o600)
    parent = self()

    target = %{
      "project" => project,
      "network" => project <> "_default",
      "volumes" => [project <> "_db", project <> "_blobs"],
      "ports" => %{"http" => 28080, "https" => 28443},
      "root" => target_root,
      "env_path" => env_path,
      "compose_path" => compose_path
    }

    executor = fn command, args, _opts ->
      send(parent, {:cleanup_command, command, args})
      {"", 0}
    end

    assert :ok = ComposeRunner.cleanup_failed(target, command_executor: executor)
    assert_receive {:cleanup_command, "docker", args}
    assert Enum.take(args, 3) == ["compose", "--project-name", project]
    assert List.last(args) == "--remove-orphans"
    assert Enum.any?(Enum.chunk_every(args, 2, 1, :discard), &(&1 == ["down", "--volumes"]))

    assert {:error, :cleanup_refused} =
             ComposeRunner.cleanup_failed(%{target | "volumes" => ["playstead_db"]},
               command_executor: executor
             )

    refute_receive {:cleanup_command, _, _}
  end

  test "rejects missing and corrupt game/save objects during the full SHA-256 scrub", %{
    root: root
  } do
    game = "game bytes"
    save = "save bytes"
    game_hash = sha256(game)
    save_hash = sha256(save)
    source = Path.join(root, "objects")
    hydrated = Path.join(root, "hydrated")
    File.mkdir_p!(Path.join([source, "objects", String.slice(game_hash, 0, 2)]))
    File.write!(Path.join([source, "objects", String.slice(game_hash, 0, 2), game_hash]), game)

    entries = [
      object_entry(game_hash, byte_size(game), :game, source),
      object_entry(save_hash, byte_size(save), :save, source)
    ]

    assert {:error, :missing_object} = ComposeRunner.scrub_objects(entries, hydrated)

    File.mkdir_p!(Path.join([source, "objects", String.slice(save_hash, 0, 2)]))

    File.write!(
      Path.join([source, "objects", String.slice(save_hash, 0, 2), save_hash]),
      "corrupt"
    )

    assert {:error, :corrupt_object} = ComposeRunner.scrub_objects(entries, hydrated)
  end

  test "hydrates verified backup members into the local store's canonical layout", %{root: root} do
    bytes = "game bytes"
    hash = sha256(bytes)
    source = Path.join(root, "backup")
    hydrated = Path.join(root, "hydrated")
    relative = Path.join(["objects", String.slice(hash, 0, 2), hash])

    :ok = File.mkdir_p(Path.dirname(Path.join(source, relative)))
    :ok = File.write(Path.join(source, relative), bytes)

    assert :ok =
             ComposeRunner.scrub_objects(
               [object_entry(hash, byte_size(bytes), :game, source)],
               hydrated
             )

    assert File.read!(
             Path.join([
               hydrated,
               "objects",
               "sha256",
               String.slice(hash, 0, 2),
               String.slice(hash, 2, 2),
               hash
             ])
           ) == bytes
  end

  defp publish_fixture!(root, id, members \\ []) do
    {:ok, set} =
      BackupSet.build(%{
        id: id,
        correlation_id: "#{id}-correlation",
        kind: :full,
        dump: %{relative: "database.dump", bytes: "portable dump"},
        members: members,
        metadata: %{release: "test", configuration: %{storage: "local"}}
      })

    {:ok, published} = BackupSet.publish(Path.join(root, "backups"), set, attested: true)
    published
  end

  defp object_entry(hash, size, kind, root) do
    %{
      "relative" => Path.join(["objects", String.slice(hash, 0, 2), hash]),
      "sha256" => hash,
      "size_bytes" => size,
      "kind" => Atom.to_string(kind),
      "__root" => root
    }
  end

  defp sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
end
