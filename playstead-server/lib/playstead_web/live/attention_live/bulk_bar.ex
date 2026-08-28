defmodule PlaysteadWeb.AttentionLive.BulkBar do
  @moduledoc """
  The labelled bulk toolbar (D-31). Offered only for resolutions that
  need no per-item input — excluding, retaining as custom, retrying,
  and assigning a system to the selected group. Correcting an
  individual title and attaching a specific companion stay per-item,
  since they need input that differs per row.
  """

  use Phoenix.Component

  attr :selected_count, :integer, required: true

  def bulk_bar(assigns) do
    ~H"""
    <div
      :if={@selected_count > 0}
      id="bulk-toolbar"
      role="toolbar"
      aria-label="Bulk actions"
      class="sticky top-0 z-10 flex flex-wrap items-center gap-3 rounded-lg border border-[#334155] bg-[#0F172A] p-4"
    >
      <span id="bulk-selected-count" class="text-sm text-[#F1F5F9]">
        {@selected_count} selected
      </span>

      <button
        type="button"
        id="bulk-exclude"
        phx-click="bulk-exclude"
        data-confirm={"Exclude #{@selected_count} items? Their bytes stay in your library and are restorable from the excluded filter."}
        class="h-9 rounded-md border border-[#EF4444] px-3 text-sm font-semibold text-[#EF4444] hover:bg-[#EF4444]/10"
      >
        Exclude
      </button>

      <button
        type="button"
        id="bulk-retain"
        phx-click="bulk-retain"
        data-confirm={"Retain #{@selected_count} items as custom content?"}
        class="h-9 rounded-md border border-[#334155] px-3 text-sm font-semibold text-[#F1F5F9] hover:border-[#38BDF8]"
      >
        Retain as custom
      </button>

      <button
        type="button"
        id="bulk-retry"
        phx-click="bulk-retry"
        data-confirm={"Retry safe processing for #{@selected_count} items?"}
        class="h-9 rounded-md border border-[#334155] px-3 text-sm font-semibold text-[#F1F5F9] hover:border-[#38BDF8]"
      >
        Retry
      </button>

      <form phx-submit="bulk-assign-system" class="flex items-center gap-2">
        <label for="bulk-assign-system-select" class="text-sm text-[#94A3B8]">Assign system</label>
        <select
          id="bulk-assign-system-select"
          name="system_id"
          class="h-9 rounded-md bg-[#1E293B] text-sm text-[#F1F5F9]"
        >
          <option value="gba">GBA</option>
          <option value="gb">GB</option>
          <option value="gbc">GBC</option>
          <option value="nes">NES</option>
          <option value="snes">SNES</option>
          <option value="md">Mega Drive</option>
          <option value="psx">PSX</option>
        </select>
        <button
          type="submit"
          id="bulk-assign-system"
          data-confirm={"Assign this system to #{@selected_count} items?"}
          class="h-9 rounded-md bg-[#38BDF8] px-3 text-sm font-semibold text-[#0F172A] hover:opacity-90"
        >
          Apply
        </button>
      </form>
    </div>
    """
  end
end
