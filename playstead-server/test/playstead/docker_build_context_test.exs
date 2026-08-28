defmodule Playstead.DockerBuildContextTest do
  @moduledoc """
  Guards against the class of regression that broke OPER-01: a module
  embedding a repository file at compile time (`@external_resource`) that
  the Dockerfile's builder stage never stages into the build context before
  `RUN mix compile` runs — or stages too late to matter. `mix test` alone
  (no Docker daemon required) must catch this the moment a future phase
  adds a new compile-time embed and forgets to stage its directory.
  """

  use ExUnit.Case, async: true

  @project_root File.cwd!()
  @dockerfile_path Path.join(@project_root, "Dockerfile")

  describe "compile-time external resources are staged before mix compile" do
    test "every in-project @external_resource maps to a builder-stage COPY that precedes the compile step" do
      required = required_resources()
      staged = staged_top_segments()

      missing =
        Enum.reject(required, fn {_mod, _resource, segment} ->
          MapSet.member?(staged, segment)
        end)

      assert missing == [],
             """
             The following compile-time embedded resources are not staged into the
             Docker builder stage before `RUN mix compile` (or are staged after it).
             Add `COPY <dir> <dir>` to the Dockerfile's builder stage, before the
             `RUN mix compile` line, for each missing directory:

             #{format_missing(missing)}
             """
    end

    test "the required set is not vacuously empty (pins PlaysteadWeb.RecoveryDocsController's resource)" do
      required = required_resources()

      assert Enum.any?(required, fn {mod, resource, _segment} ->
               mod == PlaysteadWeb.RecoveryDocsController and
                 String.ends_with?(resource, "RECOVERY.md")
             end),
             "Expected PlaysteadWeb.RecoveryDocsController to declare an @external_resource " <>
               "ending in RECOVERY.md; without this pin the generic check above could pass " <>
               "merely because zero external resources were found in the app."
    end
  end

  # -- required set: every in-project @external_resource declared by the app --

  defp required_resources do
    :playstead
    |> Application.spec(:modules)
    |> Enum.flat_map(fn mod ->
      mod
      |> safe_attributes()
      |> Keyword.get_values(:external_resource)
      |> List.flatten()
      |> Enum.map(&{mod, &1})
    end)
    |> Enum.filter(fn {_mod, resource} -> under_project_root?(resource) end)
    |> Enum.map(fn {mod, resource} -> {mod, resource, top_segment(resource)} end)
    |> Enum.uniq()
  end

  defp safe_attributes(mod) do
    mod.__info__(:attributes)
  rescue
    _ -> []
  end

  defp under_project_root?(path) do
    String.starts_with?(Path.expand(path), @project_root <> "/")
  end

  defp top_segment(path) do
    path
    |> Path.expand()
    |> String.replace_prefix(@project_root <> "/", "")
    |> Path.split()
    |> hd()
  end

  # -- staged set: every directory COPYed into the builder stage before the compile step --

  defp staged_top_segments do
    lines = dockerfile_lines()

    compile_line_index =
      Enum.find_index(lines, &(String.trim(&1) == "RUN mix compile"))

    refute_nil!(compile_line_index, "could not find the `RUN mix compile` line in the Dockerfile")

    lines
    |> Enum.take(compile_line_index)
    |> Enum.filter(&copy_instruction?/1)
    |> Enum.reject(&String.contains?(&1, "--from"))
    |> Enum.flat_map(&copy_sources/1)
    |> Enum.map(&(&1 |> Path.split() |> hd()))
    |> MapSet.new()
  end

  defp dockerfile_lines do
    @dockerfile_path
    |> File.read!()
    |> String.split("\n")
  end

  defp copy_instruction?(line) do
    String.starts_with?(String.trim(line), "COPY ")
  end

  defp copy_sources(line) do
    args =
      line
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)
      # drop the leading "COPY" keyword
      |> tl()

    # the final argument is always the destination; everything before it is a source
    case args do
      [] -> []
      [_destination] -> []
      _ -> Enum.slice(args, 0, length(args) - 1)
    end
  end

  defp refute_nil!(nil, message), do: flunk(message)
  defp refute_nil!(_value, _message), do: :ok

  defp format_missing(missing) do
    missing
    |> Enum.map(fn {mod, resource, segment} ->
      "  - #{inspect(mod)} embeds #{resource} (directory `#{segment}`) — not staged before RUN mix compile"
    end)
    |> Enum.join("\n")
  end
end
