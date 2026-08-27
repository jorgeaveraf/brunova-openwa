# Sanitized regression summary

Date: 2026-08-27. Target: local AMD64 candidate
`sha256:49dbb3d6b9ae41f4b668fc99918b39aba7dd07ecf3099eb099762313a921e2e7`.
The test used an isolated session and volume; it did not access or modify the pre-existing local
OpenWA container or any real linked session. QR bytes were neither requested nor stored.

Passed:

- Compose rendering; readiness and dashboard HTTP 200.
- API authentication: 401 without key, 200 with the generated test key.
- Swagger, MCP, and metrics endpoints returned 404.
- SQLite creation and local storage; no Redis, PostgreSQL, or MinIO dependency.
- WebSocket authenticated upgrade returned HTTP 101.
- Isolated `brunova-test` session reached `qr_ready`; Chrome remained running.
- Session profile persisted across container recreation.
- Root filesystem read-only, `/tmp` tmpfs `noexec,nosuid,nodev`, `no-new-privileges`, all
  capabilities dropped except the entrypoint's required ownership/user-switch capabilities.
- CPU 1, memory 1280 MiB, PIDs 768; no Docker socket or host bind mount.
- Encrypted backup (AES-256-CBC/PBKDF2, 200,000 iterations), byte-identical decrypt, isolated
  restore, and SQLite integrity `ok` for both databases.
- Update to the candidate and rollback to the prior minimized image with the same data volume.
- Log and artifact heuristics found no secret, token, password value, QR payload, or session export.

Operational nuance: restore needs the data directory below a writable parent so it can create its
pre-restore snapshot. Mounting a volume directly at `/app/data` while the root filesystem is
read-only prevents that sibling snapshot; mounting the volume parent and using `<mount>/data`
passes without weakening the read-only root filesystem.

Resource sample (not an equal-platform benchmark): the existing official idle container used about
141 MiB and 12 PIDs. The candidate at `qr_ready`, under AMD64 emulation on Apple Silicon, used about
902 MiB, 123 PIDs, and 4.13% CPU. VPS sizing must use the conservative candidate result and be
re-measured on native AMD64 during pairing.
