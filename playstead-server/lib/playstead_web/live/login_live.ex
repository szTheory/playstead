defmodule PlaysteadWeb.LoginLive do
  @moduledoc """
  `/log-in` — password-only console login (D-02).

  There is exactly one field an owner fills in besides their password: the
  email used at setup. Per the UI-SPEC Copywriting Contract, the password
  field carries the explicit "no email will ever be sent" reassurance and a
  "Locked out?" link to the documented, email-free recovery path plan
  01-03 completes.
  """

  use PlaysteadWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    email = Phoenix.Flash.get(socket.assigns.flash, :email)
    error = Phoenix.Flash.get(socket.assigns.flash, :error)
    form = to_form(%{"email" => email}, as: "user")

    {:ok,
     assign(socket,
       page_title: "Log in",
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
        <h1 class="text-display font-semibold text-app-text">Log in</h1>

        <.form
          :let={f}
          for={@form}
          id="login_form"
          action={~p"/log-in"}
          phx-submit="submit"
          phx-trigger-action={@trigger_submit}
          class="mt-6 space-y-4"
        >
          <div>
            <label for={f[:email].id} class="block text-sm font-semibold text-app-text">
              Email
            </label>
            <input
              type="email"
              name={f[:email].name}
              id={f[:email].id}
              value={f[:email].value}
              autocomplete="username"
              spellcheck="false"
              required
              class="mt-1 block w-full rounded-md border border-app-border bg-app-canvas px-3 py-2 text-base text-app-text focus:border-app-accent focus:outline-none focus:ring-2 focus:ring-app-accent"
            />
          </div>

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
            <p id="no-mail-helper" class="mt-2 text-sm text-app-muted">
              No email will ever be sent — this server never sends mail.
            </p>
            <p :if={@error} id="login_error" data-role="error" class="mt-2 text-sm text-app-danger">
              {@error}
            </p>
          </div>

          <button
            type="submit"
            id="login_submit"
            phx-disable-with="Logging in..."
            class="w-full rounded-md bg-app-accent px-4 py-2 text-base font-semibold text-app-canvas hover:opacity-90 disabled:opacity-60"
          >
            Log in
          </button>
        </.form>

        <p class="mt-4 text-center text-sm text-app-muted">
          <.link id="locked-out-link" href={~p"/docs/recovery"} class="underline hover:text-app-text">
            Locked out?
          </.link>
        </p>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("submit", _params, socket) do
    {:noreply, assign(socket, :trigger_submit, true)}
  end
end
