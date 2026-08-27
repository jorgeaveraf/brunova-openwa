#!/usr/bin/env bash
set -euo pipefail

command -v docker >/dev/null 2>&1 || { echo 'ERROR: docker is required' >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo 'ERROR: jq is required' >&2; exit 1; }
command -v rg >/dev/null 2>&1 || { echo 'ERROR: rg is required' >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

required_files='deploy/compose.production.yml
deploy/env.production.example
deploy/nginx/openwa.conf
deploy/scripts/preflight-vps.sh
docs/operations/LOCAL_DEPLOYMENT.md
docs/operations/PRODUCTION_DEPLOYMENT.md
docs/operations/BACKUP_RESTORE.md
docs/operations/UPDATE_ROLLBACK.md
docs/operations/SECURITY_HARDENING.md
docs/operations/INCIDENT_RESPONSE.md
docs/operations/ENVIRONMENT_CONTRACT.md
docs/operations/PRODUCTION_BLOCKERS.md
docs/operations/VPS_DEPLOYMENT_PACKAGE.md
BRUNOVA_DEPLOYMENT.md
.brunova-upstream-base'
while IFS= read -r required_file; do [ -f "$required_file" ] || { echo "ERROR: missing $required_file" >&2; exit 1; }; done <<<"$required_files"

base_commit="$(tr -d '[:space:]' <.brunova-upstream-base)"
printf '%s' "$base_commit" | rg -q '^[0-9a-f]{40}$' || { echo 'ERROR: invalid .brunova-upstream-base' >&2; exit 1; }
git cat-file -e "${base_commit}^{commit}"
git merge-base --is-ancestor "$base_commit" HEAD

if git ls-files | rg -q '(^|/)(\.env$|\.env[[:space:]]|\.api-key$|\.backup-passphrase$|[^/]+\.(sqlite|sqlite3|db|pem|key|crt|p12|pfx|enc|log)$)|^(backups?|data|sessions?|logs?|certs?)/|^deploy/(backups?|data|sessions?|logs?|certs?)/'; then
  echo 'ERROR: prohibited runtime/secret artifact is tracked' >&2
  exit 1
fi

if git diff --name-only "$base_commit"..HEAD | rg -q '(^|/)\.env$|(^|/)\.env[[:space:]]|(^|/)\.env\.(local|production|development|test)$|(^|/)[^/]+\.(sqlite|sqlite3|db|pem|key|crt|p12|pfx|enc|log)$|^(backups?|data|sessions?|logs?|certs?)/|^deploy/(backups?|data|sessions?|logs?|certs?)/'; then
  echo 'ERROR: prohibited artifact appears in the Brunova overlay range' >&2
  exit 1
fi

if git diff --numstat "$base_commit"..HEAD | awk '$1=="-" || $2=="-" {found=1} END{exit found ? 0 : 1}'; then
  echo 'ERROR: binary file added or changed in Brunova overlay range' >&2
  exit 1
fi

if stat -c '%s' . >/dev/null 2>&1; then
  tracked_sizes="$(git ls-files -z | xargs -0 stat -c '%s %n')"
else
  tracked_sizes="$(git ls-files -z | xargs -0 stat -f '%z %N')"
fi
if printf '%s\n' "$tracked_sizes" | awk '$1 > 5242880 {found=1} END{exit found ? 0 : 1}'; then
  echo 'ERROR: tracked file larger than 5 MiB' >&2
  exit 1
fi
unset tracked_sizes

image_ref="$(sed -n 's/^OPENWA_IMAGE=//p' deploy/env.production.example)"
printf '%s' "$image_ref" | rg -q '^docker\.io/rmyndharis/openwa@sha256:[0-9a-f]{64}$' || { echo 'ERROR: image is not pinned to the official immutable digest' >&2; exit 1; }
if rg -q '0\.0\.0\.0:|/var/run/docker\.sock|DOCKER_HOST|docker-proxy' deploy/compose.production.yml; then
  echo 'ERROR: forbidden public binding or Docker daemon access in production Compose' >&2
  exit 1
fi
if rg -q 'image:.*:latest' deploy/compose.production.yml; then
  echo 'ERROR: floating latest image in production Compose' >&2
  exit 1
fi

services="$(OPENWA_RUNTIME_ENV_FILE=env.production.example docker compose --env-file deploy/env.production.example -f deploy/compose.production.yml config --services)"
[ "$services" = openwa ] || { echo "ERROR: unexpected Compose services: $services" >&2; exit 1; }

compose_json="$(OPENWA_RUNTIME_ENV_FILE=env.production.example docker compose --env-file deploy/env.production.example -f deploy/compose.production.yml config --format json)"
printf '%s' "$compose_json" | jq -e '
  (.services | keys) == ["openwa"] and
  .services.openwa.read_only == true and
  .services.openwa.restart == "unless-stopped" and
  .services.openwa.mem_limit == "1342177280" and
  .services.openwa.cpus == 1 and
  .services.openwa.pids_limit == 768 and
  .services.openwa.ports == [{"mode":"ingress","host_ip":"127.0.0.1","target":2785,"published":"2785","protocol":"tcp"}] and
  (.services.openwa.volumes | length) == 1 and
  .services.openwa.volumes[0].target == "/app/data" and
  .services.openwa.security_opt == ["no-new-privileges:true"] and
  .services.openwa.cap_drop == ["ALL"] and
  (.services.openwa.healthcheck.test | length) > 0 and
  .volumes["openwa-data"].name == "brunova_openwa_data"
' >/dev/null || { echo 'ERROR: hardened one-session Compose contract changed' >&2; exit 1; }
unset compose_json

rg -q '\(docs/operations/VPS_DEPLOYMENT_PACKAGE\.md\)' BRUNOVA_DEPLOYMENT.md || { echo 'ERROR: VPS package is not linked' >&2; exit 1; }
rg -q '\(docs/operations/PRODUCTION_BLOCKERS\.md\)' BRUNOVA_DEPLOYMENT.md || { echo 'ERROR: production blockers are not linked' >&2; exit 1; }

printf 'Brunova overlay policy passed.\n'
