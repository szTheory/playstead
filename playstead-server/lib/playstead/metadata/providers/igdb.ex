defmodule Playstead.Metadata.Providers.IGDB do
  @moduledoc "Fixed-host IGDB v4 game-title search; results remain suggestions, never ROM identity."
  @behaviour Playstead.Metadata.Provider

  alias Playstead.Metadata.ProviderPolicy

  @endpoint "https://api.igdb.com/v4/games"
  @max_title_bytes 160
  @max_response_bytes 1_048_576
  @max_results 10
  @platforms %{
    "gb" => {33, "Game Boy"},
    "gbc" => {22, "Game Boy Color"},
    "gba" => {24, "Game Boy Advance"}
  }

  def name, do: "igdb"
  def version, do: "v4"
  def credentials_ready?, do: match?({:ok, _}, credentials([]))

  def search(title, system, opts \\ []) do
    with {:ok, title} <- validate_title(title),
         {:ok, {platform_id, platform_name}} <- Map.fetch(@platforms, system),
         {:ok, credentials} <- credentials(opts),
         {:ok, response} <-
           transport(opts).post(
             @endpoint,
             headers(credentials),
             query(title, platform_id),
             request_options(opts)
           ),
         {:ok, rows} <- response_rows(response) do
      {:ok,
       rows
       |> Enum.take(@max_results)
       |> Enum.map(&candidate(&1, title, platform_id, platform_name))
       |> Enum.reject(&is_nil/1)}
    else
      {:error, _} = error -> error
      _ -> {:error, :unsupported_system}
    end
  end

  defp validate_title(title) when is_binary(title) do
    normalized = String.trim(title)

    if String.valid?(normalized) and byte_size(normalized) in 1..@max_title_bytes and
         not String.contains?(normalized, ["\"", "\\", ";", "\n", "\r"]) do
      {:ok, normalized}
    else
      {:error, :invalid_title}
    end
  end

  defp validate_title(_), do: {:error, :invalid_title}

  defp credentials(opts) do
    client_id = Keyword.get(opts, :client_id, Application.get_env(:playstead, :igdb_client_id))

    access_token =
      Keyword.get(opts, :access_token, Application.get_env(:playstead, :igdb_access_token))

    if present?(client_id) and present?(access_token),
      do: {:ok, {client_id, access_token}},
      else: {:error, :credentials_unavailable}
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp headers({client_id, access_token}) do
    [
      {"accept", "application/json"},
      {"client-id", client_id},
      {"authorization", "Bearer " <> access_token},
      {"content-type", "text/plain"}
    ]
  end

  defp query(title, platform_id) do
    ~s(search "#{title}"; fields id,name,summary,platforms.id,platforms.name,cover.image_id,screenshots.image_id; where platforms = #{platform_id}; limit 10;)
  end

  defp transport(opts),
    do: Keyword.get(opts, :transport, Playstead.Metadata.Providers.IGDB.ReqTransport)

  defp request_options(opts),
    do: [
      redirect: false,
      retry: false,
      receive_timeout: 5_000,
      connect_timeout: 3_000,
      max_response_bytes: @max_response_bytes,
      test_pid: opts[:test_pid]
    ]

  defp response_rows(%Req.Response{status: 200, body: rows}) when is_list(rows), do: {:ok, rows}

  defp response_rows(%Req.Response{status: 200, body: body})
       when is_binary(body) and byte_size(body) <= @max_response_bytes do
    case Jason.decode(body) do
      {:ok, rows} when is_list(rows) -> {:ok, rows}
      _ -> {:error, :invalid_provider_response}
    end
  end

  defp response_rows(%Req.Response{status: 200}), do: {:error, :provider_response_too_large}

  defp response_rows(%Req.Response{status: 429, headers: headers}),
    do: {:error, {:retry_after, retry_after(headers)}}

  defp response_rows(%Req.Response{status: status}) when status in 500..599,
    do: {:error, :provider_unavailable}

  defp response_rows(%Req.Response{}), do: {:error, :provider_rejected}
  defp response_rows(_), do: {:error, :provider_unavailable}

  defp retry_after(headers) do
    case headers |> Map.get("retry-after", ["1"]) |> List.first() |> Integer.parse() do
      {seconds, _} -> min(3_600, max(1, seconds))
      _ -> 1
    end
  end

  defp candidate(
         %{"id" => id, "name" => title, "platforms" => platforms} = row,
         requested,
         platform_id,
         platform_name
       )
       when is_integer(id) and is_binary(title) and is_list(platforms) do
    exact_title = normalize(title) == normalize(requested)
    matching_platform = Enum.any?(platforms, &(&1["id"] == platform_id))

    %{
      external_id: id,
      title: String.slice(title, 0, @max_title_bytes),
      provider_description: bounded_summary(Map.get(row, "summary")),
      platform_id: platform_id,
      platform: platform_name,
      provider: name(),
      provider_version: version(),
      confidence: if(exact_title and matching_platform, do: :high, else: :low),
      match_kind: :suggestion,
      attribution: ProviderPolicy.attribution(),
      terms_url: ProviderPolicy.terms_url(),
      policy_revision: ProviderPolicy.revision(),
      media_references: media_references(row),
      license_expires_at: nil,
      cache_expires_at:
        DateTime.utc_now()
        |> DateTime.truncate(:second)
        |> DateTime.add(ProviderPolicy.transient_cache_seconds(), :second)
    }
  end

  defp candidate(_, _, _, _), do: nil

  defp media_references(row) do
    cover = get_in(row, ["cover", "image_id"])

    screenshots =
      row |> Map.get("screenshots", []) |> List.wrap() |> Enum.map(&Map.get(&1, "image_id"))

    cover_ref =
      if is_binary(cover), do: [%{image_id: cover, size: "cover_big", role: "cover"}], else: []

    screenshot_refs =
      screenshots
      |> Enum.filter(&is_binary/1)
      |> Enum.take(8)
      |> Enum.map(&%{image_id: &1, size: "screenshot_med", role: "screenshot"})

    %{images: cover_ref ++ screenshot_refs}
  end

  defp bounded_summary(summary) when is_binary(summary) do
    if String.valid?(summary), do: String.slice(summary, 0, 65_536), else: nil
  end

  defp bounded_summary(_), do: nil

  defp normalize(value), do: value |> String.normalize(:nfc) |> String.downcase() |> String.trim()
end

defmodule Playstead.Metadata.Providers.IGDB.ReqTransport do
  @moduledoc false
  @max_response_bytes 1_048_576

  def post(url, headers, body, opts) do
    if url != "https://api.igdb.com/v4/games" or URI.parse(url).host != "api.igdb.com" do
      {:error, :invalid_provider_endpoint}
    else
      collector = fn {:data, chunk}, {req, resp} ->
        accumulated = Map.get(resp.private, :igdb_body, <<>>)

        if byte_size(accumulated) + byte_size(chunk) > @max_response_bytes do
          {:halt, {req, put_in(resp.private[:igdb_too_large], true)}}
        else
          {:cont, {req, put_in(resp.private[:igdb_body], accumulated <> chunk)}}
        end
      end

      case Req.post(url,
             headers: headers,
             body: body,
             redirect: false,
             retry: false,
             receive_timeout: opts[:receive_timeout],
             connect_options: [timeout: opts[:connect_timeout]],
             into: collector,
             decode_body: false
           ) do
        {:ok, %Req.Response{private: %{igdb_too_large: true}}} ->
          {:error, :provider_response_too_large}

        {:ok, %Req.Response{} = response} ->
          {:ok, %{response | body: Map.get(response.private, :igdb_body, <<>>)}}

        {:error, _} ->
          {:error, :provider_unavailable}
      end
    end
  rescue
    _ -> {:error, :provider_unavailable}
  end
end
