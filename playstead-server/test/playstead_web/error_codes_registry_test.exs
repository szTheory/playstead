defmodule PlaysteadWeb.ErrorCodesRegistryTest do
  use ExUnit.Case, async: true

  alias PlaysteadWeb.ErrorCodes

  describe "D-10 import/export problem codes" do
    test "import_file_too_large maps to 413" do
      assert ErrorCodes.status_for(:import_file_too_large) == 413
    end

    test "storage_insufficient maps to 507" do
      assert ErrorCodes.status_for(:storage_insufficient) == 507
    end

    test "import_digest_mismatch maps to 422" do
      assert ErrorCodes.status_for(:import_digest_mismatch) == 422
    end

    test "upload_length_required maps to 411" do
      assert ErrorCodes.status_for(:upload_length_required) == 411
    end

    test "import_empty_file maps to 422" do
      assert ErrorCodes.status_for(:import_empty_file) == 422
    end

    test "too_many_uploads maps to 429" do
      assert ErrorCodes.status_for(:too_many_uploads) == 429
    end

    test "import_session_too_large maps to 422" do
      assert ErrorCodes.status_for(:import_session_too_large) == 422
    end

    test "each code also has a non-empty title" do
      for code <- [
            :import_file_too_large,
            :storage_insufficient,
            :import_digest_mismatch,
            :upload_length_required,
            :import_empty_file,
            :too_many_uploads,
            :import_session_too_large
          ] do
        assert is_binary(ErrorCodes.title_for(code))
        assert ErrorCodes.title_for(code) != ""
      end
    end
  end
end
