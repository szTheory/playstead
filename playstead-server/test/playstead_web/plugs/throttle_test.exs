defmodule PlaysteadWeb.Plugs.ThrottleTest do
  use PlaysteadWeb.ConnCase, async: true

  alias PlaysteadWeb.Plugs.Throttle

  setup do
    # Each test uses a unique IP and account key so Hammer's shared ETS
    # counters never bleed state across tests (async: true).
    unique = System.unique_integer([:positive])
    ip = {10, 0, div(unique, 65536) |> rem(256), rem(unique, 256)}
    email = "throttle-#{unique}@example.com"
    %{ip: ip, email: email}
  end

  defp hit(ip, email, action, opts) do
    conn =
      Phoenix.ConnTest.build_conn(:post, "/log-in", %{"user" => %{"email" => email}})
      |> Map.put(:remote_ip, ip)
      |> Map.put(:body_params, %{"user" => %{"email" => email}})

    Throttle.call(conn, Throttle.init([action: action] ++ opts))
  end

  describe "call/2" do
    test "allows requests under the per-IP limit", %{ip: ip, email: email} do
      opts = [per_ip_limit: 5, per_account_limit: 5]

      for _ <- 1..5 do
        conn = hit(ip, email, :login, opts)
        refute conn.halted
      end
    end

    test "denies requests beyond the per-IP limit with a rate_limited problem+json response", %{
      ip: ip
    } do
      opts = [per_ip_limit: 5, per_account_limit: 5]

      for i <- 1..5 do
        conn = hit(ip, "distinct-account-#{i}@example.com", :login, opts)
        refute conn.halted
      end

      conn = hit(ip, "one-more@example.com", :login, opts)

      assert conn.halted
      assert conn.status == 429
      assert ["application/problem+json" <> _] = get_resp_header(conn, "content-type")
      body = Jason.decode!(conn.resp_body)
      assert body["code"] == "rate_limited"
    end

    test "denies requests beyond the per-account limit even from different IPs", %{email: email} do
      opts = [per_ip_limit: 1000, per_account_limit: 5]

      for i <- 1..5 do
        conn = hit({10, 1, div(i, 256), rem(i, 256)}, email, :login, opts)
        refute conn.halted
      end

      conn = hit({10, 1, 99, 99}, email, :login, opts)

      assert conn.halted
      assert conn.status == 429
    end

    test "different actions get independent buckets", %{ip: ip, email: email} do
      opts = [per_ip_limit: 5, per_account_limit: 5]
      for _ <- 1..5, do: hit(ip, email <> "-a", :login, opts)

      # A different action namespace (:recovery) for the same IP is not
      # affected by :login's exhausted per-IP bucket.
      conn = hit(ip, email <> "-b", :recovery, opts)
      refute conn.halted
    end
  end
end
