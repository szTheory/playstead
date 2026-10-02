defmodule Playstead.DesignTokenParityTest do
  use ExUnit.Case, async: true

  @repo_root Path.expand("../../..", __DIR__)
  @contract_path Path.join(@repo_root, "design-system/shared-tokens.json")
  @css_path Path.join(@repo_root, "playstead-server/assets/css/app.css")
  @system_swift_path Path.join(@repo_root, "playstead-mac/Playstead/Design/SystemAccent.swift")
  @status_swift_path Path.join(@repo_root, "playstead-mac/Playstead/Design/StatusToken.swift")

  test "web palette roles match Tailwind declarations" do
    contract = @contract_path |> File.read!() |> Jason.decode!()
    css = File.read!(@css_path)
    css_roles = css_color_roles(css)

    for {role, hex} <- contract["webPalette"] do
      assert css_roles["app-#{role}"] == hex,
             "Tailwind app-#{role} should remain ##{hex}"
    end

    assert css_roles["status-pinned"] == contract["platformSpecific"]["webStatusPinned"]
  end

  test "shared system and status roles match Tailwind and Swift maps" do
    contract = @contract_path |> File.read!() |> Jason.decode!()
    css_roles = @css_path |> File.read!() |> css_color_roles()
    system_roles = @system_swift_path |> File.read!() |> swift_color_roles()
    status_roles = @status_swift_path |> File.read!() |> swift_color_roles()

    for {system_id, token} <- contract["shared"]["systemAccents"] do
      assert css_roles[token["css"]] == token["hex"],
             "Tailwind #{token["css"]} should remain ##{token["hex"]}"

      assert system_roles[token["swift"]] == token["hex"],
             "Swift SystemAccent.#{system_id} should remain ##{token["hex"]}"
    end

    for {role, token} <- contract["shared"]["status"] do
      assert css_roles[token["css"]] == token["hex"],
             "Tailwind #{token["css"]} should remain ##{token["hex"]}"

      assert status_roles[token["swift"]] == token["hex"],
             "Swift StatusToken.#{role} should remain ##{token["hex"]}"
    end
  end

  defp css_color_roles(css) do
    Regex.scan(~r/--color-([a-z-]+):\s*#([0-9A-Fa-f]{6})\s*;/, css, capture: :all_but_first)
    |> Map.new(fn [role, hex] -> {role, String.upcase(hex)} end)
  end

  defp swift_color_roles(source) do
    Regex.scan(~r/"([A-Za-z]+)"\s*:\s*0x([0-9A-Fa-f]{6})/, source, capture: :all_but_first)
    |> Map.new(fn [role, hex] -> {role, String.upcase(hex)} end)
  end
end
