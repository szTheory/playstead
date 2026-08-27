defmodule PlaysteadWeb.ErrorCodes do
  @moduledoc """
  Stable machine-code registry for RFC 9457 problem+json responses
  (D-22). Codes are the contract; clients key microcopy off `code`
  only. Titles are English strings for humans and may change without
  notice — they are never load-bearing.

  Seeded with the codes named in D-22 and D-11 that this phase uses
  across all plans.
  """

  @registry %{
    capability_incompatible: {422, "Capability Incompatible"},
    idempotency_key_missing: {422, "Idempotency Key Missing"},
    idempotency_key_conflict: {409, "Idempotency Key Conflict"},
    idempotency_key_mismatch: {422, "Idempotency Key Mismatch"},
    invalid_command_id: {422, "Invalid Command Id"},
    cursor_expired: {410, "Cursor Expired"},
    device_revoked: {401, "Device Revoked"},
    pairing_request_expired: {410, "Pairing Request Expired"},
    pairing_request_already_redeemed: {409, "Pairing Request Already Redeemed"},
    pairing_request_not_approved: {409, "Pairing Request Not Approved"},
    slow_down: {429, "Slow Down"},
    unauthorized: {401, "Unauthorized"},
    not_found: {404, "Not Found"},
    rate_limited: {429, "Rate Limited"},
    internal_error: {500, "Internal Server Error"},
    validation_failed: {422, "Validation Failed"}
  }

  @doc "The full code-to-{status, title} mapping."
  @spec registry() :: %{atom() => {pos_integer(), String.t()}}
  def registry, do: @registry

  @doc "The default HTTP status for a known code. Falls back to 500 for unknown codes."
  @spec status_for(atom()) :: pos_integer()
  def status_for(code) do
    case Map.get(@registry, code) do
      {status, _title} -> status
      nil -> 500
    end
  end

  @doc "The human-readable title for a known code. Falls back to a generic title."
  @spec title_for(atom()) :: String.t()
  def title_for(code) do
    case Map.get(@registry, code) do
      {_status, title} -> title
      nil -> "Error"
    end
  end
end
