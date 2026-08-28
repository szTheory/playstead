defmodule PlaysteadWeb.Browser.TypographyTest do
  @moduledoc """
  01-UI-SPEC § Typography on the rendered page: the two shipped families
  actually load; every text element is one of the five sizes and two
  weights; the pairing display code is the single 40px element, the largest
  on its screen, in JetBrains Mono at 0.08em; code-role text is 20px/0.04em.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  @sizes ~w(14px 16px 20px 28px 40px)
  @weights ~w(400 600)

  for screen <- BrowserScreens.screens() do
    @screen screen
    feature "#{@screen}: Inter renders every text element; JetBrains Mono only code-role text", %{
      session: session
    } do
      {session, _} = BrowserScreens.open(session, @screen)
      session = ensure_font_loaded(session, "Inter")

      text_elements = Enum.filter(style_walk(session), & &1["ownText"])
      assert text_elements != []

      families = text_elements |> Enum.map(& &1["fontFamily"]) |> Enum.uniq()

      bad_family =
        Enum.reject(families, fn f ->
          String.starts_with?(f, "Inter") or String.starts_with?(f, "\"JetBrains Mono\"") or
            String.starts_with?(f, "JetBrains Mono")
        end)

      assert bad_family == [], "unexpected font-family: #{inspect(bad_family)}"

      mono = Enum.filter(text_elements, &String.contains?(&1["fontFamily"], "JetBrains Mono"))

      if BrowserScreens.uses_mono?(@screen) do
        assert mono != [], "expected code-role text on #{@screen}"
        ensure_font_loaded(session, "JetBrains Mono")

        for el <- mono do
          assert el["dataRole"] in ["code", "display-code", "fingerprint"] or el["tag"] == "input",
                 "JetBrains Mono outside a code role: #{el["sel"]} (#{el["text"]})"
        end
      end
    end

    feature "#{@screen}: font sizes ⊆ {14,16,20,28,40}px and weights ⊆ {400,600}", %{
      session: session
    } do
      {session, _} = BrowserScreens.open(session, @screen)
      text_elements = Enum.filter(style_walk(session), & &1["ownText"])

      bad_sizes =
        for el <- text_elements,
            el["fontSize"] not in @sizes,
            do: "#{el["sel"]} #{el["fontSize"]} (#{el["text"]})"

      bad_weights =
        for el <- text_elements,
            el["fontWeight"] not in @weights,
            do: "#{el["sel"]} #{el["fontWeight"]} (#{el["text"]})"

      assert bad_sizes == [], "off-budget font sizes:\n#{Enum.join(bad_sizes, "\n")}"
      assert bad_weights == [], "off-budget font weights:\n#{Enum.join(bad_weights, "\n")}"
    end
  end

  feature "the pairing display code is the only 40px element and the largest on the Devices screen",
          %{
            session: session
          } do
    {session, %{pending: pending}} = BrowserScreens.open(session, :devices)
    walk = Enum.filter(style_walk(session), & &1["ownText"])

    forty = Enum.filter(walk, &(&1["fontSize"] == "40px"))
    assert forty != []
    assert Enum.all?(forty, &(&1["dataRole"] == "display-code")), inspect(forty)

    max_size = walk |> Enum.map(&px(&1["fontSize"])) |> Enum.max()
    assert max_size == 40.0

    sel = "#display-code-#{pending.id}"
    assert computed_style(session, sel, "fontSize") == "40px"
    assert computed_style(session, sel, "fontWeight") == "600"
    assert_in_delta px(computed_style(session, sel, "letterSpacing")), 3.2, 0.05
    assert String.contains?(computed_style(session, sel, "fontFamily"), "JetBrains Mono")
    assert same_color?(computed_style(session, sel, "color"), "#38BDF8")
    assert Wallaby.Browser.text(session, css(sel)) == pending.display_code
  end

  feature "device credential fingerprints are 14px / 400 JetBrains Mono, muted", %{
    session: session
  } do
    {session, %{active: active}} = BrowserScreens.open(session, :devices)

    for sel <- ["#device-#{active.id}-fingerprint", "#ca-fingerprint"] do
      assert computed_style(session, sel, "fontSize") == "14px", sel
      assert computed_style(session, sel, "fontWeight") == "400", sel
      assert String.contains?(computed_style(session, sel, "fontFamily"), "JetBrains Mono"), sel
      assert same_color?(computed_style(session, sel, "color"), "#94A3B8"), sel
    end
  end

  feature "the recovery-code field renders in JetBrains Mono", %{session: session} do
    {session, _} = BrowserScreens.open(session, :recovery_login)

    assert String.contains?(
             computed_style(session, "#recovery_login_form_code", "fontFamily"),
             "JetBrains Mono"
           )
  end

  feature "the setup token field is code-role: 20px / 0.04em JetBrains Mono", %{session: session} do
    {session, _} = BrowserScreens.open(session, :setup)

    assert computed_style(session, "#setup_token", "fontSize") == "20px"
    assert_in_delta px(computed_style(session, "#setup_token", "letterSpacing")), 0.8, 0.05

    assert String.contains?(
             computed_style(session, "#setup_token", "fontFamily"),
             "JetBrains Mono"
           )
  end
end
