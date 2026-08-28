defmodule Playstead.Import.Outcome do
  @moduledoc """
  The nine frozen outcome codes every `Playstead.Import.Receipt` carries
  exactly one of (D-25). Copies `Playstead.Sync.EntityKind`'s shape
  exactly. These codes are published protocol and additive only — tests
  assert codes, never English strings.
  """

  @codes ~w(
    new_asset
    exact_duplicate
    alias
    variant
    incomplete_set
    unrecognized
    patched
    quarantined
    failed_safely
  )a

  @doc "The full, frozen set of outcome codes."
  @spec all() :: [atom()]
  def all, do: @codes

  @doc "Whether `code` (an atom or its string form) is a registered outcome code."
  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(code) when code in @codes, do: true

  def valid?(code) when is_binary(code) do
    code in Enum.map(@codes, &to_string/1)
  end

  def valid?(_code), do: false
end

defmodule Playstead.Import.Outcome.UnrecognizedReason do
  @moduledoc "The reason sub-vocabulary for the `unrecognized` outcome (D-25)."

  @reasons ~w(no_reference_installed no_match ambiguous archive_not_opened signature_mismatch)a

  @spec all() :: [atom()]
  def all, do: @reasons

  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(reason) when reason in @reasons, do: true
  def valid?(reason) when is_binary(reason), do: reason in Enum.map(@reasons, &to_string/1)
  def valid?(_reason), do: false
end

defmodule Playstead.Import.Outcome.QuarantineReason do
  @moduledoc "The reason sub-vocabulary for the `quarantined` outcome (D-25)."

  @reasons ~w(size_over_cap name_policy_violation scanner_flagged)a

  @spec all() :: [atom()]
  def all, do: @reasons

  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(reason) when reason in @reasons, do: true
  def valid?(reason) when is_binary(reason), do: reason in Enum.map(@reasons, &to_string/1)
  def valid?(_reason), do: false
end

defmodule Playstead.Import.Outcome.FailureReason do
  @moduledoc "The reason sub-vocabulary for the `failed_safely` outcome (D-25)."

  @reasons ~w(io_error disk_full hash_mismatch interrupted worker_crashed)a

  @spec all() :: [atom()]
  def all, do: @reasons

  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(reason) when reason in @reasons, do: true
  def valid?(reason) when is_binary(reason), do: reason in Enum.map(@reasons, &to_string/1)
  def valid?(_reason), do: false
end
