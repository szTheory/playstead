defmodule Playstead.Repo.Migrations.EnsureMetadataProviderTermsColumns do
  use Ecto.Migration

  def change do
    alter table(:metadata_provider_evidence) do
      add_if_not_exists :terms_url, :string,
        null: false,
        default: "https://legal.twitch.com/legal/developer-agreement/"

      add_if_not_exists :license_expires_at, :utc_datetime
    end
  end
end
