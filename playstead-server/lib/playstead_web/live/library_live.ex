defmodule PlaysteadWeb.LibraryLive do
  @moduledoc """
  `/library` (list) and `/library/:id` (detail) — the console surface
  where a user reads back the IMPT-02 evidence for anything they've
  imported (D-26). Follows the devices console idiom: every load reads
  fresh from `Playstead.Catalogue`, never from a cached assign.

  An asset with no reference match gets a quiet `:unidentified` badge
  and nothing more — never an error, never a per-asset warning. The
  single invitation to install a reference pack lives once at the
  library level as a dismissible hint.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Catalogue
  alias PlaysteadWeb.LibraryLive.AssetDetail

  import AssetDetail, only: [asset_detail: 1]

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

    assign(socket,
      assets: Catalogue.list_assets(scope),
      attention_count: Playstead.Attention.count(scope.user.id)
    )
  end

  @impl true
  def handle_event("dismiss-hint", _params, socket) do
    {:noreply, assign(socket, :hint_dismissed, true)}
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
      <div class="mx-auto max-w-3xl space-y-8">
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
          <p class="text-base text-[#F1F5F9]">Nothing in your library yet</p>
        </div>

        <div :if={@assets != []} id="asset-list" class="space-y-3">
          <.link
            :for={%{asset_set: set, identification_state: state} <- @assets}
            id={"asset-#{set.id}"}
            navigate={~p"/library/#{set.id}"}
            class="block rounded-lg border border-[#334155] bg-[#1E293B] p-4 hover:border-[#38BDF8]"
          >
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
        </div>
      </div>
    </div>
    """
  end
end
