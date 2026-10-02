defmodule PlaysteadWeb.OperationsLive do
  @moduledoc "Authenticated owner-only operations evidence; public liveness stays minimal."

  use PlaysteadWeb, :live_view

  alias Playstead.Operations

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Operations") |> load_snapshot()}
  end

  @impl true
  def handle_event("refresh", _params, socket), do: {:noreply, load_snapshot(socket)}

  defp load_snapshot(socket), do: assign(socket, :components, Operations.snapshot())

  @impl true
  def render(assigns) do
    ~H"""
    <div id="operations" class="min-h-screen bg-app-canvas px-8 py-12 font-sans">
      <div class="mx-auto max-w-4xl space-y-6">
        <div class="flex items-center justify-between gap-4">
          <div>
            <h1 class="text-display font-semibold text-app-text">Operations</h1>
            <p class="mt-1 text-sm text-app-muted">Quiet evidence for recovery and continuity.</p>
          </div>
          <button
            id="refresh-operations"
            type="button"
            phx-click="refresh"
            class="rounded border border-system-accent-unknown px-3 py-2 text-sm text-app-text"
          >Refresh</button>
        </div>
        <section
          :for={component <- @components}
          id={"operations-#{component.id}"}
          class="rounded-lg border border-app-border bg-app-surface p-5"
        >
          <div class="flex items-start justify-between gap-4">
            <div>
              <h2 class="text-heading font-semibold text-app-text">{title(component.id)}</h2>
              <p :if={component.state == :healthy} class="mt-1 text-sm text-app-muted">Healthy</p>
              <p :if={component.state != :healthy} class="mt-1 text-sm text-app-text">
                {component.code}
              </p>
              <p :if={component.state != :healthy} class="mt-1 text-sm text-app-muted">
                {component.remedy}
              </p>
            </div>
            <time class="text-sm text-app-muted">{DateTime.to_iso8601(component.evidence_at)}</time>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp title(:database), do: "Database"
  defp title(:blobs), do: "Blob store"
  defp title(:queue), do: "Durable queue"
  defp title(:migrations), do: "Migrations"
  defp title(:capacity), do: "Capacity"
  defp title(:backup), do: "Backup freshness"
end
