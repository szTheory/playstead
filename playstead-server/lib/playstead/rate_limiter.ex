defmodule Playstead.RateLimiter do
  @moduledoc """
  Hammer-backed fixed-window rate limiter (D-06 chose `hammer` in plan
  01-01; this is the only rate-limiting library in the application — see
  `PlaysteadWeb.Plugs.Throttle`, its sole caller). ETS-backed, single-node.
  """

  use Hammer, backend: :ets
end
