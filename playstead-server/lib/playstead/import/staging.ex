defmodule Playstead.Import.Staging do
  @moduledoc """
  The folder-level answer to IMPT-01 (D-04) and the durable staging
  write path for a large collection import (D-01, D-05, D-08, D-10).

  `preview/2` reports everything knowable about a folder without
  hashing a single byte: total file count, total bytes, a
  recognized/unknown/archive histogram (from each file's leading magic
  bytes only), the files above the configured per-file limit, and a
  free-space verdict computed with the same rule the write-path
  preflight uses.

  `stage/3` writes one `Playstead.Import.SourceFile` row per scanned
  file inside a single transaction, in deterministic (relative-path)
  order, refusing a folder above the session file cap before writing
  any row at all.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs.Store.LocalDisk
  alias Playstead.Formats
  alias Playstead.Import.{Inbox, Session, SourceFile}
  alias Playstead.Readiness
  alias Playstead.Repo

  @magic_read_bytes 65_536

  @type histogram :: %{recognized: non_neg_integer(), unknown: non_neg_integer(), archive: non_neg_integer()}

  @type preview :: %{
          file_count: non_neg_integer(),
          total_bytes: non_neg_integer(),
          histogram: histogram(),
          over_limit_files: [map()],
          free_bytes: non_neg_integer() | :unknown,
          fits_free_space?: boolean()
        }

  @doc """
  Computes the staged-folder preview for `root`. Nothing is hashed —
  the histogram classification reads only each file's leading magic
  bytes, the same bounded read `Playstead.Formats.identify/2` already
  performs for a single file.
  """
  @spec preview(String.t(), keyword()) :: preview()
  def preview(root, _opts \\ []) do
    {:ok, %{files: files}} = Inbox.scan(root)

    total_bytes = Enum.reduce(files, 0, &(&1.size_bytes + &2))
    max_per_file = max_per_file_bytes()
    over_limit = Enum.filter(files, &(&1.size_bytes > max_per_file))
    histogram = histogram(root, files)

    capacity = LocalDisk.capacity_bytes()
    available = Readiness.free_bytes()

    %{
      file_count: length(files),
      total_bytes: total_bytes,
      histogram: histogram,
      over_limit_files: over_limit,
      free_bytes: available,
      fits_free_space?: fits_free_space?(total_bytes, available, capacity)
    }
  end

  defp fits_free_space?(_bytes, :unknown, _capacity), do: true
  defp fits_free_space?(_bytes, _available, :unknown), do: true

  defp fits_free_space?(bytes, available, capacity)
       when is_integer(available) and is_integer(capacity) do
    Readiness.fits_free_space?(bytes, available, capacity)
  end

  defp histogram(root, files) do
    Enum.reduce(files, %{recognized: 0, unknown: 0, archive: 0}, fn file, acc ->
      bump(acc, classify(root, file))
    end)
  end

  defp bump(acc, key), do: Map.update!(acc, key, &(&1 + 1))

  defp classify(root, file) do
    path = Path.join(root, file.relative_path)

    case read_leading_bytes(path) do
      {:ok, bytes} ->
        case Formats.identify(bytes, file.relative_path) do
          {:unknown, :container, _evidence} -> :archive
          {:unknown, _tier, _evidence} -> :unknown
          {_system, _tier, _evidence} -> :recognized
        end

      {:error, _reason} ->
        :unknown
    end
  end

  defp read_leading_bytes(path) do
    case File.open(path, [:read, :binary]) do
      {:ok, io} ->
        try do
          case IO.binread(io, @magic_read_bytes) do
            data when is_binary(data) -> {:ok, data}
            :eof -> {:ok, <<>>}
          end
        after
          File.close(io)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp max_per_file_bytes do
    Application.get_env(:playstead, :max_upload_bytes, 0)
  end

  defp max_session_files do
    Application.get_env(:playstead, :max_session_files, 250_000)
  end

  @doc """
  Stages `root` for `user_id` as session `session_id`: writes the
  session row and one `source_files` row per scanned file, sorted by
  relative path, inside one transaction. Refuses with
  `:import_session_too_large` before writing any row when the folder
  holds more files than the configured session cap. An empty folder
  stages successfully as a zero-file, already-complete session.
  """
  @spec stage(pos_integer(), String.t(), String.t()) ::
          {:ok, Session.t()} | {:error, :import_session_too_large} | {:error, term()}
  def stage(user_id, root, session_id) do
    {:ok, %{files: files}} = Inbox.scan(root)
    ordered = Enum.sort_by(files, & &1.relative_path)

    if length(ordered) > max_session_files() do
      {:error, :import_session_too_large}
    else
      do_stage(user_id, root, session_id, ordered)
    end
  end

  defp do_stage(user_id, _root, session_id, ordered) do
    total_bytes = Enum.reduce(ordered, 0, &(&1.size_bytes + &2))

    Repo.transaction(fn ->
      session_attrs = %{
        id: session_id,
        user_id: user_id,
        origin: "inbox",
        file_count: length(ordered),
        total_bytes: total_bytes
      }

      with {:ok, session} <- Repo.insert(Session.create_changeset(%Session{}, session_attrs)) do
        Enum.each(ordered, &insert_source_file_row(user_id, session_id, &1))
        finalize_state = if ordered == [], do: "completed", else: "staged"

        session
        |> Session.state_changeset(finalize_state)
        |> Repo.update!()
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp insert_source_file_row(user_id, session_id, file) do
    attrs = %{
      user_id: user_id,
      import_session_id: session_id,
      original_name: Path.basename(file.relative_path),
      origin: "inbox",
      relative_path: file.relative_path,
      size_bytes: file.size_bytes,
      mtime: file.mtime
    }

    %SourceFile{}
    |> SourceFile.stage_changeset(attrs)
    |> Repo.insert!()
  end
end
