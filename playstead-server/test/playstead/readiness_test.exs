defmodule Playstead.ReadinessTest do
  use Playstead.DataCase, async: true

  import Playstead.TlsFixtures

  alias Playstead.Readiness

  # `summary/1` is pure over its env map, so these run `async: true` with
  # no `System.put_env/2` — the volumes row is pinned to a writable temp
  # dir so the assertion is about the https row, not this machine's disk.
  defp env(extra) do
    Map.merge(%{"PLAYSTEAD_BLOB_PATH" => System.tmp_dir!()}, extra)
  end

  defp https_row(env), do: env |> Readiness.summary() |> Enum.find(&(&1.id == :https))

  test "always returns exactly the three rows, in order, each :ok or :warning" do
    rows = Readiness.summary(env(%{}))

    assert Enum.map(rows, & &1.id) == [:database, :volumes, :https]
    assert Enum.all?(rows, &(&1.state in [:ok, :warning]))
    assert Enum.all?(rows, &(is_binary(&1.message) and &1.message != ""))
  end

  test "the database row is :ok against the migrated test database" do
    assert %{state: :ok} = env(%{}) |> Readiness.summary() |> Enum.find(&(&1.id == :database))
  end

  test "an external proxy is an honest warning, never blocking" do
    assert %{state: :warning, message: message} =
             https_row(env(%{"PLAYSTEAD_PROXY" => "external"}))

    assert message =~ "PLAYSTEAD_PROXY=external"
  end

  test "a configured domain reports Let's Encrypt as :ok and names the domain" do
    assert %{state: :ok, message: message} =
             https_row(env(%{"PLAYSTEAD_DOMAIN" => "example.com"}))

    assert message =~ "Let's Encrypt for example.com"
  end

  test "an external proxy wins over a domain, matching TlsTrust.transport_state/1" do
    env = env(%{"PLAYSTEAD_PROXY" => "external", "PLAYSTEAD_DOMAIN" => "example.com"})
    assert %{state: :warning} = https_row(env)
    assert Playstead.TlsTrust.transport_state(env) == :external_proxy
  end

  test "outside :prod, no domain and no proxy is the plain-HTTP warning" do
    assert %{state: :warning, message: message} =
             https_row(env(%{"PLAYSTEAD_CADDY_CA_PATH" => "/nonexistent/root.crt"}))

    assert message =~ "plain HTTP"
  end

  test "the volumes row warns when the blob path is not writable" do
    assert %{state: :warning, message: message} =
             %{"PLAYSTEAD_BLOB_PATH" => "/nonexistent/playstead-blobs"}
             |> Readiness.summary()
             |> Enum.find(&(&1.id == :volumes))

    assert message =~ "/nonexistent/playstead-blobs"
  end

  test "the volumes row is :ok for a writable path" do
    assert %{state: :ok} = env(%{}) |> Readiness.summary() |> Enum.find(&(&1.id == :volumes))
    refute File.exists?(Path.join(System.tmp_dir!(), ".playstead-readiness-probe"))
  end

  test "an on-disk internal CA root does not change the readiness row outside :prod" do
    path = write_fixture_cert!("readiness_test")
    assert %{state: :warning} = https_row(env(%{"PLAYSTEAD_CADDY_CA_PATH" => path}))
  end
end
