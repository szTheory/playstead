# The browser suite (test/playstead_web/browser/, tagged :browser) drives
# headless Chrome through Wallaby. It is part of the default `mix test` run
# whenever chromedriver is on PATH (CI always has it); without chromedriver
# it is excluded with a visible notice rather than failing, so `mix precommit`
# never blocks a contributor who has not installed Chrome.
browser_available? = System.find_executable("chromedriver") != nil

exclude =
  if browser_available? do
    {:ok, _} = Application.ensure_all_started(:wallaby)
    Application.put_env(:wallaby, :base_url, PlaysteadWeb.Endpoint.url())
    []
  else
    IO.puts(
      "\n⚠  chromedriver not found on PATH — skipping :browser tests " <>
        "(brew install --cask chromedriver)\n"
    )

    [:browser]
  end

ExUnit.start(exclude: exclude)
Ecto.Adapters.SQL.Sandbox.mode(Playstead.Repo, :manual)
