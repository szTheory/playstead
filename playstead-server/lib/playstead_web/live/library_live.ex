defmodule PlaysteadWeb.LibraryLive do
  @moduledoc """
  `/library` (list) and `/library/:id` (detail) — the console surface
  where a user reads back the IMPT-02 evidence for anything they've
  imported (D-26), and, per D-11, browses and curates their canonical
  library (Favorites, Collections, the play queue, Continue, Recent)
  through the same `Playstead.Curation` context functions the API uses.
  Follows the devices console idiom: every load reads fresh from
  `Playstead.Catalogue` and `Playstead.Curation`, never from a cached
  assign — a locally patched assign is exactly how a console drifts
  from the canonical read another device just changed.

  An asset with no reference match gets a quiet `:unidentified` badge
  and nothing more — never an error, never a per-asset warning. The
  single invitation to install a reference pack lives once at the
  library level as a dismissible hint.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Catalogue
  alias Playstead.Curation
  alias PlaysteadWeb.LibraryLive.AssetDetail
  alias PlaysteadWeb.LibraryLive.GameCard
  alias PlaysteadWeb.LibraryLive.Shelves
  alias PlaysteadWeb.LibraryLive.Sidebar

  alias PlaysteadWeb.LibraryLive.StatusSlot

  import AssetDetail, only: [asset_detail: 1]
  import GameCard, only: [game_card: 1]
  import Shelves, only: [shelf: 1]
  import Sidebar, only: [sidebar: 1]
  import StatusSlot, only: [status_slot: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Library",
       hint_dismissed: false,
       attention_count: 0,
       first_run_dismissed: false,
       show_all_systems: false,
       search: "",
       filter_system: nil,
       filter_availability: nil,
       sort: "title",
       view: :grid
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    load_assets(socket)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    scope = socket.assigns.current_scope

    case Catalogue.get_asset_detail(scope, id) do
      {:ok, detail} -> assign(socket, detail: detail, not_found: false)
      {:error, :not_found} -> assign(socket, detail: nil, not_found: true)
    end
  end

  defp load_assets(socket) do
    scope = socket.assigns.current_scope
    user_id = scope.user.id

    assets = Catalogue.list_assets(scope)
    assets_by_id = Map.new(assets, fn %{asset_set: set} = entry -> {set.id, entry} end)

    favorites = Curation.list_favorites(user_id)
    favorite_ids = MapSet.new(favorites, & &1.asset_set_id)

    continue = Curation.list_continue(user_id)
    queue = Curation.list_queue(user_id)
    queue_ids = MapSet.new(queue, & &1.asset_set_id)
    recent = Curation.list_recent(user_id)
    collections = Curation.list_collections(user_id)

    {systems, hidden_systems, has_unidentified} = system_breakdown(assets)

    socket
    |> assign(
      assets: assets,
      assets_by_id: assets_by_id,
      attention_count: Playstead.Attention.count(user_id),
      favorites: favorites,
      favorite_ids: favorite_ids,
      favorite_assets: pick_entries(assets_by_id, favorites, & &1.asset_set_id),
      continue: continue,
      continue_assets: pick_entries(assets_by_id, continue, & &1.asset_set_id),
      queue: queue,
      queue_ids: queue_ids,
      queue_assets: pick_entries(assets_by_id, queue, & &1.asset_set_id),
      recent: recent,
      recent_assets: pick_entries(assets_by_id, recent, & &1.asset_set_id),
      collections: collections,
      systems: systems,
      hidden_systems: hidden_systems,
      has_unidentified: has_unidentified
    )
    |> stream_filtered_assets(reset: true)
  end

  # The full-library browse section: search, system/availability filter
  # chips, and sort all apply here — separate from the five curation
  # shelves above, which are always the raw, unfiltered curation reads.
  # Rendered via a LiveView stream (D-16): a 500-item library must be
  # interactive on cold load with fixed row heights and no skeleton,
  # which a plain `:for` over a growing list assign cannot guarantee.
  defp stream_filtered_assets(socket, opts) do
    filtered = filtered_assets(socket)

    socket
    |> assign(:browse_empty?, filtered == [])
    |> stream(
      :library_assets,
      filtered,
      Keyword.merge([dom_id: &("asset-" <> &1.asset_set.id)], opts)
    )
  end

  defp filtered_assets(socket) do
    search = String.trim(socket.assigns[:search] || "")
    filter_system = socket.assigns[:filter_system]
    filter_availability = socket.assigns[:filter_availability]
    queue_ids = socket.assigns.queue_ids

    socket.assigns.assets
    |> Enum.filter(&matches_search?(&1, search))
    |> Enum.filter(&matches_system?(&1, filter_system))
    |> Enum.filter(&matches_availability?(&1, filter_availability, queue_ids))
    |> sort_assets(socket.assigns[:sort] || "title")
  end

  defp matches_search?(_entry, ""), do: true

  defp matches_search?(%{asset_set: set}, search) do
    q = String.downcase(search)

    String.contains?(String.downcase(set.display_title || ""), q) or
      Enum.any?(set.asset_members || [], fn member ->
        String.contains?(String.downcase(member.declared_name || ""), q)
      end)
  end

  defp matches_system?(_entry, system) when system in [nil, ""], do: true
  defp matches_system?(%{asset_set: set}, system), do: set.system_id == system

  defp matches_availability?(_entry, availability, _queue_ids) when availability in [nil, ""],
    do: true

  defp matches_availability?(%{asset_set: set}, "queued", queue_ids),
    do: MapSet.member?(queue_ids, set.id)

  defp matches_availability?(%{asset_set: set}, "server_only", queue_ids),
    do: not MapSet.member?(queue_ids, set.id)

  defp matches_availability?(_entry, _other, _queue_ids), do: true

  defp sort_assets(entries, "system") do
    Enum.sort_by(entries, fn %{asset_set: s} -> {s.system_id || "zzzz", title_key(s)} end)
  end

  defp sort_assets(entries, "date_added") do
    Enum.sort_by(entries, fn %{asset_set: s} -> s.inserted_at end, {:desc, DateTime})
  end

  defp sort_assets(entries, _title) do
    Enum.sort_by(entries, fn %{asset_set: s} -> title_key(s) end)
  end

  defp title_key(%{display_title: title}), do: String.downcase(title || "")

  defp pick_entries(assets_by_id, rows, key_fun) do
    rows
    |> Enum.map(&Map.get(assets_by_id, key_fun.(&1)))
    |> Enum.reject(&is_nil/1)
  end

  # Frozen registry order (D-14), non-empty systems only — never
  # alphabetically re-sorted. `unknown` never appears in this list; it is
  # surfaced separately as the always-last Unidentified sidebar entry.
  defp system_breakdown(assets) do
    counts =
      Enum.reduce(assets, %{}, fn %{asset_set: set}, acc ->
        Map.update(acc, set.system_id, 1, &(&1 + 1))
      end)

    present =
      for id <- GameCard.system_order(), count = Map.get(counts, id, 0), count > 0 do
        %{id: id, count: count}
      end

    hidden =
      for id <- GameCard.system_order(), count = Map.get(counts, id, 0), count == 0 do
        %{id: id, count: 0}
      end

    has_unidentified = Map.get(counts, "unknown", 0) > 0 or Map.get(counts, nil, 0) > 0

    {present, hidden, has_unidentified}
  end

  @impl true
  def handle_event("dismiss-hint", _params, socket) do
    {:noreply, assign(socket, :hint_dismissed, true)}
  end

  def handle_event("dismiss-first-run-banner", _params, socket) do
    {:noreply, assign(socket, :first_run_dismissed, true)}
  end

  def handle_event("show-all-systems", _params, socket) do
    {:noreply, assign(socket, :show_all_systems, not socket.assigns.show_all_systems)}
  end

  def handle_event("search", %{"q" => query}, socket) do
    socket = assign(socket, :search, query)
    {:noreply, stream_filtered_assets(socket, reset: true)}
  end

  def handle_event("filter-system", %{"system" => system}, socket) do
    new_value = if socket.assigns.filter_system == system, do: nil, else: system
    socket = assign(socket, :filter_system, new_value)
    {:noreply, stream_filtered_assets(socket, reset: true)}
  end

  def handle_event("filter-availability", %{"availability" => availability}, socket) do
    new_value = if socket.assigns.filter_availability == availability, do: nil, else: availability
    socket = assign(socket, :filter_availability, new_value)
    {:noreply, stream_filtered_assets(socket, reset: true)}
  end

  def handle_event("sort", %{"sort" => sort}, socket) do
    socket = assign(socket, :sort, sort)
    {:noreply, stream_filtered_assets(socket, reset: true)}
  end

  def handle_event("toggle-view", _params, socket) do
    new_view = if socket.assigns.view == :grid, do: :list, else: :grid
    socket = assign(socket, :view, new_view)
    # A `phx-update="stream"` container only ever receives insert/delete/
    # reorder diffs for its children — LiveView does not re-diff an
    # already-inserted item's own markup, so a plain assign here would
    # leave every existing row showing its old grid/list branch. Forcing
    # a full re-stream (`reset: true`) re-inserts every item fresh under
    # the new view's branch.
    {:noreply, stream_filtered_assets(socket, reset: true)}
  end

  def handle_event("clear-search", _params, socket) do
    socket = assign(socket, :search, "")
    {:noreply, stream_filtered_assets(socket, reset: true)}
  end

  def handle_event("toggle-favorite", %{"asset-set-id" => asset_set_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    result =
      if MapSet.member?(socket.assigns.favorite_ids, asset_set_id) do
        Curation.remove_favorite(user_id, asset_set_id)
      else
        Curation.add_favorite(user_id, Ecto.UUID.generate(), asset_set_id)
      end

    case result do
      {:ok, _} -> {:noreply, load_assets(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event("enqueue", %{"asset-set-id" => asset_set_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Curation.enqueue(user_id, Ecto.UUID.generate(), asset_set_id) do
      {:ok, _item} -> {:noreply, load_assets(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event("dequeue", %{"asset-set-id" => asset_set_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Curation.dequeue(user_id, asset_set_id) do
      {:ok, :removed} -> {:noreply, load_assets(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event(
        "move-queue-item",
        %{"asset-set-id" => asset_set_id, "direction" => direction},
        socket
      ) do
    user_id = socket.assigns.current_scope.user.id
    neighbours = move_neighbours(socket.assigns.queue, asset_set_id, direction)

    case neighbours && Curation.move_queue_item(user_id, asset_set_id, neighbours) do
      nil -> {:noreply, socket}
      {:ok, _item} -> {:noreply, load_assets(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event("dismiss-continue", %{"asset-set-id" => asset_set_id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Curation.dismiss_continue(user_id, Ecto.UUID.generate(), asset_set_id) do
      {:ok, _dismissal} -> {:noreply, load_assets(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  # One gesture, one command (D-09): names the two neighbours the moved
  # item should sit between after a single "up"/"down" step — never an
  # intermediate drag position, never a whole ordered list.
  defp move_neighbours(items, asset_set_id, direction) do
    ids = Enum.map(items, & &1.asset_set_id)
    index = Enum.find_index(ids, &(&1 == asset_set_id))

    case {index, direction} do
      {nil, _} ->
        nil

      {0, "up"} ->
        nil

      {i, "up"} ->
        %{before_asset_set_id: safe_at(ids, i - 2), after_asset_set_id: safe_at(ids, i - 1)}

      {i, "down"} when i == length(ids) - 1 ->
        nil

      {i, "down"} ->
        %{before_asset_set_id: safe_at(ids, i + 1), after_asset_set_id: safe_at(ids, i + 2)}
    end
  end

  # `Enum.at/2` treats a negative index as "from the end" — a past-the-
  # start lookup (e.g. index -1) would otherwise silently wrap around to
  # the *last* item instead of meaning "no neighbour there", handing
  # `Curation.move_queue_item/3` a duplicate/self neighbour and hanging
  # `Position.between/2`'s midpoint search. Negative is always "none".
  defp safe_at(_list, i) when i < 0, do: nil
  defp safe_at(list, i), do: Enum.at(list, i)

  defp generic_error_flash do
    "Something went wrong on the server. Your data is safe — nothing was changed."
  end

  # Status facts computable server-side for this plan: whether the game
  # is in the play queue. Local-download state (verified/pinned/
  # downloading/missing-dependency/needs-attention) is Mac-client-local
  # (D-21) and is not tracked here — every card that isn't queued is
  # honestly `server_only` until a later plan wires that read model in.
  defp status_for(asset_set, assigns) do
    queue_ids = Map.get(assigns, :queue_ids, MapSet.new())
    %{queued: MapSet.member?(queue_ids, asset_set.id)}
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-6">
        <.link navigate={~p"/library"} class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]">
          &larr; Back to library
        </.link>

        <div
          :if={@not_found}
          id="asset-not-found"
          class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
        >
          <p class="text-base text-[#F1F5F9]">Not found</p>
        </div>

        <.asset_detail :if={@detail} detail={@detail} />
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto flex max-w-6xl flex-col gap-8 lg:flex-row">
        <.sidebar
          active={:home}
          systems={@systems}
          hidden_systems={@hidden_systems}
          show_all_systems={@show_all_systems}
          has_unidentified={@has_unidentified}
          empty={
            %{
              continue: @continue_assets == [],
              favorites: @favorite_assets == [],
              collections: @collections == [],
              queue: @queue_assets == [],
              recent: @recent_assets == []
            }
          }
        />

        <div class="min-w-0 flex-1 space-y-8">
          <div class="flex items-center justify-between">
            <h1 class="text-display font-semibold text-[#F1F5F9]">Library</h1>
            <.link
              :if={@attention_count > 0}
              navigate={~p"/attention"}
              id="attention-nav-link"
              class="text-sm font-semibold text-[#94A3B8] hover:text-[#F1F5F9]"
            >
              Needs attention ({@attention_count})
            </.link>
          </div>

          <div
            :if={not @first_run_dismissed and @assets != []}
            id="first-run-banner"
            class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
          >
            <p class="text-sm font-semibold text-[#F1F5F9]">Your library lives on your server.</p>
            <p class="mt-1 text-sm text-[#94A3B8]">
              Everything here is stored safely on your Playstead server. Download what you want to
              play offline.
            </p>
            <button
              id="dismiss-first-run-banner"
              type="button"
              phx-click="dismiss-first-run-banner"
              class="mt-2 text-sm font-semibold text-[#F1F5F9] hover:underline"
            >
              Dismiss
            </button>
          </div>

          <div
            :if={
              not @hint_dismissed and
                Enum.any?(@assets, &(&1.identification_state == :unidentified))
            }
            id="reference-pack-hint"
            class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
          >
            <p class="text-sm text-[#94A3B8]">
              <.link
                navigate={~p"/reference-packs"}
                id="reference-pack-hint-link"
                class="font-semibold text-[#F1F5F9] hover:underline"
              >
                Install a reference pack to identify games.
              </.link>
              <button
                id="dismiss-reference-pack-hint"
                type="button"
                phx-click="dismiss-hint"
                class="ml-2 text-sm font-semibold text-[#F1F5F9] hover:underline"
              >
                Dismiss
              </button>
            </p>
          </div>

          <div
            :if={@assets == []}
            id="library-empty"
            class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-display font-semibold text-[#F1F5F9]">No games yet</p>
            <p class="mt-1 text-base text-[#94A3B8]">
              Import your files to add them to your library. They'll appear here as soon as they're
              added.
            </p>
          </div>

          <.shelf
            :if={@continue_assets != []}
            id="continue-shelf"
            heading="Continue"
            items={@continue_assets}
            navigate_fun={&~p"/library/#{&1}"}
            status_fun={&status_for(&1, assigns)}
            dismiss_fun={fn _asset_set -> {"dismiss-continue", "Dismiss"} end}
          />

          <.shelf
            :if={@favorite_assets != []}
            id="favorites-shelf"
            heading="Favorites"
            items={@favorite_assets}
            navigate_fun={&~p"/library/#{&1}"}
            status_fun={&status_for(&1, assigns)}
          />

          <div :if={@collections != []} id="collections-shelf" class="library-shelf">
            <div class="library-shelf-heading flex items-baseline justify-between">
              <h2 class="text-heading font-semibold text-[#F1F5F9]">Collections</h2>
              <.link navigate={~p"/library/collections"} class="text-label text-[#94A3B8]">
                See all
              </.link>
            </div>
            <div class="mt-2 flex gap-3 overflow-x-auto">
              <.link
                :for={collection <- @collections}
                navigate={~p"/library/collections/#{collection.id}"}
                id={"collections-shelf-item-#{collection.id}"}
                class="rounded-lg border border-[#334155] bg-[#1E293B] px-4 py-3 text-sm font-semibold text-[#F1F5F9] hover:border-[#38BDF8]"
              >
                {collection.name}
              </.link>
            </div>
          </div>

          <section :if={@queue_assets != []} id="queue-shelf" class="library-shelf">
            <div class="library-shelf-heading flex items-baseline justify-between">
              <h2 class="text-heading font-semibold text-[#F1F5F9]">Queue</h2>
              <span class="text-label text-[#94A3B8]">{length(@queue_assets)}</span>
            </div>
            <div class="mt-2 space-y-2">
              <div
                :for={{entry, index} <- Enum.with_index(@queue_assets)}
                id={"queue-item-#{entry.asset_set.id}"}
                class="flex items-center justify-between rounded-lg border border-[#334155] bg-[#1E293B] p-3"
              >
                <.link
                  navigate={~p"/library/#{entry.asset_set.id}"}
                  class="text-sm font-semibold text-[#F1F5F9] hover:underline"
                >
                  {entry.asset_set.display_title}
                </.link>
                <div class="flex items-center gap-2">
                  <button
                    :if={index > 0}
                    type="button"
                    id={"queue-item-#{entry.asset_set.id}-move-up"}
                    phx-click="move-queue-item"
                    phx-value-asset-set-id={entry.asset_set.id}
                    phx-value-direction="up"
                    aria-label={"Move #{entry.asset_set.display_title} up in queue"}
                    class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                  >
                    Move up
                  </button>
                  <button
                    :if={index < length(@queue_assets) - 1}
                    type="button"
                    id={"queue-item-#{entry.asset_set.id}-move-down"}
                    phx-click="move-queue-item"
                    phx-value-asset-set-id={entry.asset_set.id}
                    phx-value-direction="down"
                    aria-label={"Move #{entry.asset_set.display_title} down in queue"}
                    class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                  >
                    Move down
                  </button>
                  <button
                    type="button"
                    id={"queue-item-#{entry.asset_set.id}-remove"}
                    phx-click="dequeue"
                    phx-value-asset-set-id={entry.asset_set.id}
                    aria-label={"Remove #{entry.asset_set.display_title} from Queue"}
                    class="text-sm font-semibold text-[#EF4444] hover:underline"
                  >
                    Remove
                  </button>
                </div>
              </div>
            </div>
          </section>

          <.shelf
            :if={@recent_assets != []}
            id="recent-shelf"
            heading="Recent"
            items={@recent_assets}
            navigate_fun={&~p"/library/#{&1}"}
            status_fun={&status_for(&1, assigns)}
          />

          <div :if={@assets != []} id="library-browse" class="space-y-4">
            <div class="flex flex-wrap items-center gap-3">
              <form id="library-search-form" phx-change="search" class="flex-1">
                <input
                  type="text"
                  name="q"
                  id="library-search"
                  value={@search}
                  placeholder="Search by title or filename"
                  aria-label="Search your library"
                  phx-debounce="300"
                  class="w-full rounded-lg border border-[#334155] bg-[#1E293B] px-3 py-2 text-sm text-[#F1F5F9]"
                />
              </form>

              <button
                type="button"
                id="toggle-view"
                phx-click="toggle-view"
                aria-label={if @view == :grid, do: "Switch to list view", else: "Switch to grid view"}
                class="text-sm font-semibold text-[#94A3B8] hover:text-[#F1F5F9]"
              >
                {if @view == :grid, do: "List view", else: "Grid view"}
              </button>
            </div>

            <div class="flex flex-wrap gap-2" role="group" aria-label="Filter by system">
              <button
                :for={system <- @systems}
                type="button"
                id={"filter-chip-system-#{system.id}"}
                phx-click="filter-system"
                phx-value-system={system.id}
                aria-pressed={to_string(@filter_system == system.id)}
                class="filter-chip rounded-full border border-[#334155] px-3 py-1 text-label text-[#94A3B8]"
              >
                {GameCard.system_display_name(system.id)}
              </button>
            </div>

            <div class="flex flex-wrap gap-2" role="group" aria-label="Filter by availability">
              <button
                type="button"
                id="filter-chip-availability-queued"
                phx-click="filter-availability"
                phx-value-availability="queued"
                aria-pressed={to_string(@filter_availability == "queued")}
                class="filter-chip rounded-full border border-[#334155] px-3 py-1 text-label text-[#94A3B8]"
              >
                Queued
              </button>
              <button
                type="button"
                id="filter-chip-availability-server-only"
                phx-click="filter-availability"
                phx-value-availability="server_only"
                aria-pressed={to_string(@filter_availability == "server_only")}
                class="filter-chip rounded-full border border-[#334155] px-3 py-1 text-label text-[#94A3B8]"
              >
                On server
              </button>
            </div>

            <form
              :if={@view == :list}
              id="library-sort-form"
              phx-change="sort"
              class="flex items-center gap-2"
            >
              <label for="library-sort" class="text-label text-[#94A3B8]">Sort by</label>
              <select
                id="library-sort"
                name="sort"
                class="rounded-lg border border-[#334155] bg-[#1E293B] px-2 py-1 text-sm text-[#F1F5F9]"
              >
                <option value="title" selected={@sort == "title"}>Title</option>
                <option value="system" selected={@sort == "system"}>System</option>
                <option value="date_added" selected={@sort == "date_added"}>Date added</option>
              </select>
            </form>

            <div :if={@browse_empty? and @search != ""} id="library-search-empty">
              <p class="text-heading font-semibold text-[#F1F5F9]">No matches for “{@search}”</p>
              <p class="mt-1 text-base text-[#94A3B8]">
                Check the spelling, or clear your search to see everything.
              </p>
              <button
                type="button"
                id="clear-search"
                phx-click="clear-search"
                class="mt-2 text-sm font-semibold text-[#F1F5F9] hover:underline"
              >
                Clear search
              </button>
            </div>

            <!--
              A LiveView stream can only be consumed by one phx-update="stream"
              container per page — inserts are delivered once, so two
              conditionally-visible containers sharing the same stream name
              (grid vs. list) would leave whichever one wasn't mounted first
              permanently empty after a view toggle. One container, switching
              its inner markup per item, is the only correct structure.
            -->
            <div
              id="library-asset-stream"
              phx-update="stream"
              class={if @view == :grid, do: "flex flex-wrap gap-4", else: "space-y-1"}
            >
              <div
                :for={{dom_id, entry} <- @streams.library_assets}
                id={dom_id}
                class={
                  if @view == :grid,
                    do: "space-y-1",
                    else:
                      "flex h-14 items-center justify-between gap-4 rounded-lg border border-[#334155] bg-[#1E293B] px-4"
                }
                aria-label={
                  if @view == :list,
                    do:
                      list_row_accessible_name(
                        entry.asset_set,
                        status_for(entry.asset_set, assigns)
                      )
                }
              >
                <%= if @view == :grid do %>
                  <.game_card
                    id_prefix="browse-card"
                    asset_set={entry.asset_set}
                    identification_state={entry.identification_state}
                    navigate={~p"/library/#{entry.asset_set.id}"}
                    status={status_for(entry.asset_set, assigns)}
                  />
                  <.asset_actions
                    asset_set={entry.asset_set}
                    favorite?={MapSet.member?(@favorite_ids, entry.asset_set.id)}
                    queued?={MapSet.member?(@queue_ids, entry.asset_set.id)}
                  />
                <% else %>
                  <.link
                    navigate={~p"/library/#{entry.asset_set.id}"}
                    class="min-w-0 flex-1 truncate text-sm font-semibold text-[#F1F5F9] hover:underline"
                  >
                    {entry.asset_set.display_title}
                  </.link>
                  <span class="text-label text-[#94A3B8]">
                    {GameCard.system_display_name(entry.asset_set.system_id)}
                  </span>
                  <.status_slot
                    id={"#{dom_id}-status"}
                    title={entry.asset_set.display_title}
                    variant={:list}
                    queued={Map.get(status_for(entry.asset_set, assigns), :queued, false)}
                  />
                  <.asset_actions
                    asset_set={entry.asset_set}
                    favorite?={MapSet.member?(@favorite_ids, entry.asset_set.id)}
                    queued?={MapSet.member?(@queue_ids, entry.asset_set.id)}
                  />
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :asset_set, :map, required: true
  attr :favorite?, :boolean, required: true
  attr :queued?, :boolean, required: true

  defp asset_actions(assigns) do
    ~H"""
    <div class="flex items-center gap-3">
      <button
        type="button"
        id={"asset-#{@asset_set.id}-favorite-toggle"}
        phx-click="toggle-favorite"
        phx-value-asset-set-id={@asset_set.id}
        class="text-sm font-semibold text-[#F1F5F9] hover:underline"
        aria-label={
          if @favorite?,
            do: "Remove #{@asset_set.display_title} from Favorites",
            else: "Add #{@asset_set.display_title} to Favorites"
        }
        aria-pressed={to_string(@favorite?)}
      >
        {if @favorite?, do: "Remove from Favorites", else: "Add to Favorites"}
      </button>
      <button
        type="button"
        id={"asset-#{@asset_set.id}-queue-toggle"}
        phx-click={if @queued?, do: "dequeue", else: "enqueue"}
        phx-value-asset-set-id={@asset_set.id}
        class="text-sm font-semibold text-[#F1F5F9] hover:underline"
        aria-label={
          if @queued?,
            do: "Remove #{@asset_set.display_title} from Queue",
            else: "Add #{@asset_set.display_title} to Queue"
        }
        aria-pressed={to_string(@queued?)}
      >
        {if @queued?, do: "Remove from Queue", else: "Add to Queue"}
      </button>
    </div>
    """
  end

  defp list_row_accessible_name(asset_set, status) do
    {_state, sentence} = StatusSlot.describe(status, asset_set.display_title)

    "#{asset_set.display_title}, #{GameCard.system_display_name(asset_set.system_id)}, #{sentence}"
  end
end
