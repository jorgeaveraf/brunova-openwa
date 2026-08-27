# OpenWA image-security evidence — 2026-08-27

This directory contains sanitized, pre-deployment evidence. It contains no environment files,
API keys, session state, QR data, WhatsApp identifiers, container layers, or registry credentials.

The final local AMD64 candidate is `brunova/openwa:poc-security-candidate`, image ID
`sha256:49dbb3d6b9ae41f4b668fc99918b39aba7dd07ecf3099eb099762313a921e2e7`. The checked-in
OpenVEX product ID is bound to that immutable ID. A registry digest is intentionally not claimed
until a provenance-enabled push completes.

Key files:

- `trivy-before-vex.json`: original full Trixie experiment, before surface reduction.
- `sbom-before-vex.cdx.json`: its CycloneDX SBOM.
- `trivy-candidate-before-vex.json`: final minimal candidate, without suppression and with unfixed findings.
- `trivy-candidate-after-vex.json`: deterministic gate result after applying `docs/security/openvex.json`.
- `sbom-candidate.cdx.json`: candidate CycloneDX SBOM (810 components).
- `candidate-runtime-analysis.txt`: architecture, package, binary, symbol, and D-Bus assertions.
- `chrome-runtime-analysis.txt`: controlled same-image Chrome launch and process maps.
- `regression-summary.md`: sanitized functional and hardening regression record.
- `trivy-version-with-db.json`: scanner and vulnerability database timestamps.

`SHA256SUMS` authenticates the evidence files relative to this directory. Regenerate it after any
intentional evidence change and review the diff before commit.
