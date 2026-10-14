defmodule BackupReleaseFixture.MixProject do
  use Mix.Project

  def project do
    [
      app: :backup_release_fixture,
      version: "0.1.0",
      deps: [],
      releases: [playstead: [include_erts: false]]
    ]
  end

  def application, do: []
end
