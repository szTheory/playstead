defmodule Playstead.OperationsTest do
  use Playstead.DataCase, async: false

  alias Playstead.Operations
  alias Playstead.Repo

  @healthy %{state: :healthy, code: nil, remedy: nil}

  test "returns the six component rows in their fixed order" do
    snapshot = Operations.snapshot(probes: Map.new(Operations.component_ids(), &{&1, @healthy}))

    assert Enum.map(snapshot, & &1.id) == Operations.component_ids()
    assert Enum.all?(snapshot, &(&1.state == :healthy))
    assert Enum.all?(snapshot, &is_struct(&1.evidence_at, DateTime))
  end

  test "non-healthy rows have stable codes, evidence, and remedies" do
    probes = Map.new(Operations.component_ids(), &{&1, @healthy})

    snapshot =
      Operations.snapshot(
        probes:
          Map.put(probes, :backup, %{
            state: :attention,
            code: "backup_missing",
            remedy: "Run a verified backup."
          })
      )

    assert %{
             state: :attention,
             code: "backup_missing",
             remedy: "Run a verified backup.",
             evidence_at: %DateTime{}
           } =
             Enum.find(snapshot, &(&1.id == :backup))
  end

  test "repeated healthy reads do not create attention history" do
    probes = Map.new(Operations.component_ids(), &{&1, @healthy})

    assert Enum.all?(Operations.snapshot(probes: probes), &(&1.state == :healthy))
    assert Enum.all?(Operations.snapshot(probes: probes), &(&1.state == :healthy))

    assert 0 == Operations.attention_history_count()
  end

  test "concurrent actionable refreshes create one transition receipt" do
    probes =
      Map.new(Operations.component_ids(), &{&1, @healthy})
      |> Map.put(:database, %{
        state: :blocked,
        code: "database_unavailable",
        remedy: "Check PostgreSQL and retry."
      })

    parent = self()

    tasks =
      for _ <- 1..4 do
        Task.async(fn ->
          Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
          Operations.snapshot(probes: probes)
        end)
      end

    Enum.each(tasks, &Task.await(&1, 5_000))

    assert 1 == Operations.attention_history_count()
  end

  test "each actionable component condition has a stable code and concrete remedy" do
    probes =
      Map.new(Operations.component_ids(), &{&1, @healthy})
      |> Map.merge(%{
        blobs: %{state: :blocked, code: "blob_store_unavailable", remedy: "Check storage."},
        queue: %{state: :attention, code: "queue_paused", remedy: "Resume queue."},
        migrations: %{state: :attention, code: "migrations_pending", remedy: "Migrate."},
        capacity: %{state: :attention, code: "capacity_reserve_low", remedy: "Free space."},
        backup: %{state: :blocked, code: "backup_failed", remedy: "Recover."}
      })

    assert Enum.all?(Operations.snapshot(probes: probes), fn row ->
             row.state == :healthy or (is_binary(row.code) and is_binary(row.remedy))
           end)
  end

  test "a probe timeout is bounded and becomes actionable evidence" do
    snapshot =
      Operations.snapshot(
        probe_fun: fn
          :database ->
            Process.sleep(1_100)
            @healthy

          _ ->
            @healthy
        end
      )

    assert %{state: :attention, code: "probe_timeout", remedy: remedy} =
             Enum.find(snapshot, &(&1.id == :database))

    assert is_binary(remedy)
  end
end
