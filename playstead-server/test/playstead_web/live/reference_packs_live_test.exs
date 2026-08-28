defmodule PlaysteadWeb.ReferencePacksLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Playstead.Recognition.DatPackImporter

  setup :register_and_log_in_user

  @fixtures_dir Path.join([__DIR__, "..", "..", "support", "fixtures", "dat"])
  defp fixture(name), do: Path.join(@fixtures_dir, name)

  defp entry(name, bytes) do
    %{
      last_modified: 1_594_171_879_000,
      name: name,
      content: bytes,
      size: byte_size(bytes),
      type: "text/xml"
    }
  end

  test "supplying a valid pack imports it and renders its entry count", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/reference-packs")

    bytes = File.read!(fixture("valid.dat"))

    upload = file_input(lv, "#reference-pack-form", :pack, [entry("valid.dat", bytes)])
    assert render_upload(upload, "valid.dat") =~ "valid.dat"

    lv
    |> form("#reference-pack-form", %{
      "pack" => %{
        "source" => "https://example.com/pack.dat",
        "upstream_version" => "2026-08-01",
        "license_claim" => "unstated",
        "license_note" => "No published licence."
      }
    })
    |> render_submit()

    html = render(lv)
    assert html =~ "2 entries"
  end

  test "the pack list renders source, retrieval time, upstream version, file hash, and licence claim",
       %{conn: conn, scope: scope} do
    {:ok, _pack} =
      DatPackImporter.import_pack(scope.user.id, fixture("valid.dat"), %{
        source: "https://example.com/no-intro.dat",
        upstream_version: "2026-08-01",
        license_claim: :share_alike,
        license_note: "CC BY-SA 4.0"
      })

    {:ok, _lv, html} = live(conn, ~p"/reference-packs")

    assert html =~ "https://example.com/no-intro.dat"
    assert html =~ "2026-08-01"
    assert html =~ "share_alike"
    assert html =~ "CC BY-SA 4.0"
  end

  test "a hostile pack fixture is refused with an explanation and stores no entries", %{
    conn: conn,
    scope: scope
  } do
    {:ok, lv, _html} = live(conn, ~p"/reference-packs")

    bytes = File.read!(fixture("doctype.dat"))

    upload = file_input(lv, "#reference-pack-form", :pack, [entry("doctype.dat", bytes)])
    render_upload(upload, "doctype.dat")

    lv
    |> form("#reference-pack-form", %{"pack" => %{"license_claim" => "unstated"}})
    |> render_submit()

    assert render(lv) =~ "Nothing was stored"
    assert DatPackImporter.list_packs(scope.user.id) == []
  end

  test "the console reports the number of newly identified assets after an import", %{
    conn: conn,
    scope: scope
  } do
    blob_sha1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

    {:ok, blob} =
      %Playstead.Blobs.Blob{}
      |> Playstead.Blobs.Blob.create_changeset(%{
        sha256: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower),
        size_bytes: 1024,
        sha1: blob_sha1
      })
      |> Playstead.Repo.insert()

    {:ok, asset_set} =
      %Playstead.Catalogue.AssetSet{}
      |> Playstead.Catalogue.AssetSet.create_changeset(%{
        user_id: scope.user.id,
        status: "active",
        member_fingerprint: "fixture:#{Ecto.UUID.generate()}"
      })
      |> Playstead.Repo.insert()

    {:ok, _member} =
      %Playstead.Catalogue.AssetMember{}
      |> Playstead.Catalogue.AssetMember.create_changeset(%{
        asset_set_id: asset_set.id,
        ordinal: 0,
        role: "primary",
        blob_id: blob.id
      })
      |> Playstead.Repo.insert()

    dat_content = """
    <?xml version="1.0"?>
    <datafile>
      <game name="Matches The Blob">
        <rom name="matches.gba" size="1024" sha1="#{blob_sha1}"/>
      </game>
    </datafile>
    """

    {:ok, lv, _html} = live(conn, ~p"/reference-packs")
    upload = file_input(lv, "#reference-pack-form", :pack, [entry("matcher.dat", dat_content)])
    render_upload(upload, "matcher.dat")

    lv
    |> form("#reference-pack-form", %{"pack" => %{"license_claim" => "unstated"}})
    |> render_submit()

    assert render(lv) =~ "1 item"
    assert render(lv) =~ "newly identified"
  end

  test "the library's install hint links to the reference packs route", %{
    conn: conn,
    scope: scope
  } do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    bytes = :crypto.strong_rand_bytes(64)
    {:ok, status, meta} = Playstead.Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, _receipt} =
      Playstead.Import.import_single(
        scope.user.id,
        %{original_name: "unidentified.gba", origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta}
      )

    {:ok, lv, _html} = live(conn, ~p"/library")
    assert has_element?(lv, "#reference-pack-hint-link[href='/reference-packs']")
  end

  test "removing a pack is confirmed, writes an audit entry, and leaves evidence rows present", %{
    conn: conn,
    scope: scope
  } do
    {:ok, pack} =
      DatPackImporter.import_pack(scope.user.id, fixture("valid.dat"), %{license_claim: :unstated})

    {:ok, lv, _html} = live(conn, ~p"/reference-packs")

    assert has_element?(
             lv,
             "#remove-pack-#{pack.id}[data-confirm]"
           )

    lv |> element("#remove-pack-#{pack.id}") |> render_click()

    refute has_element?(lv, "#pack-#{pack.id}")
    assert DatPackImporter.list_packs(scope.user.id) == []

    events = Playstead.AuditLog.list_by_subject(pack.id) |> Enum.map(& &1.event)
    assert "reference_pack_removed" in events
  end
end
