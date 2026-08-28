defmodule Playstead.Import.PreviewTest do
  use ExUnit.Case, async: true

  alias Playstead.Import.Preview

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  test "reports the exact byte size, the free space, and the space the copy will use" do
    preview = Preview.for_upload("game.gba", 12_345)

    assert preview.name == "game.gba"
    assert preview.size_bytes == 12_345
    assert preview.space_bytes == 12_345
    assert is_integer(preview.free_bytes) or preview.free_bytes == :unknown
  end

  test "carries no duplicate verdict field" do
    preview = Preview.for_upload("game.gba", 100)

    refute Map.has_key?(preview, :duplicate)
    refute Map.has_key?(preview, :duplicate?)
  end

  test "the format label is marked as extension-derived" do
    preview = Preview.for_upload("Sonic (USA).gba", 100)

    assert preview.format_guess.source == :extension
    assert preview.format_guess.system == :gba
  end

  test "an unrecognized extension reports a nil format guess, still marked as an extension source" do
    preview = Preview.for_upload("mystery.xyz", 100)

    assert preview.format_guess == %{system: nil, source: :extension}
  end

  test "a file whose size equals the configured browser ceiling is accepted" do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes)

    preview = Preview.for_upload("game.gba", ceiling)

    assert preview.within_ceiling?
  end

  test "a file one byte above the browser ceiling is refused" do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes)

    preview = Preview.for_upload("game.gba", ceiling + 1)

    refute preview.within_ceiling?
  end

  test "a file exceeding the free-space margin is refused" do
    preview = Preview.for_upload("huge.gba", 999_999_999_999_999)

    refute preview.fits_free_space?
  end

  test "a tiny file fits free space" do
    preview = Preview.for_upload("tiny.gba", 1)

    assert preview.fits_free_space?
  end
end
