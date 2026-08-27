defmodule PlaysteadWeb.SetupLive do
  @moduledoc """
  `/setup` — the four-step first-run wizard (D-03, D-04): setup token →
  owner credentials → recovery codes (shown once) → readiness summary.

  The router's `PlaysteadWeb.Plugs.RequireSetupOpen` plug 404s the initial
  HTTP GET once an owner exists, so this LiveView only ever mounts while
  none does. Once mounted, the owner is created partway through (at the
  end of step 2), but the live socket itself is unaffected by the router
  plug — only a *fresh* GET to `/setup` after that point 404s.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Readiness
  alias Playstead.Setup

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Set up Playstead",
       step: 1,
       token: nil,
       token_error: nil,
       credentials_form:
         to_form(%{"email" => "", "password" => "", "password_confirmation" => ""}, as: "owner"),
       recovery_codes: [],
       readiness: :loading
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-[#0F172A] font-[Inter] py-12">
      <div class="w-full max-w-md rounded-lg bg-[#1E293B] p-8 shadow-xl">
        <h1 class="text-2xl font-semibold text-[#F1F5F9]">Set up Playstead</h1>

        <div :if={@step == 1} class="mt-6">
          {render_step_1(assigns)}
        </div>
        <div :if={@step == 2} class="mt-6">
          {render_step_2(assigns)}
        </div>
        <div :if={@step == 3} class="mt-6">
          {render_step_3(assigns)}
        </div>
        <div :if={@step == 4} class="mt-6">
          {render_step_4(assigns)}
        </div>
      </div>
    </div>
    """
  end

  # --- Step 1: setup token ---------------------------------------------

  defp render_step_1(assigns) do
    ~H"""
    <p class="text-sm text-[#94A3B8]">
      Find your setup token by running <code class="text-[#F1F5F9]">docker compose logs</code>
      and looking for the banner printed at boot. Paste it below.
    </p>

    <.form
      for={%{}}
      as={:setup}
      id="setup_token_form"
      phx-submit="verify_token"
      class="mt-4 space-y-3"
    >
      <div>
        <label for="setup_token" class="block text-sm font-semibold text-[#F1F5F9]">
          Setup token
        </label>
        <input
          type="text"
          name="setup[token]"
          id="setup_token"
          maxlength="128"
          autocomplete="off"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
          class="mt-1 block w-full truncate rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 font-['JetBrains_Mono'] text-[20px] tracking-[0.04em] text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
        />
        <p :if={@token_error} class="mt-2 text-sm text-red-400">{@token_error}</p>
      </div>

      <button
        type="submit"
        class="w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90"
      >
        Continue
      </button>
    </.form>
    """
  end

  # --- Step 2: owner credentials ----------------------------------------

  defp render_step_2(assigns) do
    ~H"""
    <p class="text-sm text-[#94A3B8]">Create your owner account.</p>

    <.form
      for={@credentials_form}
      as={:owner}
      id="owner_form"
      phx-submit="create_owner"
      class="mt-4 space-y-3"
    >
      <div>
        <label for="owner_email" class="block text-sm font-semibold text-[#F1F5F9]">Email</label>
        <input
          type="email"
          name="owner[email]"
          id="owner_email"
          value={@credentials_form[:email].value}
          autocomplete="username"
          spellcheck="false"
          required
          phx-mounted={JS.focus()}
          class="mt-1 block w-full rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 text-base text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
        />
        <p :for={msg <- @credentials_form[:email].errors || []} class="mt-1 text-sm text-red-400">
          {translate_form_error(msg)}
        </p>
      </div>

      <div>
        <label for="owner_password" class="block text-sm font-semibold text-[#F1F5F9]">
          Password
        </label>
        <input
          type="password"
          name="owner[password]"
          id="owner_password"
          autocomplete="new-password"
          spellcheck="false"
          required
          class="mt-1 block w-full rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 text-base text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
        />
        <p class="mt-1 text-sm text-[#94A3B8]">At least 12 characters.</p>
        <p :for={msg <- @credentials_form[:password].errors || []} class="mt-1 text-sm text-red-400">
          {translate_form_error(msg)}
        </p>
      </div>

      <div>
        <label for="owner_password_confirmation" class="block text-sm font-semibold text-[#F1F5F9]">
          Confirm password
        </label>
        <input
          type="password"
          name="owner[password_confirmation]"
          id="owner_password_confirmation"
          autocomplete="new-password"
          spellcheck="false"
          required
          class="mt-1 block w-full rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 text-base text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
        />
        <p
          :for={msg <- @credentials_form[:password_confirmation].errors || []}
          class="mt-1 text-sm text-red-400"
        >
          {translate_form_error(msg)}
        </p>
      </div>

      <button
        type="submit"
        class="w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90"
      >
        Continue
      </button>
    </.form>
    """
  end

  # --- Step 3: recovery codes (shown exactly once) -----------------------

  defp render_step_3(assigns) do
    ~H"""
    <p class="text-sm text-[#94A3B8]">
      Save these recovery codes somewhere safe. Each one works once, and they
      are never shown again after this screen.
    </p>

    <div class="mt-4 grid grid-cols-2 gap-2 rounded-md border border-[#334155] bg-[#0F172A] p-4">
      <.code_display :for={code <- @recovery_codes}>{code}</.code_display>
    </div>

    <button
      type="button"
      phx-click="continue_to_readiness"
      phx-mounted={JS.focus()}
      class="mt-4 w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90"
    >
      Continue
    </button>
    """
  end

  # --- Step 4: readiness summary + backup nudge ---------------------------

  defp render_step_4(assigns) do
    ~H"""
    <p class="text-sm text-[#94A3B8]">Here's how your server is doing.</p>

    <ul class="mt-4 space-y-2">
      <li :if={@readiness == :loading} class="text-sm text-[#94A3B8]">
        Checking…
      </li>
      <li
        :for={row <- (@readiness == :loading && []) || @readiness}
        class={[
          "rounded-md border px-3 py-2 text-sm",
          row.state == :ok && "border-[#4ADE80]/40 text-[#4ADE80]",
          row.state == :warning && "border-[#FBBF24]/40 text-[#FBBF24]"
        ]}
      >
        <span class="font-semibold">{readiness_label(row.id)}</span> — {row.message}
      </li>
    </ul>

    <p class="mt-4 text-sm text-[#94A3B8]">
      Your library lives in this server's storage. Set up a backup destination soon — a copy
      on the same disk is not a backup.
    </p>

    <button
      type="button"
      phx-click="finish_setup"
      class="mt-4 w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90"
    >
      Finish setup
    </button>
    """
  end

  defp readiness_label(:database), do: "Database"
  defp readiness_label(:volumes), do: "Storage volumes"
  defp readiness_label(:https), do: "HTTPS"

  defp translate_form_error({msg, opts}),
    do: PlaysteadWeb.CoreComponents.translate_error({msg, opts})

  @impl true
  def handle_event("verify_token", %{"setup" => %{"token" => token}}, socket) do
    case Setup.verify_token(token) do
      :ok ->
        {:noreply, assign(socket, step: 2, token: token, token_error: nil)}

      {:error, :invalid_or_expired} ->
        {:noreply, assign(socket, token_error: "This token is invalid or has already been used.")}
    end
  end

  def handle_event("create_owner", %{"owner" => attrs}, socket) do
    case Setup.claim(socket.assigns.token, attrs) do
      {:ok, %{recovery_codes: codes}} ->
        {:noreply, assign(socket, step: 3, recovery_codes: codes)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, credentials_form: to_form(changeset, as: "owner"))}

      {:error, :token_already_used} ->
        {:noreply,
         assign(socket,
           step: 1,
           token: nil,
           token_error: "This token was already used. Ask the host operator for a fresh one."
         )}

      {:error, :invalid_or_expired} ->
        {:noreply,
         assign(socket, step: 1, token: nil, token_error: "This token is invalid or has expired.")}
    end
  end

  def handle_event("continue_to_readiness", _params, socket) do
    send(self(), :run_readiness_checks)
    {:noreply, assign(socket, step: 4, readiness: :loading)}
  end

  def handle_event("finish_setup", _params, socket) do
    {:noreply, push_navigate(socket, to: ~p"/log-in")}
  end

  @impl true
  def handle_info(:run_readiness_checks, socket) do
    {:noreply, assign(socket, readiness: Readiness.summary())}
  end
end
