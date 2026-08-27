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
    <div class="min-h-screen flex items-center justify-center bg-[#0F172A] font-[Inter]">
      <div class="w-full max-w-md rounded-lg bg-[#1E293B] p-8 shadow-xl">
        <h1 class="text-2xl font-semibold text-[#F1F5F9]">Log in</h1>

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
            <label for={f[:email].id} class="block text-sm font-semibold text-[#F1F5F9]">
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
              class="mt-1 block w-full rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 text-base text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
            />
          </div>

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
            <p class="mt-2 text-sm text-[#94A3B8]">
              No email will ever be sent — this server never sends mail.
            </p>
            <p :if={@error} class="mt-2 text-sm text-red-400">
              {@error}
            </p>
          </div>

          <button
            type="submit"
            phx-disable-with="Logging in..."
            class="w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90 disabled:opacity-60"
          >
            Log in
          </button>
        </.form>

        <p class="mt-4 text-center text-sm text-[#94A3B8]">
          <%!-- Plain <a>, not ~p/navigate: plan 01-03 creates this route. Using
          a verified route here would fail `mix compile --warnings-as-errors`
          until that route exists. --%>
          <a href="/docs/recovery" class="underline hover:text-[#F1F5F9]">
            Locked out?
          </a>
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
