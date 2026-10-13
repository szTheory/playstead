defmodule Playstead.Metadata.MediaDecoderTest do
  use ExUnit.Case, async: false

  alias Playstead.Metadata.MediaDecoder

  @valid_png Base.decode64!(
               "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
             )
  @valid_jpeg Base.decode64!(
                "/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A/fGwsLDSrC20vS7aOzsrONIYIIUWOKKKNQqIiKAqqqgAAAAAYFW6KK+TP6AP/9k="
              )

  @tag :packaged_media_decoder
  test "packaged sidecar fully decodes authored PNG and JPEG into metadata-free bounded PNG" do
    evidence_dir =
      System.get_env("PLAYSTEAD_MEDIA_DECODER_EVIDENCE_DIR") ||
        Path.join(File.cwd!(), "_build/media-decoder-evidence")

    {prepared, prepare_status} =
      System.cmd("bash", ["scripts/prepare-media-decoder-image.sh"],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_EVIDENCE_DIR", evidence_dir}],
        stderr_to_stdout: true
      )

    assert prepare_status == 0, prepared
    image = prepared |> String.trim() |> String.split("\n") |> List.last()
    assert Regex.match?(~r/^sha256:[0-9a-f]{64}$/, image)

    {actual_image, 0} =
      System.cmd("docker", ["image", "inspect", "--format", "{{.Id}}", image],
        cd: File.cwd!(),
        stderr_to_stdout: true
      )

    assert String.trim(actual_image) == image

    {compose_output, 0} =
      System.cmd("docker", ["compose", "-f", "docker-compose.yml", "config", "--format", "json"],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    compose_json =
      if String.starts_with?(String.trim_leading(compose_output), "{") do
        compose_output
      else
        [_, json] = String.split(compose_output, "\n{\n", parts: 2)
        "{\n" <> json
      end

    services = Jason.decode!(compose_json)["services"]
    decoder = services["media-decoder"]
    app = services["app"]
    assert decoder["image"] == image
    assert decoder["network_mode"] == "none"
    assert decoder["read_only"] == true
    assert decoder["user"] == "11001:11001"
    assert decoder["cap_drop"] == ["ALL"]
    assert decoder["pids_limit"] == 32
    assert String.to_integer(decoder["mem_limit"]) == 536_870_912
    assert decoder["cpus"] == 1.0
    assert Enum.any?(decoder["security_opt"], &String.starts_with?(&1, "seccomp="))
    assert length(decoder["volumes"]) == 1
    assert Enum.any?(app["volumes"], &(&1["target"] == "/run/playstead-media"))
    assert app["group_add"] == ["11001"]
    assert app["depends_on"]["media-decoder"]["condition"] == "service_healthy"

    project = "playstead-decoder-test-#{System.unique_integer([:positive])}"

    on_exit(fn ->
      System.cmd("docker", ["rm", "-f", "#{project}-oom-probe"],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

      System.cmd("docker", ["compose", "-p", project, "-f", "docker-compose.yml", "down", "-v"],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )
    end)

    {output, status} =
      System.cmd(
        "docker",
        [
          "compose",
          "-p",
          project,
          "-f",
          "docker-compose.yml",
          "run",
          "--rm",
          "--no-deps",
          "media-decoder",
          "self-test"
        ],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    assert status == 0, output
    assert String.contains?(output, "media decoder self-test passed")

    {startup, 0} =
      System.cmd(
        "docker",
        [
          "compose",
          "-p",
          project,
          "-f",
          "docker-compose.yml",
          "up",
          "-d",
          "--no-deps",
          "media-decoder"
        ],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    {container_output, 0} =
      System.cmd(
        "docker",
        ["compose", "-p", project, "-f", "docker-compose.yml", "ps", "-q", "media-decoder"],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    container_id = container_output |> String.split("\n", trim: true) |> List.last()

    {host_config, 0} =
      System.cmd(
        "docker",
        ["inspect", "--format", "{{json .HostConfig}}", String.trim(container_id)],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    effective = Jason.decode!(host_config)
    assert effective["NetworkMode"] == "none"
    assert effective["ReadonlyRootfs"] == true
    assert effective["UsernsMode"] in ["", nil]
    assert effective["Memory"] == 536_870_912
    assert effective["MemorySwap"] == 536_870_912
    assert effective["NanoCpus"] == 1_000_000_000
    assert effective["PidsLimit"] == 32
    assert effective["CapDrop"] == ["ALL"]
    assert Enum.any?(effective["SecurityOpt"], &String.contains?(&1, "no-new-privileges"))

    runtime_probe =
      "import os,socket; " <>
        "assert os.getuid()==11001; " <>
        "s=open('/proc/self/status').read(); assert 'NoNewPrivs:\\t1' in s; " <>
        "assert not os.access('/opt/media-decoder',os.W_OK); " <>
        "s=socket.socket(); s.settimeout(.5); " <>
        "exec('try:\\n s.connect((\"1.1.1.1\",53))\\n raise AssertionError(\"network available\")\\nexcept OSError: pass')"

    {runtime_output, 0} =
      System.cmd(
        "docker",
        [
          "compose",
          "-p",
          project,
          "-f",
          "docker-compose.yml",
          "exec",
          "-T",
          "media-decoder",
          "python3",
          "-c",
          runtime_probe
        ],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    assert runtime_output == ""

    oom_name = "#{project}-oom-probe"

    {oom_output, oom_status} =
      System.cmd(
        "docker",
        [
          "compose",
          "-p",
          project,
          "-f",
          "docker-compose.yml",
          "run",
          "-T",
          "--name",
          oom_name,
          "--no-deps",
          "media-decoder",
          "python3",
          "-c",
          "data=bytearray(768*1024*1024); data[::4096]=b'x'*(len(data)//4096)"
        ],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    assert oom_status != 0,
           "the 512 MiB decoder cgroup did not stop the 768 MiB probe: #{oom_output}"

    {oom_state, 0} =
      System.cmd("docker", ["inspect", "--format", "{{json .State}}", oom_name],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    assert Jason.decode!(oom_state)["OOMKilled"]

    {_, 0} =
      System.cmd("docker", ["rm", oom_name],
        cd: File.cwd!(),
        env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
        stderr_to_stdout: true
      )

    client =
      "import socket,struct,sys,time; d=bytes.fromhex(sys.argv[1]); m=sys.argv[2].encode(); s=socket.socket(socket.AF_UNIX); " <>
        "exec('for i in range(100):\\n try: s.connect(\\\"/run/playstead-media/decoder.sock\\\"); break\\n except OSError: time.sleep(.05)\\nelse: raise SystemExit(2)'); " <>
        "s.sendall(struct.pack('!I',len(d))+bytes([len(m)])+m+d); h=s.recv(2); assert h==b'OK',h; n=struct.unpack('!I',s.recv(4))[0]; " <>
        "out=b''; exec('while len(out)<n: out+=s.recv(n-len(out))'); assert out.startswith(bytes.fromhex('89504e470d0a1a0a'))"

    for {bytes, mime} <- [{@valid_png, "image/png"}, {@valid_jpeg, "image/jpeg"}] do
      {service_output, 0} =
        System.cmd(
          "docker",
          [
            "compose",
            "-p",
            project,
            "-f",
            "docker-compose.yml",
            "exec",
            "-T",
            "media-decoder",
            "python3",
            "-c",
            client,
            Base.encode16(bytes, case: :lower),
            mime
          ],
          cd: File.cwd!(),
          env: [{"PLAYSTEAD_MEDIA_DECODER_IMAGE", image}],
          stderr_to_stdout: true
        )

      assert is_binary(service_output)
    end

    assert String.contains?(startup, "media-decoder")
  end

  @tag :packaged_media_decoder
  test "hostile and unsupported bytes fail closed without decoder fallback" do
    for {bytes, mime} <- [
          {"not an image", "image/png"},
          {binary_part(@valid_png, 0, 20), "image/png"},
          {@valid_png <> <<0, 0, 0, 8>> <> "acTL" <> <<0::32, 1::32, 0::32>>, "image/png"},
          {<<0xFF, 0xD8, 0xFF, 0xC2>> <> @valid_jpeg, "image/jpeg"},
          {@valid_png, "image/svg+xml"},
          {binary_part(@valid_png, 0, 12) <> :binary.copy(<<0>>, 20_971_520), "image/png"}
        ] do
      assert {:error, _reason} = MediaDecoder.decode(bytes, mime)
    end

    assert byte_size(@valid_jpeg) > 0
  end

  @tag :packaged_media_decoder
  test "decoder refuses a missing socket and enforces request byte limit before IPC" do
    assert {:error, :decoder_unavailable} =
             MediaDecoder.decode(@valid_png, "image/png", socket: "/missing/socket")

    assert {:error, :image_too_large} =
             MediaDecoder.decode(:binary.copy("x", 20_971_521), "image/png")
  end

  test "mac_ci loopback bridge preserves the bounded decoder wire protocol" do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, {:packet, 0}, {:active, false}, {:ip, {127, 0, 0, 1}}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    responder =
      Task.async(fn ->
        {:ok, socket} = :gen_tcp.accept(listener, 2_000)
        {:ok, <<size::unsigned-big-32, mime_size>>} = :gen_tcp.recv(socket, 5, 2_000)
        {:ok, "image/png"} = :gen_tcp.recv(socket, mime_size, 2_000)
        {:ok, @valid_png} = :gen_tcp.recv(socket, size, 2_000)

        :ok =
          :gen_tcp.send(socket, ["OK", <<byte_size(@valid_png)::unsigned-big-32>>, @valid_png])

        :gen_tcp.close(socket)
      end)

    assert {:ok, @valid_png} =
             MediaDecoder.decode(@valid_png, "image/png", socket: {:mac_ci_tcp, port})

    Task.await(responder, 2_000)
    :gen_tcp.close(listener)

    assert {:error, :decoder_unavailable} =
             MediaDecoder.decode(@valid_png, "image/png", socket: {:mac_ci_tcp, port})
  end
end
