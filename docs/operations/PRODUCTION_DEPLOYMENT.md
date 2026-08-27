# Production deployment preparation

This runbook is design-only. It must not be executed on the Brunova VPS until a hostname, access
policy, maintenance window, and off-host backup destination are approved.

Canonical checkout path: `/opt/brunova/openwa`. Canonical runtime environment:
`/opt/brunova/openwa/deploy/.env.production` with mode `0600`. The root `.env` is operator-only VPS
access material and must never be passed to Compose or copied into the runtime environment.

## Intended topology

Internet traffic terminates at host Nginx on 443. Nginx proxies to
`127.0.0.1:2785`; Docker never publishes OpenWA on a public interface. SQLite, media, and the
WhatsApp session profile remain in the named volume `brunova_openwa_data`. No datastore port and no
Docker daemon endpoint are exposed.

## VPS readiness gate

Before deployment, verify at least 1.5 GiB of sustained RAM headroom after existing services, swap
behavior, 5 GiB free working disk beyond normal growth, Docker Compose v2, and that 2785 is unused.
The observed VPS headroom of about 2.08 GiB is narrow but potentially workable for one
`whatsapp-web.js` session; do not add sessions without new measurements. A memory limit is not a
reservation, but OOM contention with existing production services remains a material risk.

1. Copy a reviewed checkout at the pinned release plus the Brunova overlay.
2. Run `deploy/scripts/init-secrets.sh`; replace local URLs with the approved HTTPS hostname.
3. Set `CSP_UPGRADE_INSECURE_REQUESTS=true`, `BASE_URL`, `DASHBOARD_URL`, `CORS_ORIGINS`, and
   `TRUSTED_PROXIES` for the exact Nginx-to-container path.
4. Render `deploy/nginx/openwa.conf`, replacing every `OPENWA_HOSTNAME`. Create a strong htpasswd
   file and preferably add VPN or IP allowlisting. Validate with `nginx -t` before reload.
5. Provision TLS through the existing approved certificate workflow. Do not expose port 2785 in the
   firewall; Nginx is the only public boundary.
6. Configure an encrypted off-host backup copy and test retrieval before go-live.
7. Run validate, deploy, smoke test, and a restore drill during the maintenance window.

Run the read-only preflight before any change:

```bash
cd /opt/brunova/openwa
OPENWA_OFFSITE_BACKUP_TARGET='configured-target-identifier' deploy/scripts/preflight-vps.sh
```

For the authorized production deploy only after every output is reviewed:

```bash
OPENWA_DEPLOY_MODE=production \
OPENWA_PREFLIGHT_APPROVED=YES \
OPENWA_OFFSITE_BACKUP_CONFIGURED=YES \
deploy/scripts/deploy.sh
```

These approvals are process gates, not credentials. Do not save them in `.env.production`, because
that file is passed into the application container.

Monitor container health, session status, restarts, resident memory, CPU, host RAM/swap, disk,
volume size, log growth, Chromium errors, disconnects, QR regeneration, WhatsApp restrictions,
webhook failures, and queue/backlog if a queue is ever enabled. Suggested alerts are sustained host
RAM above 80%, urgent above 85%; any growing swap; two restarts in 15 minutes; readiness failure for
two minutes; disconnected production session; disk above 75%, urgent above 80%; or repeated
Chromium/WhatsApp errors.

The sample Nginx policy adds TLS, HTTP Basic authentication, security headers, a 10 MiB request cap,
timeouts, and 5 requests/second per-IP throttling. Review WebSocket concurrency and upstream proxy
CIDRs on the actual host. API keys remain mandatory behind Nginx; Basic auth is an additional layer,
not a replacement.
