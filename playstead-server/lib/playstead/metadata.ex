defmodule Playstead.Metadata do
  @moduledoc "Owner-scoped private presentation metadata."

  import Ecto.Query, warn: false

  alias Playstead.Catalogue.AssetSet
  alias Playstead.Metadata.{Conflict, Selection}
  alias Playstead.Metadata.ProviderEvidence
  alias Playstead.Pairing.Device
  alias Playstead.Repo
  alias Playstead.Sync.{ChangeJournal, MetadataPayload}

  @doc "Creates or replaces an owner's selected plain-text description and journals it atomically."
  @spec select_description(pos_integer(), String.t(), String.t()) ::
          {:ok, Selection.t()} | {:error, term()}
  def select_description(user_id, asset_set_id, description)
      when is_integer(user_id) and is_binary(asset_set_id) and is_binary(description) do
    current = get_field_revision(user_id, asset_set_id, "description")
    select_description(user_id, asset_set_id, description, current)
  end

  def select_description(_user_id, _asset_set_id, _description), do: {:error, :not_found}

  def select_description(user_id, asset_set_id, description, base_revision)
      when is_binary(description) and is_integer(base_revision) and base_revision >= 0 do
    select_field(user_id, asset_set_id, "description", description, base_revision, %{
      "source" => "user"
    })
  end

  def select_description(_, _, _, _), do: {:error, :invalid_revision}

  @fields ~w(title description candidate cover screenshots)

  @doc "Selects one presentation field with per-field optimistic concurrency and durable conflict alternatives."
  def select_field(
        user_id,
        asset_set_id,
        field,
        value,
        base_revision,
        source_metadata \\ %{"source" => "user"}
      )

  def select_field(user_id, asset_set_id, field, value, base_revision, source_metadata) do
    select_field(user_id, asset_set_id, field, value, base_revision, source_metadata, nil)
  end

  def select_field(
        user_id,
        asset_set_id,
        field,
        value,
        base_revision,
        source_metadata,
        actor_device_id
      )
      when is_integer(user_id) and is_binary(asset_set_id) and is_binary(field) and
             is_integer(base_revision) and base_revision >= 0 and is_map(source_metadata) and
             (is_nil(actor_device_id) or is_binary(actor_device_id)) do
    with true <- field in @fields,
         true <- field != "description" or (is_binary(value) and value != ""),
         {:ok, asset_set_id} <- Ecto.UUID.cast(asset_set_id),
         {:ok, actor_device_id} <- cast_actor_device_id(actor_device_id),
         :ok <- validate_field_value(field, value) do
      Repo.transaction(fn ->
        validate_actor_device!(user_id, actor_device_id)

        asset =
          Repo.one(
            from a in AssetSet,
              where: a.user_id == ^user_id and a.id == ^asset_set_id,
              lock: "FOR UPDATE"
          )

        if is_nil(asset), do: Repo.rollback(:not_found)

        current =
          Repo.one(
            from s in Selection,
              where: s.user_id == ^user_id and s.asset_set_id == ^asset_set_id,
              lock: "FOR UPDATE"
          )

        current_revision = get_in(current && current.field_revisions, [field]) || 0
        current_value = selected_value(current, field)

        if base_revision != current_revision and value != current_value do
          conflict =
            persist_conflict!(
              user_id,
              asset_set_id,
              field,
              base_revision,
              current_revision,
              current_value,
              value,
              source_metadata
            )

          saved = ensure_selection!(user_id, asset_set_id, current)
          append_selection!(user_id, asset_set_id, saved)
          {:conflict, conflict}
        else
          next_revision = ((current && current.revision) || 0) + 1
          next_field_revision = current_revision + 1

          fields =
            if is_nil(value),
              do:
                Map.delete((current && current.selections) || legacy_selections(current), field),
              else:
                Map.put(
                  (current && current.selections) || legacy_selections(current),
                  field,
                  value
                )

          field_revisions =
            Map.put((current && current.field_revisions) || %{}, field, next_field_revision)

          sources = Map.put((current && current.field_sources) || %{}, field, source_metadata)
          deleted_fields = (current && current.deleted_fields) || %{}

          deleted_fields =
            if is_nil(value),
              do: Map.put(deleted_fields, field, next_field_revision),
              else: Map.delete(deleted_fields, field)

          description =
            if field == "description", do: value, else: (current && current.description) || ""

          attrs = %{
            user_id: user_id,
            asset_set_id: asset_set_id,
            description: description,
            revision: next_revision,
            selections: fields,
            field_revisions: field_revisions,
            field_sources: sources,
            deleted_fields: deleted_fields,
            deleted_at: nil
          }

          case Repo.insert_or_update(Selection.changeset(current || %Selection{}, attrs)) do
            {:ok, saved} ->
              resolve_conflicts!(user_id, asset_set_id, field, actor_device_id)
              append_selection!(user_id, asset_set_id, saved)
              saved

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end
      end)
      |> case do
        {:ok, {:conflict, conflict}} -> {:error, {:metadata_conflict, conflict}}
        {:ok, selection} -> {:ok, selection}
        {:error, reason} -> {:error, reason}
      end
    else
      false -> {:error, :invalid_metadata_field}
      :error -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def select_field(_, _, _, _, _, _, _), do: {:error, :invalid_metadata_selection}

  @doc "Lists unresolved owner conflicts for one game presentation field."
  def conflicts(user_id, asset_set_id) do
    with {:ok, id} <- Ecto.UUID.cast(asset_set_id),
         true <- Repo.exists?(from a in AssetSet, where: a.id == ^id and a.user_id == ^user_id) do
      {:ok,
       Repo.all(
         from c in Conflict,
           where: c.user_id == ^user_id and c.asset_set_id == ^id and is_nil(c.resolved_at),
           order_by: [asc: c.inserted_at]
       )}
    else
      _ -> {:error, :not_found}
    end
  end

  defp get_field_revision(user_id, asset_set_id, field) do
    case get_description(user_id, asset_set_id) do
      {:ok, selection} -> get_in(selection.field_revisions, [field]) || 0
      _ -> 0
    end
  end

  defp selected_value(nil, _field), do: nil

  defp selected_value(
         %Selection{selections: selections, description: description},
         "description"
       ),
       do: Map.get(selections || %{}, "description", description)

  defp selected_value(%Selection{selections: selections}, field),
    do: get_in(selections || %{}, [field])

  defp legacy_selections(nil), do: %{}

  defp legacy_selections(%Selection{description: description}),
    do: %{"description" => description}

  defp validate_json_value(value) do
    case Jason.encode(value) do
      {:ok, encoded} when byte_size(encoded) <= 65_536 ->
        if safe_metadata_value?(value), do: :ok, else: {:error, :invalid_metadata_value}

      _ ->
        {:error, :invalid_metadata_value}
    end
  end

  defp safe_metadata_value?(value) when is_map(value) do
    Enum.all?(value, fn {key, child} ->
      normalized = key |> to_string() |> String.downcase()

      normalized not in [
        "path",
        "cache_path",
        "authorization",
        "token",
        "access_token",
        "client_secret",
        "credentials"
      ] and
        safe_metadata_value?(child)
    end)
  end

  defp safe_metadata_value?(value) when is_list(value),
    do: Enum.all?(value, &safe_metadata_value?/1)

  defp safe_metadata_value?(_value), do: true

  defp validate_field_value(_field, nil), do: :ok

  defp validate_field_value(field, value) when field in ["title", "description"] do
    if is_binary(value) and String.valid?(value) and byte_size(value) <= 65_536 and
         (field != "description" or value != "") do
      :ok
    else
      {:error, :invalid_metadata_value}
    end
  end

  defp validate_field_value("candidate", value) when is_map(value), do: validate_json_value(value)
  defp validate_field_value("cover", value) when is_map(value), do: validate_json_value(value)

  defp validate_field_value("screenshots", value) when is_list(value) and length(value) <= 20,
    do: validate_json_value(value)

  defp validate_field_value(_field, _value), do: {:error, :invalid_metadata_value}

  @doc "Selects one current, owner-scoped provider value after a field-specific reset request."
  def reset_from_provider(user_id, asset_set_id, field, base_revision, evidence_id) do
    reset_from_provider(user_id, asset_set_id, field, base_revision, evidence_id, nil)
  end

  def reset_from_provider(
        user_id,
        asset_set_id,
        field,
        base_revision,
        evidence_id,
        actor_device_id
      )
      when field in @fields and is_integer(base_revision) and base_revision >= 0 and
             is_binary(evidence_id) and (is_nil(actor_device_id) or is_binary(actor_device_id)) do
    with {:ok, asset_id} <- Ecto.UUID.cast(asset_set_id),
         {:ok, evidence_uuid} <- Ecto.UUID.cast(evidence_id),
         {:ok, evidence} <- current_evidence(user_id, asset_id, evidence_uuid),
         {:ok, value} <- evidence_value(field, evidence),
         :ok <- provider_field_allowed(user_id, asset_id, field, evidence) do
      select_field(
        user_id,
        asset_id,
        field,
        value,
        base_revision,
        %{
          "source" => "provider",
          "provider" => evidence.provider,
          "evidence_id" => evidence.id,
          "attribution" => evidence.attribution,
          "terms_url" => evidence.terms_url,
          "policy_revision" => evidence.policy_revision
        },
        actor_device_id
      )
    else
      {:error, reason} -> {:error, reason}
      _ -> {:error, :provider_evidence_stale}
    end
  end

  def reset_from_provider(_, _, _, _, _, _), do: {:error, :provider_evidence_stale}

  defp validate_actor_device!(_user_id, nil), do: :ok

  defp validate_actor_device!(user_id, actor_device_id) do
    if Repo.exists?(from d in Device, where: d.id == ^actor_device_id and d.user_id == ^user_id) do
      :ok
    else
      Repo.rollback(:invalid_actor_device)
    end
  end

  defp cast_actor_device_id(nil), do: {:ok, nil}
  defp cast_actor_device_id(id), do: Ecto.UUID.cast(id)

  defp current_evidence(user_id, asset_id, evidence_id) do
    latest =
      Repo.one(
        from e in ProviderEvidence,
          where: e.user_id == ^user_id and e.asset_set_id == ^asset_id,
          order_by: [desc: e.inserted_at],
          limit: 1
      )

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    if latest && latest.id == evidence_id && DateTime.compare(latest.cache_expires_at, now) == :gt do
      {:ok, latest}
    else
      {:error, :provider_evidence_stale}
    end
  end

  defp evidence_value("title", evidence), do: {:ok, evidence.title}

  defp evidence_value("description", %ProviderEvidence{provider_description: value})
       when is_binary(value) and value != "",
       do: {:ok, value}

  defp evidence_value("candidate", evidence) do
    {:ok,
     %{
       "provider" => evidence.provider,
       "external_id" => evidence.external_id,
       "title" => evidence.title,
       "platform" => evidence.platform,
       "confidence" => evidence.confidence,
       "match_kind" => evidence.match_kind
     }}
  end

  defp evidence_value(field, evidence) when field in ["cover", "screenshots"] do
    case Map.get(evidence.media_references || %{}, field) do
      nil -> {:error, :provider_evidence_stale}
      value -> {:ok, value}
    end
  end

  defp provider_field_allowed(_user_id, _asset_id, "candidate", %ProviderEvidence{
         confidence: "low"
       }),
       do: {:error, :low_confidence_suggestion}

  defp provider_field_allowed(user_id, asset_id, field, evidence)
       when field in ["cover", "screenshots"] do
    with {:ok, consent} <- Playstead.Metadata.Consent.authorize_image(user_id, asset_id),
         true <- consent.image_terms_revision == evidence.policy_revision do
      :ok
    else
      _ -> {:error, :image_rights_unverified}
    end
  end

  defp provider_field_allowed(_user_id, _asset_id, _field, _evidence), do: :ok

  defp persist_conflict!(
         user_id,
         asset_set_id,
         field,
         base_revision,
         current_revision,
         current_value,
         incoming_value,
         source
       ) do
    attrs = %{
      user_id: user_id,
      asset_set_id: asset_set_id,
      field: field,
      base_revision: base_revision,
      current_revision: max(current_revision, 1),
      current_alternative: %{value: current_value, revision: current_revision},
      incoming_alternative: %{value: incoming_value, source: source}
    }

    case Repo.insert(Conflict.changeset(%Conflict{}, attrs)) do
      {:ok, conflict} -> conflict
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  defp ensure_selection!(user_id, asset_set_id, nil) do
    {:ok, selection} =
      Repo.insert(
        Selection.changeset(%Selection{}, %{
          user_id: user_id,
          asset_set_id: asset_set_id,
          description: "",
          revision: 1,
          selections: %{},
          field_revisions: %{},
          field_sources: %{}
        })
      )

    selection
  end

  defp ensure_selection!(_user_id, _asset_set_id, %Selection{} = selection), do: selection

  defp resolve_conflicts!(user_id, asset_set_id, field, actor_device_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    query =
      from(c in Conflict,
        where:
          c.user_id == ^user_id and c.asset_set_id == ^asset_set_id and c.field == ^field and
            is_nil(c.resolved_at)
      )

    if is_nil(actor_device_id) and Repo.exists?(query) do
      Repo.rollback(:resolution_actor_required)
    end

    Repo.update_all(query,
      set: [resolved_at: now, resolved_by_device_id: actor_device_id, updated_at: now]
    )

    :ok
  end

  defp append_selection!(user_id, asset_set_id, selection) do
    conflicts =
      Repo.all(
        from c in Conflict,
          where:
            c.user_id == ^user_id and c.asset_set_id == ^asset_set_id and
              is_nil(c.resolved_at)
      )

    evidence = evidence_payload(selection, conflicts)

    case ChangeJournal.append(
           user_id,
           :metadata,
           asset_set_id,
           MetadataPayload.build(selection, conflicts, evidence)
         ) do
      {:ok, _entry} -> :ok
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "Builds sanitized provider evidence referenced by selected fields for API and sync payloads."
  def evidence_payload(%Selection{} = selection, conflicts \\ []) do
    _ = conflicts
    selection.evidence || %{}
  end

  @doc "Stores bounded sanitized provider evidence separately from owner selections and journals the new snapshot state."
  def refresh_provider_evidence(user_id, asset_set_id, evidence_rows)
      when is_integer(user_id) and is_binary(asset_set_id) and is_list(evidence_rows) do
    with {:ok, asset_id} <- Ecto.UUID.cast(asset_set_id) do
      Repo.transaction(fn ->
        asset =
          Repo.one(
            from a in AssetSet,
              where: a.user_id == ^user_id and a.id == ^asset_id,
              lock: "FOR UPDATE"
          )

        if is_nil(asset), do: Repo.rollback(:not_found)

        selection =
          Repo.one(
            from s in Selection,
              where: s.user_id == ^user_id and s.asset_set_id == ^asset_id,
              lock: "FOR UPDATE"
          )

        if evidence_rows == [] do
          :ok
        else
          selection = selection || insert_empty_selection!(user_id, asset_id)
          selected_ids = evidence_reference_ids(selection)
          referenced = Map.take(selection.evidence || %{}, selected_ids)

          latest =
            Map.new(evidence_rows, fn row ->
              {row.id, sanitized_evidence(row)}
            end)

          attrs = %{evidence: Map.merge(referenced, latest)}

          case Repo.update(Selection.changeset(selection, attrs)) do
            {:ok, updated} ->
              append_selection!(user_id, asset_id, updated)
              :ok

            {:error, changeset} ->
              Repo.rollback(changeset)
          end
        end
      end)
      |> case do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def refresh_provider_evidence(_, _, _), do: {:error, :invalid_metadata_evidence}

  defp insert_empty_selection!(user_id, asset_id) do
    {:ok, selection} =
      Repo.insert(
        Selection.changeset(%Selection{}, %{
          user_id: user_id,
          asset_set_id: asset_id,
          description: "",
          revision: 1
        })
      )

    selection
  end

  defp evidence_reference_ids(selection) do
    selected =
      selection.field_sources
      |> Map.values()
      |> Enum.map(&Map.get(&1, "evidence_id"))

    conflicts =
      Repo.all(
        from c in Conflict,
          where:
            c.user_id == ^selection.user_id and c.asset_set_id == ^selection.asset_set_id and
              is_nil(c.resolved_at)
      )
      |> Enum.map(&get_in(&1.incoming_alternative, ["source", "evidence_id"]))

    Enum.filter(selected ++ conflicts, &is_binary/1)
  end

  defp sanitized_evidence(evidence) do
    %{
      "provider" => evidence.provider,
      "provider_version" => evidence.provider_version,
      "external_id" => evidence.external_id,
      "title" => evidence.title,
      "description" => evidence.provider_description,
      "platform" => evidence.platform,
      "confidence" => evidence.confidence,
      "match_kind" => evidence.match_kind,
      "attribution" => evidence.attribution,
      "terms_url" => evidence.terms_url,
      "policy_revision" => evidence.policy_revision,
      "cache_expires_at" => evidence.cache_expires_at,
      "license_expires_at" => evidence.license_expires_at
    }
  end

  @doc "Returns a selected description only when the asset set belongs to the requested owner."
  @spec get_description(pos_integer(), String.t()) ::
          {:ok, Selection.t()} | {:error, :not_found}
  def get_description(user_id, asset_set_id)
      when is_integer(user_id) and is_binary(asset_set_id) do
    with {:ok, asset_set_id} <- Ecto.UUID.cast(asset_set_id) do
      selection =
        from(s in Selection,
          where: s.user_id == ^user_id and s.asset_set_id == ^asset_set_id,
          where: is_nil(s.deleted_at)
        )
        |> Repo.one()

      case selection do
        nil -> {:error, :not_found}
        selection -> {:ok, selection}
      end
    else
      :error -> {:error, :not_found}
    end
  end

  def get_description(_user_id, _asset_set_id), do: {:error, :not_found}

  @doc "Restores an exported owner selection without replacing a newer local correction."
  def restore_description(user_id, asset_set_id, description, revision)
      when is_integer(user_id) and is_binary(asset_set_id) and is_binary(description) and
             is_integer(revision) and revision > 0 do
    with {:ok, id} <- Ecto.UUID.cast(asset_set_id),
         :ok <- validate_description(description),
         true <- Repo.exists?(from(a in AssetSet, where: a.id == ^id and a.user_id == ^user_id)) do
      Repo.transaction(fn ->
        case Repo.one(
               from s in Selection,
                 where: s.user_id == ^user_id and s.asset_set_id == ^id,
                 lock: "FOR UPDATE"
             ) do
          %Selection{} = current ->
            current

          nil ->
            {:ok, selection} =
              Repo.insert(
                Selection.changeset(%Selection{}, %{
                  user_id: user_id,
                  asset_set_id: id,
                  description: description,
                  revision: revision,
                  deleted_at: nil
                })
              )

            {:ok, _entry} =
              ChangeJournal.append(user_id, :metadata, id, MetadataPayload.build(selection))

            selection
        end
      end)
      |> case do
        {:ok, selection} -> {:ok, selection}
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  def restore_description(_, _, _, _), do: {:error, :not_found}

  defp validate_description(description) do
    if String.valid?(description) and byte_size(description) <= 65_536 do
      :ok
    else
      {:error,
       %Selection{}
       |> Ecto.Changeset.change()
       |> Ecto.Changeset.add_error(
         :description,
         "must be valid UTF-8 and at most 65536 bytes"
       )}
    end
  end
end
