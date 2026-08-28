defmodule PlaysteadWeb.Api.V1.BlobsController do
  @moduledoc """
  `GET /api/v1/blobs/:sha256` (D-10). Authorisation is by whether the
  calling user has a `source_file` referencing that blob — never by the
  hash alone, which would make this endpoint a cross-user read oracle
  (D-13). Full resumable range semantics are Phase 3's CACH-01 work;
  this streams the whole file.
  """

  use PlaysteadWeb, :controller

  import Ecto.Query

  alias Playstead.Import.SourceFile
  alias Playstead.Repo

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  def show(conn, %{"sha256" => sha256}) do
    device = conn.assigns.current_device

    with true <- authorized?(device.user_id, sha256),
         true <- playable?(device.user_id, sha256),
         {:ok, stream} <- Playstead.Blobs.stream(sha256) do
      conn
      |> put_resp_header("etag", sha256)
      |> put_resp_content_type("application/octet-stream")
      |> send_chunked(200)
      |> stream_chunks(stream)
    else
      false -> {:error, :not_found}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp authorized?(user_id, sha256) do
    from(sf in SourceFile,
      join: b in assoc(sf, :blob),
      where: sf.user_id == ^user_id and b.sha256 == ^sha256
    )
    |> Repo.exists?()
  end

  # D-28: a quarantined blob is never served as playable content until
  # this user has their own release decision recorded — the machine
  # verdict on the shared bytes is never enough on its own.
  defp playable?(user_id, sha256) do
    case Playstead.Blobs.get_by_sha256(sha256) do
      nil -> false
      blob -> not Playstead.Blobs.quarantined?(blob) or Playstead.Blobs.released_for_user?(user_id, blob.id)
    end
  end

  defp stream_chunks(conn, stream) do
    Enum.reduce_while(stream, conn, fn chunk, conn ->
      case Plug.Conn.chunk(conn, chunk) do
        {:ok, conn} -> {:cont, conn}
        {:error, _reason} -> {:halt, conn}
      end
    end)
  end
end
