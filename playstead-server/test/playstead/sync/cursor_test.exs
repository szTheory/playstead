defmodule Playstead.Sync.CursorTest do
  use ExUnit.Case, async: true

  alias Playstead.Sync.Cursor

  setup do
    # Cursor.encode/decode reads secret_key_base from the endpoint config
    # (config/test.exs sets one), so no extra setup is needed here.
    :ok
  end

  describe "encode/1 and decode/1" do
    test "round-trips a sequence value" do
      cursor = Cursor.encode(42)
      assert is_binary(cursor)
      assert {:ok, 42} = Cursor.decode(cursor)
    end

    test "round-trips zero" do
      cursor = Cursor.encode(0)
      assert {:ok, 0} = Cursor.decode(cursor)
    end

    test "produces a URL-safe string with no padding characters" do
      cursor = Cursor.encode(123_456_789)
      refute String.contains?(cursor, "+")
      refute String.contains?(cursor, "/")
      refute String.contains?(cursor, "=")
    end

    test "rejects a cursor with a single flipped byte" do
      cursor = Cursor.encode(99)
      {:ok, raw} = Base.url_decode64(cursor, padding: false)

      <<first, rest::binary>> = raw
      tampered = <<Bitwise.bxor(first, 0x01), rest::binary>>
      tampered_cursor = Base.url_encode64(tampered, padding: false)

      assert :error = Cursor.decode(tampered_cursor)
    end

    test "rejects a truncated cursor" do
      cursor = Cursor.encode(99)
      truncated = String.slice(cursor, 0, 10)

      assert :error = Cursor.decode(truncated)
    end

    test "rejects a cursor signed with a different secret" do
      payload = <<99::unsigned-big-integer-size(64)>>
      wrong_tag = :crypto.mac(:hmac, :sha256, "a-completely-different-secret", payload)
      forged = Base.url_encode64(payload <> wrong_tag, padding: false)

      assert :error = Cursor.decode(forged)
    end

    test "rejects garbage input" do
      assert :error = Cursor.decode("not-a-real-cursor")
      assert :error = Cursor.decode("")
    end
  end
end
