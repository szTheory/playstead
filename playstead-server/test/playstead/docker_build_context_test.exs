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
      staged = staged_sources()

      missing =
        Enum.reject(required, fn {_mod, _resource, relative_path} ->
          staged?(relative_path, staged)
        end)

      assert missing == [],
             """
             The following compile-time embedded resources are not staged into the
             Docker builder stage before `RUN mix compile` (or are staged after it).
             Add a `COPY` to the Dockerfile's builder stage, before the `RUN mix
             compile` line, that actually stages each missing resource path (not
             merely its top-level directory):

             #{format_missing(missing)}
             """
    end

    test "the required set is not vacuously empty (pins PlaysteadWeb.RecoveryDocsController's resource)" do
      required = required_resources()

      assert Enum.any?(required, fn {mod, resource, _relative_path} ->
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
    |> Enum.map(fn {mod, resource} -> {mod, resource, relative_path(resource)} end)
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

  defp relative_path(path) do
    path
    |> Path.expand()
    |> String.replace_prefix(@project_root <> "/", "")
  end

  # -- staged set: every source path COPYed into the builder stage before the compile step --

  # WR-06 (01-REVIEW.md): this must be the full relative source path from
  # each `COPY` instruction, not reduced to its top-level path segment.
  # Reducing to the top segment made `COPY docs docs` and (hypothetically)
  # `COPY docs/some-other-file.txt docs/some-other-file.txt` compare equal
  # — both reduce to `"docs"` — even though only the former actually
  # stages `docs/RECOVERY.md`, which `RecoveryDocsController` reads at
  # compile time via `File.read!/1`. `staged?/2` below does a real
  # exact-or-prefix match against the un-reduced path instead.
  defp staged_sources do
    lines = dockerfile_lines()

    compile_line_index =
      Enum.find_index(lines, &(String.trim(&1) == "RUN mix compile"))

    refute_nil!(compile_line_index, "could not find the `RUN mix compile` line in the Dockerfile")

    lines
    |> Enum.take(compile_line_index)
    |> Enum.filter(&copy_instruction?/1)
    |> Enum.reject(&String.contains?(&1, "--from"))
    |> Enum.flat_map(&copy_sources/1)
    |> MapSet.new()
  end

  # A required resource is staged if some `COPY` source is either exactly
  # that path, or a directory whose contents include it (a proper path
  # prefix followed by "/"). This is a real path-prefix check against the
  # actual required resource, not a coarse top-segment comparison.
  defp staged?(resource_relative_path, staged_sources) do
    Enum.any?(staged_sources, fn source ->
      source == resource_relative_path or
        String.starts_with?(resource_relative_path, source <> "/")
    end)
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
    |> Enum.map(fn {mod, resource, relative_path} ->
      "  - #{inspect(mod)} embeds #{resource} (relative path `#{relative_path}`) — " <>
        "not staged before RUN mix compile"
    end)
    |> Enum.join("\n")
  end
end
