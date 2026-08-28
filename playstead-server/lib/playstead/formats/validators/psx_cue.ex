defmodule Playstead.Formats.Validators.PsxCue do
  @moduledoc """
  Tier B (structure-validated) PlayStation CUE descriptor parsing
  (D-14, D-15, D-21). Parses the descriptor as text under hard caps —
  at most 64 KiB, at most 99 `FILE`/`TRACK` entries, `BINARY` file type
  only, and referenced names that are bare relative names with no
  parent-directory segment, no path separator, no absolute or
  drive-letter path, and no control character. Never raises for any
  input, including non-UTF-8 bytes.
  """

  @max_bytes 65_536
  @max_entries 99

  @file_line_regex ~r/^\s*FILE\s+"([^"]*)"\s+(\S+)\s*$/i
  @track_line_regex ~r/^\s*TRACK\s+/i

  @doc """
  Recognizes a CUE descriptor, or returns `:no_match` for anything
  else — including input above the size cap, non-text bytes, a
  descriptor with too many entries, a non-`BINARY` file type, or an
  unsafe referenced name. Never raises.
  """
  @spec recognize(binary()) :: {:match, map()} | :no_match
  def recognize(binary) when is_binary(binary) do
    if byte_size(binary) <= @max_bytes and String.valid?(binary) do
      parse(binary)
    else
      :no_match
    end
  rescue
    _ -> :no_match
  end

  def recognize(_binary), do: :no_match

  defp parse(text) do
    lines = String.split(text, ["\r\n", "\n"], trim: true)
    file_lines = Enum.filter(lines, &String.match?(&1, ~r/^\s*FILE\s+/i))
    track_lines = Enum.filter(lines, &String.match?(&1, @track_line_regex))

    cond do
      file_lines == [] -> :no_match
      length(file_lines) + length(track_lines) > @max_entries -> :no_match
      true -> parse_files(file_lines, track_lines)
    end
  end

  defp parse_files(file_lines, track_lines) do
    entries = Enum.map(file_lines, &parse_file_line/1)

    if Enum.any?(entries, &(&1 == :error)) do
      :no_match
    else
      {:match,
       %{tier: :structure, files: Enum.map(entries, & &1.name), track_count: length(track_lines)}}
    end
  end

  defp parse_file_line(line) do
    case Regex.run(@file_line_regex, line) do
      [_, name, type] ->
        if String.upcase(type) == "BINARY" and safe_relative_name?(name) do
          %{name: name}
        else
          :error
        end

      _no_match ->
        :error
    end
  end

  defp safe_relative_name?(name) do
    trimmed = String.trim(name)

    trimmed != "" and
      not String.contains?(name, "..") and
      not String.contains?(name, "/") and
      not String.contains?(name, "\\") and
      not String.starts_with?(name, "/") and
      not Regex.match?(~r/^[A-Za-z]:/, name) and
      not Regex.match?(~r/[\x00-\x1F]/, name)
  end
end
