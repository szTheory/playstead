defmodule PlaysteadWeb.Api.V1.CurationController do
  @moduledoc """
  `/api/v1/curation/*` — per-row idempotent curation intents (D-07…
  D-10). Every mutating action here follows `ExportsController.create/2`'s
  `Idempotency.execute/4` call shape verbatim: read `current_device`,
  `idempotency_key`, and `idempotency_fingerprint` from assigns, build
  an `effect_fun` that calls `Playstead.Curation`, then handle
  `{:ok, status, body}` / `{:error, :conflict}` / any other error
  through the fallback controller.
  """

  use PlaysteadWeb, :controller

  alias Playstead.{Curation, Idempotency}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc """
  PUT /api/v1/curation/favorites/:asset_set_id — favorites the named
  asset set for the calling device's user. Idempotent: repeating the
  intent (even with a different client-supplied `id`) converges on one
  row via the `(user_id, asset_set_id)` unique index.
  """
  def create_favorite(conn, %{"asset_set_id" => asset_set_id} = params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    id = params["id"] || Ecto.UUID.generate()

    effect_fun = fn ->
      case Curation.add_favorite(device.user_id, id, asset_set_id) do
        {:ok, favorite} -> {:ok, 200, favorite_json(favorite)}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "DELETE /api/v1/curation/favorites/:asset_set_id"
  def delete_favorite(conn, %{"asset_set_id" => asset_set_id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Curation.remove_favorite(device.user_id, asset_set_id) do
        {:ok, :removed} -> {:ok, 200, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  ## Collections (D-10)

  @doc "POST /api/v1/curation/collections"
  def create_collection(conn, params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    id = params["id"] || Ecto.UUID.generate()
    name = params["name"] || ""

    effect_fun = fn ->
      case Curation.create_collection(device.user_id, id, name) do
        {:ok, collection} -> {:ok, 201, collection_json(collection)}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "PATCH /api/v1/curation/collections/:id"
  def rename_collection(conn, %{"id" => collection_id} = params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    name = params["name"] || ""

    effect_fun = fn ->
      case Curation.rename_collection(device.user_id, collection_id, name) do
        {:ok, collection} -> {:ok, 200, collection_json(collection)}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "DELETE /api/v1/curation/collections/:id"
  def delete_collection(conn, %{"id" => collection_id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Curation.delete_collection(device.user_id, collection_id) do
        {:ok, :removed} -> {:ok, 200, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "GET /api/v1/curation/collections"
  def list_collections(conn, _params) do
    device = conn.assigns.current_device

    json(conn, %{
      collections: Enum.map(Curation.list_collections(device.user_id), &collection_json/1)
    })
  end

  @doc "GET /api/v1/curation/collections/:id/members"
  def list_collection_members(conn, %{"id" => collection_id}) do
    device = conn.assigns.current_device

    case Curation.list_collection_members(device.user_id, collection_id) do
      {:ok, members} -> json(conn, %{members: Enum.map(members, &member_json/1)})
      {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc "PUT /api/v1/curation/collections/:id/members/:asset_set_id"
  def add_collection_member(
        conn,
        %{"id" => collection_id, "asset_set_id" => asset_set_id} = params
      ) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    id = params["id_for_member"] || Ecto.UUID.generate()

    effect_fun = fn ->
      case Curation.add_collection_member(device.user_id, collection_id, id, asset_set_id) do
        {:ok, member} -> {:ok, 200, member_json(member)}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "DELETE /api/v1/curation/collections/:id/members/:asset_set_id"
  def remove_collection_member(conn, %{"id" => collection_id, "asset_set_id" => asset_set_id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Curation.remove_collection_member(device.user_id, collection_id, asset_set_id) do
        {:ok, :removed} -> {:ok, 200, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc """
  PATCH /api/v1/curation/collections/:id/members/:asset_set_id/position
  — the move intent names its own neighbours, never a whole ordered
  list (D-09).
  """
  def move_collection_member(
        conn,
        %{"id" => collection_id, "asset_set_id" => asset_set_id} = params
      ) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    with {:ok, neighbours} <- parse_neighbours(params) do
      effect_fun = fn ->
        case Curation.move_collection_member(
               device.user_id,
               collection_id,
               asset_set_id,
               neighbours
             ) do
          {:ok, member} -> {:ok, 200, member_json(member)}
          {:error, reason} -> {:error, reason}
        end
      end

      run_idempotent(conn, device, key, fingerprint, effect_fun)
    else
      {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  ## The play queue (D-07/D-09)

  @doc "PUT /api/v1/curation/queue/:asset_set_id"
  def enqueue(conn, %{"asset_set_id" => asset_set_id} = params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    id = params["id"] || Ecto.UUID.generate()

    effect_fun = fn ->
      case Curation.enqueue(device.user_id, id, asset_set_id) do
        {:ok, item} -> {:ok, 200, queue_item_json(item)}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "DELETE /api/v1/curation/queue/:asset_set_id"
  def dequeue(conn, %{"asset_set_id" => asset_set_id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Curation.dequeue(device.user_id, asset_set_id) do
        {:ok, :removed} -> {:ok, 200, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

    run_idempotent(conn, device, key, fingerprint, effect_fun)
  end

  @doc "GET /api/v1/curation/queue"
  def list_queue(conn, _params) do
    device = conn.assigns.current_device
    json(conn, %{queue: Enum.map(Curation.list_queue(device.user_id), &queue_item_json/1)})
  end

  @doc "PATCH /api/v1/curation/queue/:asset_set_id/position"
  def move_queue_item(conn, %{"asset_set_id" => asset_set_id} = params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    with {:ok, neighbours} <- parse_neighbours(params) do
      effect_fun = fn ->
        case Curation.move_queue_item(device.user_id, asset_set_id, neighbours) do
          {:ok, item} -> {:ok, 200, queue_item_json(item)}
          {:error, reason} -> {:error, reason}
        end
      end

      run_idempotent(conn, device, key, fingerprint, effect_fun)
    else
      {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  # D-09: the unit of truth is one row's position, named by its two
  # neighbours -- a client that submits a whole ordered list as truth
  # can silently discard a concurrent offline addition, so any
  # list-shaped body is refused outright rather than accepted and
  # misinterpreted.
  defp parse_neighbours(%{"_json" => list}) when is_list(list) do
    {:error,
     {:validation_failed,
      "A move intent names its own neighbours; a whole ordered list is not accepted."}}
  end

  defp parse_neighbours(params) do
    before_id = params["before_asset_set_id"]
    after_id = params["after_asset_set_id"]

    if is_list(before_id) or is_list(after_id) do
      {:error,
       {:validation_failed,
        "A move intent names its own neighbours; a whole ordered list is not accepted."}}
    else
      {:ok, %{before_asset_set_id: before_id, after_asset_set_id: after_id}}
    end
  end

  defp collection_json(collection) do
    %{id: collection.id, name: collection.name, position: collection.position}
  end

  defp member_json(member) do
    %{id: member.id, asset_set_id: member.asset_set_id, position: member.position}
  end

  defp queue_item_json(item) do
    %{id: item.id, asset_set_id: item.asset_set_id, position: item.position}
  end

  defp run_idempotent(conn, device, key, fingerprint, effect_fun) do
    case Idempotency.execute(device.id, key, fingerprint, effect_fun) do
      {:ok, status, body} ->
        conn |> put_status(status) |> json(body)

      {:error, :conflict} ->
        conn
        |> put_resp_header("retry-after", "1")
        |> PlaysteadWeb.Problem.send_problem(
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )

      {:error, reason} ->
        PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  defp favorite_json(favorite) do
    %{
      id: favorite.id,
      asset_set_id: favorite.asset_set_id,
      inserted_at: favorite.inserted_at
    }
  end
end
