defmodule Playstead.Metadata.GlobalRequestBudget do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: false}
  schema "metadata_request_budgets" do
    field :next_allowed_at, :utc_datetime_usec
    field :updated_at, :utc_datetime_usec
  end
end

defmodule Playstead.Metadata.RequestBudget do
  @moduledoc "Database-coordinated provider request slots shared across all server nodes."
  import Ecto.Query
  alias Playstead.Metadata.GlobalRequestBudget
  alias Playstead.Repo

  @interval_ms 250

  @doc "Reserve the next global slot and wait until it is safe to send one provider request."
  def wait_for_slot do
    case Repo.transaction(fn ->
           row = Repo.one(from b in GlobalRequestBudget, where: b.id == 1, lock: "FOR UPDATE")
           if is_nil(row), do: Repo.rollback(:budget_not_initialized)

           current = now()

           slot =
             if DateTime.compare(row.next_allowed_at, current) == :gt,
               do: row.next_allowed_at,
               else: current

           next = DateTime.add(slot, @interval_ms, :millisecond)

           row
           |> Ecto.Changeset.change(next_allowed_at: next, updated_at: current)
           |> Repo.update!()

           slot
         end) do
      {:ok, slot} ->
        delay = max(0, DateTime.diff(slot, now(), :millisecond))
        if delay > 0, do: Process.sleep(delay)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  def interval_ms, do: @interval_ms

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
