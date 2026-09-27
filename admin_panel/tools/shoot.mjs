/**
 * Visual verification harness for the ShipEast admin panel.
 *
 *   node tools/shoot.mjs [outDir]
 *
 * The panel is gated behind Firebase Auth, so a plain page load only ever
 * shows the login card. This builds a throwaway harness page from the REAL
 * index.html and the REAL stylesheets, hides the login layer, reveals #app,
 * and seeds enough static rows into each table that the surfaces under test
 * actually have content in them. Nothing is stubbed visually — every rule
 * being screenshotted is the shipped rule.
 *
 * app.js is deliberately NOT loaded: it would try to reach Firestore, fail,
 * and then blank the tables we are trying to look at. Anything app.js renders
 * is therefore represented here by static markup copied from what it emits.
 */
import { readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { existsSync, readdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import path from 'node:path';
import os from 'node:os';

/* Playwright is not a dependency of this project — it is a local verification
   tool. Resolve it from wherever it happens to live (a project install, a
   global, or the npx cache a `npx playwright` invocation left behind) rather
   than making the caller export NODE_PATH. */
const chromium = await (async () => {
  const req = createRequire(import.meta.url);
  const roots = [ROOT_GUESS(), ...npxCaches()];
  for (const r of roots) {
    try { return req(r).chromium; } catch { /* try the next one */ }
  }
  throw new Error(
    'playwright not found. Install it with `npm i -D playwright` in admin_panel/, '
    + 'or run `npx playwright install chromium` once so the npx cache has it.');

  function ROOT_GUESS() { return 'playwright'; }
  function npxCaches() {
    const base = path.join(os.homedir(), '.npm', '_npx');
    if (!existsSync(base)) return [];
    return readdirSync(base)
      .map(d => path.join(base, d, 'node_modules', 'playwright'))
      .filter(existsSync);
  }
})();

const ROOT = path.resolve(import.meta.dirname, '..');
const OUT = path.resolve(process.argv[2] ?? '/tmp/shipeast-shots');

const PAGES = ['dashboard', 'orders', 'drivers', 'merchants', 'customers',
  'overseas', 'notifications', 'promos', 'analytics', 'settings'];

const VIEWPORTS = [
  { name: 'phone', width: 390, height: 1400 },
  { name: 'tablet', width: 900, height: 1500 },
  { name: 'desktop', width: 1440, height: 1700 },
];

/* Rows shaped like the ones app.js emits, so tables, badges, id cells, action
   buttons and the media chips are all exercised rather than left empty. */
const bdg = (tone, txt) => `<span class="bdg bg-${tone}">${txt}</span>`;
/* Three-icon action cell — matches the driver roster, the only table whose
   rows carry view/edit/delete inline (its column is .tc-act3, 144px). */
const acts = `<div class="cell-actions">
  <button class="aicon ai-v"><svg class="ic" aria-hidden="true"><use href="#i-view"/></svg></button>
  <button class="aicon ai-e"><svg class="ic" aria-hidden="true"><use href="#i-edit"/></svg></button>
  <button class="aicon ai-d"><svg class="ic" aria-hidden="true"><use href="#i-delete"/></svg></button>
</div>`;

/* Single view-icon action cell — what orders, dashboard, customers and the
   overseas roster actually emit at runtime (their column is .tc-act1, 96px).
   Every action for those rows lives in the detail panel, not the table. Using
   `acts` here would wrap three icons into a 96px column and balloon the row —
   a harness artifact, not the shipped layout. */
const actV = `<button class="aicon ai-v"><svg class="ic" aria-hidden="true"><use href="#i-view"/></svg></button>`;

const ROWS = {
  'dash-tbody': [
    `<td class="cell-id">SE-10428</td><td>Devon Campbell</td><td>Tastee Patties</td>
     <td class="cell-mute">Marlon B.</td><td class="right cell-strong">J$2,450</td>
     <td>${bdg('success', 'Delivered')}</td><td>${actV}</td>`,
    `<td class="cell-id">SE-10427</td><td>Alicia Brown</td><td>Juici Patties</td>
     <td class="cell-mute">—</td><td class="right cell-strong">J$980</td>
     <td>${bdg('warning', 'Pending')}</td><td>${actV}</td>`,
    `<td class="cell-id">SE-10426</td><td>Kemar Wright</td><td>Fontana Pharmacy</td>
     <td class="cell-mute">Shanice G.</td><td class="right cell-strong">J$4,120</td>
     <td>${bdg('danger', 'Cancelled')}</td><td>${actV}</td>`,
  ],
  'orders-tbody': [
    `<td class="cell-id">SE-10428</td><td>Devon Campbell</td><td>Tastee Patties</td>
     <td class="cell-mute">Marlon B.</td><td class="right cell-strong">J$2,450</td>
     <td>${bdg('info', 'Card')}</td><td>${bdg('success', 'Delivered')}</td>
     <td class="cell-mute">14:22</td><td>${actV}</td>`,
    `<td class="cell-id">SE-10427</td><td>Alicia Brown</td><td>Juici Patties</td>
     <td class="cell-mute">—</td><td class="right cell-strong">J$980</td>
     <td>${bdg('neutral', 'Cash')}</td><td>${bdg('warning', 'Pending')}</td>
     <td class="cell-mute">14:05</td><td>${actV}</td>`,
  ],
  'drivers-tbody': [
    `<td>Marlon Bennett</td><td class="cell-mute">876-555-0142</td><td>Motorcycle</td>
     <td class="cell-mute">PB 2341</td>
     <td><span class="stars"><svg class="ic" aria-hidden="true"><use href="#i-star-f"/></svg></span>
     <span class="rating-val">4.8</span></td>
     <td class="right cell-strong">312</td><td>${bdg('success', 'Approved')}</td>
     <td><label class="tgl"><input type="checkbox" checked/><span class="ts"></span></label></td>
     <td>${acts}</td>`,
    `<td>Shanice Grant</td><td class="cell-mute">876-555-0198</td><td>Car</td>
     <td class="cell-mute">CE 8890</td>
     <td><span class="stars"><svg class="ic" aria-hidden="true"><use href="#i-star-f"/></svg></span>
     <span class="rating-val">4.6</span></td>
     <td class="right cell-strong">154</td><td>${bdg('warning', 'Pending')}</td>
     <td><label class="tgl"><input type="checkbox"/><span class="ts"></span></label></td>
     <td>${acts}</td>`,
  ],
  'merchants-tbody': [
    `<td><div class="cell-media"><div class="cat-ico c-food">
       <svg class="ic" aria-hidden="true"><use href="#i-cat-food"/></svg></div>
       <span>Tastee Patties</span></div></td>
     <td>${bdg('brand', 'Food')}</td><td class="cell-mute">876-555-0111</td>
     <td class="cell-mute">Half Way Tree, St Andrew</td>
     <td class="right cell-strong">28</td>
     <td><span class="rating-val">4.7</span></td><td>${bdg('success', 'Open')}</td>
     <td><label class="tgl"><input type="checkbox" checked/><span class="ts"></span></label></td>
     <td>${acts}</td>`,
    `<td><div class="cell-media"><div class="cat-ico c-pharmacy">
       <svg class="ic" aria-hidden="true"><use href="#i-cat-pharmacy"/></svg></div>
       <span>Fontana Pharmacy</span></div></td>
     <td>${bdg('info', 'Pharmacy')}</td><td class="cell-mute">876-555-0777</td>
     <td class="cell-mute">Barbican, Kingston</td>
     <td class="right cell-strong">9</td>
     <td><span class="rating-val">4.9</span></td><td>${bdg('neutral', 'Closed')}</td>
     <td><label class="tgl"><input type="checkbox"/><span class="ts"></span></label></td>
     <td>${acts}</td>`,
  ],
  'customers-tbody': [
    `<td>Devon Campbell</td><td class="cell-mute">devon@example.com</td>
     <td class="cell-mute">876-555-0142</td><td class="right cell-strong">14</td>
     <td class="right cell-strong">J$38,400</td><td>${bdg('success', 'Active')}</td>
     <td>${actV}</td>`,
    `<td>Alicia Brown</td><td class="cell-mute">alicia@example.com</td>
     <td class="cell-mute">876-555-0198</td><td class="right cell-strong">3</td>
     <td class="right cell-strong">J$5,120</td><td>${bdg('danger', 'Disabled')}</td>
     <td>${actV}</td>`,
  ],
  'overseas-tbody': [
    `<td class="cell-id">SD-2041</td><td>Marcia Thompson</td><td>Pearl Thompson</td>
     <td class="cell-mute">St Elizabeth</td>
     <td class="cell-mute">Rice, cooking oil, chicken, tinned mackerel</td>
     <td class="right cell-strong">J$12,000</td><td>${bdg('warning', 'New')}</td>
     <td class="cell-mute">2 hrs ago</td><td>${actV}</td>`,
  ],
  'promos-tbody': [
    `<td class="cell-id">SUMMER25</td><td>25% off</td>
     <td class="right cell-strong">42<span class="usage-track">
       <span class="usage-fill u-ok" style="width:42%"></span></span></td>
     <td class="right cell-strong">100</td><td class="cell-mute">31 Aug 2026</td>
     <td>${bdg('success', 'Active')}</td>
     <td><button class="aicon ai-d"><svg class="ic" aria-hidden="true"><use href="#i-delete"/></svg></button></td>`,
    `<td class="cell-id">FREESHIP</td><td>J$300 off</td>
     <td class="right cell-strong">96<span class="usage-track">
       <span class="usage-fill u-danger" style="width:96%"></span></span></td>
     <td class="right cell-strong">100</td><td class="cell-mute">—</td>
     <td>${bdg('warning', 'Almost used up')}</td>
     <td><button class="aicon ai-d"><svg class="ic" aria-hidden="true"><use href="#i-delete"/></svg></button></td>`,
  ],
  'top-merch': [
    `<td>Tastee Patties</td><td class="right cell-strong">28</td><td class="right cell-strong">J$54,200</td>`,
    `<td>Juici Patties</td><td class="right cell-strong">19</td><td class="right cell-strong">J$31,880</td>`,
  ],
};

/* `sm` mirrors renderAnalyticsStats() in app.js, which stamps .sc-val.sm on
   every MONEY value — a currency symbol plus up to seven digits needs a
   smaller step than a bare count does. The harness used to omit it, so the
   one card most likely to overflow was the one card never being tested. */
const STAT = (label, val, sub, accent, icon, sm) => `
<div class="sc${accent ? ' ac-' + accent : ''}">
  <div class="sc-top">
    <div><div class="sc-lbl">${label}</div><div class="sc-val${sm ? ' sm' : ''} num">${val}</div></div>
    <div class="sc-chip${accent ? ' c-' + accent : ''}">
      <svg class="ic" aria-hidden="true"><use href="#i-${icon}"/></svg></div>
  </div>
  <div class="sc-sub">${sub}</div>
</div>`;

const STATS = {
  'drivers-stats': STAT('Total Drivers', '18', 'On the roster', '', 'drivers')
    + STAT('Online Now', '7', 'Accepting orders', 'success', 'bolt')
    + STAT('Pending Approval', '2', 'Awaiting review', 'warning', 'clock')
    + STAT('Avg Rating', '4.7', 'Across all trips', 'info', 'star'),
  'merchants-stats': STAT('Merchants', '46', 'Listed', '', 'merchants')
    + STAT('Open Now', '31', 'Taking orders', 'success', 'bolt')
    + STAT('Avg Rating', '4.6', 'Customer score', 'info', 'star'),
  'customers-stats': STAT('Customers', '1,248', 'Registered', '', 'users')
    + STAT('Ordered This Week', '212', 'Active buyers', 'success', 'receipt')
    + STAT('Lifetime Value', 'J$4.2M', 'All time', 'warning', 'revenue'),
  'overseas-stats': STAT('Requests', '34', 'All time', '', 'send')
    + STAT('Awaiting Quote', '6', 'Needs pricing', 'warning', 'clock')
    + STAT('Completed', '24', 'Delivered', 'success', 'check'),
  'analytics-stats': STAT('Orders', '212', 'This period', '', 'orders')
    + STAT('Revenue', 'J$418,900', 'Delivered only', 'warning', 'revenue', true)
    + STAT('Avg Basket', 'J$1,976', 'Per order', 'info', 'receipt', true)
    + STAT('Completion', '94%', 'Delivered / placed', 'success', 'check'),
};

/* Merchant cards — the merchants page is a GRID OF CARDS, not a table, and the
   grid is filled by renderMerchants() in app.js, which the harness does not run.
   Left unseeded, the one page whose mobile layout cannot be derived from a table
   fold was never actually shot. These mirror renderMerchants()'s markup: a cover
   band with a state badge, the default body (name, category, phone, the open
   switch), the revealed half (address, orders, rating, actions) and the expander.
   One card is pre-expanded (.open) so the revealed half is exercised too. */
const MERCH_ICO = (id, extra = '') =>
  `<svg class="ic${extra ? ' ' + extra : ''}" aria-hidden="true"><use href="#i-${id}"/></svg>`;
const MERCH_STARS = (v) => `<span class="stars">${
  [1, 2, 3, 4, 5].map(i => MERCH_ICO(i <= Math.round(v) ? 'star-f' : 'star',
    i <= Math.round(v) ? '' : 'off')).join('')
  }</span><span class="rating-val">${v.toFixed(1)}</span>`;
const MERCH_CARD = (m) => `<article class="mcd ${m.card}${m.open ? ' open' : ''}">
  <div class="mcd-cover"><div class="mcd-fb ${m.fb}">${MERCH_ICO(m.ico)}</div>
    <div class="mcd-state"><span class="bdg bg-${m.stOpen ? 'success' : 'neutral'}">${m.stOpen ? 'Open' : 'Closed'}</span></div>
  </div>
  <div class="mcd-body">
    <div class="mcd-id"><h3 class="mcd-name" title="${m.name}">${m.name}</h3>
      <span class="bdg bg-info plain bdg-cap mcd-cat">${m.cat}</span></div>
    <div class="mcd-line one">${MERCH_ICO('phone', 'ic-xs')}<span class="num">${m.phone}</span></div>
    <div class="mcd-stats"><div class="mcd-row"><span class="mcd-k">Accepting orders</span>
      <label class="tgl" title="Toggle open"><input type="checkbox"${m.stOpen ? ' checked' : ''}><span class="ts"></span></label></div></div>
  </div>
  <div class="mcd-more">
    <div class="mcd-line">${MERCH_ICO('map-pin', 'ic-xs')}<span class="mcd-addr">${m.addr}</span></div>
    <div class="mcd-row"><span class="mcd-k">Orders Today</span><span class="mcd-v num">${m.today}</span></div>
    <div class="mcd-row"><span class="mcd-k">Rating</span><span class="mcd-v">${
      m.ratings ? MERCH_STARS(m.rating) : '<span class="cell-mute sm">No ratings yet</span>'}</span></div>
    <div class="mcd-acts">
      <button class="aicon ai-v" title="View" aria-label="View merchant">${MERCH_ICO('view')}</button>
      <button class="aicon ai-e" title="Edit" aria-label="Edit merchant">${MERCH_ICO('edit')}</button>
      <button class="aicon ai-d" title="Delete" aria-label="Delete merchant">${MERCH_ICO('delete')}</button>
    </div>
  </div>
  <div class="mcd-foot"><button type="button" class="mcd-exp" aria-expanded="${m.open ? 'true' : 'false'}">
    <span class="mcd-exp-t">${m.open ? 'Hide details' : 'View details'}</span>
    <span class="mcd-exp-ic" aria-hidden="true">${MERCH_ICO('caret-down')}</span></button></div>
</article>`;
const MERCH = [
  { name: 'Tastee Patties', cat: 'Food', card: 'mc-food', fb: 'c-food', ico: 'cat-food',
    phone: '876-555-0111', addr: 'Shop 4, Half Way Tree Plaza, Half Way Tree, St Andrew',
    today: 12, rating: 4.7, ratings: 1, stOpen: true, open: true },
  { name: 'Fontana Pharmacy', cat: 'Pharmacy', card: 'mc-pharmacy', fb: 'c-pharmacy', ico: 'cat-pharmacy',
    phone: '876-555-0777', addr: 'Barbican Centre, Kingston 6', today: 0, rating: 0, ratings: 0, stOpen: false, open: false },
  { name: 'Hi-Lo Food Stores', cat: 'Grocery', card: 'mc-grocery', fb: 'c-grocery', ico: 'cat-grocery',
    phone: '876-555-0230', addr: 'Manor Park, Kingston 8', today: 5, rating: 4.6, ratings: 1, stOpen: true, open: false },
  { name: 'Juici Patties', cat: 'Food', card: 'mc-food', fb: 'c-food', ico: 'cat-food',
    phone: '876-555-0142', addr: 'Portmore Pines Plaza, Portmore', today: 8, rating: 4.5, ratings: 1, stOpen: true, open: false },
].map(MERCH_CARD).join('');

const NOTIF_HIST = ['Flash Sale — 20% Off Deliveries!', 'Service update: Portmore now covered']
  .map((t, i) => `<div class="nh-item">
    <div class="nh-ico"><svg class="ic" aria-hidden="true"><use href="#i-notifications-f"/></svg></div>
    <div><div class="nh-title">${t}</div>
    <div class="nh-meta">Everyone · ${i ? '3 days ago' : '4 hrs ago'}</div></div></div>`).join('');

const ZONES = ['Kingston', 'St Andrew', 'Portmore', 'Spanish Town', 'Montego Bay']
  .map((z, i) => `<div class="zr"><div class="zn">${z}</div>
    <div class="zt"><div class="zf" style="width:${[92, 74, 51, 33, 18][i]}%"></div></div>
    <div class="zv">${[64, 51, 35, 23, 12][i]}</div></div>`).join('');

const PAY = [['Card', 'brand', 62], ['Cash on delivery', 'warning', 38]]
  .map(([l, c, p]) => `<div class="prow"><div class="prow-lbl">${l}</div>
    <div class="ptrack"><div class="pfill ${c}" style="width:${p}%"></div></div>
    <div class="prow-pct">${p}%</div></div>`).join('');

const BARS = (() => {
  const v = [4, 9, 14, 22, 31, 18, 11, 6];
  const max = Math.max(...v), W = 520, H = 190, bw = W / v.length;
  const bars = v.map((n, i) => {
    const h = (n / max) * (H - 46), x = i * bw + 8, y = H - 26 - h;
    return `<g class="bar-g">
      <rect class="bar${n === max ? ' max' : ''}" x="${x}" y="${y}"
        width="${bw - 16}" height="${h}" rx="6"/>
      <text class="bar-val" x="${x + (bw - 16) / 2}" y="${y - 6}">${n}</text>
      <text class="bar-lbl" x="${x + (bw - 16) / 2}" y="${H - 8}">${i * 3}:00</text>
    </g>`;
  }).join('');
  return `<svg viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">
    <defs><linearGradient id="barGrad" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="var(--red-500)"/><stop offset="100%" stop-color="var(--red-500)"/>
    </linearGradient><linearGradient id="barGradMax" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0%" stop-color="var(--red-600)"/><stop offset="100%" stop-color="var(--red-600)"/>
    </linearGradient></defs>
    <line class="grid-line" x1="0" y1="${H - 26}" x2="${W}" y2="${H - 26}"/>
    ${bars}</svg>`;
})();

const SPARK = (color) => `<svg class="spark" viewBox="0 0 120 26" preserveAspectRatio="none">
  <defs><linearGradient id="sp${color.replace(/\W/g, '')}" x1="0" y1="0" x2="0" y2="1">
    <stop offset="0%" stop-color="${color}" stop-opacity=".20"/>
    <stop offset="100%" stop-color="${color}" stop-opacity="0"/></linearGradient></defs>
  <path d="M0 20 L17 14 L34 17 L51 8 L69 11 L86 5 L103 9 L120 3 L120 26 L0 26 Z"
    fill="url(#sp${color.replace(/\W/g, '')})"/>
  <path d="M0 20 L17 14 L34 17 L51 8 L69 11 L86 5 L103 9 L120 3" fill="none"
    stroke="${color}" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"
    vector-effect="non-scaling-stroke"/></svg>`;

async function buildHarness() {
  let html = await readFile(path.join(ROOT, 'index.html'), 'utf8');

  // app.js would reach for Firestore, fail, and wipe the tables we want to see.
  html = html.replace(/<script type="module" src="app\.js"><\/script>/, '');

  // Seed the JS-rendered regions.
  //
  // The replacements MUST be functions, never `$1`-style strings: the seed data
  // is full of Jamaican dollar amounts, and `J$1,976` contains a literal `$1`,
  // which String.replace expands into the captured group. That is what put a
  // second `<div class="sg" id="analytics-stats">` inside the Avg Basket stat
  // and pulled the whole Analytics grid out of shape.
  for (const [id, rows] of Object.entries(ROWS)) {
    const body = rows.map(r => `<tr>${r}</tr>`).join('');
    html = html.replace(new RegExp(`<tbody id="${id}">`), m => m + body);
  }
  for (const [id, markup] of Object.entries(STATS)) {
    html = html.replace(new RegExp(`<div class="sg[^"]*" id="${id}">`), m => m + markup);
  }
  html = html.replace('<div class="mgrid" id="merchants-grid"></div>',
    `<div class="mgrid" id="merchants-grid">${MERCH}</div>`);
  html = html.replace('<span class="sec-count num" id="merchants-count"></span>',
    '<span class="sec-count num" id="merchants-count">4 stores</span>');
  html = html.replace('<div id="notif-hist"></div>', `<div id="notif-hist">${NOTIF_HIST}</div>`);
  html = html.replace('<div id="zone-chart"></div>', `<div id="zone-chart">${ZONES}</div>`);
  html = html.replace('<div id="pay-split"></div>', `<div id="pay-split">${PAY}</div>`);
  html = html.replace('<div class="chart" id="bar-chart"></div>',
    `<div class="chart" id="bar-chart">${BARS}</div>`);
  html = html.replace('<div id="spark-orders"></div>',
    `<div id="spark-orders">${SPARK('var(--red-500)')}</div>`);
  html = html.replace('<div id="spark-revenue"></div>',
    `<div id="spark-revenue">${SPARK('var(--warning)')}</div>`);

  // Filter bars and the search fields are populated by app.js too.
  const tabs = (items) => items.map(([l, n], i) =>
    `<div class="tab${i === 0 ? ' active' : ''}">${l}<b>${n}</b></div>`).join('');
  html = html.replace('<div class="tabs" id="orders-tabs" role="tablist"></div>',
    `<div class="tabs" id="orders-tabs" role="tablist">${tabs(
      [['All', 128], ['Pending', 9], ['Active', 14], ['Delivered', 98], ['Cancelled', 7]])}</div>`);
  html = html.replace('<div class="tabs" id="overseas-tabs" role="tablist"></div>',
    `<div class="tabs" id="overseas-tabs" role="tablist">${tabs(
      [['All', 34], ['New', 6], ['Quoted', 4], ['Approved', 3], ['Shopping', 2],
       ['Delivered', 17], ['Cancelled', 2]])}</div>`);

  // Reveal the app, hide the auth gate, and fill the two live-preview widgets.
  html = html.replace('</head>', `<style>
  #login-page{display:none!important;}
  #app{display:block!important;}
  /* The harness scrolls the whole document so full-page shots capture
     everything; the real panel keeps the sidebar fixed. */
  .sidebar{position:absolute;}
</style></head>`);
  html = html.replace('</body>', `<script>
  document.getElementById('tb-date').textContent =
    new Date(2026, 6, 30).toLocaleDateString('en-GB',
      { weekday:'short', day:'numeric', month:'short' });
  document.getElementById('pv-title').textContent = 'Flash Sale — 20% Off Deliveries!';
  document.getElementById('pv-msg').textContent =
    'Order before 9pm tonight and save on every delivery island-wide.';
  document.getElementById('pcp-code').textContent = 'SUMMER25';
  document.getElementById('pcp-disc').textContent = '25% off your delivery';
  document.getElementById('pcp-valid').textContent = 'Valid until 31 Aug 2026';
  document.getElementById('bell-badge').textContent = '3';
  document.getElementById('bell-badge').removeAttribute('hidden');
  document.getElementById('bell-list').innerHTML =
    [['New order SE-10428','Tastee Patties · J$2,450',''],
     ['Driver awaiting approval','Shanice Grant','warning'],
     ['Shop & Deliver request','Marcia Thompson · St Elizabeth','info']]
    .map(function(r){ return '<button class="bell-item"><span class="bell-dot"'
      + (r[2] ? ' data-tone="' + r[2] + '"' : '') + '></span><span class="bell-txt">'
      + '<b>' + r[0] + '</b><span class="bell-sub">' + r[1] + '</span></span>'
      + '<svg class="ic" aria-hidden="true"><use href="#i-caret-right"/></svg></button>'; })
    .join('');
  document.getElementById('pr-bands').value = '2 = 600\\n5 = 900\\n10 = 1400\\n+ = 2200';
  document.getElementById('pr-preview').textContent =
    'Up to 2kg J$600 · up to 5kg J$900 · up to 10kg J$1,400 · heavier J$2,200';
  // Column labels for the phone card-fold, normally stamped by app.js.
  document.querySelectorAll('table').forEach(function(t){
    var hs = [].map.call(t.querySelectorAll('thead th'), function(h){ return h.textContent.trim(); });
    t.querySelectorAll('tbody tr').forEach(function(tr){
      [].forEach.call(tr.children, function(td, i){ if (hs[i]) td.setAttribute('data-label', hs[i]); });
    });
  });
</script></body>`);

  const p = path.join(ROOT, '__harness.html');
  await writeFile(p, html, 'utf8');
  return p;
}

// Served over HTTP, not file://: the self-hosted woff2 faces and app.js are
// both blocked by CORS under file://, which silently swaps every screenshot to
// a fallback font. Run `python3 -m http.server 8731 --directory admin_panel`
// first, or point SHOOT_BASE at wherever the panel is served.
const BASE = process.env.SHOOT_BASE || 'http://127.0.0.1:8731';

const shot = async (page, file) => {
  await page.screenshot({ path: file, fullPage: true, animations: 'disabled' });
  process.stdout.write(`  ${path.relative(OUT, file)}\n`);
};

(async () => {
  await rm(OUT, { recursive: true, force: true });
  await mkdir(OUT, { recursive: true });
  const harness = await buildHarness();
  const browser = await chromium.launch();

  try {
    for (const theme of ['light', 'dark']) {
      for (const vp of VIEWPORTS) {
        const ctx = await browser.newContext({
          viewport: { width: vp.width, height: vp.height },
          deviceScaleFactor: 1, reducedMotion: 'reduce',
        });
        const page = await ctx.newPage();
        const errors = [];
        page.on('console', m => m.type() === 'error' && errors.push(m.text()));
        page.on('pageerror', e => errors.push(String(e)));

        // Login first — it is a real page and needs no auth.
        await page.goto(`${BASE}/index.html`, { waitUntil: 'load' });
        await page.evaluate(t => document.documentElement.dataset.theme = t, theme);
        await page.waitForTimeout(250);
        await mkdir(path.join(OUT, `${theme}-${vp.name}`), { recursive: true });
        await shot(page, path.join(OUT, `${theme}-${vp.name}`, '00-login.png'));

        // Then the app shell, one screenshot per page.
        await page.goto(`${BASE}/${path.basename(harness)}`, { waitUntil: 'load' });
        await page.evaluate(t => document.documentElement.dataset.theme = t, theme);
        await page.waitForTimeout(250);
        for (const [i, name] of PAGES.entries()) {
          await page.evaluate((n) => {
            document.querySelectorAll('.page').forEach(p => p.classList.remove('active'));
            document.getElementById('page-' + n)?.classList.add('active');
            document.querySelectorAll('.ni').forEach(x => x.classList.remove('active'));
            document.querySelector(`.ni[data-page="${n}"]`)?.classList.add('active');
            const c = document.getElementById('tb-pg');
            if (c) c.textContent = document.querySelector('#page-' + n + ' .pg-title')?.textContent ?? n;
            window.scrollTo(0, 0);
          }, name);
          await page.waitForTimeout(120);
          await shot(page, path.join(OUT, `${theme}-${vp.name}`,
            `${String(i + 1).padStart(2, '0')}-${name}.png`));
        }

        // Overlays, on desktop only — they are the same box at every width
        // except for the bottom-sheet fold, which the phone run covers.
        if (vp.name !== 'tablet') {
          for (const [id, label] of [['modal-driver', 'modal-driver'],
                                     ['modal-merchant', 'modal-merchant'],
                                     ['modal-confirm', 'modal-confirm'],
                                     ['modal-wipe', 'modal-wipe']]) {
            await page.evaluate((m) => {
              document.querySelectorAll('.mbg').forEach(x => x.classList.remove('open'));
              document.getElementById(m)?.classList.add('open');
              const b = document.getElementById('cf-body');
              if (b) b.textContent = 'This permanently deletes driver Shanice Grant. This cannot be undone.';
              const ico = document.getElementById('cf-ico');
              if (ico && !ico.innerHTML.trim())
                ico.innerHTML = '<svg class="ic ic-lg" aria-hidden="true"><use href="#i-warning"/></svg>';
            }, id);
            await page.waitForTimeout(150);
            await shot(page, path.join(OUT, `${theme}-${vp.name}`, `9-${label}.png`));
          }
          await page.evaluate(() => {
            document.querySelectorAll('.mbg').forEach(x => x.classList.remove('open'));
            document.getElementById('spanel')?.classList.add('open');
            document.getElementById('sp-sub').textContent = 'Order SE-10428';
            document.getElementById('sp-title').textContent = 'Devon Campbell';
            document.getElementById('sp-body').innerHTML =
              '<div class="sp-hero"><div class="sp-avatar">DC</div>'
              + '<div><div class="sp-hero-name">Devon Campbell</div>'
              + '<div class="sp-lbl">876-555-0142</div></div></div>'
              + '<div class="sp-sec"><div class="sp-sec-title">Payment</div>'
              + '<div class="sp-row"><span class="sp-lbl">Total</span>'
              + '<span class="sp-val money">J$2,450</span></div>'
              + '<div class="sp-row"><span class="sp-lbl">Method</span>'
              + '<span class="sp-val">Card</span></div></div>'
              + '<div class="sp-sec"><div class="sp-sec-title">Status</div>'
              + '<div class="sf">'
              + ['Placed','Confirmed','Picked up','Delivered'].map(function(s,i){
                  return '<div class="sf-wrap"><div class="sf-dot '
                    + (i<3?'done':'current') + '"></div>'
                    + '<div class="sf-lbl">' + s + '</div></div>'
                    + (i<3?'<div class="sf-line done"></div>':''); }).join('')
              + '</div></div>';
          });
          await page.waitForTimeout(200);
          await shot(page, path.join(OUT, `${theme}-${vp.name}`, '9-side-panel.png'));
        }

        if (errors.length) {
          console.log(`\n  !! ${theme}/${vp.name} console errors:`);
          [...new Set(errors)].slice(0, 8).forEach(e => console.log(`     ${e}`));
        }
        await ctx.close();
      }
    }
  } finally {
    await browser.close();
    // KEEP_HARNESS=1 leaves __harness.html in place so the seeded DOM can be
    // opened and inspected directly. It is gitignored either way.
    if (!process.env.KEEP_HARNESS) await rm(harness, { force: true });
  }
  console.log(`\ndone → ${OUT}`);
})();
