defmodule PlaysteadWeb.SavesLive do
  @moduledoc """
  `/saves` and `/saves/:id` — the console's saves surface (D-53, D-67):
  the third of three entry points to the comparison sheet, alongside
  the Mac's attention inbox and game detail. Follows `AttentionLive`'s
  idiom exactly: every event dispatches to `Playstead.Saves` and then
  reloads fresh from the context rather than patching assigns.

  D-67: the console has no emulator and therefore no playhead —
  `current` here means only "the version a future sync will hand to
  every Mac", and this LiveView never renders a global "this is what's
  being played" claim. Every mutating action here is a peer of the
  same `Saves.resolve_divergence/4` / `Saves.acknowledge_divergence/3`
  functions the Mac client calls, so the two clients cannot diverge in
  behaviour (D-52, D-48).
  """

  use PlaysteadWeb, :live_view

  import Ecto.Query, warn: false

  alias Playstead.{Blobs, Export, Repo, Saves}
  alias Playstead.Catalogue.AssetMember
  alias Playstead.Pairing.Device
  alias Playstead.Saves.Save
  alias PlaysteadWeb.Problem
  alias PlaysteadWeb.SavesLive.ComparisonPanel

  import ComparisonPanel, only: [comparison_panel: 1]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Saves", result_message: nil)}
  end

  @impl true
  def handle_params(%{"id" => save_line_id}, _uri, socket) do
    {:noreply,
     socket
     |> assign(save_line_id: save_line_id, result_message: nil)
     |> load_line()}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply,
     socket
     |> assign(save_line_id: nil, line: nil, heads: [], sides: [])
     |> load_save_lines()}
  end

  # D-67 follow-up (G-04-1): this lists EVERY save line the user has, not
  # only the diverged ones. `/saves` is the shelf a player browses; it is
  # not a work queue. `needs_divergence_decision?` rides along as a
  # per-row flag so the decision framing appears on exactly the rows that
  # have a decision, and nowhere else.
  #
  # Filtering by it here -- the original shape -- made "inspect" and
  # "export" unreachable for anyone whose saves were healthy, which is
  # the overwhelmingly common case, since divergence is by design the
  # exception. It also duplicated `/attention`, which already unions the
  # saves attention source and links each card to `/saves/:id`.
  defp load_save_lines(socket) do
    user_id = socket.assigns.current_scope.user.id

    lines =
      from(l in Save, where: l.user_id == ^user_id, order_by: [asc: l.inserted_at])
      |> Repo.all()
      |> Enum.map(fn line ->
        %{
          id: line.id,
          title: line_title(user_id, line.content_key),
          needs_decision?: Saves.needs_divergence_decision?(user_id, line.id)
        }
      end)

    assign(socket, save_lines: lines)
  end

  # The player thinks in game names, not content keys. Fall back to a
  # plain phrase rather than leaking a sha256 into the shelf.
  defp line_title(user_id, content_key) do
    query =
      from(m in AssetMember,
        join: b in assoc(m, :blob),
        join: s in assoc(m, :asset_set),
        where: s.user_id == ^user_id and b.sha256 == ^content_key,
        select: s.display_title,
        limit: 1
      )

    case Repo.one(query) do
      nil -> "Untitled game"
      "" -> "Untitled game"
      title -> title
    end
  end

  defp load_line(socket) do
    user_id = socket.assigns.current_scope.user.id
    save_line_id = socket.assigns.save_line_id

    case Saves.get_history(user_id, save_line_id) do
      {:ok, %{line: line, heads: heads}} ->
        sides = Enum.map(heads, &build_side(user_id, heads, &1))
        current_id = current_head_id(heads)

        socket
        |> assign(
          line: line,
          heads: heads,
          sides: Enum.map(sides, &Map.put(&1, :chosen?, &1.id == current_id))
        )
        |> assign(save_lines: [])

      {:error, :not_found} ->
        socket
        |> put_flash(:error, generic_error_flash())
        |> assign(line: nil, heads: [], sides: [], save_lines: [])
    end
  end

  # D-49/D-52: whichever head is itself the most recent resolution
  # revision (`capture_method: "resolution"`) is the one the sheet
  # marks "Currently continuing from this one" — every other head,
  # chosen or not, stays a live, permanently choosable side. Nothing
  # here deletes or moves a head; this only decides which existing
  # head's line reads as current for display.
  defp current_head_id(heads) do
    heads
    |> Enum.filter(&(&1.capture_method == "resolution"))
    |> Enum.max_by(& &1.recorded_at, DateTime, fn -> nil end)
    |> case do
      nil -> nil
      revision -> revision.id
    end
  end

  defp build_side(user_id, heads, head) do
    device = head.origin_device_id && Repo.get(Device, head.origin_device_id)

    %{
      id: head.id,
      origin: origin_name(device),
      last_saved: last_saved_text(head.recorded_at),
      since_split_count: since_split_count(user_id, heads, head),
      downloaded?: Blobs.exists?(head.blob_sha256),
      clock_caveat?: clock_caveat?(head),
      digest: head.blob_sha256
    }
  end

  defp origin_name(nil), do: "Unknown Mac"
  defp origin_name(%Device{name: name}) when is_binary(name) and name != "", do: name
  defp origin_name(%Device{claimed_name: name}) when is_binary(name) and name != "", do: name
  defp origin_name(%Device{}), do: "Unnamed Mac"

  # Locked copy (shared/save-vocabulary.json, D-67), transcribed
  # verbatim as literal Elixir strings -- never read from that JSON
  # fixture at runtime, which is a test resource only.
  defp last_saved_text(recorded_at) do
    diff = DateTime.diff(DateTime.utc_now(), recorded_at, :second)

    if diff > 7 * 24 * 3600 do
      "Last saved on #{Calendar.strftime(recorded_at, "%B %-d, %Y")}"
    else
      "Last saved #{relative_time(diff)}"
    end
  end

  defp relative_time(diff) when diff < 60, do: "just now"
  defp relative_time(diff) when diff < 3600, do: "#{div(diff, 60)} minute(s) ago"
  defp relative_time(diff) when diff < 86_400, do: "#{div(diff, 3600)} hour(s) ago"
  defp relative_time(diff), do: "#{div(diff, 86_400)} day(s) ago"

  # D-15: `device_clock_offset_ms` separates clock error from queue
  # delay -- a large offset means the device's own reported time
  # cannot be trusted to line up with when this version actually
  # arrived, exactly what `compare.clock_caveat` warns about.
  @clock_caveat_threshold_ms 5 * 60 * 1000
  defp clock_caveat?(%{device_clock_offset_ms: ms}) when is_integer(ms),
    do: abs(ms) > @clock_caveat_threshold_ms

  defp clock_caveat?(_head), do: false

  # D-50: "saves since the split" is the count of revisions on this
  # side's own ancestor chain since the deepest ancestor shared with
  # every other current head -- never a merge, never a diff, just a
  # count. When no shared ancestor exists at all (independent roots),
  # the whole chain is "since the split".
  defp since_split_count(user_id, heads, head) do
    chains = Enum.map(heads, &{&1.id, ancestor_chain(user_id, &1)})
    {_id, this_chain} = Enum.find(chains, &(elem(&1, 0) == head.id))
    other_chains = for {id, chain} <- chains, id != head.id, do: chain

    case common_ancestor([this_chain | other_chains]) do
      nil -> max(length(this_chain), 1)
      common -> max(length(Enum.take_while(this_chain, &(&1 != common))), 1)
    end
  end

  defp ancestor_chain(user_id, revision) do
    Stream.unfold(revision, fn
      nil -> nil
      %{parent_revision_id: nil} = r -> {r.id, nil}
      %{parent_revision_id: parent_id} = r -> {r.id, Saves.get_revision(user_id, parent_id)}
    end)
    |> Enum.to_list()
  end

  defp common_ancestor([first | rest]) when rest != [] do
    Enum.find(first, fn id -> Enum.all?(rest, &(id in &1)) end)
  end

  defp common_ancestor(_chains), do: nil

  # --- events --------------------------------------------------------

  @impl true
  def handle_event("choose", %{"head_id" => head_id}, socket) do
    user_id = socket.assigns.current_scope.user.id
    save_line_id = socket.assigns.save_line_id

    case Saves.resolve_divergence(user_id, console_device(), save_line_id, head_id) do
      {:ok, _revision} ->
        origin = origin_for_head(socket, head_id)

        {:noreply,
         socket
         |> load_line()
         |> assign(
           :result_message,
           "Continuing from #{origin}. Your Macs will use this version the next time they connect."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  @impl true
  def handle_event("keep-both", _params, socket) do
    user_id = socket.assigns.current_scope.user.id
    save_line_id = socket.assigns.save_line_id

    case Saves.acknowledge_divergence(user_id, console_device(), save_line_id) do
      {:ok, _result} ->
        {:noreply,
         socket
         |> load_line()
         |> assign(
           :result_message,
           "Keeping both. Each Mac keeps playing the version it already has."
         )}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, generic_error_flash())}
    end
  end

  @impl true
  def handle_event("export-version", %{"head_id" => head_id}, socket) do
    scope = socket.assigns.current_scope
    line = socket.assigns.line

    socket =
      case export_version(scope.user.id, line, head_id) do
        {:ok, _export} -> put_flash(socket, :info, "Export started — see Exports for status.")
        {:error, _reason} -> put_flash(socket, :error, generic_error_flash())
      end

    {:noreply, load_line(socket)}
  end

  # The console has no device credential of its own -- every field
  # `Saves.resolve_divergence/4`/`acknowledge_divergence/3` reads off
  # `device` is nullable on `Revision` (`origin_device_id`), so an
  # `id: nil` stand-in commits exactly the same shape the Mac client's
  # own resolution/acknowledgment calls produce, just with no origin
  # device to attribute it to.
  defp console_device, do: %{id: nil}

  defp origin_for_head(socket, head_id) do
    case Enum.find(socket.assigns.sides, &(&1.id == head_id)) do
      nil -> "that version"
      side -> side.origin
    end
  end

  # D-62: "Export this version…" is a deep link into the exact same
  # server-side export machinery `Playstead.Export.create_export/3`
  # already runs for the console's own export button -- narrowed to
  # this save line's game (its asset set), never a second export path.
  defp export_version(user_id, line, _head_id) do
    with {:ok, asset_set_id} <- find_asset_set_id(user_id, line.content_key) do
      target_name = "save-export-#{System.unique_integer([:positive])}"

      Export.create_export(user_id, :set,
        asset_set_id: asset_set_id,
        target_name: target_name,
        saves_scope: "all"
      )
    end
  end

  defp find_asset_set_id(user_id, content_key) do
    query =
      from(m in AssetMember,
        join: b in assoc(m, :blob),
        join: s in assoc(m, :asset_set),
        where: s.user_id == ^user_id and b.sha256 == ^content_key,
        select: s.id,
        limit: 1
      )

    case Repo.one(query) do
      nil -> {:error, :not_found}
      asset_set_id -> {:ok, asset_set_id}
    end
  end

  defp generic_error_flash do
    "Something went wrong on the server. Nothing was changed. " <>
      "Correlation ID: #{Problem.generate_correlation_id()}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-[#0F172A] px-8 py-12 font-sans">
      <Layouts.flash_group flash={@flash} />
      <div class="mx-auto max-w-4xl space-y-8">
        <div>
          <h1 class="text-display font-semibold text-[#F1F5F9]">Saves</h1>
          <p class="mt-1 text-sm text-[#94A3B8]">
            Every game you have a save for. Open one to look through its versions or export it.
          </p>
        </div>

        <div :if={is_nil(@save_line_id)}>
          <div
            :if={@save_lines == []}
            id="saves-empty"
            class="rounded-lg border border-[#334155] bg-[#1E293B] p-6"
          >
            <p class="text-base text-[#F1F5F9]">No saves yet.</p>
            <p class="mt-1 text-sm text-[#94A3B8]">
              Play a game through Playstead and its saves will show up here.
            </p>
          </div>

          <ul :if={@save_lines != []} id="save-lines" class="space-y-3">
            <li :for={line <- @save_lines} id={"line-#{line.id}"}>
              <.link
                href={"/saves/#{line.id}"}
                class="flex items-center justify-between gap-4 rounded-lg border border-[#334155] bg-[#1E293B] p-4 text-[#F1F5F9] hover:border-[#38BDF8]"
              >
                <span>{line.title}</span>
                <span
                  :if={line.needs_decision?}
                  id={"needs-decision-#{line.id}"}
                  class="shrink-0 text-sm text-[#94A3B8]"
                >
                  Two versions to compare
                </span>
              </.link>
            </li>
          </ul>
        </div>

        <.comparison_panel
          :if={@save_line_id && @line}
          sides={@sides}
          result_message={@result_message}
        />
      </div>
    </div>
    """
  end
end
