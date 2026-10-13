defmodule Playstead.Recovery.BackupOperatorTest do
  use ExUnit.Case, async: true

  alias Playstead.Release
  alias Playstead.Recovery.BackupSet

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "playstead-backup-operator-#{System.unique_integer([:positive])}"
      )

    destination = Path.join(root, "backup")
    canonical = Path.join(root, "blobs")
    File.mkdir_p!(destination)
    File.mkdir_p!(canonical)
    on_exit(fn -> File.rm_rf!(root) end)
    {:ok, destination: destination, canonical: canonical}
  end

  test "preflight refuses unsafe destinations without creating recovery work", %{
    destination: destination,
    canonical: canonical
  } do
    assert {:ok, %{independence: "operator_attested"}} =
             BackupSet.preflight_destination(destination, nil)

    assert {:error, :destination_missing} =
             BackupSet.preflight_destination(Path.join(destination, "missing"), nil)

    file = Path.join(destination, "not-a-directory")
    File.write!(file, "not a directory")
    assert {:error, :destination_not_directory} = BackupSet.preflight_destination(file, nil)

    readonly = Path.join(destination, "readonly")
    File.mkdir_p!(readonly)
    File.chmod!(readonly, 0o500)
    on_exit(fn -> File.chmod(readonly, 0o700) end)
    assert {:error, :destination_not_writable} = BackupSet.preflight_destination(readonly, nil)

    assert {:error, :destination_overlaps_canonical} =
             BackupSet.preflight_destination(destination, destination)

    assert {:error, :destination_same_filesystem} =
             BackupSet.preflight_destination(destination, canonical)

    link = Path.join(Path.dirname(destination), "link")
    File.ln_s!(destination, link)
    assert {:error, :destination_symlink} = BackupSet.preflight_destination(link, nil)
  end

  test "preflight success renders without publication fields" do
    assert Release.render_backup_result({:ok, %{independence: "operator_attested"}}) ==
             "backup_preflight_passed"
  end

  test "preflight attestation is normalized before rendering" do
    assert {:ok, result = %{state: "preflight_passed"}} =
             Release.run_backup(["--preflight", "--full"],
               destination: fn -> {:ok, "/opaque/destination"} end,
               preflight: fn _ -> {:ok, %{independence: "operator_attested"}} end
             )

    assert Release.render_backup_result({:ok, result}) == "backup_preflight_passed"
  end

  test "full wait reports only a published allowlisted receipt projection", %{
    destination: destination
  } do
    request = fn attrs ->
      assert attrs == %{destination: destination, kind: :full}
      {:ok, "record-opaque"}
    end

    status = fn "record-opaque" ->
      {:ok,
       %{
         kind: "full",
         state: "published",
         correlation_id: "correlation-opaque",
         receipt: %{
           "receipt_id" => "receipt-opaque",
           "verified_at" => "2026-09-20T00:00:00Z",
           "independence" => "operator_attested",
           "manifest_sha256" => "hash-sentinel",
           "path" => "/private/path-sentinel"
         }
       }}
    end

    assert {:ok, projection} =
             Release.run_backup(["--full", "--wait"],
               preflight: fn _ -> :ok end,
               request: request,
               status: status,
               destination: fn -> {:ok, destination} end,
               sleep: fn _ -> :ok end,
               monotonic_time: fn -> 0 end
             )

    assert projection == %{
             kind: "full",
             receipt_id: "receipt-opaque",
             correlation_id: "correlation-opaque",
             state: "published",
             verified_at: "2026-09-20T00:00:00Z",
             independence: "operator_attested"
           }

    rendered = Release.render_backup_result({:ok, projection})
    refute rendered =~ "hash-sentinel"
    refute rendered =~ "path-sentinel"
  end

  test "full backup starts the endpoint-free backup runtime before requesting durable recovery work",
       %{
         destination: destination
       } do
    assert {:ok, %{state: "scheduled"}} =
             Release.run_backup(["--full"],
               preflight: fn _ -> :ok end,
               backup_runtime_start: fn ->
                 send(self(), :backup_runtime_started)
                 :ok
               end,
               request: fn attrs ->
                 assert attrs == %{destination: destination, kind: :full}
                 assert_received :backup_runtime_started
                 {:ok, "record-opaque"}
               end,
               destination: fn -> {:ok, destination} end
             )
  end

  test "preflight does not start the backup runtime", %{destination: destination} do
    assert {:ok, %{state: "preflight_passed"}} =
             Release.run_backup(["--preflight", "--full"],
               preflight: fn _ -> :ok end,
               backup_runtime_start: fn ->
                 send(self(), :backup_runtime_started)
                 :ok
               end,
               destination: fn -> {:ok, destination} end
             )

    refute_received :backup_runtime_started
  end

  test "backup runtime includes only durable-work services, never the HTTP endpoint" do
    children = Release.backup_runtime_children()

    assert Playstead.Repo in children
    assert Enum.any?(children, &match?({Oban, _config}, &1))
    refute PlaysteadWeb.Endpoint in children
  end

  test "incremental maps only an explicit parent receipt and failed or timed out records never succeed",
       %{destination: destination} do
    assert {:ok, %{kind: "incremental"}} =
             Release.run_backup(["--incremental", "--parent-receipt", "parent-opaque", "--wait"],
               preflight: fn _ -> :ok end,
               request: fn attrs ->
                 assert attrs == %{
                          destination: destination,
                          kind: :incremental,
                          parent: %{"receipt_id" => "parent-opaque"}
                        }

                 {:ok, "record"}
               end,
               status: fn _ ->
                 {:ok,
                  %{
                    kind: "incremental",
                    state: "published",
                    correlation_id: "correlation",
                    receipt: %{
                      "receipt_id" => "receipt",
                      "verified_at" => "2026-09-20T00:00:00Z",
                      "independence" => "operator_attested"
                    }
                  }}
               end,
               destination: fn -> {:ok, destination} end,
               sleep: fn _ -> :ok end,
               monotonic_time: fn -> 0 end
             )

    for {state, expected} <- [
          failed: :backup_not_published,
          planned: :backup_timeout,
          staging: :backup_timeout
        ] do
      assert {:error, ^expected} =
               Release.run_backup(["--full", "--wait"],
                 preflight: fn _ -> :ok end,
                 request: fn _ -> {:ok, "record"} end,
                 status: fn _ -> {:ok, %{state: Atom.to_string(state)}} end,
                 destination: fn -> {:ok, destination} end,
                 sleep: fn _ -> :ok end,
                 monotonic_time: fn -> 1 end,
                 wait_ms: 0
               )
    end

    assert {:error, :backup_timeout} =
             Release.run_backup(["--full", "--wait"],
               preflight: fn _ -> :ok end,
               request: fn _ -> {:ok, "record"} end,
               status: fn _ -> {:ok, %{state: "planned"}} end,
               destination: fn -> {:ok, destination} end,
               sleep: fn _ -> :ok end,
               monotonic_time: fn -> 1 end,
               wait_ms: 0
             )
  end

  test "strict argument parsing rejects invalid parent and conflicting forms" do
    assert {:error, :invalid_backup_arguments} =
             Release.parse_backup_args(["--full", "--incremental"])

    assert {:error, :invalid_backup_arguments} =
             Release.parse_backup_args(["--incremental", "--wait"])

    assert {:error, :invalid_backup_arguments} =
             Release.parse_backup_args(["--preflight", "--incremental", "--parent-receipt", "p"])

    assert {:error, :invalid_backup_arguments} =
             Release.parse_backup_args(["--full", "--unknown"])
  end

  test "configured destination is never rendered in errors" do
    output = Release.render_backup_result({:error, :destination_missing})
    assert output == "backup_destination_missing"
    refute output =~ "PLAYSTEAD_BACKUP_DESTINATION"
  end
end
