defmodule Playstead.Blobs.Store.LocalDisk do
  @moduledoc """
  The sole v1 `Playstead.Blobs.Store` adapter (D-11): temp-then-fsync-
  then-verify-then-atomic-rename into a two-level content-addressed
  tree, with the database's unique constraint on `blobs.sha256` — never
  a prior `exists?/1` read — as the sole authority for "this content
  already exists" (RESEARCH Pitfall 4: `exists?` followed by a
  conditional write is a check-then-act race that two concurrent
  identical imports will lose).

  Both `tmp/` and `objects/` live under one blob path so the commit
  rename stays on one filesystem and stays atomic (RESEARCH Pitfall 2;
  `Playstead.Readiness`'s `:blob_volume_atomicity` row reports a split
  mount before it can matter here).
  """

  @behaviour Playstead.Blobs.Store

  alias Playstead.Blobs.{Blob, MultiHash}
  alias Playstead.Repo

  @blob_path_env "PLAYSTEAD_BLOB_PATH"
  @default_blob_path "/app/blobs"

  defmodule WriteRef do
    @moduledoc false
    defstruct [:tmp_path, :io_device, :hash_ctx, :size, :blob_path]
  end

  @doc "The configured blob volume root. Exported for `Playstead.Import.OrphanSweeper`."
  @spec blob_path() :: String.t()
  def blob_path, do: System.get_env(@blob_path_env) || @default_blob_path

  @impl true
  def open_write(byte_size_hint) do
    path = blob_path()

    if space_available?(path, byte_size_hint) do
      do_open_write(path)
    else
      {:error, :insufficient_space}
    end
  end

  defp space_available?(path, byte_size_hint) do
    available = Playstead.Readiness.free_bytes(path)
    capacity = capacity_bytes(path)

    case {available, capacity} do
      {avail, cap} when is_integer(avail) and is_integer(cap) ->
        Playstead.Readiness.fits_free_space?(byte_size_hint, avail, cap)

      _unknown ->
        # Cannot verify here (e.g. path does not exist yet in a fresh
        # dev checkout) — degrade gracefully rather than refuse every
        # write, matching Readiness's own graceful-fallback shape.
        true
    end
  end

  @doc """
  Total capacity, in bytes, of the filesystem backing `path` (defaults
  to the blob volume). Exported for `Playstead.Import.Preview`, which
  needs the same `df`-derived figure `Playstead.Readiness.required_bytes/2`
  uses to compute the IMPT-01 storage-cost preview before a single byte
  moves.
  """
  @spec capacity_bytes(String.t()) :: non_neg_integer() | :unknown
  def capacity_bytes(path \\ blob_path())

  def capacity_bytes(path) do
    case System.cmd("df", ["-Pk", path], stderr_to_stdout: true) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)
        |> List.last()
        |> parse_df_total_kb()

      _ ->
        :unknown
    end
  rescue
    _ -> :unknown
  end

  defp parse_df_total_kb(nil), do: :unknown

  defp parse_df_total_kb(line) do
    case String.split(line) do
      [_filesystem, blocks_kb, _used, _available | _rest] ->
        case Integer.parse(blocks_kb) do
          {kb, _rest} -> kb * 1024
          :error -> :unknown
        end

      _ ->
        :unknown
    end
  end

  defp do_open_write(path) do
    tmp_dir = Path.join(path, "tmp")
    File.mkdir_p!(tmp_dir)

    tmp_path =
      Path.join(
        tmp_dir,
        "#{System.unique_integer([:positive, :monotonic])}-#{:erlang.phash2(make_ref())}.partial"
      )

    case File.open(tmp_path, [:write, :binary, :raw]) do
      {:ok, io} ->
        {:ok,
         %WriteRef{
           tmp_path: tmp_path,
           io_device: io,
           hash_ctx: MultiHash.init(),
           size: 0,
           blob_path: path
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def write_chunk(%WriteRef{} = ref, chunk) when is_binary(chunk) do
    case :file.write(ref.io_device, chunk) do
      :ok ->
        {:ok,
         %{
           ref
           | hash_ctx: MultiHash.update(ref.hash_ctx, chunk),
             size: ref.size + byte_size(chunk)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def commit(ref, opts \\ [])

  def commit(%WriteRef{} = ref, opts) do
    :ok = :file.sync(ref.io_device)
    :ok = :file.close(ref.io_device)

    digests = MultiHash.finalize(ref.hash_ctx)
    expected_sha256 = Keyword.get(opts, :expected_sha256)

    with :ok <- verify_declared_digest(digests.sha256, expected_sha256),
         :ok <- verify_on_disk(ref.tmp_path, digests.sha256) do
      place_and_record(ref, digests)
    else
      {:error, _reason} = err ->
        File.rm(ref.tmp_path)
        err
    end
  end

  @impl true
  def adopt_temp_file(tmp_path, %{sha256: sha256, size_bytes: size_bytes} = digest_map) do
    with :ok <- verify_on_disk(tmp_path, sha256) do
      place_and_record(
        %WriteRef{tmp_path: tmp_path, blob_path: blob_path(), size: size_bytes},
        digest_map
      )
    else
      {:error, _reason} = err ->
        File.rm(tmp_path)
        err
    end
  end

  # A caller-declared digest (e.g. the client's RFC 9530 Repr-Digest,
  # decoded and hex-encoded by PlaysteadWeb.Plugs.ReprDigest) that does
  # not match what the server itself streamed refuses the commit before
  # any bytes are ever renamed into place or any row is written — the
  # bytes are never trusted to be what the client claimed.
  defp verify_declared_digest(_streamed_sha256, nil), do: :ok

  defp verify_declared_digest(streamed_sha256, streamed_sha256), do: :ok

  defp verify_declared_digest(_streamed_sha256, _expected_sha256), do: {:error, :digest_mismatch}

  defp verify_on_disk(tmp_path, expected_sha256) do
    if import_verify?() do
      case rehash_file(tmp_path) do
        {:ok, ^expected_sha256} -> :ok
        _mismatch_or_error -> {:error, :hash_mismatch}
      end
    else
      :ok
    end
  end

  defp import_verify? do
    case System.get_env("PLAYSTEAD_IMPORT_VERIFY") do
      "false" -> false
      _ -> true
    end
  end

  defp rehash_file(path) do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        try do
          acc = read_and_hash(io, MultiHash.init())
          {:ok, MultiHash.finalize(acc).sha256}
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @chunk_size 1_048_576

  defp read_and_hash(io, acc) do
    case :file.read(io, @chunk_size) do
      {:ok, data} -> read_and_hash(io, MultiHash.update(acc, data))
      :eof -> acc
    end
  end

  defp place_and_record(ref, digests) do
    dest_path = object_path(ref.blob_path, digests.sha256)
    File.mkdir_p!(Path.dirname(dest_path))

    placement =
      if File.exists?(dest_path) do
        # Content-addressed path already holds identical bytes (same
        # hash) — no rewrite needed; just drop our own temp copy.
        File.rm(ref.tmp_path)
        :ok
      else
        File.rename(ref.tmp_path, dest_path)
      end

    case placement do
      :ok ->
        insert_blob_row(digests, ref.size)

      {:error, reason} ->
        File.rm(ref.tmp_path)
        {:error, reason}
    end
  end

  # Repo.insert_all/3 with on_conflict: :nothing, not Repo.insert/2 +
  # catching a unique_constraint error: a failed constrained
  # Repo.insert leaves the ambient Postgres transaction aborted for
  # every later query in that same transaction whenever this call is
  # itself nested inside another one (e.g. Playstead.Idempotency.execute/4's
  # Ecto.Multi) — insert_all with on_conflict never raises, so there is
  # nothing to recover from. The affected-row count (0 vs 1) is what
  # tells `stored` from `existing` apart; the database's unique index
  # on sha256 remains the sole collision authority either way (D-11,
  # RESEARCH Pitfall 4).
  defp insert_blob_row(digests, size) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      id: Ecto.UUID.generate(),
      sha256: digests.sha256,
      size_bytes: size,
      crc32: digests.crc32,
      md5: digests.md5,
      sha1: digests.sha1,
      scan_state: "clean",
      inserted_at: now,
      updated_at: now
    }

    {count, _} =
      Repo.insert_all(Blob, [attrs], on_conflict: :nothing, conflict_target: [:sha256])

    blob = Repo.get_by!(Blob, sha256: digests.sha256)

    if count == 1 do
      {:ok, :stored, digest_result(blob)}
    else
      {:ok, :existing, digest_result(blob)}
    end
  end

  defp digest_result(%Blob{} = blob) do
    %{
      sha256: blob.sha256,
      size_bytes: blob.size_bytes,
      crc32: blob.crc32,
      md5: blob.md5,
      sha1: blob.sha1,
      blob_id: blob.id
    }
  end

  @impl true
  def abort(%WriteRef{} = ref) do
    File.close(ref.io_device)
    File.rm(ref.tmp_path)
    :ok
  end

  @impl true
  def exists?(sha256) do
    File.exists?(object_path(blob_path(), sha256))
  end

  @impl true
  def stat(sha256) do
    case File.stat(object_path(blob_path(), sha256)) do
      {:ok, stat} -> {:ok, %{size_bytes: stat.size}}
      {:error, _reason} -> {:error, :not_found}
    end
  end

  @impl true
  def stream(sha256, range \\ nil) do
    path = object_path(blob_path(), sha256)

    if File.exists?(path) do
      {:ok, build_stream(path, range)}
    else
      {:error, :not_found}
    end
  end

  defp build_stream(path, nil), do: File.stream!(path, [], @chunk_size)

  defp build_stream(path, first..last//_step) do
    data = File.read!(path)
    last = min(last, byte_size(data) - 1)
    [binary_part(data, first, last - first + 1)]
  end

  @impl true
  def free_bytes, do: Playstead.Readiness.free_bytes(blob_path())

  @impl true
  def writable? do
    probe = Path.join(blob_path(), ".playstead-store-probe")

    case File.write(probe, "ok") do
      :ok ->
        File.rm(probe)
        true

      {:error, _reason} ->
        false
    end
  rescue
    _ -> false
  end

  @impl true
  def delete(path) do
    tmp_dir = Path.join(blob_path(), "tmp")

    if String.starts_with?(path, tmp_dir) do
      File.rm(path)
      :ok
    else
      {:error, :refused}
    end
  end

  @doc false
  def object_path(blob_path, sha256) do
    <<a::binary-size(2), b::binary-size(2), _rest::binary>> = sha256
    Path.join([blob_path, "objects", "sha256", a, b, sha256])
  end
end
