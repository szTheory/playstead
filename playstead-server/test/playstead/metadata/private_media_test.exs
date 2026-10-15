defmodule Playstead.Metadata.PrivateMediaTest do
  use Playstead.DataCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Metadata.PrivateMedia
  alias Playstead.Repo
  alias Playstead.Saves.Save

  defmodule DecoderFake do
    def decode(_bytes, _mime, _opts), do: {:ok, "safe derivative png bytes"}
  end

  test "stores exact UTF-8 source bytes in the owner-scoped media manifest" do
    owner = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id)
    asset_set_before = Repo.get!(AssetSet, asset_set.id)
    members_before = Repo.aggregate(AssetMember, :count)
    saves_before = Repo.aggregate(Save, :count)
    source = "private note — original bytes\n"

    assert {:ok, media} = PrivateMedia.create(owner.id, asset_set.id, source, "text/plain")
    assert media.original_sha256 == :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)
    assert media.original_size_bytes == byte_size(source)
    assert media.original_mime == "text/plain"
    assert media.derived_sha256 == nil
    assert {:ok, ^source} = PrivateMedia.fetch_original(owner.id, asset_set.id, media.id)
    assert Repo.get!(AssetSet, asset_set.id) == asset_set_before
    assert Repo.aggregate(AssetMember, :count) == members_before
    assert Repo.aggregate(Save, :count) == saves_before
  end

  test "keeps accepted image originals and decoded derivatives in separate CAS objects" do
    owner = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id)
    original = "uploaded png bytes"
    derivative = "safe derivative png bytes"

    assert {:ok, media} =
             PrivateMedia.create(owner.id, asset_set.id, original, "image/png",
               decoder: DecoderFake
             )

    assert media.original_sha256 == :crypto.hash(:sha256, original) |> Base.encode16(case: :lower)

    assert media.derived_sha256 ==
             :crypto.hash(:sha256, derivative) |> Base.encode16(case: :lower)

    assert media.original_sha256 != media.derived_sha256
    assert {:ok, ^original} = PrivateMedia.fetch_original(owner.id, asset_set.id, media.id)
    assert {:ok, ^derivative} = PrivateMedia.fetch_derived(owner.id, asset_set.id, media.id)
  end

  test "a rejected manifest insert publishes no new canonical media bytes" do
    owner = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id)
    bytes = "manifest insert rejection leaves no canonical object"
    digest = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    Repo.query!("""
    CREATE FUNCTION reject_test_metadata_media_insert() RETURNS trigger AS $$
    BEGIN
      IF NEW.provenance->>'reject_for_test' = 'true' THEN
        RAISE EXCEPTION 'test metadata_media insert rejection';
      END IF;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql
    """)

    Repo.query!("""
    CREATE TRIGGER reject_test_metadata_media_insert
    BEFORE INSERT ON metadata_media
    FOR EACH ROW EXECUTE FUNCTION reject_test_metadata_media_insert()
    """)

    assert_raise Postgrex.Error, ~r/test metadata_media insert rejection/, fn ->
      PrivateMedia.create(owner.id, asset_set.id, bytes, "text/plain",
        provenance: %{source: "test", reject_for_test: true}
      )
    end

    refute Playstead.Blobs.exists?(digest)
    refute Playstead.Blobs.get_by_sha256(digest)
  end

  test "another owner cannot fetch media and invalid images leave no committed manifest" do
    owner = user_scope_fixture().user
    other = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id)

    assert {:ok, media} = PrivateMedia.create(owner.id, asset_set.id, "private", "text/plain")
    assert {:error, :not_found} = PrivateMedia.fetch_original(other.id, asset_set.id, media.id)
    invalid_image = "not png"
    invalid_sha = :crypto.hash(:sha256, invalid_image) |> Base.encode16(case: :lower)
    assert {:error, _} = PrivateMedia.create(owner.id, asset_set.id, invalid_image, "image/png")
    refute Playstead.Blobs.exists?(invalid_sha)
    assert {:ok, [listed]} = PrivateMedia.list(owner.id, asset_set.id)
    assert listed.id == media.id
  end

  test "caps each game at ten media items and rejects oversized or invalid text" do
    owner = user_scope_fixture().user
    asset_set = asset_set_fixture(owner.id)

    originals =
      for index <- 1..10 do
        bytes = "private media #{index}"
        assert {:ok, item} = PrivateMedia.create(owner.id, asset_set.id, bytes, "text/plain")
        {item, bytes}
      end

    rejected = "eleventh distinct private media"
    rejected_sha = :crypto.hash(:sha256, rejected) |> Base.encode16(case: :lower)

    assert {:error, :media_limit_reached} =
             PrivateMedia.create(owner.id, asset_set.id, rejected, "text/plain")

    refute Playstead.Blobs.exists?(rejected_sha)
    refute Playstead.Blobs.get_by_sha256(rejected_sha)
    assert {:ok, listed} = PrivateMedia.list(owner.id, asset_set.id)
    assert length(listed) == 10

    for {item, bytes} <- originals do
      assert {:ok, ^bytes} = PrivateMedia.fetch_original(owner.id, asset_set.id, item.id)
      assert Playstead.Blobs.exists?(item.original_sha256)
    end

    assert {:error, _} = PrivateMedia.create(owner.id, asset_set.id, <<255>>, "text/plain")

    assert {:error, _} =
             PrivateMedia.create(owner.id, asset_set.id, :binary.copy("x", 65_537), "text/plain")
  end
end

defmodule PlaysteadWeb.Api.V1.MetadataMediaControllerTest do
  use PlaysteadWeb.ApiCase, async: false
  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures
  alias Playstead.Metadata.PrivateMedia

  test "owner can remove a derivative while keeping the exact original", %{conn: conn} do
    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)
    asset_set = asset_set_fixture(owner.user.id)
    original = "source image bytes"

    assert {:ok, item} =
             PrivateMedia.create(owner.user.id, asset_set.id, original, "image/png",
               decoder: Playstead.Metadata.PrivateMediaTest.DecoderFake
             )

    deleted =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("idempotency-key", "media-delete-#{System.unique_integer([:positive])}")
      |> delete("/api/v1/metadata/#{asset_set.id}/media/#{item.id}/derived")

    assert deleted.status == 200
    assert json_response(deleted, 200)["derived_sha256"] == nil
    assert {:ok, ^original} = PrivateMedia.fetch_original(owner.user.id, asset_set.id, item.id)
    assert {:error, :not_found} = PrivateMedia.fetch_derived(owner.user.id, asset_set.id, item.id)
  end

  test "private text media uploads and returns exact original bytes only to its owner", %{
    conn: conn
  } do
    owner = user_scope_fixture()
    %{credential_plaintext: token} = device_fixture(owner)
    asset_set = asset_set_fixture(owner.user.id)
    bytes = "private text\n"
    digest = :crypto.hash(:sha256, bytes) |> Base.encode64()
    idempotency_key = "metadata-media-#{System.unique_integer([:positive])}"

    created =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "text/plain")
      |> put_req_header("content-length", Integer.to_string(byte_size(bytes)))
      |> put_req_header("repr-digest", "sha-256=:#{digest}:")
      |> put_req_header("idempotency-key", idempotency_key)
      |> post("/api/v1/metadata/#{asset_set.id}/media", bytes)

    assert created.status == 201
    item = json_response(created, 201)
    assert item["original_sha256"] == :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    replay =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "text/plain")
      |> put_req_header("content-length", Integer.to_string(byte_size(bytes)))
      |> put_req_header("repr-digest", "sha-256=:#{digest}:")
      |> put_req_header("idempotency-key", idempotency_key)
      |> post("/api/v1/metadata/#{asset_set.id}/media", bytes)

    assert json_response(replay, 201) == item

    fetched =
      build_conn()
      |> put_req_header("authorization", "Bearer #{token}")
      |> get("/api/v1/metadata/#{asset_set.id}/media/#{item["id"]}/original")

    assert fetched.status == 200
    assert fetched.resp_body == bytes

    other = user_scope_fixture()
    %{credential_plaintext: other_token} = device_fixture(other)

    denied =
      build_conn()
      |> put_req_header("authorization", "Bearer #{other_token}")
      |> get("/api/v1/metadata/#{asset_set.id}/media/#{item["id"]}/original")

    assert denied.status == 404
  end
end
