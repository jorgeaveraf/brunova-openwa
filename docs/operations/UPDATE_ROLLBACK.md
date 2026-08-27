# Update and rollback

Never update from `main`, `latest`, a floating minor tag, or an unverified digest. Review the new
GitHub release, Dockerfile, Compose changes, migrations, dependency deltas, security advisories, and
multi-architecture manifest first. Record the release tag, commit, publication date, index digest,
per-platform digest, Node version, browser version, and WhatsApp engine version.

```bash
deploy/scripts/update.sh 0.24.0 docker.io/rmyndharis/openwa@sha256:FULL_INDEX_DIGEST
```

The update script creates an encrypted pre-update backup, retains the previous secret-bearing env
file under ignored `.deploy-state/`, updates only the version/image fields, validates Compose, pulls,
starts, waits for health, and runs smoke tests. A failed gate restores the prior image configuration
and attempts to bring it back automatically.

For an operator-requested image rollback:

```bash
deploy/scripts/rollback.sh
```

This first backs up the current state and rolls the image configuration back. It intentionally does
not roll data back. If the newer release ran an incompatible migration, select the encrypted
pre-update backup and invoke `restore.sh` explicitly after reviewing migration notes. Preserve both
old and new WhatsApp profiles; Chromium profile formats can change across browser releases, and
automatic deletion would remove the safest recovery path. Never use `docker system prune --volumes`
in this workflow.
