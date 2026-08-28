defmodule Playstead.Attention.QuarantinePolicy do
  @moduledoc """
  Quarantine's only two triggers (D-28): size over a configured cap,
  and a filename violating basic path/character policy. A scanner
  trigger is reserved for a future adapter but not implemented here.
  Deliberately does not know about signature mismatches or archives —
  those route to Needs Attention as `unrecognized` instead, decided by
  the caller, never by this module.
  """

  # A generous default distinct from the D-10 upload ceiling (8 GiB) —
  # this is a separate, configurable policy knob operators can tighten.
  @default_size_cap_bytes 16 * 1024 * 1024 * 1024

  @unsafe_name ~r/(\.\.|\x00|[\x01-\x1F])/

  @doc """
  The quarantine size cap in bytes. `override`, when given, wins over
  the configured value — this is what lets a caller (or a test) supply
  a cap without mutating the shared, process-global application
  environment, which would otherwise race every other concurrently
  running async test that imports a file.
  """
  @spec size_cap_bytes(pos_integer() | nil) :: pos_integer()
  def size_cap_bytes(override \\ nil)
  def size_cap_bytes(override) when is_integer(override), do: override

  def size_cap_bytes(nil) do
    Application.get_env(:playstead, :quarantine_size_cap_bytes, @default_size_cap_bytes)
  end

  @doc "Whether `size_bytes` exceeds the quarantine size cap (optionally overridden)."
  @spec over_size_cap?(non_neg_integer(), pos_integer() | nil) :: boolean()
  def over_size_cap?(size_bytes, cap_override \\ nil),
    do: size_bytes > size_cap_bytes(cap_override)

  @doc """
  Whether `name` violates the name policy: path traversal segments,
  a NUL byte, or a control character. An archive is never quarantined
  merely for being an archive, and a bad extension alone is never a
  name-policy violation — only unsafe characters are.
  """
  @spec name_policy_violation?(String.t() | nil) :: boolean()
  def name_policy_violation?(name) when is_binary(name) do
    Regex.match?(@unsafe_name, name)
  end

  def name_policy_violation?(_name), do: false

  @doc """
  Evaluates both triggers and returns the first one that fires, or
  `nil` when neither policy is violated. `cap_override` overrides the
  configured size cap for this one call only (see `size_cap_bytes/1`).
  """
  @spec evaluate(non_neg_integer(), String.t() | nil, pos_integer() | nil) ::
          :size_over_cap | :name_policy_violation | nil
  def evaluate(size_bytes, name, cap_override \\ nil) do
    cond do
      over_size_cap?(size_bytes, cap_override) -> :size_over_cap
      name_policy_violation?(name) -> :name_policy_violation
      true -> nil
    end
  end
end
