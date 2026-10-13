defmodule Mix.Tasks.Playstead.MacCiFixture do
  @moduledoc """
  Builds the bounded, synthetic fixture used by the hosted Mac live-server proof.

  The task deliberately uses the same setup, custody/import, and pairing contexts
  as production. Its JSON control files contain catalogue identity only; pairing
  codes and credentials stay in run-owned mode-0600 files managed by the caller.
  """

  use Mix.Task

  import Ecto.Query, warn: false

  alias Playstead.Accounts
  alias Playstead.Accounts.Scope
  alias Playstead.Blobs
  alias Playstead.Catalogue
  alias Playstead.Catalogue.{AssetMember, AssetSet}
  alias Playstead.Import
  alias Playstead.Pairing
  alias Playstead.Repo
  alias Playstead.Setup
  alias Playstead.Sync.ChangeJournal

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

      ["import-gb", "--registry", registry_path, "--fixture", fixture_name, "--output", output] ->
        owner = Accounts.get_owner() || raise ArgumentError, "Mac CI owner is missing"
        write_control!(output, import_gb_fixture!(owner, registry_path, fixture_name))

      ["import-aerevenadvance", "--registry", registry_path, "--output", output] ->
        owner = Accounts.get_owner() || raise ArgumentError, "Mac CI owner is missing"
        write_control!(output, import_aerevenadvance_fixture!(owner, registry_path))

      ["approve-sole", "--display-code", display_code, "--device-label", device_label] ->
        owner = Accounts.get_owner() || raise ArgumentError, "Mac CI owner is missing"

        _approved =
          approve_sole!(owner, %{display_code: display_code, device_label: device_label})

      _ ->
        Mix.raise(
          "expected provision --output PATH, approve --request-id ID --display-code CODE " <>
            "--device-label LABEL, approve-sole --display-code CODE --device-label LABEL, " <>
            "or second --output PATH"
        )
    end
  end

  def device_label, do: @device_label

  @doc "Creates the owner and restores a first-only synthetic catalogue baseline."
  def provision! do
    owner = Accounts.get_owner() || create_owner!()
    reset_second_sentinel!(owner)
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

  @doc """
  Approves the sole pending pairing request without requiring its id --
  the id is server-generated and never shown to the human (or the test
  driving the app's own UI), so unlike `approve_exact!/2` this identifies
  the request by device label alone plus "there is exactly one pending
  request" (the same invariant `approve_exact!/2` already trusts).
  Used by the live-server pairing ceremony proof (plan 04.5-01), where the
  request is created by the app itself, not by this fixture.
  """
  def approve_sole!(owner, claims) do
    scope = Scope.for_user(owner)

    request =
      case Pairing.list_pending_requests(scope) do
        [request] ->
          request

        pending ->
          raise ArgumentError, "expected sole pending pairing request, got #{length(pending)}"
      end

    require_equal!(request.display_code, claims.display_code, "display code")
    require_equal!(request.claimed_device_name, claims.device_label, "device label")

    case Pairing.approve(scope, request.id) do
      {:ok, approved} ->
        require_equal!(approved.display_code, claims.display_code, "approved display code")
        approved

      {:error, reason} ->
        raise ArgumentError, "sole approval failed: #{inspect(reason)}"
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

  # The serial hosted UI-test plan reuses one server owner. Snapshot tests add
  # Sentinel Two to prove refresh behavior, while later pairing/save tests
  # provision a fresh client mirror that must contain only Sentinel One. Remove
  # only the exact disposable synthetic catalogue row after that proof and
  # journal the tombstone; leave its content-addressed bytes and import receipt
  # intact. Exclusion is insufficient because full snapshots include excluded
  # rows so clients can reconstruct that state too.
  defp reset_second_sentinel!(owner) do
    sentinel_sha256 = :crypto.hash(:sha256, @second.bytes) |> Base.encode16(case: :lower)
    sentinel_title = @second.title

    query =
      from(asset_set in AssetSet,
        join: member in AssetMember,
        on: member.asset_set_id == asset_set.id,
        join: blob in Blobs.Blob,
        on: blob.id == member.blob_id,
        where: asset_set.user_id == ^owner.id,
        where: asset_set.display_title == ^sentinel_title,
        where: blob.sha256 == ^sentinel_sha256,
        select: asset_set
      )

    case Repo.transaction(fn ->
           query
           |> Repo.all()
           |> Enum.each(fn asset_set ->
             with {:ok, _deleted} <- Repo.delete(asset_set),
                  {:ok, _tombstone} <-
                    ChangeJournal.tombstone(owner.id, :catalogue, asset_set.id) do
               :ok
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end)

           :ok
         end) do
      {:ok, :ok} -> :ok
      {:error, _reason} -> raise ArgumentError, "could not reset second CI sentinel"
    end
  end

  # Imports only one of the already-registered self-authored GB/GBC fixtures. The
  # registry is private local setup; paths and hashes never leave this
  # task's process. The production blob and Import contexts own byte
  # custody and catalogue creation exactly as they do for normal uploads.
  defp import_gb_fixture!(owner, registry_path, fixture_name) do
    registry = Path.expand(registry_path)

    private_registry =
      Path.expand("../../../../playstead-mac/.local/gb-gbc-spike/fixtures/fixtures.json", __DIR__)

    generated_registry =
      Path.expand("../../../../playstead-mac/.build/ci/gb-gbc-fixtures/fixtures.json", __DIR__)

    unless registry in [private_registry, generated_registry] do
      raise ArgumentError, "GB fixture registry identity mismatch"
    end

    expected = %{
      "gb-mbc1-8k" => %{
        system: "gb",
        cartridge_type: 3,
        sram_bytes: 8192,
        rtc: false,
        filename: "gb-mbc1-8k.gb",
        sha256: "4d62166b5cd35185ac0977eb73fe5bc22b406141861832863f133d754f635aa4"
      },
      "gbc-mbc5-32k" => %{
        system: "gbc",
        cartridge_type: 27,
        sram_bytes: 32768,
        rtc: false,
        filename: "gbc-mbc5-32k.gbc",
        sha256: "f9d914ba107bfd9676c730d315956a2d264c6e0e74e042afd729f493dcb40a3b"
      },
      "gbc-mbc3-rtc" => %{
        system: "gbc",
        cartridge_type: 16,
        sram_bytes: 32768,
        rtc: true,
        filename: "gbc-mbc3-rtc.gbc",
        sha256: "0edb186314a8fee38e00fec0c52e678ba24abf5b00198e3cfcb80c0d3e60cbc7"
      }
    }

    with %{
           system: system,
           cartridge_type: cartridge_type,
           sram_bytes: sram_bytes,
           rtc: rtc,
           filename: filename,
           sha256: pinned_sha256
         } <-
           Map.fetch!(expected, fixture_name),
         {:ok, registry_bytes} <- File.read(registry),
         {:ok, rows} when is_list(rows) <- Jason.decode(registry_bytes),
         %{
           "name" => ^fixture_name,
           "system" => ^system,
           "cartridge_type" => ^cartridge_type,
           "sram_bytes" => ^sram_bytes,
           "rtc" => ^rtc,
           "path" => fixture_path,
           "sha256" => expected_sha256
         } <- Enum.find(rows, &(&1["name"] == fixture_name)),
         true <- is_binary(fixture_path) and is_binary(expected_sha256),
         true <- expected_sha256 == pinned_sha256,
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, expected_sha256),
         fixture_path <- Path.expand(fixture_path, Path.dirname(registry)),
         true <-
           String.starts_with?(fixture_path, Path.dirname(registry) <> "/"),
         {:ok, %{size: size, type: :regular}} <- File.lstat(fixture_path),
         true <- size >= 0x150 and size <= 64 * 1024 * 1024,
         {:ok, status, meta} <-
           Playstead.Blobs.put_stream(
             File.stream!(fixture_path, [], 65_536),
             size,
             expected_sha256: expected_sha256
           ),
         {:ok, receipt} <-
           Import.import_single(
             owner.id,
             %{original_name: filename, origin: "mac_ci_fixture", size_bytes: size},
             {status, meta}
           ),
         {:ok, detail} <- Catalogue.get_asset_detail(Scope.for_user(owner), receipt.asset_set_id),
         true <-
           Enum.any?(
             detail.asset_set.asset_members,
             &(&1.role == "primary" and &1.blob.sha256 == expected_sha256)
           ) do
      %{
        asset_set_id: detail.asset_set.id,
        outcome: receipt.outcome,
        sha256: meta.sha256,
        size_bytes: meta.size_bytes,
        system: detail.asset_set.system_id
      }
    else
      _ -> raise ArgumentError, "registered GB fixture import failed closed"
    end
  end

  # This private fixture path is intentionally separate from the public
  # generated GB/GBC aliases. It accepts only the exact ignored registry and
  # immutable owner-supplied ROM digest, then uses the same production blob
  # custody and single-file Import contexts.
  defp import_aerevenadvance_fixture!(owner, registry_path) do
    registry = Path.expand(registry_path)

    static_registry =
      Path.expand("../../../../playstead-mac/.local/test-fixtures/aerevenadvance.json", __DIR__)

    profile_root = System.get_env("PLAYSTEAD_GB_GBC_SAVE_E2E_PROFILE_ROOT", "") |> Path.expand()
    isolated_registry = Path.join([profile_root, "aereven-fixture", "aerevenadvance.json"])

    isolated_root? =
      profile_root != Path.expand(".") and
        Regex.match?(~r/^playstead-gb-save-e2e\.[A-Za-z0-9]{6}$/, Path.basename(profile_root))

    unless registry == static_registry or (isolated_root? and registry == isolated_registry) do
      raise ArgumentError, "AerevenAdvance fixture registry identity mismatch"
    end

    expected_sha = "de968dca9f86f1648bb2bb992d6ce4aa4007d3bf7a064b4bbfd82a96e29409ab"
    expected_size = 5_564_940

    with {:ok, registry_bytes} <- File.read(registry),
         {:ok,
          %{
            "schema" => "playstead.local-test-fixture.v1",
            "fixture_id" => "aerevenadvance",
            "system_id" => "gba",
            "game" => game
          }} <- Jason.decode(registry_bytes),
         %{"path" => fixture_path, "sha256" => ^expected_sha, "size_bytes" => ^expected_size} <-
           game,
         {:ok, stat} <- File.stat(registry),
         true <- Bitwise.band(stat.mode, 0o777) == 0o600,
         fixture_path <- Path.expand(fixture_path),
         {:ok, %{size: ^expected_size, type: :regular}} <- File.lstat(fixture_path),
         {:ok, status, meta} <-
           Playstead.Blobs.put_stream(File.stream!(fixture_path, [], 65_536), expected_size,
             expected_sha256: expected_sha
           ),
         {:ok, receipt} <-
           Import.import_single(
             owner.id,
             %{
               original_name: "AerevenAdvance.gba",
               origin: "mac_ci_fixture",
               size_bytes: expected_size
             },
             {status, meta}
           ),
         {:ok, detail} <- Catalogue.get_asset_detail(Scope.for_user(owner), receipt.asset_set_id),
         true <- detail.asset_set.system_id == "gba",
         true <-
           Enum.any?(
             detail.asset_set.asset_members,
             &(&1.role == "primary" and &1.blob.sha256 == expected_sha and
                 &1.blob.size_bytes == expected_size)
           ) do
      %{
        asset_set_id: detail.asset_set.id,
        outcome: receipt.outcome,
        sha256: meta.sha256,
        size_bytes: meta.size_bytes,
        system: detail.asset_set.system_id
      }
    else
      _ -> raise ArgumentError, "registered AerevenAdvance import failed closed"
    end
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
