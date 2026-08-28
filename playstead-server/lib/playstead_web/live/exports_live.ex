defmodule PlaysteadWeb.ExportsLive do
  @moduledoc """
  `/exports` — the durable jobs console for a write-then-verify export
  (D-33, D-38, D-40). Mirrors `PlaysteadWeb.ImportSessionsLive`'s idiom:
  every event handler reloads fresh from `Playstead.Export` rather than
  patching assigns.

  Vocabulary rule (D-40): an export is described here only as the
  user's games written out as ordinary files — never with either of
  the two reassuring words this product deliberately never applies to
  an export (see `priv/static/export-readme.txt` for the plain-language
  disclosure those two words would otherwise stand in for).
  """

  use PlaysteadWeb, :live_view

  alias Playstead.{Catalogue, Export}
  alias PlaysteadWeb.Problem

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(page_title: "Exports", readme_text: readme_text()) |> load()}
  end

  # Read from the same static asset `Playstead.Export.BagitWriter` writes
  # into every bag, rather than duplicating its wording here (D-40).
  defp readme_text do
    :playstead
    |> Application.app_dir("priv/static/export-readme.txt")
    |> File.read!()
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-8">
        <div>
          <h1 class="text-display font-semibold text-[#F1F5F9]">Exports</h1>
          <p class="mt-1 text-sm text-[#94A3B8]">
            Your games, written as ordinary files onto a disk you control.
          </p>
          <p id="export-readme-note" class="mt-2 text-sm text-[#94A3B8] whitespace-pre-line">
            {@readme_text}
          </p>
        </div>

        <section id="export-actions" class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
          <button
            id="export-library"
            type="button"
            phx-click="export_library"
            class="rounded-md border border-[#334155] px-4 py-2 text-sm font-semibold text-[#F1F5F9]"
          >
            Export whole library
          </button>
        </section>

        <section id="exports">
          <h2 class="text-heading font-semibold text-[#F1F5F9]">Export history</h2>

          <div
            :if={@exports == []}
            id="exports-empty"
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">No exports yet</p>
          </div>

          <div :if={@exports != []} id="export-list" class="mt-4 space-y-3">
            <div
              :for={export <- @exports}
              id={"export-#{export.id}"}
              class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
            >
              <p class="text-sm font-semibold text-[#F1F5F9]">{export.target_name}</p>
              <p class="text-sm text-[#94A3B8]">
                {export.set_count} set(s), {export.file_count} file(s)
              </p>
              <p id={"export-status-#{export.id}"} class="text-sm">
                {status_message(export)}
              </p>
              <button
                :if={export.status in ~w(verified verification_failed)}
                type="button"
                phx-click="verify_again"
                phx-value-id={export.id}
                class="mt-2 rounded-md border border-[#334155] px-3 py-1 text-sm font-semibold text-[#F1F5F9]"
              >
                Verify again
              </button>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("export_library", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    target_name = "library-#{System.unique_integer([:positive])}"

    socket =
      case Export.create_export(user_id, :library, target_name: target_name) do
        {:ok, _export} -> load(socket)
        {:error, _reason} -> put_flash(socket, :error, generic_error_flash())
      end

    {:noreply, socket}
  end

  @impl true
  def handle_event("verify_again", %{"id" => id}, socket) do
    user_id = socket.assigns.current_scope.user.id

    socket =
      case Export.verify_again(user_id, id) do
        {:ok, _export} -> load(socket)
        {:error, _reason} -> put_flash(socket, :error, generic_error_flash())
      end

    {:noreply, socket}
  end

  defp load(socket) do
    user_id = socket.assigns.current_scope.user.id

    assign(socket,
      exports: Export.list_exports(user_id),
      assets: Catalogue.list_assets(socket.assigns.current_scope)
    )
  end

  # D-40: a clean verification and a mismatch each get exact,
  # never-a-backup, never-"safe" wording.
  defp status_message(%{status: "writing"}), do: "Writing your games as files…"
  defp status_message(%{status: "verifying"}), do: "Re-reading every file to check it…"

  defp status_message(%{status: "verified"}) do
    "Every file was re-read and matches exactly what was written."
  end

  defp status_message(%{status: "verification_failed", mismatched_files: files}) do
    "#{length(files)} file(s) did not match on re-read: #{Enum.join(files, ", ")}"
  end

  defp generic_error_flash do
    "Something went wrong on the server. Nothing already written was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end
end
