defmodule Playstead.Pairing.RotationAuditWorker do
  @moduledoc """
  Asynchronously records the `credential_rotated` audit event for a
  command-scoped credential rotation. Enqueued with Oban's `unique`
  option keyed on the same `command_id` the rotation itself upserts on
  (D-20b) — a replayed enqueue (from a replayed outbox command)
  converges to the existing job rather than double-enqueuing.
  """

  use Oban.Worker,
    queue: :default,
    max_attempts: 3,
    unique: [keys: [:command_id], period: :infinity]

  alias Playstead.AuditLog

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"device_id" => device_id, "command_id" => command_id}}) do
    {:ok, _} =
      AuditLog.record(nil, :credential_rotated, %{subject: device_id, command_id: command_id})

    :ok
  end
end
