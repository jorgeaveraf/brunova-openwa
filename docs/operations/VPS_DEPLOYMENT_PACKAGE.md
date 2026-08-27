# VPS deployment package

This package is prepared for an approved operator; it does not authorize or perform VPS, DNS,
firewall, Nginx or WhatsApp account changes.

## Fixed deployment identity

- Checkout: an explicitly approved commit from Brunova `origin/main`.
- Install directory: `/opt/brunova/openwa`.
- Runtime environment: `/opt/brunova/openwa/deploy/.env.production`, transferred separately with
  mode `0600`; never sourced from the root `.env`.
- Backup secret: an operator-transferred passphrase file with mode `0600`, stored outside Git.
- Persistent volume: `brunova_openwa_data`.
- AMD64 image manifest: `sha256:26ddf0e8abc86d910908435b9f36dc87e5e3399e535eb1362f6691552925a986`.
- First production start: `AUTO_START_SESSIONS=false`; pairing is a separate, manual approval step.

Required versioned material is the production Compose file, environment example, Nginx example,
all `deploy/scripts/` helpers and the operational runbooks. Runtime env files, backups, databases,
certificates, logs, QR payloads, media and session data must be transferred or generated outside Git.

## Approved operator sequence

1. Select and record the exact reviewed `origin/main` commit; never deploy a floating branch or tag.
2. Clone or fetch the Brunova repository over SSH into `/opt/brunova/openwa` and check out that commit.
3. Verify the commit signature/hash and compare `.brunova-upstream-base` with the documented upstream release.
4. Transfer `deploy/.env.production` and the backup passphrase through the approved encrypted channel; set mode `0600`.
5. Confirm production URLs, immutable image digest, `AUTO_START_SESSIONS=false` and all environment-contract gates.
6. Run `deploy/scripts/preflight-vps.sh`; stop on `GLOBAL=FAIL` and review every warning.
7. Run `OPENWA_DEPLOY_MODE=production deploy/scripts/validate.sh`.
8. If an installation already exists, run and export an encrypted backup before changing it.
9. Set the documented approval variables and run the gated `deploy/scripts/deploy.sh`; do not bypass its checks.
10. Run health and smoke checks without pairing, QR capture or outbound messages.
11. Review Nginx/TLS separately, run `nginx -t`, then reload only under explicit infrastructure approval.
12. Copy the encrypted backup off-host and prove a restore in an isolated environment.
13. Only after all release blockers are cleared, authorize and perform manual WhatsApp pairing and the controlled validation plan.

The deployment gate intentionally requires `OPENWA_PREFLIGHT_APPROVED=YES`,
`OPENWA_OFFSITE_BACKUP_CONFIGURED=YES`, the canonical install path and a backup passphrase. Those
flags record human approval; they are not substitutes for evidence.
