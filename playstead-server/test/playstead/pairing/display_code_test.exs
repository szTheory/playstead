defmodule Playstead.Pairing.DisplayCodeTest do
  use ExUnit.Case, async: true

  alias Playstead.Pairing.DisplayCode

  describe "generate/0" do
    test "returns a code shaped XXXX-XXXX using only the declared alphabet" do
      alphabet = DisplayCode.alphabet() |> List.to_string() |> String.graphemes() |> MapSet.new()

      for _ <- 1..1000 do
        code = DisplayCode.generate()

        assert Regex.match?(~r/^[A-Z]{4}-[A-Z]{4}$/, code)

        code
        |> String.replace("-", "")
        |> String.graphemes()
        |> Enum.each(fn char ->
          assert MapSet.member?(alphabet, char),
                 "#{char} is not in the declared display-code alphabet"
        end)
      end
    end

    test "never emits a vowel or an easily-confused character" do
      forbidden = MapSet.new(~w(A E I O U 0 1))

      for _ <- 1..200 do
        chars =
          DisplayCode.generate()
          |> String.replace("-", "")
          |> String.graphemes()

        assert Enum.all?(chars, fn char -> not MapSet.member?(forbidden, char) end)
      end
    end
  end

  describe "format/1" do
    test "groups an 8-character code into two hyphenated groups of four" do
      assert DisplayCode.format("MKTVQRZC") == "MKTV-QRZC"
    end
  end
end
