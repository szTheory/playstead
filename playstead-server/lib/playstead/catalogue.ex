defmodule Playstead.Catalogue do
  @moduledoc """
  The user-scoped logical catalogue context: `Playstead.Catalogue.AssetSet`
  and `Playstead.Catalogue.AssetMember`. `member_fingerprint/1` is the
  natural key that makes "no duplicate logical record" a database
  guarantee via the unique index on the user/fingerprint pair (D-37).
  """

  @doc """
  D-37's natural key: the SHA-256 over the canonical sorted list of
  role-and-hash member pairs. Sorting makes the value independent of
  member insertion order; only `role` and `sha256` participate, so the
  vocabulary of roles and statuses can grow later without changing any
  existing fingerprint.
  """
  @spec member_fingerprint([%{role: String.t(), sha256: String.t() | nil}]) :: String.t()
  def member_fingerprint(members) when is_list(members) do
    canonical =
      members
      |> Enum.map(fn %{role: role, sha256: sha256} -> "#{role}:#{sha256}" end)
      |> Enum.sort()
      |> Enum.join("|")

    :crypto.hash(:sha256, canonical) |> Base.encode16(case: :lower)
  end
end
