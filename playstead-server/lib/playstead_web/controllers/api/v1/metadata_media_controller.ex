defmodule PlaysteadWeb.Api.V1.MetadataMediaController do
  @moduledoc "Authenticated upload and retrieval of private metadata media."
  use PlaysteadWeb, :controller
  alias Playstead.{Idempotency, Metadata.PrivateMedia}

  @chunk_size 1_048_576
  @max_upload 20 * 1024 * 1024

  def create(conn, %{"asset_set_id" => asset_set_id}) do
    mime =
      conn
      |> get_req_header("content-type")
      |> List.first("")
      |> String.split(";")
      |> hd()
      |> String.trim()

    case read_bounded(conn, []) do
      {:ok, bytes, conn} ->
        conn = PlaysteadWeb.Plugs.Idempotency.call(conn, [])
        if conn.halted, do: conn, else: upload(conn, asset_set_id, bytes, mime)

      {:error, :too_large, conn} ->
        conn |> put_resp_header("connection", "close") |> Plug.Conn.send_resp(413, "")

      {:error, _reason, conn} ->
        conn |> Plug.Conn.send_resp(400, "")
    end
  end

  defp upload(conn, asset_set_id, bytes, mime) do
    device = conn.assigns.current_device
    expected_sha256 = conn.assigns.expected_sha256
    declared_length = conn.assigns.declared_length
    actual_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    effect = fn ->
      if byte_size(bytes) != declared_length or actual_sha256 != expected_sha256 do
        {:error, :digest_mismatch}
      else
        case PrivateMedia.create(device.user_id, asset_set_id, bytes, mime) do
          {:ok, item} -> {:ok, 201, item_json(item)}
          {:error, reason} -> {:error, reason}
        end
      end
    end

    case Idempotency.execute(
           device.id,
           conn.assigns.idempotency_key,
           conn.assigns.idempotency_fingerprint,
           effect
         ) do
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

      {:error, :digest_mismatch} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "media_digest_mismatch"})

      {:error, :media_limit_reached} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "media_limit_reached"})

      {:error, :not_found} ->
        not_found(conn)

      {:error, _reason} ->
        conn |> put_status(:unprocessable_entity) |> json(%{error: "invalid_media"})
    end
  end

  def show_original(conn, %{"asset_set_id" => set_id, "media_id" => media_id}) do
    serve(conn, set_id, media_id, :original)
  end

  def show_derived(conn, %{"asset_set_id" => set_id, "media_id" => media_id}) do
    serve(conn, set_id, media_id, :derived)
  end

  def delete_derived(conn, %{"asset_set_id" => set_id, "media_id" => media_id}) do
    device = conn.assigns.current_device

    effect = fn ->
      case PrivateMedia.remove_derived(device.user_id, set_id, media_id) do
        {:ok, item} -> {:ok, 200, item_json(item)}
        {:error, reason} -> {:error, reason}
      end
    end

    case Idempotency.execute(
           device.id,
           conn.assigns.idempotency_key,
           conn.assigns.idempotency_fingerprint,
           effect
         ) do
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

      {:error, _} ->
        not_found(conn)
    end
  end

  defp serve(conn, set_id, media_id, kind) do
    user_id = conn.assigns.current_device.user_id

    result =
      if kind == :original,
        do: PrivateMedia.fetch_original(user_id, set_id, media_id),
        else: PrivateMedia.fetch_derived(user_id, set_id, media_id)

    case result do
      {:ok, bytes} ->
        conn
        |> put_resp_content_type(
          if(kind == :derived, do: "image/png", else: "application/octet-stream")
        )
        |> put_resp_header("cache-control", "private, no-store")
        |> send_resp(200, bytes)

      _ ->
        not_found(conn)
    end
  end

  defp read_bounded(conn, chunks, size \\ 0) do
    case Plug.Conn.read_body(conn, length: @chunk_size) do
      {:ok, chunk, conn} when size + byte_size(chunk) <= @max_upload ->
        {:ok, [chunk | chunks] |> Enum.reverse() |> IO.iodata_to_binary(), conn}

      {:more, chunk, conn} when size + byte_size(chunk) <= @max_upload ->
        read_bounded(conn, [chunk | chunks], size + byte_size(chunk))

      {_status, _chunk, conn} ->
        {:error, :too_large, conn}

      {:error, reason} ->
        {:error, reason, conn}
    end
  end

  defp item_json(item) do
    %{
      id: item.id,
      asset_set_id: item.asset_set_id,
      original_sha256: item.original_sha256,
      original_size_bytes: item.original_size_bytes,
      original_mime: item.original_mime,
      derived_sha256: item.derived_sha256,
      derived_size_bytes: item.derived_size_bytes,
      created_at: item.inserted_at
    }
  end

  defp not_found(conn),
    do:
      PlaysteadWeb.Problem.send_problem(
        conn,
        404,
        :not_found,
        "The requested media was not found."
      )
end
