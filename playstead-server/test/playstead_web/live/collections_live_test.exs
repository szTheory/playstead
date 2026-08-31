defmodule PlaysteadWeb.CollectionsLiveTest do
  @moduledoc """
  Plan 03-05 task 2: `/library/collections` and `/library/collections/:id`
  — manual, flat, ordered collections managed through
  `Playstead.Curation`, the same context the API and the LiveView
  console's other curation surfaces call (D-11).
  """

  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.CatalogueFixtures

  alias Playstead.Curation

  setup :register_and_log_in_user

  test "creates a collection, adds two members, reorders them, removes one, and the collection persists with one member",
       %{conn: conn, user: user} do
    a = asset_set_fixture(user.id, %{display_title: "Alpha"})
    b = asset_set_fixture(user.id, %{display_title: "Bravo"})

    {:ok, lv, _html} = live(conn, ~p"/library/collections")

    lv
    |> form("#create-collection-form", %{"name" => "My Collection"})
    |> render_submit()

    assert [collection] = Curation.list_collections(user.id)

    {:ok, show_lv, _html} = live(conn, ~p"/library/collections/#{collection.id}")

    show_lv
    |> element("#collection-add-#{a.id}")
    |> render_click()

    show_lv
    |> element("#collection-add-#{b.id}")
    |> render_click()

    assert {:ok, [m1, m2]} = Curation.list_collection_members(user.id, collection.id)
    assert m1.asset_set_id == a.id
    assert m2.asset_set_id == b.id

    # Reorder: move Bravo up, ahead of Alpha.
    show_lv
    |> element("#collection-member-#{b.id}-move-up")
    |> render_click()

    assert {:ok, [reordered1, reordered2]} =
             Curation.list_collection_members(user.id, collection.id)

    assert reordered1.asset_set_id == b.id
    assert reordered2.asset_set_id == a.id

    # Remove Alpha, leaving exactly one member.
    show_lv
    |> element("#collection-member-#{a.id}-remove")
    |> render_click()

    assert {:ok, [only_member]} = Curation.list_collection_members(user.id, collection.id)
    assert only_member.asset_set_id == b.id
  end

  test "renaming a collection persists the new name", %{conn: conn, user: user} do
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Old Name")

    {:ok, lv, _html} = live(conn, ~p"/library/collections")

    lv
    |> form("#rename-collection-form-#{collection.id}", %{"name" => "New Name"})
    |> render_submit()

    assert [%{name: "New Name"}] = Curation.list_collections(user.id)
  end

  test "deleting a collection removes it and navigates back to the collections index", %{
    conn: conn,
    user: user
  } do
    {:ok, collection} = Curation.create_collection(user.id, Ecto.UUID.generate(), "Doomed")

    {:ok, lv, _html} = live(conn, ~p"/library/collections")

    lv |> element("#delete-collection-#{collection.id}") |> render_click()

    assert_redirect(lv, ~p"/library/collections")
    assert Curation.list_collections(user.id) == []
  end

  test "the empty collections state invites creating one", %{conn: conn} do
    {:ok, lv, _html} = live(conn, ~p"/library/collections")

    assert has_element?(lv, "#collections-empty", "Create a collection to group games your way.")
  end
end
