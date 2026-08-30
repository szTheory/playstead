defmodule Playstead.Sync.EntityKind do
  @moduledoc """
  The published change-journal entity-kind vocabulary (PROT-05, D-18,
  D-21). All six original kinds a client will ever need to reconstruct
  were registered here up front, even though only `device` and
  `pairing` had producers in Phase 1 — freezing the vocabulary means a
  later phase attaches a producer for `catalogue`, `job`, `transfer`,
  or `save` without a protocol change, and `Playstead.Sync.Entry`'s
  changeset validates every write against this list so a later phase
  cannot silently introduce an unregistered kind.

  ## D-08: the `curation` kind (Phase 3, additive amendment)

  `curation` is added here deliberately, in Phase 3, before any native
  client has shipped. This is a logged exception to "the six kinds are
  frozen": the freeze's protected property is that `Entry`'s changeset
  rejects any kind not in this list, so nothing is written silently —
  amending the registry additively, before a client exists to be
  broken, preserves that property exactly. The same addition after a
  client ships would require capability gating (P1 D-18's
  additive-minor rule) instead of a bare registry change. No existing
  kind is ever renamed or removed; only additions are legitimate here.
  """

  @kinds ~w(device pairing catalogue job transfer save curation)a

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
