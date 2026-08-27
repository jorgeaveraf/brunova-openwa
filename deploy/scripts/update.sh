#!/usr/bin/env bash
set -euo pipefail
umask 077
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

[ "$#" -eq 2 ] || die 'usage: update.sh <version> <registry/image@sha256:digest>'
new_version="$1"
new_image="$2"
case "$new_image" in *@sha256:[0-9a-f][0-9a-f]*) ;; *) die 'new image must be pinned by sha256 digest' ;; esac

"$SCRIPT_DIR/backup.sh"
state_dir="$REPO_ROOT/.deploy-state"
mkdir -p "$state_dir"
chmod 0700 "$state_dir"
cp "$ENV_FILE" "$state_dir/env.previous"
chmod 0600 "$state_dir/env.previous"
tmp="$(mktemp "${ENV_FILE}.tmp.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
awk -v image="$new_image" -v version="$new_version" '
  /^OPENWA_IMAGE=/ { print "OPENWA_IMAGE=" image; next }
  /^OPENWA_VERSION=/ { print "OPENWA_VERSION=" version; next }
  { print }
' "$ENV_FILE" >"$tmp"
chmod 0600 "$tmp"
mv "$tmp" "$ENV_FILE"
trap - EXIT

if ! "$SCRIPT_DIR/deploy.sh"; then
  cp "$state_dir/env.previous" "$ENV_FILE"
  chmod 0600 "$ENV_FILE"
  "$SCRIPT_DIR/deploy.sh" || true
  die 'update failed; previous image configuration restored'
fi
printf 'Update accepted. Previous environment retained at .deploy-state/env.previous.\n'
