defmodule Playstead.ReadinessTest do
  use Playstead.DataCase, async: true
  use ExUnitProperties

  import Playstead.TlsFixtures

  alias Playstead.Readiness

  # `summary/1` is pure over its env map, so these run `async: true` with
  # no `System.put_env/2` — the volumes row is pinned to a writable temp
  # dir so the assertion is about the https row, not this machine's disk.
  defp env(extra) do
    Map.merge(%{"PLAYSTEAD_BLOB_PATH" => System.tmp_dir!()}, extra)
  end

  defp https_row(env), do: env |> Readiness.summary() |> Enum.find(&(&1.id == :https))

  test "always returns exactly the six rows, in order, each :ok, :warning, or :error" do
    rows = Readiness.summary(env(%{}))

    assert Enum.map(rows, & &1.id) == [
             :database,
             :volumes,
             :https,
             :inbox,
             :exports,
             :blob_volume_atomicity
           ]

    assert Enum.all?(rows, &(&1.state in [:ok, :warning, :error]))
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

  # --- inbox (D-01) -------------------------------------------------------

  defp inbox_row(env), do: env |> Readiness.summary() |> Enum.find(&(&1.id == :inbox))

  test "the inbox probe passes on a read-only, non-writable directory" do
    dir =
      System.tmp_dir!() |> Path.join("playstead-inbox-ro-#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)
    File.chmod!(dir, 0o555)

    on_exit(fn ->
      File.chmod(dir, 0o755)
      File.rm_rf(dir)
    end)

    assert %{id: :inbox, state: :ok} = inbox_row(env(%{"PLAYSTEAD_INBOX_PATH" => dir}))
  end

  test "a missing inbox path produces a warning naming the compose mount" do
    assert %{id: :inbox, state: :warning, message: message} =
             inbox_row(env(%{"PLAYSTEAD_INBOX_PATH" => "/nonexistent/playstead-inbox"}))

    assert message =~ "/app/inbox"
  end

  # --- exports (D-33) ------------------------------------------------------

  defp exports_row(env), do: env |> Readiness.summary() |> Enum.find(&(&1.id == :exports))

  test "the exports row is :ok for a writable path" do
    dir = System.tmp_dir!()
    assert %{id: :exports, state: :ok} = exports_row(env(%{"PLAYSTEAD_EXPORT_PATH" => dir}))
  end

  test "a non-writable export path produces an :error row" do
    assert %{id: :exports, state: :error, message: message} =
             exports_row(env(%{"PLAYSTEAD_EXPORT_PATH" => "/nonexistent/playstead-exports"}))

    assert message =~ "/nonexistent/playstead-exports"
  end

  # --- blob volume atomicity (D-11, RESEARCH Pitfall 2) ---------------------

  defp atomicity_row(env),
    do: env |> Readiness.summary() |> Enum.find(&(&1.id == :blob_volume_atomicity))

  test "the same-volume check degrades to a non-error state when mountinfo is unavailable" do
    refute File.exists?("/proc/self/mountinfo")

    assert %{id: :blob_volume_atomicity, state: state} = atomicity_row(env(%{}))
    assert state in [:ok, :warning]
  end

  # --- free space (D-10) ----------------------------------------------------

  describe "required_bytes/2 and fits_free_space?/3" do
    test "required_bytes/2 never returns less than the requested byte count" do
      check all(
              requested <- StreamData.integer(0..10_000_000_000),
              capacity <- StreamData.integer(0..10_000_000_000)
            ) do
        assert Readiness.required_bytes(requested, capacity) >= requested
      end
    end

    test "a request exactly at the available margin fits; one byte more is refused" do
      requested = 1_000
      capacity = 100_000
      required = Readiness.required_bytes(requested, capacity)

      assert Readiness.fits_free_space?(requested, required, capacity)
      refute Readiness.fits_free_space?(requested, required - 1, capacity)
    end

    test "the 1 GiB floor applies when 5% of capacity is smaller" do
      # 5% of a 1 GiB capacity is far under 1 GiB itself.
      assert Readiness.required_bytes(0, 1_073_741_824) == 1_073_741_824
    end

    test "5% of capacity applies once it exceeds the 1 GiB floor" do
      capacity = 100 * 1_073_741_824
      expected_margin = div(capacity * 5, 100)

      assert Readiness.required_bytes(0, capacity) == expected_margin
    end
  end
end
