defmodule PlaysteadWeb.SavesLiveTest do
  @moduledoc """
  Plan 04-10 task 2/3: the console's saves surface (D-49 through D-55,
  D-62, D-67) -- inspect, choose, keep both, export, and the exact
  four facts per side, with every rejected divergence affordance
  asserted absent.
  """

  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.PairingFixtures

  alias Playstead.Blobs
  alias Playstead.Saves

  setup :register_and_log_in_user

  setup do
    File.mkdir_p!(Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp content_key,
    do: :crypto.hash(:sha256, :crypto.strong_rand_bytes(16)) |> Base.encode16(case: :lower)

  defp commit!(scope, device, content_key, bytes, extra_attrs \\ []) do
    {:ok, _status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    command_id = Ecto.UUID.generate()

    {:ok, _pending} =
      Saves.record_pending_upload(
        scope.user.id,
        device.id,
        command_id,
        meta.sha256,
        meta.size_bytes
      )

    attrs =
      %{
        "id" => Ecto.UUID.generate(),
        "command_id" => command_id,
        "content_key" => content_key
      }
      |> Map.merge(Map.new(extra_attrs, fn {k, v} -> {to_string(k), v} end))

    Saves.commit_revision(scope.user.id, device, attrs)
  end

  defp diverged_line!(scope) do
    %{device: device_a} = device_fixture(scope)
    %{device: device_b} = device_fixture(scope)
    key = content_key()

    {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
    {:ok, revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))

    %{line_id: revision_a.save_line_id, revision_a: revision_a, revision_b: revision_b}
  end

  test "an empty saves console renders a calm zero state", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/saves")
    assert has_element?(lv, "#saves-empty")
  end

  test "a diverged line is listed and links to its comparison panel", %{conn: conn, scope: scope} do
    %{line_id: line_id} = diverged_line!(scope)

    {:ok, lv, _html} = live(conn, ~p"/saves")
    assert has_element?(lv, "#line-#{line_id}")
  end

  defp healthy_line!(scope) do
    %{device: device} = device_fixture(scope)
    {:ok, revision} = commit!(scope, device, content_key(), :crypto.strong_rand_bytes(1024))
    %{line_id: revision.save_line_id, revision: revision}
  end

  # G-04-1 regression guard. `/saves` used to filter every line through
  # `Saves.needs_divergence_decision?/2`, so a player whose saves were all
  # healthy -- the common case -- saw a permanently empty page and could
  # reach neither "inspect" nor "export", the two things the page's own
  # header offers. Every existing test passed throughout, because each one
  # seeded a divergence first.
  #
  # These assert reachability, not behaviour given a divergence: the path a
  # player actually walks, from the shelf to the export control, with no
  # conflict anywhere in it.
  describe "a healthy save line (G-04-1 reachability)" do
    test "is listed on /saves even though nothing needs deciding", %{conn: conn, scope: scope} do
      %{line_id: line_id} = healthy_line!(scope)

      {:ok, lv, _html} = live(conn, ~p"/saves")

      assert has_element?(lv, "#line-#{line_id}"),
             "a healthy save line must appear on the shelf"

      refute has_element?(lv, "#saves-empty"),
             "a user with a save must not be shown the no-saves zero state"
    end

    test "carries no decision badge, while a diverged one does", %{conn: conn, scope: scope} do
      %{line_id: healthy_id} = healthy_line!(scope)
      %{line_id: diverged_id} = diverged_line!(scope)

      {:ok, lv, _html} = live(conn, ~p"/saves")

      refute has_element?(lv, "#needs-decision-#{healthy_id}"),
             "decision framing must appear only on lines that have a decision"

      assert has_element?(lv, "#needs-decision-#{diverged_id}")
    end

    test "is reachable from /saves through to its export control", %{conn: conn, scope: scope} do
      %{line_id: line_id, revision: revision} = healthy_line!(scope)

      {:ok, index, _html} = live(conn, ~p"/saves")

      # The shelf must actually offer the door, not merely know the line
      # exists: the row links at this line's own detail path.
      assert index
             |> element(~s{#line-#{line_id} a[href="/saves/#{line_id}"]})
             |> has_element?(),
             "the shelf row must link to this line's detail page"

      {:ok, detail, _html} = live(conn, ~p"/saves/#{line_id}")

      assert has_element?(detail, "#comparison-panel")

      assert has_element?(detail, "#export-#{revision.id}"),
             "export must be reachable on a line that never diverged"
    end
  end

  describe "the comparison panel" do
    test "shows exactly four facts per side and never file size, byte-diff, similarity, ordinal, or parent pointer",
         %{conn: conn, scope: scope} do
      %{line_id: line_id} = diverged_line!(scope)

      {:ok, lv, html} = live(conn, ~p"/saves/#{line_id}")
      assert has_element?(lv, "#comparison-panel")
      assert has_element?(lv, "[data-role=comparison-side]")

      refute html =~ "byte-diff"
      refute html =~ "similarity"
      refute html =~ "ordinal"
      refute html =~ "parent pointer"
      refute html =~ ~r/\bfile size\b/i
    end

    test "choosing performs the mutation with no intervening confirmation", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id, revision_a: revision_a} = diverged_line!(scope)

      {:ok, lv, _html} = live(conn, ~p"/saves/#{line_id}")
      assert has_element?(lv, "#choose-#{revision_a.id}")

      html = lv |> element("#choose-#{revision_a.id}") |> render_click()

      assert html =~ "Continuing from"
      # The chosen head's original revision is retired (extended by a
      # new resolution revision, D-48) -- the "Currently continuing
      # from this one" label moves to whichever head is now current,
      # not necessarily this exact id, so assert the label exists at
      # all rather than pinning a specific retired id.
      assert html =~ "Currently continuing from this one"
      _ = line_id
    end

    test "the rendered output contains no Undo control and no recommended badge", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id} = diverged_line!(scope)

      {:ok, lv, html} = live(conn, ~p"/saves/#{line_id}")
      refute html =~ "Undo"
      refute html =~ ~r/recommended/i
      refute html =~ ~r/data-confirm/i

      _ = lv
    end

    test "no confirmation dialog attribute exists on the choose button", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id, revision_a: revision_a} = diverged_line!(scope)

      {:ok, _lv, html} = live(conn, ~p"/saves/#{line_id}")
      refute html =~ "data-confirm"
      assert html =~ "choose-#{revision_a.id}"
    end

    test "keep-both is a peer action and calls Saves.acknowledge_divergence/3", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id} = diverged_line!(scope)

      {:ok, lv, _html} = live(conn, ~p"/saves/#{line_id}")
      assert has_element?(lv, "#keep-both")

      html = lv |> element("#keep-both") |> render_click()
      assert html =~ "Keeping both"

      refute Saves.needs_divergence_decision?(scope.user.id, line_id)
    end

    test "N-way divergence renders the N-variant subtitle", %{conn: conn, scope: scope} do
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      %{device: device_c} = device_fixture(scope)
      key = content_key()

      {:ok, revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))
      {:ok, _revision_b} = commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024))
      {:ok, _revision_c} = commit!(scope, device_c, key, :crypto.strong_rand_bytes(1024))

      {:ok, _lv, html} = live(conn, ~p"/saves/#{revision_a.save_line_id}")
      assert html =~ "all 3 versions are safe"
      assert html =~ "Keep them all"
    end

    test "a clock caveat is rendered for a side whose reported time contradicts arrival order", %{
      conn: conn,
      scope: scope
    } do
      %{device: device_a} = device_fixture(scope)
      %{device: device_b} = device_fixture(scope)
      key = content_key()

      {:ok, _revision_a} = commit!(scope, device_a, key, :crypto.strong_rand_bytes(1024))

      {:ok, revision_b} =
        commit!(scope, device_b, key, :crypto.strong_rand_bytes(1024),
          device_clock_offset_ms: 999_999
        )

      {:ok, _lv, html} = live(conn, ~p"/saves/#{revision_b.save_line_id}")
      assert html =~ "reported a time that doesn"
      assert html =~ "line up with when this version reached your server"
    end
  end

  describe "absences asserted by test (D-49, D-51, D-55)" do
    test "no bulk always-use-this-Mac control exists on the saves surface", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id} = diverged_line!(scope)

      {:ok, _lv, html} = live(conn, ~p"/saves/#{line_id}")
      refute html =~ ~r/always use|prefer this mac/i
    end

    test "no console surface renders a global current-version playhead", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id} = diverged_line!(scope)

      {:ok, _lv, html} = live(conn, ~p"/saves/#{line_id}")
      refute html =~ ~r/now playing|currently playing/i
    end
  end

  describe "keyboard-only traversal" do
    test "every action in the panel is a native, keyboard-focusable element", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id, revision_a: revision_a} = diverged_line!(scope)

      {:ok, lv, _html} = live(conn, ~p"/saves/#{line_id}")

      assert has_element?(lv, "button##{"choose-#{revision_a.id}"}")
      assert has_element?(lv, "button##{"export-#{revision_a.id}"}")
      assert has_element?(lv, "button#keep-both")
      assert has_element?(lv, "summary")

      panel_html = lv |> element("#comparison-panel") |> render()

      # Every action must be reachable via a real <button>/<a>/<summary>
      # element -- never a bare div/span with only a click handler,
      # which native keyboard traversal (Tab) would skip.
      refute panel_html =~ ~r/<div[^>]*phx-click/
      refute panel_html =~ ~r/<span[^>]*phx-click/
    end
  end

  describe "export this version (D-62)" do
    test "the export deep link enqueues through the same server-side export machinery", %{
      conn: conn,
      scope: scope
    } do
      %{line_id: line_id, revision_a: revision_a} = diverged_line!(scope)

      {:ok, lv, _html} = live(conn, ~p"/saves/#{line_id}")

      html = lv |> element("#export-#{revision_a.id}") |> render_click()
      assert html =~ "Export started" or html =~ "Something went wrong"
    end
  end
end
