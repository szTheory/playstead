defmodule PlaysteadWeb.LibraryLive.GameCard do
  @moduledoc """
  The three-zone game card anatomy (D-12/D-13, 03-UI-SPEC.md): a
  dominant two-line clamped title, a meta line carrying the system
  monogram plus the quiet region/version chips and the existing
  not-yet-identified badge, and exactly one status slot. Tiles are
  landscape and fixed-height — no cover image, no generated artwork,
  no per-title derived color. `system_registry/0` is the one place the
  frozen system id -> monogram/display-name mapping is expressed;
  `PlaysteadWeb.LibraryLive.Sidebar` reuses it so both surfaces name a
  system identically.
  """

  use Phoenix.Component
  alias PlaysteadWeb.LibraryLive.StatusSlot
  import PlaysteadWeb.LibraryLive.StatusSlot, only: [status_slot: 1]

  @registry [
    {"gba", "GBA", "Game Boy Advance"},
    {"gb", "GB", "Game Boy"},
    {"gbc", "GBC", "Game Boy Color"},
    {"nes", "NES", "NES"},
    {"snes", "SNES", "Super Nintendo"},
    {"md", "MD", "Sega Genesis"},
    {"psx", "PSX", "PlayStation"},
    {"unknown", "?", "Unidentified"}
  ]

  @doc "The frozen `{system_id, monogram, display_name}` registry, in canonical order."
  @spec system_registry() :: [{String.t(), String.t(), String.t()}]
  def system_registry, do: @registry

  @doc "The canonical registry order of system ids (excluding `unknown`)."
  @spec system_order() :: [String.t()]
  def system_order, do: @registry |> Enum.map(&elem(&1, 0)) |> Enum.reject(&(&1 == "unknown"))

  @doc "The 2-3 letter monogram for a system id, or `?` for `nil`/unrecognized."
  @spec monogram(String.t() | nil) :: String.t()
  def monogram(system_id) do
    case Enum.find(@registry, fn {id, _mono, _name} -> id == system_id end) do
      {_id, mono, _name} -> mono
      nil -> "?"
    end
  end

  @doc "The human display name for a system id, or `Unidentified` for `nil`/unrecognized."
  @spec system_display_name(String.t() | nil) :: String.t()
  def system_display_name(system_id) do
    case Enum.find(@registry, fn {id, _mono, _name} -> id == system_id end) do
      {_id, _mono, name} -> name
      nil -> "Unidentified"
    end
  end

  @doc "The `--system-accent-*` token key for a system id (falls back to `unknown`)."
  @spec accent_key(String.t() | nil) :: String.t()
  def accent_key(system_id) do
    if Enum.any?(@registry, fn {id, _, _} -> id == system_id end), do: system_id, else: "unknown"
  end

  attr :asset_set, :map, required: true
  attr :identification_state, :atom, required: true
  attr :navigate, :string, required: true
  attr :status, :map, default: %{}

  def game_card(assigns) do
    assigns =
      assigns
      |> assign(:system_name, system_display_name(assigns.asset_set.system_id))
      |> assign(:status_state_assigns, Map.merge(%{}, assigns.status))

    ~H"""
    <.link
      navigate={@navigate}
      id={"game-card-#{@asset_set.id}"}
      class="game-card"
      aria-label={accessible_name(@asset_set, @system_name, @status_state_assigns)}
    >
      <p class="game-card-title text-heading font-semibold text-[#F1F5F9]">
        {@asset_set.display_title}
      </p>

      <div class="game-card-meta">
        <span
          class="system-monogram text-heading font-semibold"
          style={"background-color: var(--system-accent-#{accent_key(@asset_set.system_id)})"}
          aria-hidden="true"
        >
          {monogram(@asset_set.system_id)}
        </span>
        <span
          :if={@identification_state == :unidentified}
          id={"game-card-#{@asset_set.id}-unidentified"}
          class="unidentified-badge text-label text-[#94A3B8]"
        >
          Not yet identified
        </span>
      </div>

      <.status_slot
        id={"game-card-#{@asset_set.id}-status"}
        title={@asset_set.display_title}
        needs_attention={Map.get(@status_state_assigns, :needs_attention, false)}
        missing_dependency={Map.get(@status_state_assigns, :missing_dependency, false)}
        downloading={Map.get(@status_state_assigns, :downloading, false)}
        download_percent={Map.get(@status_state_assigns, :download_percent, 0)}
        queued={Map.get(@status_state_assigns, :queued, false)}
        pinned={Map.get(@status_state_assigns, :pinned, false)}
        verified={Map.get(@status_state_assigns, :verified, false)}
      />
    </.link>
    """
  end

  defp accessible_name(asset_set, system_name, status) do
    {_state, sentence} = StatusSlot.describe(status, asset_set.display_title)
    "#{asset_set.display_title}, #{system_name}, #{sentence}"
  end
end
