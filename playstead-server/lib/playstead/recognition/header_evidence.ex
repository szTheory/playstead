defmodule Playstead.Recognition.HeaderEvidence do
  @moduledoc """
  The built-in recognition provider that needs no reference data at
  all (D-16). Assembles evidence from what is already known: the
  format validation result and its tier, header fields the validators
  reported, and pre-computed alias/variant signals from
  `Playstead.Recognition`. Its status when nothing more can be said is
  `:no_reference_installed` — an ordinary quiet library state (D-16,
  D-26), never a failure.

  Implements the three frozen relationship definitions exactly as
  D-17 states them and no more strongly: **alias** (same bytes, a
  different name, already in this library), **possible variant**
  (different bytes, a header serial/game-code match — never claimed
  as certain without a reference), and **patched** (a patch file
  detected by its own leading signature, stored with the patch role
  and never applied to anything).
  """

  @behaviour Playstead.Recognition.Provider

  # IPS/UPS/BPS patch magic (D-17): a patch file is recognized by its
  # own leading signature and is never applied to a ROM.
  @patch_signatures [{"PATCH", :ips}, {"UPS1", :ups}, {"BPS1", :bps}]

  @impl true
  def name, do: "header_evidence"

  @impl true
  def version, do: "1"

  @doc """
  `facts` may carry `:bytes` (the leading bytes, for patch-signature
  detection), `:alias?` (precomputed: does this user already hold
  these bytes under another name), and `:variant_match` (precomputed:
  the header key — serial or game code — this file shares with
  another, differently-hashed blob on the same system, or `nil`).
  """
  @impl true
  def recognize(facts, format_evidence) do
    case detect_patch(facts[:bytes]) do
      {:match, kind} -> patch_result(kind)
      :no_match -> header_result(facts, format_evidence)
    end
  end

  defp detect_patch(nil), do: :no_match

  defp detect_patch(bytes) when is_binary(bytes) do
    Enum.find_value(@patch_signatures, :no_match, fn {signature, kind} ->
      size = byte_size(signature)

      if byte_size(bytes) >= size and binary_part(bytes, 0, size) == signature do
        {:match, kind}
      end
    end)
  rescue
    _ -> :no_match
  end

  defp detect_patch(_bytes), do: :no_match

  defp patch_result(kind) do
    %{status: :patched, confidence: :header, reference_name: nil, evidence: %{patch_kind: kind}}
  end

  defp header_result(facts, format_evidence) do
    cond do
      facts[:alias?] ->
        %{
          status: :alias,
          confidence: :exact,
          reference_name: nil,
          evidence: format_map(format_evidence)
        }

      facts[:variant_match] ->
        %{
          status: :possible_variant,
          confidence: header_confidence(format_evidence),
          reference_name: nil,
          evidence: Map.put(format_map(format_evidence), :matched_on, facts[:variant_match])
        }

      true ->
        %{
          status: :no_reference_installed,
          confidence: header_confidence(format_evidence),
          reference_name: nil,
          evidence: format_map(format_evidence)
        }
    end
  end

  defp format_map({_system, _tier, evidence}) when is_map(evidence), do: evidence
  defp format_map(_format_evidence), do: %{}

  defp header_confidence({_system, :signature, _evidence}), do: :header
  defp header_confidence({_system, :structure, _evidence}), do: :header
  defp header_confidence(_format_evidence), do: :filename
end
