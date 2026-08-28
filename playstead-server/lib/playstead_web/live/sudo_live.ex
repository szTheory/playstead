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
    <div class="min-h-screen flex items-center justify-center bg-[#0F172A] font-sans">
      <div class="w-full max-w-md rounded-lg bg-[#1E293B] p-8 shadow-xl">
        <h1 class="text-display font-semibold text-[#F1F5F9]">
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
          <input type="hidden" name="user[return_to]" value={@return_to} />

          <div>
            <label for={f[:password].id} class="block text-sm font-semibold text-[#F1F5F9]">
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
              class="mt-1 block w-full rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 text-base text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
            />
            <p :if={@error} id="sudo_error" class="mt-2 text-sm text-[#EF4444]">
              {@error}
            </p>
          </div>

          <button
            type="submit"
            id="sudo_submit"
            phx-disable-with="Confirming..."
            class="w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90 disabled:opacity-60"
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
