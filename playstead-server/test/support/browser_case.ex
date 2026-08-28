defmodule PlaysteadWeb.BrowserCase do
  @moduledoc """
  Case template for the headless-Chrome browser suite (`test/playstead_web/browser/`).

  These tests exist to make the UI-SPEC's design contract machine-checked —
  computed colors, loaded fonts, sizes, letter-spacing, click-target sizes,
  clipping — on the *rendered* page, which `Phoenix.LiveViewTest` cannot see.
  Everything a test waits on goes through Wallaby's retrying `assert_has/2`;
  there is no `Process.sleep/1` anywhere in this suite.

  Conventions:
    * `use PlaysteadWeb.BrowserCase, async: false` — the endpoint, the rate
      limiter and the `:env_overrides` seam are process-global.
    * Write tests with the `feature` macro (from `Wallaby.Feature`), which
      checks out the Ecto sandbox and hands the test a `session`.
    * Never call `visit/2` directly for a LiveView page — use `visit_live/2`,
      which also waits for the LiveView socket to connect (a `phx-click`
      fired before that is silently dropped).
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      use Wallaby.Feature
      use PlaysteadWeb, :verified_routes

      import Wallaby.Query, except: [text: 1, text: 2]
      import PlaysteadWeb.BrowserCase
      import Playstead.AccountsFixtures
      import Playstead.PairingFixtures
      import Playstead.TlsFixtures

      alias Playstead.Repo

      @moduletag :browser
    end
  end

  # `assert_has/2` is a macro that expands to `execute_query/2`, so the whole
  # Browser module must be imported (not just aliased) where it is used.
  import Wallaby.Browser
  alias Wallaby.Browser
  import ExUnit.Assertions
  import Wallaby.Query, only: [css: 1]

  # ---------------------------------------------------------------------
  # Navigation
  # ---------------------------------------------------------------------

  @doc """
  Visit a LiveView route and block until the socket is connected and the
  webfonts have loaded, so every subsequent computed-style read and click
  is against the fully live page.
  """
  def visit_live(session, path) do
    session
    |> Browser.visit(path)
    |> assert_has(css("[data-phx-main].phx-connected"))
    |> fonts_ready()
    |> initial_focus_settled()
  end

  # `phx-mounted={JS.focus()}` runs on a requestAnimationFrame after the
  # connected render. Typing before it lands lets it steal focus mid-keystroke
  # (the rest of the text goes into the newly focused field). Wait for it.
  defp initial_focus_settled(session) do
    wait_until(
      session,
      fn s ->
        js(
          s,
          "const auto = document.querySelector('[phx-mounted]'); " <>
            "return !auto || document.activeElement !== document.body;"
        )
      end,
      "the phx-mounted focus to settle"
    )
  end

  @doc """
  Wait (retrying) until nothing matches `query`. Wallaby's `refute_has/2`
  retries until the element *appears* — the inverse of what a post-mutation
  check needs — so every "it went away" assertion in this suite uses this.
  """
  def assert_gone(session, %Wallaby.Query{} = query) do
    assert_has(session, %{query | conditions: Keyword.put(query.conditions, :count, 0)})
  end

  @doc "Wait for `document.fonts.ready` (see app.js)."
  def fonts_ready(session), do: assert_has(session, css("html[data-fonts-ready]"))

  @doc "Wait until the browser's current path equals `path` (retried)."
  def assert_path(session, path) do
    assert_has(session, css("[data-phx-main], body"))

    wait_until(session, fn s -> Browser.current_path(s) == path end, "path to be #{path}")
  end

  # ---------------------------------------------------------------------
  # Authentication
  # ---------------------------------------------------------------------

  @session_cookie "_playstead_key"

  @doc """
  Log the browser in by minting a real, signed `_playstead_key` cookie —
  the same `Plug.Session` cookie store and salt the endpoint uses — so no
  form, CSRF token or redirect timing is involved.

  Options:
    * `:token_authenticated_at` — override sudo freshness (see
      `Playstead.AccountsFixtures.override_token_authenticated_at/2`).
    * `:session` — extra session values, e.g. an injected
      `%{"phoenix_flash" => %{"error" => "..."}}` for the long-text states.
  """
  def log_in_via_cookie(session, user, opts \\ []) do
    token = Playstead.Accounts.generate_user_session_token(user)

    if at = opts[:token_authenticated_at] do
      Playstead.AccountsFixtures.override_token_authenticated_at(token, at)
    end

    extra = Keyword.get(opts, :session, %{})
    cookie = session_cookie(Map.merge(%{"user_token" => token}, extra))

    # Chromedriver only accepts a cookie for the current document's origin,
    # so land on the cheapest same-origin page first.
    session
    |> Browser.visit("/healthz")
    |> Browser.set_cookie(@session_cookie, cookie)
  end

  @doc "Log in through the real form at /log-in."
  def log_in_via_browser(session, email, password) do
    session
    |> visit_live("/log-in")
    |> Browser.fill_in(css("#login_form_email"), with: email)
    |> Browser.fill_in(css("#login_form_password"), with: password)
    |> Browser.click(css("#login_submit"))
  end

  @doc "Produce a signed session cookie value for `values` using the endpoint's real options."
  def session_cookie(values) when is_map(values) do
    opts = Plug.Session.init(PlaysteadWeb.Endpoint.session_options())

    conn =
      Phoenix.ConnTest.build_conn()
      |> Map.put(:secret_key_base, PlaysteadWeb.Endpoint.config(:secret_key_base))
      |> Plug.Session.call(opts)
      |> Plug.Conn.fetch_session()

    conn =
      Enum.reduce(values, conn, fn {k, v}, c -> Plug.Conn.put_session(c, k, v) end)
      |> Plug.Conn.send_resp(200, "")

    conn.resp_cookies[@session_cookie].value
  end

  # ---------------------------------------------------------------------
  # JavaScript / computed-style probes
  # ---------------------------------------------------------------------

  @doc "Run `script` (which must `return`) with `args` and return its value synchronously."
  def js(session, script, args \\ []) do
    parent = self()
    ref = make_ref()
    Browser.execute_script(session, script, args, &send(parent, {ref, &1}))

    receive do
      {^ref, value} -> value
    after
      5_000 -> flunk("execute_script did not return within 5s: #{String.slice(script, 0, 80)}")
    end
  end

  @doc "One computed style property of the first element matching `selector`."
  def computed_style(session, selector, prop) do
    js(
      session,
      "const el = document.querySelector(arguments[0]); " <>
        "if (!el) return null; return getComputedStyle(el)[arguments[1]];",
      [selector, prop]
    )
  end

  @doc "Bounding box `%{\"x\",\"y\",\"w\",\"h\"}` of the first element matching `selector`."
  def bbox(session, selector) do
    js(
      session,
      "const el = document.querySelector(arguments[0]); if (!el) return null; " <>
        "const r = el.getBoundingClientRect(); return {x: r.x, y: r.y, w: r.width, h: r.height};",
      [selector]
    )
  end

  # Any CSS color (incl. Tailwind v4's color-mix()/oklab output for opacity
  # modifiers) is rasterised into one canvas pixel and read back as sRGB
  # RGBA — the only serialisation that is stable across color spaces.
  @norm_js """
  const cv = document.createElement('canvas'); cv.width = 1; cv.height = 1;
  const ctx = cv.getContext('2d', {willReadFrequently: true});
  const norm = (v) => {
    ctx.clearRect(0, 0, 1, 1); ctx.fillStyle = '#000000'; ctx.fillStyle = v;
    ctx.fillRect(0, 0, 1, 1);
    const [r, g, b, a] = ctx.getImageData(0, 0, 1, 1).data;
    return 'rgba(' + r + ', ' + g + ', ' + b + ', ' + (a / 255).toFixed(3) + ')';
  };
  """

  @style_walk @norm_js <>
                """
                const describe = (e) => e.id ? '#' + e.id : e.tagName.toLowerCase() + (e.className && typeof e.className === 'string' ? '.' + e.className.trim().split(/\\s+/).slice(0, 3).join('.') : '');
                return Array.from(document.querySelectorAll(arguments[0]))
                  .filter(e => e.getClientRects().length > 0)
                  .map(e => {
                    const s = getComputedStyle(e);
                    const ownText = Array.from(e.childNodes).some(n => n.nodeType === 3 && n.textContent.trim() !== '');
                    const idHost = e.closest('[id]');
                    const stateHost = e.closest('[data-state]');
                    const roleHost = e.closest('[data-role]');
                    return {
                      sel: describe(e), tag: e.tagName.toLowerCase(), id: e.id || null,
                      closestId: idHost ? idHost.id : null,
                      dataRole: roleHost ? roleHost.dataset.role : null,
                      closestState: stateHost ? stateHost.dataset.state : null,
                      focused: document.activeElement === e,
                      color: norm(s.color), bg: norm(s.backgroundColor),
                      border: norm(s.borderTopColor), outline: norm(s.outlineColor),
                      borderWidth: s.borderTopWidth, borderStyle: s.borderTopStyle,
                      outlineWidth: s.outlineWidth, outlineStyle: s.outlineStyle,
                      fontSize: s.fontSize, fontWeight: s.fontWeight, fontFamily: s.fontFamily,
                      letterSpacing: s.letterSpacing, lineHeight: s.lineHeight,
                      ownText: ownText, text: (e.innerText || '').trim().slice(0, 60)
                    };
                  });
                """

  @doc """
  Every visible element under `scope` with its normalized computed colors
  and type properties. This is the single probe the palette, typography and
  coherence contract tests are written against.
  """
  def style_walk(session, scope \\ "body *"), do: js(session, @style_walk, [scope])

  @doc """
  Force-load `family` (browsers fetch a `@font-face` lazily, only once an
  element renders text in it) and wait until every declared face of that
  family reports `loaded` — proving the shipped file is fetchable and parses.
  """
  def ensure_font_loaded(session, family) do
    js(
      session,
      "for (const f of document.fonts) { if (f.family.replace(/\"/g, '') === arguments[0]) f.load(); } return true;",
      [family]
    )

    wait_until(
      session,
      fn s ->
        s
        |> font_faces()
        |> Enum.filter(&match?([^family, _, _], &1))
        |> then(&(&1 != [] and Enum.all?(&1, fn [_, _, status] -> status == "loaded" end)))
      end,
      "#{family} to load"
    )
  end

  @doc "Normalise any CSS color string to `rgba(r, g, b, a)` through the canvas."
  def normalize_color(session, color),
    do: js(session, @norm_js <> "return norm(arguments[0]);", [color])

  @doc "The document's FontFace list as `[family, weight, status]` triples."
  def font_faces(session) do
    js(
      session,
      "return Array.from(document.fonts).map(f => [f.family.replace(/\"/g, ''), f.weight, f.status]);"
    )
  end

  @doc """
  Assert the element neither overflows its own box nor escapes the viewport —
  the UI-SPEC's overflow / long-text backstops made objective.
  """
  def assert_no_clip(session, selector) do
    result =
      js(
        session,
        """
        const el = document.querySelector(arguments[0]);
        if (!el) return {missing: true};
        const r = el.getBoundingClientRect();
        return {
          scrollWidth: el.scrollWidth, clientWidth: el.clientWidth,
          scrollHeight: el.scrollHeight, clientHeight: el.clientHeight,
          left: r.left, right: r.right, top: r.top, bottom: r.bottom,
          vw: document.documentElement.clientWidth, vh: document.documentElement.clientHeight,
          overflowX: getComputedStyle(el).overflowX
        };
        """,
        [selector]
      )

    refute result["missing"], "#{selector} not found"

    # A `truncate` element is *supposed* to clip with an ellipsis (claimed
    # names, session labels). Everything else must fit.
    unless result["overflowX"] == "hidden" do
      assert result["scrollWidth"] <= result["clientWidth"] + 1,
             "#{selector} overflows horizontally: #{inspect(result)}"

      assert result["scrollHeight"] <= result["clientHeight"] + 1,
             "#{selector} overflows vertically (clipped text): #{inspect(result)}"
    end

    assert result["left"] >= 0 and result["right"] <= result["vw"] + 1,
           "#{selector} escapes the viewport horizontally: #{inspect(result)}"

    session
  end

  @doc "The page has no horizontal scroll at the current window size."
  def assert_no_horizontal_scroll(session) do
    assert js(
             session,
             "return document.documentElement.scrollWidth <= document.documentElement.clientWidth + 1;"
           ),
           "page scrolls horizontally at this viewport"

    session
  end

  # ---------------------------------------------------------------------
  # Color helpers
  # ---------------------------------------------------------------------

  @doc "Parse a canvas-normalized color (`#rrggbb` or `rgba(r, g, b, a)`) into `{r, g, b, a}`."
  def parse_color("#" <> hex) when byte_size(hex) == 6 do
    {r, g, b} = {String.slice(hex, 0, 2), String.slice(hex, 2, 2), String.slice(hex, 4, 2)}
    {String.to_integer(r, 16), String.to_integer(g, 16), String.to_integer(b, 16), 1.0}
  end

  def parse_color("rgba(" <> rest) do
    [r, g, b, a] =
      rest |> String.trim_trailing(")") |> String.split(",") |> Enum.map(&String.trim/1)

    {String.to_integer(r), String.to_integer(g), String.to_integer(b), parse_float(a)}
  end

  def parse_color("rgb(" <> rest) do
    [r, g, b] = rest |> String.trim_trailing(")") |> String.split(",") |> Enum.map(&String.trim/1)
    {String.to_integer(r), String.to_integer(g), String.to_integer(b), 1.0}
  end

  defp parse_float(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> 1.0
    end
  end

  @doc "True when the color is fully transparent (ignored by the palette walk)."
  def transparent?(color) do
    match?({_, _, _, a} when a < 0.01, parse_color(color))
  end

  @doc """
  True when `color`'s RGB is within tolerance of a palette hex. Opaque colors
  must match within ±1 per channel; translucent ones (opacity modifiers such
  as `/40`) are read back from premultiplied canvas bytes, so the tolerance
  widens with transparency (≤ ±8 at 10% alpha).
  """
  def same_color?(color, "#" <> _ = hex, tolerance \\ nil) do
    {r1, g1, b1, a} = parse_color(color)
    {r2, g2, b2, _} = parse_color(String.downcase(hex))
    tolerance = tolerance || if(a >= 0.99, do: 1, else: min(8, round(1 / max(a, 0.125))))
    abs(r1 - r2) <= tolerance and abs(g1 - g2) <= tolerance and abs(b1 - b2) <= tolerance
  end

  @doc "The palette hex `color` matches, or `nil`."
  def palette_match(color, palette) do
    Enum.find(palette, &same_color?(color, &1))
  end

  @doc "Parse `\"12.5px\"` into a float."
  def px(value) when is_binary(value) do
    {f, "px"} = Float.parse(value)
    f
  end

  # ---------------------------------------------------------------------
  # Waiting
  # ---------------------------------------------------------------------

  @doc false
  def wait_until(session, fun, what, attempts \\ 50) do
    cond do
      fun.(session) ->
        session

      attempts == 0 ->
        flunk("timed out waiting for #{what}")

      true ->
        # Bounded retry backed by Wallaby's own retry loop (no Process.sleep):
        # `assert_has` on `body` costs one driver round-trip (~10ms).
        assert_has(session, css("body"))
        wait_until(session, fun, what, attempts - 1)
    end
  end
end
