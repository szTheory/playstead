#!/usr/bin/python3
"""Small fixed-protocol Unix socket service around libvips thumbnail."""
import concurrent.futures
import argparse
import base64
import binascii
import os
import resource
import signal
import socket
import struct
import subprocess
import sys
import tempfile
import threading
import time
import zlib

SOCKET = os.environ.get("MEDIA_DECODER_SOCKET", "/run/playstead-media/decoder.sock")
MAX_INPUT = 20 * 1024 * 1024
MAX_OUTPUT = 16 * 1024 * 1024
MAX_ACTIVE = threading.BoundedSemaphore(2)
DEADLINE = 10


def recv_exact(conn, size):
    parts = []
    remaining = size
    while remaining:
        block = conn.recv(min(remaining, 65536))
        if not block:
            raise ValueError("truncated")
        parts.append(block)
        remaining -= len(block)
    return b"".join(parts)


def jpeg_is_baseline(data):
    # Walk marker segments and reject progressive/lossless/arithmetic coding.
    pos = 2
    while pos < len(data):
        if data[pos] != 0xFF:
            return False
        while pos < len(data) and data[pos] == 0xFF:
            pos += 1
        if pos >= len(data):
            return False
        marker = data[pos]
        pos += 1
        if marker in (0xD9, 0xDA):
            return marker == 0xDA
        if marker in (0xD8, 0x01) or 0xD0 <= marker <= 0xD7:
            continue
        if pos + 2 > len(data):
            return False
        size = int.from_bytes(data[pos:pos + 2], "big")
        if size < 2 or pos + size > len(data):
            return False
        if marker in (0xC2, 0xC3, 0xC5, 0xC6, 0xC7, 0xC9, 0xCA, 0xCB, 0xCD, 0xCE, 0xCF):
            return False
        pos += size
    return False


def run_child(args, deadline, preexec_fn=None, env=None):
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise ValueError("timeout")
    process = subprocess.Popen(
        args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
        close_fds=True, preexec_fn=preexec_fn, start_new_session=True, env=env,
    )
    try:
        output, _ = process.communicate(timeout=remaining)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.communicate()
        raise ValueError("timeout")
    return process.returncode, output


def decode(data, mime):
    if not data or len(data) > MAX_INPUT:
        raise ValueError("input_size")
    if mime == b"image/png":
        if not data.startswith(b"\x89PNG\r\n\x1a\n") or b"acTL" in data:
            raise ValueError("unsupported_png")
    elif mime == b"image/jpeg":
        if not data.startswith(b"\xff\xd8\xff") or not jpeg_is_baseline(data) or b"MPF\x00" in data:
            raise ValueError("unsupported_jpeg")
    else:
        raise ValueError("unsupported_type")

    with tempfile.TemporaryDirectory(prefix="decode-") as directory:
        deadline = time.monotonic() + DEADLINE
        src = os.path.join(directory, "input")
        dst = os.path.join(directory, "output.png")
        with open(src, "xb") as stream:
            stream.write(data)
        try:
            width_status, width_output = run_child(["vipsheader", "-f", "width", src], deadline)
            height_status, height_output = run_child(["vipsheader", "-f", "height", src], deadline)
            if width_status or height_status:
                raise ValueError("invalid_image")
            width = int(width_output)
            height = int(height_output)
        except (OSError, ValueError, subprocess.SubprocessError):
            raise ValueError("invalid_image")
        if width < 1 or height < 1 or width > 8192 or height > 8192 or width * height > 40_000_000:
            raise ValueError("image_bounds")
        # libvips runs in a fresh process group. The kernel container limit
        # bounds RSS; the parent deadline kills the whole group on timeout.
        def limits():
            resource.setrlimit(resource.RLIMIT_CPU, (9, 9))
            resource.setrlimit(resource.RLIMIT_FSIZE, (MAX_OUTPUT, MAX_OUTPUT))
            resource.setrlimit(resource.RLIMIT_NOFILE, (32, 32))

        try:
            result_code, _ = run_child(
                ["vips", "thumbnail", src, dst, "1600", "--size", "down", "--fail-on", "warning"],
                deadline,
                preexec_fn=limits,
                env={"PATH": "/usr/bin:/bin", "TMPDIR": tempfile.gettempdir(), "VIPS_CONCURRENCY": "1"},
            )
        except OSError:
            raise ValueError("decoder_failure")
        if result_code != 0:
            raise ValueError("invalid_image")
        with open(dst, "rb") as stream:
            output = stream.read(MAX_OUTPUT + 1)
        if not output.startswith(b"\x89PNG\r\n\x1a\n") or len(output) > MAX_OUTPUT:
            raise ValueError("invalid_derivative")
        return output


def handle(conn):
    with conn:
        try:
            length = struct.unpack("!I", recv_exact(conn, 4))[0]
            mime_length = recv_exact(conn, 1)[0]
            mime = recv_exact(conn, mime_length)
            if length > MAX_INPUT:
                raise ValueError("input_size")
            data = recv_exact(conn, length)
            if not MAX_ACTIVE.acquire(blocking=False):
                raise ValueError("busy")
            try:
                output = decode(data, mime)
            finally:
                MAX_ACTIVE.release()
            conn.sendall(b"OK" + struct.pack("!I", len(output)) + output)
        except ValueError as exc:
            code = str(exc).encode("ascii", "replace")[:32]
            conn.sendall(b"ER" + bytes([len(code)]) + code)
        except (OSError, struct.error):
            try:
                conn.sendall(b"ER\x07failure")
            except OSError:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true")
    if parser.parse_args().self_test:
        return self_test()
    os.umask(0o077)
    test_port = os.environ.get("MEDIA_DECODER_MAC_CI_TCP_PORT")
    if test_port:
        # Docker Desktop cannot expose a container Unix socket to native
        # macOS. Only the isolated mac_ci fixture publishes this port, and
        # its Docker binding is restricted to host loopback.
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.bind(("0.0.0.0", int(test_port)))
    else:
        try:
            os.unlink(SOCKET)
        except FileNotFoundError:
            pass
        server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        server.bind(SOCKET)
        os.chmod(SOCKET, 0o660)
    server.listen(16)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        while True:
            conn, _ = server.accept()
            pool.submit(handle, conn)


def self_test():
    def chunk(kind, body):
        return struct.pack("!I", len(body)) + kind + body + struct.pack("!I", binascii.crc32(kind + body) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack("!2I5B", 1, 1, 8, 6, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(b"\0\0\0\xff\xff")) + chunk(b"IEND", b"")
    jpeg = base64.b64decode("/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8A/fGwsLDSrC20vS7aOzsrONIYIIUWOKKKNQqIiKAqqqgAAAAAYFW6KK+TP6AP/9k=")
    try:
        output = decode(png, b"image/png")
        assert output.startswith(b"\x89PNG\r\n\x1a\n") and len(output) <= MAX_OUTPUT
    except Exception as exc:
        raise SystemExit("valid PNG self-test failed: " + str(exc))
    try:
        output = decode(jpeg, b"image/jpeg")
        assert output.startswith(b"\x89PNG\r\n\x1a\n") and len(output) <= MAX_OUTPUT and b"Exif\x00\x00" not in output
    except Exception as exc:
        raise SystemExit("valid JPEG self-test failed: " + str(exc))
    for data, mime in [
        (b"bad", b"image/png"),
        (png[:18], b"image/png"),
        (png + b"\x00\x00\x00\x08acTL\x00\x00\x00\x00\x00\x00\x00\x01", b"image/png"),
        (b"\xff\xd8\xff\xc2" + jpeg, b"image/jpeg"),
        (png, b"image/svg+xml"),
        (b"x" * (MAX_INPUT + 1), b"image/png"),
    ]:
        try:
            decode(data, mime)
        except ValueError:
            continue
        raise SystemExit("hostile image self-test unexpectedly decoded")
    assert MAX_ACTIVE.acquire(blocking=False)
    assert MAX_ACTIVE.acquire(blocking=False)
    assert not MAX_ACTIVE.acquire(blocking=False)
    MAX_ACTIVE.release()
    MAX_ACTIVE.release()
    local_server, local_client = socket.socketpair()
    worker = threading.Thread(target=handle, args=(local_server,))
    worker.start()
    local_client.sendall(struct.pack("!I", len(png)) + bytes([len(b"image/png")]) + b"image/png" + png)
    assert recv_exact(local_client, 2) == b"OK"
    output_size = struct.unpack("!I", recv_exact(local_client, 4))[0]
    assert recv_exact(local_client, output_size).startswith(b"\x89PNG\r\n\x1a\n")
    worker.join(timeout=DEADLINE + 1)
    local_client.close()
    local_server.close()
    assert not worker.is_alive()
    local_server, local_client = socket.socketpair()
    worker = threading.Thread(target=handle, args=(local_server,))
    worker.start()
    local_client.sendall(struct.pack("!I", 100) + bytes([len(b"image/png")]) + b"image/png" + b"short")
    local_client.shutdown(socket.SHUT_WR)
    assert recv_exact(local_client, 2) == b"ER"
    local_client.close()
    worker.join(timeout=1)
    local_server.close()
    assert not worker.is_alive()
    try:
        run_child([sys.executable, "-c", "import time; time.sleep(30)"], time.monotonic() + 0.1)
    except ValueError as exc:
        assert str(exc) == "timeout"
    else:
        raise SystemExit("timeout self-test process exited unexpectedly")
    try:
        socket.create_connection(("203.0.113.1", 80), timeout=0.1)
    except OSError:
        pass
    else:
        raise SystemExit("network isolation self-test failed")
    try:
        with open("/opt/media-decoder/write-probe", "wb") as stream:
            stream.write(b"x")
    except OSError:
        pass
    else:
        os.unlink("/opt/media-decoder/write-probe")
        raise SystemExit("read-only root self-test failed")
    try:
        memory_max = int(open("/sys/fs/cgroup/memory.max").read().strip())
        pids_max = int(open("/sys/fs/cgroup/pids.max").read().strip())
    except (OSError, ValueError):
        raise SystemExit("container resource limits are not visible")
    if memory_max > 512 * 1024 * 1024 or pids_max > 32:
        raise SystemExit("container memory or process limit exceeds its bound")
    cpu_quota, cpu_period = open("/sys/fs/cgroup/cpu.max").read().split()
    if cpu_quota == "max" or int(cpu_quota) > int(cpu_period):
        raise SystemExit("container CPU limit exceeds its bound")
    status = open("/proc/self/status").read()
    if "Uid:\t11001\t11001\t11001\t11001" not in status or "CapEff:\t0000000000000000" not in status or "NoNewPrivs:\t1" not in status:
        raise SystemExit("container user, capabilities, or no-new-privileges boundary is missing")
    if not os.path.exists("/proc/self/mountinfo"):
        raise SystemExit("container mount boundary unavailable")
    print("media decoder self-test passed")


if __name__ == "__main__":
    main()
