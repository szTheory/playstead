defmodule Playstead.AvailabilityVocabulary do
  @moduledoc """
  The frozen, six-value console availability filter vocabulary
  (plan 03-13, LIBR-02 gap closure). These are the UI-SPEC's six
  card-eligible ladder states with pinned/verified merged into one
  `ready_offline` value (`03-UI-SPEC.md` "Search and filters"; D-13).
  `safe_to_evict` is deliberately excluded — it is a storage-view
  concept, never a console filter chip.

  `shared/availability-vocabulary.json` is this module's test-fixture
  mirror (the `Playstead.SaveVocabulary` pattern): a JSON file read only
  by `availability_vocabulary_contract_test.exs` to prove the two never
  drift apart. No shipped runtime code path reads that JSON file.

  `valid?/1` is a plain membership test over a frozen list of binaries.
  It must never dynamically convert a client-supplied value into an
  atom (T-03-13-01) — unbounded atom creation from untrusted input
  exhausts the non-garbage-collected atom table.
  """

  @values [
    "needs_attention",
    "missing_dependency",
    "downloading",
    "ready_offline",
    "queued",
    "server_only"
  ]

  @labels %{
    "needs_attention" => "Needs attention",
    "missing_dependency" => "Missing dependency",
    "downloading" => "Downloading",
    "ready_offline" => "Ready offline",
    "queued" => "Queued",
    "server_only" => "On server"
  }

  @accessible_names %{
    "needs_attention" => "Filter by needs attention",
    "missing_dependency" => "Filter by missing dependency",
    "downloading" => "Filter by downloading",
    "ready_offline" => "Filter by ready offline",
    "queued" => "Filter by queued",
    "server_only" => "Filter by on server"
  }

  @doc "The six frozen filter values, in display order."
  @spec values() :: [String.t()]
  def values, do: @values

  @doc "Membership test over the frozen vocabulary — never an atom conversion."
  @spec valid?(term()) :: boolean()
  def valid?(value) when is_binary(value), do: value in @values
  def valid?(_value), do: false

  @doc "The visible chip label for `value`, or `nil` if not in the vocabulary."
  @spec label(String.t()) :: String.t() | nil
  def label(value), do: Map.get(@labels, value)

  @doc "The accessible name (`aria-label`) for `value`, or `nil` if not in the vocabulary."
  @spec accessible_name(String.t()) :: String.t() | nil
  def accessible_name(value), do: Map.get(@accessible_names, value)
end
