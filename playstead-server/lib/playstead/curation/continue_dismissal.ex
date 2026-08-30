defmodule Playstead.Curation.ContinueDismissal do
  @moduledoc """
  Records that `user_id` explicitly dismissed `asset_set_id` from
  Continue (D-07). Continue = Recent minus explicitly dismissed games;
  a session started after `dismissed_at` restores the game to Continue
  without needing an explicit undismiss. `id` is client-supplied; the
  unique index on `(user_id, asset_set_id)` is what makes dismissing
  an already-dismissed game converge instead of duplicating.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id
  schema "curation_continue_dismissals" do
    field :user_id, :id
    field :asset_set_id, :binary_id
    field :dismissed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc false
  def create_changeset(dismissal, attrs) do
    dismissal
    |> cast(attrs, [:id, :user_id, :asset_set_id, :dismissed_at])
    |> validate_required([:id, :user_id, :asset_set_id, :dismissed_at])
    |> unique_constraint([:user_id, :asset_set_id],
      name: :curation_continue_dismissals_user_id_asset_set_id_index
    )
  end

  @type t :: %__MODULE__{}
end
