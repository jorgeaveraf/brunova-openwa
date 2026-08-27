# Brunova OpenWA overlay

This repository tracks [rmyndharis/OpenWA](https://github.com/rmyndharis/OpenWA) and adds a small,
reviewable operational overlay for Brunova. The application code is upstream code pinned to release
`v0.23.3` / commit `3b7fbe7ef067e0f2f0eccb7c40a38b9f8872f61d`; Brunova-owned files live in `deploy/`,
`docs/operations/`, this document, `.brunova-upstream-base`, and the Brunova CI workflow.

The intended deployment is one `whatsapp-web.js` session, one immutable OpenWA container, SQLite and
local persistent storage. Docker publishes only `127.0.0.1:2785`; host Nginx is the future HTTPS and
operator-access boundary. PostgreSQL, Redis, MinIO, MCP and Docker daemon orchestration are excluded.

Never commit `.env`, `deploy/.env.production`, backup passphrases, backups, databases, QR payloads,
logs, certificates, media, or WhatsApp session data. The root `.env` is operator-only VPS access
material and is not consumed by Compose. Runtime configuration has one canonical location:
`deploy/.env.production`, transferred manually through an approved encrypted channel to the same
path under `/opt/brunova/openwa`. It is excluded by both Git and the Docker build context.

To update, fetch `upstream`, review a stable release and its migrations/advisories, merge or rebase
the overlay non-destructively onto that exact tag, update `.brunova-upstream-base`, image/version
digests and runbooks, then run every CI and local recovery gate. Never deploy `main`, `latest`, or a
floating image merely because it is newer.

Start with [the production runbook](docs/operations/PRODUCTION_DEPLOYMENT.md), use the
[VPS deployment package](docs/operations/VPS_DEPLOYMENT_PACKAGE.md), and review the explicit
[production blockers](docs/operations/PRODUCTION_BLOCKERS.md). Then follow the backup, update,
security and incident runbooks in `docs/operations/`. OpenWA uses an unofficial WhatsApp Web
integration: account restriction or breakage remains possible. It must not be used for spam, lists,
campaigns, cold outreach, or burst messaging.

Status: **READY WITH BLOCKERS**, not production-ready. Known dependency advisories, an independent
image scan, real VPS preflight, Nginx/TLS, encrypted off-host backup, host RAM/swap pressure and a
cross-release rollback drill remain explicit release gates. Publishing this repository does not
clear them.
