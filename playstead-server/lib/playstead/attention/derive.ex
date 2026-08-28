defmodule Playstead.Attention.Derive do
  @moduledoc """
  The single function every call site asks whether an outcome needs a
  human (D-26). The exclusion side matters more than the inclusion
  side: a new asset, an exact duplicate, a clean alias, a clean
  variant, and the very common case of content with no reference
  installed all produce nothing — a first adopter importing hundreds
  of ROMs with no reference pack installed sees a quiet library, not a
  wall of chores.

  `context/0` is a plain map so call sites never need to construct or
  depend on a receipt/schema struct just to ask this question —
  keeping this module pure and directly unit-testable.
  """

  @typedoc """
  * `:outcome` — the receipt outcome code (atom or string, `Playstead.Import.Outcome`)
  * `:reason` — the outcome's reason sub-code, when present
  * `:retries_exhausted?` — for `failed_safely`: whether the bounded retry budget is spent
  * `:system_confirmation_needed?` — extension-vs-header contradiction (D-19)
  * `:unknown_system?` — no system could be assigned at all (not merely unmatched to a reference)
  """
  @type context :: %{optional(atom()) => term()}

  @doc "Whether this outcome context requires a human decision (D-26)."
  @spec needs_attention?(context()) :: boolean()
  def needs_attention?(ctx), do: not is_nil(attention_reason(ctx))

  @doc """
  The `Playstead.Attention.Reason` this context should raise, or `nil`
  when the outcome is a quiet exclusion. Confirm-system and
  unknown-system flags are consulted first since they can co-occur
  with (and take priority as the more specific reason over) a plain
  outcome/reason pair.
  """
  @spec attention_reason(context()) :: atom() | nil
  def attention_reason(%{system_confirmation_needed?: true}), do: :confirm_system
  def attention_reason(%{unknown_system?: true}), do: :unknown_system

  def attention_reason(ctx) when is_map(ctx) do
    outcome = ctx |> Map.get(:outcome) |> to_str()
    reason = ctx |> Map.get(:reason) |> to_str()

    case outcome do
      "incomplete_set" -> :missing_member
      "quarantined" -> :quarantined
      "patched" -> :patch_file_detected
      "failed_safely" -> if ctx[:retries_exhausted?], do: :failed_after_retries
      "unrecognized" -> unrecognized_reason(reason)
      _ -> nil
    end
  end

  defp unrecognized_reason("ambiguous"), do: :ambiguous_recognition
  defp unrecognized_reason("signature_mismatch"), do: :signature_mismatch
  defp unrecognized_reason("archive_not_opened"), do: :archives_kept_unopened
  defp unrecognized_reason(_reason), do: nil

  defp to_str(nil), do: nil
  defp to_str(v) when is_atom(v), do: Atom.to_string(v)
  defp to_str(v), do: v
end
