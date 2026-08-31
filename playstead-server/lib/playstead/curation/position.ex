defmodule Playstead.Curation.Position do
  @moduledoc """
  Fractional-index string ordering for D-09/D-10's ordered lists
  (collections, collection members, the play queue). A position is a
  string over a fixed base-36 alphabet (`"0-9a-z"`), compared with
  plain string ordering, so listing an ordered table is a plain
  `ORDER BY position` index scan — no CRDT, no per-row renumbering on
  every insert.

  ## Encoding

  A position string is read as digits after a decimal point in base
  36 (`0.d1 d2 d3 ...`). Two positions are compared by padding the
  shorter one with the zero digit ("0") at its end — which never
  changes its value (`0.5 == 0.50`) — then comparing byte-for-byte,
  which is exactly what a database index scan does. `between/2`
  computes the arithmetic midpoint of two such fractions, extending
  precision by one digit at a time only when the two values are
  digit-adjacent at their current length (ties are broken by
  appending to the lower bound's encoding, per D-09).

  `between/2` itself never fails — it always finds a value strictly
  between two distinct bounds by growing precision as far as needed.
  `needs_rebalance?/2` is the proactive signal: it reports `true` when
  two neighbours are close enough that continuing to insert between
  them would keep growing position strings past a practical precision
  budget, so the caller should rebalance the surrounding list (spread
  positions back out via `spaced/1`) instead of inserting again.
  """

  @alphabet ~c"0123456789abcdefghijklmnopqrstuvwxyz"
  @base length(@alphabet)
  @zero_index 0
  @max_precision 6

  @char_to_index @alphabet |> Enum.with_index() |> Map.new()

  @first List.to_string([Enum.at(@alphabet, div(@base, 2))])

  @doc "A position for the first item of an otherwise-empty ordered list."
  @spec first() :: String.t()
  def first, do: @first

  @doc """
  A position after `current_last` — `nil` means the list is currently
  empty, so this is equivalent to `first/0`.
  """
  @spec last(String.t() | nil) :: String.t()
  def last(nil), do: first()
  def last(current_last), do: between(current_last, nil)

  @doc """
  A position strictly between `low` and `high`. Either may be `nil` to
  mean "start of the list" or "end of the list" respectively; both
  `nil` means "the list is empty" (equivalent to `first/0`). `low` and
  `high`, when both given, must be distinct and `low < high`.
  """
  @spec between(String.t() | nil, String.t() | nil) :: String.t()
  def between(nil, nil), do: first()
  def between(nil, high), do: prepend_before(to_digits(high))
  def between(low, nil), do: append_after(to_digits(low))

  def between(low, high) when is_binary(low) and is_binary(high) do
    if low < high do
      midpoint(to_digits(low), to_digits(high))
    else
      raise ArgumentError,
            "Position.between/2 requires low < high, got low=#{inspect(low)} high=#{inspect(high)}"
    end
  end

  @doc """
  Whether inserting between `low` and `high` would need to grow
  position strings past #{@max_precision} digits of precision — a
  signal to rebalance the surrounding list rather than insert again.
  """
  @spec needs_rebalance?(String.t(), String.t()) :: boolean()
  def needs_rebalance?(low, high) do
    low_digits = to_digits(low)
    high_digits = to_digits(high)
    len = max(length(low_digits), length(high_digits)) |> max(1)
    check_room(pad_int(low_digits, len), pad_int(high_digits, len), len)
  end

  @doc """
  `count` distinct, ascending, evenly spaced positions. Used by
  `Playstead.Curation`'s rebalance functions to reassign positions for
  a whole ordered list at once, preserving the current visible order.
  """
  @spec spaced(non_neg_integer()) :: [String.t()]
  def spaced(0), do: []

  def spaced(count) when is_integer(count) and count > 0 do
    precision = spaced_precision(count)
    denom = Integer.pow(@base, precision)

    for rank <- 1..count do
      value = div(rank * denom, count + 1)
      encode(value, precision)
    end
  end

  # --- internals ---

  defp spaced_precision(count) do
    Enum.reduce_while(1..64, 1, fn p, _ ->
      if Integer.pow(@base, p) > count, do: {:halt, p}, else: {:cont, p + 1}
    end)
  end

  defp check_room(low_int, high_int, len) do
    cond do
      high_int - low_int >= 2 -> false
      len >= @max_precision -> true
      true -> check_room(low_int * @base, high_int * @base, len + 1)
    end
  end

  # Appends after `digits` (no upper bound). Increments the last digit
  # when there's room, so a run of sequential appends grows the
  # position string by only one digit roughly every `base` appends
  # (amortized O(log_base(n))) — the naive "bisect toward an infinite
  # ceiling" approach this replaced needed a growing number of digits
  # on almost every single append, which blew straight through a
  # `varchar(255)` column under a few hundred sequential inserts.
  #
  # Appending *any* non-zero digit to a value strictly increases it
  # (`0.xy` < `0.xy1`), so extension appends the digit `1` (not `0`,
  # which would be a same-value no-op, and not the middle digit, which
  # would only leave half the base-36 range of headroom before the
  # *next* extension — halving the headroom per level roughly doubles
  # how many digits a long run of sequential appends needs).
  defp append_after(digits) do
    case List.pop_at(digits, -1) do
      {last, rest} when last < @base - 1 -> digits_to_string(rest ++ [last + 1])
      _ -> digits_to_string(digits ++ [1])
    end
  end

  # The mirror of `append_after/1` for prepending before `digits` (no
  # lower bound). Unlike appending, appending a digit can only ever
  # *increase* a value, so "decrement the last digit" alone isn't
  # enough when that digit is already 0 -- `decrement/1` borrows from
  # the nearest non-zero digit to its left, same as decrementing an
  # ordinary base-36 integer that ends in zeros.
  defp prepend_before(digits) do
    case decrement(digits) do
      {:ok, new_digits} -> digits_to_string(new_digits)
      # digits was already the all-zero minimum -- there is no smaller
      # value representable in this unsigned scheme. Unreachable via
      # any position this module itself ever generates (first/0 is the
      # middle digit, spaced/1 never emits all-zero); kept as a
      # non-crashing fallback rather than a `raise`.
      :no_room -> digits_to_string(digits ++ [0])
    end
  end

  defp decrement(digits) do
    digits
    |> Enum.reverse()
    |> do_decrement()
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      :no_room -> :no_room
    end
  end

  defp do_decrement([]), do: :no_room
  defp do_decrement([d | rest]) when d > 0, do: {:ok, [d - 1 | rest]}

  defp do_decrement([0 | rest]) do
    case do_decrement(rest) do
      {:ok, new_rest} -> {:ok, [@base - 1 | new_rest]}
      :no_room -> :no_room
    end
  end

  defp midpoint(low_digits, high_digits) do
    len = max(length(low_digits), length(high_digits)) |> max(1)
    low_int = pad_int(low_digits, len)
    high_int = pad_int(high_digits, len)
    do_midpoint(low_int, high_int, len)
  end

  defp do_midpoint(low_int, high_int, len) do
    if high_int - low_int >= 2 do
      encode(div(low_int + high_int, 2), len)
    else
      do_midpoint(low_int * @base, high_int * @base, len + 1)
    end
  end

  defp pad_int(digits, len) do
    padded = digits ++ List.duplicate(@zero_index, len - length(digits))
    Enum.reduce(padded, 0, fn d, acc -> acc * @base + d end)
  end

  defp encode(int, len) do
    int
    |> int_to_digits(len)
    |> strip_trailing_zeros()
    |> digits_to_string()
  end

  defp int_to_digits(int, len) do
    {_, digits} =
      Enum.reduce(1..len, {int, []}, fn _, {n, acc} ->
        {div(n, @base), [rem(n, @base) | acc]}
      end)

    digits
  end

  defp strip_trailing_zeros(digits) do
    case digits |> Enum.reverse() |> Enum.drop_while(&(&1 == @zero_index)) |> Enum.reverse() do
      [] -> [@zero_index]
      d -> d
    end
  end

  defp to_digits(nil), do: []

  defp to_digits(string) when is_binary(string) do
    string |> String.to_charlist() |> Enum.map(&Map.fetch!(@char_to_index, &1))
  end

  defp digits_to_string(digits) do
    digits |> Enum.map(&Enum.at(@alphabet, &1)) |> List.to_string()
  end
end
