defmodule Playstead.CommandId do
  @moduledoc """
  Validation of client-supplied UUIDv7 command/resource identifiers
  (D-20b). The server accepts and validates UUIDv7 identifiers a client
  generates — it never mints its own. `Ecto.UUID.generate/0` produces
  UUIDv4, and RESEARCH.md's Open Question 1 explicitly resolves in this
  direction: adding a dependency purely to mint v7 values the server
  never originates is unjustified unless a concrete code path requires
  it (none does in this plan).
  """

  # RFC 9562 UUIDv7: version nibble `7` at this fixed position, variant
  # bits `10xx` (hex 8/9/a/b) at the next group.
  @v7_regex ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i

  @doc "Whether `value` is a well-formed UUIDv7 string. Rejects UUIDv4, malformed strings, and non-strings."
  @spec valid_v7?(term()) :: boolean()
  def valid_v7?(value) when is_binary(value), do: Regex.match?(@v7_regex, value)
  def valid_v7?(_value), do: false

  @doc """
  Casts `value` to a normalized (lowercase) UUIDv7 string, or `:error`
  if it isn't a well-formed UUIDv7. Ecto-castable: usable directly
  inside a changeset pipeline via `Ecto.Changeset.validate_change/3` or
  a manual `cast/1` call before building changeset attrs.
  """
  @spec cast(term()) :: {:ok, String.t()} | :error
  def cast(value) when is_binary(value) do
    if valid_v7?(value), do: {:ok, String.downcase(value)}, else: :error
  end

  def cast(_value), do: :error
end
