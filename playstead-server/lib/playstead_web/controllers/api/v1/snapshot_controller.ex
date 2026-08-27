defmodule PlaysteadWeb.Api.V1.SnapshotController do
  @moduledoc """
  `GET /api/v1/snapshot` — transactional snapshot-plus-as-of-cursor
  (PROT-05, D-21). Device-authenticated. Read-only: writes no rows.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Sync
  alias Playstead.Sync.Cursor

  def show(conn, params) do
    device = conn.assigns.current_device
    after_id = Map.get(params, "after_id")

    case pinned_as_of(params) do
      {:ok, as_of} ->
        {:ok, result} = Sync.snapshot(device.user_id, after_id: after_id, as_of: as_of)

        json(conn, %{
          entries: Enum.map(result.entries, &render_entry/1),
          cursor: result.cursor,
          has_more: result.has_more,
          next_after_id: result.next_after_id
        })

      :error ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          400,
          :cursor_invalid,
          "The provided cursor could not be verified."
        )
    end
  end

  defp pinned_as_of(%{"cursor" => cursor}) when is_binary(cursor) do
    case Cursor.decode(cursor) do
      {:ok, seq} -> {:ok, seq}
      :error -> :error
    end
  end

  defp pinned_as_of(_params), do: {:ok, nil}

  defp render_entry(%{entity_kind: kind, entity_id: id, operation: op, payload: payload}) do
    %{entity_kind: kind, entity_id: id, operation: op, payload: payload}
  end
end
