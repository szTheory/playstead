defmodule Playstead.Import.HashingWriter do
  @moduledoc """
  The D-01a browser-upload path: a custom `Phoenix.LiveView.UploadWriter`
  that hashes each chunk while writing it straight to a temporary file
  on the blob volume, so the bytes streamed from the browser are read
  exactly once.

  This writer does **not** commit the finished file into the
  content-addressed store — it only produces a completed, fsynced
  temporary file plus its finalized digests, left exactly where it is
  (RESEARCH Pattern 2). `Playstead.Import.import_upload/3` hands that
  completed file to `Playstead.Blobs.adopt_temp_file/2` — the same
  commit path the API upload uses — once the user confirms the copy
  (`PlaysteadWeb.ImportLive`), so bytes are only ever written to disk
  once, whether or not the user ultimately confirms.

  Every callback returns a tagged tuple or `{:ok, state}` — never
  raises. A failure to open the temporary file, or a write failure
  partway through, is reported as an error; an aborted or cancelled
  upload's `close/2` removes the temporary file so nothing is left
  behind (D-29).
  """

  @behaviour Phoenix.LiveView.UploadWriter

  alias Playstead.Blobs.MultiHash
  alias Playstead.Blobs.Store.LocalDisk

  @impl true
  def init(opts) do
    size_hint = Keyword.get(opts, :size_hint, 0)
    blob_path = Keyword.get(opts, :blob_path, LocalDisk.blob_path())

    if over_browser_ceiling?(size_hint) do
      {:error, :file_too_large}
    else
      open_temp_file(blob_path)
    end
  end

  # The browser ceiling (D-03) is also enforced by LiveView's own
  # `:max_file_size` upload option, which never even calls `init/1` for
  # an oversize entry — this is a second, defense-in-depth check at the
  # writer boundary itself, so the point stands even when this module
  # is driven directly (as in its own unit tests) rather than through a
  # configured `allow_upload/3`.
  defp over_browser_ceiling?(size_hint) do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes, 0)
    is_integer(ceiling) and ceiling > 0 and is_integer(size_hint) and size_hint > ceiling
  end

  defp open_temp_file(blob_path) do
    tmp_dir = Path.join(blob_path, "tmp")
    tmp_path = unique_tmp_path(tmp_dir)

    case File.mkdir_p(tmp_dir) do
      :ok ->
        case File.open(tmp_path, [:write, :binary, :raw]) do
          {:ok, io} -> {:ok, %{io: io, path: tmp_path, hash: MultiHash.init(), size: 0}}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unique_tmp_path(tmp_dir) do
    Path.join(
      tmp_dir,
      "upload-#{System.unique_integer([:positive, :monotonic])}-#{:erlang.phash2(make_ref())}.partial"
    )
  end

  @impl true
  def meta(state), do: Map.take(state, [:path, :digests])

  @impl true
  def write_chunk(chunk, state) when is_binary(chunk) do
    case :file.write(state.io, chunk) do
      :ok ->
        {:ok,
         %{state | hash: MultiHash.update(state.hash, chunk), size: state.size + byte_size(chunk)}}

      {:error, reason} ->
        {:error, reason, state}
    end
  end

  @impl true
  def close(state, :done) do
    :ok = :file.sync(state.io)
    :ok = File.close(state.io)

    digests =
      state.hash
      |> MultiHash.finalize()
      |> Map.put(:size_bytes, state.size)

    {:ok, Map.put(state, :digests, digests)}
  end

  def close(state, _reason) do
    File.close(state.io)
    LocalDisk.delete(state.path)
    {:ok, state}
  end
end
