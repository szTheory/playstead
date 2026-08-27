defmodule Playstead.TlsTrustTest do
  use ExUnit.Case, async: true

  alias Playstead.TlsTrust

  # A real, openssl-generated self-signed certificate (not the app's own
  # runtime CA) — used only to prove `ca_fingerprint/0` correctly decodes
  # PEM, hashes the DER bytes, and formats the result exactly like
  # `openssl x509 -noout -fingerprint -sha256` does, so a self-hoster can
  # cross-check what the console shows.
  @fixture_pem """
  -----BEGIN CERTIFICATE-----
  MIIDGTCCAgGgAwIBAgIUYwwqlgIxbtWsaO2LJJeEG7M9LNgwDQYJKoZIhvcNAQEL
  BQAwHDEaMBgGA1UEAwwRcGxheXN0ZWFkLXRlc3QtY2EwHhcNMjYwODI3MTc1NjM0
  WhcNMzYwODI0MTc1NjM0WjAcMRowGAYDVQQDDBFwbGF5c3RlYWQtdGVzdC1jYTCC
  ASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKqjGXFQVRAU0jYxOwmNQ6qr
  b4mzeGUyOtHlZPz+tOy7gNbSQA6m3IRGB4/nbdLlKlvwWpoeoOc5Bk34oHbDEGzz
  IRAQtmsa5BKjFyE3RBB82Zxc0K8kFVw05ensXHzELx5rtrrEY9i+FDFQ1hLTdz7+
  NLnIhxiCo5R3V1WimH8b0go3AWM5dpR9AhzdrGYWrqOlAgQyhUeiVFzhrrOGKIRS
  mtV0D3NL9n8zCOawea9mgLCCXJYu/Sx4UKPmVhsEfF6u5+Pb2Hs3rhHu1pRqob3c
  6zqWZvFku1YOEMct5sxBeLjp3js3gJxc0qegCAkAxF0aRIwj31kk5kUxekRjyt8C
  AwEAAaNTMFEwHQYDVR0OBBYEFPBCQrTgGS25M6RLG9Q8UoOoTKqLMB8GA1UdIwQY
  MBaAFPBCQrTgGS25M6RLG9Q8UoOoTKqLMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZI
  hvcNAQELBQADggEBAJzSYPzDgN+6ZmnfTh1L72H7k0mEirjyw1aRewh4Oi9r4AA7
  R4F+vkL5Xrq66KolT1fR6F0g1rRkvWKk425vkwr2+fh1oyEdZBgLuEPRomJTmO7Q
  9/6s/G24qSBmltVIn5oHzg/+fd9OR2ioa5inZaogqC0NRE3jihQq6+DrX6pjE9O4
  R7FnDXVYYy959dcB3BuZB2oT7xn92QCPlfwqGMTJMsYyoJNkKfT3+UVUWjBf9jJw
  18oUuBMyb01ThnCvQXBLcHlvQ+hEolgMHCZCCQK0bBSx5A0cltEgln4z93wdu2z+
  u9JaeIW4EFRlTve8HAPi8/WEj8pf5r0cCzQOOUM=
  -----END CERTIFICATE-----
  """

  # Computed with `openssl x509 -in test_cert.pem -noout -fingerprint -sha256`
  # against the exact certificate above.
  @expected_fingerprint "DF:FD:38:6D:FA:0A:44:76:E5:D5:C6:B3:76:D2:C6:3C:FB:72:81:E8:B7:6D:75:F5:6D:B2:77:FA:7C:1B:67:7F"

  setup do
    on_exit(fn ->
      System.delete_env("PLAYSTEAD_PROXY")
      System.delete_env("PLAYSTEAD_DOMAIN")
      System.delete_env("PLAYSTEAD_CADDY_CA_PATH")
    end)
  end

  describe "transport_state/0" do
    test "reports :external_proxy when PLAYSTEAD_PROXY is external" do
      System.put_env("PLAYSTEAD_PROXY", "external")
      assert TlsTrust.transport_state() == :external_proxy
    end

    test "reports :letsencrypt when PLAYSTEAD_DOMAIN is set" do
      System.put_env("PLAYSTEAD_DOMAIN", "example.com")
      assert TlsTrust.transport_state() == :letsencrypt
    end

    test "reports :plain_http with no domain, no external proxy, and no CA root on disk" do
      System.put_env("PLAYSTEAD_CADDY_CA_PATH", "/nonexistent/root.crt")
      assert TlsTrust.transport_state() == :plain_http
    end

    test "reports :internal_ca once a CA root certificate exists on disk" do
      path = write_fixture_cert!()
      System.put_env("PLAYSTEAD_CADDY_CA_PATH", path)
      assert TlsTrust.transport_state() == :internal_ca
    end
  end

  describe "ca_fingerprint/0" do
    test "returns :not_applicable when a domain (Let's Encrypt) is configured" do
      System.put_env("PLAYSTEAD_DOMAIN", "example.com")
      assert TlsTrust.ca_fingerprint() == {:error, :not_applicable}
    end

    test "returns :not_applicable when an external proxy is configured" do
      System.put_env("PLAYSTEAD_PROXY", "external")
      assert TlsTrust.ca_fingerprint() == {:error, :not_applicable}
    end

    test "returns :not_found when no CA root certificate exists yet" do
      System.put_env("PLAYSTEAD_CADDY_CA_PATH", "/nonexistent/root.crt")
      assert TlsTrust.ca_fingerprint() == {:error, :not_found}
    end

    test "reads a real CA root certificate and formats the fingerprint like openssl does" do
      path = write_fixture_cert!()
      System.put_env("PLAYSTEAD_CADDY_CA_PATH", path)

      assert {:ok, @expected_fingerprint} = TlsTrust.ca_fingerprint()
    end
  end

  defp write_fixture_cert! do
    path =
      Path.join(System.tmp_dir!(), "tls_trust_test_#{System.unique_integer([:positive])}.pem")

    File.write!(path, @fixture_pem)
    on_exit(fn -> File.rm(path) end)
    path
  end
end
