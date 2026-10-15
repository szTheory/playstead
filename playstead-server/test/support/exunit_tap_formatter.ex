defmodule Playstead.TestSupport.ExUnitTapFormatter do
  @moduledoc "Test-only TAP reporter whose output reflects the actual ExUnit events."
  use GenServer

  def init(_opts), do: {:ok, %{results: []}}

  def handle_cast({:test_finished, test}, state) do
    result =
      {test,
       if(test.state == nil,
         do: :pass,
         else: if(match?({:skipped, _}, test.state), do: :skip, else: :fail)
       )}

    {:noreply, %{state | results: [result | state.results]}}
  end

  def handle_cast({:suite_finished, _times}, state) do
    results = Enum.reverse(state.results)

    entries =
      Enum.with_index(results, 1)
      |> Enum.map(fn {{test, status}, index} ->
        name =
          "#{inspect(test.case)}::#{test.name |> Atom.to_string() |> String.replace_prefix("test ", "")}"

        case status do
          :pass -> "ok #{index} - #{name}\n"
          :skip -> "ok #{index} - #{name} # SKIP\n"
          :fail -> "not ok #{index} - #{name}\n"
        end
      end)

    report = IO.iodata_to_binary(["TAP version 13\n", entries, "1..#{length(results)}\n"])

    case System.get_env("PLAYSTEAD_EXUNIT_TAP_PATH") do
      path when is_binary(path) and path != "" -> File.write!(path, report)
      _ -> IO.write(report)
    end

    {:noreply, state}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
