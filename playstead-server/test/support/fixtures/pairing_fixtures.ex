defmodule Playstead.PairingFixtures do
  @moduledoc """
  Test helpers for creating pairing entities via `Playstead.Pairing`.
  """

  alias Playstead.Pairing
  alias Playstead.Repo
  alias Playstead.Pairing.PairingRequest

  @doc "A fresh, unhashed device_code a Mac client would generate."
  def unique_device_code, do: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

  def valid_pairing_request_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{
      "device_code" => unique_device_code(),
      "device_name" => "Test Mac",
      "platform" => "macOS 15.0",
      "app_version" => "1.0.0",
      "capabilities" => %{},
      "requesting_ip" => "192.0.2.1"
    })
  end

  @doc """
  Creates a pending pairing request. Returns `{request, device_code}`
  since the plaintext device code isn't stored anywhere but the caller
  needs it to exercise redemption.
  """
  def pairing_request_fixture(attrs \\ %{}) do
    device_code = attrs[:device_code] || attrs["device_code"] || unique_device_code()
    attrs = valid_pairing_request_attributes(attrs) |> Map.put("device_code", device_code)

    {:ok, request} = Pairing.create_request(attrs)
    {request, device_code}
  end

  @doc "Creates a pending pairing request that is already past its expiry."
  def expired_pairing_request_fixture(attrs \\ %{}) do
    {request, device_code} = pairing_request_fixture(attrs)

    expired_at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    request = Repo.update!(Ecto.Changeset.change(request, expires_at: expired_at))

    {request, device_code}
  end

  @doc "Creates and approves a pairing request, ready for redemption."
  def approved_pairing_request_fixture(scope, attrs \\ %{}) do
    {request, device_code} = pairing_request_fixture(attrs)
    {:ok, request} = Pairing.approve(scope, request.id)
    {request, device_code}
  end

  @doc "Directly builds an unsaved %PairingRequest{} for changeset-level tests."
  def pairing_request_struct(attrs \\ %{}) do
    struct!(PairingRequest, attrs)
  end

  @doc """
  Pairs a brand-new device end to end (request -> approve -> redeem) and
  returns the `%{device:, credential:, credential_plaintext:}` map
  `Pairing.redeem/2` returns.
  """
  def device_fixture(scope, attrs \\ %{}) do
    {request, device_code} = approved_pairing_request_fixture(scope, attrs)
    {:ok, result} = Pairing.redeem(request.id, device_code)
    result
  end
end
