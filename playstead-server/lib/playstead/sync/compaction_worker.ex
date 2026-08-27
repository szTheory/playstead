defmodule Playstead.Sync.CompactionWorker do
  @moduledoc """
  Scheduled Oban job removing change-journal entries past
  `Playstead.Sync.Compaction.horizon/0` (PROT-05, D-21). Purely
  housekeeping — the `/changes` endpoint's 410 decision is exact
  regardless of when this last ran; it only reflects whatever the
  journal's current oldest surviving sequence actually is.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Playstead.Sync.Compaction

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _count} = Compaction.run()
    :ok
  end
end
