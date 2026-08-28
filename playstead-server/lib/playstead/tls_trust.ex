defmodule Playstead.TlsTrust do
  @moduledoc """
  The server's transport-trust surface for pairing-time client pinning
  (D-13). A Mac pins the root-CA fingerprint shown here at pairing time
  instead of any Keychain Access surgery — this module is what makes
  that fingerprint computable and honestly labeled.

  `transport_state/1` is the single source of truth for the
  `PLAYSTEAD_PROXY` / `PLAYSTEAD_DOMAIN` / `PLAYSTEAD_CADDY_CA_PATH`
  decision — `Playstead.Readiness` delegates to it. It is a pure function
  over an env *map* (defaulting to `runtime_env/0`) so tests can pass an
  explicit map and stay `async: true` without touching the OS
  environment, which is process-global across the whole BEAM.
  """

  @default_ca_path "/caddy_data/caddy/pki/authorities/local/root.crt"
  @ca_path_env "PLAYSTEAD_CADDY_CA_PATH"

  @type transport_state :: :letsencrypt | :internal_ca | :external_proxy | :plain_http
  @type env :: %{optional(String.t()) => String.t()}

  @doc """
  The environment the transport decision is made against: the OS
  environment, overlaid with `config :playstead, :env_overrides` (a
  keyword/map of string keys). The override layer exists so tests that
  drive a LiveView (which calls the 0-arity forms) can inject transport
  state without `System.put_env/2`.
  """
  @spec runtime_env() :: env()
  def runtime_env do
    overrides =
      :playstead
      |> Application.get_env(:env_overrides, [])
      |> Map.new(fn {k, v} -> {to_string(k), v} end)

    Map.merge(System.get_env(), overrides)
  end

  @doc """
  Which of the four honestly-distinct transport states is active. Never
  collapsed into a boolean, and `:external_proxy`/`:plain_http` are never
  described as secure (D-13; `Playstead.Readiness.summary/1` delegates here).
  """
  @spec transport_state(env()) :: transport_state()
  def transport_state(env \\ runtime_env()) do
    proxy = env["PLAYSTEAD_PROXY"]
    domain = env["PLAYSTEAD_DOMAIN"]

    cond do
      proxy == "external" -> :external_proxy
      is_binary(domain) and domain != "" -> :letsencrypt
      true -> plain_http_or_internal_ca(env)
    end
  end

  # A bundled Caddy with no domain and no external proxy issues from its
  # own internal CA (D-13) — but whether that CA cert is actually present
  # on disk yet is a separate, honest question `ca_fingerprint/0` answers.
  # We report `:plain_http` only when there truly is nothing to pin
  # (no internal CA root has been provisioned at all); once Caddy has
  # minted one, the state is `:internal_ca`.
  defp plain_http_or_internal_ca(env) do
    if File.exists?(ca_path(env)), do: :internal_ca, else: :plain_http
  end

  @doc """
  The SHA-256 fingerprint of the Caddy internal-CA root certificate, in
  colon-separated uppercase hex — the same format `openssl x509 -noout
  -fingerprint -sha256` prints, so a self-hoster can cross-check it.

  Returns `{:error, :not_applicable}` when the active transport state has
  no local CA to pin (`:letsencrypt` — the certificate is already
  publicly trusted; `:external_proxy` — Playstead doesn't manage that
  certificate at all). Returns `{:error, :not_found}` when the internal
  CA hasn't minted its root certificate yet (Caddy does this on its own
  first boot) rather than raising or crashing the page.
  """
  @spec ca_fingerprint(env()) ::
          {:ok, String.t()} | {:error, :not_applicable | :not_found | :invalid_certificate}
  def ca_fingerprint(env \\ runtime_env()) do
    case transport_state(env) do
      state when state in [:letsencrypt, :external_proxy] ->
        {:error, :not_applicable}

      _plain_http_or_internal_ca ->
        read_fingerprint(ca_path(env))
    end
  end

  defp read_fingerprint(path) do
    with {:ok, pem} <- File.read(path),
         [{:Certificate, der, _}] <- :public_key.pem_decode(pem) do
      fingerprint =
        :crypto.hash(:sha256, der)
        |> Base.encode16(case: :upper)
        |> format_fingerprint()

      {:ok, fingerprint}
    else
      {:error, :enoent} -> {:error, :not_found}
      {:error, _reason} -> {:error, :not_found}
      _ -> {:error, :invalid_certificate}
    end
  end

  defp format_fingerprint(hex) do
    hex
    |> String.to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.map(&to_string/1)
    |> Enum.join(":")
  end

  defp ca_path(env), do: env[@ca_path_env] || @default_ca_path
end
