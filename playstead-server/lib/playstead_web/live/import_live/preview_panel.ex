defmodule PlaysteadWeb.ImportLive.PreviewPanel do
  @moduledoc """
  The IMPT-01 pre-copy preview panel (D-04, D-32): everything a user
  can be told before a single byte moves, and nothing more. States the
  managed-copy promise and the untouched-original guarantee in the
  primary action's own supporting text — never elsewhere phrased as a
  move, a relocation, or a cleanup.
  """

  use Phoenix.Component

  alias Playstead.Import.Preview

  attr :preview, Preview, required: true
  attr :entry, :any, required: true
  attr :confirming, :boolean, default: false

  def preview_panel(assigns) do
    ~H"""
    <div id={"preview-#{@entry.ref}"} class="rounded-lg border border-[#334155] bg-[#0F172A] p-4">
      <p id={"preview-#{@entry.ref}-name"} class="text-base font-semibold text-[#F1F5F9]">
        {@preview.name}
      </p>

      <dl class="mt-3 grid grid-cols-2 gap-3 sm:grid-cols-3">
        <div>
          <dt class="text-sm text-[#94A3B8]">Size</dt>
          <dd id={"preview-#{@entry.ref}-size"} class="text-sm text-[#F1F5F9]">
            {format_bytes(@preview.size_bytes)}
          </dd>
        </div>
        <div>
          <dt class="text-sm text-[#94A3B8]">Free space</dt>
          <dd id={"preview-#{@entry.ref}-free"} class="text-sm text-[#F1F5F9]">
            {format_bytes(@preview.free_bytes)}
          </dd>
        </div>
        <div>
          <dt class="text-sm text-[#94A3B8]">Format (guess)</dt>
          <dd id={"preview-#{@entry.ref}-format"} class="text-sm text-[#F1F5F9]">
            {format_guess(@preview.format_guess)}
          </dd>
        </div>
      </dl>

      <p id={"preview-#{@entry.ref}-copy-message"} class="mt-4 text-sm text-[#94A3B8]">
        Your original file stays where it is. A verified copy will be stored by your server and available to your devices.
        Uses {format_bytes(@preview.space_bytes)} of {format_bytes(@preview.free_bytes)} free.
      </p>

      <button
        id={"confirm-import-#{@entry.ref}"}
        type="submit"
        disabled={@confirming or entry_progress(@entry) < 100}
        class="mt-4 flex h-11 items-center justify-center gap-2 rounded-md bg-[#38BDF8] px-4 text-base font-semibold text-[#0F172A] hover:opacity-90 disabled:opacity-60"
      >
        Copy into my library
      </button>
    </div>
    """
  end

  defp entry_progress(%{progress: progress}), do: progress
  defp entry_progress(_entry), do: 0

  defp format_guess(%{system: nil}), do: "Unknown (guess from file name)"
  defp format_guess(%{system: system}), do: "#{system} (guess from file name)"

  defp format_bytes(:unknown), do: "unknown"

  defp format_bytes(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_073_741_824 -> "#{Float.round(bytes / 1_073_741_824, 1)} GB"
      bytes >= 1_048_576 -> "#{Float.round(bytes / 1_048_576, 1)} MB"
      bytes >= 1_024 -> "#{Float.round(bytes / 1_024, 1)} KB"
      true -> "#{bytes} B"
    end
  end
end
