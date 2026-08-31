defmodule PlaysteadWeb.Api.V1.PlaySessionsController do
  @moduledoc """
  `POST /api/v1/play-sessions` and `DELETE /api/v1/play-sessions/:id`
  (D-07). Mirrors `ExportsController.create/2`'s Idempotency call
  shape; the effect function is a plain insert with no worker enqueue.
  Nothing on the launch path calls this endpoint and no response field
  here affects launch readiness -- the client posts these from an
  outbox after the fact.
  """

  use PlaysteadWeb, :controller

  alias Playstead.{Curation, Idempotency}

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc "POST /api/v1/play-sessions"
  def create(conn, params) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    # P5-WR-004: `parse_datetime/1` used to coerce a malformed value to
    # `nil` indistinguishably from an absent one. For the optional
    # `ended_at` that silently dropped a real client value with no
    # error at all. Distinguish the two here and reject a malformed
    # field outright instead of ever reaching the changeset with a
    # quietly-nulled value.
    with {:ok, started_at} <- parse_datetime_field("started_at", params["started_at"]),
         {:ok, ended_at} <- parse_datetime_field("ended_at", params["ended_at"]) do
      attrs = %{
        id: params["id"] || Ecto.UUID.generate(),
        asset_set_id: params["asset_set_id"],
        started_at: started_at,
        ended_at: ended_at
      }

      effect_fun = fn ->
        case Curation.record_play_session(device.user_id, attrs) do
          {:ok, session} -> {:ok, 201, session_json(session)}
          {:error, reason} -> {:error, reason}
        end
      end

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
    else
      {:error, reason} -> PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  @doc "DELETE /api/v1/play-sessions/:id"
  def delete(conn, %{"id" => id}) do
    device = conn.assigns.current_device
    key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint

    effect_fun = fn ->
      case Curation.delete_play_session(device.user_id, id) do
        {:ok, :removed} -> {:ok, 200, %{}}
        {:error, reason} -> {:error, reason}
      end
    end

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

  defp parse_datetime_field(_field, nil), do: {:ok, nil}

  defp parse_datetime_field(field, str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} ->
        {:ok, dt}

      {:error, reason} ->
        {:error,
         {:validation_failed, "#{field} is not a valid ISO 8601 datetime: #{inspect(reason)}"}}
    end
  end

  defp parse_datetime_field(field, _other) do
    {:error, {:validation_failed, "#{field} must be a string if present"}}
  end

  defp session_json(session) do
    %{
      id: session.id,
      asset_set_id: session.asset_set_id,
      started_at: session.started_at,
      ended_at: session.ended_at
    }
  end
end
