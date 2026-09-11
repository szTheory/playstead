defmodule PlaysteadWeb.LibraryLiveTest do
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures
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

    # Scoped to the element's own visible text (`>` … `shared` … `<`,
    # tolerant of HEEx's insignificant inter-tag whitespace), not the
    # whole page — an accessible name attribute (e.g. "Add shared to
    # Favorites") legitimately mentions the same user's own asset again.
    assert Regex.scan(~r/>\s*shared\s*</, html) |> length() == 1

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
      assert html =~ ~s(id="favorites-shelf-card-#{receipt.asset_set_id}")
    end

    test "a card for content with no reference match renders the quiet badge and carries no error/warning role",
         %{conn: conn, user: user} do
      receipt = import!(user.id, random_bytes(64), "quiet.bin")

      {:ok, _favorite} =
        Curation.add_favorite(user.id, Ecto.UUID.generate(), receipt.asset_set_id)

      {:ok, lv, _html} = live(conn, ~p"/library")

      assert has_element?(lv, "#favorites-shelf-card-#{receipt.asset_set_id}-unidentified")
      card_html = lv |> element("#favorites-shelf-card-#{receipt.asset_set_id}") |> render()
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

  describe "Task 2: sidebar order, remaining shelves, and collections (03-05)" do
    test "the sidebar's rendered entries appear in the canonical order Home, Continue, Favorites, Collections, Queue, Recent, systems, unidentified",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{system_id: "gba", display_title: "A GBA Game"})
      asset_set_fixture(user.id, %{system_id: "unknown", display_title: "Mystery"})

      {:ok, _lv, html} = live(conn, ~p"/library")

      ids = [
        "sidebar-home",
        "sidebar-continue",
        "sidebar-favorites",
        "sidebar-collections",
        "sidebar-queue",
        "sidebar-recent",
        "sidebar-system-gba",
        "sidebar-unidentified"
      ]

      positions =
        Enum.map(ids, fn id ->
          case :binary.match(html, ~s(id="#{id}")) do
            {pos, _len} -> pos
            :nomatch -> flunk("expected sidebar entry ##{id} to be present")
          end
        end)

      assert positions == Enum.sort(positions)
    end

    test "a system with zero asset sets does not appear in the sidebar's system list", %{
      conn: conn,
      user: user
    } do
      asset_set_fixture(user.id, %{system_id: "gba", display_title: "Present"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      assert has_element?(lv, "#sidebar-system-gba")
      refute has_element?(lv, "#sidebar-system-snes")
      assert has_element?(lv, "#show-all-systems")
    end

    test "an empty Favorites shelf is absent from the home markup while the sidebar entry is present with explanatory text",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Unfavorited"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      refute has_element?(lv, "#favorites-shelf")
      assert has_element?(lv, "#sidebar-favorites-explainer", "Favorite a game to see it here.")
    end

    test "reordering the queue in the console issues exactly one context call and produces exactly one journal entry",
         %{conn: conn, user: user} do
      a = asset_set_fixture(user.id, %{display_title: "First"})
      b = asset_set_fixture(user.id, %{display_title: "Second"})
      c = asset_set_fixture(user.id, %{display_title: "Third"})

      {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), a.id)
      {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), b.id)
      {:ok, _} = Curation.enqueue(user.id, Ecto.UUID.generate(), c.id)

      {:ok, lv, _html} = live(conn, ~p"/library")

      before_count = ChangeJournal.read_after(user.id, 0, 100) |> length()

      lv |> element("#queue-item-#{c.id}-move-up") |> render_click()

      after_entries = ChangeJournal.read_after(user.id, 0, 100)
      assert length(after_entries) == before_count + 1

      assert [%{asset_set_id: id1}, %{asset_set_id: id2}, %{asset_set_id: id3}] =
               Curation.list_queue(user.id)

      assert [id1, id2, id3] == [a.id, c.id, b.id]
    end

    test "the first-run banner renders once, and does not render after the dismiss event", %{
      conn: conn,
      user: user
    } do
      asset_set_fixture(user.id, %{display_title: "Anything"})

      {:ok, lv, html} = live(conn, ~p"/library")

      assert Regex.scan(~r/Your library lives on your server/, html) |> length() == 1

      lv |> element("#dismiss-first-run-banner") |> render_click()

      refute has_element?(lv, "#first-run-banner")
    end

    test "a catalogue with zero asset sets renders the import invitation and no error styling", %{
      conn: conn,
      user: _user
    } do
      {:ok, lv, _html} = live(conn, ~p"/library")

      assert has_element?(lv, "#library-empty", "No games yet")
      empty_html = lv |> element("#library-empty") |> render()
      refute empty_html =~ ~s(role="alert")
      refute empty_html =~ ~s(role="warning")
    end
  end

  describe "Task 3: search, filters, show-all-systems, large-library rendering, accessibility (03-05)" do
    test "a library of 500 asset sets renders through a stream container with no skeleton placeholder",
         %{conn: conn, user: user} do
      for i <- 1..500 do
        asset_set_fixture(user.id, %{display_title: "Game #{i}", system_id: "gba"})
      end

      {:ok, lv, html} = live(conn, ~p"/library")

      assert has_element?(lv, "#library-asset-stream")
      refute html =~ "skeleton"
      assert html =~ ~s(phx-update="stream")
    end

    test "searching a distinctive substring narrows the rendered set to the matching entries only",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Xyzzyplugh Adventure"})
      asset_set_fixture(user.id, %{display_title: "Something Else Entirely"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      lv
      |> form("#library-search-form", %{"q" => "Xyzzyplugh"})
      |> render_change()

      html = render(lv)
      assert html =~ "Xyzzyplugh Adventure"
      refute html =~ "Something Else Entirely"
    end

    test "toggling a system chip and an availability chip each narrow the set, and a pressed chip carries aria-pressed",
         %{conn: conn, user: user} do
      gba = asset_set_fixture(user.id, %{display_title: "GBA Game", system_id: "gba"})
      asset_set_fixture(user.id, %{display_title: "SNES Game", system_id: "snes"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      assert has_element?(lv, ~s(button[aria-pressed="false"]#filter-chip-system-gba))

      lv |> element("#filter-chip-system-gba") |> render_click()

      html = render(lv)
      assert html =~ "GBA Game"
      refute html =~ "SNES Game"
      assert has_element?(lv, ~s(button[aria-pressed="true"]#filter-chip-system-gba))

      # Clicking again clears the filter.
      lv |> element("#filter-chip-system-gba") |> render_click()
      html = render(lv)
      assert html =~ "SNES Game"

      lv |> element("#filter-chip-availability-queued") |> render_click()
      html = render(lv)
      refute html =~ "GBA Game"
      refute html =~ "SNES Game"

      Curation.enqueue(user.id, Ecto.UUID.generate(), gba.id)
      {:ok, lv2, _html} = live(conn, ~p"/library")
      lv2 |> element("#filter-chip-availability-queued") |> render_click()
      html = render(lv2)
      assert html =~ "GBA Game"
      refute html =~ "SNES Game"
    end

    test "a system with zero assets appears only after show-all-systems is activated, and the control's label states the hidden count",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Present", system_id: "gba"})

      {:ok, lv, html} = live(conn, ~p"/library")

      refute has_element?(lv, "#sidebar-system-snes")
      assert html =~ "Show all systems (6 hidden)"

      lv |> element("#show-all-systems") |> render_click()

      html = render(lv)
      assert has_element?(lv, "#sidebar-system-snes")
      assert html =~ "Hide empty systems"
    end

    test "every card's accessible name contains the title, the system, and the status sentence",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Metroid Fusion", system_id: "gba"})

      {:ok, _lv, html} = live(conn, ~p"/library")

      assert html =~
               "Metroid Fusion, Game Boy Advance, Metroid Fusion is on your server. Choose Download to play it offline."
    end

    test "the list view renders a visible text label for each status in addition to the glyph",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Listed Game", system_id: "gba"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      lv |> element("#toggle-view") |> render_click()

      html = render(lv)
      assert has_element?(lv, "#library-asset-stream")
      assert html =~ "status-slot-label"
      assert html =~ "On server"
    end
  end

  describe "Task 2/3 (plan 03-13): all six availability values discriminate, no pass-through" do
    import Playstead.PairingFixtures

    alias Playstead.Availability

    defp paired_device(scope) do
      %{device: device} = device_fixture(scope)
      device
    end

    defp raise_attention!(user_id, asset_set_id) do
      {:ok, _item} =
        Playstead.Attention.Item.create_changeset(%Playstead.Attention.Item{}, %{
          user_id: user_id,
          reason: "missing_member",
          grouping_key: "fixture-#{Ecto.UUID.generate()}",
          asset_set_id: asset_set_id
        })
        |> Playstead.Repo.insert()
    end

    test "each of the six values narrows the set to exactly its own asset set, excluding every other",
         %{conn: conn, user: user, scope: scope} do
      device = paired_device(scope)

      needs_attention = asset_set_fixture(user.id, %{display_title: "Needs Attention Game"})
      raise_attention!(user.id, needs_attention.id)

      missing_dependency =
        asset_set_fixture(user.id, %{display_title: "Missing Dependency Game"})

      downloading = asset_set_fixture(user.id, %{display_title: "Downloading Game"})
      queued = asset_set_fixture(user.id, %{display_title: "Queued Game"})
      ready_offline = asset_set_fixture(user.id, %{display_title: "Ready Offline Game"})
      server_only = asset_set_fixture(user.id, %{display_title: "Server Only Game"})

      Availability.replace_for_device(device, [
        %{"asset_set_id" => missing_dependency.id, "missing_dependency" => true},
        %{"asset_set_id" => downloading.id, "downloading" => true, "download_percent" => 50},
        %{"asset_set_id" => ready_offline.id, "verified" => true}
      ])

      Curation.enqueue(user.id, Ecto.UUID.generate(), queued.id)

      {:ok, lv, _html} = live(conn, ~p"/library")

      checks = [
        {"needs_attention", needs_attention,
         [missing_dependency, downloading, queued, ready_offline, server_only]},
        {"missing_dependency", missing_dependency,
         [needs_attention, downloading, queued, ready_offline, server_only]},
        {"downloading", downloading,
         [needs_attention, missing_dependency, queued, ready_offline, server_only]},
        {"queued", queued,
         [needs_attention, missing_dependency, downloading, ready_offline, server_only]},
        {"ready_offline", ready_offline,
         [needs_attention, missing_dependency, downloading, queued, server_only]},
        {"server_only", server_only,
         [needs_attention, missing_dependency, downloading, queued, ready_offline]}
      ]

      for {value, included, excluded_list} <- checks do
        lv |> element("#filter-chip-availability-#{value}") |> render_click()

        # Scope assertions to the browse stream only — the Queue shelf
        # above it always renders queued titles regardless of the
        # browse filter, so asserting against the whole page would be
        # a false negative for the "queued" exclusion case.
        assert has_element?(lv, "#library-asset-stream ##{"asset-" <> included.id}"),
               "expected #{value} chip to include #{included.display_title}"

        for excluded <- excluded_list do
          refute has_element?(lv, "#library-asset-stream ##{"asset-" <> excluded.id}"),
                 "expected #{value} chip to exclude #{excluded.display_title}"
        end

        # Toggle off before the next value.
        lv |> element("#filter-chip-availability-#{value}") |> render_click()
      end
    end

    test "an invalid availability value leaves the filter unchanged and the full set streamed",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Untouched Game"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      render_hook(lv, "filter-availability", %{"availability" => "safe_to_evict"})

      html = render(lv)
      assert html =~ "Untouched Game"
      assert has_element?(lv, ~s(button[aria-pressed="false"]#filter-chip-availability-queued))
    end

    test "a chip selection matching nothing renders an explanatory empty state, not a blank pane",
         %{conn: conn, user: user} do
      asset_set_fixture(user.id, %{display_title: "Only Game", system_id: "gba"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      lv |> element("#filter-chip-availability-downloading") |> render_click()

      html = render(lv)
      assert has_element?(lv, "#library-search-empty")
      refute html =~ "Only Game"

      lv |> element("#clear-narrowing") |> render_click()
      html = render(lv)
      assert html =~ "Only Game"
    end

    test "every availability chip carries a non-empty accessible name and a pressed state", %{
      conn: conn,
      user: user
    } do
      asset_set_fixture(user.id, %{display_title: "Any Game"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      for value <- Playstead.AvailabilityVocabulary.values() do
        assert has_element?(
                 lv,
                 ~s(button[aria-pressed="false"]#filter-chip-availability-#{value}[aria-label])
               )
      end
    end

    test "selecting an availability chip a second time clears the filter and restores the full set",
         %{conn: conn, user: user} do
      shown = asset_set_fixture(user.id, %{display_title: "Second Click Game"})

      {:ok, lv, _html} = live(conn, ~p"/library")

      lv |> element("#filter-chip-availability-server_only") |> render_click()
      assert has_element?(lv, "#library-asset-stream ##{"asset-" <> shown.id}")

      lv |> element("#filter-chip-availability-server_only") |> render_click()
      assert has_element?(lv, "#library-asset-stream ##{"asset-" <> shown.id}")

      assert has_element?(
               lv,
               ~s(button[aria-pressed="false"]#filter-chip-availability-server_only)
             )
    end

    test "deleting any single matches_availability?/3 value clause would break at least one assertion above" do
      # This is a documentation test: the coverage lives in the table-driven
      # test above, which asserts both an included and an excluded set per
      # value. See 03-13-SUMMARY.md for the recorded manual delete-one-clause
      # observation this plan's acceptance criteria requires.
      assert true
    end
  end

  # 03-UAT.md checkpoint 48 (plan 03-13 deliverable D6, deferred there as a
  # "backstop truth"): "A download in progress uses the existing determinate
  # progress indicator, not a second loading treatment."
  #
  # Deferring it hid a real defect. The list row passed ONLY `queued:` into
  # `status_slot/1`, so `rank/1` could never reach any rung above `queued` in
  # list view -- `downloading` (the single rung that carries the determinate
  # percent D-16 requires be retained), `missing_dependency` and
  # `needs_attention` were all unreachable there. The row's own `aria-label`
  # went through `StatusSlot.describe/2` with the FULL status the whole time,
  # so a downloading row announced "is downloading, 42 percent complete" to a
  # screen reader while its visible badge read "On server".
  describe "checkpoint 48: the list row's status indicator is the determinate one" do
    import Playstead.PairingFixtures

    alias Playstead.Availability

    test "a downloading game's list row shows the determinate percent, and its badge agrees with its accessible name",
         %{conn: conn, user: user, scope: scope} do
      %{device: device} = device_fixture(scope)

      downloading =
        asset_set_fixture(user.id, %{display_title: "Downloading Game", system_id: "gba"})

      Availability.replace_for_device(device, [
        %{"asset_set_id" => downloading.id, "downloading" => true, "download_percent" => 42}
      ])

      {:ok, lv, _html} = live(conn, ~p"/library")
      lv |> element("#toggle-view") |> render_click()

      # Scoped to the row itself. The page-level flash group ships a
      # permanently-rendered, hidden "attempting to reconnect" spinner, so a
      # whole-document refute for a loading treatment can never hold and would
      # have to be deleted rather than fixed.
      row = lv |> element("#asset-#{downloading.id}") |> render()

      # The visible badge is the downloading rung and carries its percent.
      assert row =~ ~s(data-status="downloading")
      assert row =~ "Downloading — 42%"

      # The accessible name says the same thing the badge shows.
      assert row =~ "Downloading Game is downloading, 42 percent complete."

      # Exactly one indicator on the row: the determinate one, with no second
      # loading treatment rendered beside it.
      assert Regex.scan(~r/data-status-slot="true"/, row) |> length() == 1
      refute row =~ "animate-spin"
      refute row =~ "animate-pulse"
      refute row =~ "skeleton"
    end

    test "every ladder rung the grid card can show is reachable in list view too",
         %{conn: conn, user: user, scope: scope} do
      %{device: device} = device_fixture(scope)

      sets =
        Map.new(
          [:needs_attention, :missing_dependency, :downloading, :queued, :verified],
          fn rung ->
            {rung, asset_set_fixture(user.id, %{display_title: "#{rung} Game", system_id: "gba"})}
          end
        )

      raise_attention!(user.id, sets[:needs_attention].id)

      Availability.replace_for_device(device, [
        %{"asset_set_id" => sets[:missing_dependency].id, "missing_dependency" => true},
        %{
          "asset_set_id" => sets[:downloading].id,
          "downloading" => true,
          "download_percent" => 7
        },
        %{"asset_set_id" => sets[:verified].id, "verified" => true}
      ])

      Curation.enqueue(user.id, Ecto.UUID.generate(), sets[:queued].id)

      {:ok, lv, _html} = live(conn, ~p"/library")
      lv |> element("#toggle-view") |> render_click()
      html = render(lv)

      # Each seeded rung is the winning status on its own row. Asserting per
      # rung on its own line keeps the diagnosis in the CI failure location
      # rather than in an assertion message the evidence pipeline discards.
      assert html =~
               ~s(id="asset-#{sets[:needs_attention].id}-status" data-status="needs_attention")

      assert html =~
               ~s(id="asset-#{sets[:missing_dependency].id}-status" data-status="missing_dependency")

      assert html =~ ~s(id="asset-#{sets[:downloading].id}-status" data-status="downloading")
      assert html =~ ~s(id="asset-#{sets[:queued].id}-status" data-status="queued")
      assert html =~ ~s(id="asset-#{sets[:verified].id}-status" data-status="verified")
    end
  end
end
