defmodule Playstead.Recognition.LogiqxHandler do
  @moduledoc """
  The safe, capped, streaming parser for a Logiqx-style DAT reference
  pack (D-18, T-02-59, T-02-60, T-02-61). Reads the pack from disk in
  fixed-size chunks and refuses before the file is fully read once the
  hard size cap is exceeded; refuses outright — without ever handing
  the bytes to the XML parser — a document that declares a document
  type or an entity, since those are exactly the constructs external
  entity expansion and recursive expansion attacks depend on; enforces
  a hard cap on the number of `rom` entries, refusing at the cap; and
  never raises for any input, including truncated, empty, or randomly
  mutated bytes.

  `Saxy` (the added, audited dependency) does not itself refuse a
  document type declaration — its documented default is to silently
  skip DTD/XSD content and never expand an external entity reference.
  This module does not rely on that default alone: it scans the
  already-capped bytes for the literal `<!DOCTYPE` / `<!ENTITY` markup
  declaration tokens before Saxy ever sees them, so no external
  resource a hostile DOCTYPE might name is ever a live code path here,
  regardless of the parser's own configuration.

  Declared `size` attributes are read as plain metadata and stored
  as-is; nothing here ever uses a declared size to allocate a buffer or
  size a collection (T-02-61).
  """

  @behaviour Saxy.Handler

  # A generous but hard ceiling: real Logiqx/No-Intro DAT packs for a
  # full console library run a few megabytes; 32 MiB comfortably covers
  # the largest real-world pack while still bounding a hostile upload.
  # Overridable via application env so a test can exercise "refused at
  # the cap" without constructing a multi-hundred-thousand-entry fixture.
  @default_max_bytes 33_554_432
  @default_max_entries 500_000
  @chunk_size 65_536

  @forbidden_tokens ["<!DOCTYPE", "<!ENTITY"]

  defp max_bytes, do: Application.get_env(:playstead, :logiqx_max_bytes, @default_max_bytes)
  defp max_entries, do: Application.get_env(:playstead, :logiqx_max_entries, @default_max_entries)

  defmodule State do
    @moduledoc false
    defstruct entries: [], count: 0, current_game: nil, halted_reason: nil
  end

  @typedoc "One parsed entry: a rom's declared name, digests, and size."
  @type entry :: %{
          name: String.t() | nil,
          crc32: String.t() | nil,
          md5: String.t() | nil,
          sha1: String.t() | nil,
          size_bytes: integer() | nil
        }

  @doc """
  Parses the pack at `path`. Returns `{:ok, entries}` for a well-formed
  document under every cap, or `{:error, reason}` for anything else —
  never raises.
  """
  @spec parse_file(String.t()) :: {:ok, [entry()]} | {:error, atom()}
  def parse_file(path) do
    with {:ok, binary} <- read_capped(path) do
      parse_binary(binary)
    end
  rescue
    _ -> {:error, :parse_failed}
  end

  @doc """
  Parses an already-capped, in-memory pack binary. Exposed so
  `Playstead.Recognition.DatPackImporter` can hash the exact same
  bounded bytes this parser reads, without reading the file from disk
  a second time.
  """
  @spec parse_binary(binary()) :: {:ok, [entry()]} | {:error, atom()}
  def parse_binary(binary) when is_binary(binary) do
    with :ok <- guard_forbidden(binary) do
      do_parse(binary)
    end
  rescue
    _ -> {:error, :parse_failed}
  end

  @doc """
  Reads `path` in fixed-size chunks, refusing with `{:error, :too_large}`
  the moment the running total exceeds the hard size cap — before the
  file is ever fully read (T-02-60). Exposed (not `defp`) so the
  importer can compute the pack's own file hash over the identical
  bounded bytes this parser will see.
  """
  @spec read_capped(String.t()) :: {:ok, binary()} | {:error, atom()}
  def read_capped(path) do
    path
    |> File.stream!([], @chunk_size)
    |> Enum.reduce_while({:ok, <<>>}, fn chunk, {:ok, acc} ->
      new_acc = acc <> chunk

      if byte_size(new_acc) > max_bytes() do
        {:halt, {:error, :too_large}}
      else
        {:cont, {:ok, new_acc}}
      end
    end)
  rescue
    _ -> {:error, :read_failed}
  end

  defp guard_forbidden(binary) do
    if Enum.any?(@forbidden_tokens, fn token -> :binary.match(binary, token) != :nomatch end) do
      {:error, :dtd_or_entity_declared}
    else
      :ok
    end
  end

  defp do_parse(binary) do
    case Saxy.parse_string(binary, __MODULE__, %State{}, expand_entity: :skip) do
      {:ok, %State{halted_reason: nil} = state} ->
        {:ok, Enum.reverse(state.entries)}

      {:ok, %State{halted_reason: reason}} ->
        {:error, reason}

      {:error, _exception} ->
        {:error, :malformed}

      {:halt, _state, _rest} ->
        {:error, :malformed}
    end
  rescue
    _ -> {:error, :parse_failed}
  end

  # --- Saxy.Handler --------------------------------------------------

  @impl Saxy.Handler
  def handle_event(:start_element, {"game", attrs}, state) do
    {:ok, %{state | current_game: find_attr(attrs, "name")}}
  end

  def handle_event(:start_element, {"rom", attrs}, %State{count: count} = state) do
    if count >= max_entries() do
      {:stop, %{state | halted_reason: :entry_cap_exceeded}}
    else
      entry = %{
        name: find_attr(attrs, "name") || state.current_game,
        crc32: find_attr(attrs, "crc") |> normalize_crc32(),
        md5: find_attr(attrs, "md5") |> normalize_digest(),
        sha1: find_attr(attrs, "sha1") |> normalize_digest(),
        size_bytes: find_attr(attrs, "size") |> parse_size()
      }

      {:ok, %{state | entries: [entry | state.entries], count: state.count + 1}}
    end
  end

  def handle_event(_event_name, _event_data, state), do: {:ok, state}

  defp find_attr(attrs, name) do
    Enum.find_value(attrs, fn {k, v} -> if k == name, do: v end)
  end

  defp normalize_digest(nil), do: nil
  defp normalize_digest(value) when is_binary(value), do: String.downcase(value)

  # A DAT's `crc` attribute has had a leading zero stripped in the
  # wild (plan 02-10 gap closure) — `Playstead.Blobs.MultiHash` always
  # zero-pads CRC32 to eight lowercase hex characters, and digests are
  # compared with `==`, so an unpadded value here could never match a
  # computed one. MD5 and SHA-1 are fixed-width in every real DAT and
  # need no padding.
  defp normalize_crc32(nil), do: nil

  defp normalize_crc32(value) when is_binary(value) do
    value |> String.downcase() |> String.pad_leading(8, "0")
  end

  # A declared size is a claim made by a file, stored as metadata only
  # (T-02-61). A value outside the storage column's representable range
  # is exactly the kind of implausible claim this function must survive
  # without crashing — it is dropped to `nil` rather than ever being
  # handed to anything that would allocate or size a buffer from it.
  @max_representable_size 9_223_372_036_854_775_807

  defp parse_size(nil), do: nil

  defp parse_size(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} when int >= 0 and int <= @max_representable_size -> int
      _ -> nil
    end
  end
end
