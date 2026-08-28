defmodule PlaysteadWeb.Browser.PaletteTest do
  @moduledoc """
  01-UI-SPEC § Color, enforced on the rendered page: every computed color on
  every console screen is one of the nine palette hexes, and the four
  semantic colors are used *only* where the spec reserves them.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  @palette ~w(#0F172A #1E293B #38BDF8 #EF4444 #4ADE80 #FBBF24 #F1F5F9 #94A3B8 #334155)
  @accent "#38BDF8"
  @destructive "#EF4444"
  @success "#4ADE80"
  @warning "#FBBF24"

  # Where the accent may appear: primary CTAs, the display code, code-role
  # text, the "(this device)" marker, the info flash, and the focus ring
  # (any focused element).
  @accent_ids ~w(login_submit sudo_submit recovery_submit setup_token_submit owner_submit continue_to_readiness finish_setup flash-info)
  @accent_prefixes ~r/^(display-code-|approve-|recovery-code-|confirm-import-)/
  @accent_suffixes ~r/(-rename-save|-current)$/

  # Where destructive red may appear: Deny / Revoke controls, the Expired
  # marker, the error flash, and inline validation errors.
  @destructive_prefixes ~r/^(deny-|flash-error)/
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

  feature "the Deny hover surface stays on the palette", %{session: session} do
    {session, %{pending: pending}} = BrowserScreens.open(session, :devices)
    session = hover(session, css("#deny-#{pending.id}"))

    bg = computed_style(session, "#deny-#{pending.id}", "backgroundColor")
    assert same_color?(normalize_color(session, bg), @destructive)
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
