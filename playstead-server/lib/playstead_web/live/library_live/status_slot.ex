defmodule PlaysteadWeb.LibraryLive.StatusSlot do
  @moduledoc """
  The single status vocabulary component (D-13, D-17, 03-UI-SPEC.md).
  Given the raw local-availability facts about one asset set, computes
  the one status ladder rank that outranks every other simultaneous
  condition and renders exactly one indicator — glyph, badge shape,
  and color together, never color alone (QUAL-01 / WCAG 1.4.1).

  Ladder, highest to lowest: needs_attention > missing_dependency >
  downloading > queued > pinned/verified > server_only. The safe-to-evict
  condition is deliberately not part of this ladder — it belongs to the
  storage view where reclaiming actually happens (D-13).

  Nothing here ever persists a computed rank (D-21): the rank is derived
  fresh, on every render, from the booleans/percent passed in.
  """

  use Phoenix.Component

  @type state ::
          :needs_attention
          | :missing_dependency
          | :downloading
          | :queued
          | :pinned
          | :verified
          | :server_only

  @states [
    :needs_attention,
    :missing_dependency,
    :downloading,
    :queued,
    :pinned,
    :verified,
    :server_only
  ]

  @doc "The full, ordered ladder — highest rank first. Used by tests that iterate all states."
  @spec ladder() :: [state()]
  def ladder, do: @states

  @doc """
  Computes the winning ladder state and its accessible-name sentence
  for `title` from a plain map of the same status facts the
  `status_slot/1` component accepts (`needs_attention`,
  `missing_dependency`, `downloading`, `download_percent`, `queued`,
  `pinned`, `verified`). This is the single implementation both the
  component and any caller building a combined accessible name (e.g.
  `GameCard`'s card-level `aria-label`) must use — never a second,
  locally reimplemented ladder.
  """
  @spec describe(map(), String.t()) :: {state(), String.t()}
  def describe(status, title) do
    state = rank(status)
    {state, accessible_name(state, title, Map.get(status, :download_percent, 0))}
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :needs_attention, :boolean, default: false
  attr :missing_dependency, :boolean, default: false
  attr :downloading, :boolean, default: false
  attr :download_percent, :integer, default: 0
  attr :queued, :boolean, default: false
  attr :pinned, :boolean, default: false
  attr :verified, :boolean, default: false
  attr :variant, :atom, default: :card, values: [:card, :list]

  def status_slot(assigns) do
    state = rank(assigns)

    assigns =
      assigns
      |> assign(:state, state)
      |> assign(:accessible_name, accessible_name(state, assigns.title, assigns.download_percent))
      |> assign(:list_label, list_label(state, assigns.download_percent))

    ~H"""
    <span
      id={@id}
      data-status={@state}
      data-status-slot="true"
      role="img"
      aria-label={@accessible_name}
      class={["status-slot", "status-badge-#{shape(@state)}", "status-slot-#{@state}"]}
      style={"color: var(--status-#{token_suffix(@state)}); border-color: var(--status-#{token_suffix(@state)})"}
    >
      <.icon name={glyph(@state)} class={["status-slot-glyph", "status-slot-#{@state}-glyph"]} />
      <span :if={@variant == :list} class="status-slot-label text-label font-semibold">
        {@list_label}
      </span>
    </span>
    """
  end

  attr :name, :string, required: true
  attr :class, :any, default: nil

  defp icon(assigns) do
    ~H"""
    <span aria-hidden="true" class={[@name, @class]} />
    """
  end

  # --- ladder ------------------------------------------------------------

  defp rank(%{needs_attention: true}), do: :needs_attention
  defp rank(%{missing_dependency: true}), do: :missing_dependency
  defp rank(%{downloading: true}), do: :downloading
  defp rank(%{queued: true}), do: :queued
  defp rank(%{pinned: true}), do: :pinned
  defp rank(%{verified: true}), do: :verified
  defp rank(_assigns), do: :server_only

  defp glyph(:needs_attention), do: "hero-exclamation-triangle-solid"
  defp glyph(:missing_dependency), do: "hero-wrench-screwdriver-solid"
  defp glyph(:downloading), do: "hero-arrow-down-circle"
  defp glyph(:queued), do: "hero-clock"
  defp glyph(:pinned), do: "hero-map-pin-solid"
  defp glyph(:verified), do: "hero-check-circle-solid"
  defp glyph(:server_only), do: "hero-cloud"

  defp shape(:needs_attention), do: "triangle"
  defp shape(:missing_dependency), do: "hexagon"
  defp shape(:downloading), do: "ring"
  defp shape(:queued), do: "rounded-square"
  defp shape(:pinned), do: "teardrop"
  defp shape(:verified), do: "circle-filled"
  defp shape(:server_only), do: "cloud"

  defp token_suffix(:needs_attention), do: "attention"
  defp token_suffix(:missing_dependency), do: "missing-dependency"
  defp token_suffix(:downloading), do: "downloading"
  defp token_suffix(:queued), do: "queued"
  defp token_suffix(:pinned), do: "pinned"
  defp token_suffix(:verified), do: "verified"
  defp token_suffix(:server_only), do: "server-only"

  defp accessible_name(:needs_attention, title, _percent), do: "#{title} needs your attention."

  defp accessible_name(:missing_dependency, title, _percent),
    do: "#{title} is missing something it needs to play."

  defp accessible_name(:downloading, title, percent),
    do: "#{title} is downloading, #{percent} percent complete."

  defp accessible_name(:queued, title, _percent), do: "#{title} is queued to download."

  defp accessible_name(:pinned, title, _percent),
    do: "#{title} is pinned and ready to play offline."

  defp accessible_name(:verified, title, _percent),
    do: "#{title} is downloaded and ready to play offline."

  defp accessible_name(:server_only, title, _percent),
    do: "#{title} is on your server. Choose Download to play it offline."

  defp list_label(:needs_attention, _percent), do: "Needs attention"
  defp list_label(:missing_dependency, _percent), do: "Missing dependency"
  defp list_label(:downloading, percent), do: "Downloading — #{percent}%"
  defp list_label(:queued, _percent), do: "Queued"
  defp list_label(:pinned, _percent), do: "Pinned"
  defp list_label(:verified, _percent), do: "Ready offline"
  defp list_label(:server_only, _percent), do: "On server"
end
