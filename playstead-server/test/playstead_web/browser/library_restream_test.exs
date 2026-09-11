defmodule PlaysteadWeb.Browser.LibraryRestreamTest do
  @moduledoc """
  "A 500-entry library toggle re-streams the browse list without a skeleton
  or an intermediate empty frame" (03-UAT.md checkpoint 47, plan 03-13
  deliverable D5, deferred there as a backstop truth with no 500-entry
  stress fixture).

  Every filter change calls `stream_filtered_assets(socket, reset: true)`.
  A stream reset tells the client to clear the container and refill it, so
  the risk this checkpoint names is real and structural: if the clear and
  the refill land in two different paints, a user sees the whole library
  blink empty. Nothing about that is visible to `Phoenix.LiveViewTest`,
  which only ever sees the settled HTML.

  So this measures painted frames. It samples `childElementCount` on every
  `requestAnimationFrame` across the toggle: a painted empty frame shows up
  as a sample of zero, and a skeleton or indeterminate busy treatment shows
  up as a nonzero `skeleton` count. Each feature asserts the sampler
  actually ran (`samples != []`) so a rAF that never fires fails loudly
  instead of passing vacuously.
  """
  use PlaysteadWeb.BrowserCase, async: false

  import Playstead.CatalogueFixtures
  import Playstead.PairingFixtures

  alias Playstead.Accounts.Scope
  alias Playstead.Availability

  # D-16's stated figure. Large enough that a reset-and-refill blink would
  # be plainly visible to a person, and that any per-row loading treatment
  # would have somewhere to appear.
  @library_size 500
  @ready_offline_size 50

  @stream "#library-asset-stream"

  # Anything that would read as a second, indeterminate loading treatment
  # inside the browse list: a skeleton, a pulse/spin animation, or an
  # explicit busy state.
  @busy_selector "#library-asset-stream .skeleton, " <>
                   "#library-asset-stream .animate-pulse, " <>
                   "#library-asset-stream .animate-spin, " <>
                   "#library-asset-stream [aria-busy=\"true\"]"

  @start_sampler """
  window.__psSamples = [];
  window.__psStop = false;
  const step = () => {
    const el = document.querySelector(arguments[0]);
    window.__psSamples.push({
      n: el ? el.childElementCount : -1,
      busy: document.querySelectorAll(arguments[1]).length
    });
    if (!window.__psStop) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
  return true;
  """

  # `js/3` returns the script's value, not the session — the sampler is
  # started for its effect, so hand the session back for the pipeline.
  defp start_sampler(session) do
    true = js(session, @start_sampler, [@stream, @busy_selector])
    session
  end

  defp read_samples(session) do
    js(session, "window.__psStop = true; return window.__psSamples || [];")
  end

  defp stream_count(session) do
    js(
      session,
      "const el = document.querySelector(arguments[0]); return el ? el.childElementCount : -1;",
      [@stream]
    )
  end

  defp await_count(session, expected) do
    wait_until(
      session,
      fn s -> stream_count(s) == expected end,
      "the browse stream to settle at #{expected} rows"
    )
  end

  setup do
    user = owner_fixture()
    scope = Scope.for_user(user)
    %{device: device} = device_fixture(scope)

    sets =
      for i <- 1..@library_size do
        asset_set_fixture(user.id, %{
          display_title: "Stress Game #{String.pad_leading(to_string(i), 3, "0")}",
          system_id: "gba"
        })
      end

    Availability.replace_for_device(
      device,
      sets
      |> Enum.take(@ready_offline_size)
      |> Enum.map(&%{"asset_set_id" => &1.id, "verified" => true})
    )

    %{user: user}
  end

  feature "narrowing a 500-entry library never paints an empty list or a skeleton",
          %{session: session, user: user} do
    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live("/library")
      |> await_count(@library_size)

    session = start_sampler(session)

    session =
      session
      |> click(css("#filter-chip-availability-ready_offline"))
      |> await_count(@ready_offline_size)

    samples = read_samples(session)

    refute samples == [],
           "the requestAnimationFrame sampler never ran — this feature would pass vacuously"

    counts = Enum.map(samples, & &1["n"])

    assert Enum.min(counts) > 0,
           "the browse list painted an empty frame during the re-stream " <>
             "(frame-by-frame row counts: #{inspect(Enum.take(counts, 40))})"

    assert Enum.all?(samples, &(&1["busy"] == 0)),
           "a skeleton or indeterminate loading treatment was painted during the re-stream"

    # Non-vacuity in the other direction: the sampler really did span a
    # transition, not just a run of identical settled frames.
    assert Enum.max(counts) == @library_size
    assert Enum.min(counts) == @ready_offline_size
  end

  feature "widening back to the full library is equally seamless",
          %{session: session, user: user} do
    session =
      session
      |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
      |> visit_live("/library")
      |> await_count(@library_size)
      |> click(css("#filter-chip-availability-ready_offline"))
      |> await_count(@ready_offline_size)

    session = start_sampler(session)

    # Pressing the pressed chip clears the filter (`filter-availability`
    # toggles), so this is the widening half of the same control.
    session =
      session
      |> click(css("#filter-chip-availability-ready_offline"))
      |> await_count(@library_size)

    samples = read_samples(session)

    refute samples == [],
           "the requestAnimationFrame sampler never ran — this feature would pass vacuously"

    counts = Enum.map(samples, & &1["n"])

    assert Enum.min(counts) > 0,
           "the browse list painted an empty frame while widening " <>
             "(frame-by-frame row counts: #{inspect(Enum.take(counts, 40))})"

    assert Enum.all?(samples, &(&1["busy"] == 0)),
           "a skeleton or indeterminate loading treatment was painted while widening"

    assert Enum.max(counts) == @library_size
    assert Enum.min(counts) == @ready_offline_size
  end
end
