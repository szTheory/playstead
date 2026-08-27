defmodule Playstead.SyncFixtures do
  @moduledoc """
  Test helpers for the change-journal/cursor/snapshot subsystem
  (PROT-05, D-21).
  """

  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  @doc """
  Appends a journal entry directly, wrapped in its own transaction (most
  call sites in production wire this into an existing mutation's
  transaction — for fixture purposes a dedicated transaction is fine
  since there is no accompanying effect to keep atomic with).
  """
  def journal_entry_fixture(
        user_id,
        entity_kind \\ :device,
        entity_id \\ Ecto.UUID.generate(),
        payload \\ %{}
      ) do
    {:ok, entry} =
      Repo.transaction(fn ->
        case ChangeJournal.append(user_id, entity_kind, entity_id, payload) do
          {:ok, entry} -> entry
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    entry
  end

  @doc "Appends a tombstone entry directly, in its own transaction."
  def journal_tombstone_fixture(
        user_id,
        entity_kind \\ :device,
        entity_id \\ Ecto.UUID.generate()
      ) do
    {:ok, entry} =
      Repo.transaction(fn ->
        case ChangeJournal.tombstone(user_id, entity_kind, entity_id) do
          {:ok, entry} -> entry
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    entry
  end
end
