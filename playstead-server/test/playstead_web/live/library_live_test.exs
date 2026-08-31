defmodule PlaysteadWeb.LibraryLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Accounts.Scope
  alias Playstead.Blobs
  alias Playstead.Curation
  alias Playstead.Import
  alias Playstead.Recognition
  alias Playstead.RomFixtures
  alias Playstead.Sync.ChangeJournal
  alias PlaysteadWeb.LibraryLive.StatusSlot

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

    # Scoped to the element's own visible text (`>shared<`), not the whole
    # page — an accessible name attribute (e.g. "Add shared to Favorites")
    # legitimately mentions the same user's own asset a second time.
    assert Regex.scan(~r/>shared</, html) |> length() == 1

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

  describe "Task 1: favorites shelf and the single status-slot component (03-05)" do
    test "toggling the favorite control in the console creates the same row and journal entry the API path creates",
         %{conn: conn, user: user} do
      receipt = import!(user.id, random_bytes(64), "favme.bin")
      asset_set_id = receipt.asset_set_id

      {:ok, lv, _html} = live(conn, ~p"/library")

      lv |> element("#asset-#{asset_set_id}-favorite-toggle") |> render_click()

      assert [%{asset_set_id: ^asset_set_id}] = Curation.list_favorites(user.id)

      entries = ChangeJournal.read_after(user.id, 0, 50)
      assert [entry] = Enum.filter(entries, &(&1.entity_kind == "curation"))
      assert entry.operation == "upsert"
      assert entry.payload["type"] == "favorite"
      assert entry.payload["asset_set_id"] == asset_set_id
    end

    test "the Favorites shelf reflects a favorite created directly through Curation.add_favorite/3 without any console interaction",
         %{conn: conn, user: user} do
      receipt = import!(user.id, random_bytes(64), "favdirect.bin")

      {:ok, _favorite} =
        Curation.add_favorite(user.id, Ecto.UUID.generate(), receipt.asset_set_id)

      {:ok, _lv, html} = live(conn, ~p"/library")

      assert html =~ ~s(id="favorites-shelf")
      assert html =~ ~s(id="game-card-#{receipt.asset_set_id}")
    end

    test "a card for content with no reference match renders the quiet badge and carries no error/warning role",
         %{conn: conn, user: user} do
      receipt = import!(user.id, random_bytes(64), "quiet.bin")

      {:ok, _favorite} =
        Curation.add_favorite(user.id, Ecto.UUID.generate(), receipt.asset_set_id)

      {:ok, lv, _html} = live(conn, ~p"/library")

      assert has_element?(lv, "#game-card-#{receipt.asset_set_id}-unidentified")
      card_html = lv |> element("#game-card-#{receipt.asset_set_id}") |> render()
      refute card_html =~ ~s(role="alert")
      refute card_html =~ ~s(role="warning")
    end

    test "StatusSlot renders exactly one indicator element for an input carrying several simultaneous states, and the higher-ladder state wins" do
      html =
        render_component(&StatusSlot.status_slot/1, %{
          id: "multi-status",
          title: "Multi-State Game",
          needs_attention: false,
          missing_dependency: true,
          downloading: true,
          queued: true,
          pinned: true,
          verified: true
        })

      assert Regex.scan(~r/data-status-slot="true"/, html) |> length() == 1
      assert html =~ ~s(data-status="missing_dependency")
      refute html =~ ~s(data-status="downloading")
    end

    test "every status variant's rendered markup contains a glyph element and an accessible name" do
      for state <- StatusSlot.ladder() do
        assigns =
          %{
            id: "status-#{state}",
            title: "Some Game",
            needs_attention: false,
            missing_dependency: false,
            downloading: false,
            download_percent: 42,
            queued: false,
            pinned: false,
            verified: false
          }
          |> Map.put(state, true)

        html = render_component(&StatusSlot.status_slot/1, assigns)

        assert html =~ ~s(status-slot-glyph)
        assert html =~ "aria-label"
      end
    end

    test "the CSS defines the system-accent and status color vocabularies with no shared value" do
      css = File.read!("assets/css/app.css")

      system_accents =
        Regex.scan(~r/--system-accent-[a-z]+:\s*(#[0-9a-fA-F]+);/, css) |> Enum.map(&List.last/1)

      statuses =
        Regex.scan(~r/--status-[a-z-]+:\s*(#[0-9a-fA-F]+);/, css) |> Enum.map(&List.last/1)

      assert length(system_accents) > 0
      assert length(statuses) > 0
      assert MapSet.disjoint?(MapSet.new(system_accents), MapSet.new(statuses))
    end

    test "the LiveView never calls the repository directly" do
      refute File.read!("lib/playstead_web/live/library_live.ex") =~ ~r/Repo\./
    end
  end
end
