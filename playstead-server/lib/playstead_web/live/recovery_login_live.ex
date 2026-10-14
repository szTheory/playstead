defmodule PlaysteadWeb.RecoveryLoginLive do
  @moduledoc """
  `/log-in/recovery` — D-05b's email-free recovery path: log in with one
  single-use recovery code instead of a password. Throttled on the same
  limits as password login (`PlaysteadWeb.Plugs.Throttle`, `:recovery`
  action).
  """

  use PlaysteadWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    error = Phoenix.Flash.get(socket.assigns.flash, :error)
    form = to_form(%{}, as: "recovery")

    {:ok,
     assign(socket,
       page_title: "Log in with a recovery code",
       form: form,
       trigger_submit: false,
       error: error
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-app-canvas font-sans">
      <div class="w-full max-w-md rounded-lg bg-app-surface p-8 shadow-xl">
        <h1 class="text-display font-semibold text-app-text">Log in with a recovery code</h1>
        <p class="mt-2 text-sm text-app-muted">
          Enter one of the ten single-use codes you saved at setup.
        </p>

        <.form
          :let={f}
          for={@form}
          id="recovery_login_form"
          action={~p"/log-in/recovery"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
          class="mt-6 space-y-4"
        >
          <div>
            <label for={f[:code].id} class="block text-sm font-semibold text-app-text">
              Recovery code
            </label>
            <input
              type="text"
              name={f[:code].name}
              id={f[:code].id}
              autocomplete="off"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
              class="mt-1 block w-full rounded-md border border-app-border bg-app-canvas px-3 py-2 text-base font-mono text-app-text focus:border-app-accent focus:outline-none focus:ring-2 focus:ring-app-accent"
            />
            <p :if={@error} id="recovery_error" data-role="error" class="mt-2 text-sm text-app-danger">
              {@error}
            </p>
          </div>

          <button
            type="submit"
            id="recovery_submit"
            phx-disable-with="Logging in..."
            class="w-full rounded-md bg-app-accent px-4 py-2 text-base font-semibold text-app-canvas hover:opacity-90 disabled:opacity-60"
          >
            Log in
          </button>
        </.form>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("submit", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
