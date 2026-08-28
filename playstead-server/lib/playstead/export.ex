defmodule Playstead.Export do
  @moduledoc """
  The export context (D-33, D-34): writes asset sets into an ordinary,
  verifiable folder under the configured export root. Never calls
  `Playstead.Blobs.Store` or `Playstead.Blobs.Store.LocalDisk`
  directly — `Playstead.Blobs.stream/2` is how bytes are read back
  out.
  """

  import Ecto.Query, warn: false

  alias Playstead.AuditLog
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Export.{BagitWriter, ExportRecord, Layout, Sanitize, Worker}
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
    with {:ok, target_dir} <- resolve_target(target_name),
         %AssetSet{} = asset_set <- fetch_asset_set(user_id, asset_set_id) do
      layout = Layout.plan([to_layout_input(asset_set)], include_excluded: true)
      BagitWriter.write_bag(target_dir, layout)
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :not_found}
      other -> other
    end
  end

  @doc """
  Resolves and validates `target_name` under `export_root/0`. Rejects
  a target that is an absolute path, contains a parent-directory
  segment, or otherwise requires rewriting — an export target must be
  supplied exactly safe, never merely made safe.
  """
  @spec resolve_target(String.t()) :: {:ok, String.t()} | {:error, :invalid_target}
  def resolve_target(target_name) when is_binary(target_name) do
    if Sanitize.safe?(target_name) do
      case Sanitize.safe_join(export_root(), target_name) do
        {:ok, dir} -> {:ok, dir}
        :error -> {:error, :invalid_target}
      end
    else
      {:error, :invalid_target}
    end
  end

  def resolve_target(_target_name), do: {:error, :invalid_target}

  @doc "Converts a preloaded `AssetSet` into the `Playstead.Export.Layout.plan/2` input shape."
  @spec to_layout_input(AssetSet.t()) :: map()
  def to_layout_input(%AssetSet{} = asset_set) do
    %{
      id: asset_set.id,
      system_id: asset_set.system_id,
      display_title: asset_set.display_title || "untitled",
      status: asset_set.status,
      member_fingerprint: asset_set.member_fingerprint,
      excluded: not is_nil(asset_set.excluded_at),
      members:
        Enum.map(asset_set.asset_members, fn m ->
          %{
            ordinal: m.ordinal,
            role: m.role,
            required: m.required,
            declared_name: m.declared_name,
            sha256: m.blob && m.blob.sha256,
            size_bytes: m.blob && m.blob.size_bytes
          }
        end)
    }
  end

  @doc "Fetches `user_id`'s asset set with members and blobs preloaded, or `nil`."
  @spec fetch_asset_set(pos_integer(), binary()) :: AssetSet.t() | nil
  def fetch_asset_set(user_id, asset_set_id) do
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

  @doc "Fetches every non-excluded asset set for `user_id` with members and blobs preloaded."
  @spec fetch_all_asset_sets(pos_integer()) :: [AssetSet.t()]
  def fetch_all_asset_sets(user_id) do
    from(a in AssetSet, where: a.user_id == ^user_id)
    |> Repo.all()
    |> Repo.preload(asset_members: {from(m in AssetMember, order_by: m.ordinal), [:blob]})
  end

  @doc "The full filesystem directory `target_name` resolves to under `export_root/0`."
  @spec target_dir(String.t()) :: String.t()
  def target_dir(target_name), do: Path.join(export_root(), target_name)

  @doc """
  Creates a durable export record (D-33, D-38) and enqueues
  `Playstead.Export.Worker` to write and verify it. Writes an audit
  entry. `scope` is `:set` (with `asset_set_id`) or `:library`.
  """
  @spec create_export(pos_integer(), :set | :library, keyword()) ::
          {:ok, ExportRecord.t()} | {:error, :invalid_target | Ecto.Changeset.t()}
  def create_export(user_id, scope, opts) do
    target_name = Keyword.fetch!(opts, :target_name)
    asset_set_id = Keyword.get(opts, :asset_set_id)

    with {:ok, _target_dir} <- resolve_target(target_name) do
      Repo.transaction(fn ->
        attrs = %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          scope: to_string(scope),
          scope_asset_set_id: asset_set_id,
          target_name: target_name
        }

        with {:ok, export} <- Repo.insert(ExportRecord.create_changeset(%ExportRecord{}, attrs)),
             {:ok, _job} <- Worker.enqueue(export.id),
             {:ok, _entry} <-
               AuditLog.record(user_id, :export_created, %{
                 subject: export.id,
                 scope: to_string(scope)
               }) do
          export
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @doc "Lists `user_id`'s exports, most recently started first."
  @spec list_exports(pos_integer()) :: [ExportRecord.t()]
  def list_exports(user_id) do
    from(e in ExportRecord, where: e.user_id == ^user_id, order_by: [desc: e.inserted_at])
    |> Repo.all()
  end

  @doc "Fetches an export strictly scoped to its owning user, or `nil`."
  @spec get_export(pos_integer(), binary()) :: ExportRecord.t() | nil
  def get_export(user_id, export_id) do
    Repo.get_by(ExportRecord, id: export_id, user_id: user_id)
  end

  @doc "Re-verifies a past export at any time, without rewriting anything."
  @spec verify_again(pos_integer(), binary()) :: {:ok, ExportRecord.t()} | {:error, :not_found}
  def verify_again(user_id, export_id), do: Worker.verify_again(user_id, export_id)

  @doc "The manifest file content for `export`, byte-identical to the written file."
  @spec manifest_content(ExportRecord.t()) :: {:ok, String.t()} | {:error, :not_found}
  def manifest_content(%ExportRecord{} = export) do
    path = Path.join(target_dir(export.target_name), "manifest-sha256.txt")

    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, _reason} -> {:error, :not_found}
    end
  end
end
