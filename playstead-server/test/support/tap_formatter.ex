defmodule Playstead.TestSupport.TapFormatter do
  @moduledoc false
  use GenServer

  def init(_opts), do: {:ok, []}

  def handle_cast({:test_finished, test}, tests), do: {:noreply, [test | tests]}

  def handle_cast({:suite_finished, _times}, tests) do
    tests = Enum.reverse(tests)
    IO.puts("TAP version 13")

    tests
    |> Enum.with_index(1)
    |> Enum.each(fn {test, index} ->
      status = if is_nil(test.state), do: "ok", else: "not ok"
      IO.puts("#{status} #{index} - #{inspect(test.module)}::#{test.name}")
    end)

    IO.puts("1..#{length(tests)}")
    {:noreply, tests}
  end

  def handle_cast(_event, state), do: {:noreply, state}
end
