#!/usr/bin/env bash
set -euo pipefail
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

image="$(env_value OPENWA_IMAGE)"
case "$image" in
  *@sha256:[0-9a-f][0-9a-f]*) ;;
  *) die 'OPENWA_IMAGE must be pinned by sha256 digest' ;;
esac
[ "$(env_value NODE_ENV)" = production ] || die 'NODE_ENV must be production'
[ "$(env_value ENGINE_TYPE)" = whatsapp-web.js ] || die 'ENGINE_TYPE must be whatsapp-web.js'
[ "$(env_value DATABASE_TYPE)" = sqlite ] || die 'DATABASE_TYPE must be sqlite'
[ "$(env_value STORAGE_TYPE)" = local ] || die 'STORAGE_TYPE must be local'
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
