defmodule PlaysteadWeb.SudoLive do
  @moduledoc """
  `/sudo` — the re-authentication gate for dangerous actions (D-06). A
  clean single password field; no prior form state is carried in. Submits
  to the existing `POST /log-in` (`PlaysteadWeb.UserSessionController`),
  which recognizes an already-authenticated re-confirmation of the same
  user and records a `sudo_confirmed` audit entry instead of a plain
  login, then returns the owner to the pending action via
  `user[return_to]`.
  """

  use PlaysteadWeb, :live_view

  @impl true
  def mount(params, _session, socket) do
    error = Phoenix.Flash.get(socket.assigns.flash, :error)
    return_to = params["return_to"]
    form = to_form(%{"email" => socket.assigns.current_scope.user.email}, as: "user")

    {:ok,
     assign(socket,
       page_title: "Confirm it's you",
       form: form,
       trigger_submit: false,
       error: error,
       return_to: return_to
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-app-canvas font-sans">
      <div class="w-full max-w-md rounded-lg bg-app-surface p-8 shadow-xl">
        <h1 class="text-display font-semibold text-app-text">
          Confirm it's you — enter your password to continue.
        </h1>

        <.form
          :let={f}
          for={@form}
          id="sudo_form"
          action={~p"/log-in"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
          class="mt-6 space-y-4"
        >
          <input type="hidden" name={f[:email].name} value={f[:email].value} />
          <input :if={@return_to} type="hidden" name="user[return_to]" value={@return_to} />

          <div>
            <label for={f[:password].id} class="block text-sm font-semibold text-app-text">
              Password
            </label>
            <input
              type="password"
              name={f[:password].name}
              id={f[:password].id}
              autocomplete="current-password"
              spellcheck="false"
              required
              phx-mounted={JS.focus()}
              class="mt-1 block w-full rounded-md border border-app-border bg-app-canvas px-3 py-2 text-base text-app-text focus:border-app-accent focus:outline-none focus:ring-2 focus:ring-app-accent"
            />
            <p :if={@error} id="sudo_error" data-role="error" class="mt-2 text-sm text-app-danger">
              {@error}
            </p>
          </div>

          <button
            type="submit"
            id="sudo_submit"
            phx-disable-with="Confirming..."
            class="w-full rounded-md bg-app-accent px-4 py-2 text-base font-semibold text-app-canvas hover:opacity-90 disabled:opacity-60"
          >
            Confirm
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
