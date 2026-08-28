defmodule PlaysteadWeb.Browser.DevicesJourneyTest do
  @moduledoc """
  UAT #5/#6 as an end-to-end browser journey: a Mac's pairing request →
  the owner approves from the queue after seeing the display code → the Mac
  redeems → the device row appears with its fingerprint → rename → revoke
  behind a fresh sudo → tombstone + journal tombstone; plus deny, and the
  CA-fingerprint panel across all four transport states.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias Playstead.Pairing
  alias Playstead.Sync.ChangeJournal

  feature "pair → approve → redeem → rename → revoke (sudo) → tombstone", %{session: session} do
    user = owner_fixture()
    {request, device_code} = pairing_request_fixture(%{"device_name" => "Owner's MacBook Pro"})

    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live("/devices")
      |> assert_has(css("#display-code-#{request.id}", text: request.display_code))
      |> assert_has(css("#pairing-request-#{request.id}-claimed-name", text: "Owner's MacBook Pro"))
      |> assert_has(
        css("#pairing-request-#{request.id}-requesting-from", text: "from an external address")
      )
      |> click(css("#approve-#{request.id}"))
      |> assert_gone(css("#display-code-#{request.id}"))
      |> assert_has(css("#requests-empty"))

    assert {:ok, %{status: "approved"}} = Pairing.get_request_status(request.id)

    # The Mac redeems with its private device_code; the console shows the row.
    {:ok, %{device: device}} = Pairing.redeem(request.id, device_code)
    fingerprint = Pairing.active_credential_fingerprint(device.id)

    session =
      session
      |> visit_live("/devices")
      |> assert_has(css("#device-#{device.id}-name", text: "Owner's MacBook Pro"))
      |> assert_has(css("#device-#{device.id}-fingerprint", text: fingerprint))
      |> assert_has(css("#device-#{device.id}-last-seen", text: "Never"))

    # The credential itself is never rendered.
    refute Wallaby.Browser.text(session) =~ "pk_"

    # Rename in place.
    session =
      session
      |> click(css("#device-#{device.id}-rename"))
      |> fill_in(css("#device-#{device.id}-rename-input"), with: "Studio Mac")
      |> click(css("#device-#{device.id}-rename-save"))
      |> assert_has(css("#device-#{device.id}-name", text: "Studio Mac"))
      |> assert_has(css("#device-#{device.id}-revoke[aria-label='Revoke Studio Mac']"))

    assert Playstead.Repo.reload!(device).name == "Studio Mac"

    # Revoke (fresh sudo; the data-confirm dialog is accepted by the driver).
    session =
      session
      |> click(css("#device-#{device.id}-revoke"))
      |> assert_has(css("#revoked-devices #device-#{device.id}"))
      |> assert_has(css("#device-#{device.id}-revoked-at", text: "Revoked"))
      |> assert_gone(css("#device-#{device.id}-revoke"))
      |> assert_gone(css("#device-#{device.id}-fingerprint"))

    assert %DateTime{} = Playstead.Repo.reload!(device).revoked_at

    entries = ChangeJournal.read_after(user.id, 0, 100)
    assert Enum.any?(entries, &(&1.entity_id == device.id and &1.operation == "tombstone"))

    refute Wallaby.Browser.text(session) =~ "pk_"
  end

  feature "deny removes the request and issues nothing", %{session: session} do
    user = owner_fixture()
    {request, device_code} = pairing_request_fixture()

    session
    |> log_in_via_cookie(user)
    |> visit_live("/devices")
    |> click(css("#deny-#{request.id}"))
    |> assert_gone(css("#display-code-#{request.id}"))
    |> assert_has(css("#requests-empty"))

    assert {:ok, %{status: "denied"}} = Pairing.get_request_status(request.id)
    assert {:error, _} = Pairing.redeem(request.id, device_code)
  end

  feature "the server-certificate panel is honest in every transport state", %{session: session} do
    user = owner_fixture()
    session = log_in_via_cookie(session, user)

    put_env_overrides!(%{"PLAYSTEAD_CADDY_CA_PATH" => "/nonexistent/root.crt"})

    session =
      session
      |> visit_live("/devices")
      |> assert_has(
        css("#server-certificate[data-transport-state=plain_http]",
          text: "There is no certificate to pin."
        )
      )
      |> assert_gone(css("#ca-fingerprint"))

    put_env_overrides!(%{"PLAYSTEAD_CADDY_CA_PATH" => write_fixture_cert!("devices_journey")})

    session =
      session
      |> visit_live("/devices")
      |> assert_has(css("#server-certificate[data-transport-state=internal_ca]"))
      |> assert_has(css("#ca-fingerprint", text: expected_fingerprint()))
      |> assert_has(
        css("#server-certificate", text: "A Mac can pin this fingerprint at pairing time.")
      )

    put_env_overrides!(%{"PLAYSTEAD_DOMAIN" => "play.example.com"})

    session =
      session
      |> visit_live("/devices")
      |> assert_has(
        css("#server-certificate[data-transport-state=letsencrypt]",
          text: "publicly-trusted certificate"
        )
      )
      |> assert_gone(css("#ca-fingerprint"))

    put_env_overrides!(%{
      "PLAYSTEAD_PROXY" => "external",
      "PLAYSTEAD_DOMAIN" => "play.example.com"
    })

    session
    |> visit_live("/devices")
    |> assert_has(
      css("#server-certificate[data-transport-state=external_proxy]",
        text: "external reverse proxy"
      )
    )
    |> assert_gone(css("#ca-fingerprint"))
  end
end
