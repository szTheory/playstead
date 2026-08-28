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
  alias Playstead.Export.{Sanitize, Sidecar}

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

      tagmanifest_content =
        tagmanifest_lines(
          [
            {"bagit.txt", bagit_txt},
            {"bag-info.txt", bag_info_txt},
            {"manifest-sha256.txt", manifest_content},
            {"playstead-bag.json", root_sidecar_content}
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
        Enum.map(set_plan.members, &write_member!(target_dir, &1))
      end)

    quarantine_entries = Enum.map(quarantine, &write_quarantine_member!(target_dir, &1))

    (set_entries ++ quarantine_entries) |> Enum.sort_by(& &1.relative)
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
    Enum.map(sets, fn set_plan ->
      relative = Path.join("tags", Path.join(set_plan.relative_dir, "playstead-set.json"))
      {:ok, full_path} = Sanitize.safe_join(target_dir, relative)
      content = Sidecar.encode(Sidecar.set(set_plan))
      write_file_durably!(full_path, content)
      {relative, content}
    end)
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

  defp write_payload!(dest_path, sha256) do
    File.mkdir_p!(Path.dirname(dest_path))
    tmp_path = tmp_sibling(dest_path)

    {:ok, stream} = Blobs.stream(sha256)
    {:ok, io} = File.open(tmp_path, [:write, :binary, :raw])

    Enum.each(stream, fn chunk -> :file.write(io, chunk) end)

    :file.sync(io)
    File.close(io)
    File.rename!(tmp_path, dest_path)
  end

  defp write_file_durably!(path, content) do
    File.mkdir_p!(Path.dirname(path))
    tmp_path = tmp_sibling(path)
    File.write!(tmp_path, content)

    {:ok, io} = File.open(tmp_path, [:read, :write])
    :file.sync(io)
    File.close(io)

    File.rename!(tmp_path, path)
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
