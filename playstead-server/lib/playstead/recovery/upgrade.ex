defmodule Playstead.Recovery.Upgrade do
  @moduledoc """
  Evidence-only upgrade and rollback decision service.

  This module never runs Compose, migrations, or `Ecto.Migrator` rollback. A
  host command consumes a ready receipt to perform the controlled update; an
  incompatible or unhealthy rollback always names the existing isolated
  database-and-blob restore proof.
  """

  @schema "playstead.upgrade-preflight.v1"

  @spec preflight(map(), map() | nil) :: {:ok, map()} | {:error, map()}
  def preflight(context, prior_receipt \\ nil)

  def preflight(context, prior_receipt) when is_map(context) do
    receipt = receipt(context)

    case prior_receipt do
      nil -> validate_preflight(context, receipt)
      ^receipt -> {:ok, receipt}
      _ -> {:error, failed_receipt(context, "upgrade_preflight_replay_conflict")}
    end
  end

  def preflight(_, _), do: {:error, failed_receipt(%{}, "upgrade_preflight_invalid_context")}

  @doc "Selects exactly one safe rollback path; never selects a one-sided restore."
  @spec rollback_branch(map()) :: {:ok, map()}
  def rollback_branch(context) when is_map(context) do
    branch =
      if compatible?(context) and integrity_green?(context) do
        "app_only"
      else
        "clean_room_database_and_blobs"
      end

    {:ok,
     %{
       "schema" => @schema,
       "correlation_id" => Map.get(context, :correlation_id),
       "branch" => branch,
       "prior_release_digest" => Map.get(context, :prior_digest),
       "integrity" => normalize_integrity(Map.get(context, :integrity)),
       "compatibility" => if(compatible?(context), do: "certified", else: "not_certified"),
       "restore_proof" => if(branch == "app_only", do: nil, else: "playstead.restore"),
       "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
     }}
  end

  def rollback_branch(_), do: rollback_branch(%{})

  defp validate_preflight(context, ready) do
    cond do
      not digest?(Map.get(context, :prior_digest)) or
          not digest?(Map.get(context, :target_digest)) ->
        {:error, failed_receipt(context, "upgrade_preflight_invalid_release_digest")}

      not verified_backup?(Map.get(context, :backup)) ->
        {:error, failed_receipt(context, "upgrade_preflight_backup_unverified")}

      Map.get(context, :capacity, %{}) |> Map.get(:state) != :green ->
        {:error, failed_receipt(context, "upgrade_preflight_capacity_blocked")}

      not compatible?(context) ->
        {:error, failed_receipt(context, "upgrade_preflight_schema_incompatible")}

      true ->
        {:ok, ready}
    end
  end

  defp receipt(context) do
    backup = Map.get(context, :backup, %{})

    %{
      "schema" => @schema,
      "state" => "ready",
      "action" => "controlled_compose_update",
      "correlation_id" => Map.get(context, :correlation_id),
      "prior_release_digest" => Map.get(context, :prior_digest),
      "target_release_digest" => Map.get(context, :target_digest),
      "backup_receipt_id" => Map.get(backup, "receipt_id"),
      "backup_verified_at" => Map.get(backup, "verified_at"),
      "schema_compatibility" => "previous_release_certified",
      "capacity" => "green",
      "recorded_at" => Map.get(context, :recorded_at, "deterministic-preflight")
    }
  end

  defp failed_receipt(context, code) do
    %{
      "schema" => @schema,
      "state" => "blocked",
      "action" => "blocked",
      "code" => code,
      "correlation_id" => Map.get(context, :correlation_id),
      "rollback" => "clean_room_database_and_blobs",
      "restore_proof" => "playstead.restore"
    }
  end

  defp verified_backup?(%{
         "receipt_id" => id,
         "verified_at" => verified_at,
         "independence" => independence,
         "verification" => %{"state" => "verified"}
       })
       when is_binary(id) and is_binary(verified_at) and
              independence in ["detected", "operator_attested"],
       do: true

  defp verified_backup?(_), do: false

  defp compatible?(%{schema: %{state: :compatible, prior_can_read_target: true}}), do: true
  defp compatible?(_), do: false

  defp integrity_green?(%{integrity: %{database: :green, blobs: :green}}), do: true
  defp integrity_green?(_), do: false

  defp normalize_integrity(%{database: db, blobs: blobs}),
    do: %{"database" => Atom.to_string(db), "blobs" => Atom.to_string(blobs)}

  defp normalize_integrity(_), do: %{"database" => "unknown", "blobs" => "unknown"}

  defp digest?("sha256:" <> digest),
    do: byte_size(digest) == 64 and String.match?(digest, ~r/^[0-9a-f]+$/)

  defp digest?(_), do: false
end
