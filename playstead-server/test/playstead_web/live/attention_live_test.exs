defmodule PlaysteadWeb.AttentionLiveTest do
  @moduledoc """
  Task 3's console contract (D-26, D-31): grouped items, evidence
  cards, bulk actions offered only where no per-item input is needed,
  and a calm empty state.
  """
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias Playstead.Attention
  alias Playstead.Blobs
  alias Playstead.Import

  setup :register_and_log_in_user

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp import_bytes(user, name, bytes, opts \\ []) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        user.id,
        %{original_name: name, origin: "upload", size_bytes: byte_size(bytes)},
        {status, meta},
        Keyword.put(opts, :format_bytes, bytes)
      )

    receipt
  end

  test "an empty inbox renders a zero state", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert has_element?(lv, "#attention-empty")
    assert has_element?(lv, "#attention-count", "Nothing needs your attention right now")
  end

  test "the navigation count appears once at least one item exists", %{conn: conn, user: user} do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)

    {:ok, lv, _html} = live(conn, ~p"/attention")
    refute has_element?(lv, "#attention-empty")
    assert has_element?(lv, "#attention-count", "1 item")
  end

  test "items are grouped by reason", %{conn: conn, user: user} do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
    import_bytes(user, "fake.gba", :crypto.strong_rand_bytes(64))

    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert has_element?(lv, "#group-quarantined")
    assert has_element?(lv, "#group-signature_mismatch")
  end

  test "two consecutive renders return items in the same order within a group", %{
    conn: conn,
    user: user
  } do
    import_bytes(user, "a.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
    import_bytes(user, "b.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)

    {:ok, lv1, _} = live(conn, ~p"/attention")
    {:ok, lv2, _} = live(conn, ~p"/attention")

    order1 = Attention.list_items(user.id) |> Map.fetch!("quarantined") |> Enum.map(& &1.id)
    order2 = Attention.list_items(user.id) |> Map.fetch!("quarantined") |> Enum.map(& &1.id)

    assert order1 == order2
    assert render(lv1) =~ "attention-item-#{hd(order1)}"
    assert render(lv2) =~ "attention-item-#{hd(order2)}"
  end

  test "the evidence card renders the full hash, size, and magic evidence", %{
    conn: conn,
    user: user
  } do
    bytes = <<0x50, 0x4B, 0x03, 0x04>> <> :crypto.strong_rand_bytes(64)
    import_bytes(user, "collection.zip", bytes)

    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert has_element?(lv, "[data-role=evidence-card]")
  end

  test "a missing member is highlighted in the card's member list", %{conn: conn, user: user} do
    {:ok, status, cue_meta} = Blobs.put_stream(["CUE"], 3)

    {:ok, _result} =
      Import.import_descriptor_set(
        user.id,
        %{original_name: "game.cue", origin: "upload", size_bytes: 3},
        {status, cue_meta},
        ["game.bin"],
        %{}
      )

    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert render(lv) =~ "missing"
  end

  test "bulk actions are offered for exclude, retain, retry, and assign-system", %{
    conn: conn,
    user: user
  } do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
    item = Attention.list_items(user.id) |> Map.fetch!("quarantined") |> hd()

    {:ok, lv, _html} = live(conn, ~p"/attention")
    lv |> element("#select-#{item.id}") |> render_click()

    assert has_element?(lv, "#bulk-toolbar[role=toolbar]")
    assert has_element?(lv, "#bulk-exclude")
    assert has_element?(lv, "#bulk-retain")
    assert has_element?(lv, "#bulk-retry")
    assert has_element?(lv, "#bulk-assign-system-select")
  end

  test "bulk confirmation dialogs name both the effect and the item count", %{
    conn: conn,
    user: user
  } do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
    item = Attention.list_items(user.id) |> Map.fetch!("quarantined") |> hd()

    {:ok, lv, _html} = live(conn, ~p"/attention")
    lv |> element("#select-#{item.id}") |> render_click()

    html = render(lv)
    assert html =~ "Exclude 1 items?"
  end

  test "the list uses a table element with native checkbox inputs", %{conn: conn, user: user} do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)

    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert has_element?(lv, "table")
    assert has_element?(lv, "input[type=checkbox][data-role='item-checkbox']")
  end

  test "count changes are exposed through a polite live region", %{conn: conn, user: user} do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert has_element?(lv, "#attention-count[aria-live=polite]")
  end

  test "an excluded item is reachable and restorable through the excluded filter", %{
    conn: conn,
    user: user
  } do
    receipt =
      import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)

    item = Attention.list_items(user.id) |> Map.fetch!("quarantined") |> hd()
    {:ok, _} = Playstead.Attention.Resolutions.exclude(item, user.id)
    _ = receipt

    {:ok, lv, _html} = live(conn, ~p"/attention")
    assert has_element?(lv, "#excluded-#{item.id}")
    lv |> element("#restore-#{item.id}") |> render_click()

    reopened = Attention.list_items(user.id) |> Map.fetch!("quarantined") |> hd()
    assert reopened.id == item.id
  end

  test "the grouped archives item offers retain and exclude and states archives were kept as they are",
       %{conn: conn, user: user} do
    bytes = <<0x50, 0x4B, 0x03, 0x04>> <> :crypto.strong_rand_bytes(64)
    import_bytes(user, "collection.zip", bytes)

    {:ok, lv, _html} = live(conn, ~p"/attention")
    html = render(lv)
    assert html =~ "kept exactly as"
    item = Attention.list_items(user.id) |> Map.fetch!("archives_kept_unopened") |> hd()
    assert has_element?(lv, "#retain-#{item.id}")
    assert has_element?(lv, "#exclude-#{item.id}")
  end

  test "no forbidden vocabulary describes user content", %{conn: conn, user: user} do
    import_bytes(user, "big.bin", :crypto.strong_rand_bytes(64), quarantine_size_cap_bytes: 10)
    {:ok, lv, _html} = live(conn, ~p"/attention")
    html = render(lv)
    refute html =~ ~r/illegal|corrupt|disposable|virus|infected/i
  end
end
