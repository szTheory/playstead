defmodule Playstead.Formats.SystemId do
  @moduledoc """
  The frozen, closed system-identifier registry (D-14). Copies
  `Playstead.Sync.EntityKind`'s shape exactly: a module attribute list,
  `all/0`, and `valid?/1` accepting atom and string forms.

  These eight strings — the seven supported systems plus `unknown` —
  are published vocabulary: they travel into export manifests
  (`playstead-set.json`) and into the client change journal's
  `catalogue` payload (D-23). A later phase attaches recognition
  providers for these systems without ever changing this list.
  Adapter-facing names (emulator core identifiers, launcher folder
  names such as RetroArch cores or ES-DE system folders) are a
  client-side mapping and are never server truth.
  """

  @systems ~w(gba gb gbc nes snes md psx unknown)a

  @doc "The full, frozen set of registered system identifiers."
  @spec all() :: [atom()]
  def all, do: @systems

  @doc "Whether `id` (an atom or its string form) is a registered system identifier."
  @spec valid?(atom() | String.t() | term()) :: boolean()
  def valid?(id) when id in @systems, do: true

  def valid?(id) when is_binary(id) do
    id in Enum.map(@systems, &to_string/1)
  end

  def valid?(_id), do: false
end
