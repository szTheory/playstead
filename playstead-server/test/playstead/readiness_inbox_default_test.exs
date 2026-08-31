defmodule Playstead.ReadinessInboxDefaultTest do
  # `async: false` on purpose: this is the one readiness test that reads
  # the application environment rather than only its own `env` map, and
  # several import suites mutate `:playstead, :inbox_path` concurrently.
  # ExUnit runs sync modules apart from async ones, so this cannot race
  # them.
  use Playstead.DataCase, async: false

  alias Playstead.Readiness

  defp inbox_row(env) do
    %{"PLAYSTEAD_BLOB_PATH" => System.tmp_dir!()}
    |> Map.merge(env)
    |> Readiness.summary()
    |> Enum.find(&(&1.id == :inbox))
  end

  setup do
    previous = Application.get_env(:playstead, :inbox_path)
    on_exit(fn -> Application.put_env(:playstead, :inbox_path, previous) end)
    :ok
  end

  # With `PLAYSTEAD_INBOX_PATH` unset — the normal case for a developer
  # running `mix phx.server` natively — the readiness row must report on
  # whatever `config :playstead, :inbox_path` resolved to, which
  # `config/runtime.exs` points at the repo's own `inbox/` in `:dev`.
  # Before this it re-hardcoded `/app/inbox`, so the panel described a
  # container path the import UI was not reading.
  test "with no env override the inbox row reports on the configured :inbox_path" do
    dir =
      System.tmp_dir!()
      |> Path.join("playstead-inbox-configured-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    Application.put_env(:playstead, :inbox_path, dir)

    assert %{id: :inbox, state: :ok, message: message} = inbox_row(%{})
    assert message =~ dir
  end

  test "a configured inbox path that does not exist warns and names that path" do
    missing = "/nonexistent/playstead-configured-inbox"
    Application.put_env(:playstead, :inbox_path, missing)

    assert %{id: :inbox, state: :warning, message: message} = inbox_row(%{})
    assert message =~ missing
    # The remediation still names the compose mount, since that is what a
    # Docker deployment has to fix.
    assert message =~ "./inbox:/app/inbox:ro"
  end

  test "PLAYSTEAD_INBOX_PATH still overrides the configured path" do
    dir =
      System.tmp_dir!()
      |> Path.join("playstead-inbox-override-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    Application.put_env(:playstead, :inbox_path, "/nonexistent/should-not-be-used")

    assert %{id: :inbox, state: :ok, message: message} =
             inbox_row(%{"PLAYSTEAD_INBOX_PATH" => dir})

    assert message =~ dir
  end
end
