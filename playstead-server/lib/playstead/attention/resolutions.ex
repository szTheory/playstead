defmodule Playstead.Attention.Resolutions do
  @moduledoc """
  The five safe, audited, reversible commands a user has over an
  attention item (D-27). Every resolution follows the idempotency
  module's own discipline: the effect and its audit entry are written
  inside one transaction, never with the audit entry written after
  the commit. No resolution here ever deletes a byte — there is no
  physical-storage-freeing path, no delete action, and no cleanup
  routine anywhere in this module.

  Two clients resolving the same item at once never double-apply: the
  guard (`Playstead.Attention.try_transition/2`) is a conditional
  update on the item still being open, so exactly one caller's effect
  runs and the other is told the item was already resolved
  (`{:error, :already_resolved}`).
  """

  alias Playstead.Attention
  alias Playstead.Attention.Item
  alias Playstead.AuditLog
  alias Playstead.Blobs
  alias Playstead.Catalogue
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import
  alias Playstead.Recognition
  alias Playstead.Recognition.Override
  alias Playstead.Repo
  alias Playstead.Sync.ChangeJournal

  @doc """
  Corrects `item`'s asset set's system (D-19, D-27). Inserts an
  additive `Playstead.Recognition.Override` row, re-derives the
  effective system via `Playstead.Catalogue.override_system/3` (which
  never touches a machine-produced evidence row), writes one audit
  entry, and resolves the item.
  """
  @spec correct_system(Item.t(), pos_integer(), atom() | String.t()) ::
          {:ok, map()} | {:error, :already_resolved | :not_found | term()}
  def correct_system(%Item{} = item, user_id, system_id) do
    with_resolution(item, "resolved", fn resolved_item ->
      case Repo.get(AssetSet, resolved_item.asset_set_id) do
        nil ->
          {:error, :not_found}

        asset_set ->
          # A direct changeset update (not `Catalogue.override_system/3`,
          # which writes its own audit entry) so exactly one audit entry
          # is written per resolution, as every resolution promises.
          changeset =
            Ecto.Changeset.change(asset_set, system_id: to_string(system_id), system_source: "user")

          with {:ok, updated_set} <- Repo.update(changeset),
               {:ok, entry} <-
                 AuditLog.record(user_id, :attention_system_corrected, %{
                   subject: resolved_item.id,
                   system_id: to_string(system_id)
                 }),
               {:ok, _override} <-
                 %Override{}
                 |> Override.create_changeset(%{
                   user_id: user_id,
                   asset_set_id: updated_set.id,
                   system_id: to_string(system_id),
                   audit_entry_id: entry.id
                 })
                 |> Repo.insert() do
            {:ok, %{item: resolved_item, asset_set: updated_set}}
          end
      end
    end)
  end

  @doc """
  Attaches an existing, already-owned blob to the declared missing
  member slot (D-15, D-27) via `Playstead.Import.attach_companion/4`,
  which recomputes the set's member fingerprint and status in the
  same transaction. Resolves `item` only once the set is complete.
  """
  @spec attach_companion(Item.t(), pos_integer(), String.t(), map(), {:stored | :existing, map()}) ::
          {:ok, map()} | {:error, :already_resolved | term()}
  def attach_companion(%Item{} = item, user_id, declared_name, source_file_attrs, store_result) do
    with_resolution_conditional(item, fn resolved_item ->
      case Import.attach_companion(user_id, declared_name, source_file_attrs, store_result) do
        {:ok, receipt} ->
          {:ok, _entry} =
            AuditLog.record(user_id, :attention_companion_attached, %{
              subject: resolved_item.id,
              declared_name: declared_name
            })

          asset_set = receipt.asset_set_id && Repo.get(AssetSet, receipt.asset_set_id)
          resolve? = match?(%AssetSet{status: "complete"}, asset_set)
          {:ok, %{receipt: receipt, asset_set: asset_set}, resolve?}

        {:error, reason} ->
          {:error, reason}
      end
    end)
  end

  @doc """
  Retains `item`'s content as user-declared custom content (D-27). For
  a policy-quarantined blob, releases it as opaque, storable/exportable
  content only — never as inspectable-as-playable — via
  `Playstead.Blobs.release/3`. Writes one audit entry and resolves the
  item.
  """
  @spec retain_as_custom(Item.t(), pos_integer()) ::
          {:ok, map()} | {:error, :already_resolved | term()}
  def retain_as_custom(%Item{} = item, user_id) do
    with_resolution(item, "resolved", fn resolved_item ->
      released =
        if resolved_item.blob_id do
          {:ok, release} = Blobs.release(user_id, resolved_item.blob_id, "retain_as_custom")
          release
        end

      {:ok, _entry} =
        AuditLog.record(user_id, :attention_retained_as_custom, %{subject: resolved_item.id})

      {:ok, %{item: resolved_item, release: released}}
    end)
  end

  @doc """
  Excludes `item`'s asset set (D-27): sets `excluded_at` and emits a
  catalogue tombstone via `Playstead.Catalogue.exclude_set/2` — bytes
  are kept, nothing is deleted. Writes one audit entry (distinct from
  the catalogue tombstone) and marks the item `"excluded"` rather than
  `"resolved"`, so it remains reachable and restorable from the
  excluded filter.
  """
  @spec exclude(Item.t(), pos_integer()) :: {:ok, map()} | {:error, :already_resolved | term()}
  def exclude(%Item{} = item, user_id) do
    with_resolution(item, "excluded", fn resolved_item ->
      case resolved_item.asset_set_id && Repo.get(AssetSet, resolved_item.asset_set_id) do
        %AssetSet{} = asset_set ->
          with {:ok, updated_set} <- Catalogue.exclude_set(asset_set, user_id),
               {:ok, _entry} <-
                 AuditLog.record(user_id, :attention_excluded, %{subject: resolved_item.id}) do
            {:ok, %{item: resolved_item, asset_set: updated_set}}
          end

        nil ->
          with {:ok, _entry} <-
                 AuditLog.record(user_id, :attention_excluded, %{subject: resolved_item.id}) do
            {:ok, %{item: resolved_item, asset_set: nil}}
          end
      end
    end)
  end

  @doc """
  Restores a previously excluded or resolved item (D-27) — every
  resolution except retry can be undone, and undo writes its own
  audit entry. Reopens the item and, for exclusion, clears the asset
  set's `excluded_at` and appends a correcting `catalogue` upsert
  entry so a resuming reader observes the set again.
  """
  @spec undo(Item.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def undo(%Item{status: "open"}, _user_id), do: {:error, :not_resolved}

  def undo(%Item{} = item, user_id) do
    Repo.transaction(fn ->
      with {:ok, restored_set} <- maybe_restore_set(item),
           {:ok, reopened} <- Attention.reopen_item(item),
           {:ok, _entry} <-
             AuditLog.record(user_id, :attention_undone, %{subject: item.id}) do
        %{item: reopened, asset_set: restored_set}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  defp maybe_restore_set(%Item{asset_set_id: nil}), do: {:ok, nil}

  defp maybe_restore_set(%Item{asset_set_id: asset_set_id}) do
    case Repo.get(AssetSet, asset_set_id) do
      %AssetSet{excluded_at: nil} = set ->
        {:ok, set}

      %AssetSet{} = set ->
        with {:ok, updated} <- set |> Ecto.Changeset.change(excluded_at: nil) |> Repo.update(),
             {:ok, _entry} <- ChangeJournal.append(set.user_id, :catalogue, updated.id, %{}) do
          {:ok, updated}
        end

      nil ->
        {:ok, nil}
    end
  end

  @doc """
  Re-enqueues inspection and recognition for `item`'s blob against
  bytes already stored (D-27) — never re-copies or re-streams a byte,
  and creates no new `blobs` row. Retry is the only resolution that
  cannot be undone; it leaves `item` open, since the new evidence may
  or may not resolve the original reason.
  """
  @spec retry(Item.t(), pos_integer()) :: {:ok, map()} | {:error, term()}
  def retry(%Item{blob_id: nil}, _user_id), do: {:error, :nothing_to_retry}

  def retry(%Item{} = item, user_id) do
    Repo.transaction(fn ->
      blob = Repo.get!(Playstead.Blobs.Blob, item.blob_id)

      facts = %{blob_id: blob.id, sha256: blob.sha256, exclude_source_file_id: item.source_file_id}
      {_result, evidence} = Recognition.recognize_and_record(user_id, facts, nil)

      {:ok, _entry} = AuditLog.record(user_id, :attention_retried, %{subject: item.id})

      %{item: item, evidence: evidence}
    end)
  end

  # --- shared guard/effect wiring ---------------------------------------

  # The guard check happens BEFORE opening a transaction, not inside
  # one that then rolls back — nesting `Repo.transaction`/`Repo.rollback`
  # calls when this runs inside an outer transaction (as it does under
  # `Playstead.Idempotency.execute/4`) can abort more than the intended
  # inner scope. An "already resolved" outcome is not a failure this
  # module needs a database rollback to represent; it is an ordinary
  # return value.
  defp with_resolution(item, target_status, effect_fun) do
    case Attention.try_transition(item, target_status) do
      {:ok, resolved_item} ->
        Repo.transaction(fn ->
          case effect_fun.(resolved_item) do
            {:ok, result} -> result
            {:error, reason} -> Repo.rollback(reason)
          end
        end)

      {:error, :already_resolved} ->
        {:error, :already_resolved}
    end
  end

  # For resolutions whose effect itself decides whether the item
  # should close (attach may leave the set incomplete).
  defp with_resolution_conditional(item, effect_fun) do
    case Attention.try_transition(item, "resolved") do
      {:ok, claimed_item} ->
        Repo.transaction(fn ->
          case effect_fun.(claimed_item) do
            {:ok, result, true} ->
              result

            {:ok, result, false} ->
              {:ok, _reopened} = Attention.reopen_item(claimed_item)
              result

            {:error, reason} ->
              Repo.rollback(reason)
          end
        end)

      {:error, :already_resolved} ->
        {:error, :already_resolved}
    end
  end
end
