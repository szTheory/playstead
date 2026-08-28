defmodule Playstead.Import.ScaffoldTest do
  @moduledoc """
  Proves `Playstead.ImportFixtures` produces the digest/size it claims,
  and that `test/playstead/import/` is on the `mix test` path.
  """

  use ExUnit.Case, async: true

  import Playstead.ImportFixtures

  test "random_bytes/1 returns exactly the requested number of bytes" do
    assert byte_size(random_bytes(0)) == 0
    assert byte_size(random_bytes(37)) == 37
    assert byte_size(random_bytes(4096)) == 4096
  end

  test "write_temp_file!/1 returns the correct path, digest, and size" do
    bytes = random_bytes(1024)
    expected_sha256 = :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

    {path, sha256_hex, size} = write_temp_file!(bytes)

    assert File.read!(path) == bytes
    assert sha256_hex == expected_sha256
    assert size == 1024

    File.rm(path)
  end

  test "zero_byte_file!/0 writes an empty file with the empty-string SHA-256" do
    {path, sha256_hex, size} = zero_byte_file!()

    assert File.read!(path) == <<>>
    assert size == 0

    assert sha256_hex ==
             "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    File.rm(path)
  end

  test "known_short_bytes_sha256_hex/0 matches an independently computed literal" do
    assert known_short_bytes() == "playstead"

    assert known_short_bytes_sha256_hex() ==
             "aad8fab8d1e9a8dbd9e13433fa89d110e18f9360f40c9f2a95a8e3e53294b811"
  end
end
