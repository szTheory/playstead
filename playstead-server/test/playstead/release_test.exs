defmodule Playstead.ReleaseTest do
  use Playstead.DataCase, async: false

  alias Playstead.Release

  describe "assert_no_placeholder_secrets!/0" do
    test "rejects the exact .env.example placeholder value for SECRET_KEY_BASE" do
      System.put_env("SECRET_KEY_BASE", "REPLACE_WITH_GENERATED_SECRET_KEY_BASE")

      assert_raise RuntimeError, ~r/SECRET_KEY_BASE/, fn ->
        Release.assert_no_placeholder_secrets!()
      end
    after
      System.delete_env("SECRET_KEY_BASE")
    end

    test "rejects the exact .env.example placeholder value for POSTGRES_PASSWORD" do
      System.delete_env("SECRET_KEY_BASE")
      System.put_env("POSTGRES_PASSWORD", "REPLACE_WITH_STRONG_PASSWORD")

      assert_raise RuntimeError, ~r/POSTGRES_PASSWORD/, fn ->
        Release.assert_no_placeholder_secrets!()
      end
    after
      System.delete_env("POSTGRES_PASSWORD")
    end

    test "accepts a generated, non-placeholder value" do
      System.put_env("SECRET_KEY_BASE", "a-real-generated-secret-key-base-value")
      System.put_env("POSTGRES_PASSWORD", "a-real-generated-password")

      assert Release.assert_no_placeholder_secrets!() == :ok
    after
      System.delete_env("SECRET_KEY_BASE")
      System.delete_env("POSTGRES_PASSWORD")
    end

    test "does not gate on an unset environment variable" do
      System.delete_env("SECRET_KEY_BASE")
      System.delete_env("POSTGRES_PASSWORD")

      assert Release.assert_no_placeholder_secrets!() == :ok
    end
  end

  describe "assert_minimum_upgradable_version!/0" do
    test "rejects a schema version below the minimum-upgradable floor" do
      # Simulate an ancient database whose highest applied migration
      # predates this release's minimum-upgradable floor.
      Ecto.Adapters.SQL.query!(Playstead.Repo, "DELETE FROM schema_migrations", [])

      Ecto.Adapters.SQL.query!(
        Playstead.Repo,
        "INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, now())",
        [1]
      )

      assert_raise RuntimeError, ~r/minimum this release can upgrade from/, fn ->
        Release.assert_minimum_upgradable_version!()
      end
    end

    test "allows a schema at or above the minimum-upgradable floor" do
      assert Release.assert_minimum_upgradable_version!() == :ok
    end
  end
end
