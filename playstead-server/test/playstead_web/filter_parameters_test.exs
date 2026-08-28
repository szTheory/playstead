defmodule PlaysteadWeb.FilterParametersTest do
  @moduledoc """
  Standing regression guard for CR-01 (01-REVIEW.md): Phoenix's own
  request-parameter logging must never leak single-use authentication
  secrets. `password`, `device_code`, and `credential` were already
  filtered; `code` (recovery-code login,
  `POST /log-in/recovery`) and `token` (password-reset/setup-token,
  `GET/POST /reset/:token`) must be filtered too, per
  `Playstead.AuditLog`'s "metadata must never carry credential material
  or a plaintext token" discipline.
  """

  use ExUnit.Case, async: true

  # Phoenix.start/2 compiles the raw {:discard, keys} config into an
  # Aho-Corasick automaton and overwrites `Application.get_env(:phoenix,
  # :filter_parameters)` with the compiled form at boot, so by the time
  # tests run we can no longer introspect the original key list directly.
  # Instead, assert on the actual runtime behavior via
  # `Phoenix.Logger.filter_values/2` — the same function Phoenix's request
  # logger uses — which is what actually determines whether a secret is
  # logged in the clear.
  @required_keys ~w(password device_code credential code token)

  test "phoenix filter_parameters discards all known credential/token keys at runtime" do
    filter = Application.get_env(:phoenix, :filter_parameters)

    params = Map.new(@required_keys, fn key -> {key, "plaintext-secret-value"} end)
    filtered = Phoenix.Logger.filter_values(params, filter)

    leaked =
      for key <- @required_keys, Map.get(filtered, key) != "[FILTERED]", do: key

    assert leaked == [],
           "The following keys were NOT filtered from Phoenix request logging " <>
             "and would leak in the clear: #{inspect(leaked)}"
  end
end
