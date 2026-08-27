#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Used by scripts that source this library; it is intentionally not consumed inside common.sh.
# shellcheck disable=SC2034
REPO_ROOT="$(cd "$DEPLOY_DIR/.." && pwd)"
COMPOSE_FILE="$DEPLOY_DIR/compose.production.yml"
ENV_FILE="${OPENWA_ENV_FILE:-$DEPLOY_DIR/.env.production}"

compose() {
  OPENWA_RUNTIME_ENV_FILE="$ENV_FILE" \
    docker compose --project-directory "$DEPLOY_DIR" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

env_value() {
  key="$1"
  value="$(sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1)"
  [ -n "$value" ] || die "required value missing: $key"
  printf '%s' "$value"
}

wait_healthy() {
  timeout="${1:-180}"
  elapsed=0
  container_id="$(compose ps -q openwa)"
  [ -n "$container_id" ] || die "OpenWA container is not running"
  while [ "$elapsed" -lt "$timeout" ]; do
    state="$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$container_id")"
    if [ "$state" = healthy ]; then
      return 0
    fi
    if [ "$state" = exited ] || [ "$state" = dead ]; then
      die "OpenWA exited before becoming healthy"
    fi
    sleep 2
    elapsed=$((elapsed + 2))
  done
  die "OpenWA did not become healthy within ${timeout}s"
}
