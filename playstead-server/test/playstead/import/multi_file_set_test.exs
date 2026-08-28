defmodule Playstead.Import.MultiFileSetTest do
  @moduledoc """
  IMPT-04, D-15: ordered multi-file manifests, incomplete sets that
  complete later without duplication, and the concurrency guarantee a
  unique index on `(asset_set_id, ordinal)` provides (task 3 of
  02-03-PLAN.md).
  """

  use Playstead.DataCase, async: false

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Playstead.Blobs
  alias Playstead.Catalogue.AssetMember
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import
  alias Playstead.Repo

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    :ok
  end

  defp store!(bytes) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    {status, meta}
  end

  defp cue_attrs(name \\ "game.cue", size_bytes \\ 64) do
    %{original_name: name, origin: "upload", size_bytes: size_bytes}
  end

  test "a descriptor and its companion imported together produce one asset set with two members at ordinals 1 and 2" do
    %{user: user} = user_scope_fixture()
    cue_bytes = random_bytes(64)
    bin_bytes = random_bytes(2_048)

    descriptor_store = store!(cue_bytes)
    companion_store = store!(bin_bytes)

    {:ok, %{asset_set: asset_set, receipts: [descriptor_receipt | _]}} =
      Import.import_descriptor_set(
        user.id,
        cue_attrs(),
        descriptor_store,
        ["game.bin"],
        %{"game.bin" => companion_store}
      )

    members =
      AssetMember
      |> where([m], m.asset_set_id == ^asset_set.id)
      |> order_by(:ordinal)
      |> Repo.all()

    assert Enum.map(members, & &1.ordinal) == [0, 1]
    assert asset_set.status == "complete"
    assert descriptor_receipt.outcome == "new_asset"
  end

  test "each member carries a role from the frozen role vocabulary and an explicit required flag" do
    %{user: user} = user_scope_fixture()
    descriptor_store = store!(random_bytes(64))

    {:ok, %{asset_set: asset_set}} =
      Import.import_descriptor_set(user.id, cue_attrs(), descriptor_store, ["game.bin"], %{})

    members = AssetMember |> where([m], m.asset_set_id == ^asset_set.id) |> Repo.all()

    assert Enum.all?(
             members,
             &(&1.role in ~w(descriptor track primary disc patch parent companion))
           )

    assert Enum.all?(members, & &1.required)
  end

  test "a descriptor imported alone produces an incomplete_set receipt whose detail names the missing declared name" do
    %{user: user} = user_scope_fixture()
    descriptor_store = store!(random_bytes(64))

    {:ok, %{asset_set: asset_set, receipts: [descriptor_receipt]}} =
      Import.import_descriptor_set(user.id, cue_attrs(), descriptor_store, ["game.bin"], %{})

    assert descriptor_receipt.outcome == "incomplete_set"
    assert descriptor_receipt.reason =~ "game.bin"
    assert asset_set.status == "incomplete"
  end

  test "importing the missing companion afterwards completes the existing set and creates no second set" do
    %{user: user} = user_scope_fixture()
    descriptor_store = store!(random_bytes(64))

    {:ok, %{asset_set: asset_set}} =
      Import.import_descriptor_set(user.id, cue_attrs(), descriptor_store, ["game.bin"], %{})

    bin_bytes = random_bytes(2_048)
    companion_store = store!(bin_bytes)

    {:ok, receipt} =
      Import.attach_companion(
        user.id,
        "game.bin",
        %{original_name: "game.bin", origin: "upload", size_bytes: byte_size(bin_bytes)},
        companion_store
      )

    assert receipt.outcome == "new_asset"
    assert Repo.aggregate(from(a in AssetSet, where: a.user_id == ^user.id), :count) == 1

    updated_set = Repo.get!(AssetSet, asset_set.id)
    assert updated_set.status == "complete"
  end

  test "the set's member_fingerprint is recomputed when membership changes" do
    %{user: user} = user_scope_fixture()
    descriptor_store = store!(random_bytes(64))

    {:ok, %{asset_set: asset_set}} =
      Import.import_descriptor_set(user.id, cue_attrs(), descriptor_store, ["game.bin"], %{})

    incomplete_fingerprint = asset_set.member_fingerprint

    bin_bytes = random_bytes(2_048)
    companion_store = store!(bin_bytes)

    {:ok, _receipt} =
      Import.attach_companion(
        user.id,
        "game.bin",
        %{original_name: "game.bin", origin: "upload", size_bytes: byte_size(bin_bytes)},
        companion_store
      )

    updated_set = Repo.get!(AssetSet, asset_set.id)
    assert updated_set.member_fingerprint != incomplete_fingerprint
  end

  test "a declared name that must be sanitized for filesystem use is still stored unchanged as the declared name" do
    %{user: user} = user_scope_fixture()
    unsafe_name = "../evil:name?.bin"
    descriptor_store = store!(random_bytes(64))

    {:ok, %{asset_set: asset_set}} =
      Import.import_descriptor_set(user.id, cue_attrs(), descriptor_store, [unsafe_name], %{})

    member = Repo.get_by!(AssetMember, asset_set_id: asset_set.id, ordinal: 1)
    assert member.declared_name == unsafe_name
  end
end

defmodule Playstead.Import.MultiFileConcurrencyTest do
  @moduledoc """
  D-11/IMPT-04 concurrency under *real* Postgres connections (mirrors
  `Playstead.Blobs.CasRaceTest`): the Ecto sandbox normally runs a
  whole test on one shared connection, which can only prove the
  on_conflict code path handles a unique-constraint violation, not that
  two genuinely simultaneous processes racing to complete the same
  descriptor set converge on one row. This module switches to `:auto`
  sandbox mode for its own duration so each task gets its own pooled
  connection and the race is real.
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  import Ecto.Query
  import Playstead.AccountsFixtures
  import Playstead.ImportFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Playstead.Blobs
  alias Playstead.Catalogue.AssetMember
  alias Playstead.Catalogue.AssetSet
  alias Playstead.Import
  alias Playstead.Repo

  setup_all do
    Sandbox.mode(Repo, :auto)
    on_exit(fn -> Sandbox.mode(Repo, :manual) end)
    :ok
  end

  setup do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())

    on_exit(fn ->
      Repo.query!(
        "TRUNCATE asset_members, asset_sets, source_files, blobs, blob_fingerprints, recognitions, import_receipts, users RESTART IDENTITY CASCADE"
      )
    end)

    :ok
  end

  defp store!(bytes) do
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))
    {status, meta}
  end

  test "two concurrent imports that each complete the same set result in one set with exactly one row per ordinal" do
    %{user: user} = user_scope_fixture()
    cue_bytes = random_bytes(64)
    cue_attrs = %{original_name: "game.cue", origin: "upload", size_bytes: byte_size(cue_bytes)}

    tasks =
      for _ <- 1..5 do
        Task.async(fn ->
          descriptor_store = store!(cue_bytes)
          Import.import_descriptor_set(user.id, cue_attrs, descriptor_store, ["game.bin"], %{})
        end)
      end

    results = Task.await_many(tasks, 15_000)
    assert Enum.all?(results, &match?({:ok, _}, &1))

    assert Repo.aggregate(from(a in AssetSet, where: a.user_id == ^user.id), :count) == 1

    asset_set = Repo.get_by!(AssetSet, user_id: user.id)

    ordinals =
      from(m in AssetMember, where: m.asset_set_id == ^asset_set.id, select: m.ordinal)
      |> Repo.all()

    assert Enum.sort(ordinals) == Enum.uniq(Enum.sort(ordinals))
  end
end
