defmodule PlaysteadWeb.Api.V1.SaveHistoryController do
  @moduledoc """
  `GET /api/v1/saves/lines/:id/history` -- a read-only view of one save
  line's revisions and its derived branch heads (D-14), strictly scoped
  to the calling device's user (`Playstead.Saves.get_history/2`).
  Follows `CurationController`'s list-action half: no
  `:idempotency` pipeline, since reading is not mutating.
  """

  use PlaysteadWeb, :controller

  alias Playstead.Saves

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  @doc """
  A line outside the caller's scope is a 404, never a 403 that would
  confirm the line exists for someone else.
  """
  def show(conn, %{"id" => save_line_id}) do
    device = conn.assigns.current_device

    with {:ok, %{revisions: revisions, heads: heads}} <-
           Saves.get_history(device.user_id, save_line_id) do
      json(conn, %{
        revisions: Enum.map(revisions, &revision_json/1),
        heads: Enum.map(heads, & &1.id)
      })
    end
  end

  defp revision_json(revision) do
    %{
      id: revision.id,
      save_line_id: revision.save_line_id,
      parent_revision_id: revision.parent_revision_id,
      blob_sha256: revision.blob_sha256,
      size_bytes: revision.size_bytes,
      origin_device_id: revision.origin_device_id,
      recorded_at: revision.recorded_at,
      base_sha256: revision.base_sha256,
      base_matched: revision.base_matched,
      confirm_count: revision.confirm_count,
      last_confirmed_at: revision.last_confirmed_at
    }
  end
end
