defmodule Mix.Tasks.Playstead.UpgradePreflight do
  @shortdoc "Checks evidence required before a controlled Compose upgrade"
  @moduledoc "Runs only the non-destructive Phase 05 upgrade preflight fixture."
  use Mix.Task

  alias Playstead.Recovery.Upgrade

  @impl Mix.Task
  def run(["--fixture"]) do
    Mix.Task.run("app.start")

    context = %{
      prior_digest: "sha256:" <> String.duplicate("a", 64),
      target_digest: "sha256:" <> String.duplicate("b", 64),
      backup: %{
        "receipt_id" => "fixture-backup",
        "verified_at" => "2026-09-20T00:00:00Z",
        "independence" => "operator_attested",
        "verification" => %{"state" => "verified"}
      },
      capacity: %{state: :green},
      schema: %{state: :compatible, prior_can_read_target: true},
      integrity: %{database: :green, blobs: :green},
      correlation_id: "fixture-upgrade"
    }

    case Upgrade.preflight(context) do
      {:ok, receipt} -> Mix.shell().info("upgrade preflight ready: #{receipt["correlation_id"]}")
      {:error, receipt} -> Mix.raise("upgrade preflight blocked: #{receipt["code"]}")
    end
  end

  def run(_), do: Mix.raise("usage: mix playstead.upgrade_preflight --fixture")
end
