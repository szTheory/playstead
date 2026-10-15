defmodule Playstead.Sync.MetadataPayload do
  @moduledoc "Versioned selected-metadata payload for the optional metadata journal kind."

  alias Playstead.Metadata.Selection

  @version 1
  @keys ~w(version type asset_set_id description revision deleted_at selections field_revisions field_sources deleted_fields conflicts evidence)a

  @doc "The complete v1 metadata payload key set."
  def keys, do: @keys

  @doc "Builds the versioned selected-description journal and snapshot value."
  @spec build(Selection.t()) :: map()
  def build(%Selection{} = selection, conflicts \\ [], evidence \\ %{}) do
    %{
      version: @version,
      type: "description",
      asset_set_id: selection.asset_set_id,
      description: selection.description,
      revision: selection.revision,
      deleted_at: selection.deleted_at,
      selections: selection.selections || %{"description" => selection.description},
      field_revisions: selection.field_revisions || %{},
      field_sources: selection.field_sources || %{},
      deleted_fields: selection.deleted_fields || %{},
      conflicts: Enum.map(conflicts, &conflict_view/1),
      evidence: evidence
    }
  end

  defp conflict_view(conflict) do
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
