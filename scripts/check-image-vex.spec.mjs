import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import test from 'node:test';

const script = path.resolve('scripts/check-image-vex.mjs');
const digest = `sha256:${'a'.repeat(64)}`;
const product = `pkg:oci/brunova/openwa@${digest}`;

async function fixture({ fixedVersion = '', status = 'not_affected' } = {}) {
  const dir = await mkdtemp(path.join(tmpdir(), 'openwa-vex-'));
  const scan = path.join(dir, 'scan.json');
  const vex = path.join(dir, 'vex.json');
  const output = path.join(dir, 'after.json');
  await writeFile(scan, JSON.stringify({ Metadata: { ImageID: digest }, Results: [{ Vulnerabilities: [{ VulnerabilityID: 'CVE-TEST-1', Severity: 'CRITICAL', FixedVersion: fixedVersion }] }] }));
  await writeFile(vex, JSON.stringify({ '@context': 'https://openvex.dev/ns/v0.2.0', author: 'test', timestamp: '2026-08-27T00:00:00Z', statements: [{ vulnerability: { name: 'CVE-TEST-1' }, products: [{ '@id': product }], status, justification: 'vulnerable_code_not_present', impact_statement: 'Evidence. Invalidation condition: component returns.' }] }));
  return { scan, vex, output };
}

test('passes an evidenced, unfixable critical finding', async () => {
  const f = await fixture();
  const result = spawnSync(process.execPath, [script, f.scan, f.vex, f.output], { encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(await readFile(f.output)).decision, 'PASS');
});

test('rejects a fixable finding even when VEX says not affected', async () => {
  const f = await fixture({ fixedVersion: '2.0' });
  const result = spawnSync(process.execPath, [script, f.scan, f.vex], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Fixable/);
});

test('rejects an unresolved critical finding', async () => {
  const f = await fixture({ status: 'under_investigation' });
  const result = spawnSync(process.execPath, [script, f.scan, f.vex], { encoding: 'utf8' });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /under_investigation/);
});
