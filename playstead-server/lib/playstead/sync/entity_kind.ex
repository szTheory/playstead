defmodule Playstead.Sync.EntityKind do
  @moduledoc """
  The published change-journal entity-kind vocabulary (PROT-05, D-18,
  D-21). All six kinds a client will ever need to reconstruct are
  registered here now, even though only `device` and `pairing` have
  producers in this phase — freezing the vocabulary means a later phase
  attaches a producer for `catalogue`, `job`, `transfer`, or `save`
  without a protocol change, and `Playstead.Sync.Entry`'s changeset
  validates every write against this list so a later phase cannot
  silently introduce an unregistered kind.
  """

  @kinds ~w(device pairing catalogue job transfer save)a

  @doc "The full, frozen set of registered entity kinds."
  @spec all() :: [atom()]
  def all, do: @kinds

  @doc "Whether `kind` (an atom or its string form) is a registered entity kind."
  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(kind) when kind in @kinds, do: true

  def valid?(kind) when is_binary(kind) do
    kind in Enum.map(@kinds, &to_string/1)
  end

  def valid?(_kind), do: false
end
