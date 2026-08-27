defmodule Playstead.Idempotency.PruneExpiredWorker do
  @moduledoc """
  Scheduled Oban job removing idempotency receipts past the ~90-day
  retention horizon (D-20a). Purely housekeeping — no replay/conflict
  correctness in `Playstead.Idempotency` depends on this having run.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Playstead.Idempotency

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _count} = Idempotency.prune_expired()
    :ok
  end
end
