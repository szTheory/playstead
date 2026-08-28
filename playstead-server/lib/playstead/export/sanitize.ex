defmodule Playstead.Export.Sanitize do
  @moduledoc """
  The single filename and path-component sanitizer every export
  filesystem write goes through (D-33, D-34, RESEARCH Pitfall 5).
  Exported member filenames descend from client-supplied original
  names — a path built from one without passing through here is a
  path-traversal primitive.

  `component/1` follows `Playstead.CommandId`'s never-raises
  tagged-tuple contract and never returns a value containing a parent
  directory segment, a path separator, an absolute or drive-letter
  prefix, a NUL byte, or a control character. `safe_join/2` is the
  second, independent check: it expands the joined path and confirms
  the result still resolves inside the given root before returning it.

  `component/1` is idempotent (sanitizing an already-sanitized name
  returns it unchanged) and always returns a name bounded to a
  conventional filesystem's byte limit.
  """

  @max_component_bytes 255
  @control_chars Enum.to_list(0..31) ++ [127]
  @reserved_saves_name "saves"

  @doc """
  Rewrites `name` into a single, safe path component. Never raises,
  never fails — an unsafe name is rewritten rather than rejected, and
  the exact same rewrite applied twice yields the same result
  (idempotent). Returns `{sanitized, changed?}`, where `changed?` is
  `true` whenever the output differs from `name`.
  """
  @spec component(term()) :: {String.t(), boolean()}
  def component(name) when is_binary(name) do
    cleaned =
      name
      |> String.normalize(:nfc)
      |> strip_control_and_nul()
      |> strip_separators()
      |> strip_drive_prefix()
      |> collapse_parent_segments()
      |> bound_bytes()
      |> fallback_if_empty()

    {cleaned, cleaned != name}
  end

  def component(_name), do: {"unnamed", true}

  @doc """
  Whether `name` is already exactly its own sanitized form — i.e.
  `component/1` would report no change. Used where a caller needs a
  strict yes/no rather than the rewritten value.
  """
  @spec safe?(term()) :: boolean()
  def safe?(name) when is_binary(name) do
    case component(name) do
      {^name, false} -> true
      _ -> false
    end
  end

  def safe?(_name), do: false

  @doc """
  A normalized, case-folded key for collision comparison — two names
  that differ only in Unicode normalization form or case share this
  key, which is exactly the notion of "same name" a case-insensitive
  filesystem enforces.
  """
  @spec collision_key(String.t()) :: String.t()
  def collision_key(name) when is_binary(name) do
    name |> String.normalize(:nfc) |> String.downcase()
  end

  @doc "Whether `name`'s collision key matches the reserved `saves` folder name."
  @spec reserved_saves_name?(String.t()) :: boolean()
  def reserved_saves_name?(name) when is_binary(name) do
    collision_key(name) == @reserved_saves_name
  end

  @doc """
  Joins `root` with `relative` (a forward-slash path built only from
  names already passed through `component/1`) and confirms the
  expanded result still resolves inside `root`. This is the second,
  independent check — `component/1` alone does not prove the
  resulting path stays inside a given root.
  """
  @spec safe_join(String.t(), String.t()) :: {:ok, String.t()} | :error
  def safe_join(root, relative) when is_binary(root) and is_binary(relative) do
    root_expanded = Path.expand(root)
    full = Path.expand(Path.join(root, relative))

    if full == root_expanded or String.starts_with?(full, root_expanded <> "/") do
      {:ok, full}
    else
      :error
    end
  end

  defp strip_control_and_nul(name) do
    name
    |> String.to_charlist()
    |> Enum.reject(fn c -> c in @control_chars end)
    |> List.to_string()
  end

  defp strip_separators(name) do
    name
    |> String.replace("/", "_")
    |> String.replace("\\", "_")
  end

  defp strip_drive_prefix(name) do
    if Regex.match?(~r/^[A-Za-z]:/, name) do
      String.replace(name, ~r/^[A-Za-z]:/, "_")
    else
      name
    end
  end

  defp collapse_parent_segments(""), do: ""
  defp collapse_parent_segments("."), do: "_"
  defp collapse_parent_segments(".."), do: "__"
  defp collapse_parent_segments(name), do: String.replace(name, "..", "_")

  defp bound_bytes(name) do
    if byte_size(name) > @max_component_bytes do
      name |> binary_part(0, @max_component_bytes) |> trim_to_valid_utf8()
    else
      name
    end
  end

  defp trim_to_valid_utf8(bin) do
    if String.valid?(bin) do
      bin
    else
      trim_to_valid_utf8(binary_part(bin, 0, byte_size(bin) - 1))
    end
  end

  defp fallback_if_empty(""), do: "unnamed"
  defp fallback_if_empty(name), do: name
end
