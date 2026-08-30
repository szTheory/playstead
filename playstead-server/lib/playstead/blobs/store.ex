defmodule Playstead.Blobs.Store do
  @moduledoc """
  The storage adapter behaviour (D-12). This is the seam a future S3
  adapter must fit — `Playstead.Blobs.Store.LocalDisk` is the only v1
  implementation, and `Playstead.Blobs` is the only caller of whichever
  adapter is configured.

  `delete/1` is defined **only** for uncommitted temporary files (a
  path still under the adapter's own temporary storage area). No v1
  code path deletes, renames, truncates, or moves a committed blob —
  once bytes are visible at their content-addressed location they are
  never touched again by this behaviour's callbacks.
  """

  @type write_ref :: term()
  @type hash :: String.t()
  @type digest_map :: %{
          sha256: hash(),
          size_bytes: non_neg_integer(),
          crc32: hash(),
          md5: hash(),
          sha1: hash()
        }

  @doc "Opens a new write for a file of (approximately) `byte_size_hint` bytes. Re-checks free space before returning."
  @callback open_write(byte_size_hint :: non_neg_integer()) ::
              {:ok, write_ref()} | {:error, :insufficient_space} | {:error, term()}

  @doc "Writes one chunk and folds it into the write's running multi-hash accumulator."
  @callback write_chunk(write_ref(), binary()) :: {:ok, write_ref()} | {:error, term()}

  @doc """
  Fsyncs, closes, and re-hashes the written bytes to verify them, then
  atomically renames the file into its content-addressed path.
  Returns `{:ok, :stored, digest_map}` for genuinely new content or
  `{:ok, :existing, digest_map}` when the database's unique constraint
  on `sha256` reveals the content was already present.
  """
  @callback commit(write_ref(), opts :: keyword()) ::
              {:ok, :stored, digest_map()} | {:ok, :existing, digest_map()} | {:error, term()}

  @doc "Aborts an in-progress write: closes and removes the temporary file. Leaves nothing behind."
  @callback abort(write_ref()) :: :ok

  @doc "Whether a committed blob exists at the content-addressed path for `sha256`."
  @callback exists?(hash()) :: boolean()

  @doc "Filesystem stat for a committed blob, or `{:error, :not_found}`."
  @callback stat(hash()) :: {:ok, map()} | {:error, :not_found}

  @doc "A byte stream for a committed blob, optionally restricted to `range` (an inclusive `Range.t()`, or `nil` for the whole file)."
  @callback stream(hash(), range :: Range.t() | nil) ::
              {:ok, Enumerable.t()} | {:error, :not_found}

  @doc """
  Reads at most `byte_count` leading bytes of the committed object for
  `sha256`, read-only and never decompressing — a container's bytes
  come back exactly as stored. A committed object shorter than
  `byte_count` is not an error: every byte it has is returned. Returns
  `{:error, :not_found}` when no committed object exists for `sha256`.
  This callback never deletes, renames, truncates, or moves the object
  it reads.
  """
  @callback read_leading(hash(), byte_count :: pos_integer()) ::
              {:ok, binary()} | {:error, :not_found}

  @doc "Bytes currently free on the volume backing this store, or `:unknown`."
  @callback free_bytes() :: non_neg_integer() | :unknown

  @doc "Whether the store's volume is currently writable."
  @callback writable?() :: boolean()

  @doc """
  Removes an uncommitted temporary file by path. Refuses (returns
  `{:error, :refused}`) for any path outside the adapter's own
  temporary storage area — this is what keeps the orphan sweeper from
  ever being able to touch a committed blob.
  """
  @callback delete(path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Adopts an already-written, already-hashed temporary file — the
  completed output of `Playstead.Import.HashingWriter`'s own streaming
  hash-while-write (D-01a) — into the CAS without re-streaming its
  bytes: re-hashes on disk for verification (same as `commit/2`), then
  renames atomically into the content-addressed path. `digest_map` must
  include `:size_bytes`. Returns `{:ok, :stored, digest_map}` or
  `{:ok, :existing, digest_map}` under the same collision authority as
  `commit/2` (the database's unique constraint on `sha256`).
  """
  @callback adopt_temp_file(path :: String.t(), digest_map()) ::
              {:ok, :stored | :existing, digest_map()} | {:error, term()}
end
