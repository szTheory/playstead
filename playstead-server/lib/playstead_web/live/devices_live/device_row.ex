defmodule PlaysteadWeb.DevicesLive.DeviceRow do
  @moduledoc """
  A single paired device row, or a revoked tombstone (D-10, D-11).
  Single-device and many-device layouts share this exact component —
  there is no special-cased "first device" congratulatory UI (UI-SPEC E4
  zero-one-many). Never renders a credential value, only the fingerprint
  prefix `Playstead.Pairing.active_credential_fingerprint/1` computed.
  """

  use Phoenix.Component
  import PlaysteadWeb.CoreComponents

  alias Phoenix.LiveView.JS
  alias Playstead.Pairing
  alias Playstead.Pairing.Device

  attr :device, Device, required: true
  attr :acting, :any, default: nil
  attr :renaming_id, :any, default: nil
  attr :tombstone, :boolean, default: false

  def device_row(assigns) do
    assigns = assign(assigns, :fingerprint, fingerprint_for(assigns.device, assigns.tombstone))

    ~H"""
    <div
      id={"device-#{@device.id}"}
      class={["flex items-center justify-between gap-4 px-4 py-4", @tombstone && "opacity-60"]}
    >
      <div class="min-w-0">
        <form
          :if={@renaming_id == @device.id}
          id={"device-#{@device.id}-rename-form"}
          phx-submit="rename"
          class="flex items-center gap-2"
        >
          <input type="hidden" name="device_id" value={@device.id} />
          <input
            type="text"
            id={"device-#{@device.id}-rename-input"}
            name="name"
            value={@device.name || @device.claimed_name}
            maxlength={Device.max_name_length()}
            phx-mounted={JS.focus()}
            class="rounded-md border border-app-border bg-app-canvas px-2 py-1 text-base text-app-text focus:border-app-accent focus:outline-none"
          />
          <button
            type="submit"
            id={"device-#{@device.id}-rename-save"}
            phx-disable-with="Saving..."
            class="flex h-11 items-center rounded-md px-3 text-sm font-semibold text-app-accent hover:bg-app-border"
          >
            Save
          </button>
          <button
            type="button"
            id={"device-#{@device.id}-rename-cancel"}
            phx-click="cancel_rename"
            class="flex h-11 items-center rounded-md px-3 text-sm text-app-muted hover:bg-app-border"
          >
            Cancel
          </button>
        </form>

        <p :if={@renaming_id != @device.id} class="flex items-center gap-2">
          <span
            id={"device-#{@device.id}-name"}
            class="max-w-xs truncate text-base text-app-text"
            title={device_name(@device)}
            tabindex="0"
          >
            {device_name(@device)}
          </span>
          <button
            :if={!@tombstone}
            id={"device-#{@device.id}-rename"}
            type="button"
            phx-click="edit_name"
            phx-value-id={@device.id}
            aria-label={"Rename #{device_name(@device)}"}
            class="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-app-muted hover:bg-app-border phx-click-loading:opacity-60"
          >
            <.icon name="hero-pencil" class="size-5" />
          </button>
        </p>

        <p id={"device-#{@device.id}-claims"} class="mt-1 text-sm text-app-muted">
          {claim(@device.platform)} &middot; {claim(@device.app_version)}
        </p>
        <p id={"device-#{@device.id}-last-seen"} class="mt-1 text-sm text-app-muted">
          Paired {format_date(@device.paired_at)} &middot; Last seen {last_seen(@device.last_seen_at)}
        </p>
        <p
          :if={@fingerprint}
          id={"device-#{@device.id}-fingerprint"}
          data-role="fingerprint"
          class="mt-1 break-all font-mono text-label text-app-muted"
        >
          {@fingerprint}
        </p>
        <p :if={@tombstone} id={"device-#{@device.id}-revoked-at"} class="mt-1 text-sm text-app-muted">
          Revoked {format_date(@device.revoked_at)}
        </p>
      </div>

      <button
        :if={!@tombstone}
        id={"device-#{@device.id}-revoke"}
        type="button"
        phx-click="revoke"
        phx-value-id={@device.id}
        disabled={@acting == {@device.id, :revoke}}
        aria-label={"Revoke #{device_name(@device)}"}
        data-confirm={"Revoke #{device_name(@device)}? This device will lose access immediately. Its downloaded games and saves stay on it and remain playable offline — only syncing with this server stops."}
        class="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-app-danger hover:bg-app-border disabled:opacity-60 phx-click-loading:opacity-60"
      >
        <span :if={@acting == {@device.id, :revoke}} class="motion-safe:animate-spin">
          <.icon name="hero-arrow-path" class="size-5" />
        </span>
        <.icon :if={@acting != {@device.id, :revoke}} name="hero-x-mark" class="size-5" />
      </button>
    </div>
    """
  end

  defp device_name(%Device{name: name}) when is_binary(name) and name != "", do: name
  defp device_name(%Device{claimed_name: name}) when is_binary(name) and name != "", do: name
  defp device_name(_), do: "Not reported"

  defp claim(nil), do: "Not reported"
  defp claim(""), do: "Not reported"
  defp claim(value), do: value

  defp last_seen(nil), do: "Never"
  defp last_seen(dt), do: format_date(dt)

  defp format_date(nil), do: "—"
  defp format_date(dt), do: Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")

  defp fingerprint_for(_device, true), do: nil
  defp fingerprint_for(device, false), do: Pairing.active_credential_fingerprint(device.id)
end
