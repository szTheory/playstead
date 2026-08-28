defmodule Playstead.Export do
  @moduledoc """
  The export context (D-33, D-34): writes one asset set into an
  ordinary, verifiable folder under the configured export root. Never
  calls `Playstead.Blobs.Store` or `Playstead.Blobs.Store.LocalDisk`
  directly — `Playstead.Blobs.stream/2` is how bytes are read back out.
  """

  import Ecto.Query, warn: false

  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Export.{BagitWriter, PathSanitizer}
  alias Playstead.Repo

  @doc "The configured export root (D-33's PLAYSTEAD_EXPORT_PATH, never a free-form absolute path)."
  @spec export_root() :: String.t()
  def export_root, do: System.get_env("PLAYSTEAD_EXPORT_PATH") || "/app/exports"

  @doc """
  Exports `asset_set_id` (owned by `user_id`) into `target_name`, a
  single sanitized path component resolved under `export_root/0`. A
  target naming an absolute path or containing a parent-directory
  segment is refused before any filesystem call.
  """
  @spec export_set(pos_integer(), binary(), String.t()) ::
          {:ok, map()} | {:error, :invalid_target | :not_found | term()}
  def export_set(user_id, asset_set_id, target_name) do
    with {:ok, _} <- PathSanitizer.sanitize(target_name),
         {:ok, target_dir} <- PathSanitizer.resolve_under_root(export_root(), target_name),
         %AssetSet{} = asset_set <- fetch_asset_set(user_id, asset_set_id) do
      BagitWriter.write_bag(target_dir, asset_set)
    else
      :error -> {:error, :invalid_target}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  defp fetch_asset_set(user_id, asset_set_id) do
    AssetSet
    |> Repo.get_by(id: asset_set_id, user_id: user_id)
    |> case do
      nil ->
        nil

      asset_set ->
        Repo.preload(asset_set,
          asset_members: {from(m in AssetMember, order_by: m.ordinal), [:blob]}
        )
    end
  end
end
