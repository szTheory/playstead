defmodule Playstead.Import.Inbox do
  @moduledoc """
  The explicit, symlink-safe scan of the read-only host inbox folder
  (D-01, T-02-32). There is no watcher, no polling loop, and no
  filesystem-notification subscription anywhere in this module —
  scanning happens only when a caller invokes `scan/1` from an explicit
  console action.

  Every entry is inspected with the link-not-following stat call
  (`File.lstat/2`, never `File.stat/2`): the container-level read-only
  bind mount protects the host's files from Playstead, not Playstead
  from the host, so a symbolic link inside the inbox pointing elsewhere
  on the container filesystem must never be traversed. A link is
  reported, not walked; a socket, device, or other non-regular entry is
  silently skipped. The scan never opens anything under the inbox for
  writing, renames anything, or removes anything.

  ## Dot-entries are skipped

  Entries whose name begins with `.` are skipped entirely -- files and
  directories alike, before `lstat` is even reached, so a dot-named
  symlink is not reported either.

  This is the one deliberate narrowing of "report every regular file",
  and it exists because the alternative is worse than a missing file: it
  is a permanent phantom. The inbox is a folder a self-hoster opens in a
  file manager, and on macOS merely looking at it makes Finder write
  `.DS_Store` beside the ROMs; a volume picks up `.Trashes`,
  `.Spotlight-V100` and `.fseventsd`; copying from another disk leaves
  `._`-prefixed AppleDouble files. Reported, each becomes an `:unknown`
  entry demanding a decision at `/attention` that the operator never
  made and cannot act on meaningfully -- and `.DS_Store` returns the
  moment the folder is opened again, so excluding it does not settle it.

  Nothing an operator deliberately stages for import is hidden: dot-files
  are invisible in the very file manager they would have used to put them
  there. Skipping them costs no real content and removes an entire class
  of false attention. It also lets the repository keep the dev inbox
  directory alive in git with a tracked `.gitkeep` that the scan will
  never see -- the project must not ship content into a folder it has
  told the operator is theirs.

  Dot-directories are skipped rather than walked, so a ROM buried inside
  `.Trashes` is not imported. That is the intended reading: a file in the
  trash is not staged for import.
  """

  @type entry :: %{relative_path: String.t(), size_bytes: non_neg_integer(), mtime: DateTime.t()}

  @doc """
  Walks `root` and returns the regular files beneath it, in no
  particular order (callers that need a deterministic order, e.g.
  `Playstead.Import.Staging.stage/3`, sort by `relative_path`
  themselves). Symbolic links are reported separately and never
  followed; other non-regular entries are omitted entirely.

  A missing `root` is reported as an empty scan rather than an error —
  the readiness panel is the surface that reports an unreadable inbox
  mount.
  """
  @spec scan(String.t()) :: {:ok, %{files: [entry()], links: [String.t()]}}
  def scan(root) when is_binary(root) do
    if File.dir?(root) do
      {files, links} = walk(root, root)
      {:ok, %{files: files, links: links}}
    else
      {:ok, %{files: [], links: []}}
    end
  end

  defp walk(root, dir) do
    case File.ls(dir) do
      {:ok, names} ->
        names
        |> Enum.sort()
        |> Enum.reject(&dot_entry?/1)
        |> Enum.reduce({[], []}, fn name, {files_acc, links_acc} ->
          path = Path.join(dir, name)

          case File.lstat(path, time: :posix) do
            {:ok, %File.Stat{type: :directory}} ->
              {sub_files, sub_links} = walk(root, path)
              {sub_files ++ files_acc, sub_links ++ links_acc}

            {:ok, %File.Stat{type: :regular} = stat} ->
              {[to_entry(root, path, stat) | files_acc], links_acc}

            {:ok, %File.Stat{type: :symlink}} ->
              {files_acc, [Path.relative_to(path, root) | links_acc]}

            {:ok, _other} ->
              {files_acc, links_acc}

            {:error, _reason} ->
              {files_acc, links_acc}
          end
        end)

      {:error, _reason} ->
        {[], []}
    end
  end

  # Rejected by NAME, before any stat call, so this covers a dot-named
  # regular file, directory and symlink uniformly. See the moduledoc.
  defp dot_entry?(name), do: String.starts_with?(name, ".")

  defp to_entry(root, path, %File.Stat{size: size, mtime: mtime}) do
    %{
      relative_path: Path.relative_to(path, root),
      size_bytes: size,
      mtime: DateTime.from_unix!(mtime) |> DateTime.truncate(:second)
    }
  end
end
