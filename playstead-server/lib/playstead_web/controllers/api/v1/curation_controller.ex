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
