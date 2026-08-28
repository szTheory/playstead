defmodule Playstead.Sync.SnapshotConcurrencyTest do
  @moduledoc """
  PROT-05 / D-21 under *real* concurrency: genuinely independent Postgres
  transactions racing `Playstead.Sync.Snapshot.read/2`.

  Ecto's sandbox runs a whole test on one connection, so the ordinary
  suites cannot commit a competing write while a snapshot transaction is
  open. This module switches the sandbox to `:auto` mode for its own
  duration (it is `async: false`, and ExUnit runs every sync module after
  the async ones) so each process gets its own pooled connection and its
  writes commit for real; each test truncates what it wrote.

  Two properties that were previously asserted by design only:

    1. A write whose commit lands *inside* the snapshot transaction — after
       the as-of position is read, before the page query — is neither
       included in the page (REPEATABLE READ) nor lost (it is the first
       entry when the feed is resumed from the returned cursor).
    2. A multi-page read with pairs / renames / revokes interleaved between
       pages, all pinned to the first page's as-of, converges: applying the
       pages and then the resumed feed yields exactly the fresh state, with
       every later mutation delivered exactly once by the feed.
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  import Playstead.AccountsFixtures
  import Playstead.PairingFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playstead.{Pairing, Repo}
  alias Playstead.Sync.{ChangeJournal, Cursor, Snapshot}

  # Every table a device fixture touches, so a test leaves nothing behind
  # for the sync modules that run after it.
  @tables ~w(change_journal_entries idempotency_receipts capability_declarations device_credentials devices pairing_requests audit_log_entries recovery_codes setup_tokens users_tokens users)

  setup_all do
    Sandbox.mode(Repo, :auto)
    previous = Application.get_env(:playstead, Snapshot, [])
    Application.put_env(:playstead, Snapshot, Keyword.put(previous, :set_isolation, true))

    on_exit(fn ->
      Application.put_env(:playstead, Snapshot, previous)
      Sandbox.mode(Repo, :manual)
    end)

    :ok
  end

  setup do
    on_exit(fn ->
      Sandbox.mode(Repo, :auto)
      Repo.query!("TRUNCATE #{Enum.join(@tables, ", ")} RESTART IDENTITY CASCADE")
    end)
  end

  test "a commit interleaved inside the snapshot transaction is excluded from the page and delivered once on resume" do
    scope = user_scope_fixture()
    %{device: d1} = device_fixture(scope)
    parent = self()

    reader =
      Task.async(fn ->
        Snapshot.read(scope.user.id,
          between_reads: fn ->
            # The whole property rests on this: Ecto ignores an
            # `isolation_level:` transaction option, so it is set explicitly.
            assert Repo.query!("SHOW transaction_isolation").rows == [["repeatable read"]]
            send(parent, :pinned)

            receive do
              :written -> :ok
            after
              5_000 -> raise "the competing write never committed"
            end
          end
        )
      end)

    assert_receive :pinned, 5_000
    # Own pooled connection; commits while the reader's transaction is open.
    %{device: d2} = device_fixture(scope)
    send(reader.pid, :written)

    {:ok, %{entries: entries, cursor: cursor}} = Task.await(reader, 5_000)
    ids = Enum.map(entries, & &1.entity_id)

    assert d1.id in ids
    refute d2.id in ids, "a write committed inside the snapshot transaction leaked into the page"

    {:ok, seq} = Cursor.decode(cursor)
    resumed = ChangeJournal.read_after(scope.user.id, seq, 100)
    upserts = Enum.filter(resumed, &(&1.entity_kind == "device" and &1.entity_id == d2.id))
    assert Enum.map(upserts, & &1.operation) == ["upsert"]
    refute Enum.any?(resumed, &(&1.entity_kind == "device" and &1.entity_id == d1.id))
  end

  test "a multi-page read with writes interleaved between pages converges to the fresh state, every mutation delivered once" do
    scope = user_scope_fixture()
    devices = for _ <- 1..5, do: device_fixture(scope).device
    [_p1a, _p1b, p2a, _p2b, p3] = Enum.sort_by(devices, & &1.id)

    {:ok, page1} = Snapshot.read(scope.user.id, page_size: 2)
    {:ok, as_of} = Cursor.decode(page1.cursor)
    assert page1.has_more

    # Between page 1 and page 2, three independent transactions commit:
    %{device: paired_later} = device_fixture(scope)
    {:ok, _} = Pairing.rename_device(scope, p3.id, "Renamed Between Pages")
    {:ok, _} = Pairing.revoke_device(scope, p2a.id)

    # Every later page is pinned to page 1's as-of position.
    later_pages = read_rest(scope.user.id, as_of, page1.next_after_id)
    assert length(later_pages) >= 1

    pages = page1.entries ++ Enum.flat_map(later_pages, & &1.entries)
    page_ids = Enum.map(pages, & &1.entity_id)

    # Pinned as-of, second-precision timestamps: a device revoked after the
    # position but within the same second as the as-of entry is excluded
    # from its page (`revoked_at > as_of_time` is false); one revoked in a
    # later second stays on the page. Either way its tombstone is in the
    # resumed feed, so the client never retains it — exclusion is the safe
    # direction (`>=` would retain a device revoked just *before* the
    # position, whose tombstone the feed would not carry).
    assert Enum.uniq(page_ids) == page_ids
    expected_ids = devices |> Enum.map(& &1.id) |> Enum.sort()
    seen = Enum.sort(page_ids -- [paired_later.id])
    assert seen == expected_ids or seen == expected_ids -- [p2a.id]

    # The feed resumed from the first page's cursor carries each interleaved
    # mutation exactly once.
    resumed = ChangeJournal.read_after(scope.user.id, as_of, 100)

    by_device = fn id ->
      Enum.filter(resumed, &(&1.entity_kind == "device" and &1.entity_id == id))
    end

    assert Enum.map(by_device.(paired_later.id), & &1.operation) == ["upsert"]
    assert Enum.map(by_device.(p3.id), & &1.operation) == ["upsert"]

    assert by_device.(p3.id) |> hd() |> Map.get(:payload) |> Map.get("name") ==
             "Renamed Between Pages"

    assert Enum.map(by_device.(p2a.id), & &1.operation) == ["tombstone"]

    # Apply pages, then the feed: the result is exactly the fresh state.
    converged =
      pages
      |> Map.new(&{&1.entity_id, &1.payload})
      |> then(fn state ->
        Enum.reduce(resumed, state, fn
          %{entity_kind: "device", operation: "tombstone", entity_id: id}, acc ->
            Map.delete(acc, id)

          %{entity_kind: "device", operation: "upsert", entity_id: id, payload: p}, acc ->
            Map.put(acc, id, atomize(p))

          _, acc ->
            acc
        end)
      end)

    {:ok, fresh} = Snapshot.read(scope.user.id)
    assert converged == Map.new(fresh.entries, &{&1.entity_id, &1.payload})
    refute Map.has_key?(converged, p2a.id)
    assert converged[p3.id].name == "Renamed Between Pages"
    assert Map.has_key?(converged, paired_later.id)

    # Documented scope: a device paired in the *same second* as the pinned
    # as-of entry (second-precision timestamps) can appear on a later page
    # AND as a feed upsert — an idempotent upsert, so convergence holds; it
    # is never skipped. The strict as-of exclusion holds when the clock has
    # advanced, which the interleaved-commit test above proves in-transaction.
    if paired_later.id in page_ids do
      assert length(by_device.(paired_later.id)) == 1
    end
  end

  defp read_rest(user_id, as_of, after_id, acc \\ []) do
    {:ok, page} = Snapshot.read(user_id, page_size: 2, as_of: as_of, after_id: after_id)
    assert page.cursor == Cursor.encode(as_of)

    if page.has_more,
      do: read_rest(user_id, as_of, page.next_after_id, acc ++ [page]),
      else: acc ++ [page]
  end

  defp atomize(payload) when is_map(payload) do
    Map.new(payload, fn {k, v} -> {String.to_existing_atom(k), normalize_value(v)} end)
  end

  defp normalize_value(nil), do: nil

  defp normalize_value(v) when is_binary(v) do
    case DateTime.from_iso8601(v) do
      {:ok, dt, _} -> dt
      _ -> v
    end
  end

  defp normalize_value(v), do: v
end
