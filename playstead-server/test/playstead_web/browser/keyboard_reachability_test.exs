defmodule PlaysteadWeb.Browser.KeyboardReachabilityTest do
  @moduledoc """
  "The whole console is reachable by keyboard, and every focusable control
  has an accessible name and a visible focus indicator" (03-UAT.md
  checkpoint 11, QUAL-01 / WCAG 2.1.1 + 2.4.7), made objective.

  `library_live_test.exs` already proves the *markup* contract at the
  LiveView level — `aria-pressed` on chips, accessible names combining
  title/system/status. What nothing covered was sequential focus
  navigation on the rendered page: whether pressing Tab actually reaches
  every control, in a browser, with the real stylesheet applied. A control
  that renders a perfect `aria-label` but sits behind `tabindex="-1"`, or
  inside an `aria-hidden` subtree, passes every existing test and is
  unreachable by a keyboard user.

  These features drive real Tab keypresses through chromedriver rather
  than computing a focusable set in JS, because "focusable" and "in the
  sequential focus order" are not the same predicate — only the browser
  knows the difference.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  # The Phase 3 curation/library surface checkpoint 11 is about.
  @screens [:library, :library_detail, :library_collections, :library_collection_detail]

  # Tab budget: enough to cycle the largest screen plus slack for the
  # browser's own document stop. Walking stops early once focus returns to
  # an already-visited control.
  @max_tabs 120

  @stamp_js """
  const focusable = Array.from(document.querySelectorAll(
    'a[href], button, input, select, textarea, [tabindex]'
  )).filter(el => {
    if (el.disabled) return false;
    if (el.getClientRects().length === 0) return false;
    if (el.closest('[aria-hidden="true"], [inert]')) return false;
    return true;
  });

  focusable.forEach((el, i) => el.setAttribute('data-kbd-id', String(i)));

  const accessibleName = (el) => {
    const aria = el.getAttribute('aria-label');
    if (aria && aria.trim()) return aria.trim();

    const labelledby = el.getAttribute('aria-labelledby');
    if (labelledby) {
      const text = labelledby.split(/\\s+/)
        .map(id => (document.getElementById(id) || {}).innerText || '')
        .join(' ').trim();
      if (text) return text;
    }

    if (el.labels && el.labels.length) {
      const text = Array.from(el.labels).map(l => l.innerText || '').join(' ').trim();
      if (text) return text;
    }

    const own = (el.innerText || el.value || el.getAttribute('title') ||
                 el.getAttribute('alt') || '').trim();
    return own;
  };

  return focusable.map((el, i) => ({
    id: String(i),
    tag: el.tagName.toLowerCase(),
    selector: el.id ? ('#' + el.id) : (el.tagName.toLowerCase() + '[' + i + ']'),
    tabindex: el.getAttribute('tabindex'),
    name: accessibleName(el)
  }));
  """

  defp stamp_focusables(session), do: js(session, @stamp_js)

  defp active_kbd_id(session) do
    js(
      session,
      "const el = document.activeElement; " <>
        "return el ? el.getAttribute('data-kbd-id') : null;"
    )
  end

  # Walk Tab from the top of the document, returning the ordered list of
  # stamped ids the browser actually stopped on.
  defp walk_tab_order(session) do
    js(session, "if (document.activeElement) document.activeElement.blur(); return true;")

    Enum.reduce_while(1..@max_tabs, {session, []}, fn _, {session, visited} ->
      session = send_keys(session, [:tab])

      case active_kbd_id(session) do
        nil ->
          {:cont, {session, visited}}

        id ->
          if id in visited do
            {:halt, {session, visited}}
          else
            {:cont, {session, [id | visited]}}
          end
      end
    end)
    |> then(fn {_session, visited} -> Enum.reverse(visited) end)
  end

  for screen <- @screens do
    @screen screen

    feature "#{@screen}: every control is reachable by Tab", %{session: session} do
      {session, _} = BrowserScreens.open(session, @screen)

      focusables = stamp_focusables(session)

      refute focusables == [],
             "#{@screen}: no focusable controls found — this test would pass vacuously"

      visited = walk_tab_order(session)

      unreachable =
        focusables
        |> Enum.reject(&(&1["id"] in visited))
        |> Enum.map(& &1["selector"])

      assert unreachable == [],
             "#{@screen}: these controls render but Tab never reaches them: " <>
               "#{inspect(unreachable)}. A keyboard-only user cannot operate them."
    end

    feature "#{@screen}: every focusable control has a non-empty accessible name", %{
      session: session
    } do
      {session, _} = BrowserScreens.open(session, @screen)

      focusables = stamp_focusables(session)

      refute focusables == [],
             "#{@screen}: no focusable controls found — this test would pass vacuously"

      unnamed =
        focusables
        |> Enum.reject(&(&1["name"] != ""))
        |> Enum.map(& &1["selector"])

      assert unnamed == [],
             "#{@screen}: these focusable controls announce nothing to a screen reader: " <>
               "#{inspect(unnamed)}"
    end

    feature "#{@screen}: no control is removed from the focus order with tabindex=-1", %{
      session: session
    } do
      {session, _} = BrowserScreens.open(session, @screen)

      focusables = stamp_focusables(session)

      refute focusables == [],
             "#{@screen}: no focusable controls found — this test would pass vacuously"

      removed =
        focusables
        |> Enum.filter(&(&1["tabindex"] == "-1"))
        |> Enum.map(& &1["selector"])

      assert removed == [],
             "#{@screen}: these interactive controls carry tabindex=\"-1\", which takes them " <>
               "out of sequential focus navigation: #{inspect(removed)}"
    end

    feature "#{@screen}: keyboard focus is visibly indicated, not color-only", %{session: session} do
      {session, _} = BrowserScreens.open(session, @screen)

      focusables = stamp_focusables(session)

      refute focusables == [],
             "#{@screen}: no focusable controls found — this test would pass vacuously"

      js(session, "if (document.activeElement) document.activeElement.blur(); return true;")
      session = send_keys(session, [:tab])

      indicator =
        js(session, """
        const el = document.activeElement;
        if (!el || !el.getAttribute('data-kbd-id')) return null;
        const s = getComputedStyle(el);
        return {
          outlineWidth: s.outlineWidth,
          outlineStyle: s.outlineStyle,
          boxShadow: s.boxShadow,
          matchesFocusVisible: el.matches(':focus-visible')
        };
        """)

      assert indicator, "#{@screen}: Tab did not land on a stamped control"

      assert indicator["matchesFocusVisible"],
             "#{@screen}: the Tab-focused control does not match :focus-visible, so no " <>
               "focus-visible styling can ever apply to it"

      visible_ring? =
        (indicator["outlineStyle"] != "none" and indicator["outlineWidth"] != "0px") or
          indicator["boxShadow"] not in [nil, "none"]

      assert visible_ring?,
             "#{@screen}: the Tab-focused control draws no focus ring " <>
               "(outline #{indicator["outlineStyle"]} #{indicator["outlineWidth"]}, " <>
               "box-shadow #{inspect(indicator["boxShadow"])}). WCAG 2.4.7 requires a " <>
               "visible focus indicator."
    end
  end
end
