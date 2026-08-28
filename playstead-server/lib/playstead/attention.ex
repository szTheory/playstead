defmodule Playstead.Attention do
  @moduledoc """
  The Needs Attention inbox context (D-26). `raise_item/1` is the only
  write path that creates an item — it is always called from inside
  the same transaction as the outcome that caused it, so an item can
  never exist for an import that rolled back and an import can never
  commit while quietly losing the item it should have raised.

  Nothing here ages an item out or sweeps it away on its own: there
  is no scheduled cleanup function here, and none should ever be
  added (D-26).
  """

  import Ecto.Query, warn: false

  alias Playstead.Attention.{Derive, Item}
  alias Playstead.Repo

  @doc """
  Raises an attention item for `ctx` (a `Playstead.Attention.Derive.context/0`
  merged with `:user_id`, `:grouping_key`, and whichever of
  `:source_file_id`/`:asset_set_id`/`:blob_id`/`:import_session_id`/
  `:evidence` apply) when `Playstead.Attention.Derive.needs_attention?/1`
  says so. Grouped reasons (archives kept unopened) upsert onto the
  existing open item for the same `{user, grouping_key, reason}` and
  bump its count rather than inserting a second row — so an import
  containing any number of archives raises exactly one item.

  Returns `{:ok, nil}` when the context is a quiet exclusion — never
  an error, since "no item needed" is the common, expected case.
  """
  @spec raise_item(map()) :: {:ok, Item.t() | nil} | {:error, term()}
  def raise_item(ctx) do
    case Derive.attention_reason(ctx) do
      nil ->
        {:ok, nil}

      reason ->
        grouping_key = Map.get(ctx, :grouping_key) || Ecto.UUID.generate()

        attrs = %{
          user_id: Map.fetch!(ctx, :user_id),
          reason: to_string(reason),
          grouping_key: grouping_key,
          import_session_id: Map.get(ctx, :import_session_id),
          source_file_id: Map.get(ctx, :source_file_id),
          asset_set_id: Map.get(ctx, :asset_set_id),
          blob_id: Map.get(ctx, :blob_id),
          evidence: Map.get(ctx, :evidence, %{})
        }

        upsert_item(attrs)
    end
  end

  defp upsert_item(attrs) do
    changeset = Item.create_changeset(%Item{}, attrs)

    case Repo.insert(changeset,
           on_conflict: [inc: [count: 1]],
           conflict_target: [:user_id, :grouping_key, :reason],
           returning: true
         ) do
      {:ok, item} -> {:ok, item}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc "Fetches an attention item strictly scoped to its owning user, or `nil`."
  @spec get_owned_item(pos_integer(), binary()) :: Item.t() | nil
  def get_owned_item(user_id, item_id) do
    Repo.get_by(Item, id: item_id, user_id: user_id)
  end

  @doc """
  Attempts to transition `item` from `"open"` to `status` (`"resolved"`
  or `"excluded"`) using a guarded conditional update rather than a
  read-then-write check (T-02-42): two concurrent resolutions of the
  same item converge on exactly one winner — the loser's guarded
  update affects zero rows and is reported as already resolved rather
  than silently reapplying the effect.
  """
  @spec try_transition(Item.t(), String.t()) :: {:ok, Item.t()} | {:error, :already_resolved}
  def try_transition(%Item{} = item, status) when status in ["resolved", "excluded"] do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      from(i in Item, where: i.id == ^item.id and i.status == "open")
      |> Repo.update_all(set: [status: status, resolved_at: now, updated_at: now])

    if count == 1 do
      {:ok, %{item | status: status, resolved_at: now}}
    else
      {:error, :already_resolved}
    end
  end

  @doc "Reopens a resolved or excluded item (undo) — its own transition, not a delete."
  @spec reopen_item(Item.t()) :: {:ok, Item.t()}
  def reopen_item(%Item{} = item), do: item |> Item.reopen_changeset() |> Repo.update()

  # Reasons a reference match can settle with no human decision (D-26):
  # the two flavours of "we weren't sure" that a definitive digest match
  # resolves outright. Every other open reason (missing parts, a
  # quarantine, a patch file, a repeated failure, a system contradiction)
  # needs a human choice a reference pack cannot make for them.
  @resolvable_by_match ~w(ambiguous_recognition signature_mismatch)

  @doc """
  Transitions every open attention item for `asset_set_id` whose reason
  a reference match can settle (D-18: "resolves ambiguous and
  unidentified items in place without creating new attention items")
  to `"resolved"`. Silently a no-op when there is nothing open to
  resolve — this is the common case for library content that was
  already quiet.
  """
  @spec resolve_for_asset_set(pos_integer(), binary()) :: :ok
  def resolve_for_asset_set(user_id, asset_set_id) do
    from(i in Item,
      where:
        i.user_id == ^user_id and i.asset_set_id == ^asset_set_id and i.status == "open" and
          i.reason in ^@resolvable_by_match
    )
    |> Repo.all()
    |> Enum.each(&try_transition(&1, "resolved"))

    :ok
  end

  @doc """
  Lists `user_id`'s open attention items, grouped by reason (D-31).
  Ordering inside each group is stable across renders — always
  `{inserted_at, id}` ascending, never a re-sort that would reshuffle
  a list a user has their cursor over.
  """
  @spec list_items(pos_integer(), keyword()) :: %{String.t() => [Item.t()]}
  def list_items(user_id, opts \\ []) do
    status = Keyword.get(opts, :status, "open")
    session_id = Keyword.get(opts, :import_session_id)

    query =
      from(i in Item,
        where: i.user_id == ^user_id and i.status == ^status,
        order_by: [asc: i.inserted_at, asc: i.id]
      )

    query = if session_id, do: where(query, [i], i.import_session_id == ^session_id), else: query

    query
    |> Repo.all()
    |> Enum.group_by(& &1.reason)
  end

  @doc """
  Cursor-paginated, user-scoped attention items for the API (D-30):
  ordered by insertion timestamp with the row id as a deterministic
  tiebreak, mirroring `Playstead.Import.list_session_receipts/3`'s
  cursor shape exactly. Requesting the same cursor twice returns an
  identical page.
  """
  @spec list_items_page(pos_integer(), keyword()) :: %{
          entries: [Item.t()],
          next_cursor: String.t() | nil
        }
  def list_items_page(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    after_cursor = Keyword.get(opts, :after_cursor)

    base =
      from(i in Item,
        where: i.user_id == ^user_id and i.status == "open",
        order_by: [asc: i.inserted_at, asc: i.id],
        limit: ^(limit + 1)
      )

    query =
      case decode_cursor(after_cursor) do
        {:ok, {inserted_at, id}} ->
          from(i in base,
            where: i.inserted_at > ^inserted_at or (i.inserted_at == ^inserted_at and i.id > ^id)
          )

        :error ->
          base
      end

    rows = Repo.all(query)

    {page, has_more} =
      if length(rows) > limit, do: {Enum.take(rows, limit), true}, else: {rows, false}

    next_cursor = if has_more, do: encode_cursor(List.last(page)), else: nil

    %{entries: page, next_cursor: next_cursor}
  end

  defp encode_cursor(%Item{inserted_at: inserted_at, id: id}) do
    Base.url_encode64("#{DateTime.to_iso8601(inserted_at)}|#{id}", padding: false)
  end

  defp decode_cursor(nil), do: :error

  defp decode_cursor(cursor) do
    with {:ok, decoded} <- Base.url_decode64(cursor, padding: false),
         [iso, id] <- String.split(decoded, "|", parts: 2),
         {:ok, inserted_at, _offset} <- DateTime.from_iso8601(iso) do
      {:ok, {inserted_at, id}}
    else
      _ -> :error
    end
  end

  @doc "The count of `user_id`'s open attention items — a calm, neutral number (D-31)."
  @spec count(pos_integer()) :: non_neg_integer()
  def count(user_id) do
    from(i in Item, where: i.user_id == ^user_id and i.status == "open")
    |> Repo.aggregate(:count)
  end

  @doc """
  The total storage held by `user_id`'s excluded asset sets (D-27) —
  distinct blobs only, so a member shared by two excluded sets is not
  counted twice.
  """
  @spec excluded_storage_bytes(pos_integer()) :: non_neg_integer()
  def excluded_storage_bytes(user_id) do
    from(s in Playstead.Catalogue.AssetSet,
      join: m in Playstead.Catalogue.AssetMember,
      on: m.asset_set_id == s.id,
      join: b in Playstead.Blobs.Blob,
      on: b.id == m.blob_id,
      where: s.user_id == ^user_id and not is_nil(s.excluded_at),
      distinct: b.id,
      select: b.size_bytes
    )
    |> Repo.all()
    |> Enum.sum()
  end
end
