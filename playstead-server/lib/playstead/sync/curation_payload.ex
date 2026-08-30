defmodule Playstead.Sync.CurationPayload do
  @moduledoc """
  The `curation` change-journal payload (D-08): one entity kind, six
  inner shapes discriminated by a `type` field —
  `favorite | collection | collection_member | queue_item |
  continue_dismissal | recent`. Curation never travels inside the
  frozen `catalogue` payload (`Playstead.Catalogue.Payload`, D-23) —
  mixing per-user preference into that payload would re-emit a whole
  catalogue entity on every toggle and break its additive-only
  discipline.

  `build/1` dispatches on the struct/shape given to it; each curation
  schema gets its own clause as it is introduced (favorite here in
  plan 03-04 task 1; the remaining five clauses are added by the
  plans/tasks that introduce their schemas).
  """

  alias Playstead.Curation.Favorite

  @doc "Builds the `curation` journal payload for a curation row."
  @spec build(struct()) :: map()
  def build(%Favorite{} = favorite) do
    %{
      type: "favorite",
      asset_set_id: favorite.asset_set_id,
      created_at: favorite.inserted_at
    }
  end
end
