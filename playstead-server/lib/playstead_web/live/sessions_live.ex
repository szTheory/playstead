defmodule PlaysteadWeb.SessionsLive do
  @moduledoc """
  `/settings/sessions` — the Sessions half of D-06's "revocable
  credentials" mental model: a list of the owner's browser sessions with
  per-session revocation, gated behind a fresh sudo confirmation
  (`PlaysteadWeb.Plugs.SudoMode`).
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Accounts

  @impl true
  def mount(_params, session, socket) do
    current_token = session["user_token"]
    sessions = Accounts.list_sessions(socket.assigns.current_scope)

    {:ok,
     assign(socket,
       page_title: "Sessions",
       sessions: sessions,
       current_token: current_token,
       revoking_id: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-app-canvas px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-2xl">
        <h1 class="text-display font-semibold text-app-text">Sessions</h1>
        <p class="mt-2 text-sm text-app-muted">
          Every device currently signed in. Revoking a session ends it immediately — the
          other sessions are unaffected.
        </p>

        <div
          id="sessions"
          class="mt-6 rounded-lg border border-app-border bg-app-surface divide-y divide-border"
        >
          <div
            :for={session <- @sessions}
            id={"session-#{session.id}"}
            data-current={to_string(session.token == @current_token)}
            class="flex items-center justify-between gap-4 px-4 py-4"
          >
            <div class="min-w-0">
              <p
                id={"session-#{session.id}-label"}
                class="max-w-xs truncate text-base text-app-text"
                title={session.client_label || "Browser session"}
                tabindex="0"
              >
                {session.client_label || "Browser session"}
                <span
                  :if={session.token == @current_token}
                  id={"session-#{session.id}-current"}
                  class="ml-2 text-label font-semibold text-app-accent"
                >
                  (this device)
                </span>
              </p>
              <p id={"session-#{session.id}-signed-in"} class="mt-1 text-sm text-app-muted">
                Signed in {Calendar.strftime(session.inserted_at, "%Y-%m-%d %H:%M UTC")}
              </p>
            </div>

            <button
              :if={session.token != @current_token}
              id={"session-#{session.id}-revoke"}
              type="button"
              phx-click="revoke"
              phx-value-id={session.id}
              disabled={@revoking_id == session.id}
              aria-label={"Revoke #{session.client_label || "Browser session"}"}
              class="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-app-danger hover:bg-app-border disabled:opacity-60 phx-click-loading:opacity-60"
            >
              <span :if={@revoking_id == session.id} class="motion-safe:animate-spin">
                <.icon name="hero-arrow-path" class="size-5" />
              </span>
              <.icon :if={@revoking_id != session.id} name="hero-x-mark" class="size-5" />
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("revoke", %{"id" => id}, socket) do
    id = String.to_integer(id)
    socket = assign(socket, :revoking_id, id)

    case Accounts.revoke_session(socket.assigns.current_scope, id) do
      :ok ->
        sessions = Enum.reject(socket.assigns.sessions, &(&1.id == id))
        {:noreply, assign(socket, sessions: sessions, revoking_id: nil)}

      {:error, :not_found} ->
        {:noreply,
         socket
         |> assign(:revoking_id, nil)
         |> put_flash(
           :error,
           "Something went wrong on the server. Your data is safe — nothing was changed."
         )}
    end
  end
end
