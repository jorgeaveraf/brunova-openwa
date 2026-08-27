# OpenWA PoC image triage and gate

Decision date: 2026-08-27. Release: OpenWA `v0.23.3`. Scope: Brunova's AMD64, SQLite-only PoC.

## Result

The local image-security gate passes for the immutable candidate image ID
`sha256:49dbb3d6b9ae41f4b668fc99918b39aba7dd07ecf3099eb099762313a921e2e7`:

- 40 Trivy CRITICAL/HIGH records, 31 unique CVEs.
- 5 CRITICAL records/unique CVEs in the minimized candidate; all have evidence-backed
  `not_affected` OpenVEX statements.
- 35 HIGH records, 26 unique CVEs; zero have a fixed version available from the selected official
  Debian repositories.
- Zero fixable CRITICAL and zero fixable HIGH.
- Full isolated regression passed.

CI reproduced the gate and published the candidate with provenance and SBOM. The immutable
production reference is
`ghcr.io/jorgeaveraf/brunova-openwa@sha256:96feea86223bb69b2fd70e974f42fe483ffa08df092e93e79ad6b1dd2d5551c2`.
The registry-digest scan, VEX gate, and non-root smoke all passed in GitHub Actions run
`33123144905`. Those conditions authorized the production PoC deployment described below.

## Seven-CVE normalization and applicability

| CVE            | Trivy records in full image | Source/runtime component           | Architecture/fix                                      | Loaded or reachable                                                                                           | OpenVEX result                                       |
| -------------- | --------------------------: | ---------------------------------- | ----------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| CVE-2026-13221 |             Perl duplicates | Perl / essential `perl-base`       | no Debian Trixie fix                                  | Perl is not invoked by Node, Chrome, health, API, session, or SQLite backup/restore paths                     | `not_affected`: vulnerable code not in execute path  |
| CVE-2026-34873 |             Mbed duplicates | Mbed TLS TLS 1.3 stack             | no Trixie fix                                         | Mbed packages and TLS stack removed; Chrome uses BoringSSL                                                    | `not_affected`: component not present                |
| CVE-2026-34875 |             Mbed duplicates | Mbed TLS FFDH export               | no Trixie fix                                         | Mbed packages and FFDH consumer removed                                                                       | `not_affected`: component not present                |
| CVE-2026-42496 |             Perl duplicates | `Archive::Tar::_make_special_file` | no Trixie fix                                         | `Archive::Tar`/`perl-modules` absent; scanner maps source advisory to essential `perl-base`                   | `not_affected`: component not present                |
| CVE-2026-58016 |                           1 | GLib D-Bus introspection XML       | no Trixie fix                                         | GLib loaded, but no D-Bus bus/address, Chrome symbol reference, or attacker-controlled introspection consumer | `not_affected`: vulnerable code cannot be controlled |
| CVE-2026-6653  |                           1 | Debian `libxml2`                   | Debian confirms Linux package affected; no Trixie fix | FFmpeg removed; runtime executables and observed Chrome maps do not load libxml2                              | `not_affected`: vulnerable code not in execute path  |
| CVE-2026-8376  |             Perl duplicates | 32-bit Perl regex compiler         | no Trixie fix                                         | image/package/Node are AMD64/x64, pointers 64-bit, no foreign architecture                                    | `not_affected`: vulnerable code not present          |

The full experiment had 16 CRITICAL records but only seven CVE IDs because the same Perl source
advisory was attached to several binary packages. Counts are retained in the raw report; decisions
are made per unique CVE.

## Surface reduction and updates

Removed from the Brunova minimal runtime: FFmpeg, PostgreSQL client and `pg_wrapper`, full Perl,
`libperl`, `perl-modules` and Archive::Tar, Mbed TLS crypto, global npm/npx/yarn, and GNU patch.
`perl-base` remains because it is Debian-essential. The production stage performs an official
Debian upgrade; OpenSSL packages are now `3.5.7-1~deb13u2`, eliminating the previously fixable
HIGH findings.

The candidate contains 810 SBOM components and is 458,044,022 bytes, versus 533,999,103 bytes for
the official local image. The updated Bookworm base still had fixable CRITICAL/HIGH findings. An
Ubuntu 24.04 base scan was clean in isolation, but copying the pinned Trixie-built Node runtime into
Ubuntu failed its runtime loader/glibc compatibility contract. Adopting it would require another
Node delivery chain, so it was rejected despite the smaller raw count.

## Runtime-library evidence

Chrome directly/at runtime loads GLib, GIO, and libdbus. The controlled standalone headless run had
no system or session bus and logged failed bus connections. Its maps did not contain libxml2,
Mbed TLS, or Perl. During the actual `qr_ready` test, Docker Desktop/Rosetta denied `/proc` maps;
that limitation is retained rather than represented as a successful observation. Static linkage
and a controlled same-image standalone Chrome run provide the compensating evidence.

`CVE-2026-58016` must be re-opened if D-Bus is mounted or configured, a consumer of
`g_dbus_node_info_new_for_xml` is added, or untrusted introspection XML becomes accepted.
`CVE-2026-6653` must be re-opened if FFmpeg, an XML parser, or another libxml2 consumer returns.
Every other invalidation condition is recorded directly in `openvex.json` and enforced as a
required field by the gate script.

Primary advisory sources used for the decisions:

- Debian Security Tracker: [CVE-2026-13221](https://security-tracker.debian.org/tracker/CVE-2026-13221),
  [CVE-2026-34873](https://security-tracker.debian.org/tracker/CVE-2026-34873),
  [CVE-2026-42496](https://security-tracker.debian.org/tracker/CVE-2026-42496),
  [CVE-2026-6653](https://security-tracker.debian.org/tracker/CVE-2026-6653), and
  [CVE-2026-8376](https://security-tracker.debian.org/tracker/CVE-2026-8376).
- Mbed TLS upstream advisory:
  [FFDH buffer overflow](https://mbed-tls.readthedocs.io/en/latest/security-advisories/mbedtls-security-advisory-2026-03-ffdh-buffer-overflow/).
- Red Hat's applicability description for
  [CVE-2026-58016](https://access.redhat.com/security/cve/cve-2026-58016).
- NVD's affected-code description for
  [CVE-2026-42496](https://nvd.nist.gov/vuln/detail/CVE-2026-42496).

## Reproducible gate

`scripts/check-image-vex.mjs` rejects any fixable CRITICAL/HIGH, any critical without an exact
product-digest statement, non-`not_affected` status, invalid justification, or missing invalidation
condition. It emits the after-VEX summary while preserving the raw before-VEX report. Unit tests
exercise pass, fixable-finding failure, and unresolved-critical failure.

`.github/workflows/brunova-poc-security.yml` rebuilds the AMD64 minimal profile from the pinned base,
scans without `ignore-unfixed`, binds the reviewed assertions to that build's immutable image ID,
runs the gate, and verifies the non-root runtime contract. On a trusted `main` push, a dependent job
then publishes a commit-qualified GHCR tag with provenance and SBOM, scans the registry digest,
rebinds VEX to that registry digest, and repeats the non-root smoke. A change in packages or findings
therefore cannot inherit the local digest's pass silently.

## Security and deployment status

No secret values, `.env` files, QR content, session material, or container layers are included in
the evidence. Secret-bearing local and remote files remain outside Git with mode `0600`.

## Production PoC closure

The image-security decision is `IMAGE SECURITY PASS — CONTINUE`. The authorized production PoC
then completed on the VPS at `69.48.202.231` from source commit
`1ea7acbc1efdafac9a029c5b84ea3c16acc7922b`:

- Cloudflare and Google independently returned only `A 69.48.202.231`; neither returned an AAAA
  record.
- The host had approximately 2.3 GiB available RAM plus 3 GiB swap before deployment. Existing
  Brunova/n8n containers and unrelated Nginx sites were preserved.
- One hardened `brunova-openwa` container runs the registry image by digest, with a read-only root
  filesystem, dropped capabilities except the entrypoint ownership set, `no-new-privileges`, 1280
  MiB memory, 1 CPU, 768 PIDs, and no Docker socket.
- Port 2785 is bound only to `127.0.0.1`; an external connection attempt timed out. Initial usage was
  about 135 MiB and 12 PIDs. With the linked Chromium engine active, the final sample was about
  765 MiB and 112 PIDs; the container remained healthy with zero restarts.
- Nginx terminates TLS for `wa.brunova.mx`, redirects HTTP to HTTPS, proxies WebSocket, protects the
  dashboard with Basic authentication, leaves `/api/` under OpenWA API-key authentication, applies
  API rate limiting, rotates dedicated logs, and returns 404 for public health, Swagger, and MCP.
  The raw API returned 401 without a key and 200 with the production key; dashboard access returned
  401/200 without/with its separate credential. The WebSocket upgrade returned 101.
- Let's Encrypt issued a hostname-valid certificate expiring 2026-11-25. TLS 1.2/1.3, the active
  renewal timer, and a full `certbot renew --dry-run` were verified.
- Session `brunova-test` reached `qr_ready` without QR material being captured. Jorge performed the
  human scan. Eleven samples over five minutes then remained `ready` with the engine loaded.
- OpenWA's contact-check endpoint confirmed the authorized destination exists and supplied its
  canonical WhatsApp identifier; no JID was guessed.
- A durable local marker moved from `not_attempted` to `attempting` before the network call. Exactly
  one POST was made with the authorized exact text. It returned HTTP 201; only the message-ID suffix
  `BC7972B2_out` was retained. The asynchronous receipt advanced to `read`. No retry occurred and no
  other destination was used.
- Production auto-start was enabled after the PoC. A forced container recreation retained the
  session credentials and message history; the WhatsApp engine reconnected without another QR and
  stabilized at `ready`. The observed reconnect took longer than the initial two-minute probe but
  completed normally with no container restart or session error.
- A post-PoC encrypted backup named `openwa-backup-20260827-231513Z.tar.gz.enc` was copied off-host.
  Its AES-256-CBC/PBKDF2 decryption, six-file structure, and complete SHA-256 manifest were verified;
  the encrypted local copy is mode `0600`.

The resulting classification is `PRODUCTION POC COMPLETE`. No image-security, deployment, pairing,
delivery, TLS-renewal, or off-host-backup blocker remains. Operationally, WhatsApp auto-reconnect can
take roughly three minutes, so monitoring must allow for the browser/engine initialization window
after a container or host restart.
