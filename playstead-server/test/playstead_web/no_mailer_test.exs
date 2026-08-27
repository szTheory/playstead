defmodule PlaysteadWeb.NoMailerTest do
  @moduledoc """
  Standing regression guard for D-02: no code path anywhere in this
  application sends or attempts to send email. Every generated
  magic-link/email-confirmation/email-reset flow was deleted outright in
  plan 01-02, not left dormant.

  Full-line `#` comments are filtered out before matching so that
  documentation prose explaining the no-email posture (which necessarily
  discusses the removed magic-link concept) cannot satisfy or invalidate
  this check by accident — this test only cares about reachable code
  identifiers: an actual `deliver_*` call, or a reference to the `Swoosh`
  or `Mailer` modules.
  """

  use ExUnit.Case, async: true

  @app_root Path.expand("../..", __DIR__)
  @scanned_dirs ["lib"]
  @forbidden_patterns [
    ~r/Swoosh/,
    ~r/\bMailer\b/,
    ~r/\bdeliver_/
  ]

  test "no reachable deliver_*/Swoosh/Mailer code path exists in lib/" do
    violations =
      for dir <- @scanned_dirs,
          path <- source_files(Path.join(@app_root, dir)),
          {line, line_no} <- non_comment_lines(path),
          pattern <- @forbidden_patterns,
          Regex.match?(pattern, line) do
        "#{Path.relative_to(path, @app_root)}:#{line_no}: #{String.trim(line)}"
      end

    assert violations == [],
           "Found mailer-related code references outside comments:\n" <>
             Enum.join(violations, "\n")
  end

  test "the router declares no confirm/magic route path" do
    router_path = Path.join([@app_root, "lib", "playstead_web", "router.ex"])
    content = File.read!(router_path)

    route_lines =
      content
      |> String.split("\n")
      |> Enum.reject(fn line -> String.trim(line) =~ ~r/^#/ end)
      |> Enum.filter(fn line -> line =~ ~r/^\s*(get|post|put|patch|delete|live)\s+"/ end)

    assert Enum.all?(route_lines, fn line -> not (line =~ ~r/confirm|magic/i) end),
           "Found a confirm/magic route path:\n" <> Enum.join(route_lines, "\n")
  end

  defp source_files(dir) do
    Path.wildcard(Path.join(dir, "**/*.{ex,heex}"))
  end

  defp non_comment_lines(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reject(fn {line, _no} -> String.trim(line) =~ ~r/^#/ end)
  end
end
