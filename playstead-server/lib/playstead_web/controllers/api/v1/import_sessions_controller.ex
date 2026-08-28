defmodule PlaysteadWeb.Api.V1.ImportSessionsController do
  @moduledoc """
  Read-only `/api/v1/import-sessions` endpoints (D-10, D-13, T-02-38).
  `conn.assigns.current_device` (set by `PlaysteadWeb.Plugs.DeviceAuth`)
  scopes every read to its owning user — a session or receipt belonging
  to another user is never distinguishable from one that does not
  exist. Receipts page by an opaque position cursor, never by a page
  number (the same reasoning `PlaysteadWeb.Api.V1.ChangesController`
  follows): a numbered page over a growing table silently skips or
  repeats rows.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Import
  alias Playstead.Import.Progress

  def index(conn, _params) do
    device = conn.assigns.current_device
    sessions = Import.list_sessions(device.user_id)
    json(conn, %{sessions: Enum.map(sessions, &session_json/1)})
  end

  def show(conn, %{"id" => id}) do
    case Import.get_owned_session(conn.assigns.current_device.user_id, id) do
      nil -> not_found(conn)
      session -> json(conn, session_json(session))
    end
  end

  def receipts(conn, %{"id" => id} = params) do
    device = conn.assigns.current_device

    case Import.get_owned_session(device.user_id, id) do
      nil ->
        not_found(conn)

      _session ->
        opts = [after_cursor: Map.get(params, "cursor")]
        result = Import.list_session_receipts(device.user_id, id, opts)

        json(conn, %{
          receipts: Enum.map(result.entries, &receipt_json/1),
          next_cursor: result.next_cursor
        })
    end
  end

  defp not_found(conn) do
    PlaysteadWeb.Problem.send_problem(conn, 404, :not_found, "This session could not be found.")
  end

  defp session_json(session) do
    progress = Progress.summary(session)

    %{
      id: session.id,
      state: session.state,
      requested_control: session.requested_control,
      file_count: session.file_count,
      total_bytes: session.total_bytes,
      files_completed: progress.files_completed,
      bytes_completed: progress.bytes_completed,
      eta_minutes: progress.eta_minutes,
      counts_by_outcome: session.counts_by_outcome
    }
  end

  defp receipt_json(receipt) do
    %{
      id: receipt.id,
      outcome: receipt.outcome,
      reason: receipt.reason,
      sha256: receipt.sha256,
      size_bytes: receipt.size_bytes,
      inserted_at: receipt.inserted_at
    }
  end
end
