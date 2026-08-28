defmodule Playstead.Attention.Reason do
  @moduledoc """
  The frozen inclusion-reason vocabulary for `Playstead.Attention.Item`
  (D-26). Copies `Playstead.Sync.EntityKind`'s shape exactly. These
  nine reasons are the whole "in" side of the decision record's
  inclusion rule — everything else (a new asset, an exact duplicate, a
  clean alias, a clean variant, content with no reference installed)
  never raises an item at all.
  """

  @reasons ~w(
    missing_member
    quarantined
    patch_file_detected
    failed_after_retries
    ambiguous_recognition
    signature_mismatch
    unknown_system
    confirm_system
    archives_kept_unopened
  )a

  @doc "The full, frozen set of attention reasons."
  @spec all() :: [atom()]
  def all, do: @reasons

  @doc "Whether `reason` (an atom or its string form) is a registered attention reason."
  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(reason) when reason in @reasons, do: true

  def valid?(reason) when is_binary(reason) do
    reason in Enum.map(@reasons, &to_string/1)
  end

  def valid?(_reason), do: false
end
