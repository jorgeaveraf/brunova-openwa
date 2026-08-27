# Local validation report — 2026-08-27

Host: Apple Silicon ARM64 Mac, Docker Desktop 4.51.0, Engine 28.5.2, Compose 2.40.3. Port 2785 was
free before deployment. The target directory did not exist, so no prior user work required merging.

Authoritative-file review found three non-blocking traps. The shipped `.env.minimal` is explicitly a
development preset (`NODE_ENV=development`, schema synchronize on, API key optional) and must not be
used for this deployment. The primary upstream Compose starts a Docker socket proxy by default even
though OpenWA can degrade without it; this overlay omits it because built-in datastore orchestration
is out of scope. Finally, the conceptual DevOps guide contains a `latest` image example even though
the release workflow and this deployment require an immutable release/digest. The current README's
single-port dashboard description matches the runtime.

The official multi-architecture `v0.23.3` image was pulled by immutable index digest. Compose rendered
one service and created one bridge network plus one named volume. Inspection found one published
socket (`127.0.0.1:2785`), no Docker socket mount, no `DOCKER_HOST`, and no PostgreSQL, Redis, MinIO,
proxy, or sidecar container. The root filesystem was read-only; `no-new-privileges`, `cap_drop: ALL`,
1.25 GiB memory, 1 CPU, 768 PIDs, 256 MiB tmpfs, and 256 MiB `/dev/shm` were active. PID 1 was the
root `dumb-init`/entrypoint required for volume ownership; Node ran as `openwa`.

Functional results:

- readiness 200 and healthy; dashboard HTML 200 on localhost;
- unauthenticated session API 401 and authenticated session API 200;
- Swagger, MCP, and unauthenticated metrics endpoints 404;
- runtime reported `whatsapp-web.js`, SQLite connected, Redis/queue off, local storage, and Docker
  orchestration unavailable;
- only the required built-in engine plugins existed: `whatsapp-web.js` enabled and Baileys installed
  but inactive; no extension plugin was installed;
- `brunova-test` reached `qr_ready` without a phone in 7 seconds; the QR was validated only by type
  and length, never displayed or stored; no message was sent;
- stop removed all Chromium processes; forced container recreation preserved the session row and
  profile directory without auto-starting it;
- smoke tests passed before and after recreation, restore, update, and rollback exercises;
- encrypted backup could not be read as a plaintext tar and contained state plus deployment metadata;
- controlled restore brought back the original session and removed a post-backup disposable row,
  proving the round trip; a pre-restore encrypted backup was also retained;
- log comparison found neither generated secret and no QR payload pattern; restart count remained 0.

Observed resources:

| Condition | Memory | CPU samples | PIDs | Data volume |
| --- | ---: | ---: | ---: | ---: |
| Healthy, before session | 135.1–135.8 MiB | 0–2.18% | 12 | 337 KiB |
| Unlinked session at `qr_ready` | 559–689.7 MiB | 1.88–40.94% | 152 | about 25.4 MiB |
| Final, stopped session/profile retained | 143.1 MiB | 0% one-shot | 12 | 27.59 MiB |
| Linked session, 5-minute active-idle sample | 487–913.1 MiB | 9.09–100.33% | 155–163 | about 153.4 MiB |

The image occupies 533,999,103 bytes. Chromium spawned 10 OS processes; `/dev/shm` remained unused
because the upstream/default launch arguments include `--disable-dev-shm-usage`. Initial healthy
deployment completed in 36 seconds including the image pull; subsequent same-image deploy/rollback gates
completed in 1–2 seconds while already healthy. The encrypted test archive was 13,086,752 bytes.

The linked-session peak leaves roughly 367 MiB below the 1.25 GiB ceiling. Retain the 1.25 GiB,
1 CPU, and 768 PID limits initially: the CPU ceiling was reached briefly during a post-link
sync/reload but health remained stable and use returned to 10–25%. Raise CPU to 1.25 only if active
operation shows sustained saturation or reconnect timeouts and the shared VPS has measured headroom.

## Post-link validation

After a human linked the test number, the single session reported `ready`, `engineLoaded=true`, a
persisted phone and push name, no error, and no account restriction. The number was redacted in test
output. Twenty samples over five minutes showed the range in the table above; the two 100% CPU
samples and 913.1 MiB memory peak recovered without an OOM, health failure, or restart. Chromium had
12 browser-related processes, all owned by `openwa`; summed process RSS was 1.50 GiB but double-counts
shared mappings, so the 913.1 MiB cgroup measurement is authoritative. `/dev/shm` remained unused.

No webhook or automation rule was configured. The session was stopped cleanly, Chromium reached
zero processes, and a 97,689,632-byte encrypted backup was created. After setting
`AUTO_START_SESSIONS=true` and force-recreating the container, the persisted linked session returned
automatically to `ready` in 59 seconds. Post-recreate smoke tests passed, restart count remained zero,
no OOM occurred, and the new container logs contained no API secret, full phone number, QR payload,
or Chromium error match. The linked backup refused plaintext tar parsing and decrypted with its
internal checksum manifest present. No send endpoint was invoked.

Result: local mechanics and active-session recovery are ready, but production approval is blocked by
the high-severity npm audit chain, no authenticated independent image scan, and the fact that
TLS/Nginx/off-host backup/VPS contention have only been prepared, not exercised.
