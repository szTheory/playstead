defmodule PlaysteadWeb.DevicesLive do
  @moduledoc """
  `/devices` — the pairing approval queue and paired-device list (D-07
  through D-13). The console issues the same commands an API caller
  would (`Playstead.Pairing`), never a private path (T-01-36).

  All pairing/device state is read fresh from `Playstead.Pairing` on
  every mount and after every mutation — LiveView process assigns are a
  cache, never the source of truth, since LiveView re-runs `mount/3` on
  reconnect.

  Viewing this page only requires an authenticated owner; revoking a
  device requires, in addition, a fresh sudo confirmation checked
  directly against `Playstead.Accounts.sudo_mode?/1` at the moment of the
  action (not a whole-route gate) so the approval queue and read-only
  device list stay reachable without re-authenticating on every visit.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Accounts
  alias Playstead.Pairing
  alias Playstead.TlsTrust
  alias PlaysteadWeb.DevicesLive.{ApprovalCard, DeviceRow}
  alias PlaysteadWeb.Problem

  import ApprovalCard, only: [approval_card: 1]
  import DeviceRow, only: [device_row: 1]

  # Presentation-only tick driving the countdown display; server-side
  # expiry is always re-derived from `expires_at`, never from this timer
  # (D-12 — a drifted or paused tick can never grant an extra second of
  # validity).
  @tick_interval_ms 1_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@tick_interval_ms, self(), :tick)

    {:ok,
     socket
     |> assign(
       page_title: "Devices",
       now: DateTime.utc_now(),
       acting: nil,
       renaming_id: nil,
       ca_fingerprint: TlsTrust.ca_fingerprint(),
       transport_state: TlsTrust.transport_state()
     )
     |> load_requests()
     |> load_devices()}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :now, DateTime.utc_now())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-[Inter]">
      <div class="mx-auto max-w-4xl space-y-8">
        <div>
          <h1 class="text-2xl font-semibold text-[#F1F5F9]">Devices</h1>
          <.ca_fingerprint_panel ca_fingerprint={@ca_fingerprint} transport_state={@transport_state} />
        </div>

        <section>
          <h2 class="text-lg font-semibold text-[#F1F5F9]">Pairing requests</h2>
          <p :if={@pending_count >= @pending_cap} class="mt-2 text-sm text-[#FBBF24]">
            {@pending_count} pending — queue full — oldest request will be evicted.
          </p>

          <div
            :if={@requests == []}
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">No pairing requests</p>
            <p class="mt-1 text-sm text-[#94A3B8]">
              When a Mac requests to pair, its code will appear here for you to approve. Nothing to do right now.
            </p>
          </div>

          <div :for={request <- @requests} class="mt-4">
            <.approval_card request={request} now={@now} acting={@acting} />
          </div>
        </section>

        <section class="border-t border-[#334155] pt-8">
          <h2 class="text-lg font-semibold text-[#F1F5F9]">Paired devices</h2>
          <p class="mt-1 text-sm text-[#94A3B8]">
            A revoked Mac keeps its downloaded games and saves and can pair again from its Settings screen.
          </p>

          <div
            :if={@active_devices == [] and @revoked_devices == []}
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">No devices paired yet</p>
            <p class="mt-1 text-sm text-[#94A3B8]">
              Pair a Mac from its Settings screen, then approve the request here.
            </p>
          </div>

          <div
            :if={@active_devices != []}
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] divide-y divide-[#334155]"
          >
            <.device_row
              :for={device <- @active_devices}
              device={device}
              acting={@acting}
              renaming_id={@renaming_id}
              tombstone={false}
            />
          </div>

          <div :if={@revoked_devices != []} class="mt-6">
            <h3 class="text-sm font-semibold text-[#94A3B8]">Revoked</h3>
            <div class="mt-2 divide-y divide-[#334155] rounded-lg border border-[#334155] bg-[#1E293B]">
              <.device_row
                :for={device <- @revoked_devices}
                device={device}
                acting={@acting}
                renaming_id={nil}
                tombstone={true}
              />
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  # --- pairing requests -------------------------------------------------

  # --- pairing requests -------------------------------------------------

  @impl true
  def handle_event("approve", %{"id" => id}, socket), do: handle_transition(socket, id, :approve)
  def handle_event("deny", %{"id" => id}, socket), do: handle_transition(socket, id, :deny)

  # --- device list, rename, revoke --------------------------------------

  def handle_event("edit_name", %{"id" => id}, socket) do
    {:noreply, assign(socket, :renaming_id, id)}
  end

  def handle_event("cancel_rename", _params, socket) do
    {:noreply, assign(socket, :renaming_id, nil)}
  end

  def handle_event("rename", %{"device_id" => id, "name" => name}, socket) do
    scope = socket.assigns.current_scope

    case Pairing.rename_device(scope, id, name) do
      {:ok, _device} ->
        {:noreply, socket |> assign(:renaming_id, nil) |> load_devices()}

      {:error, _reason} ->
        {:noreply,
         socket
         |> assign(:renaming_id, nil)
         |> put_flash(:error, generic_error_flash())}
    end
  end

  def handle_event("revoke", %{"id" => id}, socket) do
    user = socket.assigns.current_scope.user

    if Accounts.sudo_mode?(user) do
      socket = assign(socket, :acting, {id, :revoke})

      case Pairing.revoke_device(socket.assigns.current_scope, id) do
        {:ok, _device} ->
          {:noreply, socket |> assign(:acting, nil) |> load_devices()}

        {:error, _reason} ->
          {:noreply,
           socket
           |> assign(:acting, nil)
           |> put_flash(:error, generic_error_flash())}
      end
    else
      {:noreply, redirect(socket, to: ~p"/sudo?return_to=%2Fdevices")}
    end
  end

  defp handle_transition(socket, id, action) do
    scope = socket.assigns.current_scope
    socket = assign(socket, :acting, {id, action})

    result =
      case action do
        :approve -> Pairing.approve(scope, id)
        :deny -> Pairing.deny(scope, id)
      end

    case result do
      {:ok, _request} ->
        {:noreply, socket |> assign(:acting, nil) |> load_requests()}

      {:error, {:invalid_transition, "expired"}} ->
        {:noreply,
         socket
         |> assign(:acting, nil)
         |> load_requests()
         |> put_flash(
           :error,
           "This request expired before it was approved. Ask the Mac to request pairing again."
         )}

      {:error, _other} ->
        {:noreply,
         socket
         |> assign(:acting, nil)
         |> load_requests()
         |> put_flash(:error, generic_error_flash())}
    end
  end

  defp load_requests(socket) do
    scope = socket.assigns.current_scope

    assign(socket,
      requests: Pairing.list_pending_requests(scope),
      pending_count: Pairing.pending_request_count(),
      pending_cap: Pairing.pending_queue_cap()
    )
  end

  defp load_devices(socket) do
    scope = socket.assigns.current_scope
    devices = Pairing.list_devices(scope)
    {active, revoked} = Enum.split_with(devices, &is_nil(&1.revoked_at))
    assign(socket, active_devices: active, revoked_devices: revoked)
  end

  defp generic_error_flash do
    "Something went wrong on the server. Your data is safe — nothing was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end

  # --- CA fingerprint panel (D-13) ---------------------------------------

  attr :ca_fingerprint, :any, required: true
  attr :transport_state, :atom, required: true

  defp ca_fingerprint_panel(%{transport_state: :internal_ca} = assigns) do
    ~H"""
    <div class="mt-2 rounded-lg border border-[#334155] bg-[#1E293B] p-4">
      <p class="text-sm font-semibold text-[#F1F5F9]">Server certificate</p>
      <p
        :if={match?({:ok, _}, @ca_fingerprint)}
        class="mt-1 font-['JetBrains_Mono'] text-[14px] text-[#94A3B8]"
      >
        {elem(@ca_fingerprint, 1)}
      </p>
      <p :if={match?({:ok, _}, @ca_fingerprint)} class="mt-1 text-sm text-[#94A3B8]">
        This server uses a locally-trusted certificate. A Mac can pin this fingerprint at pairing time.
      </p>
      <p :if={!match?({:ok, _}, @ca_fingerprint)} class="mt-1 text-sm text-[#94A3B8]">
        The server certificate fingerprint isn't available yet.
      </p>
    </div>
    """
  end

  defp ca_fingerprint_panel(%{transport_state: :letsencrypt} = assigns) do
    ~H"""
    <div class="mt-2 rounded-lg border border-[#334155] bg-[#1E293B] p-4">
      <p class="text-sm font-semibold text-[#F1F5F9]">Server certificate</p>
      <p class="mt-1 text-sm text-[#94A3B8]">
        This server has a publicly-trusted certificate. Pinning is unnecessary.
      </p>
    </div>
    """
  end

  defp ca_fingerprint_panel(%{transport_state: :external_proxy} = assigns) do
    ~H"""
    <div class="mt-2 rounded-lg border border-[#334155] bg-[#1E293B] p-4">
      <p class="text-sm font-semibold text-[#F1F5F9]">Server certificate</p>
      <p class="mt-1 text-sm text-[#94A3B8]">
        This server is reached through an external reverse proxy. Playstead does not manage that
        certificate, so there is nothing here to pin.
      </p>
    </div>
    """
  end

  defp ca_fingerprint_panel(%{transport_state: :plain_http} = assigns) do
    ~H"""
    <div class="mt-2 rounded-lg border border-[#334155] bg-[#1E293B] p-4">
      <p class="text-sm font-semibold text-[#F1F5F9]">Server certificate</p>
      <p class="mt-1 text-sm text-[#94A3B8]">
        This server is running over plain HTTP right now. There is no certificate to pin.
      </p>
    </div>
    """
  end
end
