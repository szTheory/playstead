defmodule Playstead.DependencyPinTest do
  @moduledoc """
  The automated supply-chain gate for `saxy` (T-02-62). RESEARCH.md's
  Package Legitimacy Audit approved `saxy` 1.6.1 manually — hex.pm is
  outside the automated `npm|pypi|crates` legitimacy-check seam — and
  the project owner's zero-manual-verification preference (this plan's
  scope note) substitutes this automated pinned-version-and-checksum
  assertion for the recommended human checkpoint. If either the pinned
  version or its lockfile checksum ever changes, this test fails loudly
  rather than silently trusting a new resolution.
  """

  use ExUnit.Case, async: true

  @audited_version "1.6.1"
  @audited_outer_checksum "742eff28f553c066d0b54e84662dbf384a1d1f38595472ed15f6e0a33038bbe1"
  @audited_inner_checksum "8989d504424ba29460a61950f8968380651413fa05e63b6118084db057da1a6b"

  test "mix.exs pins saxy to the exact audited version" do
    saxy_dep = Mix.Project.config()[:deps] |> Enum.find(fn dep -> elem(dep, 0) == :saxy end)

    assert saxy_dep != nil, "saxy must be declared in mix.exs deps"
    assert elem(saxy_dep, 1) == "~> 1.6"
  end

  test "mix.lock pins saxy to the exact audited version and checksum" do
    lock = Mix.Dep.Lock.read()
    assert %{saxy: entry} = lock

    assert entry ==
             {:hex, :saxy, @audited_version, @audited_outer_checksum, [:mix], [], "hexpm",
              @audited_inner_checksum},
           "saxy's mix.lock entry no longer matches the audited version/checksum recorded in " <>
             "RESEARCH.md's Package Legitimacy Audit — re-run the manual audit before accepting " <>
             "a new resolution (T-02-62)"
  end
end
