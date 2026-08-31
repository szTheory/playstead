defmodule PlaysteadWeb.LibraryLive do
  @moduledoc """
  `/library` (list) and `/library/:id` (detail) — the console surface
  where a user reads back the IMPT-02 evidence for anything they've
  imported (D-26), and, per D-11, curates their canonical library
  (Favorites, Collections, the play queue, Continue) through the same
  `Playstead.Curation` context functions the API uses. Follows the
  devices console idiom: every load reads fresh from `Playstead.Catalogue`
  and `Playstead.Curation`, never from a cached assign — a locally
  patched assign is exactly how a console drifts from the canonical
  read another device just changed.

  An asset with no reference match gets a quiet `:unidentified` badge
  and nothing more — never an error, never a per-asset warning. The
  single invitation to install a reference pack lives once at the
  library level as a dismissible hint.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Catalogue
  alias Playstead.Curation
  alias PlaysteadWeb.LibraryLive.AssetDetail
  alias PlaysteadWeb.LibraryLive.Shelves

  import AssetDetail, only: [asset_detail: 1]
  import Shelves, only: [shelf: 1, shelf_empty_explainer: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Library", hint_dismissed: false, attention_count: 0)}
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
    favorites = Curation.list_favorites(user_id)
    favorite_ids = MapSet.new(favorites, & &1.asset_set_id)

    assign(socket,
      assets: assets,
      attention_count: Playstead.Attention.count(user_id),
      favorites: favorites,
      favorite_ids: favorite_ids,
      favorite_assets: pick_assets(assets, favorite_ids)
    )
  end

  defp pick_assets(assets, %MapSet{} = ids) do
    Enum.filter(assets, fn %{asset_set: set} -> MapSet.member?(ids, set.id) end)
  end

  @impl true
  def handle_event("dismiss-hint", _params, socket) do
    {:noreply, assign(socket, :hint_dismissed, true)}
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

  defp generic_error_flash do
    "Something went wrong on the server. Your data is safe — nothing was changed."
  end

  # Status facts computable server-side for this plan: whether the game
  # is in the play queue. Local-download state (verified/pinned/
  # downloading/missing-dependency/needs-attention) is Mac-client-local
  # (D-21) and is not tracked here — every card that isn't queued is
  # honestly `server_only` until a later plan wires that read model in.
  defp status_for(asset_set, assigns) do
    queue_ids = Map.get(assigns, :queue_asset_set_ids, MapSet.new())
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
      <div class="mx-auto max-w-5xl space-y-8">
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
          :if={
            not @hint_dismissed and Enum.any?(@assets, &(&1.identification_state == :unidentified))
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
          :if={@favorite_assets != []}
          id="favorites-shelf"
          heading="Favorites"
          items={@favorite_assets}
          navigate_fun={&~p"/library/#{&1}"}
          status_fun={&status_for(&1, assigns)}
        />
        <.shelf_empty_explainer
          :if={@favorite_assets == [] and @assets != []}
          id="favorites-shelf-explainer"
          heading="Favorites"
          body="Favorite a game to see it here."
        />

        <div :if={@assets != []} id="asset-list" class="space-y-3">
          <div
            :for={%{asset_set: set, identification_state: state} <- @assets}
            id={"asset-#{set.id}"}
            class="rounded-lg border border-[#334155] bg-[#1E293B] p-4 hover:border-[#38BDF8]"
          >
            <.link navigate={~p"/library/#{set.id}"} class="block">
              <p class="text-base font-semibold text-[#F1F5F9]">{set.display_title}</p>
              <p class="mt-1 text-sm text-[#94A3B8]">
                {set.system_id || "Unknown system"}
                <span
                  :if={state == :unidentified}
                  id={"asset-#{set.id}-unidentified-badge"}
                  class="ml-2 text-[#94A3B8]"
                >
                  Not yet identified
                </span>
              </p>
            </.link>
            <button
              type="button"
              id={"asset-#{set.id}-favorite-toggle"}
              phx-click="toggle-favorite"
              phx-value-asset-set-id={set.id}
              class="mt-2 text-sm font-semibold text-[#F1F5F9] hover:underline"
              aria-label={
                if MapSet.member?(@favorite_ids, set.id),
                  do: "Remove #{set.display_title} from Favorites",
                  else: "Add #{set.display_title} to Favorites"
              }
              aria-pressed={MapSet.member?(@favorite_ids, set.id)}
            >
              {if MapSet.member?(@favorite_ids, set.id),
                do: "Remove from Favorites",
                else: "Add to Favorites"}
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
