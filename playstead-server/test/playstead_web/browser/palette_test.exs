defmodule PlaysteadWeb.Browser.PaletteTest do
  @moduledoc """
  01-UI-SPEC § Color, enforced on the rendered page: every computed color on
  every console screen is one of the nine palette hexes, and the four
  semantic colors are used *only* where the spec reserves them.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  # Phase 1's nine-hex console palette, plus the two Phase 3 vocabularies
  # 03-UI-SPEC.md adds alongside it (never replacing it): system identity
  # (monogram tiles, meta-line chips) and the status ladder (one status
  # slot per card, the storage view). Both are deliberately disjoint from
  # each other and from Phase 1's semantic roles — see 03-UI-SPEC.md
  # § Color — so they are additive here, not a relaxation of the rule.
  @system_accents ~w(#6366F1 #65A30D #0D9488 #B91C1C #A21CAF #1D4ED8 #57534E #64748B)
  @status_ladder ~w(#F59E0B #EA580C #0EA5E9 #9CA3AF #16A34A #15803D #94A3B8 #78716C)
  @palette ~w(#0F172A #1E293B #38BDF8 #EF4444 #4ADE80 #FBBF24 #F1F5F9 #94A3B8 #334155) ++
             @system_accents ++ @status_ladder
  @accent "#38BDF8"
  @destructive "#EF4444"
  @success "#4ADE80"
  @warning "#FBBF24"

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
  # `color-mix(in oklab, ...)`.
  @destructive_hover_surface "color-mix(in oklab, #EF4444 10%, transparent)"

  feature "the Deny hover surface stays on the palette", %{session: session} do
    {session, %{pending: pending}} = BrowserScreens.open(session, :devices)
    selector = "#deny-#{pending.id}"

    resting = computed_style(session, selector, "backgroundColor")
    session = hover(session, css(selector))
    hovered = computed_style(session, selector, "backgroundColor")

    # Split from the color assertion so a headless browser that never
    # applies :hover reports that, rather than looking like a palette
    # violation.
    refute normalize_color(session, hovered) == normalize_color(session, resting),
           "hovering #{selector} did not change its background (resting #{resting}, " <>
             "hovered #{hovered}) -- the hover state never applied, so the color " <>
             "assertion below would be meaningless"

    # Both sides are normalized by the SAME browser rather than comparing a
    # 10%-alpha color against an opaque hex. That comparison round-trips
    # through a canvas pixel, and unpremultiplying at alpha 0.1 amplifies
    # 8-bit rounding roughly tenfold -- enough for Chrome's Skia backend to
    # land outside tolerance on Linux while passing on macOS, which is
    # exactly how this test failed on its first CI run. Normalizing both
    # sides identically cancels that error on every platform while still
    # catching a genuinely off-palette hover surface.
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
