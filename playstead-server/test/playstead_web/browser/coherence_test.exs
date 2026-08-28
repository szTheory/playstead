defmodule PlaysteadWeb.Browser.CoherenceTest do
  @moduledoc """
  "The whole console reads as one coherent dark-console design" (UAT #8),
  made objective: every screen shares the canvas background, the nav, a
  single 28px/600 heading, keyboard focus on its primary field, 44px
  icon-only targets with accessible names, and no horizontal scroll on a
  desktop or a phone-width viewport. The screen registry itself is checked
  against the router so nothing can opt out.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  @desktop {1280, 800}
  @phone {390, 844}

  for screen <- BrowserScreens.screens() do
    @screen screen
    feature "#{@screen}: canvas background, console nav, one display heading", %{session: session} do
      {session, _} = BrowserScreens.open(session, @screen)

      assert same_color?(computed_style(session, "body", "backgroundColor"), "#0F172A")
      assert String.starts_with?(computed_style(session, "body", "fontFamily"), "Inter")
      assert_has(session, css("#console-nav"))

      headings =
        js(
          session,
          "return Array.from(document.querySelectorAll('h1')).map(h => [getComputedStyle(h).fontSize, getComputedStyle(h).fontWeight]);"
        )

      assert headings == [["28px", "600"]]
    end

    feature "#{@screen}: no horizontal scroll on desktop or phone widths", %{session: session} do
      {session, _} = BrowserScreens.open(session, @screen)

      {w, h} = @desktop
      session |> resize_window(w, h) |> assert_no_horizontal_scroll()

      {w, h} = @phone
      session |> resize_window(w, h) |> assert_no_horizontal_scroll()

      {w, h} = @desktop
      resize_window(session, w, h)
    end

    feature "#{@screen}: icon-only buttons are ≥44×44 with an exact accessible name", %{
      session: session
    } do
      {session, _} = BrowserScreens.open(session, @screen)

      buttons =
        js(
          session,
          """
          return Array.from(document.querySelectorAll('button')).filter(b => b.getClientRects().length > 0).map(b => {
            const r = b.getBoundingClientRect();
            return {id: b.id, text: (b.innerText || '').trim(), label: b.getAttribute('aria-label'), w: r.width, h: r.height};
          });
          """
        )

      for b <- buttons, b["text"] == "" do
        assert is_binary(b["label"]) and b["label"] != "",
               "icon-only button ##{b["id"]} has no aria-label"

        assert b["w"] >= 44 and b["h"] >= 44,
               "icon-only button ##{b["id"]} is #{b["w"]}×#{b["h"]}"
      end

      for b <- buttons, is_binary(b["label"]) do
        assert Regex.match?(
                 ~r/^(Approve device|Deny pairing request|Revoke .+|Rename .+|Dismiss)$/,
                 b["label"]
               ),
               "aria-label is not an action verb phrase: #{inspect(b["label"])}"
      end
    end

    if BrowserScreens.initial_focus(screen) do
      @focus BrowserScreens.initial_focus(screen)
      feature "#{@screen}: keyboard focus starts on #{@focus}", %{
        session: session
      } do
        {session, _} = BrowserScreens.open(session, @screen)
        expected = @focus

        wait_until(
          session,
          &(js(&1, "return document.activeElement && document.activeElement.id;") == expected),
          "focus on ##{expected}"
        )
      end
    end
  end

  test "the screen registry covers every console route in the router" do
    console_paths =
      Phoenix.Router.routes(PlaysteadWeb.Router)
      |> Enum.filter(&(&1.verb == :get))
      |> Enum.map(& &1.path)
      |> Enum.reject(&(String.starts_with?(&1, "/dev/") or String.starts_with?(&1, "/api")))
      |> Enum.reject(&(&1 in BrowserScreens.excluded_paths()))
      |> Enum.uniq()
      |> Enum.sort()

    registry = BrowserScreens.screens() |> Enum.map(&BrowserScreens.path/1) |> Enum.sort()

    assert console_paths == registry,
           "console routes changed — add the new screen to PlaysteadWeb.BrowserScreens\n" <>
             "router: #{inspect(console_paths)}\nregistry: #{inspect(registry)}"
  end
end
