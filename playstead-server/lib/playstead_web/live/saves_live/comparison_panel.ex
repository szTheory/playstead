defmodule PlaysteadWeb.SavesLive.ComparisonPanel do
  @moduledoc """
  "Two versions of your progress" — the comparison sheet (D-50 through
  D-55). Exactly four facts per side (origin, last saved, play time
  since the split, saves since the split); the digest lives behind
  "Details" only. Deliberately does not render: file size, byte-diff,
  a similarity score, a revision ordinal, or a parent pointer.

  No side is ever singled out, highlighted, or pre-chosen by this
  code, and there is no confirmation dialog before choosing (D-51) —
  `phx-click` fires the mutation directly, with no `data-confirm`. No
  Undo control exists anywhere on this sheet (D-49): the non-chosen
  side stays a live, permanently choosable "Continue from this one"
  button instead. The only bulk action a divergence surface may ever
  offer is "Keep both" itself; a standing per-device default is
  refused by decision (D-55) and does not exist here.

  Each side is one accessibility element carrying one complete
  comparison sentence (D-55) — every action (choose, keep both,
  export, details) is a plain `<button>`/`<a>`, reachable and
  activatable by keyboard alone, with no gesture-only, hover-only, or
  pointer-only affordance and no colour distinguishing the sides.
  """

  use Phoenix.Component

  attr :sides, :list, required: true
  attr :result_message, :string, default: nil

  def comparison_panel(assigns) do
    ~H"""
    <div id="comparison-panel" data-role="comparison-panel" class="space-y-6">
      <div>
        <h2 id="comparison-title" class="text-heading font-semibold text-[#F1F5F9]">
          Two versions of your progress
        </h2>
        <p id="comparison-subtitle" class="mt-1 text-sm text-[#94A3B8]">
          {subtitle(@sides)}
        </p>
      </div>

      <p
        :if={@result_message}
        id="comparison-result"
        aria-live="polite"
        class="rounded-md border border-[#334155] bg-[#1E293B] p-3 text-sm text-[#F1F5F9]"
      >
        {@result_message}
      </p>

      <div id="comparison-sides" class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div
          :for={side <- @sides}
          id={"side-#{side.id}"}
          data-role="comparison-side"
          role="group"
          aria-label={accessible_sentence(side)}
          class="rounded-lg border border-[#334155] bg-[#1E293B] p-5"
        >
          <h3 id={"side-#{side.id}-heading"} class="text-base font-semibold text-[#F1F5F9]">
            {side.origin}
          </h3>

          <p id={"side-#{side.id}-line1"} class="mt-2 text-sm text-[#94A3B8]">{side.last_saved}</p>
          <p id={"side-#{side.id}-line2"} class="text-sm text-[#94A3B8]">
            No recorded play here since these split
          </p>
          <p id={"side-#{side.id}-line3"} class="text-sm text-[#94A3B8]">
            {saves_since_split_text(side.since_split_count)}
          </p>

          <p
            :if={side.clock_caveat?}
            id={"side-#{side.id}-clock-caveat"}
            class="mt-2 text-sm text-[#94A3B8]"
          >
            {side.origin} reported a time that doesn't line up with when this version reached your server. Times from that Mac may be wrong.
          </p>

          <p
            :if={not side.downloaded?}
            id={"side-#{side.id}-not-downloaded"}
            class="mt-2 text-sm text-[#94A3B8]"
          >
            This isn't downloaded on this Mac. You can still choose and export.
          </p>

          <div class="mt-4 flex flex-wrap gap-2">
            <button
              :if={not side.chosen?}
              type="button"
              id={"choose-#{side.id}"}
              phx-click="choose"
              phx-value-head_id={side.id}
              class="h-9 rounded-md border border-[#334155] px-3 text-sm font-semibold text-[#F1F5F9] hover:border-[#38BDF8]"
            >
              Continue from this one
            </button>

            <p
              :if={side.chosen?}
              id={"chosen-#{side.id}"}
              class="text-sm font-semibold text-[#F1F5F9]"
            >
              Currently continuing from this one
            </p>

            <button
              type="button"
              id={"export-#{side.id}"}
              phx-click="export-version"
              phx-value-head_id={side.id}
              class="h-9 rounded-md border border-[#334155] px-3 text-sm font-semibold text-[#F1F5F9] hover:border-[#38BDF8]"
            >
              Export this version…
            </button>

            <details id={"details-#{side.id}"} class="w-full">
              <summary class="cursor-pointer text-sm text-[#94A3B8] hover:text-[#F1F5F9]">
                Details
              </summary>
              <p
                id={"side-#{side.id}-digest"}
                class="mt-1 break-all font-mono text-label text-[#94A3B8]"
              >
                {side.digest}
              </p>
            </details>
          </div>
        </div>
      </div>

      <div class="border-t border-[#334155] pt-4">
        <button
          type="button"
          id="keep-both"
          phx-click="keep-both"
          class="h-9 rounded-md border border-[#334155] px-3 text-sm font-semibold text-[#F1F5F9] hover:border-[#38BDF8]"
        >
          {keep_both_label(@sides)}
        </button>
        <p class="mt-1 text-sm text-[#94A3B8]">
          Both versions stay in your library. This Mac keeps playing the version it already has.
        </p>
      </div>
    </div>
    """
  end

  defp subtitle(sides) when length(sides) > 2 do
    "all #{length(sides)} versions are safe. Pick the one to continue from, or keep them all."
  end

  defp subtitle(_sides), do: "both versions are safe. Pick the one to continue from, or keep both."

  defp keep_both_label(sides) when length(sides) > 2, do: "Keep them all"
  defp keep_both_label(_sides), do: "Keep both"

  defp saves_since_split_text(1), do: "in 1 save"
  defp saves_since_split_text(n), do: "across #{n} saves"

  defp accessible_sentence(side) do
    "#{side.origin}. #{side.last_saved}. No recorded play here since these split. " <>
      saves_since_split_text(side.since_split_count) <> "."
  end
end
