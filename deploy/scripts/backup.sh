#!/usr/bin/env bash
set -euo pipefail
umask 077
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command openssl
require_command tar
require_command shasum
"$SCRIPT_DIR/validate.sh" >/dev/null
pass_file="${OPENWA_BACKUP_PASSPHRASE_FILE:-$DEPLOY_DIR/.backup-passphrase}"
[ -s "$pass_file" ] || die "missing backup passphrase file: $pass_file"
backup_dir="${OPENWA_BACKUP_DIR:-$REPO_ROOT/backups}"
mkdir -p "$backup_dir"
chmod 0700 "$backup_dir"
stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT

container_id="$(compose ps -q openwa)"
[ -n "$container_id" ] || die 'OpenWA must be running for an online-consistent backup'
remote_dir='/app/data/.backup-staging'
compose exec -T -e BACKUP_DIR="$remote_dir" openwa /app/scripts/backup.sh >/dev/null
remote_archive="$(compose exec -T openwa sh -c "ls -1t ${remote_dir}/openwa-backup-*.tar.gz | head -n 1" | tr -d '\r')"
[ -n "$remote_archive" ] || die 'upstream backup archive was not created'
docker cp "${container_id}:${remote_archive}" "$stage/openwa-state.tar.gz" >/dev/null
compose exec -T openwa rm -f "$remote_archive"

cp "$COMPOSE_FILE" "$stage/compose.production.yml"
cp "$ENV_FILE" "$stage/env.production"
cp "$DEPLOY_DIR/nginx/openwa.conf" "$stage/openwa.nginx.conf"
image="$(env_value OPENWA_IMAGE)"
{
  printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'release=%s\n' "$(env_value OPENWA_VERSION)"
  printf 'image=%s\n' "$image"
  printf 'source_commit=%s\n' "$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf unknown)"
  printf 'container_image_id=%s\n' "$(docker inspect --format '{{.Image}}' "$container_id")"
} >"$stage/metadata.txt"
(cd "$stage" && shasum -a 256 openwa-state.tar.gz compose.production.yml env.production openwa.nginx.conf metadata.txt) \
  >"$stage/manifest.sha256"

stamp="$(date -u +%Y%m%d-%H%M%SZ)"
output="$backup_dir/openwa-backup-${stamp}.tar.gz.enc"
tar -czf - -C "$stage" . | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 200000 -md sha256 -pass "file:$pass_file" -out "$output"
chmod 0600 "$output"

retention_days="${OPENWA_BACKUP_RETENTION_DAYS:-14}"
case "$retention_days" in ''|*[!0-9]*) die 'OPENWA_BACKUP_RETENTION_DAYS must be an integer' ;; esac
find "$backup_dir" -type f -name 'openwa-backup-*.tar.gz.enc' -mtime "+$retention_days" -delete
printf 'Encrypted backup created: %s\n' "$output"
