FROM cgr.dev/chainguard/wolfi-base@sha256:256c88bb066424045021090932d50be93c8e3f2ce3586707702a401b146f3e43

COPY build/generated/packages /tmp/decoder-repo
COPY build/generated/SOURCE-PINS.json /usr/share/licenses/media-decoder/SOURCE-PINS.json
COPY runner.py /usr/local/bin/runner
COPY server.py /opt/media-decoder/server.py

RUN apk_arch="$(apk --print-arch)" \
    && apk_repo="/tmp/decoder-repo/$apk_arch" \
    && test -s "$apk_repo/python-3.15-3.15.0_git20261010-r0.apk" \
    && test -s "$apk_repo/python-3.15-base-3.15.0_git20261010-r0.apk" \
    && test -s "$apk_repo/glib-2.90.1-r0.apk" \
    && test -s "$apk_repo/libvips-8.18.7-r1.apk" \
    && cp /tmp/decoder-repo/decoder-signing.rsa.pub /etc/apk/keys/decoder-signing.rsa.pub \
    && apk add --no-cache \
      "$apk_repo/python-3.15-3.15.0_git20261010-r0.apk" \
      "$apk_repo/python-3.15-base-3.15.0_git20261010-r0.apk" \
      "$apk_repo/glib-2.90.1-r0.apk" "$apk_repo/libvips-8.18.7-r1.apk" \
    && mkdir -p /usr/share/licenses/media-decoder/provenance /run/playstead-media /tmp/decoder \
    && find /tmp/decoder-repo -type f -name '*.attest.tar.gz' -exec cp '{}' /usr/share/licenses/media-decoder/provenance/ \; \
    && test -s /usr/share/licenses/glib/LGPL-2.1-or-later.txt \
    && test -s /usr/share/licenses/libvips/LICENSE \
    && test -s /usr/share/licenses/python-3.15/LICENSE \
    && test -d /var/lib/db/sbom \
    && test -n "$(find /var/lib/db/sbom -maxdepth 1 -type f -name '*.spdx.json' -print -quit)" \
    && rm -rf /tmp/decoder-repo \
    && rm -f /etc/apk/keys/decoder-signing.rsa.pub \
    && chmod 0555 /usr/local/bin/runner /opt/media-decoder/server.py \
    && chown 11001:11001 /run/playstead-media /tmp/decoder \
    && apk --no-network --no-scripts del apk-tools busybox wolfi-base wolfi-keys libxcrypt libcrypt1-2.44

USER 11001:11001
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 TMPDIR=/tmp/decoder
ENTRYPOINT ["/usr/local/bin/runner"]
