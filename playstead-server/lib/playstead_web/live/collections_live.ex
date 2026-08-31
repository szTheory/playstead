defmodule PlaysteadWeb.CollectionsLive do
  @moduledoc """
  `/library/collections` (list) and `/library/collections/:id` (members)
  — manual, flat, ordered collections (D-10), managed through the same
  `Playstead.Curation` context functions the API uses (D-11). No nesting,
  no rule builder: create, rename, delete, add member, remove member,
  reorder. Every load reads fresh from the context, never a cached
  assign, exactly like `PlaysteadWeb.LibraryLive`.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Catalogue
  alias Playstead.Curation

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Collections", new_name: "")}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    load_collections(socket)
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> load_collections()
    |> load_members(id)
  end

  defp load_collections(socket) do
    user_id = socket.assigns.current_scope.user.id
    assign(socket, :collections, Curation.list_collections(user_id))
  end

  defp load_members(socket, collection_id) do
    user_id = socket.assigns.current_scope.user.id
    scope = socket.assigns.current_scope

    case Curation.list_collection_members(user_id, collection_id) do
      {:ok, members} ->
        assets_by_id =
          Catalogue.list_assets(scope)
          |> Map.new(fn %{asset_set: set} = entry -> {set.id, entry} end)

        collection = Enum.find(socket.assigns.collections, &(&1.id == collection_id))

        assign(socket,
          collection: collection,
          collection_not_found: is_nil(collection),
          members: members,
          assets_by_id: assets_by_id,
          available_assets: Map.values(assets_by_id) -- member_entries(members, assets_by_id)
        )

      {:error, :not_found} ->
        assign(socket, collection: nil, collection_not_found: true, members: [])
    end
  end

  defp member_entries(members, assets_by_id) do
    members
    |> Enum.map(&Map.get(assets_by_id, &1.asset_set_id))
    |> Enum.reject(&is_nil/1)
  end

  @impl true
  def handle_event("create-collection", %{"name" => name}, socket) when name != "" do
    user_id = socket.assigns.current_scope.user.id

    case Curation.create_collection(user_id, Ecto.UUID.generate(), name) do
      {:ok, _collection} -> {:noreply, socket |> assign(:new_name, "") |> load_collections()}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event("create-collection", _params, socket), do: {:noreply, socket}

  def handle_event("rename-collection", %{"collection_id" => id, "name" => name}, socket)
      when name != "" do
    user_id = socket.assigns.current_scope.user.id

    case Curation.rename_collection(user_id, id, name) do
      {:ok, _collection} -> {:noreply, load_collections(socket)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event("delete-collection", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    case Curation.delete_collection(user_id, id) do
      {:ok, :removed} ->
        {:noreply,
         socket
         |> load_collections()
         |> push_navigate(to: ~p"/library/collections")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event(
        "add-collection-member",
        %{"collection-id" => collection_id, "asset-set-id" => asset_set_id},
        socket
      ) do
    user_id = socket.assigns.current_scope.user.id

    case Curation.add_collection_member(
           user_id,
           collection_id,
           Ecto.UUID.generate(),
           asset_set_id
         ) do
      {:ok, _member} -> {:noreply, load_members(socket, collection_id)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event(
        "remove-collection-member",
        %{"collection-id" => collection_id, "asset-set-id" => asset_set_id},
        socket
      ) do
    user_id = socket.assigns.current_scope.user.id

    case Curation.remove_collection_member(user_id, collection_id, asset_set_id) do
      {:ok, :removed} -> {:noreply, load_members(socket, collection_id)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  def handle_event(
        "move-collection-member",
        %{"collection-id" => collection_id, "asset-set-id" => asset_set_id, "direction" => dir},
        socket
      ) do
    user_id = socket.assigns.current_scope.user.id
    members = socket.assigns.members
    neighbours = move_neighbours(members, asset_set_id, dir)

    case neighbours &&
           Curation.move_collection_member(user_id, collection_id, asset_set_id, neighbours) do
      nil -> {:noreply, socket}
      {:ok, _member} -> {:noreply, load_members(socket, collection_id)}
      {:error, _reason} -> {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  # One gesture (one button press), one command: names the two neighbours
  # the moved member should sit between after a single "up"/"down" step —
  # never an intermediate position, never a whole ordered list (D-09).
  defp move_neighbours(members, asset_set_id, direction) do
    ids = Enum.map(members, & &1.asset_set_id)
    index = Enum.find_index(ids, &(&1 == asset_set_id))

    case {index, direction} do
      {nil, _} ->
        nil

      {0, "up"} ->
        nil

      {i, "up"} ->
        %{
          before_asset_set_id: safe_at(ids, i - 2),
          after_asset_set_id: safe_at(ids, i - 1)
        }

      {i, "down"} when i == length(ids) - 1 ->
        nil

      {i, "down"} ->
        %{
          before_asset_set_id: safe_at(ids, i + 1),
          after_asset_set_id: safe_at(ids, i + 2)
        }
    end
  end

  # `Enum.at/2` treats a negative index as "from the end", which would
  # silently wrap a past-the-start lookup (e.g. index -1) around to the
  # *last* element instead of "no neighbour there" — exactly the kind of
  # off-by-one that hands `Curation.move_collection_member/4` a
  # duplicate/self neighbour and hangs `Position.between/2`'s midpoint
  # search. Negative indices are always "no neighbour" here.
  defp safe_at(_list, i) when i < 0, do: nil
  defp safe_at(list, i), do: Enum.at(list, i)

  defp generic_error_flash do
    "Something went wrong on the server. Your data is safe — nothing was changed."
  end

  @impl true
  def render(%{live_action: :show} = assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-6">
        <.link navigate={~p"/library/collections"} class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]">
          &larr; Back to collections
        </.link>

        <div :if={@collection_not_found} id="collection-not-found" class="text-base text-[#F1F5F9]">
          Not found
        </div>

        <div :if={@collection} id={"collection-#{@collection.id}"}>
          <h1 class="text-display font-semibold text-[#F1F5F9]">{@collection.name}</h1>

          <div id="collection-members" class="mt-6 space-y-2">
            <div
              :for={member <- @members}
              id={"collection-member-#{member.asset_set_id}"}
              class="flex items-center justify-between rounded-lg border border-[#334155] bg-[#1E293B] p-3"
            >
              <span class="text-sm text-[#F1F5F9]">
                {member_title(member, @assets_by_id)}
              </span>
              <div class="flex items-center gap-2">
                <button
                  type="button"
                  id={"collection-member-#{member.asset_set_id}-move-up"}
                  phx-click="move-collection-member"
                  phx-value-collection-id={@collection.id}
                  phx-value-asset-set-id={member.asset_set_id}
                  phx-value-direction="up"
                  aria-label={"Move #{member_title(member, @assets_by_id)} up"}
                  class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                >
                  Move up
                </button>
                <button
                  type="button"
                  id={"collection-member-#{member.asset_set_id}-move-down"}
                  phx-click="move-collection-member"
                  phx-value-collection-id={@collection.id}
                  phx-value-asset-set-id={member.asset_set_id}
                  phx-value-direction="down"
                  aria-label={"Move #{member_title(member, @assets_by_id)} down"}
                  class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                >
                  Move down
                </button>
                <button
                  type="button"
                  id={"collection-member-#{member.asset_set_id}-remove"}
                  phx-click="remove-collection-member"
                  phx-value-collection-id={@collection.id}
                  phx-value-asset-set-id={member.asset_set_id}
                  aria-label={"Remove #{member_title(member, @assets_by_id)} from collection"}
                  class="text-sm font-semibold text-[#EF4444] hover:underline"
                >
                  Remove
                </button>
              </div>
            </div>
          </div>

          <div :if={@available_assets != []} id="collection-add-member" class="mt-6">
            <h2 class="text-heading font-semibold text-[#F1F5F9]">Add a game</h2>
            <div class="mt-2 space-y-2">
              <button
                :for={%{asset_set: set} <- @available_assets}
                type="button"
                id={"collection-add-#{set.id}"}
                phx-click="add-collection-member"
                phx-value-collection-id={@collection.id}
                phx-value-asset-set-id={set.id}
                class="block text-sm text-[#F1F5F9] hover:underline"
              >
                {set.display_title}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-6">
        <.link navigate={~p"/library"} class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]">
          &larr; Back to library
        </.link>

        <h1 class="text-display font-semibold text-[#F1F5F9]">Collections</h1>

        <form id="create-collection-form" phx-submit="create-collection" class="flex gap-2">
          <input
            type="text"
            name="name"
            id="create-collection-name"
            aria-label="Collection name"
            class="rounded-lg border border-[#334155] bg-[#1E293B] px-3 py-2 text-sm text-[#F1F5F9]"
          />
          <button
            type="submit"
            id="create-collection-submit"
            class="rounded-lg bg-[#38BDF8] px-3 py-2 text-sm font-semibold text-[#0F172A]"
          >
            Create Collection
          </button>
        </form>

        <div
          :if={@collections == []}
          id="collections-empty"
          class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
        >
          <p class="text-base text-[#94A3B8]">Create a collection to group games your way.</p>
        </div>

        <div :if={@collections != []} id="collections-list" class="space-y-3">
          <div
            :for={collection <- @collections}
            id={"collection-row-#{collection.id}"}
            class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
          >
            <.link
              navigate={~p"/library/collections/#{collection.id}"}
              class="text-base font-semibold text-[#F1F5F9] hover:underline"
            >
              {collection.name}
            </.link>

            <form
              id={"rename-collection-form-#{collection.id}"}
              phx-submit="rename-collection"
              class="mt-2 flex gap-2"
            >
              <input type="hidden" name="collection_id" value={collection.id} />
              <input
                type="text"
                name="name"
                id={"rename-collection-name-#{collection.id}"}
                value={collection.name}
                aria-label={"Rename #{collection.name}"}
                class="rounded-lg border border-[#334155] bg-[#1E293B] px-2 py-1 text-sm text-[#F1F5F9]"
              />
              <button
                type="submit"
                id={"rename-collection-submit-#{collection.id}"}
                class="text-sm font-semibold text-[#F1F5F9] hover:underline"
              >
                Rename
              </button>
            </form>

            <button
              type="button"
              id={"delete-collection-#{collection.id}"}
              phx-click="delete-collection"
              phx-value-id={collection.id}
              data-confirm={
                "Delete \"#{collection.name}\"? This removes the collection and its order. The games themselves stay in your library and on your server."
              }
              class="mt-2 text-sm font-semibold text-[#EF4444] hover:underline"
            >
              Delete
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp member_title(member, assets_by_id) do
    case Map.get(assets_by_id, member.asset_set_id) do
      %{asset_set: %{display_title: title}} -> title
      nil -> "Unknown game"
    end
  end
end
