defmodule Playstead.Readiness do
  @moduledoc """
  The setup wizard's readiness summary (D-04): database, volumes, and
  HTTPS. Always exactly these three rows, always `:ok` or `:warning` —
  warnings never block wizard completion, and this module never raises.
  """

  alias Playstead.Repo
  alias Playstead.TlsTrust

  # Evaluated at compile time and embedded as a literal atom — `Mix` is
  # not available at runtime inside a compiled release (same technique
  # as `Playstead.Application`'s boot-time gates).
  @env Mix.env()

  @type state :: :ok | :warning
  @type row :: %{id: :database | :volumes | :https, state: state, message: String.t()}

  @doc """
  Returns the fixed, ordered three-row readiness summary. `env` is the
  environment map the volumes/https rows are decided against — defaults to
  `Playstead.TlsTrust.runtime_env/0` (OS env + `:env_overrides`), so tests
  can pass an explicit map instead of mutating the process-global OS env.
  """
  @spec summary(TlsTrust.env()) :: [row()]
  def summary(env \\ TlsTrust.runtime_env()) do
    [database_check(), volumes_check(env), https_check(env)]
  end

  # --- database -------------------------------------------------------

  defp database_check do
    with :ok <- check_connection(), :ok <- check_migrations() do
      %{id: :database, state: :ok, message: "Connected and fully migrated."}
    else
      {:warning, message} -> %{id: :database, state: :warning, message: message}
    end
  end

  defp check_connection do
    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:warning, "Database connection failed: #{inspect(reason)}"}
    end
  rescue
    e -> {:warning, "Database connection failed: #{Exception.message(e)}"}
  end

  defp check_migrations do
    case Ecto.Migrator.with_repo(Repo, &Ecto.Migrator.migrations/1) do
      {:ok, migrations, _apps} ->
        pending = Enum.filter(migrations, fn {status, _version, _name} -> status == :down end)

        if pending == [] do
          :ok
        else
          {:warning, "#{length(pending)} pending migration(s) have not been applied."}
        end

      {:error, reason} ->
        {:warning, "Could not determine migration state: #{inspect(reason)}"}
    end
  rescue
    e -> {:warning, "Could not determine migration state: #{Exception.message(e)}"}
  end

  # --- volumes ----------------------------------------------------------
  # D-04 names the anonymous-volume mistake explicitly: a self-hoster who
  # forgets to declare a named volume loses everything on `docker compose
  # down`. From inside the app container we can only directly inspect the
  # blob-storage mount (the database lives in a separate container); we
  # detect an anonymous volume via /proc/self/mountinfo, since Docker
  # mounts a named volume's host path as .../volumes/<name>/_data and an
  # anonymous volume as .../volumes/<64-hex-char-id>/_data.

  @blob_path_env "PLAYSTEAD_BLOB_PATH"
  @default_blob_path "/app/blobs"
  @anonymous_volume_id ~r/\/volumes\/([0-9a-f]{64})\/_data(\s|$)/

  defp volumes_check(env) do
    path = env[@blob_path_env] || @default_blob_path

    case writable_check(path) do
      :ok ->
        case anonymous_volume?(path) do
          true ->
            %{
              id: :volumes,
              state: :warning,
              message:
                "#{path} looks like an anonymous Docker volume — it will be destroyed on " <>
                  "container removal. Use a named volume (see docker-compose.yml)."
            }

          false ->
            %{id: :volumes, state: :ok, message: "#{path} is writable on a named volume."}

          :unknown ->
            %{
              id: :volumes,
              state: :ok,
              message: "#{path} is writable. (Could not verify named-volume status here.)"
            }
        end

      {:warning, message} ->
        %{id: :volumes, state: :warning, message: message}
    end
  end

  defp writable_check(path) do
    probe = Path.join(path, ".playstead-readiness-probe")

    case File.write(probe, "ok") do
      :ok ->
        File.rm(probe)
        :ok

      {:error, reason} ->
        {:warning, "#{path} is not writable: #{:file.format_error(reason)}."}
    end
  rescue
    e -> {:warning, "#{path} could not be checked: #{Exception.message(e)}"}
  end

  defp anonymous_volume?(path) do
    with {:ok, mountinfo} <- File.read("/proc/self/mountinfo"),
         [line] <- matching_mount_lines(mountinfo, path) do
      Regex.match?(@anonymous_volume_id, line)
    else
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  defp matching_mount_lines(mountinfo, path) do
    mountinfo
    |> String.split("\n")
    |> Enum.filter(&String.contains?(&1, " #{path} "))
    |> Enum.take(1)
  end

  # --- https ------------------------------------------------------------
  # Four distinct, honestly-labeled transport states (D-13, D-04): never
  # collapse them into a single boolean, and never call plain-HTTP or an
  # external proxy "secure".

  # The proxy/domain decision itself lives in `TlsTrust.transport_state/1`
  # so the wizard and the Devices page can never disagree about it.
  defp https_check(env) do
    case TlsTrust.transport_state(env) do
      :external_proxy ->
        %{
          id: :https,
          state: :warning,
          message:
            "An external reverse proxy is configured (PLAYSTEAD_PROXY=external). " <>
              "Playstead cannot verify its own TLS — make sure your proxy terminates HTTPS."
        }

      :letsencrypt ->
        %{
          id: :https,
          state: :ok,
          message: "Automatic HTTPS via Let's Encrypt for #{env["PLAYSTEAD_DOMAIN"]}."
        }

      _internal_ca_or_plain_http when @env == :prod ->
        %{
          id: :https,
          state: :ok,
          message:
            "HTTPS via Caddy's internal certificate authority (self-signed — expected " <>
              "with no PLAYSTEAD_DOMAIN configured)."
        }

      _internal_ca_or_plain_http ->
        %{
          id: :https,
          state: :warning,
          message: "Running over plain HTTP. This is not secure outside local development."
        }
    end
  end
end
