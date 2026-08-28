defmodule PlaysteadWeb.SetupLiveTest do
  use PlaysteadWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Playstead.AccountsFixtures

  alias Playstead.Repo
  alias Playstead.Setup

  defp minted_token do
    ExUnit.CaptureIO.capture_io(fn -> Setup.mint_token() end)
    |> then(fn banner ->
      [_, token] = Regex.run(~r/wizard at \/setup\):\n\n(\S+)\n/, banner)
      token
    end)
  end

  describe "GET /setup" do
    test "renders the wizard while no owner exists", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/setup")
      assert html =~ "Set up Playstead"
      assert html =~ "Setup token"
    end

    test "returns 404 once an owner exists", %{conn: conn} do
      owner_fixture()
      conn = get(conn, ~p"/setup")
      assert conn.status == 404
    end
  end

  describe "the full wizard flow" do
    test "walks token -> credentials -> recovery codes -> readiness -> finish", %{conn: conn} do
      token = minted_token()

      {:ok, lv, _html} = live(conn, ~p"/setup")

      # Step 1: wrong token stays on step 1 with an inline error.
      lv
      |> form("#setup_token_form", %{})
      |> render_submit(%{"setup" => %{"token" => "wrong-token"}})

      assert render(lv) =~ "invalid or has already been used"

      # Step 1: valid token advances to step 2.
      html =
        lv
        |> form("#setup_token_form", %{})
        |> render_submit(%{"setup" => %{"token" => token}})

      assert html =~ "Create your owner account"

      # Step 2: valid owner credentials creates exactly one owner and
      # advances to step 3 (recovery codes shown once).
      html =
        lv
        |> form("#owner_form", %{})
        |> render_submit(%{
          "owner" => %{
            "email" => "owner@example.com",
            "password" => "a very long password",
            "password_confirmation" => "a very long password"
          }
        })

      assert html =~ "Save these recovery codes"
      assert Repo.aggregate(Playstead.Accounts.User, :count) == 1

      # Step 3 -> Step 4: readiness summary renders exactly three checks.
      html = lv |> element("button", "Continue") |> render_click()
      assert html =~ "Database" or html =~ "Checking"

      # Give the async handle_info a chance to run, then re-render.
      html = render(lv)
      assert html =~ "Database"
      assert html =~ "Storage volumes"
      assert html =~ "HTTPS"
      assert html =~ "Set up a backup destination soon"

      # Finish setup navigates to /log-in.
      {:error, {:redirect, %{to: "/log-in"}}} =
        lv |> element("button", "Finish setup") |> render_click()
    end
  end
end
