defmodule PlaysteadWeb.Api.V1.MetadataController do
  @moduledoc "Owner-scoped selected presentation metadata endpoints."

  use PlaysteadWeb, :controller

  alias Playstead.{Idempotency, Metadata}
  alias Playstead.Metadata.Consent, as: ProviderConsent

  action_fallback PlaysteadWeb.Api.V1.FallbackController

  def openapi(conn, _params), do: json(conn, PlaysteadWeb.Api.V1.MetadataOpenAPI.document())

  def reset_provider(
        conn,
        %{
          "asset_set_id" => asset_set_id,
          "field" => field,
          "base_revision" => base_revision,
          "evidence_id" => evidence_id
        }
      )
      when is_integer(base_revision) and base_revision >= 0 do
    device = conn.assigns.current_device

    effect = fn ->
      case Metadata.reset_from_provider(
             device.user_id,
             asset_set_id,
             field,
             base_revision,
             evidence_id,
             device.id
           ) do
        {:ok, selection} ->
          {:ok, 201, selection_json(selection)}

        {:error, {:metadata_conflict, conflict}} ->
          {:ok, 409,
           %{
             type: "metadata_conflict",
             field: conflict.field,
             base_revision: conflict.base_revision,
             current_revision: conflict.current_revision,
             current_alternative: conflict.current_alternative,
             incoming_alternative: conflict.incoming_alternative
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    run_provider_mutation(conn, device, effect)
  end

  def reset_provider(_conn, _params), do: {:error, :provider_evidence_stale}

  @doc "POST /api/v1/metadata/:asset_set_id selects the owner's plain-text description."
  def create(conn, %{"asset_set_id" => asset_set_id, "base_revision" => base_revision} = params)
      when is_integer(base_revision) and base_revision >= 0 do
    device = conn.assigns.current_device
    idempotency_key = conn.assigns.idempotency_key
    fingerprint = conn.assigns.idempotency_fingerprint
    field = Map.get(params, "field", "description")
    value = Map.get(params, "value", Map.get(params, "description"))

    effect = fn ->
      case Metadata.select_field(
             device.user_id,
             asset_set_id,
             field,
             value,
             base_revision,
             %{"source" => "user"},
             device.id
           ) do
        {:ok, selection} ->
          {:ok, 201, selection_json(selection)}

        {:error, {:metadata_conflict, conflict}} ->
          {:ok, 409,
           %{
             type: "metadata_conflict",
             field: conflict.field,
             base_revision: conflict.base_revision,
             current_revision: conflict.current_revision,
             current_alternative: conflict.current_alternative,
             incoming_alternative: conflict.incoming_alternative
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    run_idempotent(conn, device, idempotency_key, fingerprint, effect)
  end

  def create(_conn, _params) do
    {:error,
     Ecto.Changeset.add_error(
       Metadata.Selection.changeset(%Metadata.Selection{}, %{}),
       :base_revision,
       "is required and must identify the field revision you edited"
     )}
  end

  @doc "GET /api/v1/metadata/:asset_set_id reads the caller's selected description."
  def show(conn, %{"asset_set_id" => asset_set_id}) do
    device = conn.assigns.current_device

    with {:ok, selection} <- Metadata.get_description(device.user_id, asset_set_id) do
      json(conn, selection_json(selection))
    end
  end

  @doc "GET /api/v1/metadata/:asset_set_id/provider previews exact disclosure and readiness."
  def provider(conn, %{"asset_set_id" => asset_set_id}) do
    with {:ok, preview} <-
           ProviderConsent.preview(conn.assigns.current_device.user_id, asset_set_id) do
      json(conn, preview)
    else
      error -> provider_error(conn, error)
    end
  end

  @doc "POST /api/v1/metadata/:asset_set_id/provider/consent records exact title/system disclosure."
  def consent(conn, %{"asset_set_id" => asset_set_id} = params) do
    device = conn.assigns.current_device

    effect = fn ->
      case ProviderConsent.enable(device.user_id, asset_set_id, params) do
        {:ok, consent} ->
          {:ok, 200,
           %{
             provider: "igdb",
             enabled: consent.enabled,
             revision: consent.revision,
             disclosure_revision: consent.disclosure_revision
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    run_provider_mutation(conn, device, effect)
  end

  @doc "DELETE /api/v1/metadata/:asset_set_id/provider/consent revokes disclosure."
  def revoke(conn, %{"asset_set_id" => asset_set_id}) do
    device = conn.assigns.current_device

    effect = fn ->
      case ProviderConsent.disable(device.user_id, asset_set_id) do
        {:ok, consent} ->
          {:ok, 200, %{provider: "igdb", enabled: false, revision: consent.revision}}

        {:error, {:revoked_cache_cleanup_failed, consent}} ->
          {:ok, 200,
           %{
             provider: "igdb",
             enabled: false,
             revision: consent.revision,
             cache_cleanup: %{status: "failed", retryable: true}
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    run_provider_mutation(conn, device, effect)
  end

  @doc "POST /api/v1/metadata/:asset_set_id/provider/search performs one consent-gated bounded lookup."
  def provider_search(conn, %{"asset_set_id" => asset_set_id}) do
    device = conn.assigns.current_device

    effect = fn ->
      case ProviderConsent.search(device.user_id, asset_set_id) do
        {:ok, evidence} ->
          {:ok, 200, %{provider: "igdb", results: Enum.map(evidence, &evidence_json/1)}}

        {:error, reason} ->
          {:error, reason}
      end
    end

    run_provider_mutation(conn, device, effect)
  end

  defp run_provider_mutation(conn, device, effect) do
    case Idempotency.execute(
           device.id,
           conn.assigns.idempotency_key,
           conn.assigns.idempotency_fingerprint,
           effect
         ) do
      {:ok, status, body} ->
        conn |> put_status(status) |> json(body)

      {:error, :conflict} ->
        PlaysteadWeb.Problem.send_problem(
          conn,
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )

      {:error, reason} ->
        provider_error(conn, {:error, reason})
    end
  end

  defp evidence_json(row) do
    %{
      id: row.id,
      external_id: row.external_id,
      title: row.title,
      system: row.platform,
      confidence: row.confidence,
      match_kind: row.match_kind,
      provider: row.provider,
      provider_version: row.provider_version,
      attribution: row.attribution,
      terms_url: row.terms_url,
      policy_revision: row.policy_revision,
      cache_expires_at: row.cache_expires_at,
      license_expires_at: row.license_expires_at
    }
  end

  defp provider_error(conn, {:error, reason})
       when reason in [:consent_required, :consent_stale] do
    PlaysteadWeb.Problem.send_problem(
      conn,
      409,
      reason,
      "Current explicit title and system consent is required before provider lookup."
    )
  end

  defp provider_error(conn, {:error, :credentials_unavailable}),
    do:
      PlaysteadWeb.Problem.send_problem(
        conn,
        503,
        :provider_unavailable,
        "IGDB credentials are not configured by this server owner."
      )

  defp provider_error(conn, {:error, :disclosure_mismatch}),
    do:
      PlaysteadWeb.Problem.send_problem(
        conn,
        422,
        :validation_failed,
        "The disclosed title, system, or policy revision no longer matches this game."
      )

  defp provider_error(conn, {:error, :image_rights_unverified}),
    do:
      PlaysteadWeb.Problem.send_problem(
        conn,
        403,
        :image_rights_unverified,
        "Provider image rights have not been verified for this owner and use."
      )

  defp provider_error(conn, {:error, :provider_evidence_stale}),
    do:
      PlaysteadWeb.Problem.send_problem(
        conn,
        409,
        :provider_evidence_stale,
        "A current owner-scoped provider evidence record is required for this field reset."
      )

  defp provider_error(conn, {:error, :low_confidence_suggestion}),
    do:
      PlaysteadWeb.Problem.send_problem(
        conn,
        409,
        :low_confidence_suggestion,
        "A low-confidence provider candidate cannot be selected automatically."
      )

  defp provider_error(conn, error), do: PlaysteadWeb.Api.V1.FallbackController.call(conn, error)

  defp run_idempotent(conn, device, key, fingerprint, effect) do
    case Idempotency.execute(device.id, key, fingerprint, effect) do
      {:ok, status, body} ->
        conn |> put_status(status) |> json(body)

      {:error, :conflict} ->
        conn
        |> put_resp_header("retry-after", "1")
        |> PlaysteadWeb.Problem.send_problem(
          409,
          :idempotency_key_conflict,
          "A request with this Idempotency-Key is already being processed."
        )

      {:error, reason} ->
        PlaysteadWeb.Api.V1.FallbackController.call(conn, {:error, reason})
    end
  end

  defp selection_json(selection) do
    conflicts =
      case Metadata.conflicts(selection.user_id, selection.asset_set_id) do
        {:ok, conflicts} -> conflicts
        _ -> []
      end

    %{
      asset_set_id: selection.asset_set_id,
      description: selection.description,
      selections: selection.selections || %{"description" => selection.description},
      field_revisions: selection.field_revisions || %{},
      field_sources: selection.field_sources || %{},
      deleted_fields: selection.deleted_fields || %{},
      conflicts: Enum.map(conflicts, &conflict_json/1),
      evidence: selection.evidence || %{},
      revision: selection.revision,
      updated_at: selection.updated_at
    }
  end

  defp conflict_json(conflict) do
    %{
      id: conflict.id,
      field: conflict.field,
      base_revision: conflict.base_revision,
      current_revision: conflict.current_revision,
      current_alternative: conflict.current_alternative,
      incoming_alternative: conflict.incoming_alternative
    }
  end
end
