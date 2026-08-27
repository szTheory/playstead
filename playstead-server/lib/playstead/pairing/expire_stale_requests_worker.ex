defmodule Playstead.Pairing.ExpireStaleRequestsWorker do
  @moduledoc """
  Housekeeping-only Oban job sweeping stale pending pairing requests to
  `expired` (D-12). Purely cosmetic for anyone reading the `status`
  column directly (e.g. an ops query) — `Playstead.Pairing` itself never
  depends on this having run, since `get_request_status/1` and
  `approve/2` re-derive expiry from `expires_at` on every call.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Playstead.Pairing

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:ok, _count} = Pairing.expire_stale_requests()
    :ok
  end
end
