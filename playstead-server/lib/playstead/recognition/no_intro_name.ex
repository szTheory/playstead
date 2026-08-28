defmodule Playstead.Recognition.NoIntroName do
  @moduledoc """
  Parses the standard No-Intro release-naming convention —
  `Title (Region) (Languages) (Version) (Devstatus) (Additional) [Status]`
  — into a title plus the documented tag groups (D-22). Follows the
  same never-raises tagged-tuple contract as the format validators.
  Grammar coverage beyond the documented tag groups is at the
  implementer's discretion (02-CONTEXT.md, Claude's Discretion).
  """

  @paren_regex ~r/\(([^()]*)\)/
  @bracket_regex ~r/\[([^\[\]]*)\]/

  @regions ~w(USA Europe Japan World Australia Canada China Korea Netherlands
              Spain France Germany Italy Brazil Sweden Asia UK)

  @dev_statuses ~w(Beta Proto Prototype Demo Sample Alpha Unl Unlicensed)

  @doc """
  Parses `filename` (its extension is stripped first). Returns
  `{:ok, %{title: title, tags: tags}}` when at least one parenthesized
  tag is present, or `:no_match` for anything else — including
  filenames with no tag groups at all. Never raises.
  """
  @spec parse(String.t()) :: {:ok, map()} | :no_match
  def parse(filename) when is_binary(filename) do
    base = filename |> Path.basename() |> Path.rootname()

    parens = @paren_regex |> Regex.scan(base) |> Enum.map(fn [_, inner] -> String.trim(inner) end)

    brackets =
      @bracket_regex |> Regex.scan(base) |> Enum.map(fn [_, inner] -> String.trim(inner) end)

    title =
      base
      |> String.replace(@paren_regex, "")
      |> String.replace(@bracket_regex, "")
      |> String.trim()

    if title != "" and parens != [] do
      {:ok, %{title: title, tags: classify(parens, brackets)}}
    else
      :no_match
    end
  rescue
    _ -> :no_match
  end

  def parse(_filename), do: :no_match

  defp classify(parens, brackets) do
    region = Enum.find(parens, &(&1 in @regions))
    dev_status = Enum.find(parens, &(&1 in @dev_statuses))
    version = Enum.find(parens, &version_tag?/1)
    languages = Enum.find(parens, &language_tag?/1)

    additional =
      parens
      |> Enum.reject(&(&1 == region or &1 == dev_status or &1 == version or &1 == languages))

    %{
      region: region,
      languages: languages,
      version: version,
      dev_status: dev_status,
      additional: additional,
      status: brackets
    }
  end

  defp version_tag?(tag), do: Regex.match?(~r/^(v[\d.]+|Rev\s*[\dA-Za-z]+)$/i, tag)

  defp language_tag?(tag) do
    Regex.match?(~r/^[A-Z][a-z]?(,[A-Z][a-z]?)*$/, tag)
  end
end
