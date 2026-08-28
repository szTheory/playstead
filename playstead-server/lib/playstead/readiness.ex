defmodule Playstead.Readiness do
  @moduledoc """
  The setup wizard's readiness summary (D-04, extended for Phase 2 by
  D-01/D-10/D-11/D-33): database, volumes, HTTPS, the read-only inbox
  mount, the writable export mount, and blob-volume rename atomicity.
  Every row is `:ok`, `:warning`, or `:error` — `:warning` never blocks
  wizard completion; `:error` names a row this phase's write paths
  cannot safely proceed without. This module never raises.
  """

  alias Playstead.Repo
  alias Playstead.TlsTrust

  # Evaluated at compile time and embedded as a literal atom — `Mix` is
  # not available at runtime inside a compiled release (same technique
  # as `Playstead.Application`'s boot-time gates).
  @env Mix.env()

  @type state :: :ok | :warning | :error
  @type row_id :: :database | :volumes | :https | :inbox | :exports | :blob_volume_atomicity
  @type row :: %{id: row_id, state: state, message: String.t()}

  @doc """
  Returns the ordered readiness summary. `env` is the environment map
  every env-dependent row is decided against — defaults to
  `Playstead.TlsTrust.runtime_env/0` (OS env + `:env_overrides`), so tests
  can pass an explicit map instead of mutating the process-global OS env.
  """
  @spec summary(TlsTrust.env()) :: [row()]
  def summary(env \\ TlsTrust.runtime_env()) do
    [
      database_check(),
      volumes_check(env),
      https_check(env),
      inbox_check(env),
      exports_check(env),
      blob_volume_atomicity_check(env)
    ]
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

  # --- inbox --------------------------------------------------------------
  # D-01: the inbox is bind-mounted `:ro` on purpose — "source untouched"
  # is a kernel guarantee, not an application-code promise. The probe is
  # therefore read-only (directory listing), never `writable_check/1`'s
  # write probe, which would report a correctly-configured read-only
  # mount as broken.

  @inbox_path_env "PLAYSTEAD_INBOX_PATH"
  @default_inbox_path "/app/inbox"

  defp inbox_check(env) do
    path = env[@inbox_path_env] || @default_inbox_path

    case File.ls(path) do
      {:ok, _entries} ->
        %{id: :inbox, state: :ok, message: "#{path} is readable."}

      {:error, reason} ->
        %{
          id: :inbox,
          state: :warning,
          message:
            "#{path} could not be read (#{:file.format_error(reason)}). Configure the " <>
              "compose bind mount `./inbox:/app/inbox:ro`."
        }
    end
  rescue
    e ->
      %{
        id: :inbox,
        state: :warning,
        message:
          "#{env[@inbox_path_env] || @default_inbox_path} could not be checked: " <>
            "#{Exception.message(e)}. Configure the compose bind mount `./inbox:/app/inbox:ro`."
      }
  end

  # --- exports --------------------------------------------------------------
  # D-33: unlike the inbox, this mount genuinely must be writable, so an
  # unwritable export path is reported as :error, not :warning — export
  # jobs cannot proceed at all without it.

  @export_path_env "PLAYSTEAD_EXPORT_PATH"
  @default_export_path "/app/exports"

  defp exports_check(env) do
    path = env[@export_path_env] || @default_export_path

    case writable_check(path) do
      :ok -> %{id: :exports, state: :ok, message: "#{path} is writable."}
      {:warning, message} -> %{id: :exports, state: :error, message: message}
    end
  end

  # --- blob volume atomicity -------------------------------------------------
  # D-11's custody guarantee is `File.rename/2` being atomic, which holds
  # only within one filesystem. If `tmp/` and `objects/` ever diverge onto
  # separate mounts, the rename silently degrades to copy+delete and
  # reopens the partial-write window D-11 exists to close (RESEARCH
  # Pitfall 2). Outside a Linux container `/proc/self/mountinfo` is
  # absent — this degrades to a non-fatal `:ok`/"could not verify", the
  # same graceful-fallback shape `anonymous_volume?/1` already uses,
  # since the release only ever runs inside the Linux container.

  defp blob_volume_atomicity_check(env) do
    blob_path = env[@blob_path_env] || @default_blob_path
    tmp_path = Path.join(blob_path, "tmp")
    objects_path = Path.join(blob_path, "objects")

    case {mount_device(tmp_path), mount_device(objects_path)} do
      {{:ok, device}, {:ok, device}} ->
        %{
          id: :blob_volume_atomicity,
          state: :ok,
          message:
            "#{tmp_path} and #{objects_path} are on the same filesystem; renames between " <>
              "them are atomic."
        }

      {{:ok, _tmp_device}, {:ok, _objects_device}} ->
        %{
          id: :blob_volume_atomicity,
          state: :warning,
          message:
            "#{tmp_path} and #{objects_path} are on different filesystems -- File.rename/2 " <>
              "will silently fall back to copy+delete, reopening the partial-write window."
        }

      _unknown ->
        %{
          id: :blob_volume_atomicity,
          state: :ok,
          message:
            "Could not verify whether #{tmp_path} and #{objects_path} share a filesystem here."
        }
    end
  end

  # Resolves the most specific `/proc/self/mountinfo` entry whose mount
  # point is a prefix of `path`, returning its device id (major:minor).
  # This is a *prefix* match (unlike `anonymous_volume?/1`'s exact-line
  # match) because `tmp/`/`objects/` are ordinary subdirectories, not
  # necessarily mount points themselves — they inherit their enclosing
  # mount's device unless one of them was deliberately bind-mounted
  # elsewhere, which is exactly the misconfiguration this check exists
  # to catch.
  defp mount_device(path) do
    with {:ok, mountinfo} <- File.read("/proc/self/mountinfo") do
      mountinfo
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_mountinfo_line/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {mount_point, _device} -> String.starts_with?(path, mount_point) end)
      |> Enum.max_by(fn {mount_point, _device} -> String.length(mount_point) end, fn -> nil end)
      |> case do
        {_mount_point, device} -> {:ok, device}
        nil -> :unknown
      end
    else
      _ -> :unknown
    end
  rescue
    _ -> :unknown
  end

  # mountinfo line shape: "<id> <parent-id> <major:minor> <root> <mount-point> ... - <fstype> <source> <options>"
  defp parse_mountinfo_line(line) do
    parts = String.split(line, " ")

    case Enum.find_index(parts, &(&1 == "-")) do
      idx when is_integer(idx) and idx >= 5 ->
        device = Enum.at(parts, 2)
        mount_point = Enum.at(parts, 4)
        {mount_point, device}

      _ ->
        nil
    end
  end

  # --- free space (D-10) ------------------------------------------------
  # The IMPT-01 storage preview, the per-write preflight (RESEARCH
  # Pitfall 3), and this readiness row all read the same integer-exact
  # number from these two public functions — no floats, no `round/1`, no
  # division that loses a remainder at any step.

  @min_free_margin_bytes 1_073_741_824

  @doc """
  Available bytes on the filesystem containing `path` (defaults to the
  blob volume), from a live filesystem-statistics call — never a cached
  or previously-computed value. Returns `:unknown` if it cannot be
  determined (e.g. the path does not exist).
  """
  @spec free_bytes(String.t()) :: non_neg_integer() | :unknown
  def free_bytes(path \\ System.get_env(@blob_path_env) || @default_blob_path) do
    case System.cmd("df", ["-Pk", path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> List.last()
        |> parse_df_available_kb()

      _ ->
        :unknown
    end
  rescue
    _ -> :unknown
  end

  defp parse_df_available_kb(nil), do: :unknown

  defp parse_df_available_kb(line) do
    case String.split(line) do
      [_filesystem, _blocks, _used, available_kb | _rest] ->
        case Integer.parse(available_kb) do
          {kb, _rest} -> kb * 1024
          :error -> :unknown
        end

      _ ->
        :unknown
    end
  end

  @doc """
  D-10's free-space rule as pure integer arithmetic: the space required
  for a write of `requested_bytes` is `requested_bytes` plus the larger
  of 1 GiB and five percent of `capacity_bytes`. No floats and no lost
  remainder — `div/2` truncates toward zero, which only ever makes the
  5% term smaller (never inflates it), so this never *overestimates* the
  margin either.
  """
  @spec required_bytes(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def required_bytes(requested_bytes, capacity_bytes)
      when is_integer(requested_bytes) and requested_bytes >= 0 and
             is_integer(capacity_bytes) and capacity_bytes >= 0 do
    margin = max(@min_free_margin_bytes, div(capacity_bytes * 5, 100))
    requested_bytes + margin
  end

  @doc """
  Whether a write of `requested_bytes` fits within `available_bytes`
  under `required_bytes/2`'s rule for a volume of `capacity_bytes`. A
  request needing exactly the available margin passes; one byte more is
  refused.
  """
  @spec fits_free_space?(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: boolean()
  def fits_free_space?(requested_bytes, available_bytes, capacity_bytes)
      when is_integer(available_bytes) and available_bytes >= 0 do
    available_bytes >= required_bytes(requested_bytes, capacity_bytes)
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
