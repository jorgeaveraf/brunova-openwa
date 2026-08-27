#!/usr/bin/env node

import { readFile, writeFile } from 'node:fs/promises';

const [scanPath, vexPath, outputPath] = process.argv.slice(2);
if (!scanPath || !vexPath) {
  console.error('Usage: node scripts/check-image-vex.mjs <trivy.json> <openvex.json> [after-vex.json]');
  process.exit(2);
}

const [scan, vex] = await Promise.all([
  readFile(scanPath, 'utf8').then(JSON.parse),
  readFile(vexPath, 'utf8').then(JSON.parse),
]);

const imageId = scan?.Metadata?.ImageID;
if (!/^sha256:[a-f0-9]{64}$/.test(imageId ?? '')) {
  throw new Error('Trivy report does not contain an immutable sha256 image ID');
}
const productDigest = process.env.OPENWA_VEX_PRODUCT_DIGEST ?? imageId;
if (!/^sha256:[a-f0-9]{64}$/.test(productDigest)) {
  throw new Error('OPENWA_VEX_PRODUCT_DIGEST must be an immutable sha256 digest');
}
const productId = `pkg:oci/brunova/openwa@${productDigest}`;
if (vex?.['@context'] !== 'https://openvex.dev/ns/v0.2.0' || !vex.author || !vex.timestamp) {
  throw new Error('OpenVEX document is missing its v0.2 context, author, or timestamp');
}

const findings = (scan.Results ?? []).flatMap((result) => result.Vulnerabilities ?? []);
const gated = findings.filter((finding) => ['CRITICAL', 'HIGH'].includes(finding.Severity));
const fixable = gated.filter((finding) => (finding.FixedVersion ?? '').trim() !== '');
if (fixable.length) {
  throw new Error(`Fixable CRITICAL/HIGH findings remain: ${[...new Set(fixable.map((f) => f.VulnerabilityID))].join(', ')}`);
}

const criticalIds = [...new Set(gated.filter((f) => f.Severity === 'CRITICAL').map((f) => f.VulnerabilityID))].sort();
const validJustifications = new Set([
  'component_not_present',
  'vulnerable_code_not_present',
  'vulnerable_code_not_in_execute_path',
  'vulnerable_code_cannot_be_controlled_by_adversary',
  'inline_mitigations_already_exist',
]);
const statements = new Map();
for (const statement of vex.statements ?? []) {
  const id = statement?.vulnerability?.name;
  if (!id) continue;
  if (!statement.products?.some((product) => product['@id'] === productId)) continue;
  statements.set(id, statement);
}

for (const id of criticalIds) {
  const statement = statements.get(id);
  if (!statement) throw new Error(`${id} has no OpenVEX statement for ${productId}`);
  if (statement.status !== 'not_affected') throw new Error(`${id} is ${statement.status}, not not_affected`);
  if (!validJustifications.has(statement.justification)) throw new Error(`${id} has no valid not_affected justification`);
  if (!statement.impact_statement?.includes('Invalidation condition:')) {
    throw new Error(`${id} does not state its invalidation condition`);
  }
}

const result = {
  schemaVersion: 1,
  imageId,
  productDigest,
  productId,
  input: {
    records: gated.length,
    uniqueCritical: criticalIds.length,
    uniqueHigh: new Set(gated.filter((f) => f.Severity === 'HIGH').map((f) => f.VulnerabilityID)).size,
    fixableCriticalOrHigh: fixable.length,
  },
  vex: {
    notAffectedCritical: criticalIds,
    unresolvedCritical: [],
  },
  decision: 'PASS',
};

if (outputPath) await writeFile(outputPath, `${JSON.stringify(result, null, 2)}\n`, { mode: 0o644 });
console.log(`PASS: ${criticalIds.length} unique critical CVEs are evidenced by OpenVEX; 0 fixable CRITICAL/HIGH.`);
