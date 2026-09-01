defmodule Mix.Tasks.Playstead.MacCiFixture do
  @moduledoc """
  Builds the bounded, synthetic fixture used by the hosted Mac live-server proof.

  The task deliberately uses the same setup, custody/import, and pairing contexts
  as production. Its JSON control files contain catalogue identity only; pairing
  codes and credentials stay in run-owned mode-0600 files managed by the caller.
  """

  use Mix.Task

  alias Playstead.Accounts
  alias Playstead.Accounts.Scope
  alias Playstead.Blobs
  alias Playstead.Catalogue
  alias Playstead.Import
  alias Playstead.Pairing
  alias Playstead.Setup

  @shortdoc "Creates and approves the bounded hosted Mac CI fixture"
  @device_label "Playstead Hosted Mac"
  @first %{title: "Playstead CI Sentinel One", bytes: "PLAYSTEAD-CI-SENTINEL-ONE\n"}
  @second %{title: "Playstead CI Sentinel Two", bytes: "PLAYSTEAD-CI-SENTINEL-TWO\n"}

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    case argv do
      ["provision", "--output", output] ->
        fixture = provision!()
        write_control!(output, %{sentinel: fixture.sentinel})

      [
        "approve",
        "--request-id",
        request_id,
        "--display-code",
        display_code,
        "--device-label",
        device_label
      ] ->
        owner = Accounts.get_owner() || raise ArgumentError, "Mac CI owner is missing"

        _approved =
          approve_exact!(owner, %{
            request_id: request_id,
            display_code: display_code,
            device_label: device_label
          })

      ["second", "--output", output] ->
        owner = Accounts.get_owner() || raise ArgumentError, "Mac CI owner is missing"
        write_control!(output, %{sentinel: add_second_sentinel!(owner)})

      _ ->
        Mix.raise(
          "expected provision --output PATH, approve --request-id ID --display-code CODE " <>
            "--device-label LABEL, or second --output PATH"
        )
    end
  end

  def device_label, do: @device_label

  @doc "Creates the sole owner and first public synthetic catalogue sentinel."
  def provision! do
    owner = Accounts.get_owner() || create_owner!()
    %{owner: owner, sentinel: import_sentinel!(owner, @first)}
  end

  @doc "Adds the second public synthetic sentinel used to disprove mirror reuse."
  def add_second_sentinel!(owner), do: import_sentinel!(owner, @second)

  @doc "Approves only one exact, independently identified pending request."
  def approve_exact!(owner, claims) do
    scope = Scope.for_user(owner)

    request =
      case Pairing.list_pending_requests(scope) do
        [request] ->
          request

        pending ->
          raise ArgumentError, "expected sole pending pairing request, got #{length(pending)}"
      end

    require_equal!(request.id, claims.request_id, "request id")
    require_equal!(request.display_code, claims.display_code, "display code")
    require_equal!(request.claimed_device_name, claims.device_label, "device label")
    require_equal!(claims.device_label, @device_label, "unique fixture device label")

    case Pairing.approve(scope, request.id) do
      {:ok, approved} ->
        require_equal!(approved.id, claims.request_id, "approved request id")
        require_equal!(approved.display_code, claims.display_code, "approved display code")
        approved

      {:error, reason} ->
        raise ArgumentError, "exact approval failed: #{inspect(reason)}"
    end
  end

  defp create_owner! do
    setup_token = random_text(32)
    System.put_env("PLAYSTEAD_SETUP_TOKEN", setup_token)

    try do
      :ok = Setup.mint_token()

      {:ok, %{user: owner}} =
        Setup.claim(setup_token, %{
          email: "mac-ci-owner@invalid.example",
          password: random_text(48)
        })

      owner
    after
      System.delete_env("PLAYSTEAD_SETUP_TOKEN")
    end
  end

  defp import_sentinel!(owner, %{title: title, bytes: bytes}) do
    File.mkdir_p!(Playstead.Blobs.Store.LocalDisk.blob_path())
    {:ok, status, meta} = Blobs.put_stream([bytes], byte_size(bytes))

    {:ok, receipt} =
      Import.import_single(
        owner.id,
        %{
          original_name: title <> ".txt",
          origin: "mac_ci_fixture",
          size_bytes: byte_size(bytes)
        },
        {status, meta},
        format_bytes: bytes
      )

    {:ok, detail} = Catalogue.get_asset_detail(Scope.for_user(owner), receipt.asset_set_id)
    require_equal!(detail.asset_set.display_title, title, "sentinel title")

    %{
      title: detail.asset_set.display_title,
      asset_set_id: detail.asset_set.id,
      byte_size: byte_size(bytes)
    }
  end

  defp write_control!(output, payload) do
    root = System.fetch_env!("PLAYSTEAD_MAC_CI_ROOT") |> Path.expand()
    output = Path.expand(output)

    unless output == root or String.starts_with?(output, root <> "/") do
      raise ArgumentError, "control output must stay inside PLAYSTEAD_MAC_CI_ROOT"
    end

    File.mkdir_p!(Path.dirname(output))
    File.write!(output, Jason.encode!(payload))
    File.chmod!(output, 0o600)
  end

  defp require_equal!(actual, expected, label) do
    unless actual == expected do
      raise ArgumentError, "#{label} did not match exact Mac CI fixture claim"
    end
  end

  defp random_text(bytes),
    do: :crypto.strong_rand_bytes(bytes) |> Base.url_encode64(padding: false)
end
