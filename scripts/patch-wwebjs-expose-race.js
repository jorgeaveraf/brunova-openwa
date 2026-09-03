/**
 * Backport whatsapp-web.js#201861 for 1.34.7.
 *
 * A WhatsApp Web navigation can start two inject() pipelines concurrently. The upstream
 * exposeFunctionIfAbsent() helper checks window[name] and calls page.exposeFunction() as two
 * separate async operations, so both pipelines can observe the binding as absent and the slower
 * one rejects with "window[name] already exists". That leaves the post-auth message bridge only
 * partly attached and has been observed immediately before unexpected post_logout navigation.
 *
 * The binding exists after that specific race, so treating only that exact Puppeteer error as
 * success is safe. Every other expose failure still propagates. The exact-shape transform is
 * deliberately self-disabling when upstream ships the repair.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const DEFAULT_WWJS = path.join(__dirname, '..', 'node_modules', 'whatsapp-web.js');
const PUPPETEER_UTIL_PATH = path.join('src', 'util', 'Puppeteer.js');

const EXPOSE_FIND = `    await page.exposeFunction(name, fn);`;

const EXPOSE_REPLACE = `    try {
        await page.exposeFunction(name, fn);
    } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        // Concurrent inject() calls can both pass the existence check. The losing call is
        // successful for our purposes because the page binding now exists; do not hide any
        // other Puppeteer/CDP failure.
        if (!/Failed to add page binding with name .*window\\['.*'\\] already exists!/i.test(message)) {
            throw error;
        }
    }`;

function occurrences(source, needle) {
  return source.split(needle).length - 1;
}

function applyExposeRacePatch(wwjsDir = DEFAULT_WWJS) {
  const utilFile = path.join(wwjsDir, PUPPETEER_UTIL_PATH);
  if (!fs.existsSync(utilFile)) {
    throw new Error(`whatsapp-web.js Puppeteer utility not found at ${utilFile}`);
  }

  const source = fs.readFileSync(utilFile, 'utf8');
  const replacementCount = occurrences(source, EXPOSE_REPLACE);
  const findCount = occurrences(source.split(EXPOSE_REPLACE).join(''), EXPOSE_FIND);

  if (findCount === 0 && replacementCount === 1) {
    return { skipped: true, reason: 'installed whatsapp-web.js already carries the expose race repair' };
  }
  if (findCount === 1 && replacementCount === 0) {
    fs.writeFileSync(utilFile, source.replace(EXPOSE_FIND, EXPOSE_REPLACE));
    return { skipped: false, note: 'concurrent exposeFunction registration race repaired' };
  }
  throw new Error(
    `unsupported Puppeteer.js shape (unpatched: ${findCount}, patched: ${replacementCount}); ` +
      're-evaluate the expose-function race repair against the installed whatsapp-web.js',
  );
}

function run() {
  const bestEffort = process.argv.includes('--best-effort');
  try {
    const result = applyExposeRacePatch();
    console.log(`patch-wwebjs-expose-race: ${result.skipped ? `skipped — ${result.reason}` : result.note}`);
  } catch (error) {
    if (bestEffort) {
      console.warn(`patch-wwebjs-expose-race: skipped — ${error.message}`);
      return;
    }
    console.error(`patch-wwebjs-expose-race: ${error.message}`);
    process.exitCode = 1;
  }
}

if (require.main === module) run();

module.exports = { applyExposeRacePatch, EXPOSE_FIND, EXPOSE_REPLACE };
