defmodule Playstead.Blobs do
  @moduledoc """
  The blob storage context (D-11, D-12) — the only caller of the
  configured `Playstead.Blobs.Store` adapter anywhere in the
  application. Nothing in the import or export pipeline may reference
  `Playstead.Blobs.Store` or `Playstead.Blobs.Store.LocalDisk` directly.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs.{Blob, Release}
  alias Playstead.Repo

  @default_store Playstead.Blobs.Store.LocalDisk

  # Matches Playstead.Formats' @max_read: the SNES copier probe reaches
  # 512 + 0xFFC0 + 0x20 = 66,048 bytes, so this is the smallest bounded
  # read that lets every validator see everything it needs.
  @default_leading_bytes 66_048

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

  @doc """
  Reads at most `byte_count` (default #{@default_leading_bytes}) leading
  bytes of the committed blob for `sha256`, read-only and bounded. See
  `Playstead.Blobs.Store.read_leading/2`.
  """
  @spec read_leading(String.t(), pos_integer()) :: {:ok, binary()} | {:error, :not_found}
  def read_leading(sha256, byte_count \\ @default_leading_bytes),
    do: store().read_leading(sha256, byte_count)

  @doc "Bytes currently free on the configured store's volume."
  @spec free_bytes() :: non_neg_integer() | :unknown
  def free_bytes, do: store().free_bytes()

  @doc "Whether the configured store's volume is writable."
  @spec writable?() :: boolean()
  def writable?, do: store().writable?()

  @doc "Fetches a committed blob's row by its content hash, or `nil`."
  @spec get_by_sha256(String.t()) :: Blob.t() | nil
  def get_by_sha256(sha256), do: Repo.get_by(Blob, sha256: sha256)

  @doc """
  Sets `blob`'s shared quarantine state and reason (D-28). Never moves
  or copies the underlying bytes — quarantine is a state on the
  existing CAS row, not a second store.
  """
  @spec quarantine(Blob.t() | String.t(), atom() | String.t()) ::
          {:ok, Blob.t()} | {:error, term()}
  def quarantine(%Blob{} = blob, reason) do
    blob |> Blob.quarantine_changeset(to_string(reason)) |> Repo.update()
  end

  def quarantine(sha256, reason) when is_binary(sha256) do
    case get_by_sha256(sha256) do
      nil -> {:error, :not_found}
      blob -> quarantine(blob, reason)
    end
  end

  @doc "Quarantines the blob identified by its primary key (D-28) — never by its content hash."
  @spec quarantine_by_id(binary(), atom() | String.t()) :: {:ok, Blob.t()} | {:error, term()}
  def quarantine_by_id(blob_id, reason) do
    case Repo.get(Blob, blob_id) do
      nil -> {:error, :not_found}
      blob -> quarantine(blob, reason)
    end
  end

  @doc """
  Whether `blob` is currently quarantined — a policy state on the
  bytes themselves, shared across every user who happens to reference
  them (D-28).
  """
  @spec quarantined?(Blob.t()) :: boolean()
  def quarantined?(%Blob{} = blob), do: Blob.quarantined?(blob)

  @doc """
  Records `user_id`'s own release decision over `blob_id` (D-28). The
  machine verdict on the shared bytes never changes; only this user's
  own record of having released them does. Idempotent: releasing
  twice for the same user/blob updates the existing row rather than
  raising a unique-constraint error.
  """
  @spec release(pos_integer(), binary(), String.t()) :: {:ok, Release.t()} | {:error, term()}
  def release(user_id, blob_id, resolution) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    attrs = %{
      user_id: user_id,
      blob_id: blob_id,
      resolution: to_string(resolution),
      released_at: now
    }

    %Release{}
    |> Release.create_changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:resolution, :released_at, :updated_at]},
      conflict_target: [:user_id, :blob_id]
    )
  end

  @doc """
  Whether `user_id` has released `blob_id` for their own use (D-28).
  Scoped strictly to this user's own release row — never influenced by
  another user's release of the same shared bytes.
  """
  @spec released_for_user?(pos_integer(), binary()) :: boolean()
  def released_for_user?(user_id, blob_id) do
    from(r in Release, where: r.user_id == ^user_id and r.blob_id == ^blob_id) |> Repo.exists?()
  end
end
