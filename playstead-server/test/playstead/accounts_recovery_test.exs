defmodule Playstead.AccountsRecoveryTest do
  use Playstead.DataCase, async: true

  alias Playstead.{Accounts, AuditLog, Release}
  alias Playstead.Accounts.Scope

  import Playstead.AccountsFixtures

  describe "Release.reset_owner_password/0" do
    test "prints a single-use reset URL and returns :ok" do
      owner_fixture()

      output =
        ExUnit.CaptureIO.capture_io(fn ->
          assert :ok = Release.reset_owner_password()
        end)

      assert output =~ "/reset/"
    end

    test "deletes all existing session tokens for the owner" do
      user = owner_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.get_user_by_session_token(token)

      ExUnit.CaptureIO.capture_io(fn -> Release.reset_owner_password() end)

      refute Accounts.get_user_by_session_token(token)
    end

    test "writes a password_reset_issued audit entry" do
      user = owner_fixture()

      ExUnit.CaptureIO.capture_io(fn -> Release.reset_owner_password() end)

      [entry] = AuditLog.list(user.id)
      assert entry.event == "password_reset_issued"
    end

    test "returns :error and prints a message when no owner exists yet" do
      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert :error = Release.reset_owner_password()
        end)

      assert output =~ "run the setup wizard first"
    end
  end

  describe "Accounts.reset_password_with_token/2" do
    setup do
      user = owner_fixture()
      {url_token, user_token} = Accounts.UserToken.build_hashed_token(user, "password_reset")
      Playstead.Repo.insert!(user_token)
      %{user: user, token: url_token}
    end

    test "allows setting a new password", %{token: token} do
      assert {:ok, {_user, _expired}} =
               Accounts.reset_password_with_token(token, %{
                 password: "a brand new password!",
                 password_confirmation: "a brand new password!"
               })
    end

    test "a reset token cannot be consumed twice", %{token: token} do
      attrs = %{password: "a brand new password!", password_confirmation: "a brand new password!"}

      assert {:ok, _} = Accounts.reset_password_with_token(token, attrs)
      assert {:error, :invalid_or_expired} = Accounts.reset_password_with_token(token, attrs)
    end

    test "rejects an expired token", %{user: user} do
      {url_token, user_token} = Accounts.UserToken.build_hashed_token(user, "password_reset")

      user_token
      |> Ecto.Changeset.change(inserted_at: DateTime.add(DateTime.utc_now(:second), -2, :hour))
      |> Playstead.Repo.insert!()

      attrs = %{password: "a brand new password!", password_confirmation: "a brand new password!"}
      assert {:error, :invalid_or_expired} = Accounts.reset_password_with_token(url_token, attrs)
    end

    test "rejects an unknown token" do
      attrs = %{password: "a brand new password!", password_confirmation: "a brand new password!"}

      assert {:error, :invalid_or_expired} =
               Accounts.reset_password_with_token("not-a-real-token", attrs)
    end
  end

  describe "Accounts.consume_recovery_code/2 (recovery login path)" do
    test "a consumed recovery code cannot be reused" do
      user = owner_fixture()
      [code | _] = Accounts.generate_recovery_codes(user, 3)

      assert {:ok, _user} = Accounts.consume_recovery_code(user, code)
      assert {:error, :invalid_code} = Accounts.consume_recovery_code(user, code)
    end

    test "records a recovery_code_consumed audit entry" do
      user = owner_fixture()
      [code | _] = Accounts.generate_recovery_codes(user, 3)

      assert {:ok, _} = Accounts.consume_recovery_code(user, code)

      [entry] = AuditLog.list(user.id)
      assert entry.event == "recovery_code_consumed"
    end
  end

  describe "Accounts.regenerate_recovery_codes/1" do
    test "invalidates the existing codes and returns a fresh set" do
      user = owner_fixture()
      [old_code | _] = Accounts.generate_recovery_codes(user, 3)

      assert {:ok, new_codes} = Accounts.regenerate_recovery_codes(user, 3)
      assert length(new_codes) == 3

      assert {:error, :invalid_code} = Accounts.consume_recovery_code(user, old_code)
      assert {:ok, _} = Accounts.consume_recovery_code(user, hd(new_codes))
    end
  end

  describe "sudo gate on recovery-code regeneration" do
    test "revoke_session and regenerate_recovery_codes never cross accounts" do
      user_a = owner_fixture()
      user_b = owner_fixture()
      token = Accounts.generate_user_session_token(user_a)
      [session] = Accounts.list_sessions(Scope.for_user(user_a))

      assert {:error, :not_found} = Accounts.revoke_session(Scope.for_user(user_b), session.id)
      assert Accounts.get_user_by_session_token(token)
    end
  end
end
