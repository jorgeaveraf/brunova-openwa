#!/usr/bin/env bash
set -euo pipefail
umask 077
# shellcheck source=deploy/scripts/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

previous="$REPO_ROOT/.deploy-state/env.previous"
[ -f "$previous" ] || die 'no previous deployment environment is available'
"$SCRIPT_DIR/backup.sh"
current="$REPO_ROOT/.deploy-state/env.failed-$(date -u +%Y%m%d-%H%M%SZ)"
cp "$ENV_FILE" "$current"
chmod 0600 "$current"
cp "$previous" "$ENV_FILE"
chmod 0600 "$ENV_FILE"
"$SCRIPT_DIR/deploy.sh"
printf 'Rollback healthy. Data was not rolled back; use restore.sh only when a migration requires it.\n'
