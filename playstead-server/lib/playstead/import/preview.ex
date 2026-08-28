defmodule Playstead.Import.Preview do
  @moduledoc """
  The IMPT-01 pre-copy preview (D-04): everything a user can honestly
  be told about a browser-selected file *before* a single byte moves —
  its name, its exact byte size, the free space available, and how
  much of that free space the copy will use — computed from the same
  `Playstead.Readiness` free-space arithmetic the write-path preflight
  uses.

  Two omissions are deliberate and load-bearing:

    * **No duplicate verdict.** The browser has not hashed the bytes
      yet, so a claim of "already in your library" made here would
      sometimes be wrong. Duplicate status belongs in the receipt,
      after the copy.
    * **The format label is a guess.** It is derived from the file
      extension alone (`Playstead.Catalogue.extension_guess/1`) and
      explicitly marked as such — the magic-byte validators need the
      bytes, which this preview does not have.
  """

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Catalogue
  alias Playstead.Readiness

  @enforce_keys [
    :name,
    :size_bytes,
    :free_bytes,
    :space_bytes,
    :within_ceiling?,
    :fits_free_space?,
    :format_guess
  ]
  defstruct @enforce_keys

  @type format_guess :: %{system: atom() | nil, source: :extension}

  @type t :: %__MODULE__{
          name: String.t(),
          size_bytes: non_neg_integer(),
          free_bytes: non_neg_integer() | :unknown,
          space_bytes: non_neg_integer(),
          within_ceiling?: boolean(),
          fits_free_space?: boolean(),
          format_guess: format_guess()
        }

  @doc """
  Computes the preview for a file named `name` whose browser-declared
  size is `size_bytes` — every field here is knowable from that
  declaration alone, with no bytes read and no hash taken.
  """
  @spec for_upload(String.t(), non_neg_integer()) :: t()
  def for_upload(name, size_bytes) when is_binary(name) and is_integer(size_bytes) do
    blob_path = LocalDisk.blob_path()
    available = Readiness.free_bytes(blob_path)
    capacity = LocalDisk.capacity_bytes(blob_path)

    %__MODULE__{
      name: name,
      size_bytes: size_bytes,
      free_bytes: available,
      space_bytes: size_bytes,
      within_ceiling?: within_ceiling?(size_bytes),
      fits_free_space?: fits_free_space?(size_bytes, available, capacity),
      format_guess: %{system: Catalogue.extension_guess(name), source: :extension}
    }
  end

  defp within_ceiling?(size_bytes) do
    ceiling = Application.get_env(:playstead, :max_browser_upload_bytes, 0)
    not (is_integer(ceiling) and ceiling > 0 and size_bytes > ceiling)
  end

  # Absent a live filesystem reading (e.g. the volume does not exist
  # yet in a fresh dev checkout), degrade gracefully rather than refuse
  # every preview — matches `Playstead.Blobs.Store.LocalDisk`'s own
  # fallback for the same "capacity unknown" case.
  defp fits_free_space?(_size_bytes, :unknown, _capacity), do: true
  defp fits_free_space?(_size_bytes, _available, :unknown), do: true

  defp fits_free_space?(size_bytes, available, capacity)
       when is_integer(available) and is_integer(capacity) do
    Readiness.fits_free_space?(size_bytes, available, capacity)
  end
end
