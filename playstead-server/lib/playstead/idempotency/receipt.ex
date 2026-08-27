defmodule Playstead.Idempotency.Receipt do
  @moduledoc """
  A per-device idempotency receipt (D-20a). Unique on `{device_id,
  idempotency_key}` — that unique index is the concurrency primitive: an
  in-flight marker inserted at the start of processing makes a racing
  retry's insert fail, which is what produces the 409 rather than a
  second effect (see `Playstead.Idempotency.execute/4`).

  `state` is `"in_flight"` while the wrapped effect runs and
  `"complete"` once the response is recorded. `expires_at` drives
  `prune_expired/0`'s ~90-day retention horizon.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @states ~w(in_flight complete)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "idempotency_receipts" do
    field :device_id, :binary_id
    field :idempotency_key, :string
    field :request_fingerprint, :string
    field :response_status, :integer
    field :response_body, :string
    field :state, :string, default: "in_flight"
    field :expires_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @doc "The full set of valid persisted states."
  def states, do: @states

  @doc false
  def create_changeset(receipt, attrs) do
    receipt
    |> cast(attrs, [:device_id, :idempotency_key, :request_fingerprint, :expires_at])
    |> validate_required([:device_id, :idempotency_key, :request_fingerprint, :expires_at])
    |> put_change(:state, "in_flight")
    |> unique_constraint([:device_id, :idempotency_key],
      name: :idempotency_receipts_device_id_idempotency_key_index
    )
  end

  @doc false
  def complete_changeset(receipt, response_status, response_body) do
    receipt
    |> change(state: "complete", response_status: response_status, response_body: response_body)
  end

  @type t :: %__MODULE__{}
end
