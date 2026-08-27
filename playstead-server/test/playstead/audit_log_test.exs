defmodule Playstead.AuditLogTest do
  use Playstead.DataCase, async: true

  alias Playstead.AuditLog
  alias Playstead.AuditLog.Entry

  import Playstead.AccountsFixtures

  describe "record/3" do
    test "inserts an audit entry with event, subject, and metadata" do
      user = owner_fixture()

      assert {:ok, %Entry{} = entry} =
               AuditLog.record(user.id, :session_revoked, %{subject: "42", reason: "manual"})

      assert entry.user_id == user.id
      assert entry.event == "session_revoked"
      assert entry.subject == "42"
      assert entry.metadata == %{"reason" => "manual"}
    end

    test "defaults metadata to an empty map" do
      user = owner_fixture()

      assert {:ok, %Entry{metadata: %{}}} = AuditLog.record(user.id, :sudo_confirmed)
    end

    test "carries no update or delete function" do
      refute function_exported?(AuditLog, :update, 2)
      refute function_exported?(AuditLog, :update, 3)
      refute function_exported?(AuditLog, :delete, 1)
      refute function_exported?(AuditLog, :delete, 2)
    end
  end

  describe "list/2" do
    test "returns entries for a user, most recent first" do
      user = owner_fixture()
      {:ok, _} = AuditLog.record(user.id, :sudo_confirmed, %{})
      {:ok, second} = AuditLog.record(user.id, :session_revoked, %{subject: "1"})

      [most_recent | _] = AuditLog.list(user.id)
      assert most_recent.id == second.id
    end
  end
end
