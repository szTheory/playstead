defmodule Playstead.Export.Verifier do
  @moduledoc """
  The second-pass re-hash that decides an export is verified or
  verification-failed (D-36). Re-opens and re-hashes every payload
  and tag file listed in the bag's manifests and compares each against
  its recorded digest. Never deletes, never rewrites — a mismatch is
  named and the file is left exactly as found so the user decides what
  to do about it.
  """

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

    if mismatches == [] do
      {:ok, %{checked: length(entries)}}
    else
      {:error, {:mismatches, mismatches}}
    end
  end

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
