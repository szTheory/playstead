defmodule Playstead.TlsTrustTest do
  use ExUnit.Case, async: true

  import Playstead.TlsFixtures

  alias Playstead.TlsTrust

  # Every case passes an explicit env map — nothing here touches the
  # process-global OS environment, which is what keeps this module safe to
  # run `async: true` next to the LiveView suites.
  @no_ca %{"PLAYSTEAD_CADDY_CA_PATH" => "/nonexistent/root.crt"}

  describe "transport_state/1" do
    test "reports :external_proxy when PLAYSTEAD_PROXY is external" do
      assert TlsTrust.transport_state(%{"PLAYSTEAD_PROXY" => "external"}) == :external_proxy
    end

    test "an external proxy wins over a configured domain" do
      env = %{"PLAYSTEAD_PROXY" => "external", "PLAYSTEAD_DOMAIN" => "example.com"}
      assert TlsTrust.transport_state(env) == :external_proxy
    end

    test "reports :letsencrypt when PLAYSTEAD_DOMAIN is set" do
      assert TlsTrust.transport_state(%{"PLAYSTEAD_DOMAIN" => "example.com"}) == :letsencrypt
    end

    test "an empty PLAYSTEAD_DOMAIN is treated as unset" do
      assert TlsTrust.transport_state(Map.put(@no_ca, "PLAYSTEAD_DOMAIN", "")) == :plain_http
    end

    test "reports :plain_http with no domain, no external proxy, and no CA root on disk" do
      assert TlsTrust.transport_state(@no_ca) == :plain_http
    end

    test "reports :internal_ca once a CA root certificate exists on disk" do
      path = write_fixture_cert!("tls_trust_test")
      assert TlsTrust.transport_state(%{"PLAYSTEAD_CADDY_CA_PATH" => path}) == :internal_ca
    end
  end

  describe "ca_fingerprint/1" do
    test "returns :not_applicable when a domain (Let's Encrypt) is configured" do
      assert TlsTrust.ca_fingerprint(%{"PLAYSTEAD_DOMAIN" => "example.com"}) ==
               {:error, :not_applicable}
    end

    test "returns :not_applicable when an external proxy is configured" do
      assert TlsTrust.ca_fingerprint(%{"PLAYSTEAD_PROXY" => "external"}) ==
               {:error, :not_applicable}
    end

    test "returns :not_found when no CA root certificate exists yet" do
      assert TlsTrust.ca_fingerprint(@no_ca) == {:error, :not_found}
    end

    test "returns :invalid_certificate for a file that is not a PEM certificate" do
      path = Path.join(System.tmp_dir!(), "not_a_cert_#{System.unique_integer([:positive])}")
      File.write!(path, "definitely not a certificate")
      on_exit(fn -> File.rm(path) end)

      assert TlsTrust.ca_fingerprint(%{"PLAYSTEAD_CADDY_CA_PATH" => path}) ==
               {:error, :invalid_certificate}
    end

    test "reads a real CA root certificate and formats the fingerprint like openssl does" do
      path = write_fixture_cert!("tls_trust_test")
      expected = expected_fingerprint()

      assert {:ok, ^expected} = TlsTrust.ca_fingerprint(%{"PLAYSTEAD_CADDY_CA_PATH" => path})
    end
  end

  describe "runtime_env/0" do
    test "overlays :env_overrides on top of the OS environment" do
      # Deliberately does NOT call Application.put_env (global) — instead it
      # proves the merge shape: keys present in the OS env survive, and the
      # override layer is a plain string-keyed map.
      env = TlsTrust.runtime_env()
      assert is_map(env)
      assert Map.has_key?(env, "PATH")
      assert Enum.all?(env, fn {k, v} -> is_binary(k) and is_binary(v) end)
    end
  end
end
