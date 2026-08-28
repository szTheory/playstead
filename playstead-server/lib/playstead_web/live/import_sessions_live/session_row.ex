defmodule PlaysteadWeb.ImportSessionsLive.SessionRow do
  @moduledoc """
  Renders one `Playstead.Import.Session`'s state, counts by outcome,
  bounded progress, and the control actions valid for its current
  state (D-06, D-07, D-09). The cancel confirmation names the count of
  copies already made and states plainly that they are kept — the one
  control action whose effect a user is most likely to mispredict.
  """

  use Phoenix.Component

  alias Playstead.Import.{Progress, Session}

  attr :session, Session, required: true
  attr :acting, :any, default: nil

  def session_row(assigns) do
    progress = Progress.summary(assigns.session)
    assigns = assign(assigns, :progress, progress)

    ~H"""
    <div
      id={"session-#{@session.id}"}
      data-state={@session.state}
      class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
    >
      <div class="flex items-center justify-between">
        <p id={"session-#{@session.id}-state"} class="text-base font-semibold text-[#F1F5F9]">
          {String.capitalize(@session.state)}
        </p>
        <p id={"session-#{@session.id}-caption"} class="text-sm text-[#94A3B8]">
          {@progress.files_completed} / {@progress.file_count} files
        </p>
      </div>

      <div class="mt-2 h-2 w-full overflow-hidden rounded-full bg-[#334155]">
        <div
          id={"session-#{@session.id}-bar"}
          class="h-2 rounded-full bg-[#94A3B8]"
          style={"width: #{bar_percent(@progress)}%"}
        >
        </div>
      </div>

      <p
        :if={@progress.eta_minutes}
        id={"session-#{@session.id}-eta"}
        class="mt-1 text-sm text-[#94A3B8]"
      >
        About {@progress.eta_minutes} {if @progress.eta_minutes == 1, do: "minute", else: "minutes"} left
      </p>

      <p
        :for={{outcome, count} <- @session.counts_by_outcome || %{}}
        id={"session-#{@session.id}-outcome-#{outcome}"}
        class="mt-1 text-sm text-[#94A3B8]"
      >
        {count} {outcome}
      </p>

      <div class="mt-3 flex gap-2">
        <button
          :if={@session.state in ["staged", "paused"]}
          id={"session-#{@session.id}-start"}
          type="button"
          phx-click="start"
          phx-value-id={@session.id}
          class="rounded-md border border-[#334155] px-3 py-2 text-sm font-semibold text-[#F1F5F9]"
        >
          {if @session.state == "paused", do: "Resume", else: "Start"}
        </button>

        <button
          :if={@session.state == "running"}
          id={"session-#{@session.id}-pause"}
          type="button"
          phx-click="pause"
          phx-value-id={@session.id}
          class="rounded-md border border-[#334155] px-3 py-2 text-sm font-semibold text-[#F1F5F9]"
        >
          Pause
        </button>

        <button
          :if={has_failed_rows?(@session)}
          id={"session-#{@session.id}-retry"}
          type="button"
          phx-click="retry"
          phx-value-id={@session.id}
          class="rounded-md border border-[#334155] px-3 py-2 text-sm font-semibold text-[#F1F5F9]"
        >
          Retry failed
        </button>

        <button
          :if={@session.state in ["staged", "running", "paused"]}
          id={"session-#{@session.id}-cancel"}
          type="button"
          phx-click="cancel"
          phx-value-id={@session.id}
          data-confirm={cancel_confirmation(@progress)}
          class="rounded-md border border-[#334155] px-3 py-2 text-sm font-semibold text-[#F1F5F9]"
        >
          Cancel
        </button>
      </div>
    </div>
    """
  end

  defp bar_percent(%{total_bytes: total}) when total <= 0, do: 100

  defp bar_percent(%{bytes_completed: completed, total_bytes: total}) do
    min(100, trunc(completed / total * 100))
  end

  defp has_failed_rows?(%Session{counts_by_outcome: counts}) do
    is_map(counts) and Map.get(counts, "failed_safely", 0) > 0
  end

  # D-07: the confirmation must state exactly that copies already made
  # are kept — the effect a user is most likely to mispredict.
  defp cancel_confirmation(%{files_completed: 0}) do
    "Cancel this import? Nothing has been copied yet, so nothing is kept or lost."
  end

  defp cancel_confirmation(%{files_completed: count}) do
    "Cancel this import? The #{count} file#{if count == 1, do: "", else: "s"} already copied " <>
      "will be kept — only the rest will be skipped."
  end
end
