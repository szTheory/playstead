defmodule Playstead.ImportFixtures do
  @moduledoc """
  Byte-level test helpers shared by every import/export/format test in
  Phase 2. Purely filesystem and digest oriented — no Phase 2 schema
  exists yet, so this module must not depend on one.
  """

  @doc "A deterministic pseudo-random binary of exactly `size` bytes."
  def random_bytes(size) when is_integer(size) and size >= 0 do
    :crypto.strong_rand_bytes(size)
  end

  @doc """
  Writes `bytes` to a fresh temp file and returns
  `{path, sha256_hex, byte_size}`.
  """
  def write_temp_file!(bytes) when is_binary(bytes) do
    path =
      Path.join(
        System.tmp_dir!(),
        "playstead-import-fixture-#{System.unique_integer([:positive])}"
      )

    File.write!(path, bytes)

    sha256_hex = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    {path, sha256_hex, byte_size(bytes)}
  end

  @doc "Writes a zero-byte temp file and returns `{path, sha256_hex, 0}`."
  def zero_byte_file! do
    write_temp_file!(<<>>)
  end

  @doc """
  The known-good SHA-256 hex digest of a fixed short byte string, so a
  test can assert a digest function against a literal rather than
  against itself.

  `known_short_bytes/0` is `"playstead"`; its SHA-256 hex digest is
  computed once here and asserted as a literal in scaffold tests.
  """
  def known_short_bytes, do: "playstead"

  def known_short_bytes_sha256_hex do
    :crypto.hash(:sha256, known_short_bytes()) |> Base.encode16(case: :lower)
  end
end
