defmodule Playstead.Blobs.MultiHash do
  @moduledoc """
  SHA-256, SHA-1, MD5, and CRC32 computed in a single streaming pass
  (D-20, RESEARCH Pattern 1). One accumulator belongs to one file and
  threads sequentially through that file's own chunks — parallelism in
  this phase is across files, never across chunks within a file,
  because a hash context cannot be split (RESEARCH Pitfall 1: a
  chunk-parallel hash produces a wrong digest that only surfaces at the
  read-back check, or ships silently wrong if verification is ever
  disabled).
  """

  defstruct [:sha256, :sha1, :md5, :crc32]

  @type t :: %__MODULE__{}

  @doc "A fresh accumulator for one file."
  @spec init() :: t()
  def init do
    %__MODULE__{
      sha256: :crypto.hash_init(:sha256),
      sha1: :crypto.hash_init(:sha),
      md5: :crypto.hash_init(:md5),
      crc32: 0
    }
  end

  @doc "Folds `chunk` into the accumulator. Chunks may be any size and any number."
  @spec update(t(), binary()) :: t()
  def update(%__MODULE__{} = acc, chunk) when is_binary(chunk) do
    %__MODULE__{
      sha256: :crypto.hash_update(acc.sha256, chunk),
      sha1: :crypto.hash_update(acc.sha1, chunk),
      md5: :crypto.hash_update(acc.md5, chunk),
      crc32: :erlang.crc32(acc.crc32, chunk)
    }
  end

  @doc "Finalizes the accumulator into lowercase hexadecimal digests for all four algorithms."
  @spec finalize(t()) :: %{
          sha256: String.t(),
          sha1: String.t(),
          md5: String.t(),
          crc32: String.t()
        }
  def finalize(%__MODULE__{} = acc) do
    %{
      sha256: :crypto.hash_final(acc.sha256) |> Base.encode16(case: :lower),
      sha1: :crypto.hash_final(acc.sha1) |> Base.encode16(case: :lower),
      md5: :crypto.hash_final(acc.md5) |> Base.encode16(case: :lower),
      crc32: crc32_hex(acc.crc32)
    }
  end

  @doc """
  Computes the SHA-256 of an entire binary in one shot (no streaming).
  Used by tests to assert chunked and single-shot hashing agree, and by
  any caller that already holds the whole binary in memory.
  """
  @spec sha256_of(binary()) :: String.t()
  def sha256_of(binary) when is_binary(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
  end

  @doc """
  Computes the CRC32/MD5/SHA-1 triple over the bytes of `path` starting
  at `offset` (a headerless-offset fingerprint, D-20). Reads the file in
  one mebibyte chunks; does not touch the SHA-256 (SHA-256 is always
  computed over the whole file by the write path, never from an
  offset).
  """
  @spec digest_from_offset(String.t(), non_neg_integer()) ::
          {:ok, %{crc32: String.t(), md5: String.t(), sha1: String.t()}} | {:error, term()}
  def digest_from_offset(path, offset) when is_integer(offset) and offset >= 0 do
    case File.open(path, [:read, :binary, :raw]) do
      {:ok, io} ->
        try do
          case :file.position(io, offset) do
            {:ok, _pos} ->
              acc =
                stream_hash_from(io, %{
                  sha1: :crypto.hash_init(:sha),
                  md5: :crypto.hash_init(:md5),
                  crc32: 0
                })

              {:ok,
               %{
                 crc32: crc32_hex(acc.crc32),
                 md5: :crypto.hash_final(acc.md5) |> Base.encode16(case: :lower),
                 sha1: :crypto.hash_final(acc.sha1) |> Base.encode16(case: :lower)
               }}

            {:error, reason} ->
              {:error, reason}
          end
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @chunk_size 1_048_576

  defp stream_hash_from(io, acc) do
    case :file.read(io, @chunk_size) do
      {:ok, data} ->
        stream_hash_from(io, %{
          sha1: :crypto.hash_update(acc.sha1, data),
          md5: :crypto.hash_update(acc.md5, data),
          crc32: :erlang.crc32(acc.crc32, data)
        })

      :eof ->
        acc
    end
  end

  defp crc32_hex(crc32) do
    crc32
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(8, "0")
  end
end
