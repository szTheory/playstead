defmodule PlaysteadWeb.AvailabilityVocabularyContractTest do
  @moduledoc """
  Plan 03-13 (LIBR-02 gap closure): proves `Playstead.AvailabilityVocabulary`
  and `shared/availability-vocabulary.json` (D-67-style test fixture)
  cannot drift apart -- exhaustively, in both directions -- over the six
  frozen filter values, their labels, and their accessible names. The
  JSON is read here as a test resource only; no shipped Elixir code
  path ever reads it (see `Playstead.AvailabilityVocabulary`'s
  moduledoc).
  """

  use ExUnit.Case, async: true

  alias Playstead.AvailabilityVocabulary

  defp json_vocabulary! do
    path = Path.join([File.cwd!(), "..", "shared", "availability-vocabulary.json"])
    path |> File.read!() |> Jason.decode!()
  end

  test "every module value's label and accessible_name exist in the JSON with identical values" do
    json = json_vocabulary!()

    for value <- AvailabilityVocabulary.values() do
      label_key = "filter.#{value}.label"
      name_key = "filter.#{value}.accessible_name"

      assert Map.fetch(json, label_key) == {:ok, AvailabilityVocabulary.label(value)},
             "module label for #{value} must match the JSON vocabulary"

      assert Map.fetch(json, name_key) == {:ok, AvailabilityVocabulary.accessible_name(value)},
             "module accessible_name for #{value} must match the JSON vocabulary"
    end
  end

  test "the JSON declares exactly six values, one label and one accessible_name each" do
    json = json_vocabulary!()
    assert map_size(json) == 12

    json_values =
      json
      |> Map.keys()
      |> Enum.map(fn key -> key |> String.split(".") |> Enum.at(1) end)
      |> Enum.uniq()
      |> Enum.sort()

    assert json_values == Enum.sort(AvailabilityVocabulary.values())
  end

  test "a JSON key with no matching module value would be caught" do
    json = json_vocabulary!() |> Map.put("filter.phantom_value.label", "Phantom")

    json_values =
      json
      |> Map.keys()
      |> Enum.map(fn key -> key |> String.split(".") |> Enum.at(1) end)
      |> Enum.uniq()
      |> Enum.sort()

    refute json_values == Enum.sort(AvailabilityVocabulary.values())
  end

  test "a module value missing from the JSON would be caught" do
    json = json_vocabulary!() |> Map.delete("filter.queued.label")

    assert Map.fetch(json, "filter.queued.label") != {:ok, AvailabilityVocabulary.label("queued")}
  end

  test "valid?/1 never converts a client-supplied value to an atom" do
    refute AvailabilityVocabulary.valid?("not_a_real_value")
    assert AvailabilityVocabulary.valid?("ready_offline")
    refute AvailabilityVocabulary.valid?(nil)
  end
end
