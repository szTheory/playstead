defmodule Playstead.Metadata.SyncContractTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Sync.Cursor
  alias PlaysteadWeb.Api.V1.MetadataOpenAPI

  test "published OpenAPI and checked examples match the current metadata payload contract", %{
    conn: conn
  } do
    fixture =
      "../../fixtures/metadata_api_v1.json"
      |> Path.expand(__DIR__)
      |> File.read!()
      |> Jason.decode!()

    document =
      conn
      |> get("/api/v1/openapi.json")
      |> json_response(200)

    examples = MetadataOpenAPI.examples() |> Jason.encode!() |> Jason.decode!()
    assert Map.take(fixture, Map.keys(examples)) == examples
    assert document["x-examples"] == examples
    assert document["paths"]["/api/v1/metadata/{asset_set_id}"]["post"]
    assert document["components"]["schemas"]["MetadataSelection"]["properties"]["conflicts"]
    assert document["paths"]["/api/v1/metadata/{asset_set_id}/media"]["post"]
    assert document["paths"]["/api/v1/metadata/{asset_set_id}/provider/consent"]["delete"]
    revoke = document["paths"]["/api/v1/metadata/{asset_set_id}/provider/consent"]["delete"]
    revoke_response = revoke["responses"]["200"]
    revoke_schema = document["components"]["schemas"]["ProviderConsentRevocationResponse"]

    assert revoke_response["content"]["application/json"]["schema"]["$ref"] ==
             "#/components/schemas/ProviderConsentRevocationResponse"

    assert revoke_schema["required"] == ["enabled", "revision"]

    assert revoke_schema["properties"]["cache_cleanup"]["properties"]["status"]["enum"] == [
             "failed"
           ]

    assert revoke_response["content"]["application/json"]["examples"]["clean"]["value"] ==
             fixture["provider_consent_revocation_response"]

    assert revoke_response["content"]["application/json"]["examples"]["cleanup_pending"]["value"] ==
             fixture["provider_consent_revocation_partial_response"]

    assert examples["provider_consent_revocation_response"]["enabled"] == false

    assert examples["provider_consent_revocation_partial_response"]["cache_cleanup"] == %{
             "status" => "failed",
             "retryable" => true
           }

    assert document["paths"]["/api/v1/metadata/{asset_set_id}/provider/enrichment"]["post"]

    capabilities = conn |> get("/api/v1/capabilities") |> json_response(200)
    assert capabilities == fixture["capability_response"]

    legacy = fixture["legacy_mac_metadata_selection"]

    assert Map.keys(legacy) |> Enum.sort() ==
             ~w(asset_set_id deleted_at description revision type version)

    assert legacy["type"] == "description"
  end

  test "journal and same-cursor snapshot preserve unresolved alternatives", %{conn: conn} do
    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)
    asset_set = asset_set_fixture(owner.user.id)

    first = metadata_mutation(conn, token, asset_set.id, "first", 0, "First")
    assert first.status == 201

    before_conflict =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/snapshot")
      |> json_response(200)

    conflict = metadata_mutation(conn, token, asset_set.id, "conflict", 0, "Second")
    assert conflict.status == 409

    changes =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/changes")
      |> json_response(200)

    entry =
      changes["entries"]
      |> Enum.filter(fn entry ->
        entry["entity_kind"] == "metadata" and entry["entity_id"] == asset_set.id
      end)
      |> List.last()

    journal_conflicts = entry["payload"]["conflicts"]

    assert [
             %{
               "current_alternative" => %{"value" => "First"},
               "incoming_alternative" => %{"value" => "Second"}
             }
           ] = journal_conflicts

    snapshot =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/snapshot")
      |> json_response(200)

    assert {:ok, _cursor} = Cursor.decode(snapshot["cursor"])

    assert [%{"conflicts" => ^journal_conflicts}] =
             Enum.filter(snapshot["metadata"], &(&1["asset_set_id"] == asset_set.id))

    reset =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/snapshot?cursor=#{URI.encode(snapshot["cursor"])}")
      |> json_response(200)

    assert reset["cursor"] == snapshot["cursor"]
    assert reset["metadata"] == snapshot["metadata"]

    pinned_after_later_write =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/snapshot?cursor=#{URI.encode(before_conflict["cursor"])}")
      |> json_response(200)

    assert pinned_after_later_write["cursor"] == before_conflict["cursor"]

    assert [%{"selections" => %{"title" => "First"}, "conflicts" => []}] =
             Enum.filter(
               pinned_after_later_write["metadata"],
               &(&1["asset_set_id"] == asset_set.id)
             )
  end

  defp metadata_mutation(conn, token, asset_set_id, suffix, base_revision, value) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(
      "idempotency-key",
      "sync-contract-#{suffix}-#{System.unique_integer([:positive])}"
    )
    |> post("/api/v1/metadata/#{asset_set_id}", %{
      "field" => "title",
      "value" => value,
      "base_revision" => base_revision
    })
  end
end
