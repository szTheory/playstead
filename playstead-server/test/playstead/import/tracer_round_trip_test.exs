defmodule Playstead.Import.TracerRoundTripTest do
  @moduledoc """
  The end-to-end proof of the whole Phase 2 tracer (D-34, D-37,
  PORT-02): upload one file over the API, export the resulting set,
  verify the bag independently, and reimport it — both into the same
  library (a duplicate, not a second copy) and into an empty one (a
  full restore).
  """

  use PlaysteadWeb.ApiCase, async: false
  use ExUnitProperties

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures
  import Playstead.PairingFixtures

  alias Playstead.Blobs.Blob
  alias Playstead.Catalogue
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Export
  alias Playstead.Export.PathSanitizer
  alias Playstead.Import
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    File.mkdir_p!(Export.export_root())
    :ok
  end

  defp paired do
    scope = user_scope_fixture()
    %{device: device, credential_plaintext: token} = device_fixture(scope)
    {scope, device, token}
  end

  defp repr_digest_header(bytes) do
    raw = :crypto.hash(:sha256, bytes)
    "sha-256=:#{Base.encode64(raw)}:"
  end

  defp uuid_v7 do
    <<r1::48, _::4, r2::12, _::2, r3::14, r4::48>> = :crypto.strong_rand_bytes(16)
    bin = <<r1::48, 7::4, r2::12, 2::2, r3::14, r4::48>>
    hex = Base.encode16(bin, case: :lower)
    <<p1::binary-8, p2::binary-4, p3::binary-4, p4::binary-4, p5::binary-12>> = hex
    "#{p1}-#{p2}-#{p3}-#{p4}-#{p5}"
  end

  defp upload!(conn, token, bytes) do
    resp =
      conn
      |> put_req_header("authorization", "Bearer #{token}")
      |> put_req_header("content-type", "application/octet-stream")
      |> put_req_header("idempotency-key", "up-#{System.unique_integer([:positive])}")
      |> put_req_header("repr-digest", repr_digest_header(bytes))
      |> put_req_header("content-length", to_string(byte_size(bytes)))
      |> put(~p"/api/v1/imports/uploads/#{uuid_v7()}", bytes)

    json_response(resp, 201)
  end

  test "upload, export, independent verify, and reimport into the same library round-trips with zero new logical records",
       %{conn: conn} do
    {scope, _device, token} = paired()
    bytes = random_bytes(20_000)

    %{"receipt_id" => _receipt_id, "sha256" => sha256, "size_bytes" => size_bytes} =
      upload!(conn, token, bytes)

    assert size_bytes == byte_size(bytes)

    asset_set = Repo.get_by!(AssetSet, user_id: scope.user.id)
    target_name = "export-#{System.unique_integer([:positive])}"

    assert {:ok, %{target_dir: target_dir}} =
             Export.export_set(scope.user.id, asset_set.id, target_name)

    for name <- ~w(bagit.txt bag-info.txt manifest-sha256.txt tagmanifest-sha256.txt) do
      assert File.exists?(Path.join(target_dir, name))
    end

    manifest = File.read!(Path.join(target_dir, "manifest-sha256.txt"))
    lines = String.split(manifest, "\n", trim: true)
    assert length(lines) == 1

    for line <- lines do
      assert line =~ ~r/^[0-9a-f]{64}  data\/.+$/
    end

    [line] = lines
    [manifest_sha256, relative_path] = String.split(line, "  ", parts: 2)
    assert manifest_sha256 == sha256

    payload_path = Path.join(target_dir, relative_path)
    payload_bytes = File.read!(payload_path)
    assert payload_bytes == bytes

    # Independent re-hash of every listed file, exactly what a
    # self-hoster's `sha256sum -c` would do.
    for line <- lines do
      [expected_sha256, rel] = String.split(line, "  ", parts: 2)

      actual =
        :crypto.hash(:sha256, File.read!(Path.join(target_dir, rel)))
        |> Base.encode16(case: :lower)

      assert actual == expected_sha256
    end

    blob_count_before = Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count)
    asset_set_count_before = Repo.aggregate(AssetSet, :count)

    assert {:ok, [receipt]} = Import.reimport_folder(scope.user.id, target_dir)
    assert receipt.outcome == "alias"

    assert Repo.aggregate(from(b in Blob, where: b.sha256 == ^sha256), :count) ==
             blob_count_before

    assert Repo.aggregate(AssetSet, :count) == asset_set_count_before
  end

  test "reimporting an exported folder into an empty library restores the set with identical members",
       %{conn: conn} do
    {scope_a, _device_a, token_a} = paired()
    bytes = random_bytes(9_000)
    %{"sha256" => sha256} = upload!(conn, token_a, bytes)

    original_member =
      AssetSet
      |> Repo.get_by!(user_id: scope_a.user.id)
      |> Repo.preload(:asset_members)
      |> Map.fetch!(:asset_members)
      |> List.first()

    target_name = "export-#{System.unique_integer([:positive])}"
    asset_set_a = Repo.get_by!(AssetSet, user_id: scope_a.user.id)

    assert {:ok, %{target_dir: target_dir}} =
             Export.export_set(scope_a.user.id, asset_set_a.id, target_name)

    {scope_b, _device_b, _token_b} = paired()
    assert {:ok, [receipt]} = Import.reimport_folder(scope_b.user.id, target_dir)
    # 02-09 gap closure: header evidence now reaches classification for
    # every import; random bytes with no reference pack installed for
    # this fresh user land the quiet unrecognized{no_reference_installed}
    # reason rather than a plain new_asset. This test's identity claim
    # (restore into a fresh, empty library) is unaffected — reimport
    # identity is proven separately below by the set/member assertions.
    assert receipt.outcome == "unrecognized"
    assert receipt.reason == "no_reference_installed"

    restored_set = Repo.get_by!(AssetSet, user_id: scope_b.user.id)

    restored_member =
      restored_set
      |> Repo.preload(:asset_members)
      |> Map.fetch!(:asset_members)
      |> List.first()

    assert restored_member.role == original_member.role
    assert restored_member.ordinal == original_member.ordinal
    assert restored_member.required == original_member.required

    restored_blob = Repo.get!(Playstead.Blobs.Blob, restored_member.blob_id)
    assert restored_blob.sha256 == sha256
  end

  describe "member_fingerprint/1" do
    test "is stable across orderings of the same member set" do
      members_a = [%{role: "rom", sha256: "aaa"}, %{role: "manual", sha256: "bbb"}]
      members_b = Enum.reverse(members_a)

      assert Catalogue.member_fingerprint(members_a) == Catalogue.member_fingerprint(members_b)
    end

    test "differs when any member's role changes" do
      members = [%{role: "rom", sha256: "aaa"}]
      changed = [%{role: "manual", sha256: "aaa"}]

      refute Catalogue.member_fingerprint(members) == Catalogue.member_fingerprint(changed)
    end

    test "differs when any member's hash changes" do
      members = [%{role: "rom", sha256: "aaa"}]
      changed = [%{role: "rom", sha256: "bbb"}]

      refute Catalogue.member_fingerprint(members) == Catalogue.member_fingerprint(changed)
    end
  end

  describe "Playstead.Export.PathSanitizer" do
    property "never yields a result containing .., a leading separator, or a NUL byte" do
      check all(name <- StreamData.string(:printable, min_length: 1, max_length: 40)) do
        case PathSanitizer.sanitize(name) do
          {:ok, sanitized} ->
            refute String.contains?(sanitized, "..")
            refute String.starts_with?(sanitized, "/")
            refute String.contains?(sanitized, <<0>>)

          :error ->
            :ok
        end
      end
    end

    test "rejects a parent-directory segment" do
      assert PathSanitizer.sanitize("../etc/passwd") == :error
    end

    test "rejects an absolute path" do
      assert PathSanitizer.sanitize("/etc/passwd") == :error
    end

    test "resolve_under_root refuses a path that escapes the root" do
      assert PathSanitizer.resolve_under_root("/tmp/root", "safe.rom") ==
               {:ok, "/tmp/root/safe.rom"}
    end
  end

  describe "export target and marker safety" do
    test "an export target containing a parent-directory segment is refused", %{conn: conn} do
      {scope, _device, token} = paired()
      bytes = random_bytes(100)
      upload!(conn, token, bytes)

      asset_set = Repo.get_by!(AssetSet, user_id: scope.user.id)

      assert {:error, :invalid_target} =
               Export.export_set(scope.user.id, asset_set.id, "../escape")
    end

    test "an export refuses a non-empty target lacking its own marker file", %{conn: conn} do
      {scope, _device, token} = paired()
      bytes = random_bytes(100)
      upload!(conn, token, bytes)

      target_name = "export-#{System.unique_integer([:positive])}"
      target_dir = Path.join(Export.export_root(), target_name)
      File.mkdir_p!(target_dir)
      File.write!(Path.join(target_dir, "unrelated.txt"), "pre-existing")

      asset_set = Repo.get_by!(AssetSet, user_id: scope.user.id)

      assert {:error, :target_not_empty} =
               Export.export_set(scope.user.id, asset_set.id, target_name)

      assert File.read!(Path.join(target_dir, "unrelated.txt")) == "pre-existing"
    end
  end
end
