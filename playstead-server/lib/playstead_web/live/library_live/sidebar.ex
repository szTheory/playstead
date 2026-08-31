defmodule PlaysteadWeb.LibraryLive.Sidebar do
  @moduledoc """
  The canonical navigation order (D-14, 03-UI-SPEC.md): Home, Continue,
  Favorites, Collections, Queue, Recent, then the systems that actually
  have content (frozen registry order, never alphabetical), then
  Unidentified last — shared one-to-one with the Mac client's source
  list. A shelf with zero items keeps its sidebar entry with a one-line
  explainer rather than disappearing (D-15): removing the noun entirely
  would teach the user the feature does not exist.
  """

  use Phoenix.Component
  import PlaysteadWeb.LibraryLive.GameCard, only: [system_display_name: 1]

  attr :active, :atom, default: :home

  attr :systems, :list,
    default: [],
    doc: "[%{id: system_id, count: n}] present systems, registry order"

  attr :hidden_systems, :list, default: [], doc: "[%{id: system_id, count: n}] empty systems"
  attr :show_all_systems, :boolean, default: false
  attr :has_unidentified, :boolean, default: false
  attr :active_system, :string, default: nil

  attr :empty, :map,
    default: %{},
    doc: "%{continue: bool, favorites: bool, collections: bool, queue: bool, recent: bool}"

  def sidebar(assigns) do
    ~H"""
    <nav id="library-sidebar" aria-label="Library navigation" class="library-sidebar">
      <.entry id="sidebar-home" href="/library" active={@active == :home}>Home</.entry>
      <.entry id="sidebar-continue" href="/library?shelf=continue" active={@active == :continue}>
        Continue
      </.entry>
      <p
        :if={Map.get(@empty, :continue, false)}
        id="sidebar-continue-explainer"
        class="text-label text-[#94A3B8]"
      >
        Play something, and pick up where you left off here.
      </p>

      <.entry id="sidebar-favorites" href="/library?shelf=favorites" active={@active == :favorites}>
        Favorites
      </.entry>
      <p
        :if={Map.get(@empty, :favorites, false)}
        id="sidebar-favorites-explainer"
        class="text-label text-[#94A3B8]"
      >
        Favorite a game to see it here.
      </p>

      <.entry id="sidebar-collections" href="/library/collections" active={@active == :collections}>
        Collections
      </.entry>
      <p
        :if={Map.get(@empty, :collections, false)}
        id="sidebar-collections-explainer"
        class="text-label text-[#94A3B8]"
      >
        Create a collection to group games your way.
      </p>

      <.entry id="sidebar-queue" href="/library?shelf=queue" active={@active == :queue}>
        Queue
      </.entry>
      <p
        :if={Map.get(@empty, :queue, false)}
        id="sidebar-queue-explainer"
        class="text-label text-[#94A3B8]"
      >
        Add a game to your queue to keep it in mind.
      </p>

      <.entry id="sidebar-recent" href="/library?shelf=recent" active={@active == :recent}>
        Recent
      </.entry>
      <p
        :if={Map.get(@empty, :recent, false)}
        id="sidebar-recent-explainer"
        class="text-label text-[#94A3B8]"
      >
        Play a game to see it here.
      </p>

      <div class="mt-4">
        <.entry
          :for={system <- @systems}
          id={"sidebar-system-#{system.id}"}
          href={"/library?system=#{system.id}"}
          active={@active == :system and @active_system == system.id}
        >
          {system_display_name(system.id)} ({system.count})
        </.entry>

        <button
          :if={@hidden_systems != []}
          type="button"
          id="show-all-systems"
          phx-click="show-all-systems"
          aria-pressed={@show_all_systems}
          class="text-label text-[#94A3B8] hover:text-[#F1F5F9]"
        >
          {if @show_all_systems,
            do: "Hide empty systems",
            else: "Show all systems (#{length(@hidden_systems)} hidden)"}
        </button>
      </div>

      <.entry
        :if={@has_unidentified}
        id="sidebar-unidentified"
        href="/library?system=unknown"
        active={@active == :unidentified}
      >
        Unidentified
      </.entry>
    </nav>
    """
  end

  attr :id, :string, required: true
  attr :href, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp entry(assigns) do
    ~H"""
    <.link
      navigate={@href}
      id={@id}
      class={["library-sidebar-entry text-label font-semibold", @active && "text-[#38BDF8]"]}
      aria-current={@active && "page"}
    >
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
