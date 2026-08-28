defmodule PlaysteadWeb.LibraryLive.AssetDetail do
  @moduledoc """
  The IMPT-02 evidence card (D-13, D-22, D-26): the full SHA-256 with a
  copy affordance, the exact byte size, the format and its magic
  evidence (header fields only for a signature-validated match), the
  ordered member list with any missing member visibly marked, and the
  source provenance — explicitly labelled as a claim made by the
  submitting client, since a client-supplied path is exactly that.

  Every string here describes evidence, not a verdict on the user's
  content — D-26's forbidden-vocabulary rule for describing user
  content is observed throughout (see `copy_contract_test.exs`).
  """

  use Phoenix.Component
  alias Phoenix.LiveView.JS

  attr :detail, :map, required: true

  def asset_detail(assigns) do
    assigns =
      assigns
      |> assign(:members, Enum.sort_by(assigns.detail.asset_set.asset_members, & &1.ordinal))
      |> assign(:asset_set, assigns.detail.asset_set)
      |> assign(:receipts, assigns.detail.receipts)
      |> assign(:evidence_by_blob, assigns.detail.evidence_by_blob)

    ~H"""
    <div id={"asset-detail-#{@asset_set.id}"} class="space-y-6">
      <div class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
        <h1 id="asset-detail-title" class="text-display font-semibold text-[#F1F5F9]">
          {@asset_set.display_title}
        </h1>
        <p class="mt-1 text-sm text-[#94A3B8]">
          {@asset_set.system_id || "Unknown system"}
          <span
            :if={@detail.identification_state == :unidentified}
            id="asset-detail-unidentified-badge"
            class="ml-2"
          >
            Not yet identified
          </span>
        </p>
      </div>

      <div class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
        <h2 class="text-base font-semibold text-[#F1F5F9]">Members</h2>

        <div
          :for={member <- @members}
          id={"member-#{member.id}"}
          class="mt-4 border-t border-[#334155] pt-4 first:mt-0 first:border-0 first:pt-0"
        >
          <p class="text-sm font-semibold text-[#F1F5F9]">
            {member.declared_name}
            <span
              :if={is_nil(member.blob_id)}
              id={"member-#{member.id}-missing"}
              class="ml-2 text-sm font-semibold text-[#FBBF24]"
            >
              Missing
            </span>
          </p>

          <div :if={member.blob} class="mt-2 space-y-2">
            <div>
              <dt class="text-sm text-[#94A3B8]">SHA-256</dt>
              <dd class="flex items-center gap-2">
                <code
                  id={"member-#{member.id}-sha256"}
                  class="break-all font-mono text-sm text-[#F1F5F9]"
                >
                  {member.blob.sha256}
                </code>
                <button
                  id={"member-#{member.id}-copy-sha256"}
                  type="button"
                  phx-click={JS.dispatch("phx:clipboard-copy", detail: %{text: member.blob.sha256})}
                  class="text-sm text-[#F1F5F9] hover:underline"
                >
                  Copy
                </button>
              </dd>
            </div>
            <div>
              <dt class="text-sm text-[#94A3B8]">Size</dt>
              <dd id={"member-#{member.id}-size"} class="text-sm text-[#F1F5F9]">
                {member.blob.size_bytes} bytes
              </dd>
            </div>

            <.format_evidence
              evidence={Map.get(@evidence_by_blob, member.blob_id)}
              member_id={member.id}
            />
          </div>
        </div>
      </div>

      <div :if={@receipts != []} class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
        <h2 class="text-base font-semibold text-[#F1F5F9]">Provenance</h2>
        <p id="asset-detail-provenance" class="mt-2 text-sm text-[#94A3B8]">
          Reported by the submitting client: {provenance_text(List.first(@receipts))}
        </p>
      </div>

      <div :if={@receipts != []} class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
        <h2 class="text-base font-semibold text-[#F1F5F9]">Import receipts</h2>

        <div
          :for={receipt <- @receipts}
          id={"asset-detail-receipt-#{receipt.id}"}
          class="mt-3 text-sm text-[#94A3B8]"
        >
          At import: {receipt.outcome}
          <span :if={current_state_differs?(receipt, @detail.identification_state)}>
            · now: {current_state_label(@detail.identification_state)}
          </span>
        </div>
      </div>
    </div>
    """
  end

  attr :evidence, :any, default: nil
  attr :member_id, :any, required: true

  defp format_evidence(%{evidence: nil} = assigns) do
    ~H"""
    """
  end

  defp format_evidence(assigns) do
    ~H"""
    <div id={"member-#{@member_id}-evidence"}>
      <dt class="text-sm text-[#94A3B8]">Format evidence</dt>
      <dd class="text-sm text-[#F1F5F9]">
        {@evidence.status}
      </dd>

      <div
        :if={signature_validated?(@evidence)}
        id={"member-#{@member_id}-header-fields"}
        class="mt-1"
      >
        <p :for={{key, value} <- header_fields(@evidence)} class="text-sm text-[#94A3B8]">
          {key}: {value}
        </p>
      </div>
    </div>
    """
  end

  defp signature_validated?(%{evidence: %{"tier" => "signature"}}), do: true
  defp signature_validated?(_evidence), do: false

  defp header_fields(%{evidence: evidence}) when is_map(evidence) do
    evidence |> Map.drop(["tier"]) |> Enum.sort()
  end

  defp header_fields(_evidence), do: []

  defp provenance_text(nil), do: "unknown"

  defp provenance_text(%{source_file: %{original_name: name, origin: origin}}) do
    "#{name} (#{origin})"
  end

  defp current_state_differs?(receipt, identification_state) do
    current_state_label(identification_state) != receipt.outcome
  end

  defp current_state_label(:identified), do: "recognized"
  defp current_state_label(:unidentified), do: "unrecognized"
end
