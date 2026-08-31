#!/bin/sh
# Runs as root for exactly as long as it takes to fix bind-mount ownership,
# then drops to `nobody` and never returns to root.
#
# Why this exists: the Dockerfile chowns /app/exports to `nobody` at build
# time, but compose bind-mounts ./exports over it. A bind mount carries the
# HOST directory's ownership into the container, so the image's chown is
# discarded — and because ./exports is not tracked in git, Docker creates it
# root-owned on a fresh clone. The app, running as `nobody`, then cannot
# write a single export.
#
# This is invisible on macOS (Docker Desktop's VirtioFS translates UIDs) and
# fatal on Linux, which is where self-hosters actually deploy. The
# `compose-smoke` CI job caught it on its first run against a Linux runner.
#
# Named volumes (/app/blobs) do NOT need this — Docker seeds a fresh named
# volume from the image path, ownership included — so they are left alone.
set -eu

EXPORT_PATH="${PLAYSTEAD_EXPORT_PATH:-/app/exports}"

if [ "$(id -u)" = "0" ]; then
  mkdir -p "$EXPORT_PATH"

  # Non-recursive by design: this makes new exports writable without
  # stalling startup to walk an export directory that may hold many large
  # files. Pre-existing root-owned content from a broken deploy keeps its
  # ownership; remove or chown it by hand if that ever matters.
  chown nobody:nogroup "$EXPORT_PATH"

  # setpriv ships in the Debian runner image (util-linux), so this needs no
  # extra package the way gosu or su-exec would.
  exec setpriv --reuid=nobody --regid=nogroup --clear-groups "$@"
fi

# Already unprivileged (e.g. `docker run --user`): nothing to fix, nothing
# to drop. Run the command as-is rather than failing on a chown we cannot do.
exec "$@"
