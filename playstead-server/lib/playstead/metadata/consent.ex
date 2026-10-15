defmodule Playstead.Metadata.ProviderConsent do
  @moduledoc "Persisted exact title/system disclosure grant for an optional metadata provider."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "metadata_provider_consents" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :provider, :string, default: "igdb"
    field :enabled, :boolean, default: false
    field :revision, :integer, default: 1
    field :disclosure_revision, :string
    field :disclosed_title, :string
    field :disclosed_system, :string
    field :image_terms_revision, :string
    field :image_grant_scope, :string
    timestamps(type: :utc_datetime)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [
      :user_id,
      :asset_set_id,
      :provider,
      :enabled,
      :revision,
      :disclosure_revision,
      :disclosed_title,
      :disclosed_system,
      :image_terms_revision,
      :image_grant_scope
    ])
    |> validate_required([:user_id, :asset_set_id, :provider, :enabled, :revision])
    |> validate_number(:revision, greater_than: 0)
    |> foreign_key_constraint(:asset_set_id)
    |> unique_constraint([:user_id, :asset_set_id, :provider],
      name: :metadata_provider_consents_owner_asset_provider_index
    )
  end
end

defmodule Playstead.Metadata.ProviderEvidence do
  @moduledoc "Bounded third-party text evidence; never a ROM or content identity."
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "metadata_provider_evidence" do
    field :user_id, :id
    belongs_to :asset_set, Playstead.Catalogue.AssetSet
    field :provider, :string
    field :provider_version, :string
    field :external_id, :integer
    field :title, :string
    field :provider_description, :string
    field :platform_id, :integer
    field :platform, :string
    field :confidence, :string
    field :match_kind, :string, default: "suggestion"
    field :attribution, :string
    field :terms_url, :string
    field :policy_revision, :string
    field :media_references, :map, default: %{}
    field :cache_expires_at, :utc_datetime
    field :license_expires_at, :utc_datetime
    timestamps(type: :utc_datetime)
  end

  def changeset(evidence, attrs) do
    evidence
    |> cast(attrs, [
      :user_id,
      :asset_set_id,
      :provider,
      :provider_version,
      :external_id,
      :title,
      :provider_description,
      :platform_id,
      :platform,
      :confidence,
      :match_kind,
      :attribution,
      :terms_url,
      :policy_revision,
      :media_references,
      :cache_expires_at,
      :license_expires_at
    ])
    |> validate_required([
      :user_id,
      :asset_set_id,
      :provider,
      :provider_version,
      :external_id,
      :title,
      :platform_id,
      :platform,
      :confidence,
      :match_kind,
      :attribution,
      :terms_url,
      :policy_revision,
      :cache_expires_at
    ])
    |> validate_inclusion(:confidence, ["high", "low"])
    |> validate_inclusion(:match_kind, ["suggestion"])
    |> foreign_key_constraint(:asset_set_id)
  end
end

defmodule Playstead.Metadata.Consent do
  @moduledoc "Owner-scoped disclosure preview, revocation and provider request gate."
  import Ecto.Query, warn: false

  alias Playstead.{Catalogue.AssetSet, Metadata.ProviderConsent, Metadata.ProviderEvidence, Repo}
  alias Playstead.Metadata.{ProviderPolicy, Providers.IGDB}

  @disclosure_revision "igdb-title-system-v1"

  def disclosure_revision, do: @disclosure_revision

  def preview(user_id, asset_set_id) do
    with {:ok, asset} <- owned_asset(user_id, asset_set_id) do
      consent = get_consent(user_id, asset.id)

      {:ok,
       %{
         provider: "igdb",
         enabled: (consent && consent.enabled) || false,
         revision: (consent && consent.revision) || 0,
         disclosure_revision: @disclosure_revision,
         query_preview: asset.display_title,
         system: asset.system_id,
         title_warning:
           if(asset.title_source == "filename", do: "filename_derived_title", else: nil),
         credentials_ready: provider_credentials_ready?(),
         attribution: ProviderPolicy.attribution(),
         terms_url: ProviderPolicy.terms_url(),
         image_fetch_allowed: (consent && ProviderPolicy.image_fetch_allowed?(consent)) || false,
         cache_age_days: 30,
         license_expires_at: nil
       }}
    end
  end

  def enable(user_id, asset_set_id, disclosure) when is_map(disclosure) do
    with {:ok, asset_id} <- Ecto.UUID.cast(asset_set_id) do
      with_owner_asset_lock(user_id, asset_id, fn asset ->
        if is_binary(asset.display_title) and asset.display_title != "" and
             is_binary(asset.system_id) and asset.system_id != "" and
             disclosure["title"] == asset.display_title and
             disclosure["system"] == asset.system_id and
             disclosure["disclosure_revision"] == @disclosure_revision do
          persist_consent(user_id, asset, true)
        else
          {:error, :disclosure_mismatch}
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  def enable(_, _, _), do: {:error, :disclosure_mismatch}

  def disable(user_id, asset_set_id) do
    with {:ok, asset_id} <- Ecto.UUID.cast(asset_set_id) do
      result =
        with_owner_asset_lock(user_id, asset_id, fn asset ->
          with {:ok, consent} <- persist_consent(user_id, asset, false) do
            case Playstead.Metadata.ProviderMediaCache.purge(user_id, asset.id) do
              :ok -> {:ok, consent}
              {:error, _cleanup_error} -> {:error, {:revoked_cache_cleanup_failed, consent}}
            end
          end
        end)

      case result do
        {:ok, consent} ->
          Playstead.Metadata.EnrichmentWorker.cancel_for_asset(user_id, asset_id)
          {:ok, consent}

        {:error, {:revoked_cache_cleanup_failed, consent}} ->
          Playstead.Metadata.EnrichmentWorker.cancel_for_asset(user_id, asset_id)
          {:error, {:revoked_cache_cleanup_failed, consent}}

        error ->
          error
      end
    else
      :error -> {:error, :not_found}
    end
  end

  def authorize(user_id, asset_set_id) do
    with {:ok, asset} <- owned_asset(user_id, asset_set_id),
         %ProviderConsent{enabled: true, disclosure_revision: @disclosure_revision} = consent <-
           get_consent(user_id, asset.id),
         true <-
           consent.disclosed_title == asset.display_title and
             consent.disclosed_system == asset.system_id do
      {:ok,
       %{
         consent: consent,
         title: consent.disclosed_title,
         system: consent.disclosed_system,
         asset_set_id: asset.id
       }}
    else
      nil -> {:error, :consent_required}
      false -> {:error, :consent_stale}
      {:error, _} = error -> error
      _ -> {:error, :consent_required}
    end
  end

  def authorize_image(user_id, asset_set_id) do
    with {:ok, %{consent: consent}} <- authorize(user_id, asset_set_id),
         true <- ProviderPolicy.image_fetch_allowed?(consent) do
      {:ok, consent}
    else
      false -> {:error, :image_rights_unverified}
      error -> error
    end
  end

  def search(user_id, asset_set_id, opts \\ []) do
    opts = test_provider_options(opts)

    with {:ok, authorization} <- authorize(user_id, asset_set_id),
         {:ok, candidates} <- IGDB.search(authorization.title, authorization.system, opts),
         {:ok, evidence} <-
           persist_provider_evidence(
             user_id,
             authorization.asset_set_id,
             authorization.consent.revision,
             candidates
           ) do
      {:ok, evidence}
    end
  end

  defp provider_credentials_ready? do
    Application.get_env(:playstead, :metadata_provider_test_stub, false) or
      IGDB.credentials_ready?()
  end

  defp test_provider_options(opts) do
    if Application.get_env(:playstead, :metadata_provider_test_stub, false) do
      opts
      |> Keyword.drop([:client_id, :access_token, :transport])
      |> Keyword.merge(
        client_id: "playstead-local-test",
        access_token: "playstead-local-test",
        transport: Playstead.Metadata.Providers.LocalTestStub,
        test_pid: Application.get_env(:playstead, :metadata_provider_test_pid)
      )
    else
      opts
    end
  end

  defp persist_consent(user_id, asset, enabled) do
    existing = get_consent(user_id, asset.id)

    attrs = %{
      user_id: user_id,
      asset_set_id: asset.id,
      provider: "igdb",
      enabled: enabled,
      revision: if(existing, do: existing.revision + 1, else: 1),
      disclosure_revision: @disclosure_revision,
      disclosed_title:
        if(enabled, do: asset.display_title, else: existing && existing.disclosed_title),
      disclosed_system:
        if(enabled, do: asset.system_id, else: existing && existing.disclosed_system)
    }

    Repo.insert_or_update(ProviderConsent.changeset(existing || %ProviderConsent{}, attrs))
  end

  defp with_owner_asset_lock(user_id, asset_set_id, fun) do
    case Repo.transaction(fn ->
           # Share the owner serialization point with provider image publication.
           Repo.query!("SELECT id FROM users WHERE id = $1 FOR UPDATE", [user_id])

           asset =
             Repo.one(
               from a in AssetSet,
                 where: a.id == ^asset_set_id and a.user_id == ^user_id,
                 lock: "FOR UPDATE"
             )

           if is_nil(asset), do: Repo.rollback(:not_found)
           fun.(asset)
         end) do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  def persist_provider_evidence(user_id, asset_set_id, consent_revision, candidates) do
    Repo.transaction(fn ->
      consent =
        Repo.one(
          from c in ProviderConsent,
            where:
              c.user_id == ^user_id and c.asset_set_id == ^asset_set_id and c.provider == "igdb",
            lock: "FOR UPDATE"
        )

      asset = Repo.one(from a in AssetSet, where: a.id == ^asset_set_id and a.user_id == ^user_id)

      unless match?(%ProviderConsent{enabled: true}, consent) and match?(%AssetSet{}, asset) and
               consent.revision == consent_revision and
               consent.disclosure_revision == @disclosure_revision and
               consent.disclosed_title == asset.display_title and
               consent.disclosed_system == asset.system_id do
        Repo.rollback(:consent_stale)
      end

      evidence =
        Enum.map(candidates, fn candidate ->
          attrs =
            Map.merge(candidate, %{
              user_id: user_id,
              asset_set_id: asset_set_id,
              confidence: to_string(candidate.confidence),
              match_kind: "suggestion"
            })

          case Repo.insert(ProviderEvidence.changeset(%ProviderEvidence{}, attrs)) do
            {:ok, evidence} -> evidence
            {:error, changeset} -> Repo.rollback(changeset)
          end
        end)

      case Playstead.Metadata.refresh_provider_evidence(user_id, asset_set_id, evidence) do
        :ok -> evidence
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, evidence} -> {:ok, evidence}
      {:error, reason} -> {:error, reason}
    end
  end

  defp get_consent(user_id, asset_set_id),
    do:
      Repo.one(
        from c in ProviderConsent,
          where:
            c.user_id == ^user_id and c.asset_set_id == ^asset_set_id and c.provider == "igdb"
      )

  defp owned_asset(user_id, asset_set_id) do
    with {:ok, uuid} <- Ecto.UUID.cast(asset_set_id),
         %AssetSet{} = asset <-
           Repo.one(from a in AssetSet, where: a.user_id == ^user_id and a.id == ^uuid) do
      {:ok, asset}
    else
      _ -> {:error, :not_found}
    end
  end
end
