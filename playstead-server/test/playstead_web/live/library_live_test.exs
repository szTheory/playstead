defmodule PlaysteadWeb.LibraryLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Accounts.Scope
  alias Playstead.Blobs
  alias Playstead.Import
  alias Playstead.Recognition
  alias Playstead.RomFixtures

  setup :register_and_log_in_user

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp store!(bytes) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    {status, meta}
  end

  defp import!(user_id, bytes, name, opts \\ []) do
    {status, meta} = store!(bytes)

    {:ok, receipt} =
      Import.import_single(
        user_id,
        %{original_name: name, origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta},
        opts
      )

    receipt
  end

  test "lists this user's asset sets with display title, system, and identification state", %{
    conn: conn,
    user: user
  } do
    bytes = RomFixtures.valid_gba("PLAYSTEAD")
    import!(user.id, bytes, "playstead.gba", format_bytes: bytes)

    {:ok, _lv, html} = live(conn, ~p"/library")

    assert html =~ "playstead"
    assert html =~ "gba"
  end

  test "an unidentified asset shows the quiet badge and no error styling", %{
    conn: conn,
    user: user
  } do
    import!(user.id, random_bytes(64), "mystery.bin")

    {:ok, lv, html} = live(conn, ~p"/library")

    assert html =~ "Not yet identified"
    refute has_element?(lv, ".text-\\[\\#EF4444\\]", "Not yet identified")
  end

  test "the reference-pack hint appears once at the library level and not per asset", %{
    conn: conn,
    user: user
  } do
    import!(user.id, random_bytes(64), "mystery1.bin")
    import!(user.id, random_bytes(64), "mystery2.bin")

    {:ok, _lv, html} = live(conn, ~p"/library")

    assert Regex.scan(~r/Install a reference pack/, html) |> length() == 1
  end

  test "the hint is dismissible", %{conn: conn, user: user} do
    import!(user.id, random_bytes(64), "mystery.bin")

    {:ok, lv, _html} = live(conn, ~p"/library")
    assert has_element?(lv, "#reference-pack-hint")

    lv |> element("#dismiss-reference-pack-hint") |> render_click()
    refute has_element?(lv, "#reference-pack-hint")
  end

  test "the asset detail view renders the full 64-character SHA-256 of the stored blob", %{
    conn: conn,
    user: user
  } do
    bytes = random_bytes(64)
    receipt = import!(user.id, bytes, "game.bin")

    {:ok, _lv, html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
    assert String.length(sha256) == 64
    assert html =~ sha256
  end

  test "the asset detail view renders the exact byte size as an integer count", %{
    conn: conn,
    user: user
  } do
    bytes = random_bytes(12_345)
    receipt = import!(user.id, bytes, "game.bin")

    {:ok, _lv, html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    assert html =~ "12345 bytes"
  end

  test "the asset detail view renders the source provenance labelled as a client-supplied claim",
       %{conn: conn, user: user} do
    receipt = import!(user.id, random_bytes(64), "declared-name.bin")

    {:ok, _lv, html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    assert html =~ "Reported by the submitting client"
    assert html =~ "declared-name.bin"
  end

  test "the asset detail view renders header fields only for a signature-validated format", %{
    conn: conn,
    user: user
  } do
    bytes = RomFixtures.valid_gba("PLAYSTEAD")
    receipt = import!(user.id, bytes, "playstead.gba", format_bytes: bytes)

    {:ok, _lv, html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    assert html =~ "game_code"
  end

  test "no header fields are rendered for an unrecognized format", %{conn: conn, user: user} do
    receipt = import!(user.id, random_bytes(64), "mystery.bin")

    {:ok, lv, _html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    refute has_element?(lv, "[id$=-header-fields]")
  end

  test "a receipt whose asset has since been identified still displays the outcome recorded at import",
       %{conn: conn, user: user} do
    bytes = RomFixtures.valid_gba("PLAYSTEAD")
    # First import with no reference pack installed (02-09 gap closure:
    # header evidence now reaches classification even with no explicit
    # format_bytes option, so the receipt records the quiet
    # unrecognized{no_reference_installed} reason, not a plain new_asset).
    receipt = import!(user.id, bytes, "playstead.gba")
    assert receipt.outcome == "unrecognized"

    # A later reference-pack install produces recognition evidence for
    # the same blob, independent of the receipt already written.
    {_status, meta} = store!(bytes)

    Recognition.recognize_and_record(
      user.id,
      %{blob_id: meta.blob_id, sha256: meta.sha256, bytes: bytes},
      Playstead.Formats.identify(bytes, "playstead.gba")
    )

    {:ok, _lv, html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    assert html =~ "At import: unrecognized"
    assert html =~ "now: recognized"
  end

  test "two users holding identical bytes each see only their own asset, with no count, hint, or field referencing the other",
       %{conn: conn, user: user} do
    other = owner_fixture()
    bytes = random_bytes(64)

    import!(user.id, bytes, "shared.bin")
    other_receipt = import!(other.id, bytes, "shared.bin")

    {:ok, _lv, html} = live(conn, ~p"/library")

    assert Regex.scan(~r/shared/, html) |> length() == 1

    other_scope = Scope.for_user(other)

    assert {:error, :not_found} =
             Playstead.Catalogue.get_asset_detail(
               Scope.for_user(user),
               other_receipt.asset_set_id
             )

    assert {:ok, _detail} =
             Playstead.Catalogue.get_asset_detail(other_scope, other_receipt.asset_set_id)
  end

  test "no forbidden vocabulary appears in the library or asset detail source", %{
    conn: conn,
    user: user
  } do
    receipt = import!(user.id, random_bytes(64), "mystery.bin")
    {:ok, _lv, _html} = live(conn, ~p"/library")
    {:ok, _lv, _html} = live(conn, ~p"/library/#{receipt.asset_set_id}")

    count =
      "lib/playstead_web/live/library_live.ex"
      |> File.read!()
      |> Kernel.<>(File.read!("lib/playstead_web/live/library_live/asset_detail.ex"))
      |> String.split("\n")
      |> Enum.reject(&(String.trim(&1) |> String.starts_with?("#")))
      |> Enum.join("\n")
      |> then(&Regex.scan(~r/illegal|corrupt file|disposable|virus/i, &1))
      |> length()

    assert count == 0
  end
end
