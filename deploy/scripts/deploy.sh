#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

"$SCRIPT_DIR/validate.sh"
started="$(date +%s)"
compose pull openwa
compose up -d --remove-orphans openwa
wait_healthy "${OPENWA_HEALTH_TIMEOUT:-180}"
"$SCRIPT_DIR/smoke-test.sh"
elapsed=$(( $(date +%s) - started ))
printf 'Deployment healthy after %ss at http://127.0.0.1:%s\n' "$elapsed" "$(env_value API_PORT)"
