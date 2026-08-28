defmodule Playstead.Formats do
  @moduledoc """
  The single entry point for reading untrusted bytes safely and
  bounded (T-02-18, T-02-19). `identify/2` takes the leading bytes and
  the original filename and returns the system identifier, the tier,
  and the evidence map, with archives short-circuiting to a container
  result and everything else falling through to `:unknown` with no
  claim made.

  Every validator invoked here is pure Elixir binary pattern matching
  over at most the first 64 KiB, never raises, and records its tier as
  evidence rather than a verdict.
  """

  alias Playstead.Formats.Archive
  alias Playstead.Formats.Validators.{Gb, Gba, Md, Nes, PsxCue, Snes}

  @max_read 65_536

  @doc """
  Identifies `bytes` (only the leading `max_read` bytes are ever
  consulted) using `filename` only to decide whether the PSX CUE text
  parser is attempted — the resulting system is always determined by
  the bytes, never by the extension. Returns
  `{system_id, tier, evidence}`.
  """
  @spec identify(binary(), String.t() | nil) :: {atom(), atom(), map()}
  def identify(bytes, filename \\ nil)

  def identify(bytes, filename) when is_binary(bytes) do
    bounded = bounded_bytes(bytes)

    case Archive.detect(bounded) do
      {:match, kind} -> {:unknown, :container, %{archive_kind: kind, reason: :archive_not_opened}}
      :no_match -> identify_rom(bounded, filename)
    end
  end

  def identify(_bytes, _filename), do: {:unknown, :none, %{}}

  defp identify_rom(bounded, filename) do
    rom_validators()
    |> Enum.find_value(fn {system, fun} -> match_result(system, fun.(bounded)) end)
    |> case do
      nil -> maybe_psx(bounded, filename)
      result -> result
    end
  end

  defp rom_validators do
    [
      {:gba, &Gba.recognize/1},
      {:gb, &Gb.recognize/1},
      {:nes, &Nes.recognize/1},
      {:md, &Md.recognize/1},
      {:snes, &Snes.recognize/1}
    ]
  end

  defp match_result(:gb, {:match, evidence}),
    do: {gb_system_id(evidence), evidence.tier, evidence}

  defp match_result(system, {:match, evidence}), do: {system, evidence.tier, evidence}
  defp match_result(_system, :no_match), do: nil

  defp gb_system_id(%{system: :gbc_only}), do: :gbc
  defp gb_system_id(_evidence), do: :gb

  defp maybe_psx(bounded, filename) do
    if cue_extension?(filename) do
      case PsxCue.recognize(bounded) do
        {:match, evidence} -> {:psx, evidence.tier, evidence}
        :no_match -> {:unknown, :none, %{}}
      end
    else
      {:unknown, :none, %{}}
    end
  end

  defp cue_extension?(nil), do: false

  defp cue_extension?(filename) do
    String.downcase(filename) |> String.ends_with?(".cue")
  end

  defp bounded_bytes(bytes) do
    size = min(byte_size(bytes), @max_read)
    binary_part(bytes, 0, size)
  end
end
