defmodule PlaysteadWeb.LibraryLive.Shelves do
  @moduledoc """
  The five curation shelves (D-11/D-15): a horizontal, keyboard-scrollable
  row of `PlaysteadWeb.LibraryLive.GameCard` tiles with a heading and a
  count. A shelf with zero items is not rendered here — its sidebar
  entry with a one-line explainer carries that state instead, so the
  caller decides whether to render `shelf/1` at all.
  """

  use Phoenix.Component
  import PlaysteadWeb.LibraryLive.GameCard, only: [game_card: 1]

  attr :id, :string, required: true
  attr :heading, :string, required: true
  attr :items, :list, required: true
  attr :navigate_fun, :any, required: true, doc: "fun(asset_set_id) -> path"
  attr :status_fun, :any, default: nil, doc: "fun(asset_set) -> status map"

  def shelf(assigns) do
    status_fun = assigns.status_fun || (&default_status_fun/1)
    assigns = assign(assigns, :status_fun, status_fun)

    ~H"""
    <section id={@id} class="library-shelf" aria-label={@heading}>
      <div class="library-shelf-heading flex items-baseline justify-between">
        <h2 class="text-heading font-semibold text-[#F1F5F9]">{@heading}</h2>
        <span class="text-label text-[#94A3B8]">{length(@items)}</span>
      </div>
      <div class="library-shelf-track" role="list" tabindex="0">
        <div :for={entry <- @items} role="listitem" class="library-shelf-item">
          <.game_card
            asset_set={entry.asset_set}
            identification_state={entry.identification_state}
            navigate={@navigate_fun.(entry.asset_set.id)}
            status={@status_fun.(entry.asset_set)}
          />
        </div>
      </div>
    </section>
    """
  end

  defp default_status_fun(_asset_set), do: %{}

  attr :heading, :string, required: true
  attr :body, :string, required: true
  attr :id, :string, required: true

  def shelf_empty_explainer(assigns) do
    ~H"""
    <p id={@id} class="library-shelf-explainer text-label text-[#94A3B8]">
      <span class="font-semibold text-[#F1F5F9]">{@heading}</span> — {@body}
    </p>
    """
  end
end
