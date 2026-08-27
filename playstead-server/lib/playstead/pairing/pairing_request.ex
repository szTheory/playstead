defmodule Playstead.Pairing.PairingRequest do
  @moduledoc """
  A single pairing ceremony (D-07). Persisted state machine: `pending`
  transitions to `approved`, `denied`, or `expired`; `approved` transitions
  to `redeemed` exactly once (task 2). All state lives in Postgres —
  RESEARCH.md names LiveView process state as the specific wrong home for
  pairing facts, since LiveView re-runs mount on reconnect.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @statuses ~w(pending approved denied expired redeemed)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "pairing_requests" do
    field :device_code_hash, :string
    field :display_code, :string
    field :claimed_device_name, :string
    field :claimed_platform, :string
    field :claimed_app_version, :string
    field :claimed_capabilities, :map, default: %{}
    field :requesting_ip, :string
    field :status, :string, default: "pending"
    field :approved_by_user_id, :id
    field :expires_at, :utc_datetime
    field :redeemed_at, :utc_datetime

    # usec precision: eviction relies on strict inserted_at ordering to
    # pick a single "oldest pending" row (see migration comment).
    timestamps(type: :utc_datetime_usec)
  end

  @doc "The full set of valid persisted statuses."
  def statuses, do: @statuses

  @doc false
  def create_changeset(request, attrs) do
    request
    |> cast(attrs, [
      :device_code_hash,
      :display_code,
      :claimed_device_name,
      :claimed_platform,
      :claimed_app_version,
      :claimed_capabilities,
      :requesting_ip,
      :expires_at
    ])
    |> validate_required([:device_code_hash, :display_code, :expires_at])
    |> put_change(:status, "pending")
    |> unique_constraint(:device_code_hash)
  end

  @doc false
  def status_changeset(request, status) when status in @statuses do
    change(request, status: status)
  end

  @doc """
  Whether this request is past its 10-minute expiry window (D-12).
  Re-derived on every read — expiry is never a background-job-only fact.
  """
  @spec expired?(t()) :: boolean()
  def expired?(%__MODULE__{expires_at: expires_at}) do
    DateTime.compare(DateTime.utc_now(), expires_at) == :gt
  end

  @doc """
  The status this request effectively reports right now: `pending`
  requests past their `expires_at` report `expired` even if no
  background sweep has run yet (D-12).
  """
  @spec effective_status(t()) :: String.t()
  def effective_status(%__MODULE__{status: "pending"} = request) do
    if expired?(request), do: "expired", else: "pending"
  end

  def effective_status(%__MODULE__{status: status}), do: status

  @type t :: %__MODULE__{}
end
