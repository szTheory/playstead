defmodule Playstead.Metadata.SelectionTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  defmodule ProviderTransport do
    def post(_url, _headers, _body, _opts) do
      {:ok,
       %Req.Response{
         status: 200,
         body: [
           %{
             "id" => 4242,
             "name" => "Provider title",
             "summary" => "Provider description",
             "platforms" => [%{"id" => 24, "name" => "Game Boy Advance"}]
           }
         ]
       }}
    end
  end

  test "explicit metadata mutations require a base revision", %{conn: conn} do
    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)
    asset_set = asset_set_fixture(owner.user.id)

    response =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "metadata-base-#{System.unique_integer([:positive])}")
      |> post("/api/v1/metadata/#{asset_set.id}", %{
        "description" => "A corrected description"
      })

    PlaysteadWeb.ApiCase.assert_problem(response, 422, :validation_failed)
    refute Playstead.Repo.exists?(Playstead.Metadata.Selection)
  end

  test "wire selections reject cache paths and credential fields", %{conn: _conn} do
    owner = user_scope_fixture()
    asset_set = asset_set_fixture(owner.user.id)

    assert {:error, :invalid_metadata_value} =
             Playstead.Metadata.select_field(
               owner.user.id,
               asset_set.id,
               "cover",
               %{"cache_path" => "/private/cache/cover.png"},
               0
             )

    assert {:error, :invalid_metadata_value} =
             Playstead.Metadata.select_field(
               owner.user.id,
               asset_set.id,
               "candidate",
               %{"access_token" => "never-on-wire"},
               0
             )
  end

  test "concurrent edits retain both alternatives until an explicit current-revision choice", %{
    conn: conn
  } do
    owner = user_scope_fixture()
    %{device: first_device, credential_plaintext: token} = device_fixture(owner)
    %{device: resolving_device, credential_plaintext: resolving_token} = device_fixture(owner)
    foreign_owner = user_scope_fixture()
    %{device: foreign_device} = device_fixture(foreign_owner)
    asset_set = asset_set_fixture(owner.user.id)

    first =
      mutation(conn, token, asset_set.id, "first", %{
        "field" => "title",
        "value" => "First title",
        "base_revision" => 0
      })

    assert first.status == 201, first.resp_body
    assert json_response(first, 201)["field_revisions"]["title"] == 1

    conflict =
      mutation(conn, token, asset_set.id, "second", %{
        "field" => "title",
        "value" => "Second title",
        "base_revision" => 0
      })

    assert conflict.status == 409
    conflict_body = json_response(conflict, 409)
    assert conflict_body["current_alternative"]["value"] == "First title"
    assert conflict_body["incoming_alternative"]["value"] == "Second title"

    current =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/metadata/#{asset_set.id}")
      |> json_response(200)

    assert [%{"field" => "title"} = retained] = current["conflicts"]
    conflict_id = retained["id"]
    assert retained["current_alternative"]["value"] == "First title"
    assert retained["incoming_alternative"]["value"] == "Second title"

    assert {:error, :resolution_actor_required} =
             Playstead.Metadata.select_field(
               owner.user.id,
               asset_set.id,
               "title",
               "Second title",
               1
             )

    assert {:error, :invalid_actor_device} =
             Playstead.Metadata.select_field(
               owner.user.id,
               asset_set.id,
               "title",
               "Second title",
               1,
               %{"source" => "user"},
               foreign_device.id
             )

    unresolved_conflict = Playstead.Repo.get!(Playstead.Metadata.Conflict, conflict_id)
    assert is_nil(unresolved_conflict.resolved_at)
    assert is_nil(unresolved_conflict.resolved_by_device_id)

    resolved =
      mutation(conn, resolving_token, asset_set.id, "resolve", %{
        "field" => "title",
        "value" => "Second title",
        "base_revision" => 1,
        "resolved_by_device_id" => first_device.id
      })

    assert resolved.status == 201
    resolved_body = json_response(resolved, 201)
    assert resolved_body["selections"]["title"] == "Second title"
    assert resolved_body["conflicts"] == []

    resolved_conflict = Playstead.Repo.get!(Playstead.Metadata.Conflict, conflict_id)
    assert resolved_conflict.resolved_at
    assert resolved_conflict.resolved_by_device_id == resolving_device.id

    tombstone =
      mutation(conn, token, asset_set.id, "delete-title", %{
        "field" => "title",
        "value" => nil,
        "base_revision" => 2
      })

    assert tombstone.status == 201
    assert json_response(tombstone, 201)["deleted_fields"]["title"] == 3
    refute Map.has_key?(json_response(tombstone, 201)["selections"], "title")
  end

  test "successive offline edits use the selected field revision after other fields advance", %{
    conn: conn
  } do
    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)
    asset_set = asset_set_fixture(owner.user.id)

    assert mutation(conn, token, asset_set.id, "title-a", %{
             "field" => "title",
             "value" => "Title A",
             "base_revision" => 0
           }).status == 201

    assert mutation(conn, token, asset_set.id, "description-d", %{
             "field" => "description",
             "value" => "Description D",
             "base_revision" => 0
           }).status == 201

    assert mutation(conn, token, asset_set.id, "title-b", %{
             "field" => "title",
             "value" => "Title B",
             "base_revision" => 1
           }).status == 201

    final =
      mutation(conn, token, asset_set.id, "title-c", %{
        "field" => "title",
        "value" => "Title C",
        "base_revision" => 2
      })

    assert final.status == 201, final.resp_body
    body = json_response(final, 201)
    assert body["selections"]["title"] == "Title C"
    assert body["field_revisions"]["title"] == 3
    assert body["field_revisions"]["description"] == 1
    assert body["revision"] == 4
    assert body["conflicts"] == []
  end

  test "provider refresh leaves corrections intact and field reset requires current evidence", %{
    conn: conn
  } do
    owner = user_scope_fixture()
    asset_set = asset_set_fixture(owner.user.id, %{system_id: "gba"})

    assert {:ok, _} =
             Playstead.Metadata.select_field(
               owner.user.id,
               asset_set.id,
               "title",
               "Owner title",
               0
             )

    assert {:ok, _consent} =
             Playstead.Metadata.Consent.enable(owner.user.id, asset_set.id, %{
               "title" => asset_set.display_title,
               "system" => asset_set.system_id,
               "disclosure_revision" => Playstead.Metadata.Consent.disclosure_revision()
             })

    assert {:ok, [evidence]} =
             Playstead.Metadata.Consent.search(owner.user.id, asset_set.id,
               client_id: "test-client",
               access_token: "test-token",
               transport: ProviderTransport
             )

    assert {:ok, after_refresh} = Playstead.Metadata.get_description(owner.user.id, asset_set.id)
    assert after_refresh.selections["title"] == "Owner title"
    refute Map.has_key?(after_refresh.selections, "candidate")

    {:ok, changes} = Playstead.Sync.changes_after(owner.user.id, nil)

    refreshed_payload =
      changes.entries
      |> Enum.filter(&(&1.entity_kind == "metadata" and &1.entity_id == asset_set.id))
      |> List.last()
      |> Map.fetch!(:payload)

    assert refreshed_payload["evidence"][evidence.id]["attribution"] == evidence.attribution
    refute Map.has_key?(refreshed_payload["evidence"][evidence.id], "cache_path")
    refute Map.has_key?(refreshed_payload["evidence"][evidence.id], "access_token")

    {:ok, snapshot} = Playstead.Sync.snapshot(owner.user.id)

    [metadata_snapshot] =
      Enum.filter(snapshot.metadata, &(&1["asset_set_id"] == asset_set.id))

    assert metadata_snapshot["evidence"][evidence.id]["title"] == "Provider title"
    assert metadata_snapshot["selections"]["title"] == "Owner title"

    %{credential_plaintext: token} = device_fixture(owner)

    reset =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/json")
      |> put_req_header("idempotency-key", "provider-reset-#{System.unique_integer([:positive])}")
      |> post("/api/v1/metadata/#{asset_set.id}/reset-provider", %{
        "field" => "title",
        "base_revision" => 1,
        "evidence_id" => evidence.id
      })

    assert reset.status == 201
    reset = json_response(reset, 201)
    assert reset["selections"]["title"] == "Provider title"
    assert reset["field_sources"]["title"]["evidence_id"] == evidence.id

    low_confidence =
      Playstead.Repo.update!(Ecto.Changeset.change(evidence, confidence: "low"))

    assert {:error, :low_confidence_suggestion} =
             Playstead.Metadata.reset_from_provider(
               owner.user.id,
               asset_set.id,
               "candidate",
               0,
               low_confidence.id
             )
  end

  defp mutation(conn, token, asset_set_id, key, params) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", "metadata-#{key}-#{System.unique_integer([:positive])}")
    |> post("/api/v1/metadata/#{asset_set_id}", params)
  end
end
