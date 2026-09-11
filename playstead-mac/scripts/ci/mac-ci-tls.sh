#!/usr/bin/env bash
# Run-scoped TLS issuer for the mac_ci Phoenix fixture (ROADMAP criterion 6).
#
# Every subcommand takes exactly one argument: <server_root>, the value of
# PLAYSTEAD_MAC_CI_ROOT. All material lives under <server_root>/tls so a
# run's own native root remains the sole source of truth for its trust
# anchor -- nothing here reads or writes outside that directory tree except
# `trust`/`untrust`, which mutate the System keychain by design.
#
# `issue` refuses a pre-existing tls/ directory (T-04.5-06 / A-01): two
# concurrent live-server runs sharing one root must never clobber or share a
# private key. `untrust` never swallows a real failure -- a leftover trusted
# root on a machine is the worst outcome this script can produce.
set -euo pipefail

usage() {
  printf 'usage: %s {issue|trust|untrust|fingerprint} <server_root>\n' "$(basename "$0")" >&2
  exit 2
}

[ "$#" -eq 2 ] || usage
action="$1"
server_root="$2"
[ -n "$server_root" ] || usage
tls_root="$server_root/tls"

fingerprint_of() {
  # Bare uppercase hex, no colons -- the exact form `security delete-certificate -Z` expects.
  openssl x509 -in "$tls_root/ca.pem" -noout -fingerprint -sha1 |
    sed -n 's/^.*Fingerprint=//p' | tr -d ':' | tr '[:lower:]' '[:upper:]'
}

cmd_issue() {
  if [ -e "$tls_root" ]; then
    printf 'mac-ci-tls: %s already exists -- refusing to clobber or share a run'"'"'s TLS material\n' "$tls_root" >&2
    exit 1
  fi
  mkdir -m 0700 "$tls_root"

  cat >"$tls_root/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
prompt = no

[dn]
CN = Playstead Mac CI Root

[v3_ca]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash

[v3_leaf]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = IP:127.0.0.1,DNS:localhost
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid,issuer
CNF

  (
    umask 077

    local_ca_cn="Playstead Mac CI Root $(uuidgen)"

    openssl req -x509 -newkey rsa:2048 -sha256 -days 397 -nodes \
      -keyout "$tls_root/ca-key.pem" -out "$tls_root/ca.pem" \
      -config "$tls_root/openssl.cnf" -extensions v3_ca \
      -subj "/CN=$local_ca_cn"

    openssl req -new -newkey rsa:2048 -nodes \
      -keyout "$tls_root/server-key.pem" -out "$tls_root/server.csr" \
      -config "$tls_root/openssl.cnf" -subj "/CN=127.0.0.1"

    openssl x509 -req -in "$tls_root/server.csr" \
      -CA "$tls_root/ca.pem" -CAkey "$tls_root/ca-key.pem" -CAcreateserial \
      -days 397 -sha256 -extfile "$tls_root/openssl.cnf" -extensions v3_leaf \
      -out "$tls_root/server-leaf.pem"

    # CA MUST be last: PinnedCertificateCapture pins chain.last. A leaf-only
    # or leaf-first chain would pin the leaf and break the pinned relaunch path.
    cat "$tls_root/server-leaf.pem" "$tls_root/ca.pem" >"$tls_root/server.pem"

    openssl x509 -in "$tls_root/ca.pem" -outform DER -out "$tls_root/ca.der"
  )

  chmod 0600 "$tls_root"/*
  rm -f "$tls_root/server.csr"
}

cmd_fingerprint() {
  [ -f "$tls_root/ca.pem" ] || { printf 'mac-ci-tls: no CA at %s\n' "$tls_root/ca.pem" >&2; exit 1; }
  fingerprint_of
}

cmd_trust() {
  sudo -n true 2>/dev/null || { printf 'mac-ci-tls: passwordless sudo unavailable\n' >&2; exit 1; }
  [ -f "$tls_root/ca.pem" ] || { printf 'mac-ci-tls: no CA at %s\n' "$tls_root/ca.pem" >&2; exit 1; }
  sudo -n security add-trusted-cert -d -r trustRoot -p ssl \
    -k /Library/Keychains/System.keychain "$tls_root/ca.pem"
  printf 'mac-ci-tls: trusted %s\n' "$(fingerprint_of)"
}

cmd_untrust() {
  local fp remaining
  fp="$(fingerprint_of 2>/dev/null || true)"
  sudo -n true 2>/dev/null || { printf 'mac-ci-tls: passwordless sudo unavailable\n' >&2; exit 1; }

  # Removal is best-effort; the VERIFICATION below is what decides the exit
  # status. Structuring it the other way round is how an empty $fp used to
  # skip every check and still report success (WR-01): when `ca.pem` was gone
  # at untrust time, `[ -n "$fp" ]` was false, both guarded branches were
  # skipped, and the function printed "untrusted" and returned 0 while the
  # anchor was still installed -- the exact outcome the header forbids.
  sudo -n security remove-trusted-cert -d "$tls_root/ca.pem" 2>/dev/null || true
  if [ -n "$fp" ]; then
    sudo -n security delete-certificate -Z "$fp" /Library/Keychains/System.keychain 2>/dev/null || true
  fi

  # Unconditional: always ask the keychain what actually survived.
  remaining="$(sudo -n security find-certificate -a -Z -c "Playstead Mac CI Root" \
    /Library/Keychains/System.keychain 2>/dev/null || true)"

  if [ -n "$fp" ]; then
    if printf '%s' "$remaining" | grep -qi "$fp"; then
      printf 'mac-ci-tls: UNTRUST FAILED %s\n' "$fp" >&2
      exit 1
    fi
    printf 'mac-ci-tls: untrusted %s\n' "$fp"
    return 0
  fi

  # No fingerprint: `ca.pem` is missing or unreadable, so this run's anchor
  # cannot be targeted by -Z. Deleting every "Playstead Mac CI Root" by common
  # name would clobber a concurrent run's anchor, so refuse to guess -- a
  # surviving root fails loudly and names the manual remedy. A guard that
  # cannot verify must not answer "safe".
  if [ -n "$remaining" ]; then
    printf 'mac-ci-tls: UNTRUST FAILED (no fingerprint -- %s/ca.pem missing or unreadable)\n' "$tls_root" >&2
    printf 'mac-ci-tls: a Playstead Mac CI Root is still trusted; remove it with:\n' >&2
    printf '  sudo security delete-certificate -c "Playstead Mac CI Root" /Library/Keychains/System.keychain\n' >&2
    exit 1
  fi
  printf 'mac-ci-tls: untrusted (no Playstead Mac CI Root present)\n'
}

case "$action" in
  issue) cmd_issue ;;
  fingerprint) cmd_fingerprint ;;
  trust) cmd_trust ;;
  untrust) cmd_untrust ;;
  *) usage ;;
esac
