defmodule Playstead.Catalogue.Payload do
  @moduledoc """
  The frozen `catalogue` change-journal payload (D-23). Built through
  this one function so no call site can add a field by accident — the
  key set is exactly what D-23 specifies, and carries no source
  filesystem path, no legacy digest, and no provenance: those are
  server-side facts about where bytes came from, and a client that
  never receives them cannot leak them.
  """

  import Ecto.Query, warn: false

  alias Playstead.Catalogue.AssetSet
  alias Playstead.Recognition.Evidence
  alias Playstead.Repo

  @frozen_keys ~w(
    id system status display_title title_source tags manifest_version
    members recognition attention excluded_at updated_at
  )a

  @doc "The frozen key set, for tests that assert no accidental additions."
  def frozen_keys, do: @frozen_keys

  @doc """
  Builds the exact frozen payload for `asset_set` (its `:asset_members`
  association, each with its `:blob` nested, must be preloaded). Reads the most
  recent recognition evidence row for the set's members' blobs, if
  any, to populate the `recognition` block.
  """
  @spec build(AssetSet.t()) :: map()
  def build(%AssetSet{} = asset_set) do
    members = asset_set.asset_members |> Enum.sort_by(& &1.ordinal)
    latest_recognition = latest_recognition_for(members)

    %{
      id: asset_set.id,
      system: asset_set.system_id,
      status: asset_set.status,
      display_title: asset_set.display_title,
      title_source: asset_set.title_source,
      tags: %{},
      manifest_version: 1,
      members: Enum.map(members, &member_view/1),
      recognition: recognition_view(latest_recognition),
      attention: false,
      excluded_at: asset_set.excluded_at,
      updated_at: asset_set.updated_at
    }
  end

  defp member_view(member) do
    %{
      ordinal: member.ordinal,
      role: member.role,
      required: member.required,
      sha256: member.blob && member.blob.sha256,
      size: member.blob && member.blob.size_bytes,
      name: member.declared_name
    }
  end

  defp latest_recognition_for(members) do
    blob_ids = members |> Enum.map(& &1.blob_id) |> Enum.reject(&is_nil/1)

    if blob_ids == [] do
      nil
    else
      from(r in Evidence,
        where: r.blob_id in ^blob_ids,
        order_by: [desc: r.inserted_at],
        limit: 1
      )
      |> Repo.one()
    end
  end

  defp recognition_view(nil) do
    %{
      status: "no_reference_installed",
      confidence: nil,
      provider: nil,
      provider_version: nil,
      reference_name: nil
    }
  end

  defp recognition_view(%Evidence{} = evidence) do
    %{
      status: evidence.status,
      confidence: evidence.confidence,
      provider: evidence.provider_name,
      provider_version: evidence.provider_version,
      reference_name: evidence.reference_name
    }
  end
end
