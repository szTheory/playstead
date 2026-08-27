defmodule PlaysteadWeb.SetupLive do
  @moduledoc """
  `/setup` — the first-run console shell (D-03, D-04).

  This plan renders only the minimal single-step shell: the dark
  console surface from UI-SPEC. Plan 01-02 fills this shell with the
  real wizard step sequence (setup token → owner credentials →
  recovery codes → readiness summary). The architecture here — a
  LiveView mounting its own step state, not a static page — is real;
  only the step content is a stub.
  """

  use PlaysteadWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Set up Playstead")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen flex items-center justify-center bg-[#0F172A] font-[Inter]">
      <div class="w-full max-w-md rounded-lg bg-[#1E293B] p-8 shadow-xl">
        <h1 class="text-2xl font-semibold text-[#F1F5F9]">Set up Playstead</h1>
        <p class="mt-2 text-sm text-[#F1F5F9]/70">
          Welcome. This wizard will help you claim this server and create your owner account.
        </p>
      </div>
    </div>
    """
  end
end
