defmodule Playstead.IdempotencyFixtures do
  @moduledoc """
  Test helpers for creating `Playstead.Idempotency.Receipt` rows.
  """

  alias Playstead.Repo
  alias Playstead.Idempotency.Receipt

  @doc "A fresh idempotency key a client would generate."
  def unique_idempotency_key, do: "key-#{System.unique_integer([:positive])}"

  @doc "Directly inserts a complete receipt row, bypassing `Idempotency.execute/4`."
  def complete_receipt_fixture(attrs \\ %{}) do
    defaults = %{
      device_id: attrs[:device_id],
      idempotency_key: attrs[:idempotency_key] || unique_idempotency_key(),
      request_fingerprint: attrs[:request_fingerprint] || "fp",
      expires_at:
        DateTime.utc_now()
        |> DateTime.add(90 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)
    }

    %Receipt{}
    |> Receipt.create_changeset(defaults)
    |> Repo.insert!()
    |> Receipt.complete_changeset(
      attrs[:response_status] || 200,
      attrs[:response_body] || Jason.encode!(%{ok: true})
    )
    |> Repo.update!()
  end

  @doc "Directly inserts an in-flight receipt row."
  def in_flight_receipt_fixture(attrs \\ %{}) do
    defaults = %{
      device_id: attrs[:device_id],
      idempotency_key: attrs[:idempotency_key] || unique_idempotency_key(),
      request_fingerprint: attrs[:request_fingerprint] || "fp",
      expires_at:
        DateTime.utc_now()
        |> DateTime.add(90 * 24 * 60 * 60, :second)
        |> DateTime.truncate(:second)
    }

    %Receipt{}
    |> Receipt.create_changeset(defaults)
    |> Repo.insert!()
  end

  @doc "Inserts a receipt already past its expiry, for pruning tests."
  def expired_receipt_fixture(attrs \\ %{}) do
    receipt = complete_receipt_fixture(attrs)

    expired_at = DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
    Repo.update!(Ecto.Changeset.change(receipt, expires_at: expired_at))
  end
end
