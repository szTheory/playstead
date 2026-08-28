defmodule Playstead.Attention.DeriveTest do
  @moduledoc """
  Unit-level proof of the single in-and-out rule (D-26): every
  inclusion case raises exactly one reason, and every exclusion case
  raises nothing. Deliberately independent of the database — this is
  a pure decision function.
  """
  use ExUnit.Case, async: true

  alias Playstead.Attention.Derive

  describe "inclusion cases" do
    test "an incomplete set needs attention" do
      assert Derive.attention_reason(%{outcome: :incomplete_set}) == :missing_member
    end

    test "a quarantined input needs attention" do
      assert Derive.attention_reason(%{outcome: :quarantined, reason: "size_over_cap"}) ==
               :quarantined
    end

    test "a detected patch file needs attention" do
      assert Derive.attention_reason(%{outcome: :patched}) == :patch_file_detected
    end

    test "a failure that exhausted retries needs attention" do
      ctx = %{outcome: :failed_safely, retries_exhausted?: true}
      assert Derive.attention_reason(ctx) == :failed_after_retries
    end

    test "a failure still within its retry budget does not need attention" do
      ctx = %{outcome: :failed_safely, retries_exhausted?: false}
      refute Derive.needs_attention?(ctx)
    end

    test "an ambiguous recognition needs attention" do
      ctx = %{outcome: :unrecognized, reason: "ambiguous"}
      assert Derive.attention_reason(ctx) == :ambiguous_recognition
    end

    test "a signature-mismatched recognition needs attention" do
      ctx = %{outcome: :unrecognized, reason: "signature_mismatch"}
      assert Derive.attention_reason(ctx) == :signature_mismatch
    end

    test "an unknown system needs attention" do
      assert Derive.attention_reason(%{unknown_system?: true}) == :unknown_system
    end

    test "an extension-versus-header contradiction needs attention as confirm-system" do
      ctx = %{system_confirmation_needed?: true, outcome: :new_asset}
      assert Derive.attention_reason(ctx) == :confirm_system
    end

    test "archives kept unopened need attention" do
      ctx = %{outcome: :unrecognized, reason: "archive_not_opened"}
      assert Derive.attention_reason(ctx) == :archives_kept_unopened
    end
  end

  describe "exclusion cases (D-26)" do
    test "a new asset produces no item" do
      refute Derive.needs_attention?(%{outcome: :new_asset})
    end

    test "an exact duplicate produces no item" do
      refute Derive.needs_attention?(%{outcome: :exact_duplicate})
    end

    test "a clean alias produces no item" do
      refute Derive.needs_attention?(%{outcome: :alias})
    end

    test "a clean variant produces no item" do
      refute Derive.needs_attention?(%{outcome: :variant})
    end

    test "content with no reference installed produces no item" do
      ctx = %{outcome: :unrecognized, reason: "no_reference_installed"}
      refute Derive.needs_attention?(ctx)
    end

    test "unrecognized with no match at all produces no item" do
      ctx = %{outcome: :unrecognized, reason: "no_match"}
      refute Derive.needs_attention?(ctx)
    end
  end
end
