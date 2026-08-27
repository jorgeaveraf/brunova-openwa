# Backup and restore

The wrapper uses the release's in-container SQLite `.backup` implementation, then packages the
OpenWA state archive with the exact Compose file, real operational environment, Nginx template,
release/digest, source commit, and running image ID. The outer archive is encrypted using
AES-256-CBC with PBKDF2-HMAC-SHA256 and 200,000 iterations. Plaintext staging is created with
restrictive permissions and removed on exit. A SHA-256 manifest is stored inside the encrypted
payload and must verify before restore touches the running service.

```bash
deploy/scripts/backup.sh
deploy/scripts/restore.sh backups/openwa-backup-YYYYMMDD-HHMMSSZ.tar.gz.enc
```

Backups contain the WhatsApp device session, plaintext bootstrap API key, databases, generated
configuration, and possibly message/media content. Treat possession of one as potential possession
of the WhatsApp account. Archives and the passphrase never enter Git. Store the passphrase separately
from archives, copy archives to an encrypted private off-host destination, restrict access, and test
retrieval. Local retention defaults to 14 days and is configurable through
`OPENWA_BACKUP_RETENTION_DAYS`.

Restore decrypts and validates paths, stops OpenWA, invokes the upstream strict restore into the
named volume, starts the pinned image, waits for health, and runs smoke tests. It preserves the
current `deploy/.env.production`; the archived environment is evidence for disaster recovery and is
not silently activated. When the service is running, the wrapper first creates a second encrypted
backup of the current state. The short-lived recovery container alone receives a writable rootfs so
the upstream script can create its sibling safety snapshot; the regular application remains
read-only.

A recovery claim is valid only after a controlled test proves that pre-backup database/session state
returns and post-backup state disappears, followed by readiness and authenticated API success. Never
restore while the regular app container is running. Never discard old profiles automatically when a
Chromium change makes one unusable.
