defmodule PlaysteadWeb.AttentionLive do
  @moduledoc """
  `/attention` — the Needs Attention inbox (D-26, D-31). Follows the
  devices console idiom exactly: every event dispatches to
  `Playstead.Attention`/`Playstead.Attention.Resolutions` and then
  reloads from the context rather than patching assigns, and failures
  surface through the generic flash with a correlation identifier.

  The navigation count stays calm: neutral, shown only when at least
  one item is open, never a badge or a congratulation when the inbox
  is empty — the same restraint the library's quiet badge follows.
  """

  use PlaysteadWeb, :live_view

  alias Playstead.Attention
  alias Playstead.Attention.Resolutions
  alias PlaysteadWeb.AttentionLive.{BulkBar, EvidenceCard}
  alias PlaysteadWeb.Problem

  import BulkBar, only: [bulk_bar: 1]
  import EvidenceCard, only: [evidence_card: 1]

  # D-31: bulk actions are offered only for resolutions needing no
  # per-item input.
  @bulk_eligible_reasons ~w(quarantined archives_kept_unopened patch_file_detected
                            failed_after_retries unknown_system signature_mismatch
                            ambiguous_recognition confirm_system)

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Needs attention", selected: MapSet.new(), session_filter: nil)
     |> load_items()}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    filter = params["session"]
    {:noreply, socket |> assign(:session_filter, filter) |> load_items()}
  end

  defp load_items(socket) do
    scope = socket.assigns.current_scope

    opts =
      if socket.assigns[:session_filter],
        do: [import_session_id: socket.assigns.session_filter],
        else: []

    grouped = Attention.list_items(scope.user.id, opts)
    excluded = Attention.list_items(scope.user.id, Keyword.put(opts, :status, "excluded"))

    assign(socket,
      grouped: grouped,
      excluded: excluded,
      count: Attention.count(scope.user.id),
      excluded_storage_bytes: Attention.excluded_storage_bytes(scope.user.id),
      selected: MapSet.new()
    )
  end

  # --- selection ---------------------------------------------------------

  @impl true
  def handle_event("toggle-select", %{"id" => id}, socket) do
    selected =
      if MapSet.member?(socket.assigns.selected, id) do
        MapSet.delete(socket.assigns.selected, id)
      else
        MapSet.put(socket.assigns.selected, id)
      end

    {:noreply, assign(socket, :selected, selected)}
  end

  # --- per-item resolutions ------------------------------------------------

  def handle_event("retain-as-custom", %{"id" => id}, socket) do
    dispatch(socket, id, fn item, user_id -> Resolutions.retain_as_custom(item, user_id) end)
  end

  def handle_event("exclude", %{"id" => id}, socket) do
    dispatch(socket, id, fn item, user_id -> Resolutions.exclude(item, user_id) end)
  end

  def handle_event("retry", %{"id" => id}, socket) do
    dispatch(socket, id, fn item, user_id -> Resolutions.retry(item, user_id) end)
  end

  def handle_event("restore", %{"id" => id}, socket) do
    dispatch(socket, id, fn item, user_id -> Resolutions.undo(item, user_id) end)
  end

  def handle_event("correct-system", %{"id" => id, "system_id" => system_id}, socket) do
    dispatch(socket, id, fn item, user_id ->
      Resolutions.correct_system(item, user_id, system_id)
    end)
  end

  # --- bulk resolutions (D-31) --------------------------------------------

  def handle_event("bulk-exclude", _params, socket) do
    dispatch_bulk(socket, fn item, user_id -> Resolutions.exclude(item, user_id) end)
  end

  def handle_event("bulk-retain", _params, socket) do
    dispatch_bulk(socket, fn item, user_id -> Resolutions.retain_as_custom(item, user_id) end)
  end

  def handle_event("bulk-retry", _params, socket) do
    dispatch_bulk(socket, fn item, user_id -> Resolutions.retry(item, user_id) end)
  end

  def handle_event("bulk-assign-system", %{"system_id" => system_id}, socket) do
    dispatch_bulk(socket, fn item, user_id ->
      Resolutions.correct_system(item, user_id, system_id)
    end)
  end

  defp dispatch(socket, id, fun) do
    scope = socket.assigns.current_scope

    case Attention.get_owned_item(scope.user.id, id) do
      nil ->
        {:noreply, put_flash(socket, :error, generic_error_flash())}

      item ->
        case fun.(item, scope.user.id) do
          {:ok, _result} ->
            {:noreply, load_items(socket)}

          {:error, :already_resolved} ->
            {:noreply, load_items(socket)}

          {:error, _reason} ->
            {:noreply, socket |> load_items() |> put_flash(:error, generic_error_flash())}
        end
    end
  end

  defp dispatch_bulk(socket, fun) do
    scope = socket.assigns.current_scope
    ids = MapSet.to_list(socket.assigns.selected)

    Enum.each(ids, fn id ->
      case Attention.get_owned_item(scope.user.id, id) do
        nil -> :ok
        item -> fun.(item, scope.user.id)
      end
    end)

    {:noreply, socket |> load_items() |> assign(:selected, MapSet.new())}
  end

  defp generic_error_flash do
    "Something went wrong on the server. Your data is safe — nothing was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end

  defp bulk_eligible?(reason), do: reason in @bulk_eligible_reasons

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-4xl space-y-8">
        <div>
          <h1 class="text-display font-semibold text-[#F1F5F9]">Needs attention</h1>
          <p id="attention-count" aria-live="polite" class="mt-1 text-sm text-[#94A3B8]">
            <span :if={@count > 0}>{@count} item{if @count != 1, do: "s"} need a decision</span>
            <span :if={@count == 0}>Nothing needs your attention right now</span>
          </p>
        </div>

        <div
          :if={@count == 0}
          id="attention-empty"
          class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
        >
          <p class="text-base text-[#F1F5F9]">Nothing needs your attention</p>
          <p class="mt-1 text-sm text-[#94A3B8]">
            New content that doesn't need a decision stays quietly in your library.
          </p>
        </div>

        <.bulk_bar selected_count={MapSet.size(@selected)} />

        <section
          :for={{reason, items} <- Enum.sort_by(@grouped, fn {r, _} -> r end)}
          id={"group-#{reason}"}
          class="space-y-3"
        >
          <h2 class="text-heading font-semibold text-[#F1F5F9]">{group_title(reason)}</h2>

          <table id={"table-#{reason}"} class="w-full">
            <tbody>
              <tr :for={item <- items}>
                <td class="py-2">
                  <.evidence_card
                    item={item}
                    selectable={bulk_eligible?(reason)}
                    selected={MapSet.member?(@selected, item.id)}
                  />

                  <div class="mt-2 flex flex-wrap gap-2">
                    <button
                      :if={item.reason == "missing_member"}
                      type="button"
                      id={"attach-#{item.id}"}
                      phx-click="exclude"
                      phx-value-id={item.id}
                      class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                    >
                      Exclude
                    </button>

                    <button
                      :if={item.reason == "archives_kept_unopened"}
                      type="button"
                      id={"retain-#{item.id}"}
                      phx-click="retain-as-custom"
                      phx-value-id={item.id}
                      class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                    >
                      Retain as custom
                    </button>

                    <button
                      :if={item.reason == "archives_kept_unopened"}
                      type="button"
                      id={"exclude-#{item.id}"}
                      phx-click="exclude"
                      phx-value-id={item.id}
                      class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                    >
                      Exclude
                    </button>

                    <button
                      :if={item.reason == "quarantined"}
                      type="button"
                      id={"retry-#{item.id}"}
                      phx-click="retry"
                      phx-value-id={item.id}
                      class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                    >
                      Retry safe processing
                    </button>

                    <button
                      :if={item.reason in ["confirm_system", "signature_mismatch", "unknown_system"]}
                      type="button"
                      id={"correct-#{item.id}"}
                      phx-click="correct-system"
                      phx-value-id={item.id}
                      phx-value-system_id="unknown"
                      class="text-sm text-[#94A3B8] hover:text-[#F1F5F9]"
                    >
                      Correct system
                    </button>
                  </div>
                </td>
              </tr>
            </tbody>
          </table>
        </section>

        <section id="excluded-filter" class="border-t border-[#334155] pt-6">
          <p class="text-sm text-[#94A3B8]">
            <span id="excluded-storage">{@excluded_storage_bytes} bytes</span> held by excluded items.
          </p>

          <div :if={@excluded != %{}} id="excluded-items" class="mt-3 space-y-2">
            <div :for={{_reason, items} <- @excluded}>
              <div
                :for={item <- items}
                id={"excluded-#{item.id}"}
                class="flex items-center justify-between rounded border border-[#334155] p-3"
              >
                <span class="text-sm text-[#F1F5F9]">{item.reason}</span>
                <button
                  type="button"
                  id={"restore-#{item.id}"}
                  phx-click="restore"
                  phx-value-id={item.id}
                  class="text-sm font-semibold text-[#94A3B8] hover:text-[#F1F5F9]"
                >
                  Restore
                </button>
              </div>
            </div>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp group_title("missing_member"), do: "Some parts are missing"
  defp group_title("quarantined"), do: "Set aside for review"
  defp group_title("patch_file_detected"), do: "Patch files detected"
  defp group_title("failed_after_retries"), do: "Couldn't finish"
  defp group_title("ambiguous_recognition"), do: "More than one possible match"
  defp group_title("signature_mismatch"), do: "Name and contents disagree"
  defp group_title("unknown_system"), do: "Unknown system"
  defp group_title("confirm_system"), do: "Confirm system"
  defp group_title("archives_kept_unopened"), do: "Archives kept unopened"
  defp group_title(reason), do: reason
end
