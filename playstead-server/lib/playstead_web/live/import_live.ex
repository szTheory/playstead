defmodule PlaysteadWeb.ImportLive do
  @moduledoc """
  `/import` — the browser upload console surface (IMPT-01, D-01a,
  D-04). Follows `PlaysteadWeb.DevicesLive`'s idiom exactly: every
  event handler ends by reloading from `Playstead.Import` rather than
  patching assigns, and errors surface through a generic flash carrying
  a correlation identifier. This LiveView holds no protocol logic and
  no outcome classification — it calls the same context functions the
  API controller calls and renders what they return.

  Nothing durable lives in this process: a single-file copy runs
  inline in the request, and the underlying bytes are already
  committed to the blob store by the time `Playstead.Import.import_upload/3`
  ever runs (`Playstead.Import.HashingWriter` wrote and hashed them as
  they streamed in) — a navigation or reconnect loses at most an
  in-flight browser upload, never a committed import.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Import
  alias Playstead.Import.{HashingWriter, Preview}
  alias PlaysteadWeb.ImportLive.{PreviewPanel, ReceiptRow}
  alias PlaysteadWeb.Problem

  import PreviewPanel, only: [preview_panel: 1]
  import ReceiptRow, only: [receipt_row: 1]

  @impl true
  def mount(_params, _session, socket) do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes, 0)

    {:ok,
     socket
     |> assign(page_title: "Import", ceiling: ceiling, confirming: false)
     |> allow_upload(:file,
       accept: :any,
       max_entries: 1,
       max_file_size: ceiling,
       auto_upload: true,
       writer: fn _name, entry, _socket -> {HashingWriter, [size_hint: entry.client_size]} end,
       validator: &validate_entry/1
     )
     |> load_receipts()}
  end

  # Refuses a selection that cannot fit the free-space margin *before*
  # any chunk is ever sent — the validator runs at preflight, ahead of
  # the writer's `init/1` (D-10, RESEARCH Pitfall 3).
  defp validate_entry(entry) do
    preview = Preview.for_upload(entry.client_name, entry.client_size)

    if preview.fits_free_space? do
      :ok
    else
      {:error, :insufficient_space}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-3xl space-y-8">
        <div>
          <h1 class="text-display font-semibold text-[#F1F5F9]">Import</h1>
          <p class="mt-1 text-sm text-[#94A3B8]">
            Choose one file to copy into your library.
          </p>
        </div>

        <section id="upload-section" class="rounded-lg border border-[#334155] bg-[#1E293B] p-6">
          <form id="import-form" phx-change="validate" phx-submit="confirm">
            <label
              for={@uploads.file.ref}
              class="flex h-11 w-fit cursor-pointer items-center justify-center rounded-md border border-[#334155] bg-[#1E293B] px-4 text-base font-semibold text-[#F1F5F9] hover:border-[#94A3B8]"
            >
              Choose a file
            </label>
            <.live_file_input upload={@uploads.file} class="sr-only" />

            <div
              :for={err <- upload_errors(@uploads.file)}
              id="upload-error"
              class="mt-4 text-sm text-[#EF4444]"
            >
              {error_to_string(err, @ceiling)}
            </div>

            <div :for={entry <- @uploads.file.entries} class="mt-6">
              <div
                :for={err <- upload_errors(@uploads.file, entry)}
                id={"entry-error-#{entry.ref}"}
                class="text-sm text-[#EF4444]"
              >
                {error_to_string(err, @ceiling)}
              </div>

              <.preview_panel
                :if={upload_errors(@uploads.file, entry) == []}
                preview={Preview.for_upload(entry.client_name, entry.client_size)}
                entry={entry}
                confirming={@confirming}
              />
            </div>
          </form>
        </section>

        <section id="receipts">
          <h2 class="text-heading font-semibold text-[#F1F5F9]">Recent imports</h2>

          <div
            :if={@receipts == []}
            id="receipts-empty"
            class="mt-4 rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">Nothing imported yet</p>
          </div>

          <div :if={@receipts != []} id="receipt-list" class="mt-4 space-y-3">
            <.receipt_row :for={receipt <- @receipts} receipt={receipt} />
          </div>
        </section>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("validate", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("confirm", _params, socket) do
    user_id = socket.assigns.current_scope.user.id

    results =
      consume_uploaded_entries(socket, :file, fn writer_meta, entry ->
        {:ok, Import.import_upload(user_id, entry.client_name, writer_meta)}
      end)

    socket =
      case results do
        [{:ok, _receipt}] ->
          socket |> load_receipts()

        [{:error, _reason}] ->
          socket |> put_flash(:error, generic_error_flash())

        [] ->
          socket
      end

    {:noreply, socket}
  end

  defp load_receipts(socket) do
    user_id = socket.assigns.current_scope.user.id
    assign(socket, receipts: Import.list_receipts(user_id))
  end

  defp generic_error_flash do
    "Something went wrong on the server. Your original file is untouched — nothing was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end

  defp error_to_string(:too_large, ceiling) do
    "Files over #{humanize_gb(ceiling)}: copy them into your inbox folder instead."
  end

  defp error_to_string(:insufficient_space, _ceiling) do
    "Not enough free space on the server for this file. Free up space, or copy it into your inbox folder instead."
  end

  defp error_to_string(:too_many_files, _ceiling), do: "Choose one file at a time."
  defp error_to_string(_other, _ceiling), do: "This file could not be selected."

  defp humanize_gb(bytes) when is_integer(bytes) and bytes > 0 do
    "#{Float.round(bytes / 1_073_741_824, 0) |> trunc()} GB"
  end

  defp humanize_gb(_bytes), do: "the browser limit"
end
