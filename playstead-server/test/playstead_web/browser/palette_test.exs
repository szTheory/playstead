defmodule PlaysteadWeb.Browser.PaletteTest do
  @moduledoc """
  01-UI-SPEC § Color, enforced on the rendered page: every computed color on
  every console screen is one of the nine palette hexes, and the four
  semantic colors are used *only* where the spec reserves them.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  # The checked-in design contract feeds the rendered palette allow-list,
  # while DesignTokenParityTest verifies its Swift and Tailwind mappings.
  @token_contract_path Path.expand("../../../../design-system/shared-tokens.json", __DIR__)
  @token_contract @token_contract_path |> File.read!() |> Jason.decode!()
  @web_palette @token_contract["webPalette"]
  @system_accents @token_contract["shared"]["systemAccents"]
                  |> Map.values()
                  |> Enum.map(fn token -> "##{token["hex"]}" end)
  @status_ladder @token_contract["shared"]["status"]
                 |> Map.values()
                 |> Enum.map(fn token -> "##{token["hex"]}" end)
  @palette Enum.map(Map.values(@web_palette), fn hex -> "##{hex}" end) ++
             @system_accents ++
             @status_ladder ++
             ["##{@token_contract["platformSpecific"]["webStatusPinned"]}"]
  @accent "##{@web_palette["accent"]}"
  @destructive "##{@web_palette["danger"]}"
  @success "##{@web_palette["success"]}"
  @warning "##{@web_palette["warning"]}"

  # Where the accent may appear: primary CTAs, the display code, code-role
  # text, the "(this device)" marker, the info flash, and the focus ring
  # (any focused element).
  @accent_ids ~w(login_submit sudo_submit recovery_submit setup_token_submit owner_submit continue_to_readiness finish_setup flash-info import-pack-submit create-collection-submit)
  @accent_prefixes ~r/^(display-code-|approve-|recovery-code-|confirm-import-)/
  @accent_suffixes ~r/(-rename-save|-current)$/

  # Where destructive red may appear: Deny / Revoke controls, the Expired
  # marker, the error flash, and inline validation errors.
  @destructive_prefixes ~r/^(deny-|flash-error|delete-collection-)/
  @destructive_suffixes ~r/(-revoke|-expired|_error)$/

  for screen <- BrowserScreens.screens() do
    @screen screen
    feature "#{@screen}: every rendered color is one of the nine palette hexes", %{
      session: session
    } do
      {session, _} = BrowserScreens.open(session, @screen)

      offenders =
        for el <- style_walk(session),
            {prop, value} <- painted_colors(el),
            not transparent?(value),
            is_nil(palette_match(value, @palette)),
            do: "#{el["sel"]} #{prop}=#{value} (#{el["text"]})"

      assert offenders == [], "off-palette colors:\n" <> Enum.join(offenders, "\n")
    end

    feature "#{@screen}: accent, destructive, success and warning are used only where reserved",
            %{
              session: session
            } do
      {session, _} = BrowserScreens.open(session, @screen)
      walk = style_walk(session)

      accent_misuse =
        for el <- walk, painted?(el, @accent), not accent_allowed?(el), do: describe(el)

      destructive_misuse =
        for el <- walk, painted?(el, @destructive), not destructive_allowed?(el), do: describe(el)

      success_misuse =
        for el <- walk,
            painted?(el, @success),
            not (String.starts_with?(el["closestId"] || "", "readiness-") and
                   el["closestState"] == "ok"),
            do: describe(el)

      warning_misuse =
        for el <- walk,
            painted?(el, @warning),
            not ((String.starts_with?(el["closestId"] || "", "readiness-") and
                    el["closestState"] == "warning") or el["closestId"] == "queue-full-notice"),
            do: describe(el)

      assert accent_misuse == [],
             "accent outside CTA/display-code/focus:\n#{Enum.join(accent_misuse, "\n")}"

      assert destructive_misuse == [],
             "destructive outside revoke/deny/error:\n#{Enum.join(destructive_misuse, "\n")}"

      assert success_misuse == [],
             "success outside readiness OK rows:\n#{Enum.join(success_misuse, "\n")}"

      assert warning_misuse == [],
             "warning outside readiness warnings / queue-full:\n#{Enum.join(warning_misuse, "\n")}"
    end
  end

  # The Deny button's hover surface is `hover:bg-[#EF4444]/10` -- the
  # destructive red at 10% alpha, which Tailwind v4 emits as a
  # `color-mix(in oklab, ...)` inside `@media (hover: hover)`.
  @destructive_hover_surface "color-mix(in oklab, #EF4444 10%, transparent)"

  feature "the Deny hover surface stays on the palette", %{session: session} do
    {session, %{pending: pending}} = BrowserScreens.open(session, :devices)
    selector = "#deny-#{pending.id}"

    # Guards the whole assertion: Tailwind v4 wraps `hover:` utilities in
    # `@media (hover: hover)`, so a browser advertising no hover-capable
    # pointer makes every one of them inert and this test unfalsifiable.
    # config/test.exs sets blink settings so headless Chrome advertises
    # one; if that ever regresses, fail here rather than silently passing.
    assert js(session, "return matchMedia('(hover: hover)').matches;"),
           "this browser reports no hover-capable pointer, so every Tailwind `hover:` " <>
             "utility is inert and this test cannot detect an off-palette hover surface"

    resting = computed_style(session, selector, "backgroundColor")
    session = hover(session, css(selector))
    hovered = computed_style(session, selector, "backgroundColor")

    refute normalize_color(session, hovered) == normalize_color(session, resting),
           "hovering #{selector} did not change its background (resting #{resting}, " <>
             "hovered #{hovered})"

    # Both sides are normalized by the SAME browser rather than comparing a
    # 10%-alpha color against an opaque hex: that round-trips through a
    # canvas pixel, and unpremultiplying at alpha 0.1 amplifies 8-bit
    # rounding roughly tenfold. Normalizing both sides identically cancels
    # the error on every platform while still catching an off-palette value.
    assert normalize_color(session, hovered) ==
             normalize_color(session, @destructive_hover_surface),
           "the Deny hover surface is #{hovered}, which is not the destructive red " <>
             "at 10% (#{@destructive_hover_surface})"
  end

  # --- helpers ----------------------------------------------------------

  defp painted_colors(el) do
    [{"color", el["color"]}, {"bg", el["bg"]}] ++
      if(el["borderWidth"] != "0px" and el["borderStyle"] != "none",
        do: [{"border", el["border"]}],
        else: []
      ) ++
      if(el["outlineWidth"] != "0px" and el["outlineStyle"] != "none",
        do: [{"outline", el["outline"]}],
        else: []
      )
  end

  # Only the text color and background count for the exclusivity rules —
  # a border on a Deny button is destructive by design and covered by the
  # same allow-list because it lives on the same element.
  defp painted?(el, hex) do
    Enum.any?(painted_colors(el), fn {_, v} -> not transparent?(v) and same_color?(v, hex) end)
  end

  defp accent_allowed?(el) do
    id = el["closestId"] || ""

    el["focused"] or id in @accent_ids or Regex.match?(@accent_prefixes, id) or
      Regex.match?(@accent_suffixes, id) or el["dataRole"] in ["code", "display-code"]
  end

  defp destructive_allowed?(el) do
    id = el["closestId"] || ""

    el["dataRole"] == "error" or Regex.match?(@destructive_prefixes, id) or
      Regex.match?(@destructive_suffixes, id)
  end

  defp describe(el),
    do:
      "#{el["sel"]} (closest ##{el["closestId"]}) color=#{el["color"]} bg=#{el["bg"]} border=#{el["border"]}"
end
