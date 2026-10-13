defmodule Playstead.Metadata.IGDBTest do
  use ExUnit.Case, async: true

  alias Playstead.Metadata.Providers.IGDB

  defmodule TransportSpy do
    def post(url, headers, body, opts) do
      send(opts[:test_pid], {:request, url, headers, body, opts})

      {:ok,
       %Req.Response{
         status: 200,
         body: [
           %{
             "id" => 42,
             "name" => "Metroid Fusion",
             "summary" => "An interstellar adventure.",
             "platforms" => [%{"id" => 24, "name" => "Game Boy Advance"}]
           }
         ]
       }}
    end
  end

  test "sends only escaped title and mapped system to fixed IGDB endpoint and bounds evidence" do
    assert {:ok, [candidate]} =
             IGDB.search("Metroid Fusion", "gba",
               client_id: "test-client",
               access_token: "test-token",
               transport: TransportSpy,
               test_pid: self()
             )

    assert_receive {:request, "https://api.igdb.com/v4/games", headers, body, opts}
    assert {"client-id", "test-client"} in headers
    assert {"authorization", "Bearer test-token"} in headers

    assert body ==
             ~s(search "Metroid Fusion"; fields id,name,summary,platforms.id,platforms.name,cover.image_id,screenshots.image_id; where platforms = 24; limit 10;)

    assert opts[:redirect] == false
    assert opts[:retry] == false
    assert candidate.provider == "igdb"
    assert candidate.provider_version == "v4"
    assert candidate.external_id == 42
    assert candidate.title == "Metroid Fusion"
    assert candidate.provider_description == "An interstellar adventure."
    assert candidate.confidence == :high
    assert candidate.match_kind == :suggestion
    assert candidate.attribution =~ "IGDB"
    assert candidate.terms_url == "https://legal.twitch.com/legal/developer-agreement/"
    assert candidate.policy_revision
    assert candidate.license_expires_at == nil
  end

  test "hash lookup is absent from the provider boundary" do
    Code.ensure_loaded!(IGDB)
    refute function_exported?(IGDB, :lookup_hash, 1)
    refute function_exported?(IGDB, :lookup_hash, 2)

    refute Enum.any?(Playstead.Metadata.Provider.behaviour_info(:callbacks), fn {name, _} ->
             name == :lookup_hash
           end)

    refute_receive {:request, _, _, _, _}
  end

  test "unknown system and query injection are rejected before transport" do
    assert {:error, :unsupported_system} =
             IGDB.search("Metroid", "unknown-system", transport: TransportSpy, test_pid: self())

    assert {:error, :invalid_title} =
             IGDB.search("\"; where id > 0;", "gba", transport: TransportSpy, test_pid: self())

    refute_receive {:request, _, _, _, _}
  end
end
