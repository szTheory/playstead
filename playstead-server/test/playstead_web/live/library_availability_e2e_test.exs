defmodule PlaysteadWeb.LibraryAvailabilityE2ETest do
  @moduledoc """
  Plan 03-15 (LIBR-02 gap closure, Task 2): proves the `missing_dependency`
  chip can return a game because a real device produced that fact and
  sent it over the real transport -- not because this test seeded the
  read model directly.

  This test reads `shared/availability-report-fixture.json` from disk
  (the same fixture `AvailabilityReporterTests.
  test_buildEntriesOutputEncodesByteIdenticallyToSharedReportFixture`
  proves the Mac encoder produces) and PUTs its body, verbatim except
  for `asset_set_id` binding, to `PUT /api/v1/devices/me/availability`
  through the real controller. Only after that HTTP round trip succeeds
  does it mount the library LiveView and assert the chip.

  This file NEVER calls `Playstead.Availability.replace_for_device/2`
  and NEVER constructs a `Playstead.Availability.DeviceReport` struct
  directly -- the single reason this file exists separately from
  `library_live_test.exs`, whose own six-value discrimination test
  seeds the read model directly and therefore proves only that the
  LiveView clause works, never that a device can produce the fact.
  """

  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  setup :register_and_log_in_user

  defp fixture_body! do
    path = Path.join([File.cwd!(), "..", "shared", "availability-report-fixture.json"])
    path |> File.read!() |> Jason.decode!()
  end

  defp paired_device(scope) do
    %{device: device, credential_plaintext: token} = device_fixture(scope)
    {device, token}
  end

  test "the missing_dependency chip returns a game the device reported over HTTP", %{
    conn: conn,
    user: user,
    scope: scope
  } do
    {_device, token} = paired_device(scope)
    fixture = fixture_body!()

    # Bind each fixture entry's placeholder asset_set_id to a real asset
    # set this test's own user owns, so `replace_for_device/2`'s
    # ownership filter does not silently drop it. `asset_set_id` is the
    # only field this test rewrites -- every other fact
    # (downloading/verified/pinned/missing_dependency/download_percent)
    # is sent exactly as the fixture declares it.
    missing_dependency_set =
      asset_set_fixture(user.id, %{display_title: "Missing Dependency Fixture Game"})

    downloading_set = asset_set_fixture(user.id, %{display_title: "Downloading Fixture Game"})
    verified_set = asset_set_fixture(user.id, %{display_title: "Verified Fixture Game"})
    all_false_set = asset_set_fixture(user.id, %{display_title: "All False Fixture Game"})

    bindings = %{
      "missing-dependency-asset-set" => missing_dependency_set,
      "downloading-asset-set" => downloading_set,
      "verified-asset-set" => verified_set,
      "all-false-asset-set" => all_false_set
    }

    rewritten_entries =
      Enum.map(fixture["entries"], fn entry ->
        real_set = Map.fetch!(bindings, entry["asset_set_id"])
        Map.put(entry, "asset_set_id", real_set.id)
      end)

    idempotency_key = "avail-e2e-#{System.unique_integer([:positive])}"

    put_resp =
      build_conn()
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("idempotency-key", idempotency_key)
      |> Phoenix.ConnTest.put(~p"/api/v1/devices/me/availability", %{"entries" => rewritten_entries})

    assert put_resp.status == 200

    {:ok, lv, _html} = live(conn, ~p"/library")

    lv |> element("#filter-chip-availability-missing_dependency") |> render_click()

    assert has_element?(lv, "#library-asset-stream ##{"asset-" <> missing_dependency_set.id}"),
           "the missing_dependency chip must return the game the device reported over HTTP"

    refute has_element?(lv, "#library-asset-stream ##{"asset-" <> downloading_set.id}")
    refute has_element?(lv, "#library-asset-stream ##{"asset-" <> verified_set.id}")
    refute has_element?(lv, "#library-asset-stream ##{"asset-" <> all_false_set.id}")

    lv |> element("#filter-chip-availability-missing_dependency") |> render_click()

    lv |> element("#filter-chip-availability-server_only") |> render_click()

    assert has_element?(lv, "#library-asset-stream ##{"asset-" <> all_false_set.id}"),
           "server_only must still return the game with every fact false"

    refute has_element?(lv, "#library-asset-stream ##{"asset-" <> missing_dependency_set.id}"),
           "server_only must not have eaten the missing_dependency chip's game"
  end
end
