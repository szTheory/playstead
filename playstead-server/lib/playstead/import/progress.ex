defmodule Playstead.Import.Progress do
  @moduledoc """
  Bounded, honest progress for a session (D-09), and the throttled
  `:job` change-journal checkpoint (D-30, T-02-37).

  Bytes drive the progress bar — file counts lie badly on a mixed
  collection where one disc image outweighs a thousand cartridge dumps
  — with the file count kept only as the caption. A time estimate
  appears only once enumeration has finished and at least ten seconds
  of throughput have been observed, and is always rounded to whole
  minutes, never expressed in seconds.

  `checkpoint/2` appends a `:job` journal entry no more often than
  every #{5} seconds and no closer than #{1}% of progress apart — a
  per-file entry is explicitly excluded, since a 250,000-file session
  would otherwise flood every client's change feed with entries
  carrying no decision value.
  """

  alias Playstead.Import.Session
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  @checkpoint_interval_seconds 5
  @checkpoint_min_delta_percent 1
  @eta_min_observation_seconds 10

  @type summary :: %{
          bytes_completed: non_neg_integer(),
          total_bytes: non_neg_integer(),
          files_completed: non_neg_integer(),
          file_count: non_neg_integer(),
          eta_minutes: pos_integer() | nil
        }

  @doc """
  The session's current, honest progress: authoritative counts re-read
  from the database row (never accumulated from a stream of hints), a
  byte ratio and a file-count caption, and a rounded-minutes ETA that
  is `nil` until it can be honestly stated.
  """
  @spec summary(Session.t()) :: summary()
  def summary(%Session{} = session) do
    %{
      bytes_completed: session.bytes_completed,
      total_bytes: session.total_bytes,
      files_completed: session.files_completed,
      file_count: session.file_count,
      eta_minutes: eta_minutes(session)
    }
  end

  defp eta_minutes(%Session{enumeration_completed_at: nil}), do: nil
  defp eta_minutes(%Session{started_at: nil}), do: nil
  defp eta_minutes(%Session{bytes_completed: bytes}) when bytes <= 0, do: nil

  defp eta_minutes(%Session{} = session) do
    elapsed = DateTime.diff(DateTime.utc_now(), session.started_at, :second)

    if elapsed >= @eta_min_observation_seconds do
      rate = session.bytes_completed / elapsed
      remaining_bytes = max(session.total_bytes - session.bytes_completed, 0)

      if rate > 0 do
        remaining_minutes = remaining_bytes / rate / 60
        max(round(remaining_minutes), 1)
      end
    end
  end

  @doc """
  Appends a throttled `:job` journal entry and records the checkpoint
  position, or returns `session` unchanged when the throttle rule has
  not yet been satisfied.
  """
  @spec checkpoint(Session.t(), keyword()) :: Session.t()
  def checkpoint(%Session{} = session, opts \\ []) do
    if should_checkpoint?(session, opts) do
      {:ok, _entry} = ChangeJournal.append(session.user_id, :job, session.id, %{})

      session
      |> Ecto.Changeset.change(
        last_checkpoint_at: DateTime.utc_now(),
        last_checkpointed_bytes: session.bytes_completed
      )
      |> Repo.update!()
    else
      session
    end
  end

  defp should_checkpoint?(%Session{last_checkpoint_at: nil}, _opts), do: true

  defp should_checkpoint?(%Session{} = session, opts) do
    interval = Keyword.get(opts, :interval_seconds, @checkpoint_interval_seconds)
    min_delta = Keyword.get(opts, :min_delta_percent, @checkpoint_min_delta_percent)

    DateTime.diff(DateTime.utc_now(), session.last_checkpoint_at, :second) >= interval and
      delta_percent(session) >= min_delta
  end

  defp delta_percent(%Session{total_bytes: total}) when total <= 0, do: 100

  defp delta_percent(%Session{} = session) do
    (session.bytes_completed - (session.last_checkpointed_bytes || 0)) / session.total_bytes * 100
  end
end
