defmodule Playstead.Curation.ContinueTest do
  @moduledoc """
  Plan 03-04 task 3: play sessions, Recent/Continue derivation, and
  continue dismissals (D-07).
  """

  # async: false -- see favorites_test.exs for why (global ChangeJournal
  # advisory lock + many sequential writes here).
  use Playstead.DataCase, async: false

  import Playstead.AccountsFixtures
  import Playstead.CatalogueFixtures

  alias Playstead.Curation
  alias Playstead.Curation.PlaySession
  alias Playstead.Sync.ChangeJournal

  defp record!(user_id, asset_set_id, started_at, ended_at \\ nil) do
    {:ok, session} =
      Curation.record_play_session(user_id, %{
        id: Ecto.UUID.generate(),
        asset_set_id: asset_set_id,
        started_at: started_at,
        ended_at: ended_at
      })

    session
  end

  test "recording a play session creates one row and one recent journal entry" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    started_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    session = record!(user.id, asset_set.id, started_at)
    assert session.asset_set_id == asset_set.id

    entries = ChangeJournal.read_after(user.id, 0, 10)
    entry = Enum.find(entries, &(&1.entity_id == asset_set.id and &1.payload["type"] == "recent"))
    assert entry
  end

  test "posting the same session id twice leaves one row and returns success" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    id = Ecto.UUID.generate()
    started_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    assert {:ok, _} =
             Curation.record_play_session(user.id, %{
               id: id,
               asset_set_id: asset_set.id,
               started_at: started_at
             })

    assert {:ok, _} =
             Curation.record_play_session(user.id, %{
               id: id,
               asset_set_id: asset_set.id,
               started_at: started_at
             })

    assert [%PlaySession{}] =
             Playstead.Repo.all(Ecto.Query.from(s in PlaySession, where: s.user_id == ^user.id))
  end

  test "two sessions for the same game collapse to one Recent entry ordered by the most recent start" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    earlier =
      DateTime.utc_now() |> DateTime.add(-3600, :second) |> DateTime.truncate(:microsecond)

    later = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    _ = record!(user.id, asset_set.id, earlier)
    _ = record!(user.id, asset_set.id, later)

    assert [%{asset_set_id: id, last_played_at: last}] = Curation.list_recent(user.id)
    assert id == asset_set.id
    assert DateTime.compare(last, later) == :eq
  end

  test "Recent for a user who has never played is an empty list" do
    user = owner_fixture()
    assert Curation.list_recent(user.id) == []
  end

  test "Continue equals Recent minus explicitly dismissed games; dismissing leaves it in Recent" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    started_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    _ = record!(user.id, asset_set.id, started_at)

    assert [%{asset_set_id: _}] = Curation.list_continue(user.id)

    assert {:ok, _dismissal} =
             Curation.dismiss_continue(user.id, Ecto.UUID.generate(), asset_set.id)

    assert Curation.list_continue(user.id) == []
    assert [%{asset_set_id: id}] = Curation.list_recent(user.id)
    assert id == asset_set.id
  end

  test "dismissing an already-dismissed game is accepted and changes nothing" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    _ = record!(user.id, asset_set.id, DateTime.utc_now() |> DateTime.truncate(:microsecond))

    assert {:ok, _} = Curation.dismiss_continue(user.id, Ecto.UUID.generate(), asset_set.id)
    assert {:ok, _} = Curation.dismiss_continue(user.id, Ecto.UUID.generate(), asset_set.id)
    assert Curation.list_continue(user.id) == []
  end

  test "playing a dismissed game again returns it to Continue" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    _ = record!(user.id, asset_set.id, DateTime.utc_now() |> DateTime.truncate(:microsecond))

    {:ok, _} = Curation.dismiss_continue(user.id, Ecto.UUID.generate(), asset_set.id)
    assert Curation.list_continue(user.id) == []

    # Force a start time strictly after "now" so it's unambiguously
    # later than the dismissal timestamp recorded above.
    later = DateTime.utc_now() |> DateTime.add(5, :second) |> DateTime.truncate(:microsecond)
    _ = record!(user.id, asset_set.id, later)

    assert [%{asset_set_id: id}] = Curation.list_continue(user.id)
    assert id == asset_set.id
  end

  test "a session naming another user's asset set returns not_found" do
    owner = owner_fixture()
    other = owner_fixture()
    asset_set = asset_set_fixture(other.id)

    assert {:error, :not_found} =
             Curation.record_play_session(owner.id, %{
               id: Ecto.UUID.generate(),
               asset_set_id: asset_set.id,
               started_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
             })
  end

  test "deleting a play session removes it from Recent and tombstones the recent entity" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)

    session =
      record!(user.id, asset_set.id, DateTime.utc_now() |> DateTime.truncate(:microsecond))

    assert [%{asset_set_id: _}] = Curation.list_recent(user.id)
    assert {:ok, :removed} = Curation.delete_play_session(user.id, session.id)
    assert Curation.list_recent(user.id) == []

    entries = ChangeJournal.read_after(user.id, 0, 10)

    tombstone =
      Enum.find(entries, &(&1.entity_id == asset_set.id and &1.operation == "tombstone"))

    assert tombstone
    assert tombstone.payload == %{}
  end

  test "the curation snapshot branch contains recent and continue_dismissal entries" do
    user = owner_fixture()
    asset_set = asset_set_fixture(user.id)
    _ = record!(user.id, asset_set.id, DateTime.utc_now() |> DateTime.truncate(:microsecond))
    {:ok, _} = Curation.dismiss_continue(user.id, Ecto.UUID.generate(), asset_set.id)

    {:ok, page} = Playstead.Sync.Snapshot.read(user.id)
    types = Enum.map(page.curation, & &1.type)

    assert "recent" in types
    assert "continue_dismissal" in types
  end

  test "PlaySession's schema field list is exactly the D-07 fields plus id and timestamps" do
    fields = PlaySession.__schema__(:fields) |> MapSet.new()

    expected =
      MapSet.new([
        :id,
        :user_id,
        :asset_set_id,
        :started_at,
        :ended_at,
        :inserted_at,
        :updated_at
      ])

    assert fields == expected
  end
end
