# Production release blockers

The repository and deployment tooling are prepared, but production approval remains blocked until
every item below has current evidence for the target VPS and exact image digest.

| Gate | Current state | Evidence required to clear it |
| --- | --- | --- |
| High-severity `puppeteer` / `extract-zip` dependency chain | Blocked | A fixed upstream release and a clean production dependency audit. Do not patch the upstream application ad hoc. |
| Independent container image scan | Pending | Trivy or Grype must scan the exact AMD64 digest with no unresolved high/critical findings accepted silently. |
| Linked-session stability | Locally passed | The local five-minute and restart validation passed previously; repeat the same proof on the VPS before production use. |
| Read-only VPS preflight | Pending | `deploy/scripts/preflight-vps.sh` must finish with `GLOBAL=PASS` or an explicitly reviewed `GLOBAL=WARN`. |
| Nginx and TLS boundary | Pending | Approved hostname, certificate, restrictive proxy configuration and successful `nginx -t`. |
| Encrypted off-site backup | Pending | Configured destination plus a restore proof made from an encrypted backup copied away from the VPS. |
| VPS RAM and swap headroom | Pending | Preflight evidence showing adequate available memory, swap and disk for Chromium. |
| Cross-release rollback drill | Pending | Timed rollback and data/session restore proof across the chosen release boundary. |

The operator-only root `.env` is ignored and untracked, but its `VPS_HOSTNAME` and `VPS_PSWD`
values did not pass the conservative hostname/credential checks. Correct them before using the VPS,
rotate any weak or reused password, and prefer a restricted SSH key. Never copy this file into the
container or the repository.
