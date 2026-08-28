defmodule Playstead.Import.FolderImport do
  @moduledoc """
  Hash-set-first reimport identity (D-08, D-37). Reads a bag folder's
  payload manifest, re-hashes every listed file — the recomputed
  fingerprint decides identity, never anything read out of the folder
  — and only then consults the folder's sidecar (if any) for anything
  beyond the bytes themselves.

  Every payload file in the manifest is grouped by its containing
  folder (one `Playstead.Export.Layout` set folder). A group whose
  sidecar is present and parses under a known major schema version is
  imported as a multi-member set using the sidecar's declared
  role/ordinal/required shape; a group with a missing or tampered
  sidecar degrades to a plain folder import — each payload file becomes
  its own single-member set under the ordinary grouping rules,
  identical to a folder with no sidecar at all.
  """

  import Ecto.Query, warn: false

  alias Playstead.Blobs
  alias Playstead.Catalogue
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Export.Sidecar
  alias Playstead.Import.{Receipt, SourceFile}
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  @chunk_size 1_048_576
  @tracer_role "primary"

  @doc """
  Imports every payload file under `bag_dir` for `user_id`. Every byte
  is re-hashed on the way in; the member fingerprint computed from
  those re-hashed bytes decides identity before any sidecar is
  consulted for anything.
  """
  @spec import_folder(pos_integer(), String.t(), keyword()) ::
          {:ok, [Receipt.t()]} | {:error, term()}
  def import_folder(user_id, bag_dir, _opts \\ []) do
    manifest_path = Path.join(bag_dir, "manifest-sha256.txt")

    case File.read(manifest_path) do
      {:ok, content} ->
        entries = parse_manifest(content)

        receipts =
          entries
          |> Enum.group_by(&Path.dirname(&1.relative))
          |> Enum.flat_map(fn {group_dir, group_entries} ->
            import_group(user_id, bag_dir, group_dir, group_entries)
          end)

        {:ok, receipts}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_manifest(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      [sha256, relative] = String.split(line, "  ", parts: 2)
      %{sha256: sha256, relative: relative}
    end)
  end

  defp import_group(user_id, bag_dir, group_dir, group_entries) do
    sidecar_path =
      Path.join([bag_dir, "tags", strip_data_prefix(group_dir), "playstead-set.json"])

    case read_sidecar(sidecar_path) do
      {:ok, sidecar} -> import_with_sidecar(user_id, bag_dir, sidecar, group_entries)
      :degrade -> Enum.map(group_entries, &import_plain_file(user_id, bag_dir, &1))
    end
  end

  defp strip_data_prefix("data/" <> rest), do: rest
  defp strip_data_prefix(other), do: other

  defp read_sidecar(path) do
    case File.read(path) do
      {:ok, content} ->
        case Sidecar.parse(content) do
          {:ok, sidecar} -> {:ok, sidecar}
          :ignore -> :degrade
        end

      {:error, _reason} ->
        :degrade
    end
  end

  # --- plain fallback: no sidecar, or a tampered one — one file, one set

  defp import_plain_file(user_id, bag_dir, %{relative: relative}) do
    meta = rehash!(Path.join(bag_dir, relative))
    original_name = Path.basename(relative)
    fingerprint = Catalogue.member_fingerprint([%{role: @tracer_role, sha256: meta.sha256}])

    case Repo.get_by(AssetSet, user_id: user_id, member_fingerprint: fingerprint) do
      %AssetSet{} = existing ->
        commit_member(user_id, existing.id, original_name, meta, :alias)

      nil ->
        member_attrs = [
          %{
            ordinal: 0,
            role: @tracer_role,
            required: true,
            declared_name: original_name,
            blob_id: meta.blob_id
          }
        ]

        asset_set =
          insert_new_set!(
            user_id,
            Ecto.UUID.generate(),
            fingerprint,
            %{
              display_title: original_name,
              title_source: "filename_stem",
              system_id: nil,
              system_source: nil,
              status: "active",
              provenance: %{}
            },
            member_attrs
          )

        commit_member(user_id, asset_set.id, original_name, meta, :new_asset)
    end
  end

  # --- sidecar-declared multi-member set -------------------------------

  defp import_with_sidecar(user_id, bag_dir, sidecar, _group_entries) do
    member_specs = sidecar["members"] || []

    hashed =
      Enum.map(member_specs, fn spec ->
        payload_path = Path.join(bag_dir, spec["path"] || "")

        if File.regular?(payload_path) do
          %{spec: spec, meta: rehash!(payload_path), present: true}
        else
          %{spec: spec, meta: nil, present: false}
        end
      end)

    fingerprint =
      Catalogue.member_fingerprint(
        Enum.map(hashed, fn %{spec: spec, meta: meta} ->
          %{role: spec["role"], sha256: meta && meta.sha256}
        end)
      )

    case Repo.get_by(AssetSet, user_id: user_id, member_fingerprint: fingerprint) do
      %AssetSet{} = existing ->
        commit_alias_group(user_id, existing, hashed)

      nil ->
        create_new_group(user_id, sidecar, hashed, fingerprint)
    end
  end

  defp rehash!(path) do
    size = File.stat!(path).size
    stream = File.stream!(path, [], @chunk_size)
    {:ok, _status, meta} = Blobs.put_stream(stream, size)
    meta
  end

  # D-37: a fingerprint match is an alias — zero new blobs, zero new
  # sets, one new source_file row per present member.
  defp commit_alias_group(user_id, existing, hashed) do
    hashed
    |> Enum.filter(& &1.present)
    |> Enum.map(fn %{spec: spec, meta: meta} ->
      original_name = spec["original_name"] || spec["exported_name"] || "member"
      commit_member(user_id, existing.id, original_name, meta, :alias)
    end)
  end

  defp create_new_group(user_id, sidecar, hashed, fingerprint) do
    claimed_id = sidecar["id"]

    {set_id, provenance} = resolve_identifier(user_id, claimed_id, hashed)

    missing_names = missing_member_names(hashed)
    status = if missing_names != [], do: "incomplete", else: "active"

    member_attrs =
      hashed
      |> Enum.with_index()
      |> Enum.map(fn {%{spec: spec, meta: meta}, idx} ->
        %{
          ordinal: spec["ordinal"] || idx,
          role: spec["role"] || @tracer_role,
          required: Map.get(spec, "required", true),
          declared_name: spec["original_name"] || spec["exported_name"],
          blob_id: meta && meta.blob_id
        }
      end)

    asset_set =
      insert_new_set!(
        user_id,
        set_id,
        fingerprint,
        %{
          display_title: sidecar["title"] || "untitled",
          title_source: "sidecar",
          system_id: sidecar["system_id"],
          system_source: if(sidecar["system_id"], do: "sidecar", else: nil),
          status: status,
          provenance: provenance
        },
        member_attrs
      )

    present = Enum.filter(hashed, & &1.present)

    present
    |> Enum.with_index()
    |> Enum.map(fn {%{spec: spec, meta: meta}, idx} ->
      original_name = spec["original_name"] || spec["exported_name"] || "member"

      if idx == 0 do
        outcome = if missing_names != [], do: :incomplete_set, else: :new_asset

        reason =
          if missing_names != [], do: "missing: " <> Enum.join(missing_names, ", "), else: nil

        commit_member(user_id, asset_set.id, original_name, meta, outcome, reason)
      else
        commit_member(user_id, asset_set.id, original_name, meta, :new_asset)
      end
    end)
  end

  defp missing_member_names(hashed) do
    hashed
    |> Enum.reject(& &1.present)
    |> Enum.map(fn %{spec: spec} ->
      spec["original_name"] || spec["exported_name"] || spec["path"] || "unknown member"
    end)
  end

  # D-37's four identifier-resolution cases. `hashed`'s present
  # role/sha256 pairs decide subset-vs-derived; the sidecar identifier
  # is never consulted to attach bytes, only to name or reuse an id.
  defp resolve_identifier(user_id, claimed_id, hashed) do
    case cast_uuid(claimed_id) do
      {:ok, id} ->
        resolve_existing_claim(user_id, id, claimed_id, hashed)

      :error ->
        {Ecto.UUID.generate(),
         %{"claimed_identifier" => claimed_id, "rejected_reason" => "malformed"}}
    end
  end

  defp cast_uuid(value) when is_binary(value), do: Ecto.UUID.cast(value)
  defp cast_uuid(_value), do: :error

  defp resolve_existing_claim(user_id, id, claimed_id, hashed) do
    case Repo.get(AssetSet, id) do
      nil ->
        {id, %{}}

      %AssetSet{user_id: ^user_id} = found_set ->
        classify_relation(found_set, claimed_id, hashed)

      %AssetSet{} ->
        {Ecto.UUID.generate(),
         %{"claimed_identifier" => claimed_id, "rejected_reason" => "foreign_owner"}}
    end
  end

  defp classify_relation(found_set, claimed_id, hashed) do
    found_set = Repo.preload(found_set, asset_members: :blob)

    found_pairs =
      MapSet.new(found_set.asset_members, fn m -> {m.role, m.blob && m.blob.sha256} end)

    present_pairs =
      hashed
      |> Enum.filter(& &1.present)
      |> MapSet.new(fn %{spec: spec, meta: meta} -> {spec["role"], meta.sha256} end)

    if MapSet.subset?(present_pairs, found_pairs) and
         MapSet.size(present_pairs) < MapSet.size(found_pairs) do
      {Ecto.UUID.generate(),
       %{
         "claimed_identifier" => claimed_id,
         "relation" => "subset_of",
         "of_set_id" => found_set.id
       }}
    else
      {Ecto.UUID.generate(),
       %{
         "claimed_identifier" => claimed_id,
         "relation" => "derived_from_export",
         "title" => found_set.display_title
       }}
    end
  end

  defp insert_new_set!(user_id, id, fingerprint, attrs, member_attrs) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    insert_attrs =
      Map.merge(attrs, %{
        id: id,
        user_id: user_id,
        member_fingerprint: fingerprint,
        inserted_at: now,
        updated_at: now
      })

    {count, _} =
      Repo.insert_all(AssetSet, [insert_attrs],
        on_conflict: :nothing,
        conflict_target: [:user_id, :member_fingerprint]
      )

    asset_set = Repo.get_by!(AssetSet, user_id: user_id, member_fingerprint: fingerprint)

    if count == 1 do
      Enum.each(member_attrs, fn m ->
        Repo.insert!(
          AssetMember.create_changeset(%AssetMember{}, Map.put(m, :asset_set_id, asset_set.id))
        )
      end)
    end

    asset_set
  end

  defp commit_member(user_id, asset_set_id, original_name, meta, outcome, reason \\ nil) do
    source_file =
      Repo.insert!(
        SourceFile.create_changeset(%SourceFile{}, %{
          user_id: user_id,
          original_name: original_name,
          origin: "reimport",
          size_bytes: meta.size_bytes,
          blob_id: meta.blob_id
        })
      )

    {:ok, _entry} = ChangeJournal.append(user_id, :catalogue, asset_set_id, %{})

    Repo.insert!(
      Receipt.create_changeset(%Receipt{}, %{
        user_id: user_id,
        source_file_id: source_file.id,
        blob_id: meta.blob_id,
        asset_set_id: asset_set_id,
        outcome: to_string(outcome),
        reason: reason,
        sha256: meta.sha256,
        size_bytes: meta.size_bytes
      })
    )
  end
end
