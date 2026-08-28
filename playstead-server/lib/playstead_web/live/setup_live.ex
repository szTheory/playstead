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

  alias Playstead.RateLimiter
  alias Playstead.Readiness
  alias Playstead.Setup

  # WR-01 (01-REVIEW.md): `verify_token` runs over the LiveView socket
  # with no HTTP-pipeline throttle, unlike every other credential-checking
  # endpoint in this app. Fixed per-connect-IP limit, defense-in-depth
  # only — the setup token is a 256-bit value so brute force isn't
  # practically feasible on its own.
  @verify_token_scale :timer.minutes(1)
  @verify_token_limit 20

  # WR-05 (01-REVIEW.md): `create_owner` is likewise reachable over the
  # socket with no throttle. Defense-in-depth only, same rationale.
  @create_owner_scale :timer.minutes(1)
  @create_owner_limit 20

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
       create_owner_error: nil,
       recovery_codes: [],
       readiness: :loading,
       connect_ip: connect_ip(socket)
     )}
  end

  defp connect_ip(socket) do
    case Phoenix.LiveView.get_connect_info(socket, :peer_data) do
      %{address: address} -> address |> :inet.ntoa() |> to_string()
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-[#0F172A] font-sans py-12">
      <div class="w-full max-w-md rounded-lg bg-[#1E293B] p-8 shadow-xl">
        <h1 class="text-display font-semibold text-[#F1F5F9]">Set up Playstead</h1>

        <div :if={@step == 1} id="setup-step-1" class="mt-6">
          {render_step_1(assigns)}
        </div>
        <div :if={@step == 2} id="setup-step-2" class="mt-6">
          {render_step_2(assigns)}
        </div>
        <div :if={@step == 3} id="setup-step-3" class="mt-6">
          {render_step_3(assigns)}
        </div>
        <div :if={@step == 4} id="setup-step-4" class="mt-6">
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
          class="mt-1 block w-full truncate rounded-md border border-[#334155] bg-[#0F172A] px-3 py-2 font-mono text-code text-[#F1F5F9] focus:border-[#38BDF8] focus:outline-none focus:ring-2 focus:ring-[#38BDF8]"
        />
        <p :if={@token_error} id="setup_token_error" class="mt-2 text-sm text-[#EF4444]">
          {@token_error}
        </p>
      </div>

      <button
        type="submit"
        id="setup_token_submit"
        phx-disable-with="Checking..."
        class="w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90 disabled:opacity-60"
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
    <p :if={@create_owner_error} id="owner_error" class="mt-2 text-sm text-[#EF4444]">
      {@create_owner_error}
    </p>

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
        <p :for={msg <- @credentials_form[:email].errors || []} class="mt-1 text-sm text-[#EF4444]">
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
        <p :for={msg <- @credentials_form[:password].errors || []} class="mt-1 text-sm text-[#EF4444]">
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
          class="mt-1 text-sm text-[#EF4444]"
        >
          {translate_form_error(msg)}
        </p>
      </div>

      <button
        type="submit"
        id="owner_submit"
        phx-disable-with="Creating..."
        class="w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90 disabled:opacity-60"
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

    <div
      id="recovery-codes"
      class="mt-4 grid grid-cols-2 gap-2 rounded-md border border-[#334155] bg-[#0F172A] p-4"
    >
      <.code_display
        :for={{code, index} <- Enum.with_index(@recovery_codes)}
        id={"recovery-code-#{index}"}
        class="min-w-0 truncate"
      >
        {code}
      </.code_display>
    </div>

    <button
      type="button"
      id="continue_to_readiness"
      phx-click="continue_to_readiness"
      phx-mounted={JS.focus()}
      class="mt-4 w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90 phx-click-loading:opacity-60"
    >
      Continue
    </button>
    """
  end

  # --- Step 4: readiness summary + backup nudge ---------------------------

  defp render_step_4(assigns) do
    ~H"""
    <p class="text-sm text-[#94A3B8]">Here's how your server is doing.</p>

    <ul id="readiness" class="mt-4 space-y-2">
      <li :if={@readiness == :loading} id="readiness-loading" class="text-sm text-[#94A3B8]">
        Checking…
      </li>
      <li
        :for={row <- (@readiness == :loading && []) || @readiness}
        id={"readiness-#{row.id}"}
        data-state={row.state}
        class={[
          "rounded-md border px-3 py-2 text-sm",
          row.state == :ok && "border-[#4ADE80]/40 text-[#4ADE80]",
          row.state == :warning && "border-[#FBBF24]/40 text-[#FBBF24]"
        ]}
      >
        <span class="font-semibold">{readiness_label(row.id)}</span> — {row.message}
      </li>
    </ul>

    <p id="backup-nudge" class="mt-4 text-sm text-[#94A3B8]">
      Your library lives in this server's storage. Set up a backup destination soon — a copy
      on the same disk is not a backup.
    </p>

    <button
      type="button"
      id="finish_setup"
      phx-click="finish_setup"
      class="mt-4 w-full rounded-md bg-[#38BDF8] px-4 py-2 text-base font-semibold text-[#0F172A] hover:opacity-90 phx-click-loading:opacity-60"
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
    case rate_limit_verify_token(socket) do
      {:allow, _} ->
        case Setup.verify_token(token) do
          :ok ->
            {:noreply, assign(socket, step: 2, token: token, token_error: nil)}

          {:error, :invalid_or_expired} ->
            {:noreply,
             assign(socket, token_error: "This token is invalid or has already been used.")}
        end

      {:deny, _} ->
        {:noreply,
         assign(socket, token_error: "Too many attempts. Please wait a moment and try again.")}
    end
  end

  def handle_event("create_owner", %{"owner" => attrs}, socket) do
    case rate_limit_create_owner(socket) do
      {:allow, _} ->
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
             assign(socket,
               step: 1,
               token: nil,
               token_error: "This token is invalid or has expired."
             )}
        end

      {:deny, _} ->
        {:noreply,
         assign(socket,
           create_owner_error: "Too many attempts. Please wait a moment and try again."
         )}
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

  defp rate_limit_verify_token(socket) do
    case socket.assigns[:connect_ip] do
      nil ->
        {:allow, 0}

      ip ->
        RateLimiter.hit("setup:verify_token:ip:#{ip}", @verify_token_scale, verify_token_limit())
    end
  end

  defp rate_limit_create_owner(socket) do
    case socket.assigns[:connect_ip] do
      nil ->
        {:allow, 0}

      ip ->
        RateLimiter.hit("setup:create_owner:ip:#{ip}", @create_owner_scale, create_owner_limit())
    end
  end

  defp create_owner_limit do
    Application.get_env(:playstead, __MODULE__, [])
    |> Keyword.get(:create_owner_limit, @create_owner_limit)
  end

  defp verify_token_limit do
    Application.get_env(:playstead, __MODULE__, [])
    |> Keyword.get(:verify_token_limit, @verify_token_limit)
  end
end
