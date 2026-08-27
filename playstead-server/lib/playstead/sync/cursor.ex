defmodule Playstead.Sync.Cursor do
  @moduledoc """
  The opaque, HMAC-SHA256-signed cursor over a change-journal sequence
  position (PROT-05, D-21).

  A cursor encodes position only — never identity and never
  authorization (T-01-44). Tampering with it can at most produce an
  invalid or expired cursor; per-owner partitioning is enforced
  independently by `Playstead.Sync.ChangeJournal.read_after/3` regardless
  of what a decoded cursor contains, so even a fully valid cursor cannot
  cross owners.

  The wire format is `<8-byte big-endian seq><32-byte HMAC-SHA256 tag>`,
  URL-safe base64-encoded without padding. This is a hand-rolled
  opaque-cursor primitive, not a generic Ecto cursor-pagination
  library — RESEARCH.md Pitfall 4 is explicit that those libraries solve
  stable list pagination, not change-feed convergence, and have no
  concept of a stale-versus-exhausted cursor.
  """

  @tag_bytes 32
  @payload_bytes 8

  @doc "Encodes a non-negative journal sequence as an opaque, signed cursor string."
  @spec encode(non_neg_integer()) :: String.t()
  def encode(seq) when is_integer(seq) and seq >= 0 do
    payload = <<seq::unsigned-big-integer-size(64)>>
    tag = :crypto.mac(:hmac, :sha256, signing_secret(), payload)
    Base.url_encode64(payload <> tag, padding: false)
  end

  @doc """
  Decodes and verifies an opaque cursor. Rejects a cursor that is
  malformed, truncated, tampered with (even a single flipped byte), or
  signed with a different secret — all indistinguishably, as `:error`.
  """
  @spec decode(String.t()) :: {:ok, non_neg_integer()} | :error
  def decode(cursor) when is_binary(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         <<payload::binary-size(@payload_bytes), tag::binary-size(@tag_bytes)>> <- decoded,
         expected_tag <- :crypto.mac(:hmac, :sha256, signing_secret(), payload),
         true <- Plug.Crypto.secure_compare(tag, expected_tag) do
      <<seq::unsigned-big-integer-size(64)>> = payload
      {:ok, seq}
    else
      _ -> :error
    end
  end

  def decode(_cursor), do: :error

  # Derives a stable signing key from the application's own secret_key_base
  # rather than storing a separate cursor-specific secret (config/runtime.exs
  # is where secret_key_base is sourced).
  defp signing_secret do
    base = Application.fetch_env!(:playstead, PlaysteadWeb.Endpoint)[:secret_key_base]
    :crypto.mac(:hmac, :sha256, base, "playstead.sync.cursor.v1")
  end
end
