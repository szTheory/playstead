defmodule Playstead.AuditLog do
  @moduledoc """
  Append-only audit log for auth, session, recovery, and (from plan 01-04
  onward) pairing events (D-05a, D-12).

  `record/3` is the only write path — this module intentionally defines no
  update or delete function (T-01-18). Event names are lowercase snake_case
  verbs in the past tense, namespaced by area: `session_revoked`,
  `sudo_confirmed`, `password_reset_issued`, `recovery_code_consumed`, and
  the pairing events plan 01-04 adds.

  `metadata` must never carry credential material or a plaintext token.
  """

  import Ecto.Query, warn: false
  alias Playstead.Repo
  alias Playstead.AuditLog.Entry

  @doc """
  Records an audit entry for `user_id` (may be `nil` for a system-level
  event with no associated account) and `event` (an atom). `metadata` is a
  map merged onto the entry; an optional `:subject` key is pulled out into
  the entry's dedicated `subject` column (a free-form identifier such as a
  session or device id) rather than stored inside `metadata` itself.
  """
  @spec record(integer() | nil, atom(), map()) :: {:ok, Entry.t()} | {:error, Ecto.Changeset.t()}
  def record(user_id, event, metadata \\ %{}) when is_atom(event) and is_map(metadata) do
    {subject, metadata} = Map.pop(metadata, :subject)

    %Entry{}
    |> Entry.changeset(%{
      user_id: user_id,
      event: Atom.to_string(event),
      subject: subject,
      metadata: stringify_keys(metadata)
    })
    |> Repo.insert()
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} -> {to_string(k), v} end)
  end

  @doc """
  Lists audit entries for `user_id`, most recent first. `opts[:limit]`
  bounds the result set (default 100).
  """
  @spec list(integer(), keyword()) :: [Entry.t()]
  def list(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    Entry
    |> where([e], e.user_id == ^user_id)
    |> order_by([e], desc: e.inserted_at, desc: e.id)
    |> limit(^limit)
    |> Repo.all()
  end
end
