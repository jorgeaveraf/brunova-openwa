#!/usr/bin/env bash
set -euo pipefail
umask 077
# shellcheck source=deploy/scripts/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ "$#" -eq 1 ] || die 'usage: restore.sh <openwa-backup-*.tar.gz.enc>'
archive="$1"
[ -f "$archive" ] || die "backup not found: $archive"
require_command openssl
require_command tar
require_command shasum
pass_file="${OPENWA_BACKUP_PASSPHRASE_FILE:-$DEPLOY_DIR/.backup-passphrase}"
[ -s "$pass_file" ] || die "missing backup passphrase file: $pass_file"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

openssl enc -d -aes-256-cbc -pbkdf2 -iter 200000 -md sha256 -pass "file:$pass_file" -in "$archive" -out "$stage/outer.tar.gz"
while IFS= read -r entry; do
  case "$entry" in /*|../*|*/../*|*/..) die "unsafe path in encrypted backup: $entry" ;; esac
done < <(tar -tzf "$stage/outer.tar.gz")
tar -xzf "$stage/outer.tar.gz" -C "$stage"
[ -s "$stage/manifest.sha256" ] || die 'backup is missing its encrypted checksum manifest'
(cd "$stage" && shasum -a 256 -c manifest.sha256) >/dev/null || die 'backup checksum verification failed'
[ -s "$stage/openwa-state.tar.gz" ] || die 'backup is missing OpenWA state archive'
[ -s "$stage/metadata.txt" ] || die 'backup is missing deployment metadata'

# Preserve the current state in a second encrypted archive whenever the app is healthy enough to
# back up. This remains recoverable after the one-off restore container (and its upstream safety
# snapshot in the writable container layer) is removed.
if [ -n "$(compose ps --status running -q openwa)" ]; then
  "$SCRIPT_DIR/backup.sh"
fi
compose stop openwa
OPENWA_RUNTIME_ENV_FILE="$ENV_FILE" docker compose --project-directory "$DEPLOY_DIR" --env-file "$ENV_FILE" \
  -f "$COMPOSE_FILE" -f "$DEPLOY_DIR/compose.restore.yml" \
  run --rm --no-deps --entrypoint /bin/bash \
    -v "$stage/openwa-state.tar.gz:/restore/openwa-state.tar.gz:ro" openwa \
    /app/scripts/restore.sh /restore/openwa-state.tar.gz --strict --force
compose up -d openwa
wait_healthy "${OPENWA_HEALTH_TIMEOUT:-180}"
"$SCRIPT_DIR/smoke-test.sh"
printf 'Restore verified healthy. Current operational env was preserved; archived env is recovery evidence only.\n'
