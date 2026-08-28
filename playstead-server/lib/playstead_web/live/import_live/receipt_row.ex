defmodule PlaysteadWeb.ImportLive.ReceiptRow do
  @moduledoc """
  Renders one `Playstead.Import.Receipt` by its outcome **code** (D-25,
  D-32) — never by an English string a caller might have typed. The
  microcopy table below is the decision record's own table, verbatim;
  adding a tenth outcome code anywhere else in the codebase without
  adding a row here is a compile-time-invisible but test-visible gap
  (`copy_contract_test.exs` asserts every code against this table).
  """

  use Phoenix.Component
  import PlaysteadWeb.CoreComponents

  alias Playstead.Import.Receipt

  @microcopy %{
    "new_asset" => {"Added to your library", "A verified copy is now stored by your server."},
    "exact_duplicate" =>
      {"Already in your library",
       "These exact bytes were imported before. We kept the new file name as a note."},
    "alias" =>
      {"Another copy of a game you have", "Same bytes, different name. Both names are kept."},
    "variant" =>
      {"A different version of a game you have", "Kept alongside the version you already had."},
    "incomplete_set" =>
      {"Some parts are missing", "This game needs more than one file. We kept what you gave us."},
    "unrecognized" =>
      {"Not yet identified", "Stored safely. Playstead couldn't match it to a reference yet."},
    "patched" => {"Looks modified", "Doesn't match the reference exactly. Kept as-is."},
    "quarantined" => {"Set aside for review", "We stored it but didn't process it."},
    "failed_safely" =>
      {"Couldn't finish — nothing was changed",
       "Your original file is untouched. You can try again."}
  }

  attr :receipt, Receipt, required: true

  def receipt_row(assigns) do
    assigns = assign(assigns, :copy, Map.get(@microcopy, assigns.receipt.outcome))

    ~H"""
    <div
      id={"receipt-#{@receipt.id}"}
      data-outcome={@receipt.outcome}
      class="rounded-lg border border-[#334155] bg-[#1E293B] p-4"
    >
      <p id={"receipt-#{@receipt.id}-label"} class="text-base font-semibold text-[#F1F5F9]">
        {elem(@copy, 0)}
      </p>
      <p id={"receipt-#{@receipt.id}-explanation"} class="mt-1 text-sm text-[#94A3B8]">
        {elem(@copy, 1)}
        <span :if={@receipt.reason}>{@receipt.reason}</span>
      </p>
      <p
        :if={@receipt.source_file}
        id={"receipt-#{@receipt.id}-filename"}
        class="mt-2 text-sm text-[#94A3B8]"
      >
        {@receipt.source_file.original_name}
      </p>
      <.icon
        :if={@receipt.outcome == "unrecognized"}
        name="hero-question-mark-circle"
        class="mt-2 size-4 text-[#94A3B8]"
      />
    </div>
    """
  end
end
