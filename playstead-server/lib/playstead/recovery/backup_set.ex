defmodule Playstead.Recovery.BackupSet do
  @moduledoc """
  The application-owned on-disk backup-set format. A set is written below a
  generated staging directory, independently re-read by `Verifier`, then
  atomically renamed into place with its receipt. User supplied paths and
  filenames never select members in this format.
  """

  alias Playstead.Recovery.Verifier
  import Bitwise

  @schema "playstead.backup-set.v1"

  @spec build(map()) :: {:ok, map()} | {:error, atom()}
  def build(%{dump: nil}), do: {:error, :missing_dump}

  def build(%{
        id: id,
        correlation_id: correlation_id,
        kind: kind,
        dump: dump,
        members: members,
        metadata: metadata
      })
      when kind in [:full, :incremental] and is_list(members) and is_binary(id) and
             is_binary(correlation_id) do
    with {:ok, dump_entry} <- dump_entry(dump),
         {:ok, member_entries} <- member_entries(members),
         :ok <- valid_parent(kind, Map.get(metadata, :parent)) do
      entries = Enum.sort_by([dump_entry | member_entries], & &1["relative"])

      manifest = %{
        "schema" => @schema,
        "id" => id,
        "kind" => Atom.to_string(kind),
        "correlation_id" => correlation_id,
        "coverage" => %{
          "inventory_count" => length(member_entries),
          "entries" => entries,
          "release" => Map.get(metadata, :release, "unknown"),
          "configuration" => Map.get(metadata, :configuration, %{})
        },
        "parent" => Map.get(metadata, :parent)
      }

      {:ok,
       %{
         id: id,
         manifest: manifest,
         sources: Map.new(entries, &{&1["relative"], &1["source"]})
       }}
    end
  end

  def build(_), do: {:error, :invalid_backup_set}

  @doc "Materializes a persisted command through a bounded source reader, never request input."
  @spec materialize(map(), (String.t() -> {:ok, binary() | Enumerable.t()} | {:error, term()})) ::
          {:ok, map()} | {:error, term()}
  def materialize(%{"schema" => "playstead.recovery-command.v1"} = command, reader)
      when is_function(reader, 1) do
    with {:ok, dump} <- dump_artifact(command),
         {:ok, members} <- materialize_members(command["inventory"], reader) do
      build(%{
        id: command["id"],
        correlation_id: command["correlation_id"],
        kind: String.to_existing_atom(command["kind"]),
        dump: %{relative: "database.dump", path: dump},
        members: members,
        metadata: normalize_metadata(command["metadata"])
      })
    end
  rescue
    ArgumentError -> {:error, :invalid_command}
  end

  def materialize(_, _), do: {:error, :invalid_command}

  @doc """
  Produces a PostgreSQL custom-format dump at a generated file path.

  The caller must keep the exported repeatable-read transaction open until this
  function returns. The connection URL is intentionally an execution-only
  input: it is never copied into a recovery command, manifest, or receipt.
  """
  @spec capture_dump(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, atom()}
  def capture_dump(snapshot, root, opts \\ [])

  def capture_dump(snapshot, root, opts) when is_binary(snapshot) and is_binary(root) do
    with true <- snapshot != "",
         database_url when is_binary(database_url) and database_url != "" <-
           Keyword.get(opts, :database_url),
         :ok <- File.mkdir_p(root) do
      path = Path.join(root, "database-#{System.unique_integer([:positive, :monotonic])}.dump")

      args = [
        "--format=custom",
        "--file",
        path,
        "--snapshot",
        snapshot,
        "--dbname",
        database_url,
        "--no-password"
      ]

      runner = Keyword.get(opts, :command_runner, &default_command_runner/3)

      case run_dump(runner, args) do
        {:ok, 0} -> validate_dump_artifact(path)
        {:ok, _status} -> remove_failed_dump(path, :pg_dump_failed)
        {:error, :enoent} -> {:error, :pg_dump_unavailable}
        {:error, _reason} -> remove_failed_dump(path, :pg_dump_failed)
      end
    else
      false -> {:error, :database_snapshot_unavailable}
      _ -> {:error, :database_connection_unavailable}
    end
  end

  def capture_dump(_, _, _), do: {:error, :database_snapshot_unavailable}

  @spec publish(String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def publish(destination_root, %{id: id, manifest: manifest, sources: sources}, opts \\ []) do
    canonical_root = Keyword.get(opts, :canonical_root)

    with :ok <- validate_destination(destination_root, canonical_root),
         :ok <- File.mkdir_p(destination_root),
         staging <-
           Path.join(destination_root, ".staging-#{id}-#{System.unique_integer([:positive])}"),
         :ok <- File.mkdir_p(staging),
         :ok <- write_members(staging, sources),
         :ok <- write_json(Path.join(staging, "manifest.json"), manifest),
         {:ok, verification} <- Verifier.verify(staging),
         receipt <- receipt(manifest, verification, Keyword.get(opts, :attested, false)),
         :ok <- write_json(Path.join(staging, "receipt.json"), receipt),
         :ok <- fsync_directory(staging),
         final <- Path.join(destination_root, id),
         :ok <- publish_rename(staging, final) do
      {:ok, %{path: final, receipt: receipt}}
    else
      {:error, _} = error -> error
      reason -> {:error, reason}
    end
  end

  @doc "Reject canonical containment and, where available, equal filesystem identities."
  @spec validate_destination(String.t(), String.t() | nil) :: :ok | {:error, atom()}
  def validate_destination(destination_root, canonical_root) when is_binary(destination_root) do
    destination = Path.expand(destination_root)

    cond do
      is_binary(canonical_root) and overlaps?(destination, Path.expand(canonical_root)) ->
        {:error, :destination_overlaps_canonical}

      is_binary(canonical_root) and same_filesystem?(destination, canonical_root) ->
        {:error, :destination_same_filesystem}

      true ->
        :ok
    end
  end

  def validate_destination(_, _), do: {:error, :invalid_destination}

  @doc """
  Validates an existing operator-provided destination without writing it.

  This is deliberately narrower than `publish/3`: the release preflight must
  prove that a bind mount is a real writable directory before it is permitted
  to schedule any recovery work. A missing destination, symlink, or detectable
  shared filesystem fails closed. Filesystem topology cannot prove physical
  independence in every deployment, so a successful result remains explicitly
  operator-attested.
  """
  @spec preflight_destination(String.t(), String.t() | nil) ::
          {:ok, %{independence: String.t()}} | {:error, atom()}
  def preflight_destination(destination_root, canonical_root)
      when is_binary(destination_root) and destination_root != "" do
    with {:ok, stat} <- File.lstat(destination_root),
         :directory <- Map.get(stat, :type),
         false <- Map.get(stat, :type) == :symlink,
         true <- writable_mode?(stat),
         :ok <- validate_destination(destination_root, canonical_root) do
      {:ok, %{independence: "operator_attested"}}
    else
      {:error, :enoent} ->
        {:error, :destination_missing}

      {:error, reason}
      when reason in [
             :destination_overlaps_canonical,
             :destination_same_filesystem,
             :invalid_destination
           ] ->
        {:error, reason}

      {:error, _} ->
        {:error, :destination_unavailable}

      :symlink ->
        {:error, :destination_symlink}

      false ->
        {:error, :destination_not_writable}

      _ ->
        {:error, :destination_not_directory}
    end
  end

  def preflight_destination(_, _), do: {:error, :destination_missing}

  defp writable_mode?(%{mode: mode}) when is_integer(mode), do: band(mode, 0o222) != 0
  defp writable_mode?(_), do: false

  defp dump_entry(%{relative: relative, bytes: bytes})
       when is_binary(relative) and is_binary(bytes) do
    entry(relative, bytes, "logical_dump")
  end

  defp dump_entry(%{relative: relative, path: path})
       when is_binary(relative) and is_binary(path) do
    file_entry(relative, path, "logical_dump")
  end

  defp dump_entry(_), do: {:error, :missing_dump}

  defp member_entries(members) do
    members
    |> Enum.reduce_while({:ok, []}, fn member, {:ok, entries} ->
      case member_entry(member) do
        {:ok, entry} -> {:cont, {:ok, [entry | entries]}}
        error -> {:halt, error}
      end
    end)
    |> then(fn
      {:ok, entries} -> {:ok, Enum.reverse(entries)}
      error -> error
    end)
  end

  defp member_entry(%{sha256: sha256, bytes: bytes, kind: kind})
       when is_binary(sha256) and byte_size(sha256) == 64 and is_binary(bytes) and
              kind in [:game, :save] do
    entry(Path.join(["objects", String.slice(sha256, 0, 2), sha256]), bytes, Atom.to_string(kind))
  end

  defp member_entry(%{sha256: sha256, size_bytes: size, source: source, kind: kind})
       when is_binary(sha256) and byte_size(sha256) == 64 and is_integer(size) and size >= 0 and
              kind in [:game, :save] do
    streamed_entry(
      Path.join(["objects", String.slice(sha256, 0, 2), sha256]),
      sha256,
      size,
      source,
      Atom.to_string(kind)
    )
  end

  defp member_entry(_), do: {:error, :invalid_member}

  defp dump_artifact(%{"dump_path" => path}) when is_binary(path),
    do: validate_dump_artifact(path)

  defp dump_artifact(_), do: {:error, :missing_dump_artifact}

  defp materialize_members(inventory, reader) when is_list(inventory) do
    inventory
    |> Enum.reduce_while({:ok, []}, fn
      %{"sha256" => sha256, "size_bytes" => size, "kind" => _kind}, {:ok, members}
      when is_integer(size) and size >= 0 ->
        case reader.(sha256) do
          {:ok, bytes} when is_binary(bytes) ->
            {:cont, {:ok, [%{sha256: sha256, bytes: bytes, kind: :game} | members]}}

          {:ok, stream} ->
            {:cont,
             {:ok, [%{sha256: sha256, size_bytes: size, source: stream, kind: :game} | members]}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end

      _invalid_inventory, _acc ->
        {:halt, {:error, :invalid_inventory}}
    end)
    |> then(fn
      {:ok, members} -> {:ok, Enum.reverse(members)}
      error -> error
    end)
  end

  defp materialize_members(_, _), do: {:error, :invalid_inventory}

  defp normalize_metadata(metadata) do
    %{
      release: metadata["release"],
      configuration: metadata["configuration"],
      parent: metadata["parent"]
    }
  end

  defp entry(relative, bytes, kind) do
    if safe_relative?(relative) do
      {:ok,
       %{
         "relative" => relative,
         "kind" => kind,
         "size_bytes" => byte_size(bytes),
         "sha256" => digest(bytes),
         "source" => {:bytes, bytes}
       }}
    else
      {:error, :invalid_member_path}
    end
  end

  defp file_entry(relative, path, kind) do
    if custom_dump?(path) do
      with true <- safe_relative?(relative),
           {:ok, %{size: size}} <- File.stat(path),
           {:ok, sha256} <- digest_file(path) do
        {:ok,
         %{
           "relative" => relative,
           "kind" => kind,
           "size_bytes" => size,
           "sha256" => sha256,
           "source" => {:file, path}
         }}
      else
        false -> {:error, :invalid_member_path}
        {:error, _} -> {:error, :missing_dump_artifact}
      end
    else
      {:error, :invalid_dump_artifact}
    end
  end

  defp streamed_entry(relative, sha256, size, source, kind) do
    if safe_relative?(relative) and valid_source?(source) do
      {:ok,
       %{
         "relative" => relative,
         "kind" => kind,
         "size_bytes" => size,
         "sha256" => sha256,
         "source" => source
       }}
    else
      {:error, :invalid_member_path}
    end
  end

  defp valid_parent(:full, nil), do: :ok
  defp valid_parent(:full, _), do: {:error, :full_has_parent}
  defp valid_parent(:incremental, %{"receipt_id" => id}) when is_binary(id), do: :ok
  defp valid_parent(:incremental, %{receipt_id: id}) when is_binary(id), do: :ok
  defp valid_parent(:incremental, _), do: {:error, :missing_parent}

  defp write_members(root, sources) do
    Enum.reduce_while(sources, :ok, fn {relative, source}, :ok ->
      path = Path.join(root, relative)

      with true <- contained?(path, root),
           :ok <- File.mkdir_p(Path.dirname(path)),
           :ok <- write_source(path, source),
           :ok <- sync_file(path) do
        {:cont, :ok}
      else
        false -> {:halt, {:error, :invalid_member_path}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp write_json(path, value), do: File.write(path, Jason.encode!(strip_bytes(value)), [:binary])

  defp strip_bytes(value) when is_map(value) do
    value
    |> Enum.reject(fn {key, _} -> key in ["bytes", "source"] end)
    |> Map.new(fn {key, val} -> {key, strip_bytes(val)} end)
  end

  defp strip_bytes(value) when is_list(value), do: Enum.map(value, &strip_bytes/1)
  defp strip_bytes(value), do: value

  defp receipt(manifest, verification, attested) do
    %{
      "schema" => @schema,
      "receipt_id" => manifest["id"],
      "manifest_sha256" => digest(Jason.encode!(strip_bytes(manifest))),
      "correlation_id" => manifest["correlation_id"],
      "verified_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "verification" => verification,
      "independence" => if(attested, do: "operator_attested", else: "detected")
    }
  end

  defp publish_rename(staging, final) do
    if File.exists?(final), do: {:error, :already_published}, else: File.rename(staging, final)
  end

  defp sync_file(path) do
    with {:ok, io} <- File.open(path, [:read, :binary, :raw]) do
      try do
        :file.sync(io)
      after
        File.close(io)
      end
    end
  end

  defp fsync_directory(_path), do: :ok
  defp digest(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  defp digest_file(path) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        try do
          {:ok,
           hash_file(io, :crypto.hash_init(:sha256))
           |> :crypto.hash_final()
           |> Base.encode16(case: :lower)}
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp hash_file(io, context) do
    case :file.read(io, 1_048_576) do
      {:ok, chunk} -> hash_file(io, :crypto.hash_update(context, chunk))
      :eof -> context
      {:error, reason} -> throw({:file_hash_error, reason})
    end
  end

  defp validate_dump_artifact(path) do
    with {:ok, %{size: size}} when size > 5 <- File.stat(path),
         true <- custom_dump?(path) do
      {:ok, path}
    else
      _ -> remove_failed_dump(path, :invalid_dump_artifact)
    end
  end

  defp custom_dump?(path) do
    case File.open(path, [:read, :binary], fn io -> IO.binread(io, 5) end) do
      {:ok, "PGDMP"} -> true
      _ -> false
    end
  end

  defp remove_failed_dump(path, reason) do
    _ = File.rm(path)
    {:error, reason}
  end

  defp run_dump(runner, args) do
    case runner.("pg_dump", args, []) do
      {_output, status} when is_integer(status) -> {:ok, status}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :invalid_command_runner_result}
    end
  rescue
    ErlangError -> {:error, :enoent}
  end

  defp default_command_runner(executable, args, _opts),
    do: System.cmd(executable, args, stderr_to_stdout: true)

  defp write_source(path, {:bytes, bytes}) when is_binary(bytes),
    do: File.write(path, bytes, [:binary])

  defp write_source(path, {:file, source}) when is_binary(source), do: copy_file(source, path)

  defp write_source(path, stream) do
    with {:ok, io} <- File.open(path, [:write, :binary, :raw]) do
      try do
        Enum.reduce_while(stream, :ok, fn
          chunk, :ok when is_binary(chunk) ->
            case :file.write(io, chunk) do
              :ok -> {:cont, :ok}
              {:error, reason} -> {:halt, {:error, reason}}
            end

          _chunk, :ok ->
            {:halt, {:error, :invalid_blob_stream}}
        end)
      after
        File.close(io)
      end
    end
  end

  defp copy_file(source, destination) do
    case File.copy(source, destination) do
      {:ok, _bytes} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp valid_source?({:bytes, bytes}) when is_binary(bytes), do: true
  defp valid_source?({:file, path}) when is_binary(path), do: true
  defp valid_source?(source), do: Enumerable.impl_for(source) != nil

  defp safe_relative?(path),
    do: Path.type(path) != :absolute and not Enum.member?(Path.split(path), "..")

  defp contained?(path, root),
    do: Path.expand(path) |> String.starts_with?(Path.expand(root) <> "/")

  defp overlaps?(left, right),
    do:
      left == right or String.starts_with?(left, right <> "/") or
        String.starts_with?(right, left <> "/")

  defp same_filesystem?(left, right) do
    with {:ok, left_stat} <- File.stat(left), {:ok, right_stat} <- File.stat(right) do
      Map.get(left_stat, :major_device) == Map.get(right_stat, :major_device) and
        Map.get(left_stat, :minor_device) == Map.get(right_stat, :minor_device)
    else
      _ -> false
    end
  end
end
