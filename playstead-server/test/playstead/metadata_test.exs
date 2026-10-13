defmodule PlaysteadWeb.Api.V1.MetadataControllerTest do
  use PlaysteadWeb.ApiCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs.Blob
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.{Repo, Sync}
  alias Playstead.Protocol.{Capabilities, Negotiation}
  alias Playstead.Saves.{Revision, Save}
  alias Playstead.Sync.{Cursor, EntityKind}

  defp paired do
    scope = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(scope)
    {scope, token}
  end

  defp create_description!(conn, token, asset_set_id, description, key) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> put_req_header("content-type", "application/json")
    |> put_req_header("idempotency-key", key)
    |> post("/api/v1/metadata/#{asset_set_id}", %{
      "description" => description,
      "base_revision" => 0
    })
  end

  defp read_description(conn, token, asset_set_id) do
    conn
    |> put_req_header("authorization", "Bearer #{token}")
    |> get("/api/v1/metadata/#{asset_set_id}")
  end

  defp unique_key, do: "metadata-#{System.unique_integer([:positive])}"

  test "authenticated owner persists a private description and reads it back", %{conn: conn} do
    {scope, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    description = "Synthetic private description for an authored test game."

    created = create_description!(conn, token, asset_set.id, description, unique_key())
    assert created.status == 201
    body = json_response(created, 201)
    assert body["asset_set_id"] == asset_set.id
    assert body["description"] == description
    assert body["revision"] == 1
    assert body["selections"]["description"] == description
    assert body["field_revisions"]["description"] == 1

    assert {:ok, _selected} = Playstead.Metadata.get_description(scope.user.id, asset_set.id)
    fetched = read_description(conn, token, asset_set.id)
    assert json_response(fetched, 200) == body

    {:ok, changes} = Sync.changes_after(scope.user.id, nil)

    assert [%{entity_kind: "metadata", entity_id: id, payload: payload}] =
             Enum.filter(changes.entries, &(&1.entity_kind == "metadata"))

    assert id == asset_set.id
    assert payload["description"] == description
    assert payload["revision"] == 1
  end

  test "same idempotency key replays one durable revision and journal entry", %{conn: conn} do
    {scope, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    key = unique_key()

    first = create_description!(conn, token, asset_set.id, "Chosen text", key)
    replay = create_description!(conn, token, asset_set.id, "Chosen text", key)

    assert json_response(first, 201) == json_response(replay, 201)
    {:ok, changes} = Sync.changes_after(scope.user.id, nil)
    metadata = Enum.filter(changes.entries, &(&1.entity_kind == "metadata"))
    assert length(metadata) == 1
    assert hd(metadata).payload["revision"] == 1

    assert json_response(read_description(conn, token, asset_set.id), 200)["revision"] == 1
  end

  test "snapshot reset reconstructs metadata at the advertised cursor", %{conn: conn} do
    {scope, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    _ = create_description!(conn, token, asset_set.id, "Reset-safe text", unique_key())

    snapshot =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/snapshot")
      |> json_response(200)

    assert [%{"asset_set_id" => id, "description" => "Reset-safe text", "revision" => 1}] =
             Enum.filter(snapshot["metadata"], &(&1["asset_set_id"] == asset_set.id))

    assert {:ok, sequence} = Cursor.decode(snapshot["cursor"])
    assert sequence > 0

    reset =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/snapshot?cursor=#{URI.encode(snapshot["cursor"])}")
      |> json_response(200)

    assert reset["cursor"] == snapshot["cursor"]
    assert reset["metadata"] == snapshot["metadata"]
    assert id == asset_set.id
  end

  test "another owner cannot read or replace the selected description", %{conn: conn} do
    {_scope, token} = paired()
    other = owner_fixture()
    asset_set = asset_set_fixture(other.id)

    created =
      create_description!(conn, token, asset_set.id, "Private to the other owner", unique_key())

    PlaysteadWeb.ApiCase.assert_problem(created, 404, :not_found)

    read = read_description(conn, token, asset_set.id)
    PlaysteadWeb.ApiCase.assert_problem(read, 404, :not_found)
  end

  test "metadata selection leaves game and save identities unchanged", %{conn: conn} do
    {scope, token} = paired()
    asset_set = asset_set_fixture(scope.user.id)
    game_bytes = "synthetic game bytes whose identity must not change"
    game_sha256 = :crypto.hash(:sha256, game_bytes) |> Base.encode16(case: :lower)
    save_bytes = "synthetic battery save bytes"
    save_sha256 = :crypto.hash(:sha256, save_bytes) |> Base.encode16(case: :lower)

    {:ok, blob} =
      %Blob{}
      |> Blob.create_changeset(%{sha256: game_sha256, size_bytes: byte_size(game_bytes)})
      |> Repo.insert()

    {:ok, member} =
      %AssetMember{}
      |> AssetMember.create_changeset(%{
        asset_set_id: asset_set.id,
        ordinal: 0,
        role: "primary",
        blob_id: blob.id,
        declared_name: "synthetic-game.rom"
      })
      |> Repo.insert()

    {:ok, save} =
      %Save{}
      |> Save.create_changeset(%{
        id: Ecto.UUID.generate(),
        user_id: scope.user.id,
        content_key: game_sha256,
        save_kind: "battery",
        slot: "0"
      })
      |> Repo.insert()

    {:ok, revision} =
      %Revision{}
      |> Revision.create_changeset(%{
        id: Ecto.UUID.generate(),
        user_id: scope.user.id,
        save_line_id: save.id,
        blob_sha256: save_sha256,
        size_bytes: byte_size(save_bytes),
        recorded_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })
      |> Repo.insert()

    before_identities = {
      Repo.get!(AssetSet, asset_set.id),
      Repo.get!(AssetMember, member.id),
      Repo.get!(Blob, blob.id),
      Repo.get!(Save, save.id),
      Repo.get!(Revision, revision.id)
    }

    _ =
      create_description!(conn, token, asset_set.id, "Presentation-only correction", unique_key())

    after_identities = {
      Repo.get!(AssetSet, asset_set.id),
      Repo.get!(AssetMember, member.id),
      Repo.get!(Blob, blob.id),
      Repo.get!(Save, save.id),
      Repo.get!(Revision, revision.id)
    }

    assert after_identities == before_identities
    assert blob.sha256 == game_sha256
    assert blob.size_bytes == byte_size(game_bytes)
    assert revision.blob_sha256 == save_sha256
    assert revision.size_bytes == byte_size(save_bytes)
  end

  test "capability negotiates metadata as an optional additive kind" do
    server_ranges = Capabilities.supported_client_ranges()
    assert server_ranges.app == %{min: "1.0.0", max: "1.1.0"}
    assert EntityKind.valid?(:metadata)

    old_client = %{"app" => %{"min" => "1.0.0", "max" => "1.0.0"}}
    assert %{verdict: :compatible} = Negotiation.verdict(old_client, server_ranges)
  end
end
