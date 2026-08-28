defmodule PlaysteadWeb.ImportSessionsLive do
  @moduledoc """
  `/import/sessions` — the durable jobs console for a staged
  folder-level import (D-01, D-05, D-06, D-07, D-09). Staging happens
  only on this explicit action; there is no watcher and no automatic
  scan. Every event handler reloads fresh from `Playstead.Import`
  rather than patching assigns, following `PlaysteadWeb.DevicesLive`'s
  idiom.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Import
  alias Playstead.Import.Staging
  alias PlaysteadWeb.ImportSessionsLive.SessionRow
  alias PlaysteadWeb.Problem

  import SessionRow, only: [session_row: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Import sessions", preview: nil, staging: false)
     |> load_sessions()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-8">
        <div>
          <h1 class="text-display font-semibold text-[#F1F5F9]">Import sessions</h1>
          <p class="mt-1 text-sm text-[#94A3B8]">
            Stage the inbox folder to see exactly what will be imported before it starts.
          </p>
        </div>

        <section id="stage-section" class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
          <button
            id="preview-inbox"
            type="button"
            phx-click="preview"
            class="rounded-md border border-[#334155] px-4 py-2 text-sm font-semibold text-[#F1F5F9]"
          >
            Preview inbox folder
          </button>

          <div :if={@preview} id="inbox-preview" class="mt-4 space-y-1 text-sm text-[#94A3B8]">
            <p id="preview-file-count">{@preview.file_count} files, {@preview.total_bytes} bytes</p>
            <p id="preview-histogram">
              {@preview.histogram.recognized} recognized, {@preview.histogram.unknown} unknown, {@preview.histogram.archive} archives
            </p>
            <p :if={@preview.over_limit_files != []} id="preview-over-limit" class="text-[#FBBF24]">
              {length(@preview.over_limit_files)} file(s) exceed the per-file size limit.
            </p>
            <p :if={!@preview.fits_free_space?} id="preview-space-warning" class="text-[#EF4444]">
              Not enough free space for this folder.
            </p>

            <button
              id="stage-inbox"
              type="button"
              phx-click="stage"
              disabled={@staging}
              class="mt-3 rounded-md border border-[#334155] px-4 py-2 text-sm font-semibold text-[#F1F5F9]"
            >
              Stage this folder
            </button>
          </div>
        </section>

        <section id="sessions">
          <h2 class="text-heading font-semibold text-[#F1F5F9]">Sessions</h2>

          <div
            :if={@sessions == []}
            id="sessions-empty"
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">No sessions yet</p>
          </div>

          <div :if={@sessions != []} id="session-list" class="mt-4 space-y-3">
            <.session_row :for={session <- @sessions} session={session} />
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("preview", _params, socket) do
    root = Application.get_env(:playstead, :inbox_path)
    {:noreply, assign(socket, :preview, Staging.preview(root))}
  end

  @impl true
  def handle_event("stage", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    root = Application.get_env(:playstead, :inbox_path)
    session_id = Ecto.UUID.generate()

    socket =
      case Staging.stage(user_id, root, session_id) do
        {:ok, _session} ->
          {:ok, _} = Import.start_session(user_id, session_id)
          socket |> assign(preview: nil) |> load_sessions()

        {:error, :import_session_too_large} ->
          put_flash(socket, :error, "This folder has more files than one session can hold.")

        {:error, _reason} ->
          put_flash(socket, :error, generic_error_flash())
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("start", %{"id" => id}, socket) do
    with_owned_session(socket, id, fn user_id -> Import.start_session(user_id, id) end)
  end

  @impl true
  def handle_event("pause", %{"id" => id}, socket) do
    with_owned_session(socket, id, fn user_id -> Import.pause_session(user_id, id) end)
  end

  @impl true
  def handle_event("retry", %{"id" => id}, socket) do
    with_owned_session(socket, id, fn user_id -> Import.retry_failed(user_id, id) end)
  end

  @impl true
  def handle_event("cancel", %{"id" => id}, socket) do
    with_owned_session(socket, id, fn user_id -> Import.cancel_session(user_id, id) end)
  end

  defp with_owned_session(socket, _id, action_fun) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      case action_fun.(user_id) do
        {:ok, _result} -> load_sessions(socket)
        {:error, _reason} -> put_flash(socket, :error, generic_error_flash())
      end

    {:noreply, socket}
  end

  defp load_sessions(socket) do
    user_id = socket.assigns.current_scope.user.id
    assign(socket, sessions: Import.list_sessions(user_id))
  end

  defp generic_error_flash do
    "Something went wrong on the server. Nothing already copied was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end
end
