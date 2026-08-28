defmodule Playstead.Idempotency do
  @moduledoc """
  The `Idempotency-Key` receipt layer for mutating `/api/v1` endpoints
  (D-20a, PROT-04). Every mutating handler goes through `execute/4`,
  which is the single site in this module that writes a receipt — and
  it always does so inside the same `Ecto.Multi` transaction as the
  effect it records. There is no after-commit or separate-transaction
  write path anywhere in this module (RESEARCH.md Pitfall 3).

  `PlaysteadWeb.Plugs.Idempotency` performs the pre-flight replay/
  conflict/mismatch check via `fetch/3`; `execute/4` performs the
  actual guarded write.
  """

  import Ecto.Query, warn: false

  alias Playstead.Repo
  alias Playstead.Idempotency.Receipt

  # D-20a: ~90-day retention horizon. Also the floor for plan 01-07's
  # change-journal compaction (must be at least this long so outbox
  # replay and cursor resync stay mutually consistent).
  @retention_days 90

  @doc "The retention horizon (days) receipts are kept before `prune_expired/0` removes them."
  def retention_days, do: @retention_days

  @doc """
  A stable hash over the request method, path, and canonicalized body.
  Detects a genuinely different payload reused under the same key.
  """
  @spec fingerprint(%{method: String.t(), path: String.t(), body: term()}) :: String.t()
  def fingerprint(%{method: method, path: path, body: body}) do
    canonical = {method, path, canonicalize(body)}

    :crypto.hash(:sha256, :erlang.term_to_binary(canonical))
    |> Base.encode16(case: :lower)
  end

  defp canonicalize(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {to_string(k), canonicalize(v)} end)
    |> Enum.sort_by(fn {k, _v} -> k end)
  end

  defp canonicalize(value) when is_list(value), do: Enum.map(value, &canonicalize/1)
  defp canonicalize(value), do: value

  @doc """
  Looks up any existing receipt for `device_id`/`idempotency_key` and
  classifies it against `fingerprint`:

  - `{:ok, :fresh}` — no receipt exists; the caller should proceed to `execute/4`.
  - `{:ok, :replay, receipt}` — a complete receipt with a matching fingerprint; replay it verbatim.
  - `{:error, :mismatch}` — a complete receipt with a different fingerprint.
  - `{:error, :in_flight}` — the original request is still being processed.
  """
  @spec fetch(binary(), String.t(), String.t()) ::
          {:ok, :fresh} | {:ok, :replay, Receipt.t()} | {:error, :mismatch} | {:error, :in_flight}
  def fetch(device_id, idempotency_key, fingerprint) do
    case Repo.get_by(Receipt, device_id: device_id, idempotency_key: idempotency_key) do
      nil ->
        {:ok, :fresh}

      %Receipt{state: "in_flight"} ->
        {:error, :in_flight}

      %Receipt{state: "complete", request_fingerprint: ^fingerprint} = receipt ->
        {:ok, :replay, receipt}

      %Receipt{state: "complete"} ->
        {:error, :mismatch}
    end
  end

  @doc """
  The single entry point every mutating handler goes through. Builds
  one `Ecto.Multi` that inserts the in-flight receipt, runs
  `effect_fun` (which must return `{:ok, status, body}` or
  `{:error, reason}`), and updates the receipt to complete with the
  serialized response — one transaction, one commit.

  If a racing retry's insert loses the unique-index race (the window
  between the plug's pre-flight `fetch/3` and this call), returns
  `{:error, :conflict}` so the caller can render 409 + `Retry-After`
  instead of running the effect twice.
  """
  @spec execute(binary(), String.t(), String.t(), (-> {:ok, pos_integer(), term()}
                                                      | {:error, term()})) ::
          {:ok, pos_integer(), term()} | {:error, :conflict} | {:error, term()}
  def execute(device_id, idempotency_key, fingerprint, effect_fun)
      when is_function(effect_fun, 0) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:receipt, fn _changes ->
      Receipt.create_changeset(%Receipt{}, %{
        device_id: device_id,
        idempotency_key: idempotency_key,
        request_fingerprint: fingerprint,
        expires_at: expires_at()
      })
    end)
    |> Ecto.Multi.run(:effect, fn _repo, _changes ->
      case effect_fun.() do
        {:ok, status, body} -> {:ok, {status, body}}
        {:error, reason} -> {:error, reason}
      end
    end)
    |> Ecto.Multi.update(:receipt_complete, fn %{receipt: receipt, effect: {status, body}} ->
      Receipt.complete_changeset(receipt, status, Jason.encode!(body))
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{effect: {status, body}}} -> {:ok, status, body}
      {:error, :receipt, changeset, _changes} -> classify_receipt_error(changeset)
      {:error, :effect, reason, _changes} -> {:error, reason}
      {:error, _step, reason, _changes} -> {:error, reason}
    end
  end

  defp classify_receipt_error(%Ecto.Changeset{errors: errors} = changeset) do
    if Enum.any?(errors, fn {_field, {_msg, opts}} ->
         Keyword.get(opts, :constraint) == :unique
       end) do
      {:error, :conflict}
    else
      {:error, changeset}
    end
  end

  @doc """
  Removes receipts past the `retention_days/0` horizon. Invoked by a
  scheduled Oban job — nothing in this module's replay/conflict
  correctness depends on this having run.
  """
  @spec prune_expired() :: {:ok, non_neg_integer()}
  def prune_expired do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} = from(r in Receipt, where: r.expires_at < ^now) |> Repo.delete_all()
    {:ok, count}
  end

  defp expires_at do
    DateTime.utc_now()
    |> DateTime.truncate(:second)
    |> DateTime.add(@retention_days * 24 * 60 * 60, :second)
  end
end
