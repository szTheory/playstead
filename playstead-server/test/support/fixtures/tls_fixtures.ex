defmodule Playstead.TlsFixtures do
  @moduledoc """
  A real, openssl-generated self-signed certificate (not the app's own
  runtime CA) used only to prove `Playstead.TlsTrust.ca_fingerprint/1`
  decodes PEM, hashes the DER bytes, and formats the result exactly like
  `openssl x509 -noout -fingerprint -sha256` does, so a self-hoster can
  cross-check what the console shows.
  """

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

  def fixture_pem, do: @fixture_pem
  def expected_fingerprint, do: @expected_fingerprint

  @doc "Writes the fixture certificate to a unique temp file; removed on exit."
  def write_fixture_cert!(prefix \\ "tls_fixture") do
    path = Path.join(System.tmp_dir!(), "#{prefix}_#{System.unique_integer([:positive])}.pem")
    File.write!(path, @fixture_pem)
    ExUnit.Callbacks.on_exit(fn -> File.rm(path) end)
    path
  end

  @doc """
  Point the runtime env at a transport state without touching the OS env.
  Global (`Application.put_env`) — only for `async: false` modules that
  drive a LiveView; pure callers should pass a map to `TlsTrust` directly.
  """
  def put_env_overrides!(overrides) when is_map(overrides) do
    previous = Application.get_env(:playstead, :env_overrides, [])
    Application.put_env(:playstead, :env_overrides, overrides)
    ExUnit.Callbacks.on_exit(fn -> Application.put_env(:playstead, :env_overrides, previous) end)
    :ok
  end
end
