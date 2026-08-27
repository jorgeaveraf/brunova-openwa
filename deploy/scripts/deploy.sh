#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=deploy/scripts/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

if [ "${OPENWA_DEPLOY_MODE:-local}" = production ]; then
  [ "${OPENWA_PREFLIGHT_APPROVED:-}" = YES ] || die 'production deploy requires OPENWA_PREFLIGHT_APPROVED=YES'
  [ "${OPENWA_OFFSITE_BACKUP_CONFIGURED:-}" = YES ] || die 'production deploy requires OPENWA_OFFSITE_BACKUP_CONFIGURED=YES'
  install_dir="${OPENWA_INSTALL_DIR:-/opt/brunova/openwa}"
  [ "$REPO_ROOT" = "$install_dir" ] || die "production checkout must be at $install_dir"
  [ -s "$DEPLOY_DIR/.backup-passphrase" ] || die 'production deploy requires deploy/.backup-passphrase (0600)'
  unset install_dir
fi

"$SCRIPT_DIR/validate.sh"
started="$(date +%s)"
compose pull openwa
compose up -d --remove-orphans openwa
wait_healthy "${OPENWA_HEALTH_TIMEOUT:-180}"
"$SCRIPT_DIR/smoke-test.sh"
elapsed=$(( $(date +%s) - started ))
printf 'Deployment healthy after %ss at http://127.0.0.1:%s\n' "$elapsed" "$(env_value API_PORT)"
