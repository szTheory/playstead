defmodule Playstead.TlsTrust do
  @moduledoc """
  The server's transport-trust surface for pairing-time client pinning
  (D-13). A Mac pins the root-CA fingerprint shown here at pairing time
  instead of any Keychain Access surgery — this module is what makes
  that fingerprint computable and honestly labeled.

  `transport_state/0` mirrors `Playstead.Readiness`'s https-check env-var
  logic (`PLAYSTEAD_PROXY`, `PLAYSTEAD_DOMAIN`) but returns one of four
  raw states rather than a readiness row, since the Devices page needs
  the state itself to decide whether a fingerprint even applies.
  """

  @default_ca_path "/caddy_data/caddy/pki/authorities/local/root.crt"
  @ca_path_env "PLAYSTEAD_CADDY_CA_PATH"

  @type transport_state :: :letsencrypt | :internal_ca | :external_proxy | :plain_http

  @doc """
  Which of the four honestly-distinct transport states is active. Never
  collapsed into a boolean, and `:external_proxy`/`:plain_http` are never
  described as secure (D-13, mirrors `Playstead.Readiness.summary/0`).
  """
  @spec transport_state() :: transport_state()
  def transport_state do
    proxy = System.get_env("PLAYSTEAD_PROXY")
    domain = System.get_env("PLAYSTEAD_DOMAIN")

    cond do
      proxy == "external" -> :external_proxy
      is_binary(domain) and domain != "" -> :letsencrypt
      true -> plain_http_or_internal_ca()
    end
  end

  # A bundled Caddy with no domain and no external proxy issues from its
  # own internal CA (D-13) — but whether that CA cert is actually present
  # on disk yet is a separate, honest question `ca_fingerprint/0` answers.
  # We report `:plain_http` only when there truly is nothing to pin
  # (no internal CA root has been provisioned at all); once Caddy has
  # minted one, the state is `:internal_ca`.
  defp plain_http_or_internal_ca do
    if File.exists?(ca_path()), do: :internal_ca, else: :plain_http
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
  @spec ca_fingerprint() ::
          {:ok, String.t()} | {:error, :not_applicable | :not_found | :invalid_certificate}
  def ca_fingerprint do
    case transport_state() do
      state when state in [:letsencrypt, :external_proxy] ->
        {:error, :not_applicable}

      _plain_http_or_internal_ca ->
        read_fingerprint(ca_path())
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

  defp ca_path, do: System.get_env(@ca_path_env, @default_ca_path)
end
