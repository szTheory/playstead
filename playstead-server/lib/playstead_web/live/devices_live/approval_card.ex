defmodule PlaysteadWeb.DevicesLive.ApprovalCard do
  @moduledoc """
  The pairing evidence card (D-07, D-09) — the whole security property.
  The display code is the single largest element in the console: 40px
  JetBrains Mono, 0.08em letter-spacing, accent color — a documented
  exception to the 4-role typography budget, scoped to this element on
  this screen only. Claimed fields (name/platform/app version) render
  muted, labelled, and truncated; observed facts (code, IP, age) are
  always present and never share the claimed fields' visual authority.
  """

  use Phoenix.Component
  import PlaysteadWeb.CoreComponents

  alias Playstead.Pairing.PairingRequest

  attr :request, PairingRequest, required: true
  attr :now, :any, required: true
  attr :acting, :any, default: nil

  def approval_card(assigns) do
    assigns =
      assigns
      |> assign(:expired?, assigns.request.status == "expired")
      |> assign(:remaining, remaining_seconds(assigns.request, assigns.now))

    ~H"""
    <div
      class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
      id={"pairing-request-#{@request.id}"}
    >
      <div class="flex items-start justify-between gap-4">
        <div>
          <p class="font-['JetBrains_Mono'] text-[40px] font-semibold tracking-[0.08em] text-[#38BDF8]">
            {@request.display_code}
          </p>
          <p class="mt-1 text-sm text-[#94A3B8]">
            Only approve if this code matches the one on your Mac's screen.
          </p>
        </div>
        <div class="shrink-0 text-right">
          <p :if={!@expired?} class="text-sm text-[#F1F5F9]">
            Expires in {format_countdown(@remaining)}
          </p>
          <p :if={@expired?} class="text-sm font-semibold text-[#EF4444]">Expired</p>
        </div>
      </div>

      <dl class="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
        <div class="min-w-0">
          <dt class="text-sm font-semibold text-[#94A3B8]">Device name (claimed)</dt>
          <dd
            class="mt-1 max-w-[16ch] truncate text-sm text-[#94A3B8]"
            title={claim(@request.claimed_device_name)}
            tabindex="0"
          >
            {claim(@request.claimed_device_name)}
          </dd>
        </div>
        <div class="min-w-0">
          <dt class="text-sm font-semibold text-[#94A3B8]">Platform (claimed)</dt>
          <dd class="mt-1 truncate text-sm text-[#94A3B8]">{claim(@request.claimed_platform)}</dd>
        </div>
        <div class="min-w-0">
          <dt class="text-sm font-semibold text-[#94A3B8]">App version (claimed)</dt>
          <dd class="mt-1 truncate text-sm text-[#94A3B8]">{claim(@request.claimed_app_version)}</dd>
        </div>
        <div class="min-w-0">
          <dt class="text-sm font-semibold text-[#F1F5F9]">Requesting from</dt>
          <dd class="mt-1 text-sm text-[#F1F5F9]">{network_hint(@request.requesting_ip)}</dd>
        </div>
      </dl>

      <p class="mt-3 text-sm text-[#94A3B8]">Requested {relative_age(@request.inserted_at, @now)}</p>

      <p :if={@expired?} class="mt-4 text-sm text-[#94A3B8]">
        This request expired before it was approved. Ask the Mac to request pairing again.
      </p>

      <div :if={!@expired?} class="mt-6 flex gap-3">
        <button
          type="button"
          phx-click="approve"
          phx-value-id={@request.id}
          disabled={@acting == {@request.id, :approve}}
          aria-label="Approve device"
          class="flex h-11 items-center justify-center gap-2 rounded-md bg-[#38BDF8] px-4 text-base font-semibold text-[#0F172A] hover:opacity-90 disabled:opacity-60"
        >
          <span :if={@acting == {@request.id, :approve}} class="motion-safe:animate-spin">
            <.icon name="hero-arrow-path" class="size-5" />
          </span>
          Approve
        </button>
        <button
          type="button"
          phx-click="deny"
          phx-value-id={@request.id}
          disabled={@acting == {@request.id, :deny}}
          aria-label="Deny pairing request"
          data-confirm="Deny this pairing request? The Mac will need to request pairing again."
          class="flex h-11 items-center justify-center gap-2 rounded-md border border-[#EF4444] px-4 text-base font-semibold text-[#EF4444] hover:bg-[#EF4444]/10 disabled:opacity-60"
        >
          <span :if={@acting == {@request.id, :deny}} class="motion-safe:animate-spin">
            <.icon name="hero-arrow-path" class="size-5" />
          </span>
          Deny
        </button>
      </div>
    </div>
    """
  end

  defp claim(nil), do: "Not reported"
  defp claim(""), do: "Not reported"
  defp claim(value), do: value

  defp remaining_seconds(%{expires_at: expires_at}, now),
    do: max(DateTime.diff(expires_at, now), 0)

  defp format_countdown(seconds) do
    minutes = div(seconds, 60)
    secs = rem(seconds, 60)
    :io_lib.format("~2..0B:~2..0B", [minutes, secs]) |> to_string()
  end

  defp relative_age(inserted_at, now) do
    seconds = max(DateTime.diff(now, inserted_at), 0)

    cond do
      seconds < 60 -> "just now"
      seconds < 3600 -> "#{div(seconds, 60)} min ago"
      true -> "#{div(seconds, 3600)} hr ago"
    end
  end

  # D-09: a plain-language network hint, never a bare address alone. No
  # geolocation or ASN enrichment (CONTEXT.md defers both).
  defp network_hint(nil), do: "unknown"

  defp network_hint(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, {10, _, _, _}} -> "from your local network (#{ip_string})"
      {:ok, {192, 168, _, _}} -> "from your local network (#{ip_string})"
      {:ok, {127, _, _, _}} -> "from your local network (#{ip_string})"
      {:ok, {172, b, _, _}} when b >= 16 and b <= 31 -> "from your local network (#{ip_string})"
      {:ok, {100, b, _, _}} when b >= 64 and b <= 127 -> "via Tailscale"
      {:ok, _} -> "from an external address (#{ip_string})"
      {:error, _} -> "from an unknown address"
    end
  end
end
