defmodule PlaysteadWeb.Browser.ReducedMotionTest do
  @moduledoc """
  "Reduced-motion behavior: the download progress fill is retained while
  status-change transitions become instant/crossfade under
  prefers-reduced-motion" (03-UAT.md checkpoint 12, D-16 motion budget),
  made objective.

  `assets/css/app.css` carries a `@media (prefers-reduced-motion: reduce)`
  block, but nothing exercised it — the media query had zero coverage, so a
  blanket `* { transition: none }` regression (the usual way this rule is
  written) would have killed the information-bearing progress fill silently.

  Chrome is launched with `--force-prefers-reduced-motion` for the reduced
  session, so these are real computed styles from the real shipped
  stylesheet under a real media-query match — not a source-text grep.

  The status slot is injected into `document.body`, outside the LiveView
  container, because no console screen in this phase renders a
  `downloading`/`verified`/`pinned` slot yet (that availability state is
  Mac-side). Injecting outside `[data-phx-main]` keeps LiveView's DOM
  patching from reaping the node mid-test.
  """
  use PlaysteadWeb.BrowserCase, async: false

  alias PlaysteadWeb.BrowserScreens

  @reduced_motion_capabilities Wallaby.Chrome.default_capabilities()
                               |> update_in(
                                 [:chromeOptions, :args],
                                 &(&1 ++ ["--force-prefers-reduced-motion"])
                               )

  # The three ladder states that carry a crossfade (app.css "Motion budget").
  @transitioning_states ~w(downloading verified pinned)

  # A stand-in for the information-bearing download progress fill: an
  # element whose own transition is declared inline, exactly as a width-
  # driven fill would be. If the reduced-motion block ever becomes a
  # blanket reset, this is what silently dies.
  @progress_fill_transition "width 300ms linear"

  defp inject_probes(session) do
    js(session, """
    const host = document.createElement('div');
    host.id = 'motion-probe';
    host.innerHTML = #{Jason.encode!(probe_markup())};
    document.body.appendChild(host);
    return true;
    """)

    session
  end

  defp probe_markup do
    slots =
      Enum.map_join(@transitioning_states, "", fn state ->
        ~s(<span class="status-slot status-slot-#{state}">) <>
          ~s(<span class="status-slot-glyph" data-probe="#{state}"></span></span>)
      end)

    slots <>
      ~s(<div data-probe="progress-fill" style="transition: #{@progress_fill_transition}"></div>)
  end

  defp transition_duration(session, probe) do
    computed_style(session, ~s([data-probe="#{probe}"]), "transitionDuration")
  end

  feature "without reduced motion, status-change glyphs crossfade over 150ms", %{
    session: session
  } do
    {session, _} = BrowserScreens.open(session, :library)
    session = inject_probes(session)

    assert js(session, "return matchMedia('(prefers-reduced-motion: reduce)').matches;") == false,
           "the control session must NOT match prefers-reduced-motion"

    for state <- @transitioning_states do
      assert transition_duration(session, state) == "0.15s",
             "#{state} glyph should crossfade over 150ms without reduced motion"
    end
  end

  @sessions [[capabilities: @reduced_motion_capabilities]]
  feature "under reduced motion, status-change glyphs swap instantly", %{session: session} do
    {session, _} = BrowserScreens.open(session, :library)
    session = inject_probes(session)

    assert js(session, "return matchMedia('(prefers-reduced-motion: reduce)').matches;") == true,
           "--force-prefers-reduced-motion did not take effect; the rest of this test is vacuous"

    for state <- @transitioning_states do
      assert transition_duration(session, state) == "0s",
             "#{state} glyph must not animate under prefers-reduced-motion"
    end
  end

  @sessions [[capabilities: @reduced_motion_capabilities]]
  feature "under reduced motion, information-bearing fill motion is retained", %{
    session: session
  } do
    {session, _} = BrowserScreens.open(session, :library)
    session = inject_probes(session)

    assert js(session, "return matchMedia('(prefers-reduced-motion: reduce)').matches;") == true

    assert transition_duration(session, "progress-fill") == "0.3s",
           "the reduced-motion block must scope its reset to status-change transitions — " <>
             "a blanket reset would also kill the download progress fill, which D-16 retains " <>
             "because it is continuous and information-bearing"
  end
end
