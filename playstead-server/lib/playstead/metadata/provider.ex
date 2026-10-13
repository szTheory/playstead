defmodule Playstead.Metadata.Provider do
  @moduledoc "Provider boundary for optional, owner-consented presentation evidence."

  @callback name() :: String.t()
  @callback version() :: String.t()
  @callback search(title :: String.t(), system :: String.t(), opts :: keyword()) ::
              {:ok, [map()]} | {:error, term()}
end
