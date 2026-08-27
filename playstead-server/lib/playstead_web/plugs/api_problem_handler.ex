defmodule PlaysteadWeb.Plugs.ApiProblemHandler do
  @moduledoc """
  Closes the framework-level gap RESEARCH.md Pitfall 2 warns about: a
  fallback-controller-only implementation of RFC 9457 passes its own
  tests while still leaking Phoenix's default HTML/JSON error page for
  an unmatched route or an unhandled exception.

  `use PlaysteadWeb.Plugs.ApiProblemHandler` in `PlaysteadWeb.Router`
  wraps the router's own `call/2` in a try/rescue (the same mechanism
  `Plug.ErrorHandler` uses), so this fires *before* an exception raised
  anywhere beneath the router — including `Phoenix.Router.NoRouteError`
  for an unmatched path — can reach the endpoint's default
  `render_errors` HTML/JSON rendering.

  Unlike `Plug.ErrorHandler`, this does not unconditionally re-raise
  after handling: for a `/api` path we have already sent the definitive
  response, so there is nothing further for Phoenix's own error
  rendering to do. Non-`/api` paths re-raise so Phoenix's normal
  browser error rendering (HTML error pages) is untouched.
  """

  defmacro __using__(_opts) do
    quote do
      @before_compile PlaysteadWeb.Plugs.ApiProblemHandler
    end
  end

  defmacro __before_compile__(_env) do
    quote location: :keep do
      defoverridable call: 2

      def call(conn, opts) do
        try do
          super(conn, opts)
        rescue
          e in Plug.Conn.WrapperError ->
            %{conn: conn, kind: kind, reason: reason, stack: stack} = e
            PlaysteadWeb.Plugs.ApiProblemHandler.__catch__(conn, kind, reason, stack)
        catch
          kind, reason ->
            PlaysteadWeb.Plugs.ApiProblemHandler.__catch__(conn, kind, reason, __STACKTRACE__)
        end
      end
    end
  end

  @already_sent {:plug_conn, :sent}

  @doc false
  def __catch__(conn, kind, reason, stack) do
    if api_path?(conn) do
      normalized = Exception.normalize(kind, reason, stack)

      receive do
        @already_sent ->
          send(self(), @already_sent)
          %{conn | state: :sent}
      after
        0 ->
          status = status_for(kind, normalized)
          code = code_for_status(status)

          PlaysteadWeb.Problem.send_problem(
            conn,
            status,
            code,
            "An unexpected error occurred. Reference the correlation ID when reporting this."
          )
      end
    else
      :erlang.raise(kind, reason, stack)
    end
  end

  defp api_path?(conn) do
    String.starts_with?(conn.request_path, "/api")
  end

  defp status_for(:error, reason), do: Plug.Exception.status(reason)
  defp status_for(_kind, _reason), do: 500

  defp code_for_status(404), do: :not_found
  defp code_for_status(_status), do: :internal_error
end
