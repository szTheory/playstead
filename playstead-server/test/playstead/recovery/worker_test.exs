defmodule Playstead.Recovery.WorkerTest do
  use Playstead.DataCase, async: false

  alias Playstead.{Recovery.Worker, Repo}

  test "configures a bounded recovery queue" do
    assert 1 = Application.fetch_env!(:playstead, Oban)[:queues][:recovery]
  end

  test "the forward migration provides the durable command column" do
    assert {:ok, %{rows: [["command"]]}} =
             Ecto.Adapters.SQL.query(
               Repo,
               "SELECT column_name FROM information_schema.columns WHERE table_name = 'recovery_records' AND column_name = 'command'"
             )
  end

  test "uses one durable job identity for competing recovery enqueues" do
    recovery_id = Ecto.UUID.generate()
    assert {:ok, first} = Worker.enqueue(recovery_id)
    assert {:ok, second} = Worker.enqueue(recovery_id)
    assert first.id == second.id
  end
end
