defmodule Playstead.Sync.Snapshot do
  @moduledoc """
  The transactional snapshot read (PROT-05, D-21): the current
  materialized state for `user_id`'s registered entity kinds, together
  with an as-of cursor that comes from the *same* transaction as the
  page data.

  This is the load-bearing property: reading the as-of position outside
  the page query's transaction can land before or after the data,
  producing either a duplicate or — far worse — a permanently skipped
  change once the client resumes `/changes` from it. Both reads run
  inside one `Repo.transaction/2` at the `:repeatable_read` isolation
  level, so the returned cursor is exactly the position the returned
  data reflects.

  ## Scope of this snapshot (Claude's Discretion, per plan 01-07)

  Phase 1 only has real producers for the `device` and `pairing` entity
  kinds (the scope note in the plan: catalogue/job/transfer/save are
  registered in the vocabulary but have no data until Phases 2-4). Of
  those two, only `device` state is a durable, materializable "current
  state" a client's local cache needs to reconstruct — pairing_requests
  are an ephemeral ceremony, not library state a reconnecting client
  browses. This snapshot therefore materializes one domain
  (non-revoked devices) rather than one endpoint per domain; a later
  phase adds its own materialization branch here as its entity kinds
  gain producers, without changing this endpoint's shape.

  Revoked devices are deliberately excluded — the same outcome a
  resuming `/changes` client reaches once it applies that device's
  tombstone entry, so snapshot-then-resume and changes-only
  reconstruction agree.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Pairing.Device
  alias Playstead.Sync.{ChangeJournal, Cursor}

  @page_size 200

  @doc """
  Reads a page of the owner's current state plus its as-of cursor.

  `opts`:
  - `:after_id` — the last `entity_id` from a previous page, to fetch the next one.
  - `:as_of` — the decoded `seq` from a previous page's cursor, so every
    page of one logical multi-page read is pinned to the same position
    (a page fetched later must not silently include a write later pages
    missed). Omit on the first page.
  """
  @spec read(pos_integer(), keyword()) ::
          {:ok,
           %{
             entries: [map()],
             cursor: String.t(),
             has_more: boolean(),
             next_after_id: String.t() | nil
           }}
  def read(user_id, opts \\ []) do
    after_id = Keyword.get(opts, :after_id)
    pinned_as_of = Keyword.get(opts, :as_of)

    {:ok, result} =
      Repo.transaction(
        fn ->
          as_of_seq = pinned_as_of || ChangeJournal.max_seq(user_id)
          as_of_time = as_of_time_for(as_of_seq)

          {rows, has_more} = fetch_page(user_id, as_of_time, after_id)

          %{
            entries: Enum.map(rows, &to_entry_view/1),
            cursor: Cursor.encode(as_of_seq),
            has_more: has_more,
            next_after_id: next_after_id(rows, has_more)
          }
        end,
        isolation_level: :repeatable_read
      )

    {:ok, result}
  end

  # `as_of_seq == 0` means the journal has never recorded anything for
  # this user yet — there is nothing to pin against, so "now" is the
  # correct anchor (current state already *is* the as-of state).
  defp as_of_time_for(0), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp as_of_time_for(seq), do: ChangeJournal.inserted_at_for(seq) || DateTime.utc_now()

  defp fetch_page(user_id, as_of_time, after_id) do
    query =
      from(d in Device,
        where: d.user_id == ^user_id,
        where: d.inserted_at <= ^as_of_time,
        where: is_nil(d.revoked_at) or d.revoked_at > ^as_of_time,
        order_by: [asc: d.id],
        limit: ^(@page_size + 1)
      )

    query = if after_id, do: where(query, [d], d.id > ^after_id), else: query

    rows = Repo.all(query)

    if length(rows) > @page_size do
      {Enum.take(rows, @page_size), true}
    else
      {rows, false}
    end
  end

  defp next_after_id(_rows, false), do: nil
  defp next_after_id(rows, true), do: rows |> List.last() |> Map.fetch!(:id)

  defp to_entry_view(%Device{} = device) do
    %{
      entity_kind: "device",
      entity_id: device.id,
      operation: "upsert",
      payload: %{
        name: device.name,
        claimed_name: device.claimed_name,
        platform: device.platform,
        app_version: device.app_version,
        revoked_at: device.revoked_at
      }
    }
  end
end
