defmodule Playstead.Recovery.ComposeRunner do
  @moduledoc """
  Concrete, fail-closed command runner for a clean-room recovery target.

  It is intentionally the only production path that can invoke Docker.  Tests
  may replace `:command_executor`, but no injected success callback is used by
  production restore execution.
  """

  alias Playstead.Recovery.Verifier

  @spec prepare(map(), [map()], keyword()) :: {:ok, map()} | {:error, atom()}
  def prepare(target, chain, opts) do
    env_path = Path.join(target["root"], ".restore.env")
    compose_path = Path.join(target["root"], "compose.restore.yml")

    with :ok <- File.write(env_path, environment(target), [:binary]),
         :ok <- File.chmod(env_path, 0o600),
         :ok <- File.write(compose_path, compose_override(target), [:binary]),
         :ok <- File.chmod(compose_path, 0o600),
         :ok <- compose(target, env_path, compose_path, ["config", "--quiet"], opts) do
      {:ok,
       target
       |> Map.put("chain", chain)
       |> Map.put("env_path", env_path)
       |> Map.put("compose_path", compose_path)}
    else
      _ -> {:error, :compose_preflight_failed}
    end
  end

  @spec run(atom(), map(), keyword()) :: :ok | {:error, atom()}
  @doc "Tears down only a generated target whose local Compose files and resource names match its failure receipt."
  @spec cleanup_failed(map(), keyword()) :: :ok | {:error, atom()}
  def cleanup_failed(target, opts \\ []) do
    if cleanup_target_valid?(target) do
      compose(target, ["down", "--volumes", "--remove-orphans"], opts)
    else
      {:error, :cleanup_refused}
    end
  end

  def run(:database, target, opts) do
    with :ok <- compose(target, ["up", "-d", "db"], opts),
         :ok <- await_database(target, opts, 20),
         :ok <- stage_dump(target, opts),
         :ok <-
           compose(
             target,
             [
               "exec",
               "-T",
               "db",
               "pg_restore",
               "-U",
               "playstead_restore",
               "-d",
               "playstead_restore",
               "--clean",
               "--if-exists",
               "--no-owner",
               "/tmp/database.dump"
             ],
             opts
           ),
         :ok <-
           compose(
             target,
             [
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
             ],
             opts
           ) do
      :ok
    else
      _ -> {:error, :pg_restore_failed}
    end
  end

  def run(:cas, target, opts) do
    with :ok <- hydrate_and_scrub(target),
         :ok <- compose(target, ["up", "-d", "app", "caddy"], opts),
         :ok <- await_caddy(target, opts, 40),
         :ok <- copy_caddy_ca(target, opts),
         :ok <- copy_hydrated_objects(target, opts) do
      :ok
    else
      _ -> {:error, :cas_scrub_failed}
    end
  end

  def run(:manifest, target, _opts) do
    if Enum.all?(target["chain"], fn manifest ->
         match?({:ok, _}, Verifier.verify(manifest_root(manifest)))
       end),
       do: :ok,
       else: {:error, :manifest_verification_failed}
  end

  def run(:api, target, opts) do
    case Keyword.get(opts, :api_probe) do
      probe when is_function(probe, 1) -> probe.(target)
      _ -> authenticated_probe(target, opts)
    end
  rescue
    _ -> {:error, :authenticated_api_failed}
  end

  def run(_, _target, _opts), do: {:error, :invalid_restore_stage}

  @doc "Streams every manifest-declared game/save object into an isolated tree and verifies size and SHA-256."
  @spec scrub_objects([map()], String.t()) :: :ok | {:error, :missing_object | :corrupt_object}
  def scrub_objects(entries, hydrated) when is_list(entries) and is_binary(hydrated) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      source = Path.join(manifest_root(entry), entry["relative"])

      with true <- safe_object?(entry),
           destination <- Path.join(hydrated, canonical_object_relative(entry["sha256"])),
           {:ok, _} <- File.stat(source),
           :ok <- File.mkdir_p(Path.dirname(destination)),
           :ok <- File.cp(source, destination),
           {:ok, digest} <- digest_file(destination),
           {:ok, %{size: size}} <- File.stat(destination),
           true <- digest == entry["sha256"] and size == entry["size_bytes"] do
        {:cont, :ok}
      else
        false -> {:halt, {:error, :corrupt_object}}
        {:error, :enoent} -> {:halt, {:error, :missing_object}}
        {:error, _} -> {:halt, {:error, :corrupt_object}}
        _ -> {:halt, {:error, :corrupt_object}}
      end
    end)
  end

  def scrub_objects(_, _), do: {:error, :corrupt_object}

  defp environment(target) do
    password = secret()

    """
    PLAYSTEAD_COMPOSE_PROJECT=#{target["project"]}
    POSTGRES_USER=playstead_restore
    POSTGRES_PASSWORD=#{password}
    POSTGRES_DB=playstead_restore
    DATABASE_URL=ecto://playstead_restore:#{password}@db/playstead_restore
    SECRET_KEY_BASE=#{secret()}
    PLAYSTEAD_SETUP_TOKEN=#{secret()}
    PLAYSTEAD_HTTP_PORT=#{target["ports"]["http"]}
    PLAYSTEAD_HTTPS_PORT=#{target["ports"]["https"]}
    PLAYSTEAD_DOMAIN=localhost
    PHX_HOST=localhost
    PLAYSTEAD_PROXY=trusted
    """
  end

  defp compose_override(target) do
    project = target["project"]
    subnet = restore_subnet(project)

    """
    services:
      caddy:
        environment:
          CADDY_HTTP_PORT: "80"
          CADDY_HTTPS_PORT: "443"
        ports: !override
          - "127.0.0.1:#{target["ports"]["http"]}:80"
          - "127.0.0.1:#{target["ports"]["https"]}:443"
    volumes:
      playstead_db: {name: #{project}_db}
      playstead_blobs: {name: #{project}_blobs}
      caddy_data: {name: #{project}_caddy_data}
      caddy_config: {name: #{project}_caddy_config}
    networks:
      default:
        ipam:
          config:
            - subnet: #{subnet}
    """
  end

  # A retained restore must not depend on Docker's global automatic address
  # pool: a host can legitimately retain enough isolated targets to exhaust it.
  # The project identity already has high entropy; deriving a /24 keeps this
  # target's network stable within the restore while avoiding the default pool.
  defp restore_subnet(project) do
    octet = :erlang.phash2(project, 256)
    "10.253.#{octet}.0/24"
  end

  # `System.cmd/3` does not provide a stdin option.  Stage the digest-verified
  # archive in the isolated database container, then restore from that file.
  # The archive never crosses into the canonical Compose project.
  defp stage_dump(target, opts) do
    path =
      target["chain"]
      |> List.first()
      |> manifest_root()
      |> Path.join("database.dump")

    with true <- File.regular?(path),
         :ok <- compose(target, ["cp", path, "db:/tmp/database.dump"], opts) do
      :ok
    else
      _ -> {:error, :archive_staging_failed}
    end
  end

  defp hydrate_and_scrub(target) do
    hydrated = Path.join(target["root"], "hydrated")

    target
    |> custody_entries()
    |> scrub_objects(hydrated)
  end

  defp copy_hydrated_objects(target, opts) do
    hydrated = Path.join([target["root"], "hydrated", "objects"])

    if File.dir?(hydrated) do
      with :ok <- compose(target, ["cp", hydrated <> "/.", "app:/app/blobs/objects"], opts),
           # `docker compose cp` preserves the hydrator host's ownership. The
           # released server intentionally runs as nobody, so repair the
           # verified target volume before a future import needs to create a
           # new content-addressed prefix directory.
           :ok <-
             compose(
               target,
               [
                 "exec",
                 "-T",
                 "--user",
                 "0:0",
                 "app",
                 "chown",
                 "-R",
                 "nobody:nogroup",
                 "/app/blobs/objects"
               ],
               opts
             ) do
        :ok
      end
    else
      :ok
    end
  end

  # Caddy starts only after the application health check.  Wait for the
  # isolated proxy itself, then export its public local-CA certificate so the
  # API evidence is TLS-authenticated rather than an insecure readiness probe.
  defp await_caddy(_target, _opts, 0), do: {:error, :proxy_unavailable}

  defp await_caddy(target, opts, attempts) do
    case compose(target, ["exec", "-T", "caddy", "caddy", "version"], opts) do
      :ok ->
        :ok

      {:error, _} ->
        Process.sleep(500)
        await_caddy(target, opts, attempts - 1)
    end
  end

  defp copy_caddy_ca(target, opts) do
    path = Path.join(target["root"], "caddy-root-ca.pem")

    with :ok <-
           compose(
             target,
             ["cp", "caddy:/data/caddy/pki/authorities/local/root.crt", path],
             opts
           ) do
      # Command-boundary tests do not materialize Docker's copied file. Retained
      # mode independently requires this file to exist and be mode 0600.
      if File.regular?(path), do: File.chmod(path, 0o600), else: :ok
    else
      _ -> {:error, :ca_export_failed}
    end
  end

  defp authenticated_probe(target, opts) do
    with {:ok, token} <- mint_probe_credential(target, opts),
         :ok <-
           command(
             "curl",
             [
               "--fail",
               "--silent",
               "--show-error",
               "--cacert",
               Path.join(target["root"], "caddy-root-ca.pem"),
               "-H",
               "Authorization: Bearer #{token}",
               "https://localhost:#{target["ports"]["https"]}/api/v1/devices/me"
             ],
             opts
           ) do
      :ok
    else
      _ -> {:error, :authenticated_api_failed}
    end
  end

  # A credential is generated inside the isolated app process and is never
  # written to receipts or handoffs.  The production image owns its schema.
  defp mint_probe_credential(target, opts) do
    code =
      "u = Playstead.Accounts.get_owner() || elem(Playstead.Accounts.register_owner(%{email: \"restore-probe@invalid\", password: \"restore probe password 123\"}), 1); c = Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false); {:ok, r} = Playstead.Pairing.create_request(%{device_code: c, device_name: \"restore-probe\", platform: \"recovery\", app_version: \"1\"}); {:ok, _} = Playstead.Pairing.approve(Playstead.Accounts.Scope.for_user(u), r.id); {:ok, %{credential_plaintext: t}} = Playstead.Pairing.redeem(r.id, c); IO.write(t)"

    case compose_output(target, ["exec", "-T", "app", "bin/playstead", "rpc", code], opts) do
      {:ok, token} when byte_size(token) > 20 -> {:ok, String.trim(token)}
      _ -> {:error, :probe_credential_failed}
    end
  end

  defp compose(target, args, opts),
    do: compose(target, target["env_path"], target["compose_path"], args, opts)

  defp compose(target, env, file, args, opts),
    do:
      command(
        "docker",
        compose_args(target, env, file, args),
        Keyword.put(opts, :command_env, command_environment(env))
      )

  defp compose_output(target, args, opts),
    do:
      command_output(
        "docker",
        compose_args(target, target["env_path"], target["compose_path"], args),
        Keyword.put(opts, :command_env, command_environment(target["env_path"]))
      )

  defp compose_args(target, env, file, args),
    do: [
      "compose",
      "--project-name",
      target["project"],
      "--env-file",
      env,
      "-f",
      "docker-compose.yml",
      "-f",
      file | args
    ]

  defp cleanup_target_valid?(target) when is_map(target) do
    project = target["project"]
    root = target["root"]

    is_binary(project) and Regex.match?(~r/^playstead-restore-[a-z0-9-]+$/, project) and
      is_binary(root) and Path.type(root) == :absolute and
      target["network"] == project <> "_default" and
      target["volumes"] == [project <> "_db", project <> "_blobs"] and
      is_map(target["ports"]) and target["ports"]["http"] != target["ports"]["https"] and
      Enum.all?([target["ports"]["http"], target["ports"]["https"]], fn port ->
        is_integer(port) and port in 1024..65_535
      end) and
      target["env_path"] == Path.join(root, ".restore.env") and
      target["compose_path"] == Path.join(root, "compose.restore.yml") and
      match?({:ok, %{type: :directory}}, File.lstat(root)) and
      restrictive_regular?(target["env_path"]) and
      restrictive_regular?(target["compose_path"])
  rescue
    _ -> false
  end

  defp cleanup_target_valid?(_), do: false

  defp restrictive_regular?(path) do
    with {:ok, %{type: :regular, mode: mode}} <- File.lstat(path),
         true <- Bitwise.band(mode, 0o777) == 0o600 do
      true
    else
      _ -> false
    end
  end

  defp await_database(_target, _opts, 0), do: {:error, :database_unavailable}

  defp await_database(target, opts, attempts) do
    # `pg_isready` returns success as soon as PostgreSQL accepts connections,
    # including the entrypoint window before the requested restore database is
    # fully initialized. Restore only after a real query can authenticate to
    # that exact database.
    case compose(
           target,
           [
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
           ],
           opts
         ) do
      :ok ->
        :ok

      {:error, _} ->
        Process.sleep(500)
        await_database(target, opts, attempts - 1)
    end
  end

  defp command(command, args, opts) do
    case executor(opts).(command, args, command_options(opts)) do
      {_output, 0} -> :ok
      _ -> {:error, :command_failed}
    end
  rescue
    _ -> {:error, :command_failed}
  end

  defp command_output(command, args, opts) do
    case executor(opts).(command, args, command_options(opts)) do
      {output, 0} -> {:ok, output}
      _ -> {:error, :command_failed}
    end
  rescue
    _ -> {:error, :command_failed}
  end

  defp executor(opts), do: Keyword.get(opts, :command_executor, &System.cmd/3)

  # Docker Compose prioritizes its parent process environment over --env-file.
  # The host Mix task legitimately inherits canonical credentials, but a
  # recovery target must never interpolate those values into its own Compose
  # resources. Forward only the generated restore environment to Docker.
  defp command_environment(path) do
    path
    |> File.read!()
    |> String.split("\n", trim: true)
    |> Enum.map(fn line -> String.split(line, "=", parts: 2) end)
    |> Enum.map(fn [key, value] -> {key, value} end)
  end

  defp command_options(opts),
    do: [stderr_to_stdout: true, env: Keyword.get(opts, :command_env, [])]

  defp manifest_root(%{"__path" => path}), do: path
  defp manifest_root(%{"__root" => path}), do: path
  defp manifest_root(%{"path" => path}), do: path
  defp manifest_root(entry) when is_map(entry), do: Map.get(entry, "__path", "")

  defp safe_object?(%{"relative" => "objects/" <> _, "sha256" => hash, "size_bytes" => size})
       when byte_size(hash) == 64 and is_integer(size) and size >= 0, do: true

  defp safe_object?(_), do: false

  # Backup sets intentionally use a portable, shallow member layout.  The
  # local object store has its own canonical layout, however; hydrate into
  # that layout before copying into the isolated volume so a verified restore
  # is also readable by the running server.
  defp canonical_object_relative(<<a::binary-size(2), b::binary-size(2), _::binary>> = sha256),
    do: Path.join(["objects", "sha256", a, b, sha256])

  defp custody_entries(target) do
    target["chain"]
    |> Enum.flat_map(fn manifest ->
      manifest
      |> get_in(["coverage", "entries"])
      |> Enum.map(&Map.put(&1, "__root", manifest_root(manifest)))
    end)
    |> Enum.filter(&(&1["kind"] in ["game", "save"]))
  end

  defp digest_file(path),
    do:
      File.open(path, [:read, :binary, :raw], fn io ->
        digest_io(io, :crypto.hash_init(:sha256))
        |> :crypto.hash_final()
        |> Base.encode16(case: :lower)
      end)

  defp digest_io(io, acc) do
    case :file.read(io, 1_048_576) do
      {:ok, chunk} -> digest_io(io, :crypto.hash_update(acc, chunk))
      :eof -> acc
      _ -> throw(:read_error)
    end
  end

  # Phoenix's cookie session store requires `SECRET_KEY_BASE` to be at least
  # 64 bytes.  Keep every generated restore secret at that safe size so an
  # otherwise healthy isolated target can also serve browser requests.
  defp secret, do: Base.url_encode64(:crypto.strong_rand_bytes(48), padding: false)
end
