defmodule Playstead.Export.PathSanitizer do
  @moduledoc """
  The one sanitizer every path component reaching a filesystem call in
  the export writer passes through (RESEARCH Pitfall 5, D-33). Exported
  member filenames descend from client-supplied original names, so any
  `Path.join` that skips this is a path-traversal primitive. Follows
  `Playstead.CommandId`'s never-raises tagged-tuple contract.

  Rejects a parent-directory segment, an absolute path, any path
  separator inside a single component, a NUL byte, and any control
  character. This function alone does not prove the *resulting* path
  stays inside a given root — callers additionally call
  `resolve_under_root/2` before opening any file.
  """

  @doc "Sanitizes one path component (never a multi-segment path)."
  @spec sanitize(term()) :: {:ok, String.t()} | :error
  def sanitize(name) when is_binary(name) do
    cond do
      name == "" -> :error
      String.contains?(name, "..") -> :error
      String.starts_with?(name, "/") -> :error
      String.contains?(name, "/") -> :error
      String.contains?(name, "\\") -> :error
      String.contains?(name, <<0>>) -> :error
      has_control_char?(name) -> :error
      true -> {:ok, name}
    end
  end

  def sanitize(_name), do: :error

  @doc """
  Expands `relative` under `root` and confirms the result is still
  inside `root`. Called after `sanitize/1` — the second, independent
  check RESEARCH Pitfall 5 calls for.
  """
  @spec resolve_under_root(String.t(), String.t()) :: {:ok, String.t()} | :error
  def resolve_under_root(root, relative) when is_binary(root) and is_binary(relative) do
    root_expanded = Path.expand(root)
    full = Path.expand(Path.join(root, relative))

    if full == root_expanded or String.starts_with?(full, root_expanded <> "/") do
      {:ok, full}
    else
      :error
    end
  end

  defp has_control_char?(name) do
    name
    |> String.to_charlist()
    |> Enum.any?(fn c -> c < 0x20 or c == 0x7F end)
  end
end
