if Mix.env() in [:dev, :test] do
  defmodule PlaysteadWeb.Api.V1.DebugController do
    @moduledoc """
    Dev/test-only. Gives the forced-500 problem+json contract test a
    real route that deliberately raises, proving
    `PlaysteadWeb.Plugs.ApiProblemHandler` catches an unhandled
    exception, not just an expected error tuple (D-22, RESEARCH.md
    Pitfall 2). Never compiled into a production release.
    """

    use PlaysteadWeb, :controller

    def boom(_conn, _params) do
      raise "deliberate test exception"
    end
  end
end
