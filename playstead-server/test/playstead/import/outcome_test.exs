defmodule Playstead.Import.OutcomeTest do
  use ExUnit.Case, async: true

  alias Playstead.Import.Outcome
  alias Playstead.Import.Outcome.{FailureReason, QuarantineReason, UnrecognizedReason}

  test "all/0 returns exactly the nine frozen codes" do
    codes = Outcome.all()

    assert length(codes) == 9

    assert MapSet.new(codes) ==
             MapSet.new([
               :new_asset,
               :exact_duplicate,
               :alias,
               :variant,
               :incomplete_set,
               :unrecognized,
               :patched,
               :quarantined,
               :failed_safely
             ])
  end

  test "valid?/1 accepts both the atom and string forms" do
    for code <- Outcome.all() do
      assert Outcome.valid?(code)
      assert Outcome.valid?(to_string(code))
    end
  end

  test "valid?/1 returns false for a code outside the nine" do
    refute Outcome.valid?(:not_a_real_outcome)
    refute Outcome.valid?("not_a_real_outcome")
    refute Outcome.valid?(nil)
    refute Outcome.valid?(123)
  end

  test "the reason sub-vocabularies follow the same atom-or-string shape" do
    for reason <- UnrecognizedReason.all() do
      assert UnrecognizedReason.valid?(reason)
      assert UnrecognizedReason.valid?(to_string(reason))
    end

    for reason <- QuarantineReason.all() do
      assert QuarantineReason.valid?(reason)
    end

    for reason <- FailureReason.all() do
      assert FailureReason.valid?(reason)
    end

    refute UnrecognizedReason.valid?(:bogus)
    refute QuarantineReason.valid?(:bogus)
    refute FailureReason.valid?(:bogus)
  end
end
