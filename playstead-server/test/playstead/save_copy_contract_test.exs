defmodule Playstead.SaveCopyContractTest do
  @moduledoc """
  Plan 04-09 task 1: proves `shared/save-vocabulary.json` (D-67) and the
  console's partial `Playstead.SaveVocabulary` mirror cannot drift apart --
  exhaustively, in both directions, never merely "matching". The JSON is
  read here as a test resource only; no shipped Elixir code path ever
  reads it (see `Playstead.SaveVocabulary`'s moduledoc).
  """

  use ExUnit.Case, async: true

  @banned_words ~w(sha256 digest hash cursor journal parent base head
                    ancestor revision blob CAS LWW merge sync uploaded)
  @banned_phrases ["idempotency key", "backed up"]
  @banned_divergence_words ~w(conflict overwrite lost wins loser merge error
                               failed corrupt stale invalid)
  @banned_divergence_phrases ["you should have"]
  @divergence_prefixes ["attention.", "compare.", "result.", "danger."]

  defp json_vocabulary! do
    path = Path.join([File.cwd!(), "..", "shared", "save-vocabulary.json"])
    path |> File.read!() |> Jason.decode!()
  end

  test "the JSON vocabulary's console subset exactly matches Playstead.SaveVocabulary" do
    json = json_vocabulary!()
    assert map_size(json) >= 50

    console = Playstead.SaveVocabulary.all()
    # Exhaustive equality over the console's declared subset: every key
    # this module declares must exist in the JSON with an identical
    # value -- a removed JSON key or a differing value fails this loop.
    for {key, value} <- console do
      assert Map.fetch(json, key) == {:ok, value},
             "console key #{key} must exist in the JSON vocabulary with an identical value"
    end
  end

  # -- Negative case: both drift directions are actually caught --

  defp diff(vocabulary, emitted) do
    vocab_keys = vocabulary |> Map.keys() |> MapSet.new()
    emitted_keys = emitted |> Map.keys() |> MapSet.new()

    %{
      missing_from_vocabulary: MapSet.difference(emitted_keys, vocab_keys),
      unused_in_vocabulary: MapSet.difference(vocab_keys, emitted_keys)
    }
  end

  test "an emitted, unlisted string is caught" do
    vocabulary = %{"a" => "Alpha"}
    emitted = %{"a" => "Alpha", "b" => "Beta"}
    result = diff(vocabulary, emitted)
    assert result.missing_from_vocabulary == MapSet.new(["b"])
  end

  test "an unused vocabulary key is caught" do
    vocabulary = %{"a" => "Alpha", "b" => "Beta"}
    emitted = %{"a" => "Alpha"}
    result = diff(vocabulary, emitted)
    assert result.unused_in_vocabulary == MapSet.new(["b"])
  end

  test "matching sets produce no drift" do
    vocabulary = %{"a" => "Alpha"}
    emitted = %{"a" => "Alpha"}
    result = diff(vocabulary, emitted)
    assert Enum.empty?(result.missing_from_vocabulary)
    assert Enum.empty?(result.unused_in_vocabulary)
  end

  # -- Every declared console key names a real, compiled Elixir constant --

  test "every console vocabulary key names a real compiled value" do
    console = Playstead.SaveVocabulary.all()
    assert map_size(console) > 0

    for {key, value} <- console do
      assert Playstead.SaveVocabulary.all()[key] == value
    end
  end

  # -- Banned words --

  defp whole_word_hits(words, value) do
    downcased = String.downcase(value)

    Enum.filter(words, fn word ->
      Regex.match?(~r/\b#{Regex.escape(String.downcase(word))}\b/, downcased)
    end)
  end

  test "banned words never appear in any vocabulary value" do
    json = json_vocabulary!()

    for {key, value} <- json do
      hits = whole_word_hits(@banned_words ++ @banned_phrases, value)
      assert hits == [], "key #{key} contains banned word(s) #{inspect(hits)}: #{value}"
    end
  end

  test "divergence-banned words never appear in divergence copy" do
    json = json_vocabulary!()

    json
    |> Enum.filter(fn {key, _value} ->
      Enum.any?(@divergence_prefixes, &String.starts_with?(key, &1))
    end)
    |> Enum.each(fn {key, value} ->
      hits = whole_word_hits(@banned_divergence_words ++ @banned_divergence_phrases, value)

      assert hits == [],
             "divergence key #{key} contains banned word(s) #{inspect(hits)}: #{value}"
    end)
  end

  test "the banned-word scan catches a real violation" do
    assert whole_word_hits(@banned_words ++ @banned_phrases, "This save was backed up.") == [
             "backed up"
           ]

    assert whole_word_hits(@banned_words ++ @banned_phrases, "It has not been merged.") == []

    assert whole_word_hits(@banned_words ++ @banned_phrases, "the next time they sync.") == [
             "sync"
           ]
  end
end
