defmodule Playstead.Metadata.Providers.LocalTestStub do
  @moduledoc false
  require Logger
  @endpoint "https://api.igdb.com/v4/games"

  def post(@endpoint, _headers, query, opts) do
    # mac_ci-only fixed response through the production IGDB adapter. This
    # function performs no HTTP request and accepts no caller-controlled host.
    Logger.info("metadata_test_provider_request")
    if pid = opts[:test_pid], do: send(pid, {:metadata_test_provider_request, query})

    title =
      Regex.run(~r/search "([^"\\]+)";/, query, capture: :all_but_first) |> List.first() ||
        "Fixture Game"

    platform =
      Regex.run(~r/platforms = (\d+);/, query, capture: :all_but_first) |> List.first() || "24"

    platform = String.to_integer(platform)

    platform_name =
      if platform == 33,
        do: "Game Boy",
        else: if(platform == 22, do: "Game Boy Color", else: "Game Boy Advance")

    {:ok,
     %Req.Response{
       status: 200,
       body: [
         %{
           "id" => 7409,
           "name" => title,
           "summary" => "Local deterministic provider fixture.",
           "platforms" => [%{"id" => platform, "name" => platform_name}]
         }
       ]
     }}
  end

  def post(_url, _headers, _query, _opts), do: {:error, :provider_rejected}
end
