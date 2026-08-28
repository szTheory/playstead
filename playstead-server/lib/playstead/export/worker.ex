defmodule Playstead.Export.Worker do
  @moduledoc """
  The resumable export job (D-33, D-36, D-38), one job per export,
  unique on the export identifier — the same job model
  `Playstead.Import.SessionWorker` uses for imports, reused rather than
  reimplemented.

  `Playstead.Export.BagitWriter.write_bag/2` is itself resumable
  (re-hashes a file already at its destination and skips it on match),
  so re-running this job against a target that already has some files
  written — after a crash, or via a deliberate re-enqueue — only
  rewrites what is actually missing or mismatched, and never touches a
  file outside the plan.
  """

  use Oban.Worker,
    queue: :import,
    max_attempts: 5,
    unique: [keys: [:export_id], states: [:available, :scheduled, :executing]]

  alias Playstead.Export
  alias Playstead.Export.{BagitWriter, ExportRecord, Layout, Sidecar, Verifier}
  alias Playstead.Repo

  @doc "Enqueues the durable per-export job."
  @spec enqueue(binary()) :: {:ok, Oban.Job.t()} | {:error, term()}
  def enqueue(export_id) do
    %{export_id: export_id} |> new() |> Oban.insert()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"export_id" => export_id}}) do
    export = Repo.get!(ExportRecord, export_id)
    target_dir = Export.target_dir(export.target_name)
    layout = build_layout(export)

    case BagitWriter.write_bag(target_dir, layout) do
      {:ok, %{payload_entries: payload_entries}} ->
        export
        |> ExportRecord.counts_changeset(%{
          set_count: length(layout.sets),
          file_count: length(payload_entries),
          total_bytes: Enum.sum(Enum.map(payload_entries, &(&1.size_bytes || 0))),
          sidecar_schema_id: Sidecar.schema_id(),
          generator_version: generator_version()
        })
        |> Repo.update!()
        |> ExportRecord.verifying_changeset()
        |> Repo.update!()
        |> verify_and_finalize(target_dir)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp verify_and_finalize(export, target_dir) do
    case Verifier.verify(target_dir) do
      {:ok, _summary} ->
        export |> ExportRecord.verified_changeset() |> Repo.update!()

      {:error, {:mismatches, mismatches}} ->
        export |> ExportRecord.verification_failed_changeset(mismatches) |> Repo.update!()
    end
  end

  defp build_layout(%ExportRecord{
         scope: "set",
         scope_asset_set_id: asset_set_id,
         user_id: user_id
       }) do
    asset_set = Export.fetch_asset_set(user_id, asset_set_id)
    Layout.plan([Export.to_layout_input(asset_set)], include_excluded: true)
  end

  defp build_layout(%ExportRecord{scope: "library", user_id: user_id}) do
    asset_sets = Export.fetch_all_asset_sets(user_id)
    Layout.plan(Enum.map(asset_sets, &Export.to_layout_input/1))
  end

  @doc """
  Re-verifies `export_id` (owned by `user_id`) at any time, without
  rewriting anything — the target's files are re-read and re-hashed
  exactly as `Playstead.Export.Verifier.verify/1` always does.
  """
  @spec verify_again(pos_integer(), binary()) :: {:ok, ExportRecord.t()} | {:error, :not_found}
  def verify_again(user_id, export_id) do
    case Repo.get_by(ExportRecord, id: export_id, user_id: user_id) do
      nil ->
        {:error, :not_found}

      export ->
        target_dir = Export.target_dir(export.target_name)
        {:ok, verify_and_finalize(export, target_dir)}
    end
  end

  defp generator_version do
    case Application.spec(:playstead, :vsn) do
      nil -> "dev"
      vsn -> to_string(vsn)
    end
  end
end
