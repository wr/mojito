#!/usr/bin/env node
// Render a 1200×630 Open Graph card for each guide page into og/<slug>.png.
//
//   node scripts/og-images.mjs            # all guides
//   node scripts/og-images.mjs em-dash-mac degree-symbol-mac
//
// The headline is read from each page's <h1>, so cards stay in sync with the
// copy; the glyph and the keys/shortcode chip come from CARDS below. Uses the
// puppeteer-core + chrome-launcher that lighthouse already installs (no new
// deps). Run scripts/checks/images.sh afterwards to compress the PNGs.

import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const require = createRequire(join(ROOT, 'package.json'));
const chromeLauncher = require('chrome-launcher');
const puppeteer = require('puppeteer-core');

// glyph: the big character on the right. keys: keycaps under the headline
// (rendered as a chord). chip: a typed shortcode instead of keys.
const CARDS = {
  'em-dash-mac':                     { glyph: '—', keys: ['⇧', '⌥', '-'] },
  'degree-symbol-mac':               { glyph: '°', keys: ['⇧', '⌥', '8'] },
  'check-mark-mac':                  { glyph: '✓', chip: '::check_mark' },
  'currency-symbols-mac':            { glyph: '€', small: '£ ¥ ¢', keys: ['⇧', '⌥', '2'] },
  'math-symbols-mac':                { glyph: 'π', small: '≠ ± √ ∞', keys: ['⌥', 'P'] },
  'copyright-trademark-symbols-mac': { glyph: '©', small: '™ ®', keys: ['⌥', 'G'] },
  'mac-key-symbols':                 { glyph: '⌘', small: '⌥ ⇧ ⌃', chip: '::cmd' },
  'how-to-type-emoji-on-mac':        { glyph: '😀', keys: ['fn', 'E'] },
  'emoji-shortcuts-mac':             { glyph: '🚀', keys: ['⌃', '⌘', 'Space'] },
  'emoji-shortcodes':                { glyph: '🎉', chip: ':tada:' },
  'mac-emoji-picker':                { glyph: '☕', chip: ':coffee:' },
  'emoji-picker-not-working-mac':    { glyph: '🛠️', keys: ['fn', 'E'] },
  'best-emoji-app-for-mac':          { glyph: '🏆', chip: ':trophy:' },
  'how-to-send-gifs-on-mac':         { glyph: 'GIF', chip: ':::party' },
  'tenor-gif-keyboard-mac':          { glyph: 'GIF', chip: ':::party' },
  'guides':                          { glyph: '🍹', small: '° — ⌘ 🎉', title: 'Typing emoji, symbols and GIFs on a Mac' },
};

const esc = (s) => s.replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function h1Of(slug) {
  const html = readFileSync(join(ROOT, slug, 'index.html'), 'utf8');
  const m = html.match(/<h1[^>]*>([\s\S]*?)<\/h1>/);
  if (!m) return slug;
  return m[1]
    .replace(/<[^>]+>/g, '')
    .replace(/&nbsp;/g, '\u00a0')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(Number(d)))
    .replace(/&amp;/g, '&')
    .trim();
}

function cardHTML(card, title, iconURL) {
  const keys = card.keys
    ? `<div class="keys">${card.keys.map((k) => `<span class="key${k.length > 2 ? ' wide' : ''}">${esc(k)}</span>`).join('')}</div>`
    : card.chip ? `<div class="keys"><span class="chip">${esc(card.chip)}</span></div>` : '';
  const glyphClass = /\p{Extended_Pictographic}/u.test(card.glyph) ? 'glyph emoji' : card.glyph.length > 2 ? 'glyph word' : 'glyph';
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  * { box-sizing: border-box; margin: 0; }
  body {
    width: 1200px; height: 630px; overflow: hidden;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Display", system-ui, sans-serif;
    color: #1d1d1f;
    background:
      radial-gradient(90% 120% at 0% 0%, #cfe6dc 0%, transparent 60%),
      radial-gradient(80% 110% at 100% 100%, #c9d6f0 0%, transparent 62%),
      #e9edf2;
    display: grid; grid-template-columns: 1fr 380px; gap: 56px; align-items: center;
    padding: 64px 72px;
  }
  .left { display: flex; flex-direction: column; gap: 34px; }
  h1 { font-size: ${title.length > 44 ? 58 : 66}px; line-height: 1.05; letter-spacing: -0.03em; font-weight: 750; }
  .keys { display: flex; gap: 14px; align-items: center; }
  .key, .chip {
    min-width: 76px; height: 76px; padding: 0 18px; border-radius: 16px;
    display: inline-grid; place-items: center;
    background: #fff; border: 1.5px solid rgba(0,0,0,.12); box-shadow: 0 4px 0 rgba(0,0,0,.10);
    font-size: 36px; font-weight: 500;
  }
  .key.wide { font-size: 28px; }
  .chip { font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: 34px; color: #176e41; }
  .brand { display: flex; gap: 14px; align-items: center; font-size: 26px; font-weight: 600; color: rgba(0,0,0,.6); }
  .brand img { width: 48px; height: 48px; }
  .tile {
    width: 380px; height: 380px; border-radius: 64px; background: #fff;
    box-shadow: 0 2px 6px rgba(0,0,0,.06), 0 24px 60px rgba(0,0,0,.14);
    display: grid; place-items: center; position: relative;
  }
  .glyph { font-size: 230px; line-height: 1; font-weight: 400; }
  .glyph.emoji { font-size: 200px; }
  .glyph.word { font-size: 120px; font-weight: 800; letter-spacing: -0.02em; color: #1e8c54; }
  .small { position: absolute; bottom: 30px; font-size: 40px; color: rgba(0,0,0,.45); letter-spacing: 0.08em; }
  </style></head><body>
  <div class="left">
    <h1>${esc(title)}</h1>
    ${keys}
    <div class="brand"><img src="${iconURL}" alt="">Mojito · mojito.wells.ee</div>
  </div>
  <div class="tile"><span class="${glyphClass}">${esc(card.glyph)}</span>${card.small ? `<span class="small">${esc(card.small)}</span>` : ''}</div>
  </body></html>`;
}

const slugs = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(CARDS);
const icon = 'data:image/png;base64,' + readFileSync(join(ROOT, 'app-icon-128.png')).toString('base64');
mkdirSync(join(ROOT, 'og'), { recursive: true });

const chrome = await chromeLauncher.launch({ chromeFlags: ['--headless=new', '--hide-scrollbars'] });
const browser = await puppeteer.connect({ browserURL: `http://127.0.0.1:${chrome.port}` });
try {
  const page = await browser.newPage();
  await page.setViewport({ width: 1200, height: 630, deviceScaleFactor: 1 });
  for (const slug of slugs) {
    const card = CARDS[slug];
    if (!card) { console.error(`no card for ${slug}`); process.exitCode = 1; continue; }
    const title = card.title || h1Of(slug);
    await page.setContent(cardHTML(card, title, icon), { waitUntil: 'load' });
    const out = join(ROOT, 'og', `${slug}.png`);
    writeFileSync(out, await page.screenshot({ type: 'png' }));
    console.log(`og/${slug}.png  ${title}`);
  }
} finally {
  await browser.disconnect();
  await chrome.kill();
}
