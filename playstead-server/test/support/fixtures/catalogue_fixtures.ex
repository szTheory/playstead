defmodule Playstead.CatalogueFixtures do
  @moduledoc """
  Test helpers for creating `Playstead.Catalogue.AssetSet` rows
  directly (no upload pipeline), for tests that only need an owned
  asset set to reference — e.g. curation fixtures (plan 03-04).
  """

  alias Playstead.Catalogue.AssetSet

  @doc "Creates a minimal active asset set owned by `user_id`."
  def asset_set_fixture(user_id, attrs \\ %{}) do
    default = %{
      user_id: user_id,
      status: "active",
      member_fingerprint: "fixture:#{Ecto.UUID.generate()}",
      display_title: "Fixture Game"
    }

    {:ok, asset_set} =
      %AssetSet{}
      |> AssetSet.create_changeset(Map.merge(default, attrs))
      |> Playstead.Repo.insert()

    asset_set
  end
end
