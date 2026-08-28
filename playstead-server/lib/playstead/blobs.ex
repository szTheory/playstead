defmodule Playstead.Blobs do
  @moduledoc """
  The blob storage context (D-11, D-12) — the only caller of the
  configured `Playstead.Blobs.Store` adapter anywhere in the
  application. Nothing in the import or export pipeline may reference
  `Playstead.Blobs.Store` or `Playstead.Blobs.Store.LocalDisk` directly.
  """

  @default_store Playstead.Blobs.Store.LocalDisk

  defp store do
    Application.get_env(:playstead, __MODULE__, []) |> Keyword.get(:store, @default_store)
  end

  @doc """
  Streams `chunk_stream` (any `Enumerable` of binaries) through the
  configured store, hashing and writing as it goes. Aborts and cleans
  up on any write failure.
  """
  @spec put_stream(Enumerable.t(), non_neg_integer(), keyword()) ::
          {:ok, :stored, map()} | {:ok, :existing, map()} | {:error, term()}
  def put_stream(chunk_stream, byte_size_hint, opts \\ []) do
    store = store()

    with {:ok, ref} <- store.open_write(byte_size_hint) do
      case reduce_chunks(store, ref, chunk_stream) do
        {:ok, ref} -> store.commit(ref, opts)
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp reduce_chunks(store, ref, chunk_stream) do
    Enum.reduce_while(chunk_stream, {:ok, ref}, fn chunk, {:ok, current_ref} ->
      case store.write_chunk(current_ref, chunk) do
        {:ok, next_ref} ->
          {:cont, {:ok, next_ref}}

        {:error, reason} ->
          store.abort(current_ref)
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Whether a committed blob exists for `sha256`."
  @spec exists?(String.t()) :: boolean()
  def exists?(sha256), do: store().exists?(sha256)

  @doc "Filesystem stat for a committed blob."
  @spec stat(String.t()) :: {:ok, map()} | {:error, :not_found}
  def stat(sha256), do: store().stat(sha256)

  @doc "A byte stream for a committed blob."
  @spec stream(String.t(), Range.t() | nil) :: {:ok, Enumerable.t()} | {:error, :not_found}
  def stream(sha256, range \\ nil), do: store().stream(sha256, range)

  @doc """
  Adopts an already-written, already-hashed temporary file — the
  completed output of `Playstead.Import.HashingWriter`'s streaming
  hash-while-write (D-01a) — into the CAS without re-streaming its
  bytes. See `Playstead.Blobs.Store.adopt_temp_file/2`.
  """
  @spec adopt_temp_file(String.t(), map()) ::
          {:ok, :stored | :existing, map()} | {:error, term()}
  def adopt_temp_file(tmp_path, digest_map), do: store().adopt_temp_file(tmp_path, digest_map)

  @doc "Bytes currently free on the configured store's volume."
  @spec free_bytes() :: non_neg_integer() | :unknown
  def free_bytes, do: store().free_bytes()

  @doc "Whether the configured store's volume is writable."
  @spec writable?() :: boolean()
  def writable?, do: store().writable?()
end
