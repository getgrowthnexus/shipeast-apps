/**
 * Render every built page to a PNG so the mirror can be LOOKED at, and so a
 * screen page can be diffed against the Flutter screenshot of the same screen.
 *
 *   node tool/shoot.mjs [--only <name>]
 *
 * Output lands in `build/shots/`, alongside (not inside) the uploadable bundle.
 * Playwright is not a dependency of this repo — it is a local instrument, so it
 * is resolved from wherever it happens to live, the same way the admin panel's
 * harness does it.
 */
import { readdir, mkdir, rm } from 'node:fs/promises';
import { existsSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import os from 'node:os';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const BUILD = path.join(HERE, '..', 'build');
const SHOTS = path.join(HERE, '..', 'shots');
const FRAMES = path.join(SHOTS, 'frames');

const chromium = await (async () => {
  const req = createRequire(import.meta.url);
  for (const root of ['playwright', ...npxCaches()]) {
    try { return req(root).chromium; } catch { /* try the next one */ }
  }
  throw new Error('playwright not found — `npx playwright install chromium` once.');

  function npxCaches() {
    const base = path.join(os.homedir(), '.npm', '_npx');
    if (!existsSync(base)) return [];
    return readdirSync(base).map(
      (d) => path.join(base, d, 'node_modules', 'playwright'));
  }
})();

const only = process.argv.includes('--only')
  ? process.argv[process.argv.indexOf('--only') + 1]
  : null;

await rm(SHOTS, { recursive: true, force: true });
await mkdir(FRAMES, { recursive: true });

const browser = await chromium.launch();
// deviceScaleFactor 2 matches harness.dart, so a page shot and a screen shot
// are directly comparable rather than merely similar.
const ctx = await browser.newContext({
  viewport: { width: 1000, height: 900 },
  deviceScaleFactor: 2,
});
const page = await ctx.newPage();

const errors = [];
page.on('pageerror', (e) => errors.push(`  js: ${e.message}`));
page.on('requestfailed', (r) => {
  // A self-contained page must not reach the network at all. If one does, the
  // inlining in build.py has sprung a leak and the card would render bare.
  errors.push(`  network: ${r.url().slice(0, 90)}`);
});

const files = (await readdir(BUILD)).filter((f) => f.endsWith('.html'));
let shot = 0;

for (const file of files) {
  const name = file.replace(/\.html$/, '');
  if (only && name !== only) continue;
  errors.length = 0;
  await page.goto(pathToFileURL(path.join(BUILD, file)).href,
    { waitUntil: 'load' });
  await page.evaluate(() => document.fonts.ready);
  // The skeleton shimmer breathes forever; freeze it so the shot is stable.
  await page.addStyleTag({ content: '*{animation:none !important}' });
  await page.screenshot({
    path: path.join(SHOTS, `${name}.png`),
    fullPage: true,
  });
  // Also shoot each phone frame on its own. Those are the images that get laid
  // beside the Flutter screenshot of the same screen, and cropping them out of
  // a full-page shot by hand-tuned pixel offsets would break the first time a
  // spec table gained a row.
  const frames = await page.locator('.ds-frame .phone').all();
  for (const [i, frame] of frames.entries()) {
    await frame.screenshot({
      path: path.join(FRAMES, frames.length > 1 ? `${name}-${i + 1}.png` : `${name}.png`),
    });
  }
  shot++;
  if (errors.length) {
    console.log(`${name}:`);
    console.log([...new Set(errors)].join('\n'));
  }
}

await browser.close();
console.log(`shot ${shot} page(s) -> ${path.relative(process.cwd(), SHOTS)}`);
