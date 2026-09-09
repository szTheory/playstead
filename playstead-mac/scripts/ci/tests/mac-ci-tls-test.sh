#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TLS_SCRIPT="${CI_DIR}/mac-ci-tls.sh"

[ -x "$TLS_SCRIPT" ] || { printf 'mac-ci-tls.sh missing or not executable\n' >&2; exit 1; }

# This test must not mutate the machine's keychain -- issue/fingerprint only.
ROOT="$(mktemp -d "${TMPDIR:-/tmp}/mac-ci-tls-test.XXXXXX")"
cleanup() { rm -rf "$ROOT"; }
trap cleanup EXIT

"$TLS_SCRIPT" issue "$ROOT"

for f in ca.pem ca.der ca-key.pem server.pem server-key.pem; do
  [ -f "$ROOT/tls/$f" ] || { printf 'missing expected file: %s\n' "$f" >&2; exit 1; }
done
[ ! -f "$ROOT/tls/server.csr" ] || { printf 'server.csr must be removed after issue\n' >&2; exit 1; }

[ "$(stat -f '%Lp' "$ROOT/tls")" = "700" ] || { printf 'tls/ must be mode 0700\n' >&2; exit 1; }
for f in "$ROOT"/tls/*; do
  [ "$(stat -f '%Lp' "$f")" = "600" ] || { printf '%s must be mode 0600\n' "$f" >&2; exit 1; }
done

openssl x509 -in "$ROOT/tls/server-leaf.pem" -noout -text | grep -q 'IP Address:127.0.0.1' ||
  { printf 'leaf certificate is missing IP:127.0.0.1 SAN\n' >&2; exit 1; }
openssl x509 -in "$ROOT/tls/server-leaf.pem" -noout -text | grep -q 'TLS Web Server Authentication' ||
  { printf 'leaf certificate is missing the serverAuth EKU\n' >&2; exit 1; }
openssl x509 -in "$ROOT/tls/ca.pem" -noout -text | grep -q 'CA:TRUE' ||
  { printf 'CA certificate is missing CA:TRUE\n' >&2; exit 1; }

openssl verify -CAfile "$ROOT/tls/ca.pem" "$ROOT/tls/server-leaf.pem" >/dev/null ||
  { printf 'leaf certificate does not verify against the issued CA\n' >&2; exit 1; }

# The final certificate in server.pem (the chain) must be byte-identical to ca.pem.
awk -v outdir="$ROOT/chain-part-" '
  /-----BEGIN CERTIFICATE-----/ { n++ }
  { print > (outdir n ".pem") }
' "$ROOT/tls/server.pem"
last_part="$(ls "$ROOT"/chain-part-*.pem | sort -t- -k3 -n | tail -1)"
cmp -s "$last_part" "$ROOT/tls/ca.pem" ||
  { printf 'final certificate in server.pem is not byte-identical to ca.pem\n' >&2; exit 1; }
rm -f "$ROOT"/chain-part-*.pem

if "$TLS_SCRIPT" issue "$ROOT" 2>/dev/null; then
  printf 'a second issue against an existing root must exit non-zero\n' >&2
  exit 1
fi

printf 'mac-ci-tls contract: passed\n'
