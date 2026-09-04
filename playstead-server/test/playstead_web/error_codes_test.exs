defmodule PlaysteadWeb.ErrorCodesTest do
  @moduledoc """
  D-13/D-24/D-33: the six save-domain problem codes must resolve to
  their decided statuses and be registered — a code that falls through
  to the 500 default is a registration failure, not a valid answer.
  Asserts statuses only, never English titles (the moduledoc states
  titles are never load-bearing).
  """

  use ExUnit.Case, async: true

  alias PlaysteadWeb.ErrorCodes

  describe "save-domain problem codes" do
    test "save_binding_incompatible maps to 422" do
      assert ErrorCodes.status_for(:save_binding_incompatible) == 422
    end

    test "save_revision_digest_mismatch maps to 422" do
      assert ErrorCodes.status_for(:save_revision_digest_mismatch) == 422
    end

    test "save_revision_too_large maps to 413" do
      assert ErrorCodes.status_for(:save_revision_too_large) == 413
    end

    test "save_parent_unknown maps to 409" do
      assert ErrorCodes.status_for(:save_parent_unknown) == 409
    end

    test "save_branch_limit_exceeded maps to 422" do
      assert ErrorCodes.status_for(:save_branch_limit_exceeded) == 422
    end

    test "save_revision_immutable maps to 409" do
      assert ErrorCodes.status_for(:save_revision_immutable) == 409
    end

    test "every save code is registered — none falls through to the 500 default" do
      codes = [
        :save_binding_incompatible,
        :save_revision_digest_mismatch,
        :save_revision_too_large,
        :save_parent_unknown,
        :save_branch_limit_exceeded,
        :save_revision_immutable
      ]

      registry = ErrorCodes.registry()

      for code <- codes do
        assert Map.has_key?(registry, code), "#{code} is missing from the registry"
      end
    end
  end
end
