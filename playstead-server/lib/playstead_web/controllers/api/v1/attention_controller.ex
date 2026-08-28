defmodule PlaysteadWeb.Api.V1.AttentionController do
  @moduledoc """
  `GET /api/v1/attention` (cursor-paginated, user-scoped) and
  `POST /api/v1/attention/:id/resolve` (idempotent, D-30). An item
  belonging to another user is refused as not-found rather than
  forbidden, so the endpoint cannot be used to probe for another
  user's items (T-02-41).
  """

  use PlaysteadWeb, :controller

  alias Playstead.Attention
  alias Playstead.Attention.Resolutions
  alias Playstead.Idempotency

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  def index(conn, params) do
    device = conn.assigns.current_device
    page = Attention.list_items_page(device.user_id, after_cursor: params["cursor"])

    json(conn, %{
      items: Enum.map(page.entries, &item_json/1),
      next_cursor: page.next_cursor
    })
  end

  def resolve(conn, %{"id" => id} = params) do
    device = conn.assigns.current_device

    case Attention.get_owned_item(device.user_id, id) do
      nil ->
        {:error, :not_found}

      item ->
        key = conn.assigns.idempotency_key
        fingerprint = conn.assigns.idempotency_fingerprint

        result =
          Idempotency.execute(device.id, key, fingerprint, fn ->
            case apply_resolution(item, device.user_id, params) do
              {:ok, result} -> {:ok, 200, %{status: "ok", result: summarize(result)}}
              {:error, :already_resolved} -> {:ok, 200, %{status: "already_resolved"}}
              {:error, reason} -> {:error, reason}
            end
          end)

        case result do
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
  end

  defp apply_resolution(item, user_id, %{
         "resolution" => "correct_system",
         "system_id" => system_id
       }) do
    Resolutions.correct_system(item, user_id, system_id)
  end

  defp apply_resolution(item, user_id, %{
         "resolution" => "attach_companion",
         "declared_name" => declared_name,
         "blob_id" => blob_id,
         "sha256" => sha256,
         "size_bytes" => size_bytes
       }) do
    meta = %{blob_id: blob_id, sha256: sha256, size_bytes: size_bytes}
    attrs = %{original_name: declared_name, origin: "attach", size_bytes: size_bytes}
    Resolutions.attach_companion(item, user_id, declared_name, attrs, {:existing, meta})
  end

  defp apply_resolution(item, user_id, %{"resolution" => "retain_as_custom"}) do
    Resolutions.retain_as_custom(item, user_id)
  end

  defp apply_resolution(item, user_id, %{"resolution" => "exclude"}) do
    Resolutions.exclude(item, user_id)
  end

  defp apply_resolution(item, user_id, %{"resolution" => "retry"}) do
    Resolutions.retry(item, user_id)
  end

  defp apply_resolution(item, user_id, %{"resolution" => "undo"}) do
    Resolutions.undo(item, user_id)
  end

  defp apply_resolution(_item, _user_id, _params), do: {:error, :invalid_resolution}

  defp summarize(%{item: item} = result) do
    asset_set_id =
      case Map.get(result, :asset_set) do
        %{id: id} -> id
        _ -> nil
      end

    %{item_id: item.id, status: item.status} |> maybe_put(:asset_set_id, asset_set_id)
  end

  defp summarize(_other), do: %{}

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp item_json(item) do
    %{
      id: item.id,
      reason: item.reason,
      status: item.status,
      count: item.count,
      grouping_key: item.grouping_key,
      import_session_id: item.import_session_id,
      source_file_id: item.source_file_id,
      asset_set_id: item.asset_set_id,
      blob_id: item.blob_id,
      evidence: item.evidence,
      inserted_at: item.inserted_at
    }
  end
end
