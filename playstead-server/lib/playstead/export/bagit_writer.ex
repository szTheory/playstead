defmodule Playstead.Export.BagitWriter do
  @moduledoc """
  Writes a minimal but genuinely RFC 8493 compliant bag for one asset
  set (D-34): `bagit.txt`, `bag-info.txt`, `manifest-sha256.txt`,
  `tagmanifest-sha256.txt`, and the payload under `data/`. The manifest
  line format is exactly GNU `sha256sum -c` compatible — lowercase
  hexadecimal, two spaces, bag-relative forward-slash path,
  newline-terminated — because D-34 chose this format so a self-hoster
  can verify an export with coreutils and no Playstead tooling at all.

  Every file is written to a sibling temporary name, fsynced, and
  renamed into place (D-36, RESEARCH Pattern 4); the containing
  directory is fsynced afterward on a best-effort basis (some
  filesystems/platforms do not support fsync on a directory handle).
  The writer refuses a target that is neither empty nor carrying its
  own marker file, and never deletes or overwrites a file it did not
  itself write.

  The full write-then-verify second pass, per-member checkpointing,
  sidecars, and the durable `exports` row are plan 02-07's work — this
  ships the real layout and the real safety rules on the one-set path.
  """

  alias Playstead.Blobs
  alias Playstead.Export.PathSanitizer

  @marker_file ".playstead-bag"

  @doc "Writes `asset_set` (with `asset_members` and each member's `blob` preloaded) into `target_dir`."
  @spec write_bag(String.t(), Playstead.Catalogue.AssetSet.t()) ::
          {:ok, map()} | {:error, term()}
  def write_bag(target_dir, asset_set) do
    with :ok <- check_target(target_dir) do
      File.mkdir_p!(Path.join(target_dir, "data"))

      members = Enum.sort_by(asset_set.asset_members, & &1.ordinal)
      payload_entries = Enum.map(members, &write_member!(target_dir, &1))

      manifest_content = manifest_lines(payload_entries)
      total_bytes = Enum.sum(Enum.map(payload_entries, & &1.size))

      bagit_txt = "BagIt-Version: 1.0\nTag-File-Character-Encoding: UTF-8\n"

      bag_info_txt =
        "Bagging-Date: #{Date.utc_today()}\nPayload-Oxum: #{total_bytes}.#{length(payload_entries)}\n"

      write_file_durably!(Path.join(target_dir, "bagit.txt"), bagit_txt)
      write_file_durably!(Path.join(target_dir, "bag-info.txt"), bag_info_txt)
      write_file_durably!(Path.join(target_dir, "manifest-sha256.txt"), manifest_content)

      tagmanifest_content =
        tagmanifest_lines([
          {"bagit.txt", bagit_txt},
          {"bag-info.txt", bag_info_txt},
          {"manifest-sha256.txt", manifest_content}
        ])

      write_file_durably!(Path.join(target_dir, "tagmanifest-sha256.txt"), tagmanifest_content)
      write_file_durably!(Path.join(target_dir, @marker_file), asset_set.id)

      fsync_dir(target_dir)

      {:ok, %{target_dir: target_dir, payload_entries: payload_entries}}
    end
  end

  defp check_target(target_dir) do
    File.mkdir_p!(target_dir)

    case File.ls(target_dir) do
      {:ok, []} -> :ok
      {:ok, entries} -> if @marker_file in entries, do: :ok, else: {:error, :target_not_empty}
      {:error, _reason} -> :ok
    end
  end

  defp write_member!(target_dir, member) do
    {:ok, safe_name} = safe_member_filename(member)
    {:ok, full_path} = PathSanitizer.resolve_under_root(target_dir, Path.join("data", safe_name))

    write_payload!(full_path, member.blob.sha256)

    %{relative: "data/#{safe_name}", sha256: member.blob.sha256, size: member.blob.size_bytes}
  end

  defp safe_member_filename(member) do
    candidate = member.declared_name || "member-#{member.ordinal}"

    case PathSanitizer.sanitize(candidate) do
      {:ok, name} -> {:ok, name}
      :error -> {:ok, "member-#{member.ordinal}"}
    end
  end

  defp manifest_lines(payload_entries) do
    Enum.map_join(payload_entries, "", fn e -> "#{e.sha256}  #{e.relative}\n" end)
  end

  defp tagmanifest_lines(tag_entries) do
    Enum.map_join(tag_entries, "", fn {name, content} ->
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
