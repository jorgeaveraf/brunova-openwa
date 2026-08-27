#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=deploy/scripts/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command curl
require_command jq
api_port="$(env_value API_PORT)"
api_key="$(env_value API_MASTER_KEY)"
base="http://127.0.0.1:${api_port}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"; unset api_key' EXIT

code="$(curl -sS -o "$tmp/ready" -w '%{http_code}' "$base/api/health/ready")"
[ "$code" = 200 ] || die "readiness returned HTTP $code"
jq -e '.status == "ready" or .status == "ok" or .ready == true' "$tmp/ready" >/dev/null || die 'unexpected readiness payload'

code="$(curl -sS -o "$tmp/dashboard" -w '%{http_code}' "$base/")"
[ "$code" = 200 ] || die "dashboard returned HTTP $code"
rg -qi '<!doctype html|<html' "$tmp/dashboard" || die 'dashboard did not return HTML'

code="$(curl -sS -o /dev/null -w '%{http_code}' "$base/api/sessions")"
[ "$code" = 401 ] || die "unauthenticated API returned HTTP $code instead of 401"
code="$(curl -sS -o "$tmp/sessions" -w '%{http_code}' -H "X-API-Key: $api_key" "$base/api/sessions")"
[ "$code" = 200 ] || die "authenticated API returned HTTP $code"
jq -e 'type == "array"' "$tmp/sessions" >/dev/null || die 'session list is not JSON array'

code="$(curl -sS -o /dev/null -w '%{http_code}' "$base/api/docs")"
[ "$code" = 404 ] || die "Swagger endpoint returned HTTP $code instead of 404"
code="$(curl -sS -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' --data '{}' "$base/mcp")"
[ "$code" = 404 ] || die "MCP endpoint returned HTTP $code instead of 404"

printf 'Smoke test passed: readiness, dashboard, API authentication, Swagger off, MCP off.\n'
