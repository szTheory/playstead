defmodule Playstead.Sync do
  @moduledoc """
  Facade over the sync subsystem (PROT-05, D-21): cursor decode, journal
  read, and the compaction-boundary check that decides between 200 and
  410, so `PlaysteadWeb.Api.V1.ChangesController` and
  `PlaysteadWeb.Api.V1.SnapshotController` stay thin — neither controller
  makes a compatibility or expiry decision of its own.
  """

  alias Playstead.Sync.{Cursor, ChangeJournal, Compaction, Entry}

  @page_size 200

  @doc """
  Reads the change feed for `user_id` after `cursor` (or from the
  beginning when `cursor` is `nil`). This is a read-only call: it never
  writes, never advances any server-held position, and is safe to call
  any number of times with the same cursor — the client owns its
  position entirely.

  Returns `{:error, :cursor_invalid}` for a malformed/tampered/foreign
  cursor, or `{:error, :cursor_expired}` when the cursor's position
  predates the compaction horizon (`Playstead.Sync.Compaction`).
  """
  @spec changes_after(pos_integer(), String.t() | nil) ::
          {:ok, %{entries: [Entry.t()], cursor: String.t(), has_more: boolean()}}
          | {:error, :cursor_invalid}
          | {:error, :cursor_expired}
  # `nil` — no cursor at all — is a genuinely fresh client that has
  # never synced; it always reads from wherever the journal currently
  # begins and is never expired, regardless of compaction history.
  def changes_after(user_id, nil), do: read_from(user_id, 0)

  # A *decoded* cursor of any value, including 0, is a position a
  # client actually holds (it received it from a previous response) —
  # unlike `nil`, it is checked against the compaction boundary like
  # any other cursor, since the entries between it and the current
  # surviving boundary may genuinely have been compacted away.
  def changes_after(user_id, cursor) when is_binary(cursor) do
    case Cursor.decode(cursor) do
      {:ok, seq} ->
        if expired?(seq), do: {:error, :cursor_expired}, else: read_from(user_id, seq)

      :error ->
        {:error, :cursor_invalid}
    end
  end

  def changes_after(_user_id, _cursor), do: {:error, :cursor_invalid}

  defp read_from(user_id, after_seq) do
    entries = ChangeJournal.read_after(user_id, after_seq, @page_size + 1)
    {page, has_more} = split_page(entries)
    next_seq = page |> List.last() |> next_seq_or(after_seq)

    {:ok, %{entries: page, cursor: Cursor.encode(next_seq), has_more: has_more}}
  end

  # A cursor is expired when there's at least one entry between it and
  # the oldest surviving sequence that has been compacted away. A
  # journal that was never compacted (or is empty) never expires
  # anything.
  defp expired?(after_seq) do
    case Compaction.oldest_surviving_seq() do
      nil -> false
      oldest -> after_seq < oldest - 1
    end
  end

  defp split_page(entries) when length(entries) > @page_size do
    {Enum.take(entries, @page_size), true}
  end

  defp split_page(entries), do: {entries, false}

  defp next_seq_or(nil, after_seq), do: after_seq
  defp next_seq_or(%{seq: seq}, _after_seq), do: seq

  @doc "Delegates to `Playstead.Sync.Snapshot.read/2` (task 3)."
  @spec snapshot(pos_integer(), keyword()) :: {:ok, map()}
  def snapshot(user_id, opts \\ []), do: Playstead.Sync.Snapshot.read(user_id, opts)
end
