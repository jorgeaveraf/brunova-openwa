#!/usr/bin/env bash
set -euo pipefail
# shellcheck source=deploy/scripts/common.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_command docker
require_command curl
require_command jq
require_command rg
[ -f "$ENV_FILE" ] || die "missing $ENV_FILE; run deploy/scripts/init-secrets.sh"

mode="$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || stat -c '%a' "$ENV_FILE")"
case "$mode" in 600|400) ;; *) die "$ENV_FILE permissions are $mode; expected 600 or 400" ;; esac

for key in OPENWA_IMAGE API_PORT NODE_ENV API_MASTER_KEY API_KEY_PEPPER ENGINE_TYPE DATABASE_TYPE STORAGE_TYPE; do
  env_value "$key" >/dev/null
done

# Reject typos and stale knobs. The release template is the authoritative application contract;
# the Brunova template adds only Compose/operator fields used by this overlay.
unknown_keys="$(
  awk 'BEGIN{FS="="} /^[[:space:]]*($|#)/{next} /^[A-Za-z_][A-Za-z0-9_]*=/{print $1}' "$ENV_FILE" | sort -u |
    while IFS= read -r candidate_key; do
      if ! awk -F= -v key="$candidate_key" '
        /^[[:space:]]*#/ {line=$0; sub(/^[[:space:]]*#[[:space:]]*/, "", line); split(line, a, "="); if (a[1]==key) found=1}
        /^[A-Za-z_][A-Za-z0-9_]*=/ {if ($1==key) found=1}
        END{exit found ? 0 : 1}
      ' "$REPO_ROOT/.env.example" "$DEPLOY_DIR/env.production.example"; then
        printf '%s\n' "$candidate_key"
      fi
    done
)"
[ -z "$unknown_keys" ] || die "unknown environment variable name(s): $(printf '%s' "$unknown_keys" | tr '\n' ' ')"

duplicate_keys="$(awk 'BEGIN{FS="="} /^[A-Za-z_][A-Za-z0-9_]*=/{count[$1]++} END{for(k in count) if(count[k]>1) print k}' "$ENV_FILE" | sort)"
[ -z "$duplicate_keys" ] || die "duplicate environment variable name(s): $(printf '%s' "$duplicate_keys" | tr '\n' ' ')"

image="$(env_value OPENWA_IMAGE)"
case "$image" in
  *@sha256:[0-9a-f][0-9a-f]*) ;;
  *) die 'OPENWA_IMAGE must be pinned by sha256 digest' ;;
esac
[ "$(env_value NODE_ENV)" = production ] || die 'NODE_ENV must be production'
[ "$(env_value ENGINE_TYPE)" = whatsapp-web.js ] || die 'ENGINE_TYPE must be whatsapp-web.js'
[ "$(env_value DATABASE_TYPE)" = sqlite ] || die 'DATABASE_TYPE must be sqlite'
[ "$(env_value STORAGE_TYPE)" = local ] || die 'STORAGE_TYPE must be local'
[ "$(env_value ALLOW_DEV_API_KEY)" = false ] || die 'ALLOW_DEV_API_KEY must be false'
[ "$(env_value ENABLE_SWAGGER)" = false ] || die 'ENABLE_SWAGGER must be false'
[ "$(env_value MCP_ENABLED)" = false ] || die 'MCP_ENABLED must be false'
[ "$(env_value WEBHOOK_SSRF_PROTECT)" = true ] || die 'WEBHOOK_SSRF_PROTECT must be true'
[ "$(env_value REDIS_ENABLED)" = false ] || die 'REDIS_ENABLED must be false'
[ "$(env_value QUEUE_ENABLED)" = false ] || die 'QUEUE_ENABLED must be false'
[ "$(env_value CACHE_ENABLED)" = false ] || die 'CACHE_ENABLED must be false'
[ "$(env_value MAX_CONCURRENT_SESSIONS)" = 1 ] || die 'MAX_CONCURRENT_SESSIONS must be 1'
[ "$(env_value SEND_PACING_ENABLED)" = true ] || die 'SEND_PACING_ENABLED must be true'

master_key="$(env_value API_MASTER_KEY)"
pepper="$(env_value API_KEY_PEPPER)"
[ "${#master_key}" -ge 48 ] || die 'API_MASTER_KEY is too short'
printf '%s' "$master_key" | rg -q '^owa_k1_[0-9a-fA-F]{64}$' || die 'API_MASTER_KEY format is invalid'
printf '%s' "$pepper" | rg -q '^[0-9a-fA-F]{64}$' || die 'API_KEY_PEPPER format is invalid'
unset master_key pepper

cors="$(env_value CORS_ORIGINS)"
[ "$cors" != '*' ] || die 'CORS_ORIGINS cannot be wildcard'
body_limit="$(env_value BODY_SIZE_LIMIT)"
printf '%s' "$body_limit" | rg -q '^[1-9][0-9]*(kb|mb)$' || die 'BODY_SIZE_LIMIT format is invalid'
unset cors body_limit

for numeric_key in RATE_LIMIT_SHORT_TTL RATE_LIMIT_SHORT_LIMIT RATE_LIMIT_MEDIUM_TTL RATE_LIMIT_MEDIUM_LIMIT RATE_LIMIT_LONG_TTL RATE_LIMIT_LONG_LIMIT OPENWA_PIDS_LIMIT; do
  numeric_value="$(env_value "$numeric_key")"
  printf '%s' "$numeric_value" | rg -q '^[1-9][0-9]*$' || die "$numeric_key must be a positive integer"
done
unset numeric_value

if [ "${OPENWA_DEPLOY_MODE:-local}" = production ]; then
  [ "$(env_value AUTO_START_SESSIONS)" = false ] || die 'AUTO_START_SESSIONS must be false for first production deploy'
  base_url="$(env_value BASE_URL)"
  dashboard_url="$(env_value DASHBOARD_URL)"
  cors_origin="$(env_value CORS_ORIGINS)"
  case "$base_url" in https://*) ;; *) die 'BASE_URL must use HTTPS in production mode' ;; esac
  case "$dashboard_url" in https://*) ;; *) die 'DASHBOARD_URL must use HTTPS in production mode' ;; esac
  case "$cors_origin" in https://*) ;; *) die 'CORS_ORIGINS must be an explicit HTTPS origin in production mode' ;; esac
  unset base_url dashboard_url cors_origin
fi
if rg -q '__GENERATE_|change-me|your-.*-here' "$ENV_FILE"; then
  die 'placeholder found in the real environment file'
fi

rendered="$(mktemp)"
trap 'rm -f "$rendered"' EXIT
chmod 0600 "$rendered"
compose config >"$rendered"

services="$(docker compose --project-directory "$DEPLOY_DIR" --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --services)"
[ "$services" = openwa ] || die "unexpected Compose services: $services"
rg -q '127\.0\.0\.1:' "$rendered" || die 'published port is not loopback-bound'
if rg -q '/var/run/docker\.sock|docker-proxy|0\.0\.0\.0:' "$rendered"; then
  die 'forbidden Docker socket/proxy or public binding found'
fi

printf 'Validation passed: one loopback-only OpenWA service, immutable image, no Docker socket or optional datastore.\n'
