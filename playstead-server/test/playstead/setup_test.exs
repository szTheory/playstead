defmodule Playstead.SetupTest do
  use Playstead.DataCase

  alias Playstead.Accounts
  alias Playstead.Setup

  import Playstead.AccountsFixtures

  setup do
    # mint_token/0 is boot-only in normal operation (skipped in :test —
    # see Playstead.Application); each test calls it directly so it runs
    # inside this test's own sandboxed connection.
    :ok
  end

  describe "mint_token/0" do
    test "is a no-op once an owner exists" do
      owner_fixture()
      assert Setup.mint_token() == :ok
      assert Repo.aggregate(Playstead.Accounts.SetupToken, :count) == 0
    end

    test "mints and stores a hashed token, printing it to stdout" do
      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert Setup.mint_token() == :ok
        end)

      assert output =~ "Playstead setup token"
      assert Repo.aggregate(Playstead.Accounts.SetupToken, :count) == 1
    end

    test "honors PLAYSTEAD_SETUP_TOKEN and does not print it" do
      System.put_env("PLAYSTEAD_SETUP_TOKEN", "my-override-token")

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert Setup.mint_token() == :ok
        end)

      assert output == ""
      assert Setup.verify_token("my-override-token") == :ok
    after
      System.delete_env("PLAYSTEAD_SETUP_TOKEN")
    end

    test "replaces a prior unconsumed token rather than accumulating rows" do
      ExUnit.CaptureIO.capture_io(fn -> Setup.mint_token() end)
      assert Repo.aggregate(Playstead.Accounts.SetupToken, :count) == 1

      ExUnit.CaptureIO.capture_io(fn -> Setup.mint_token() end)
      assert Repo.aggregate(Playstead.Accounts.SetupToken, :count) == 1
    end
  end

  describe "claim/2" do
    setup do
      token =
        ExUnit.CaptureIO.capture_io(fn -> Setup.mint_token() end)
        |> extract_token()

      %{token: token}
    end

    test "creates exactly one owner with a valid token", %{token: token} do
      assert {:ok, %{user: user, recovery_codes: codes}} =
               Setup.claim(token, valid_owner_attributes())

      assert user.role == :owner
      assert length(codes) == 10
      assert Accounts.owner_exists?()
    end

    test "rejects a wrong token" do
      assert {:error, :invalid_or_expired} = Setup.claim("wrong-token", valid_owner_attributes())
      refute Accounts.owner_exists?()
    end

    test "rejects reuse of an already-consumed token", %{token: token} do
      assert {:ok, _} = Setup.claim(token, valid_owner_attributes())
      assert {:error, :token_already_used} = Setup.claim(token, valid_owner_attributes())
    end

    test "does not consume the token when owner registration fails validation", %{token: token} do
      assert {:error, %Ecto.Changeset{}} =
               Setup.claim(token, valid_owner_attributes(password: "short"))

      # the token is still valid — a fixable typo shouldn't burn it
      assert Setup.verify_token(token) == :ok
    end

    test "two concurrent claims with the same token create exactly one owner", %{token: token} do
      parent = self()

      tasks =
        for _ <- 1..2 do
          Task.async(fn ->
            Ecto.Adapters.SQL.Sandbox.allow(Repo, parent, self())
            Setup.claim(token, valid_owner_attributes())
          end)
        end

      results = Task.await_many(tasks)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :token_already_used}, &1)) == 1

      assert Repo.aggregate(Playstead.Accounts.User, :count) == 1
    end
  end

  defp extract_token(banner) do
    [_, token] = Regex.run(~r/wizard at \/setup\):\n\n(\S+)\n/, banner)
    token
  end
end
