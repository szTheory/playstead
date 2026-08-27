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
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-[Inter]">
      <div class="mx-auto max-w-2xl">
        <h1 class="text-2xl font-semibold text-[#F1F5F9]">Sessions</h1>
        <p class="mt-2 text-sm text-[#94A3B8]">
          Every device currently signed in. Revoking a session ends it immediately — the
          other sessions are unaffected.
        </p>

        <div class="mt-6 rounded-lg border border-[#334155] bg-[#1E293B] divide-y divide-[#334155]">
          <div
            :for={session <- @sessions}
            id={"session-#{session.id}"}
            class="flex items-center justify-between gap-4 px-4 py-4"
          >
            <div class="min-w-0">
              <p
                class="max-w-xs truncate text-base text-[#F1F5F9]"
                title={session.client_label || "Browser session"}
                tabindex="0"
              >
                {session.client_label || "Browser session"}
                <span
                  :if={session.token == @current_token}
                  class="ml-2 text-xs font-semibold text-[#38BDF8]"
                >
                  (this device)
                </span>
              </p>
              <p class="mt-1 text-sm text-[#94A3B8]">
                Signed in {Calendar.strftime(session.inserted_at, "%Y-%m-%d %H:%M UTC")}
              </p>
            </div>

            <button
              :if={session.token != @current_token}
              type="button"
              phx-click="revoke"
              phx-value-id={session.id}
              disabled={@revoking_id == session.id}
              aria-label={"Revoke #{session.client_label || "Browser session"}"}
              class="flex h-11 w-11 shrink-0 items-center justify-center rounded-md text-[#EF4444] hover:bg-[#334155] disabled:opacity-60"
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
