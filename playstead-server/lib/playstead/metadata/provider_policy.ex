defmodule Playstead.Metadata.ProviderPolicy do
  @moduledoc "IGDB attribution, transient cache and image rights policy."

  @revision "igdb-noncommercial-2026-10"
  @cache_seconds 30 * 24 * 60 * 60

  def revision, do: @revision
  def transient_cache_seconds, do: @cache_seconds

  def attribution do
    "Game metadata suggestions provided by IGDB. IGDB use is subject to the Twitch Developer Service Agreement; noncommercial use only."
  end

  def terms_url, do: "https://legal.twitch.com/legal/developer-agreement/"

  def image_fetch_allowed?(consent) when is_map(consent) do
    exact_revision = Application.get_env(:playstead, :igdb_private_image_terms_revision)

    is_binary(exact_revision) and exact_revision != "" and
      Map.get(consent, :image_terms_revision) == exact_revision and
      Map.get(consent, :image_grant_scope) == "private_single_owner"
  end

  def image_fetch_allowed?(_), do: false
end
