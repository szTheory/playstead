defmodule Playstead.Config.MacCiConfigTest do
  use ExUnit.Case, async: false

  # config/mac_ci.exs is not evaluated under MIX_ENV=test, so it is read
  # directly through Config.Reader rather than via Application.get_env/2.
  # One assertion per line: this project's CI keeps file:line, not assertion
  # messages, so a failure must be independently locatable on its own line.

  setup do
    root =
      Path.join(System.tmp_dir!(), "playstead-mac-ci-config-test-#{System.unique_integer([:positive])}")

    previous_root = System.get_env("PLAYSTEAD_MAC_CI_ROOT")
    previous_port = System.get_env("PORT")
    System.put_env("PLAYSTEAD_MAC_CI_ROOT", root)
    System.put_env("PORT", "4010")

    on_exit(fn ->
      if previous_root do
        System.put_env("PLAYSTEAD_MAC_CI_ROOT", previous_root)
      else
        System.delete_env("PLAYSTEAD_MAC_CI_ROOT")
      end

      if previous_port do
        System.put_env("PORT", previous_port)
      else
        System.delete_env("PORT")
      end
    end)

    config_path =
      Path.expand("../../config/mac_ci.exs", __DIR__)

    config = Config.Reader.read!(config_path, env: :mac_ci)
    endpoint_config = config[:playstead][PlaysteadWeb.Endpoint]

    %{root: root, endpoint_config: endpoint_config}
  end

  test "the endpoint's :url scheme is https", %{endpoint_config: endpoint_config} do
    assert endpoint_config[:url][:scheme] == "https"
  end

  test "the endpoint has an :https listener bound to loopback on PORT and no :http key", %{
    endpoint_config: endpoint_config
  } do
    assert endpoint_config[:https][:ip] == {127, 0, 0, 1}
    assert endpoint_config[:https][:port] == 4010
    refute Keyword.has_key?(endpoint_config, :http)
  end

  test "certfile and keyfile both resolve under PLAYSTEAD_MAC_CI_ROOT/tls", %{
    root: root,
    endpoint_config: endpoint_config
  } do
    tls_root = Path.join(root, "tls")
    assert endpoint_config[:https][:certfile] == Path.join(tls_root, "server.pem")
    assert endpoint_config[:https][:keyfile] == Path.join(tls_root, "server-key.pem")
  end
end
