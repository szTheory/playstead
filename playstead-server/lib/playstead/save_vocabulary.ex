defmodule Playstead.SaveVocabulary do
  @moduledoc """
  The console's partial mirror of the shared save-copy fixture under
  `shared/` (D-67).

  Only the keys the console actually renders -- today, the two
  console-only divergence result variants -- are declared here. That
  fixture is a test resource only, read by `save_copy_contract_test.exs`
  to prove this module and the fixture agree exhaustively, in both
  directions, over this subset. Do not read that fixture from any
  shipped runtime code path.
  """

  @all %{
    "result.console_after_choosing" => "Continuing from {Origin}. Your Macs will use this version the next time they connect.",
    "result.console_after_keeping_both" => "Keeping both. Each Mac keeps playing the version it already has.",
  }

  @doc "key => value, for every save string the console ships today."
  def all, do: @all
end
