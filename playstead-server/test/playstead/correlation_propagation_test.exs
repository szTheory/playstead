defmodule Playstead.CorrelationPropagationTest do
  use Playstead.DataCase, async: false

  import Ecto.Query

  alias Playstead.{Operations, Recovery, Repo}
  alias Playstead.Operations.DiagnosticBundle
  alias Playstead.Recovery.Worker

  @forbidden ~w(secret-rom-name.sfc /private/roms deadbeef credential token password header request)

  test "recovery carries the boundary correlation through its Oban job and safe storage evidence" do
    Ecto.Adapters.SQL.Sandbox.unboxed_run(Repo, fn ->
      correlation_id = Ecto.UUID.generate()

      destination =
        Path.join(
          System.tmp_dir!(),
          "playstead-correlation-#{System.unique_integer([:positive])}"
        )

      try do
        assert {:ok, recovery_id} =
                 Recovery.request_backup(%{
                   destination: destination,
                   kind: :full,
                   correlation_id: correlation_id
                 })

        job =
          Repo.one!(
            from j in Oban.Job,
              where: fragment("?->>'recovery_id'", j.args) == ^recovery_id
          )

        assert job.args["correlation_id"] == correlation_id

        assert :ok = Worker.perform(job)
        assert {:ok, summary} = DiagnosticBundle.for_correlation(correlation_id)
        assert summary.correlation_id == correlation_id
        assert summary.subsystem == "recovery"
        assert summary.state == "published"
        encoded = Jason.encode!(summary)
        refute Enum.any?(@forbidden, &String.contains?(encoded, &1))
      after
        {:ok, dumped_correlation_id} = Ecto.UUID.dump(correlation_id)

        Repo.query!(
          "DELETE FROM oban_jobs WHERE args->>'correlation_id' = $1",
          [correlation_id]
        )

        Repo.query!(
          "DELETE FROM operations_failure_evidence WHERE correlation_id = $1",
          [dumped_correlation_id]
        )

        Repo.query!(
          "DELETE FROM recovery_records WHERE correlation_id = $1",
          [dumped_correlation_id]
        )

        File.rm_rf!(destination)
      end
    end)
  end

  test "allowlisted operation evidence retains only correlation, subsystem, code, state, and time" do
    correlation_id = Ecto.UUID.generate()
    assert :ok = Operations.record_failure(correlation_id, "pairing", "pairing_not_approved")
    assert {:ok, summary} = DiagnosticBundle.for_correlation(correlation_id)

    assert %{
             correlation_id: ^correlation_id,
             subsystem: "pairing",
             code: "pairing_not_approved",
             state: "failed"
           } = summary

    refute Enum.any?(@forbidden, &String.contains?(Jason.encode!(summary), &1))
  end
end
