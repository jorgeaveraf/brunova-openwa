'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { applyExposeRacePatch, EXPOSE_FIND, EXPOSE_REPLACE } = require('./patch-wwebjs-expose-race');

const SOURCE = `async function exposeFunctionIfAbsent(page, name, fn) {
    const exist = await page.evaluate((name) => {
        return !!window[name];
    }, name);
    if (exist) {
        return;
    }
${EXPOSE_FIND}
}

module.exports = { exposeFunctionIfAbsent };
`;

function fakeWwjs(source = SOURCE) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'wwjs-expose-race-'));
  const utilDir = path.join(dir, 'src', 'util');
  fs.mkdirSync(utilDir, { recursive: true });
  const utilFile = path.join(utilDir, 'Puppeteer.js');
  fs.writeFileSync(utilFile, source);
  return { dir, utilFile };
}

test('applies the repair once and is idempotent', () => {
  const { dir, utilFile } = fakeWwjs();
  assert.deepEqual(applyExposeRacePatch(dir), {
    skipped: false,
    note: 'concurrent exposeFunction registration race repaired',
  });
  assert.ok(fs.readFileSync(utilFile, 'utf8').includes(EXPOSE_REPLACE));
  assert.equal(applyExposeRacePatch(dir).skipped, true);
});

test('the patched helper tolerates only the concurrent already-exists error', async () => {
  const { dir, utilFile } = fakeWwjs();
  applyExposeRacePatch(dir);
  const { exposeFunctionIfAbsent } = require(utilFile);

  await assert.doesNotReject(() =>
    exposeFunctionIfAbsent(
      {
        evaluate: async () => false,
        exposeFunction: async () => {
          throw new Error(
            "Failed to add page binding with name onQRChangedEvent: window['onQRChangedEvent'] already exists!",
          );
        },
      },
      'onQRChangedEvent',
      () => undefined,
    ),
  );

  await assert.rejects(
    exposeFunctionIfAbsent(
      {
        evaluate: async () => false,
        exposeFunction: async () => {
          throw new Error('Protocol error: target closed');
        },
      },
      'onQRChangedEvent',
      () => undefined,
    ),
    /target closed/,
  );
});

test('refuses an unknown shape without modifying it', () => {
  const { dir, utilFile } = fakeWwjs('module.exports = {};\n');
  const before = fs.readFileSync(utilFile, 'utf8');
  assert.throws(() => applyExposeRacePatch(dir), /unsupported Puppeteer\.js shape/);
  assert.equal(fs.readFileSync(utilFile, 'utf8'), before);
});

test('CLI is fatal by default and best-effort for a missing dependency', () => {
  const { spawnSync } = require('node:child_process');
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'wwjs-expose-race-cli-'));
  const scriptDir = path.join(root, 'scripts');
  fs.mkdirSync(scriptDir);
  const script = path.join(scriptDir, 'patch-wwebjs-expose-race.js');
  fs.copyFileSync(path.join(__dirname, 'patch-wwebjs-expose-race.js'), script);

  const bare = spawnSync(process.execPath, [script], { encoding: 'utf8' });
  assert.equal(bare.status, 1);
  assert.match(bare.stderr, /Puppeteer utility not found/);

  const bestEffort = spawnSync(process.execPath, [script, '--best-effort'], { encoding: 'utf8' });
  assert.equal(bestEffort.status, 0);
  assert.match(bestEffort.stderr, /skipped/);
});
