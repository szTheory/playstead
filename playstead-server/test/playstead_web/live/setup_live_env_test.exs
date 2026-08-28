defmodule PlaysteadWeb.SetupLiveEnvTest do
  # `async: false` on purpose: the readiness step runs inside the LiveView
  # process, which reads `Playstead.TlsTrust.runtime_env/0` — so transport
  # state has to be injected globally via `:env_overrides`. That is only
  # safe while no other module runs concurrently.
  use PlaysteadWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Playstead.TlsFixtures

  alias Playstead.Setup

  defp minted_token do
    ExUnit.CaptureIO.capture_io(fn -> Setup.mint_token() end)
    |> then(fn banner ->
      [_, token] = Regex.run(~r/wizard at \/setup\):\n\n(\S+)\n/, banner)
      token
    end)
  end

  describe "readiness warnings never block completion" do
    test "a warning row does not disable the Finish setup control", %{conn: conn} do
      put_env_overrides!(%{"PLAYSTEAD_PROXY" => "external"})
      token = minted_token()

      {:ok, lv, _html} = live(conn, ~p"/setup")

      lv
      |> form("#setup_token_form", %{})
      |> render_submit(%{"setup" => %{"token" => token}})

      lv
      |> form("#owner_form", %{})
      |> render_submit(%{
        "owner" => %{
          "email" => "owner@example.com",
          "password" => "a very long password",
          "password_confirmation" => "a very long password"
        }
      })

      lv |> element("button", "Continue") |> render_click()
      html = render(lv)

      assert html =~ "border-[#FBBF24]"
      refute button_disabled?(html)

      # The control is present and clickable — clicking it navigates away,
      # which would be impossible if it were disabled.
      assert {:error, {:redirect, %{to: "/log-in"}}} =
               lv |> element("button", "Finish setup") |> render_click()
    end
  end

  defp button_disabled?(html) do
    html =~ ~r/disabled[^>]*>\s*Finish setup/
  end
end
