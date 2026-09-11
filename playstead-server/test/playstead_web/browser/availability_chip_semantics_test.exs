defmodule PlaysteadWeb.Browser.AvailabilityChipSemanticsTest do
  @moduledoc """
  "Every availability chip carries an accessible name and a pressed state
  not conveyed by color alone, reachable from the keyboard" (03-UAT.md
  checkpoint 46, plan 03-13 deliverable D4).

  03-13 left this as a human checkpoint because the chips postdate
  checkpoint 11's keyboard/screen-reader walkthrough — the six availability
  chips did not exist when that walkthrough was recorded, so nothing had
  ever driven them. `library_live_test.exs` proves the chips render
  `aria-label` and `aria-pressed` attributes; what it cannot see is whether
  Tab reaches them on the rendered page and whether the *pressed* state
  survives being stripped of color (WCAG 1.4.1, QUAL-01).

  The color-independence half is the part worth stating precisely. It is
  not enough that the pressed chip looks different — it must differ in
  something that is not a color channel. `.filter-chip[aria-pressed="true"]`
  buys that with `border-width: 2px` and `font-weight: 600`, and this suite
  reads both back from `getComputedStyle` on the real stylesheet so a
  refactor that collapses the rule to a color swap fails here.
  """
  use PlaysteadWeb.BrowserCase, async: false

  import Playstead.CatalogueFixtures

  alias Playstead.AvailabilityVocabulary

  @max_tabs 160

  defp chip_id(value), do: "filter-chip-availability-#{value}"
  defp chip_sel(value), do: "##{chip_id(value)}"

  defp dom_attr(session, selector, name) do
    js(
      session,
      "const el = document.querySelector(arguments[0]); " <>
        "return el ? el.getAttribute(arguments[1]) : null;",
      [selector, name]
    )
  end

  # The ids Tab actually stops on, walking from the top of the document
  # until focus returns somewhere already seen.
  defp tab_visited_ids(session) do
    js(session, "if (document.activeElement) document.activeElement.blur(); return true;")

    Enum.reduce_while(1..@max_tabs, {session, []}, fn _, {session, seen} ->
      session = send_keys(session, [:tab])

      id =
        js(
          session,
          "const el = document.activeElement; return el && el.id ? el.id : null;"
        )

      cond do
        is_nil(id) -> {:cont, {session, seen}}
        id in seen -> {:halt, {session, seen}}
        true -> {:cont, {session, [id | seen]}}
      end
    end)
    |> then(fn {_session, seen} -> Enum.reverse(seen) end)
  end

  setup do
    user = owner_fixture()

    # One asset set is enough to render `#library-browse`, which is what
    # gates the chip row. The chips themselves are always the full frozen
    # vocabulary, independent of what is in the library.
    asset_set_fixture(user.id, %{display_title: "Chip Fixture Game", system_id: "gba"})

    %{user: user}
  end

  defp open_library(session, user) do
    session
    |> log_in_via_cookie(user, token_authenticated_at: DateTime.utc_now(:second))
    |> visit_live("/library")
    |> assert_has(css(chip_sel("server_only")))
  end

  feature "every chip in the frozen vocabulary is reached by Tab", %{
    session: session,
    user: user
  } do
    session = open_library(session, user)

    visited = tab_visited_ids(session)

    refute visited == [],
           "Tab reached no identified control at all — this feature would pass vacuously"

    for value <- AvailabilityVocabulary.values() do
      assert chip_id(value) in visited,
             "Tab never reached the #{value} chip (visited: #{inspect(visited)})"
    end
  end

  feature "every chip's accessible name is its exact frozen sentence", %{
    session: session,
    user: user
  } do
    session = open_library(session, user)

    for value <- AvailabilityVocabulary.values() do
      expected = AvailabilityVocabulary.accessible_name(value)

      refute is_nil(expected),
             "#{value} has no accessible name in the vocabulary — fixture is wrong"

      assert dom_attr(session, chip_sel(value), "aria-label") == expected
    end
  end

  feature "pressing a chip moves aria-pressed to it and off every other chip", %{
    session: session,
    user: user
  } do
    session = open_library(session, user)

    for value <- AvailabilityVocabulary.values() do
      assert dom_attr(session, chip_sel(value), "aria-pressed") == "false"
    end

    session = click(session, css(chip_sel("downloading")))

    session =
      wait_until(
        session,
        fn s -> dom_attr(s, chip_sel("downloading"), "aria-pressed") == "true" end,
        "the downloading chip to report itself pressed"
      )

    for value <- AvailabilityVocabulary.values(), value != "downloading" do
      assert dom_attr(session, chip_sel(value), "aria-pressed") == "false",
             "#{value} stayed pressed while downloading was selected"
    end
  end

  feature "the pressed state is carried by something other than color", %{
    session: session,
    user: user
  } do
    session = open_library(session, user)

    unpressed_border = computed_style(session, chip_sel("queued"), "borderTopWidth")
    unpressed_weight = computed_style(session, chip_sel("queued"), "fontWeight")

    session = click(session, css(chip_sel("queued")))

    session =
      wait_until(
        session,
        fn s -> dom_attr(s, chip_sel("queued"), "aria-pressed") == "true" end,
        "the queued chip to report itself pressed"
      )

    pressed_border = computed_style(session, chip_sel("queued"), "borderTopWidth")
    pressed_weight = computed_style(session, chip_sel("queued"), "fontWeight")

    # Two independent non-color channels, each asserted on its own line so a
    # CI failure names which one regressed (the evidence pipeline keeps
    # file:line, not assertion messages).
    assert px(pressed_border) > px(unpressed_border),
           "pressed border width did not grow: #{unpressed_border} -> #{pressed_border}"

    assert String.to_integer(pressed_weight) > String.to_integer(unpressed_weight),
           "pressed font weight did not grow: #{unpressed_weight} -> #{pressed_weight}"

    # A sibling chip stays in the unpressed treatment, so the change above is
    # the pressed rule firing rather than a page-wide restyle.
    assert computed_style(session, chip_sel("server_only"), "borderTopWidth") == unpressed_border
    assert computed_style(session, chip_sel("server_only"), "fontWeight") == unpressed_weight
  end

  feature "a chip focused by Tab draws a real focus indicator", %{
    session: session,
    user: user
  } do
    session = open_library(session, user)

    true =
      js(
        session,
        "const el = document.querySelector(arguments[0]); el.focus(); return true;",
        [chip_sel("ready_offline")]
      )

    indicator =
      js(
        session,
        """
        const el = document.querySelector(arguments[0]);
        if (!el) return null;
        const s = getComputedStyle(el);
        return {
          focused: document.activeElement === el,
          matchesFocusVisible: el.matches(':focus-visible'),
          outlineWidth: s.outlineWidth,
          outlineStyle: s.outlineStyle,
          boxShadow: s.boxShadow
        };
        """,
        [chip_sel("ready_offline")]
      )

    assert indicator["focused"], "the chip did not take focus"

    ring? =
      (indicator["outlineStyle"] != "none" and px(indicator["outlineWidth"]) > 0) or
        (indicator["boxShadow"] not in [nil, "none"] and indicator["boxShadow"] != "")

    assert ring?,
           "the focused chip draws no outline or box-shadow ring: #{inspect(indicator)}"
  end
end
