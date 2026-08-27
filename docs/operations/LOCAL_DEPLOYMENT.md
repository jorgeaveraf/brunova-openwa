# Local deployment

This overlay runs exactly one OpenWA `v0.23.3` container, one SQLite data volume, and no Docker
socket, proxy, PostgreSQL, Redis, MinIO, MCP server, or extra plugin. The published port is bound to
`127.0.0.1` only. The upstream source remains intact; all Brunova operational changes live under
`deploy/` and `docs/operations/`.

## Pinned inputs

- Git tag: `v0.23.3`
- Git commit: `3b7fbe7ef067e0f2f0eccb7c40a38b9f8872f61d`
- Release date: 2026-08-24
- Image: `docker.io/rmyndharis/openwa@sha256:c00b5b589446ce7dd6177f1b871789284bcfbe3612189ba109465025eb0ad4ec`
- ARM64 image manifest: `sha256:2e9d235adc63b5178c365775e5a4398d03a82f9292936257ccef2d18373050fa`
- AMD64 image manifest: `sha256:26ddf0e8abc86d910908435b9f36dc87e5e3399e535eb1362f6691552925a986`
- Runtime observed in the ARM64 image: Node.js 22.23.2, `whatsapp-web.js` 1.34.7, Puppeteer and
  Puppeteer Core 24.38.0, `better-sqlite3` 13.0.3, and Debian Chromium 151.0.7922.173. The declared
  Node minimum is `>=22.13`; the Dockerfile pins Chrome for Testing 146.0.7680.31 on AMD64 but uses
  Debian's native Chromium package for ARM64.

## Clean checkout procedure

```bash
git clone --branch v0.23.3 --single-branch https://github.com/rmyndharis/OpenWA.git openwa
cd openwa
git switch -c brunova/devops-first-v0.23.3
# Apply or merge the Brunova overlay commit.
deploy/scripts/init-secrets.sh
deploy/scripts/validate.sh
deploy/scripts/deploy.sh
```

`init-secrets.sh` creates `deploy/.env.production` and `deploy/.backup-passphrase` with mode `0600`.
It refuses to overwrite either file and never prints their values. Copy the backup passphrase to a
separate password manager before relying on backups; losing it makes every encrypted archive
unrecoverable.

Open `http://127.0.0.1:2785`. The dashboard and API share this origin. Obtain the local API key from
`deploy/.env.production` without pasting it into shell history, and enter it into the dashboard.
The live API is under `/api`; `/api/docs` and `/mcp` must return 404.

## Pair a test number later (human-only)

1. Open the local dashboard and authenticate with the generated key.
2. Create one session named `brunova-test`; leave proxy settings empty.
3. Start it and wait for status `QR_READY`.
4. On a dedicated test phone, open WhatsApp **Settings → Linked devices → Link a device**.
5. Scan the QR shown in the dashboard. Do not copy the QR into tickets, logs, or screenshots.
6. Confirm status `READY`; do not invoke any send endpoint during commissioning.
7. Set `AUTO_START_SESSIONS=true` only after the test account is deliberately linked.

An unlinked session can be stopped from the dashboard. To stop all local resource consumption:

```bash
docker compose --project-directory deploy --env-file deploy/.env.production \
  -f deploy/compose.production.yml stop openwa
```

Do not use `docker compose down -v`: the named volume is credential-bearing persistent state.

## Repeat resource measurements

Run before creating a session, with `QR_READY`, and again after a human links the test account:

```bash
docker stats --no-stream brunova-openwa
docker exec brunova-openwa ps -eo pid,ppid,user,rss,comm,args
docker inspect --format '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{.HostConfig.PidsLimit}} {{.HostConfig.ShmSize}}' brunova-openwa
docker image inspect "$(sed -n 's/^OPENWA_IMAGE=//p' deploy/.env.production)" --format '{{.Size}}'
docker system df -v
docker volume inspect brunova_openwa_data
```

Record a five-minute idle sample after the session reaches `READY`; a one-shot CPU value is not a
capacity measurement. Watch for Chromium crashes or PID exhaustion before reducing limits.
