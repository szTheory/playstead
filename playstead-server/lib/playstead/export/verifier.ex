defmodule Playstead.Export.Verifier do
  @moduledoc """
  The second-pass re-hash that decides an export is verified or
  verification-failed (D-36). Re-opens and re-hashes every payload
  and tag file listed in the bag's manifests and compares each against
  its recorded digest. Never deletes, never rewrites — a mismatch is
  named and the file is left exactly as found so the user decides what
  to do about it.
  """

  alias Playstead.Export.{Sanitize, Sidecar}

  @chunk_size 1_048_576

  @doc """
  Re-verifies every manifested file under `target_dir`. Returns
  `{:ok, %{checked: n}}` when every listed file's live hash matches, or
  `{:error, {:mismatches, [relative_path]}}` naming every file whose
  live bytes disagree with (or are missing from) the manifest —
  nothing under `target_dir` is ever modified by this call.
  """
  @spec verify(String.t()) ::
          {:ok, %{checked: non_neg_integer()}} | {:error, {:mismatches, [String.t()]}}
  def verify(target_dir) do
    entries =
      manifest_entries(target_dir, "manifest-sha256.txt") ++
        manifest_entries(target_dir, "tagmanifest-sha256.txt")

    mismatches =
      entries
      |> Enum.reject(fn %{relative: relative, sha256: sha256} ->
        matches?(Path.join(target_dir, relative), sha256)
      end)
      |> Enum.map(& &1.relative)

    media_mismatches = verify_private_media(target_dir)
    mismatches = Enum.uniq(mismatches ++ media_mismatches)

    if mismatches == [] do
      {:ok, %{checked: length(entries)}}
    else
      {:error, {:mismatches, mismatches}}
    end
  end

  defp verify_private_media(target_dir) do
    target_dir
    |> Path.join("tags/**/playstead-set.json")
    |> Path.wildcard()
    |> Enum.flat_map(fn sidecar_path ->
      case File.read(sidecar_path) do
        {:ok, content} ->
          case Sidecar.parse(content) do
            {:ok, sidecar} ->
              Enum.map(Map.get(sidecar, "media", []), &verify_media_entry(target_dir, &1))

            :ignore ->
              []
          end

        {:error, _} ->
          []
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp verify_media_entry(target_dir, %{"path" => path, "sha256" => sha, "size_bytes" => size})
       when is_binary(path) and is_binary(sha) and is_integer(size) and size >= 0 do
    safe? = Path.type(path) == :relative and not Enum.member?(Path.split(path), "..")

    with true <- safe?,
         {:ok, full_path} <- Sanitize.safe_join(target_dir, path),
         {:ok, %{size: ^size}} <- File.stat(full_path),
         true <- matches?(full_path, sha) do
      nil
    else
      _ -> "invalid-private-media:#{path}"
    end
  end

  defp verify_media_entry(_target_dir, _entry), do: "invalid-private-media-entry"

  defp manifest_entries(target_dir, manifest_name) do
    path = Path.join(target_dir, manifest_name)

    case File.read(path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.map(fn line ->
          [sha256, relative] = String.split(line, "  ", parts: 2)
          %{sha256: sha256, relative: relative}
        end)

      {:error, _reason} ->
        []
    end
  end

  defp matches?(path, expected_sha256) do
    case hash_file(path) do
      {:ok, sha256} -> sha256 == expected_sha256
      :error -> false
    end
  end

  defp hash_file(path) do
    path
    |> File.stream!([], @chunk_size)
    |> Enum.reduce(:crypto.hash_init(:sha256), &:crypto.hash_update(&2, &1))
    |> :crypto.hash_final()
    |> Base.encode16(case: :lower)
    |> then(&{:ok, &1})
  rescue
    _ -> :error
  end
end
