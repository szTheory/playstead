defmodule Playstead.Metadata.ProviderMediaCacheTest do
  use PlaysteadWeb.ApiCase, async: false

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.{Blobs, Repo, Saves}
  alias Playstead.Catalogue.AssetMember
  alias Playstead.Metadata.{Consent, PrivateMedia, ProviderMediaCache}

  @png <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>

  defmodule ImageTransport do
    def get(url, limit, opts) do
      send(opts[:test_pid], {:image_request, url, limit})

      Keyword.get(
        opts,
        :response,
        {:ok,
         %{status: 200, body: "provider source", mime: "image/jpeg", license_expires_at: nil}}
      )
    end
  end

  defmodule DecoderFake do
    def decode(bytes, mime, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:decoded, byte_size(bytes), mime})
      {:ok, <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 0>>}
    end
  end

  defmodule ChangedDecoderFake do
    def decode(_bytes, _mime, _opts),
      do: {:ok, <<137, 80, 78, 71, 13, 10, 26, 10, 1, 2, 3>>}
  end

  defmodule LargeDecoderFake do
    def decode(_bytes, _mime, _opts),
      do: {:ok, <<137, 80, 78, 71, 13, 10, 26, 10, 0::size(8 * 1_048_576 * 8)>>}
  end

  setup do
    previous_terms = Application.get_env(:playstead, :igdb_private_image_terms_revision)
    Application.put_env(:playstead, :igdb_private_image_terms_revision, "terms-test-v1")

    on_exit(fn ->
      restore_env(:igdb_private_image_terms_revision, previous_terms)
    end)

    :ok
  end

  test "constructs media URLs from validated IDs and fixed size allowlist" do
    assert {:ok, "https://images.igdb.com/igdb/image/upload/t_cover_big/abc-123_x.jpg"} =
             ProviderMediaCache.image_url("abc-123_x", "cover_big")

    assert {:error, :invalid_image_reference} =
             ProviderMediaCache.image_url("../attacker", "cover_big")

    assert {:error, :invalid_image_reference} = ProviderMediaCache.image_url("abc", "../../host")
    assert ProviderMediaCache.max_response_bytes() == 12 * 1_048_576
  end

  test "requires exact private serving rights and invokes the bounded decoder after a fixed-host fetch" do
    owner = user_scope_fixture().user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})
    enable_consent(owner.id, asset)
    cache_root = cache_root()
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)

    on_exit(fn ->
      restore_env(:metadata_provider_cache_root, previous_root)
      File.rm_rf!(cache_root)
    end)

    assert {:error, :image_rights_unverified} =
             ProviderMediaCache.fetch(owner.id, asset.id, "cover-1", "cover_big",
               transport: ImageTransport,
               decoder: DecoderFake,
               test_pid: self()
             )

    refute_receive {:image_request, _, _}

    grant_image_rights(owner.id, asset.id)

    assert {:ok, object} =
             ProviderMediaCache.fetch(owner.id, asset.id, "cover-1", "cover_big",
               transport: ImageTransport,
               decoder: DecoderFake,
               test_pid: self()
             )

    assert_receive {:image_request,
                    "https://images.igdb.com/igdb/image/upload/t_cover_big/cover-1.jpg",
                    12_582_912}

    source_size = byte_size("provider source")
    assert_receive {:decoded, ^source_size, "image/jpeg"}
    assert object.bytes == @png
    assert object.sha256 == Base.encode16(:crypto.hash(:sha256, @png), case: :lower)
    assert DateTime.compare(object.cache_expires_at, DateTime.utc_now()) == :gt
  end

  test "refuses a decoded cover larger than its independent image cap" do
    owner = user_scope_fixture().user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})
    enable_consent(owner.id, asset)
    grant_image_rights(owner.id, asset.id)
    cache_root = cache_root()
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)

    on_exit(fn ->
      restore_env(:metadata_provider_cache_root, previous_root)
      File.rm_rf!(cache_root)
    end)

    assert {:error, :decoded_image_too_large} =
             ProviderMediaCache.fetch(owner.id, asset.id, "oversized", "cover_big",
               transport: ImageTransport,
               decoder: LargeDecoderFake,
               test_pid: self()
             )

    assert ProviderMediaCache.usage(owner.id).used_bytes == 0
  end

  test "refuses capacity when the only eligible game-cache object is pinned" do
    owner = user_scope_fixture().user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})
    enable_consent(owner.id, asset)
    grant_image_rights(owner.id, asset.id)
    cache_root = cache_root()
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)

    on_exit(fn ->
      restore_env(:metadata_provider_cache_root, previous_root)
      File.rm_rf!(cache_root)
    end)

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(%ProviderMediaCache.Object{
      user_id: owner.id,
      asset_set_id: asset.id,
      provider: "igdb",
      image_id: "pinned-cover",
      size: "screenshot_med",
      object_key: "pinned/missing.png",
      sha256: String.duplicate("a", 64),
      size_bytes: 32 * 1_048_576,
      pinned: true,
      legally_refetchable: false,
      cache_expires_at: DateTime.add(now, 86_400, :second),
      license_expires_at: nil,
      last_accessed_at: now
    })

    assert {:error, {:capacity_refused, usage}} =
             ProviderMediaCache.fetch(owner.id, asset.id, "next-image", "screenshot_med",
               transport: ImageTransport,
               decoder: DecoderFake,
               test_pid: self()
             )

    assert usage.used_bytes == 32 * 1_048_576
    assert usage.reclaimable_bytes == 0
  end

  test "consent revocation after final authorization prevents derivative publication" do
    owner = user_scope_fixture().user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})
    enable_consent(owner.id, asset)
    grant_image_rights(owner.id, asset.id)
    cache_root = cache_root()
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)

    on_exit(fn ->
      restore_env(:metadata_provider_cache_root, previous_root)
      File.rm_rf!(cache_root)
    end)

    parent = self()

    fetch =
      Task.async(fn ->
        ProviderMediaCache.fetch(owner.id, asset.id, "revoked-image", "cover_big",
          transport: ImageTransport,
          decoder: DecoderFake,
          test_pid: parent,
          before_store: fn ->
            send(parent, :authorized_waiting_to_publish)

            receive do
              :resume_publication -> :ok
            after
              5_000 -> raise "timed out waiting to resume provider cache publication"
            end
          end
        )
      end)

    assert_receive :authorized_waiting_to_publish, 5_000
    assert {:ok, _consent} = Consent.disable(owner.id, asset.id)
    send(fetch.pid, :resume_publication)

    assert {:error, :consent_required} = Task.await(fetch, 5_000)
    assert Repo.all(from o in ProviderMediaCache.Object, where: o.user_id == ^owner.id) == []
    assert ProviderMediaCache.usage(owner.id).used_bytes == 0
    refute File.exists?(cache_root)
  end

  test "replaces an expired derivative, purges it on revocation, and retains failed deletions in usage" do
    owner = user_scope_fixture().user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})
    enable_consent(owner.id, asset)
    grant_image_rights(owner.id, asset.id)
    cache_root = cache_root()
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)

    on_exit(fn ->
      restore_env(:metadata_provider_cache_root, previous_root)
      File.rm_rf!(cache_root)
    end)

    assert {:ok, original} =
             ProviderMediaCache.fetch(owner.id, asset.id, "same-image", "cover_big",
               transport: ImageTransport,
               decoder: DecoderFake,
               test_pid: self()
             )

    original_path = Path.join(cache_root, original.object_key)
    assert File.read!(original_path) == @png

    expired =
      Repo.get_by!(ProviderMediaCache.Object,
        user_id: owner.id,
        asset_set_id: asset.id,
        image_id: "same-image",
        size: "cover_big"
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.update!(
      Ecto.Changeset.change(expired,
        cache_expires_at: DateTime.add(now, -1, :second)
      )
    )

    assert {:ok, replacement} =
             ProviderMediaCache.fetch(owner.id, asset.id, "same-image", "cover_big",
               transport: ImageTransport,
               decoder: ChangedDecoderFake,
               test_pid: self()
             )

    replacement_path = Path.join(cache_root, replacement.object_key)
    assert replacement.object_key != original.object_key
    refute File.exists?(original_path)
    assert File.read!(replacement_path) != @png
    assert ProviderMediaCache.usage(owner.id).used_bytes == byte_size(replacement.bytes)

    assert {:ok, _} = Consent.disable(owner.id, asset.id)
    refute File.exists?(replacement_path)
    assert ProviderMediaCache.usage(owner.id).used_bytes == 0

    stuck =
      Repo.insert!(%ProviderMediaCache.Object{
        user_id: owner.id,
        asset_set_id: asset.id,
        provider: "igdb",
        image_id: "undeletable",
        size: "cover_small",
        object_key: "undeletable/path.png",
        sha256: String.duplicate("c", 64),
        size_bytes: 7,
        pinned: false,
        legally_refetchable: true,
        cache_expires_at: DateTime.add(now, 60, :second),
        license_expires_at: nil,
        last_accessed_at: now
      })

    File.mkdir_p!(Path.join(cache_root, stuck.object_key))

    assert {:error, {:cache_delete_failed, [{id, reason}]}} =
             ProviderMediaCache.purge(owner.id, asset.id)

    assert id == stuck.id
    assert reason in [:eisdir, :eperm]
    assert Repo.get(ProviderMediaCache.Object, stuck.id)
    assert ProviderMediaCache.usage(owner.id).used_bytes == 7

    assert {:error, {:cache_delete_failed, ^id, eviction_reason}} =
             ProviderMediaCache.reclaim(owner.id)

    assert eviction_reason in [:eisdir, :eperm]
    assert Repo.get(ProviderMediaCache.Object, stuck.id)
    assert ProviderMediaCache.usage(owner.id).used_bytes == 7
  end

  test "reclaim removes provider derivatives while preserving exact ROM, save, and private-original bytes" do
    owner_scope = user_scope_fixture()
    owner = owner_scope.user
    asset = asset_set_fixture(owner.id, %{system_id: "gba"})
    enable_consent(owner.id, asset)
    grant_image_rights(owner.id, asset.id)
    cache_root = cache_root()
    previous_root = Application.get_env(:playstead, :metadata_provider_cache_root)
    Application.put_env(:playstead, :metadata_provider_cache_root, cache_root)

    on_exit(fn ->
      restore_env(:metadata_provider_cache_root, previous_root)
      File.rm_rf!(cache_root)
    end)

    rom_bytes = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
    {:ok, _rom_status, rom_blob} = Blobs.put_stream([rom_bytes], byte_size(rom_bytes))

    Repo.insert!(
      AssetMember.create_changeset(%AssetMember{}, %{
        asset_set_id: asset.id,
        ordinal: 0,
        role: "primary",
        required: true,
        blob_id: rom_blob.blob_id,
        declared_name: "authored-homebrew.gba",
        export_path: "roms/authored-homebrew.gba"
      })
    )

    private_bytes = "private authored media original"

    assert {:ok, private_media} =
             PrivateMedia.create(owner.id, asset.id, private_bytes, "text/plain")

    save_bytes = "persistent save bytes"
    {:ok, _save_status, save_blob} = Blobs.put_stream([save_bytes], byte_size(save_bytes))
    %{device: device} = device_fixture(owner_scope)
    command_id = Ecto.UUID.generate()

    assert {:ok, _} =
             Saves.record_pending_upload(
               owner.id,
               device.id,
               command_id,
               save_blob.sha256,
               save_blob.size_bytes
             )

    assert {:ok, save_revision} =
             Saves.commit_revision(owner.id, device, %{
               "id" => Ecto.UUID.generate(),
               "command_id" => command_id,
               "content_key" => String.duplicate("b", 64)
             })

    before = %{
      rom: read_blob(rom_blob.sha256),
      save: read_blob(save_revision.blob_sha256),
      private: PrivateMedia.fetch_original(owner.id, asset.id, private_media.id)
    }

    assert before == %{rom: rom_bytes, save: save_bytes, private: {:ok, private_bytes}}

    assert {:ok, _object} =
             ProviderMediaCache.fetch(owner.id, asset.id, "evictable", "cover_big",
               transport: ImageTransport,
               decoder: DecoderFake,
               test_pid: self()
             )

    assert {:ok, %{reclaimed_bytes: bytes}} = ProviderMediaCache.reclaim(owner.id)
    assert bytes == byte_size(@png)
    assert ProviderMediaCache.usage(owner.id).used_bytes == 0

    assert read_blob(rom_blob.sha256) == rom_bytes
    assert read_blob(save_revision.blob_sha256) == save_bytes

    assert {:ok, ^private_bytes} =
             PrivateMedia.fetch_original(owner.id, asset.id, private_media.id)

    assert Blobs.exists?(rom_blob.sha256)
    assert Blobs.exists?(save_revision.blob_sha256)
  end

  defp enable_consent(user_id, asset) do
    assert {:ok, _} =
             Consent.enable(user_id, asset.id, %{
               "title" => asset.display_title,
               "system" => asset.system_id,
               "disclosure_revision" => Consent.disclosure_revision()
             })
  end

  defp grant_image_rights(user_id, asset_id) do
    consent =
      Repo.one!(
        from c in Playstead.Metadata.ProviderConsent,
          where: c.user_id == ^user_id and c.asset_set_id == ^asset_id
      )

    Repo.update!(
      Ecto.Changeset.change(consent,
        image_terms_revision: "terms-test-v1",
        image_grant_scope: "private_single_owner"
      )
    )
  end

  defp cache_root,
    do:
      Path.join(
        System.tmp_dir!(),
        "playstead-provider-cache-#{System.unique_integer([:positive])}"
      )

  defp restore_env(key, nil), do: Application.delete_env(:playstead, key)
  defp restore_env(key, value), do: Application.put_env(:playstead, key, value)

  defp read_blob(sha) do
    {:ok, stream} = Blobs.stream(sha)
    stream |> Enum.to_list() |> IO.iodata_to_binary()
  end
end
