defmodule Playstead.Export.BagitWriter do
  @moduledoc """
  Writes a genuinely RFC 8493 compliant bag for a `Playstead.Export.Layout`
  plan: `bagit.txt`, `bag-info.txt`, `manifest-sha256.txt`,
  `tagmanifest-sha256.txt`, a root sidecar, one sidecar per set, and the
  payload under `data/`. The manifest line format is exactly GNU
  `sha256sum -c` compatible — lowercase hexadecimal, two spaces,
  bag-relative forward-slash path, newline-terminated (D-34).

  `manifest-sha256.txt` lists payload bytes only (every file under
  `data/`); the root and per-set sidecars are tag files (under `tags/`)
  and are covered by `tagmanifest-sha256.txt` instead, keeping the
  payload manifest exactly the set of game bytes a self-hoster expects
  to verify.

  Every file is written to a sibling temporary name, fsynced, and
  renamed into place (D-36, RESEARCH Pattern 4); the containing
  directory is fsynced afterward on a best-effort basis. The writer
  refuses a target that is neither empty nor carrying its own marker
  file, and never deletes or overwrites a file it did not itself
  write.
  """

  alias Playstead.Blobs
  alias Playstead.Export.{Sanitize, SavesPlan, Sidecar}

  @marker_file ".playstead-bag"
  @bagit_profile_identifier "https://playstead.example/bagit-profile.json"

  @doc """
  Writes `layout` (the output of `Playstead.Export.Layout.plan/2`) into
  `target_dir`.
  """
  @spec write_bag(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def write_bag(target_dir, layout) do
    with :ok <- check_target(target_dir) do
      payload_entries = write_payload(target_dir, layout)
      tag_entries = write_sidecars(target_dir, layout)

      manifest_content = manifest_lines(payload_entries)
      total_bytes = Enum.sum(Enum.map(payload_entries, &(&1.size_bytes || 0)))

      bagit_txt = "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n"

      bag_info_txt =
        "Bagging-Date: #{Date.utc_today()}\n" <>
          "Payload-Oxum: #{total_bytes}.#{length(payload_entries)}\n" <>
          "BagIt-Profile-Identifier: #{@bagit_profile_identifier}\n"

      write_file_durably!(Path.join(target_dir, "bagit.txt"), bagit_txt)
      write_file_durably!(Path.join(target_dir, "bag-info.txt"), bag_info_txt)
      write_file_durably!(Path.join(target_dir, "manifest-sha256.txt"), manifest_content)

      root_sidecar_content = Sidecar.encode(Sidecar.root())
      write_file_durably!(Path.join(target_dir, "playstead-bag.json"), root_sidecar_content)

      readme_content = readme_text()
      write_file_durably!(Path.join(target_dir, "README.txt"), readme_content)

      tagmanifest_content =
        tagmanifest_lines(
          [
            {"bagit.txt", bagit_txt},
            {"bag-info.txt", bag_info_txt},
            {"manifest-sha256.txt", manifest_content},
            {"playstead-bag.json", root_sidecar_content},
            {"README.txt", readme_content}
          ] ++ tag_entries
        )

      write_file_durably!(Path.join(target_dir, "tagmanifest-sha256.txt"), tagmanifest_content)
      write_file_durably!(Path.join(target_dir, @marker_file), marker_content(layout))

      fsync_dir(target_dir)

      {:ok, %{target_dir: target_dir, payload_entries: payload_entries}}
    end
  end

  defp marker_content(%{sets: [%{set_id: set_id}]}), do: set_id
  defp marker_content(_layout), do: "playstead-export"

  # The written material accompanying every export (D-40): read from a
  # static asset rather than a string literal in this module, so its
  # exact wording — including the explicit "not a backup" statement —
  # lives once, in one file, instead of being duplicated (and risking
  # drift) across every writer.
  defp readme_text do
    :playstead
    |> Application.app_dir("priv/static/export-readme.txt")
    |> File.read!()
  end

  defp check_target(target_dir) do
    File.mkdir_p!(target_dir)

    case File.ls(target_dir) do
      {:ok, []} -> :ok
      {:ok, entries} -> if @marker_file in entries, do: :ok, else: {:error, :target_not_empty}
      {:error, _reason} -> :ok
    end
  end

  defp write_payload(target_dir, %{sets: sets, quarantine: quarantine}) do
    set_entries =
      Enum.flat_map(sets, fn set_plan ->
        Enum.map(set_plan.members, &write_member!(target_dir, &1)) ++
          write_saves_payload!(target_dir, set_plan)
      end)

    quarantine_entries = Enum.map(quarantine, &write_quarantine_member!(target_dir, &1))

    (set_entries ++ quarantine_entries) |> Enum.sort_by(& &1.relative)
  end

  # D-61: a revision whose bytes never uploaded is written into the
  # sidecar as missing (`Sidecar.saves_sidecar/1`) but is never opened,
  # streamed, or hashed here -- its manifest entry carries `sha256:
  # nil`, so `manifest_lines/1`'s existing `Enum.filter(& &1.sha256)`
  # excludes it automatically, exactly like a member with no blob.
  defp write_saves_payload!(target_dir, set_plan) do
    saves_plan = Map.get(set_plan, :saves_plan)

    if saves_plan do
      revision_entries = Enum.map(saves_plan.entries, &write_save_entry!(target_dir, &1))

      drop_in_entries =
        case saves_plan.drop_in do
          nil -> []
          drop_in -> [write_save_entry!(target_dir, drop_in)]
        end

      revision_entries ++ drop_in_entries
    else
      []
    end
  end

  defp write_save_entry!(target_dir, entry) do
    relative = Path.join("data", entry.relative)

    if Map.get(entry, :bytes, :present) == :present do
      {:ok, full_path} = Sanitize.safe_join(target_dir, relative)
      write_payload!(full_path, entry.sha256)
      %{relative: relative, sha256: entry.sha256, size_bytes: entry.size_bytes}
    else
      %{relative: relative, sha256: nil, size_bytes: entry.size_bytes}
    end
  end

  defp write_member!(target_dir, member) do
    relative = Path.join("data", member.relative)
    {:ok, full_path} = Sanitize.safe_join(target_dir, relative)

    if member.sha256 do
      write_payload!(full_path, member.sha256)
    end

    %{relative: relative, sha256: member.sha256, size_bytes: member.size_bytes}
  end

  defp write_quarantine_member!(target_dir, entry) do
    relative = Path.join("data", entry.relative)
    {:ok, full_path} = Sanitize.safe_join(target_dir, relative)

    write_payload!(full_path, entry.sha256)

    %{relative: relative, sha256: entry.sha256, size_bytes: entry.size_bytes}
  end

  defp write_sidecars(target_dir, %{sets: sets}) do
    Enum.flat_map(sets, fn set_plan ->
      relative = Path.join("tags", Path.join(set_plan.relative_dir, "playstead-set.json"))
      {:ok, full_path} = Sanitize.safe_join(target_dir, relative)
      content = Sidecar.encode(Sidecar.set(set_plan))
      write_file_durably!(full_path, content)

      saves_txt_relative = Path.join("tags", Path.join(set_plan.relative_dir, "saves.txt"))
      {:ok, saves_txt_full_path} = Sanitize.safe_join(target_dir, saves_txt_relative)
      saves_txt_content = saves_txt(set_plan)
      write_file_durably!(saves_txt_full_path, saves_txt_content)

      [{relative, content}, {saves_txt_relative, saves_txt_content}]
    end)
  end

  # D-60: the "readable" half of "readable manifest" -- one plain-text
  # line per exported revision, grouped by branch, with the shared
  # (unlettered) history first. No tooling required to read it.
  defp saves_txt(set_plan) do
    saves_plan = Map.get(set_plan, :saves_plan, SavesPlan.plan([]))
    header = "Save history — #{set_plan.display_title}\n\n"

    body =
      if saves_plan.entries == [] do
        "No save revisions recorded for this title.\n"
      else
        saves_plan.branches
        |> Enum.map(&format_save_branch/1)
        |> Enum.join("\n\n")
        |> Kernel.<>("\n")
      end

    header <> body
  end

  defp format_save_branch(%{branch: branch, revisions: revisions}) do
    label = if branch, do: "Branch #{branch}", else: "Shared history"

    lines =
      Enum.map(revisions, fn r ->
        missing =
          if Map.get(r, :bytes, :present) == :missing, do: " (not on this server)", else: ""

        seq = r.seq |> Integer.to_string() |> String.pad_leading(3, " ")
        "  #{seq}  #{Path.basename(r.relative)}  #{r.sha256}  #{r.size_bytes} bytes#{missing}"
      end)

    Enum.join([label | lines], "\n")
  end

  defp manifest_lines(payload_entries) do
    payload_entries
    |> Enum.filter(& &1.sha256)
    |> Enum.sort_by(& &1.relative)
    |> Enum.map_join("", fn e -> "#{e.sha256}  #{e.relative}\n" end)
  end

  defp tagmanifest_lines(tag_entries) do
    tag_entries
    |> Enum.sort_by(fn {name, _content} -> name end)
    |> Enum.map_join("", fn {name, content} ->
      sha256 = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
      "#{sha256}  #{name}\n"
    end)
  end

  # Resumable by construction (D-36): a file already present at
  # `dest_path` whose content already re-hashes to `sha256` is left
  # completely untouched — not opened for writing, not renamed over
  # itself — so re-running `write_bag/2` against a partially-written
  # target only rewrites what is actually missing or mismatched.
  defp write_payload!(dest_path, sha256) do
    if matches_hash?(dest_path, sha256) do
      :ok
    else
      File.mkdir_p!(Path.dirname(dest_path))
      tmp_path = tmp_sibling(dest_path)

      {:ok, stream} = Blobs.stream(sha256)
      {:ok, io} = File.open(tmp_path, [:write, :binary, :raw])

      Enum.each(stream, fn chunk -> :file.write(io, chunk) end)

      :file.sync(io)
      File.close(io)
      File.rename!(tmp_path, dest_path)
    end
  end

  defp matches_hash?(path, expected_sha256) do
    case File.read(path) do
      {:ok, content} ->
        :crypto.hash(:sha256, content) |> Base.encode16(case: :lower) == expected_sha256

      {:error, _reason} ->
        false
    end
  end

  # Same resume rule as `write_payload!/2`: an already-present tag file
  # whose bytes already match `content` exactly is left untouched.
  defp write_file_durably!(path, content) do
    if File.regular?(path) and File.read!(path) == content do
      :ok
    else
      File.mkdir_p!(Path.dirname(path))
      tmp_path = tmp_sibling(path)
      File.write!(tmp_path, content)

      {:ok, io} = File.open(tmp_path, [:read, :write])
      :file.sync(io)
      File.close(io)

      File.rename!(tmp_path, path)
    end
  end

  defp tmp_sibling(path) do
    "#{path}.tmp-#{System.unique_integer([:positive, :monotonic])}"
  end

  defp fsync_dir(path) do
    case File.open(path, [:raw, :read]) do
      {:ok, io} ->
        :file.sync(io)
        File.close(io)
        :ok

      {:error, _reason} ->
        :ok
    end
  rescue
    _ -> :ok
  end
end
