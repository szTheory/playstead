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
  inside one `Repo.transaction/2` at REPEATABLE READ, so the returned
  cursor is exactly the position the returned data reflects.

  The isolation level is set with an explicit `SET TRANSACTION` as the
  first statement of the transaction: Ecto/Postgrex silently ignore an
  `isolation_level:` option to `Repo.transaction/2`, leaving the default
  READ COMMITTED — which `Playstead.Sync.SnapshotConcurrencyTest` proved
  lets a commit that lands between the two reads leak into the page.

  Postgres refuses to change the level once a transaction has run any
  statement (or inside a savepoint), so under the Ecto sandbox — where a
  whole test is one already-started transaction — the statement cannot be
  issued. `config :playstead, Playstead.Sync.Snapshot, set_isolation: false`
  (config/test.exs) turns it off there; the sandbox's single transaction
  gives every sandboxed test the same-snapshot property trivially, and the
  concurrency test re-enables it for its own real, top-level transactions.

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

  alias Playstead.Catalogue.AssetSet
  alias Playstead.Catalogue.Payload, as: CataloguePayload
  alias Playstead.Import.Session
  alias Playstead.Repo
  alias Playstead.Pairing.Device
  alias Playstead.Sync.{ChangeJournal, Cursor}

  @default_page_size 200

  @doc """
  Reads a page of the owner's current state plus its as-of cursor.

  `opts`:
  - `:after_id` — the last `entity_id` from a previous page, to fetch the next one.
  - `:as_of` — the decoded `seq` from a previous page's cursor, so every
    page of one logical multi-page read is pinned to the same position
    (a page fetched later must not silently include a write later pages
    missed). Omit on the first page.
  - `:page_size` — rows per page; defaults to
    `config :playstead, Playstead.Sync.Snapshot, page_size:` or #{@default_page_size}.
    The API never passes this — it exists so tests can exercise multi-page
    reads without hundreds of fixture rows.
  - `:between_reads` — a zero-arity function invoked *inside* the
    transaction, after the as-of position is read and before the page
    query runs. A no-op by default; the concurrency contract test uses it
    as a barrier to commit a competing write at exactly that moment.
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
    page_size = Keyword.get(opts, :page_size, configured_page_size())
    between_reads = Keyword.get(opts, :between_reads, fn -> :ok end)

    {:ok, result} =
      Repo.transaction(fn ->
        if set_isolation?(), do: Repo.query!("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")

        as_of_seq = pinned_as_of || ChangeJournal.max_seq(user_id)
        as_of_time = as_of_time_for(as_of_seq)

        between_reads.()

        {rows, has_more} = fetch_page(user_id, as_of_time, after_id, page_size)

        %{
          entries: Enum.map(rows, &to_entry_view/1),
          cursor: Cursor.encode(as_of_seq),
          has_more: has_more,
          next_after_id: next_after_id(rows, has_more),
          catalogue: fetch_catalogue(user_id, as_of_time),
          job: fetch_jobs(user_id, as_of_time)
        }
      end)

    {:ok, result}
  end

  # `as_of_seq == 0` means the journal has never recorded anything for
  # this user yet — there is nothing to pin against, so "now" is the
  # correct anchor (current state already *is* the as-of state).
  defp as_of_time_for(0), do: DateTime.utc_now() |> DateTime.truncate(:second)
  defp as_of_time_for(seq), do: ChangeJournal.inserted_at_for(seq) || DateTime.utc_now()

  defp configured_page_size do
    :playstead
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:page_size, @default_page_size)
  end

  defp set_isolation? do
    :playstead
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:set_isolation, true)
  end

  defp fetch_page(user_id, as_of_time, after_id, page_size) do
    query =
      from(d in Device,
        where: d.user_id == ^user_id,
        where: d.inserted_at <= ^as_of_time,
        where: is_nil(d.revoked_at) or d.revoked_at > ^as_of_time,
        order_by: [asc: d.id],
        limit: ^(page_size + 1)
      )

    query = if after_id, do: where(query, [d], d.id > ^after_id), else: query

    rows = Repo.all(query)

    if length(rows) > page_size do
      {Enum.take(rows, page_size), true}
    else
      {rows, false}
    end
  end

  # D-23: the catalogue branch, read from the same transaction as the
  # device page above so a resuming client sees a catalogue snapshot
  # and an as-of cursor with no gap and no overlap.
  defp fetch_catalogue(user_id, as_of_time) do
    from(a in AssetSet,
      where: a.user_id == ^user_id,
      where: a.inserted_at <= ^as_of_time,
      order_by: [asc: a.id]
    )
    |> Repo.all()
    |> Repo.preload(asset_members: :blob)
    |> Enum.map(&CataloguePayload.build/1)
  end

  # D-30: the `job` branch (one row per import session, D-05/D-06/D-08)
  # read from the same transaction and as-of position as the device
  # page and the catalogue branch above, so a resuming client's
  # snapshot and its as-of cursor never disagree about session state.
  defp fetch_jobs(user_id, as_of_time) do
    from(s in Session,
      where: s.user_id == ^user_id,
      where: s.inserted_at <= ^as_of_time,
      order_by: [asc: s.id]
    )
    |> Repo.all()
    |> Enum.map(&job_view/1)
  end

  defp job_view(%Session{} = session) do
    %{
      id: session.id,
      state: session.state,
      file_count: session.file_count,
      files_completed: session.files_completed,
      total_bytes: session.total_bytes,
      bytes_completed: session.bytes_completed,
      counts_by_outcome: session.counts_by_outcome
    }
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
