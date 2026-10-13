defmodule Playstead.Recovery.Restore do
  @moduledoc """
  Fail-closed clean-room restore coordinator.

  This module deliberately performs no implicit shell work.  It validates only
  published backup-set receipts while the target is offline, generates an
  isolated Compose namespace, and then hands each destructive stage to the
  caller's explicit stage runner.  A successful health response is recorded as
  prerequisite evidence in the `:api` stage; it is never a restore verdict on
  its own.
  """

  alias Playstead.Recovery.{ComposeRunner, Verifier}

  @schema "playstead.restore-receipt.v1"
  @stages [:chain, :preflight, :database, :cas, :manifest, :api]

  @type receipt :: %{required(String.t()) => term()}

  @doc """
  Validates `backup_paths`, creates a never-before-used isolated target, and
  executes the required restore evidence stages in order.

  `:stage_runner` is an injected `fn stage, target -> :ok | {:error, reason}
  end`; keeping command execution outside the domain module makes its safety
  boundary testable and prevents a library call from selecting live resources.
  The legacy `:stages` callback is accepted for fixture callers and runs once
  after preflight.
  """
  @spec run_chain([String.t()], keyword()) :: {:ok, receipt()} | {:error, receipt()}
  def run_chain(backup_paths, opts \\ [])

  def run_chain(backup_paths, opts) when is_list(backup_paths) do
    correlation_id = Keyword.get(opts, :correlation_id, Ecto.UUID.generate())

    case validate_chain(backup_paths) do
      {:ok, chain} ->
        run_verified_chain(chain, correlation_id, opts)

      {:error, reason} ->
        receipt = failed_receipt(correlation_id, :chain, reason)
        persist_receipt(receipt, opts)
        {:error, receipt}
    end
  end

  def run_chain(_, opts) do
    receipt =
      failed_receipt(
        Keyword.get(opts, :correlation_id, Ecto.UUID.generate()),
        :chain,
        :invalid_chain
      )

    persist_receipt(receipt, opts)
    {:error, receipt}
  end

  @doc "Runs a real, independently published chain into one retained target."
  @spec retain([String.t()], keyword()) ::
          {:ok, receipt(), String.t()} | {:error, atom() | receipt()}
  def retain(backup_paths, opts) when is_list(backup_paths) do
    with :ok <- retained_inputs?(backup_paths, opts),
         {:ok, receipt} <- run_chain(backup_paths, Keyword.put(opts, :retained, true)),
         :ok <- retained_artifacts?(receipt, opts) do
      {:ok, receipt, handoff_output(opts)}
    else
      {:error, _} = error -> error
      false -> {:error, :unsafe_retained_input}
    end
  end

  def retain(_, _), do: {:error, :unsafe_retained_input}

  @doc "Tears down only the exact, verified retained Compose target."
  @spec cleanup(keyword()) :: :ok | {:error, atom()}
  def cleanup(opts) do
    with :ok <- cleanup_inputs?(opts),
         {:ok, handoff} <- read_handoff(Keyword.fetch!(opts, :handoff_output)),
         {:ok, receipt} <- read_receipt(handoff["receipt_path"]),
         :ok <- cleanup_matches?(handoff, receipt, opts),
         :ok <- cleanup_compose(handoff, opts),
         :ok <- File.rm_rf(Keyword.fetch!(opts, :target_root)) do
      :ok
    else
      {:error, _} = error -> error
      _ -> {:error, :cleanup_refused}
    end
  end

  defp run_verified_chain(chain, correlation_id, opts) do
    with {:ok, target} <- isolated_target(opts),
         :ok <- ensure_target_directory(target),
         {:ok, target} <- prepare_target(target, chain, opts),
         {:ok, receipt} <- run_stages(chain, target, correlation_id, opts),
         :ok <- publish_handoff(receipt, target, opts) do
      persist_receipt(receipt, opts)
      {:ok, receipt}
    else
      {:error, %{} = receipt} ->
        persist_receipt(receipt, opts)
        {:error, receipt}

      {:error, reason} ->
        receipt = failed_receipt(correlation_id, :preflight, reason)
        persist_receipt(receipt, opts)
        {:error, receipt}
    end
  end

  @doc "Validates only published, digest-matching backup receipts before target creation."
  @spec validate_chain([String.t()]) :: {:ok, [map()]} | {:error, atom()}
  def validate_chain(paths) when is_list(paths) and paths != [] do
    paths
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, manifests} ->
      case validated_manifest(path) do
        {:ok, manifest} -> {:cont, {:ok, [manifest | manifests]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, manifests} ->
        ordered = Enum.reverse(manifests)

        case Verifier.verify_chain(ordered) do
          :ok -> {:ok, ordered}
          {:error, _} = error -> error
        end

      error ->
        error
    end
  end

  def validate_chain(_), do: {:error, :invalid_chain}

  @doc "Generates resource names that cannot be the canonical Compose project."
  @spec isolated_target(keyword()) :: {:ok, map()} | {:error, atom()}
  def isolated_target(opts) do
    canonical_project = Keyword.get(opts, :canonical_project, "playstead")
    target_root = Keyword.get(opts, :target_root)
    identity = Keyword.get(opts, :identity, generated_identity())
    ports = Keyword.get(opts, :ports, generated_ports())

    cond do
      not valid_identity?(identity) ->
        {:error, :invalid_restore_target}

      not (is_binary(target_root) and target_root != "") ->
        {:error, :invalid_restore_target}

      resource_overlap?(identity, canonical_project) ->
        {:error, :canonical_resource_overlap}

      root_overlaps_any?(target_root, Keyword.get(opts, :canonical_roots, [])) ->
        {:error, :canonical_mount_overlap}

      not available_ports?(ports) ->
        {:error, :port_collision}

      File.exists?(target_root) ->
        {:error, :restore_identity_reused}

      true ->
        {:ok,
         %{
           "project" => identity,
           "network" => "#{identity}_default",
           "volumes" => ["#{identity}_db", "#{identity}_blobs"],
           "ports" => ports,
           "root" => Path.expand(target_root),
           "identity_guard" =>
             Path.join([
               Path.expand(Keyword.get(opts, :identity_root, Path.dirname(target_root))),
               ".playstead-restore-identities",
               identity
             ])
         }}
    end
  end

  defp validated_manifest(path) do
    with false <- staging_path?(path),
         {:ok, manifest_bytes} <- File.read(Path.join(path, "manifest.json")),
         {:ok, receipt_bytes} <- File.read(Path.join(path, "receipt.json")),
         {:ok, manifest} <- Jason.decode(manifest_bytes),
         {:ok, receipt} <- Jason.decode(receipt_bytes),
         {:ok, _verification} <- Verifier.verify(path),
         true <- receipt["schema"] == "playstead.backup-set.v1",
         true <- receipt["receipt_id"] == manifest["id"],
         true <- receipt["manifest_sha256"] == digest(manifest_bytes) do
      {:ok, Map.put(manifest, "__path", path)}
    else
      true -> {:error, :staging_backup_refused}
      {:error, :enoent} -> {:error, :unpublished_backup}
      {:error, _} -> {:error, :invalid_backup_receipt}
      false -> {:error, :invalid_backup_receipt}
      _ -> {:error, :invalid_backup_receipt}
    end
  end

  defp run_stages(chain, target, correlation_id, opts) do
    Enum.reduce_while(@stages, {:ok, []}, fn stage, {:ok, completed} ->
      case run_stage(stage, target, opts) do
        :ok ->
          {:cont, {:ok, [Atom.to_string(stage) | completed]}}

        {:error, reason} ->
          receipt =
            failed_receipt(correlation_id, stage, reason, target, chain, Enum.reverse(completed))

          receipt = cleanup_failed_fixture_target(receipt, target, opts)
          {:halt, {:error, write_receipt(receipt, target)}}
      end
    end)
    |> case do
      {:ok, completed} ->
        receipt = verified_receipt(correlation_id, target, chain, Enum.reverse(completed))
        {:ok, write_receipt(receipt, target)}

      error ->
        error
    end
  end

  defp run_stage(:chain, _target, _opts), do: :ok
  defp run_stage(:preflight, _target, _opts), do: :ok

  defp run_stage(stage, target, opts) do
    runner =
      Keyword.get_lazy(opts, :stage_runner, fn ->
        case Keyword.get(opts, :stages) do
          fun when is_function(fun, 1) -> fn _stage, target -> fun.(target) end
          _ -> fn stage, target -> ComposeRunner.run(stage, target, opts) end
        end
      end)

    case runner.(stage, target) do
      :ok -> :ok
      {:error, _} = error -> error
      _ -> {:error, :invalid_stage_result}
    end
  rescue
    _ -> {:error, :stage_runner_failed}
  end

  defp cleanup_failed_fixture_target(receipt, target, opts) do
    if Keyword.get(opts, :cleanup_failed_target, false) do
      case ComposeRunner.cleanup_failed(target, opts) do
        :ok -> receipt
        {:error, _} -> Map.put(receipt, "cleanup_code", "restore_target_cleanup_failed")
      end
    else
      receipt
    end
  end

  defp prepare_target(target, chain, opts) do
    case Keyword.get(opts, :stage_runner) || Keyword.get(opts, :stages) do
      nil -> ComposeRunner.prepare(target, chain, opts)
      _ -> {:ok, Map.put(target, "chain", chain)}
    end
  end

  defp publish_handoff(%{"state" => "verified"} = receipt, target, opts) do
    handoff = %{
      "schema" => "playstead.restore-handoff.v1",
      "correlation_id" => receipt["correlation_id"],
      "project" => target["project"],
      "url" => "https://localhost:#{target["ports"]["https"]}",
      "receipt_path" => Path.join(target["root"], "restore-receipt.json"),
      "ca_path" => Path.join(target["root"], "caddy-root-ca.pem")
    }

    path = Keyword.get(opts, :handoff_output, Path.join(target["root"], "server-handoff.json"))

    with :ok <- File.write(path, Jason.encode!(handoff), [:binary]),
         :ok <- File.chmod(path, 0o600) do
      :ok
    end
  end

  defp publish_handoff(_, _, _), do: {:error, :handoff_refused}

  defp ensure_target_directory(%{"root" => root, "identity_guard" => guard}) do
    with :ok <- File.mkdir_p(Path.dirname(guard)),
         :ok <- File.write(guard, "claimed", [:binary, :exclusive]),
         :ok <- File.mkdir_p(root) do
      :ok
    else
      {:error, :eexist} -> {:error, :restore_identity_reused}
      {:error, reason} -> {:error, reason}
    end
  end

  defp write_receipt(receipt, %{"root" => root}) do
    case File.write(Path.join(root, "restore-receipt.json"), Jason.encode!(receipt), [:binary]) do
      :ok ->
        _ = File.chmod(Path.join(root, "restore-receipt.json"), 0o600)
        receipt

      {:error, reason} ->
        Map.put(receipt, "receipt_write_error", inspect(reason))
    end
  end

  defp persist_receipt(receipt, opts) do
    case Keyword.get(opts, :persist) do
      fun when is_function(fun, 1) -> fun.(receipt)
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp verified_receipt(correlation_id, target, chain, stages) do
    %{
      "schema" => @schema,
      "state" => "verified",
      "correlation_id" => correlation_id,
      "target" => public_target(target),
      "chain_ids" => Enum.map(chain, & &1["id"]),
      "stages" => stages,
      "verified_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp failed_receipt(correlation_id, stage, reason, target \\ nil, chain \\ [], completed \\ []) do
    %{
      "schema" => @schema,
      "state" => "failed",
      "correlation_id" => correlation_id,
      "failed_stage" => Atom.to_string(stage),
      "code" => failure_code(stage, reason),
      "remedy" => remedy(stage),
      "stages" => completed,
      "chain_ids" => Enum.map(chain, & &1["id"]),
      "target" => if(target, do: public_target(target), else: nil),
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp failure_code(:chain, reason), do: "restore_chain_#{reason}"

  defp failure_code(:preflight, :canonical_resource_overlap),
    do: "restore_preflight_canonical_resource_overlap"

  defp failure_code(:preflight, :canonical_mount_overlap),
    do: "restore_preflight_canonical_mount_overlap"

  defp failure_code(:preflight, :restore_identity_reused), do: "restore_preflight_identity_reused"
  defp failure_code(:preflight, :port_collision), do: "restore_preflight_port_collision"
  defp failure_code(stage, _reason), do: "restore_#{stage}_failed"

  defp remedy(:chain), do: "Select only a published verified backup receipt chain."
  defp remedy(:preflight), do: "Generate a fresh isolated Compose target and retry."

  defp remedy(:database),
    do: "Inspect the isolated database restore output; do not touch the live stack."

  defp remedy(:cas), do: "Restore and SHA-256 verify every referenced game and save object."
  defp remedy(:manifest), do: "Repair the isolated manifest members and rerun the full scrub."
  defp remedy(:api), do: "Complete authenticated API convergence in the isolated target."

  defp generated_identity do
    "playstead-restore-" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp generated_ports, do: generated_ports(8)

  defp generated_ports(attempts) when attempts > 0 do
    ports = %{"http" => random_loopback_port(), "https" => random_loopback_port()}
    if available_ports?(ports), do: ports, else: generated_ports(attempts - 1)
  end

  # `isolated_target/1` still checks availability; this fallback only keeps the
  # generator bounded if an unusually busy host consumes every sampled pair.
  defp generated_ports(0), do: %{"http" => 0, "https" => 0}

  defp random_loopback_port do
    20_000 + (:crypto.strong_rand_bytes(2) |> :binary.decode_unsigned() |> rem(40_000))
  end

  defp available_ports?(%{"http" => http, "https" => https})
       when is_integer(http) and is_integer(https) and http != https do
    Enum.all?([http, https], &available_loopback_port?/1)
  end

  defp available_ports?(_), do: false

  defp available_loopback_port?(port) when port in 1024..65_535 do
    case :gen_tcp.listen(port, [:binary, ip: {127, 0, 0, 1}, active: false]) do
      {:ok, socket} ->
        :ok = :gen_tcp.close(socket)
        true

      {:error, _} ->
        false
    end
  end

  defp available_loopback_port?(_), do: false

  defp public_target(target),
    do: Map.drop(target, ["root", "identity_guard", "chain", "env_path", "compose_path"])

  defp valid_identity?(identity),
    do: is_binary(identity) and Regex.match?(~r/^playstead-restore-[a-z0-9-]+$/, identity)

  defp resource_overlap?(left, right) when is_binary(right),
    do: left == right or String.starts_with?(left, right <> "_")

  defp resource_overlap?(_, _), do: true

  defp root_overlaps_any?(root, roots) when is_list(roots) do
    expanded = Path.expand(root)

    Enum.any?(roots, fn canonical ->
      is_binary(canonical) and path_overlap?(expanded, Path.expand(canonical))
    end)
  end

  defp root_overlaps_any?(_, _), do: true

  defp path_overlap?(left, right),
    do:
      left == right or String.starts_with?(left, right <> "/") or
        String.starts_with?(right, left <> "/")

  defp staging_path?(path), do: String.contains?(Path.basename(path), ".staging-")
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp retained_inputs?(backup_paths, opts) do
    target = Keyword.get(opts, :target_root)
    output = Keyword.get(opts, :handoff_output)

    cond do
      Keyword.get(opts, :compose_fixture, false) ->
        {:error, :fixture_refused}

      not (backup_paths != [] and Enum.all?(backup_paths, &absolute_regular_dir?/1)) ->
        {:error, :invalid_backup_set}

      not absolute_new_directory?(target) ->
        {:error, :unsafe_target_root}

      output != Path.join(target, "server-handoff.json") ->
        {:error, :unsafe_handoff_output}

      not (is_binary(Keyword.get(opts, :canonical_project)) and
               Keyword.get(opts, :canonical_project) != "") ->
        {:error, :invalid_canonical_project}

      not (is_list(Keyword.get(opts, :canonical_roots)) and
               Enum.all?(Keyword.get(opts, :canonical_roots), &absolute_path?/1)) ->
        {:error, :invalid_canonical_root}

      true ->
        :ok
    end
  end

  defp retained_artifacts?(%{"state" => "verified", "target" => target} = receipt, opts) do
    root = Keyword.fetch!(opts, :target_root)
    output = Keyword.fetch!(opts, :handoff_output)

    with true <- target["project"] =~ ~r/^playstead-restore-[a-z0-9-]+$/,
         true <- target["network"] == target["project"] <> "_default",
         true <- target["volumes"] == [target["project"] <> "_db", target["project"] <> "_blobs"],
         true <- receipt["stages"] == Enum.map(@stages, &Atom.to_string/1),
         :ok <- restrictive_owned_regular?(Path.join(root, "restore-receipt.json")),
         :ok <- restrictive_owned_regular?(Path.join(root, "caddy-root-ca.pem")),
         :ok <- restrictive_owned_regular?(output),
         {:ok, handoff} <- read_handoff(output),
         true <-
           handoff["correlation_id"] == receipt["correlation_id"] and
             handoff["project"] == target["project"] do
      :ok
    else
      _ -> {:error, :retained_evidence_refused}
    end
  end

  defp retained_artifacts?(_, _), do: {:error, :retained_evidence_refused}

  defp cleanup_inputs?(opts) do
    target = Keyword.get(opts, :target_root)
    output = Keyword.get(opts, :handoff_output)

    if absolute_existing_directory?(target) and output == Path.join(target, "server-handoff.json"),
      do: :ok,
      else: {:error, :cleanup_refused}
  end

  defp read_handoff(path) do
    with :ok <- restrictive_owned_regular?(path),
         {:ok, bytes} <- File.read(path),
         {:ok, handoff} <- Jason.decode(bytes),
         true <-
           Map.keys(handoff) |> MapSet.new() ==
             MapSet.new(["schema", "correlation_id", "project", "url", "receipt_path", "ca_path"]),
         "playstead.restore-handoff.v1" <- handoff["schema"] do
      {:ok, handoff}
    else
      _ -> {:error, :invalid_handoff}
    end
  end

  defp read_receipt(path) do
    with :ok <- restrictive_owned_regular?(path),
         {:ok, bytes} <- File.read(path),
         {:ok, receipt} <- Jason.decode(bytes),
         "playstead.restore-receipt.v1" <- receipt["schema"],
         "verified" <- receipt["state"] do
      {:ok, receipt}
    else
      _ -> {:error, :invalid_receipt}
    end
  end

  defp cleanup_matches?(handoff, receipt, opts) do
    root = Keyword.fetch!(opts, :target_root)
    target = receipt["target"]

    with true <- is_map(target),
         true <- handoff["receipt_path"] == Path.join(root, "restore-receipt.json"),
         true <- handoff["ca_path"] == Path.join(root, "caddy-root-ca.pem"),
         true <- handoff["correlation_id"] == receipt["correlation_id"],
         true <- handoff["project"] == target["project"],
         true <- target["network"] == handoff["project"] <> "_default",
         true <-
           target["volumes"] == [handoff["project"] <> "_db", handoff["project"] <> "_blobs"],
         true <- handoff["project"] =~ ~r/^playstead-restore-[a-z0-9-]+$/,
         :ok <- restrictive_owned_regular?(handoff["ca_path"]) do
      :ok
    else
      _ -> {:error, :cleanup_refused}
    end
  end

  defp cleanup_compose(handoff, opts) do
    executor = Keyword.get(opts, :command_executor, &System.cmd/3)
    root = Keyword.fetch!(opts, :target_root)

    args = [
      "compose",
      "--project-name",
      handoff["project"],
      "--env-file",
      Path.join(root, ".restore.env"),
      "-f",
      "docker-compose.yml",
      "-f",
      Path.join(root, "compose.restore.yml"),
      "down",
      "--volumes",
      "--remove-orphans"
    ]

    case executor.("docker", args, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      _ -> {:error, :cleanup_compose_failed}
    end
  rescue
    _ -> {:error, :cleanup_compose_failed}
  end

  defp handoff_output(opts) do
    quoted = shell_quote(Keyword.fetch!(opts, :handoff_output))

    "PLAYSTEAD_RECOVERY_RESTORE_HANDOFF=#{quoted}\nexport PLAYSTEAD_RECOVERY_RESTORE_HANDOFF=#{quoted}\nplaystead-mac/scripts/ci/prove-recovery-known-playable.sh --prepare --fixture --no-human-observation"
  end

  defp shell_quote(path), do: "'" <> String.replace(path, "'", "'\\\"'\\\"'") <> "'"
  defp absolute_path?(path), do: is_binary(path) and Path.type(path) == :absolute

  defp absolute_regular_dir?(path),
    do:
      absolute_path?(path) and File.dir?(path) and
        match?({:ok, %{type: :directory}}, File.lstat(path))

  defp absolute_new_directory?(path),
    do:
      absolute_path?(path) and not File.exists?(path) and
        not match?({:ok, %{type: :symlink}}, File.lstat(path))

  defp absolute_existing_directory?(path),
    do:
      absolute_path?(path) and File.dir?(path) and
        match?({:ok, %{type: :directory}}, File.lstat(path))

  defp restrictive_owned_regular?(path) do
    with {:ok, %{type: :regular, mode: mode, uid: uid}} <- File.lstat(path),
         true <- rem(mode, 0o1000) == 0o600,
         true <- is_nil(uid) or uid == current_uid() do
      :ok
    else
      _ -> {:error, :unsafe_file}
    end
  end

  defp current_uid do
    case System.cmd("id", ["-u"], stderr_to_stdout: true) do
      {value, 0} -> value |> String.trim() |> String.to_integer()
      _ -> -1
    end
  rescue
    _ -> -1
  end
end
