# Environment contract

## File roles

| File | Git | Runtime | Purpose |
| --- | --- | --- | --- |
| Root `.env` | ignored | no | Operator-only VPS access material; never passed to Compose |
| `deploy/.env.production` | ignored | yes | Canonical OpenWA/Compose runtime configuration, mode `0600` |
| `deploy/env.production.example` | tracked | no | Sanitized names, comments and non-secret defaults |
| `deploy/.backup-passphrase` | ignored | backup only | Local encryption passphrase, mode `0600`, stored separately off-host |

The root `.env` observed during preparation contains only `VPS_HOSTNAME` and `VPS_PSWD`. Both are set
but failed the conservative hostname/password format checks; neither is a supported OpenWA runtime
variable. Correct or rotate them before any VPS access. Their values were not printed, copied, or
committed.

## Required production values

| Variable | Present in template | Format | Secret | Used by runtime | Required action |
| --- | --- | --- | --- | --- | --- |
| `OPENWA_IMAGE` | yes | immutable official SHA-256 digest | no | Compose | Keep pinned |
| `OPENWA_VERSION` | yes | exact release | no | operations | Keep aligned with image/source |
| `API_PORT` | yes | integer, loopback published by Compose | no | Compose | Keep `2785` unless approved |
| `NODE_ENV` | yes | `production` | no | application | Required |
| `BASE_URL` | yes | explicit HTTPS URL on VPS | no | application | Replace local URL before VPS |
| `DASHBOARD_URL` | yes | explicit HTTPS URL on VPS | no | application | Replace local URL before VPS |
| `CORS_ORIGINS` | yes | explicit HTTPS origin, never `*` | no | application | Replace local origin before VPS |
| `TRUSTED_PROXIES` | yes | exact Nginx address/CIDR or empty | no | application | Set after network inspection |
| `API_MASTER_KEY` | marker | `owa_k1_` plus 32 random bytes | yes | application | Generate; never commit |
| `API_KEY_PEPPER` | marker | 32 random bytes as hex | yes | application | Generate; never commit |
| `ALLOW_DEV_API_KEY` | yes | `false` | no | application | Required |
| `ENABLE_SWAGGER` | yes | `false` | no | application | Required |
| `MCP_ENABLED` | yes | `false` | no | application | Required |
| `WEBHOOK_SSRF_PROTECT` | yes | `true` | no | application | Required |
| `ENGINE_TYPE` | yes | `whatsapp-web.js` | no | application | Required |
| `MAX_CONCURRENT_SESSIONS` | yes | `1` | no | application | Required |
| `AUTO_START_SESSIONS` | yes | `false` for first VPS deploy | no | application | Enable only after acceptance |
| `DATABASE_TYPE` | yes | `sqlite` | no | application | Required |
| `DATABASE_NAME` | yes | persistent path below `./data` | no | application | Required |
| `MAIN_DATABASE_NAME` | yes | distinct persistent path | no | application | Required |
| `REDIS_ENABLED` | yes | `false` | no | application | Required |
| `QUEUE_ENABLED` | yes | `false` | no | application | Required |
| `CACHE_ENABLED` | yes | `false` | no | application | Required |
| `STORAGE_TYPE` | yes | `local` | no | application | Required |
| `STORAGE_LOCAL_PATH` | yes | persistent path below `./data` | no | application | Required |
| `RATE_LIMIT_*` | yes | positive integers | no | application | Keep conservative values |
| `SEND_PACING_*` | yes | enabled, conservative schedules | no | application | Required |
| `BODY_SIZE_LIMIT` | yes | positive `kb`/`mb` value | no | application | Keep at 10 MiB initially |
| `OPENWA_MEM_LIMIT` | yes | `1280m` | no | Compose | Required |
| `OPENWA_CPU_LIMIT` | yes | `1.0` | no | Compose | Required |
| `OPENWA_PIDS_LIMIT` | yes | `768` | no | Compose | Required |

`deploy/scripts/validate.sh` rejects unknown/duplicate names, weak key formats, unsafe feature flags,
floating images, optional services, public bindings and Docker daemon access. In production mode it
also requires HTTPS origins and `AUTO_START_SESSIONS=false`.
