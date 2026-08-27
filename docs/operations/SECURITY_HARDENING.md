# Security hardening

Applied controls: immutable release image; loopback-only port; one container and one session cap;
SQLite/local storage; read-only root filesystem; no-new-privileges; all capabilities dropped with
only the five required for the root entrypoint's volume ownership repair and `gosu` privilege drop;
bounded memory, CPU, PIDs, temp space, and shared memory; rotated Docker logs; strict CORS; production
validation; Swagger, MCP, dev key, unsigned ingress, Redis, queue, and database query logging off;
SSRF protection on; conservative body, rate, webhook, automation, and outbound pacing limits.

The image deliberately has no `USER` directive: PID 1 starts as root to chown the named volume and
then the entrypoint executes Node/Chromium as `openwa`. Verify the live process user after each image
update. The Compose overlay has neither `/var/run/docker.sock`, `DOCKER_HOST`, nor the upstream Docker
socket proxy. Optional datastore orchestration therefore reports unavailable, which is expected.

There is no supported global `PLUGINS_ENABLED=false` flag in v0.23.3. The plugin module and its
authenticated admin routes remain compiled in, but no plugin is installed or enabled and the plugin
directory starts empty. This is a documented gap; restrict admin keys and verify the registry remains
empty. Likewise, OpenWA provides no application-level encryption at rest for session/media/config
data. Filesystem controls protect the live volume; encrypted backups protect exported copies.

An `npm audit --omit=dev` run on 2026-08-27 reported five high-severity package entries forming one
transitive chain: `whatsapp-web.js` → Puppeteer/Puppeteer Core → `@puppeteer/browsers` →
`extract-zip`, rooted in GHSA-jmr9-qjv8-65gv (unvalidated symlink path traversal). No critical entry
was reported. The affected extraction path is primarily browser acquisition and the immutable ARM64
image uses an already-installed Debian Chromium, which reduces runtime reachability but does not
remove the vulnerable packages. Do not call this production-ready until upstream ships and verifies
a fixed dependency set. Docker Scout was present locally but required Docker Hub login, so an
independent image CVE scan was not completed.

Never log or transmit API keys, QR payloads, session directories, databases, backup passphrases, or
archives. `LOG_LEVEL=warn` prevents the first-boot info banner from persisting the newly seeded raw
master key in Docker logs. Rotate operational API keys approximately every 180 days or after any
suspected exposure. `API_KEY_PEPPER` changes invalidate stored hashes, so rotate through the API and
test the replacement key before changing it.

For production, put Nginx Basic auth plus VPN/IP allowlisting in front of the dashboard, terminate
TLS, keep Docker port binding on loopback, and ensure volume/backups are readable only by the
deployment administrator. The WhatsApp session profile is a credential capable of account takeover.
