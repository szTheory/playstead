defmodule PlaysteadWeb.AttentionLive.EvidenceCard do
  @moduledoc """
  The evidence a resolution decision needs (D-26): the full hash with
  a copy affordance, the exact size, the format and its magic
  evidence, header fields for validated formats only, the member list
  with missing members highlighted, the source path labelled as a
  client claim, and a plain-language reason. Never describes a user's
  content with the forbidden vocabulary the decision record rules out
  — a file that failed a heuristic check has done nothing wrong.
  """

  use Phoenix.Component

  attr :item, :map, required: true
  attr :selectable, :boolean, default: false
  attr :selected, :boolean, default: false

  def evidence_card(assigns) do
    ~H"""
    <div
      id={"attention-item-#{@item.id}"}
      data-role="evidence-card"
      class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
    >
      <div class="flex items-start gap-4">
        <input
          :if={@selectable}
          type="checkbox"
          id={"select-#{@item.id}"}
          data-role="item-checkbox"
          phx-click="toggle-select"
          phx-value-id={@item.id}
          checked={@selected}
          aria-label="Select this item"
          class="mt-1 size-4"
        />
        <div class="min-w-0 flex-1">
          <p id={"attention-item-#{@item.id}-reason"} class="text-base font-semibold text-[#F1F5F9]">
            {plain_language_reason(@item)}
          </p>

          <dl class="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div :if={@item.evidence["sha256"] || sha256(@item)}>
              <dt class="text-sm font-semibold text-[#94A3B8]">Hash (SHA-256)</dt>
              <dd
                id={"attention-item-#{@item.id}-hash"}
                class="mt-1 break-all font-mono text-label text-[#94A3B8]"
              >
                {sha256(@item)}
                <button
                  type="button"
                  data-role="copy-hash"
                  data-clipboard-text={sha256(@item)}
                  class="ml-2 text-sm font-semibold text-[#94A3B8] hover:text-[#F1F5F9]"
                >
                  Copy
                </button>
              </dd>
            </div>

            <div :if={@item.evidence["size_bytes"]}>
              <dt class="text-sm font-semibold text-[#94A3B8]">Size</dt>
              <dd class="mt-1 text-sm text-[#F1F5F9]">{@item.evidence["size_bytes"]} bytes</dd>
            </div>

            <div :if={@item.evidence["format"]}>
              <dt class="text-sm font-semibold text-[#94A3B8]">Format</dt>
              <dd class="mt-1 text-sm text-[#F1F5F9]">{@item.evidence["format"]}</dd>
            </div>

            <div :if={@item.evidence["extension"] && @item.evidence["header"]}>
              <dt class="text-sm font-semibold text-[#94A3B8]">Readings</dt>
              <dd id={"attention-item-#{@item.id}-confirm-detail"} class="mt-1 text-sm text-[#F1F5F9]">
                Extension says {@item.evidence["extension"]}, header says {@item.evidence["header"]}
              </dd>
            </div>

            <div :if={@item.evidence["header_fields"]}>
              <dt class="text-sm font-semibold text-[#94A3B8]">
                Header fields (signature-validated)
              </dt>
              <dd class="mt-1 text-sm text-[#F1F5F9]">{inspect(@item.evidence["header_fields"])}</dd>
            </div>

            <div :if={@item.evidence["missing_members"]}>
              <dt class="text-sm font-semibold text-[#94A3B8]">Members</dt>
              <dd class="mt-1 text-sm text-[#F1F5F9]">
                <span
                  :for={name <- @item.evidence["missing_members"]}
                  id={"attention-item-#{@item.id}-missing-#{name}"}
                  data-role="missing-member"
                  class="mr-2 rounded bg-[#7F1D1D]/30 px-2 py-0.5 text-[#FCA5A5]"
                >
                  {name} — missing
                </span>
              </dd>
            </div>

            <div :if={@item.evidence["source_path"]}>
              <dt class="text-sm font-semibold text-[#94A3B8]">
                Source path (as reported by the client)
              </dt>
              <dd class="mt-1 break-all text-sm text-[#94A3B8]">{@item.evidence["source_path"]}</dd>
            </div>
          </dl>

          <details class="mt-4">
            <summary class="cursor-pointer text-sm text-[#94A3B8]">Expert detail</summary>
            <pre class="mt-2 whitespace-pre-wrap break-all font-mono text-label text-[#94A3B8]">{inspect(@item.evidence)}</pre>
          </details>
        </div>
      </div>
    </div>
    """
  end

  defp sha256(%{blob_id: nil}), do: nil
  defp sha256(item), do: item.evidence["sha256"] || item.blob_id

  # D-26: never illegal, bad, corrupt-as-verdict, disposable, or infected.
  defp plain_language_reason(%{reason: "missing_member"}),
    do: "Some parts are missing — this game needs more than one file."

  defp plain_language_reason(%{reason: "quarantined"}),
    do: "Set aside for review before it's processed further."

  defp plain_language_reason(%{reason: "patch_file_detected"}),
    do: "Looks like a patch file, kept as-is."

  defp plain_language_reason(%{reason: "failed_after_retries"}),
    do: "Couldn't finish after a few tries — nothing was changed."

  defp plain_language_reason(%{reason: "ambiguous_recognition"}),
    do: "More than one possible match — a person's judgment is needed."

  defp plain_language_reason(%{reason: "signature_mismatch"}),
    do: "The name and the bytes don't agree on what this is."

  defp plain_language_reason(%{reason: "unknown_system"}),
    do: "Playstead couldn't tell which system this is for."

  defp plain_language_reason(%{reason: "confirm_system"}),
    do: "The file name and its contents suggest different systems."

  defp plain_language_reason(%{reason: "archives_kept_unopened", count: count}) when count > 1,
    do:
      "#{count} archives were kept exactly as they are. They can't be played until archive support ships — extracting them first makes them playable."

  defp plain_language_reason(%{reason: "archives_kept_unopened"}),
    do:
      "An archive was kept exactly as it is. It can't be played until archive support ships — extracting it first makes it playable."

  defp plain_language_reason(_item), do: "Needs a decision."
end
