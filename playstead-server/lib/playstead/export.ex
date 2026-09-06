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
  alias Playstead.Saves

  # D-10: the only `save_kind` the Mac client writes today
  # (`PlaysteadApp.swift:938`). `Playstead.Saves.Save.save_kind`
  # defaults to this same string; `Playstead.Export.SavesPlan` expects
  # the distinct literal `"system_save"` for a slot eligible for a
  # drop-in copy, so `map_save_kind/1` below is the one place that
  # reconciles the two vocabularies.
  @battery_save_kind "battery"
  @system_save_kind "system_save"

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
      saves = load_save_revisions(user_id, asset_set)
      layout = Layout.plan([to_layout_input(asset_set, saves)], include_excluded: true)
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

  @doc """
  Converts a preloaded `AssetSet` into the `Playstead.Export.Layout.plan/2`
  input shape. `saves` (default `[]`) is the `SavesPlan.revision_input`
  list `load_save_revisions/2` produces; the default keeps every
  existing arity-1 caller and fixture compiling unchanged.
  """
  @spec to_layout_input(AssetSet.t(), [map()]) :: map()
  def to_layout_input(%AssetSet{} = asset_set, saves \\ []) do
    %{
      id: asset_set.id,
      system_id: asset_set.system_id,
      display_title: asset_set.display_title || "untitled",
      status: asset_set.status,
      member_fingerprint: asset_set.member_fingerprint,
      excluded: not is_nil(asset_set.excluded_at),
      provenance: asset_set.provenance || %{},
      saves: saves,
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

  @doc """
  Loads `user_id`'s save revisions for `asset_set`'s primary member
  content key (D-62: this is the ONE place `Playstead.Export` crosses
  into `Playstead.Saves` — `Playstead.Export.Layout` and
  `Playstead.Export.SavesPlan` never do), shaped as
  `Playstead.Export.SavesPlan.revision_input/0` maps.

  Returns `[]` when the asset set has no member with a blob digest, or
  when the user has no save line for that content key. If more than
  one save line exists for the content key (v1 only ever writes one —
  `save_kind: "battery"`, `slot: "0"`, `PlaysteadApp.swift:938`), only
  that line is loaded; any other lines are recorded as a disclosed
  limitation rather than merged, because concatenating two histories
  into one would make `SavesPlan.diverged?/1` lie.
  """
  @spec load_save_revisions(pos_integer(), AssetSet.t()) :: [map()]
  def load_save_revisions(user_id, %AssetSet{} = asset_set) do
    with content_key when is_binary(content_key) <- primary_content_key(asset_set),
         lines when lines != [] <- Saves.list_lines(user_id, content_key),
         %Saves.Save{} = line <- select_battery_line(lines) do
      {:ok, %{revisions: revisions, heads: heads}} = Saves.get_history(user_id, line.id)
      head_ids = MapSet.new(heads, & &1.id)

      Enum.map(revisions, fn revision ->
        %{
          id: revision.id,
          sha256: revision.blob_sha256,
          size_bytes: revision.size_bytes,
          recorded_at: revision.recorded_at,
          save_kind: map_save_kind(line.save_kind),
          is_head: MapSet.member?(head_ids, revision.id),
          branch_key: nil,
          bytes: if(Playstead.Blobs.exists?(revision.blob_sha256), do: :present, else: :missing)
        }
      end)
    else
      _ -> []
    end
  end

  # D-10: v1 ships exactly one supported (save_kind, slot) pair --
  # ("battery", "0"). Any other lines returned for this content key are
  # a disclosed limitation (recorded via `gsd-tools windows record`),
  # never merged into this list.
  defp select_battery_line(lines) do
    Enum.find(lines, &(&1.save_kind == @battery_save_kind and &1.slot == "0"))
  end

  defp map_save_kind(@battery_save_kind), do: @system_save_kind
  defp map_save_kind(other), do: other

  defp primary_content_key(%AssetSet{asset_members: members}) do
    case Enum.find(members, List.first(members), &(&1.role == "primary")) do
      nil -> nil
      %{blob: nil} -> nil
      %{blob: blob} -> blob.sha256
    end
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
    # D-57: a user choice, persisted on the record (not derived from
    # scope) so a re-enqueued job reproduces the same plan.
    saves_scope = Keyword.get(opts, :saves_scope, "all")

    with {:ok, _target_dir} <- resolve_target(target_name) do
      Repo.transaction(fn ->
        attrs = %{
          id: Ecto.UUID.generate(),
          user_id: user_id,
          scope: to_string(scope),
          scope_asset_set_id: asset_set_id,
          target_name: target_name,
          saves_scope: saves_scope
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
