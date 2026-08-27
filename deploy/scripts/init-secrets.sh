#!/usr/bin/env bash
set -euo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
EXAMPLE="$DEPLOY_DIR/env.production.example"
TARGET="$DEPLOY_DIR/.env.production"
PASSPHRASE_FILE="$DEPLOY_DIR/.backup-passphrase"

command -v openssl >/dev/null 2>&1 || { echo 'ERROR: openssl is required' >&2; exit 1; }
[ ! -e "$TARGET" ] || { echo "ERROR: refusing to overwrite existing $TARGET" >&2; exit 1; }
[ ! -e "$PASSPHRASE_FILE" ] || { echo "ERROR: refusing to overwrite existing $PASSPHRASE_FILE" >&2; exit 1; }

master="owa_k1_$(openssl rand -hex 32)"
pepper="$(openssl rand -hex 32)"
passphrase="$(openssl rand -base64 48 | tr -d '\n')"
tmp="$(mktemp "${TARGET}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

awk -v master="$master" -v pepper="$pepper" '
  /^API_MASTER_KEY=__GENERATE_API_MASTER_KEY__$/ { print "API_MASTER_KEY=" master; next }
  /^API_KEY_PEPPER=__GENERATE_API_KEY_PEPPER__$/ { print "API_KEY_PEPPER=" pepper; next }
  { print }
' "$EXAMPLE" >"$tmp"
chmod 0600 "$tmp"
mv "$tmp" "$TARGET"
printf '%s\n' "$passphrase" >"$PASSPHRASE_FILE"
chmod 0600 "$PASSPHRASE_FILE"
trap - EXIT
unset master pepper passphrase
printf 'Created %s and backup passphrase with mode 0600. Secrets were not printed.\n' "$TARGET"
