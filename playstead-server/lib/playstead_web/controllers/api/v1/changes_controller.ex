defmodule PlaysteadWeb.Api.V1.ChangesController do
  @moduledoc """
  `GET /api/v1/changes` — the resumable change feed (PROT-05, D-21).
  Device-authenticated: `conn.assigns.current_device` is set by
  `PlaysteadWeb.Plugs.DeviceAuth`. Read-only: never writes, never
  advances a server-held position — the client's `cursor` query
  parameter is the only position the server ever consults.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Sync

  def index(conn, params) do
    device = conn.assigns.current_device
    cursor = Map.get(params, "cursor")

    case Sync.changes_after(device.user_id, cursor) do
      {:ok, %{entries: entries, cursor: next_cursor, has_more: has_more}} ->
        json(conn, %{
          entries: Enum.map(entries, &render_entry/1),
          cursor: next_cursor,
          has_more: has_more
        })

      {:error, :cursor_invalid} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          400,
          :cursor_invalid,
          "The provided cursor could not be verified."
        )

      {:error, :cursor_expired} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          410,
          :cursor_expired,
          "This cursor is older than the server's retention window. Take a fresh snapshot and resume from its cursor.",
          %{detail_url: "/api/v1/snapshot"}
        )
    end
  end

  defp render_entry(entry) do
    %{
      seq: entry.seq,
      entity_kind: entry.entity_kind,
      entity_id: entry.entity_id,
      operation: entry.operation,
      payload: entry.payload
    }
  end
end
