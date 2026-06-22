/*
 * Mojito anonymous usage stats — Cloudflare Worker.
 *
 *   POST /ingest          one daily aggregate per install (no ID, IP discarded)
 *   GET  /api/stats.json  public marginal aggregates (the dataset *is* the page)
 *
 * Privacy posture:
 *  - We never read cf-connecting-ip / any client identifier. Nothing links one
 *    ping to another, across days or dimensions.
 *  - Stored data is per-UTC-day counters only. No raw events, no free text
 *    (GIF search terms are dropped on-device and never arrive here).
 *  - Published output is pure marginals + light long-tail trimming.
 */

const SITE_ORIGIN = "https://mojito.wells.ee";
const MAX_BODY = 16 * 1024;
// Mirrors maxEmojiPerPing in Sources/Mojito/Telemetry/TelemetryUploader.swift.
const MAX_EMOJI_PER_PING = 300;

// Allow-list of dimensions/features so a malformed or hostile payload can't
// invent arbitrary rows. This is the *ingest* set — everything the client may
// report. Keep it in sync with features() in
// Sources/Mojito/Telemetry/TelemetryUploader.swift (scripts/check_telemetry.py
// fails the build if they drift).
const FEATURE_KEYS = [
  "emoji", "symbols", "symbolsDoubleColon", "emoticons", "arrows", "gifSearch",
  "frequencyBoost", "launchAtLogin", "quickAccess", "menuBarIcon", "easterEggs",
  "triggersCustom", "emojiTriggerCustom", "symbolsTriggerCustom",
  "gifTriggerCustom", "quickAccessTriggerCustom",
];
// The curated subset published on the public page, in display order. Minutiae
// (arrows, symbolsDoubleColon) and the per-mode customization flags (collapsed
// into triggersCustom) are ingested but never published. Must be a subset of
// FEATURE_KEYS.
const PUBLIC_FEATURE_KEYS = [
  "emoji", "emoticons", "symbols", "gifSearch", "quickAccess",
  "triggersCustom", "frequencyBoost", "easterEggs", "launchAtLogin",
  "menuBarIcon",
];
const SKIN_TONES = new Set([
  "default", "light", "mediumLight", "medium", "mediumDark", "dark",
]);
const TOTAL_KINDS = ["emoji", "symbol", "gif", "emoticon", "quickAccess"];
// Quick Access favorites: 8 slots, so cap the per-ping favorite histogram.
const MAX_FAVORITES_PER_PING = 8;

const today = () => Math.floor(Date.now() / 86_400_000);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "POST" && url.pathname === "/ingest") {
      return ingest(request, env);
    }
    if (request.method === "GET" && url.pathname === "/api/stats.json") {
      return stats(env);
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors() });
    }
    return new Response("Not found", { status: 404 });
  },
};

// ---- ingest --------------------------------------------------------------

async function ingest(request, env) {
  // Reject oversized bodies before buffering when the client declares a
  // length; the post-read check still covers chunked uploads.
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_BODY) {
    return new Response("Too large", { status: 413 });
  }
  const raw = await request.text();
  if (raw.length > MAX_BODY) return new Response("Too large", { status: 413 });

  let body;
  try { body = JSON.parse(raw); } catch { return new Response("Bad JSON", { status: 400 }); }
  if (!body || body.v !== 1) return new Response("Bad schema", { status: 400 });

  const day = today();
  const stmts = [];

  // Daily-active ping (the active-user signal — one per install per day).
  stmts.push(totalStmt(env, day, "active", 1));

  // Marginal dimensions.
  pushDim(stmts, env, day, "app", cleanVersion(body.app));
  pushDim(stmts, env, day, "os", cleanInt(body.os));
  pushDim(stmts, env, day, "arch", body.arch === "arm64" || body.arch === "x86_64" ? body.arch : null);
  pushDim(stmts, env, day, "lang", cleanLang(body.lang));
  pushDim(stmts, env, day, "skinTone", SKIN_TONES.has(body.skinTone) ? body.skinTone : null);

  // Feature adoption.
  const features = body.features && typeof body.features === "object" ? body.features : {};
  for (const key of FEATURE_KEYS) {
    if (key in features) {
      stmts.push(
        env.DB.prepare(
          `INSERT INTO feature_daily (day, feature, enabled, total) VALUES (?, ?, ?, 1)
           ON CONFLICT(day, feature) DO UPDATE SET enabled = enabled + excluded.enabled, total = total + 1`
        ).bind(day, key, features[key] ? 1 : 0)
      );
    }
  }

  // Insertion totals (daily deltas).
  const totals = body.totals && typeof body.totals === "object" ? body.totals : {};
  for (const kind of TOTAL_KINDS) {
    const n = clampCount(totals[kind], 100_000);
    if (n > 0) stmts.push(totalStmt(env, day, kind, n));
  }

  // Quick Access daily-active: one tick per ping that used the pill at all
  // (the QA analogue of the `active` signal).
  if (clampCount(totals.quickAccess, 100_000) > 0) {
    stmts.push(totalStmt(env, day, "quickAccessActive", 1));
  }

  // Favorites pinned (0–8) as a marginal distribution. Recorded even at 0 so
  // the adoption rate has the full reporting population as its denominator.
  pushDim(stmts, env, day, "favorites", cleanFavCount(body.favoritesCount));

  // Top-favorites histogram — charset-validated, capped at the slot count.
  const favorites = Array.isArray(body.favorites) ? body.favorites : [];
  let favKept = 0;
  for (const hexcode of favorites) {
    if (favKept >= MAX_FAVORITES_PER_PING) break;
    if (typeof hexcode !== "string" || !/^[0-9A-Fa-f-]{1,48}$/.test(hexcode)) continue;
    favKept++;
    stmts.push(
      env.DB.prepare(
        `INSERT INTO favorite_daily (day, hexcode, count) VALUES (?, ?, 1)
         ON CONFLICT(day, hexcode) DO UPDATE SET count = count + 1`
      ).bind(day, hexcode.toUpperCase())
    );
  }

  // Easter-egg discoveries — a bare integer that feeds the community counter.
  const eggs = clampCount(body.eggs, 100);
  if (eggs > 0) {
    stmts.push(totalStmt(env, day, "eggs", eggs));
    stmts.push(
      env.DB.prepare(
        `INSERT INTO meta (key, value) VALUES ('community_eggs', ?)
         ON CONFLICT(key) DO UPDATE SET value = value + excluded.value`
      ).bind(eggs)
    );
  }

  // Per-emoji histogram (capped + charset-validated; bounded count per ping).
  const emoji = body.emoji && typeof body.emoji === "object" ? body.emoji : {};
  let kept = 0;
  for (const [hexcode, count] of Object.entries(emoji)) {
    if (kept >= MAX_EMOJI_PER_PING) break;
    if (!/^[0-9A-Fa-f-]{1,48}$/.test(hexcode)) continue;
    const n = clampCount(count, 1000);
    if (n <= 0) continue;
    kept++;
    stmts.push(
      env.DB.prepare(
        `INSERT INTO emoji_daily (day, hexcode, count) VALUES (?, ?, ?)
         ON CONFLICT(day, hexcode) DO UPDATE SET count = count + excluded.count`
      ).bind(day, hexcode.toUpperCase(), n)
    );
  }

  // D1 caps batch size; chunk to stay well under it.
  try {
    for (let i = 0; i < stmts.length; i += 50) {
      await env.DB.batch(stmts.slice(i, i + 50));
    }
  } catch (e) {
    return new Response("Store error", { status: 500 });
  }
  return new Response(null, { status: 204 });
}

function totalStmt(env, day, kind, n) {
  return env.DB.prepare(
    `INSERT INTO totals_daily (day, kind, count) VALUES (?, ?, ?)
     ON CONFLICT(day, kind) DO UPDATE SET count = count + excluded.count`
  ).bind(day, kind, n);
}

function pushDim(stmts, env, day, dim, value) {
  if (value == null || value === "") return;
  stmts.push(
    env.DB.prepare(
      `INSERT INTO dim_daily (day, dim, value, count) VALUES (?, ?, ?, 1)
       ON CONFLICT(day, dim, value) DO UPDATE SET count = count + 1`
    ).bind(day, dim, value)
  );
}

// ---- stats ---------------------------------------------------------------

async function stats(env) {
  const day = today();
  const win = day - 29; // trailing 30 days for "current population" views
  const activeLo = day - 7; // headline avg over the last 7 *complete* UTC days

  const [emoji, os, arch, lang, app, skin, features, totals, active30, active7,
         eggs, qaActive7, favorites, topFav] =
    await Promise.all([
      env.DB.prepare(
        `SELECT hexcode, SUM(count) c FROM emoji_daily WHERE day >= ?
         GROUP BY hexcode ORDER BY c DESC LIMIT 50`
      ).bind(win).all(),
      dim(env, "os", win),
      dim(env, "arch", win),
      dim(env, "lang", win),
      dim(env, "app", win),
      dim(env, "skinTone", win),
      env.DB.prepare(
        `SELECT feature, SUM(enabled) e, SUM(total) t FROM feature_daily
         WHERE day >= ? GROUP BY feature`
      ).bind(win).all(),
      env.DB.prepare(`SELECT kind, SUM(count) c FROM totals_daily GROUP BY kind`).all(),
      env.DB.prepare(
        `SELECT COALESCE(SUM(count), 0) c, COUNT(DISTINCT day) d
         FROM totals_daily WHERE kind = 'active' AND day >= ?`
      ).bind(win).all(),
      // Headline mean excludes the in-progress UTC day so it doesn't sag and
      // climb through the day; it then settles once per UTC day.
      env.DB.prepare(
        `SELECT COALESCE(SUM(count), 0) c, COUNT(DISTINCT day) d
         FROM totals_daily WHERE kind = 'active' AND day >= ? AND day < ?`
      ).bind(activeLo, day).all(),
      env.DB.prepare(`SELECT value FROM meta WHERE key = 'community_eggs'`).all(),
      // Quick Access daily-active, same 7-complete-day window as avgDailyActive.
      env.DB.prepare(
        `SELECT COALESCE(SUM(count), 0) c, COUNT(DISTINCT day) d
         FROM totals_daily WHERE kind = 'quickAccessActive' AND day >= ? AND day < ?`
      ).bind(activeLo, day).all(),
      dim(env, "favorites", win),
      env.DB.prepare(
        `SELECT hexcode, SUM(count) c FROM favorite_daily WHERE day >= ?
         GROUP BY hexcode ORDER BY c DESC LIMIT 20`
      ).bind(win).all(),
    ]);

  const totalsMap = {};
  for (const r of totals.results) totalsMap[r.kind] = r.c;

  // Curated, fixed-order feature list — only keys in PUBLIC_FEATURE_KEYS that
  // have actually been reported. Drops minutiae + the raw per-mode flags, and
  // keeps the order stable day to day (no pct re-sorting).
  const featMap = {};
  for (const r of features.results) featMap[r.feature] = { e: r.e, t: r.t };
  const featureList = PUBLIC_FEATURE_KEYS
    .filter((k) => featMap[k] && featMap[k].t > 0)
    .map((k) => ({ feature: k, enabled: featMap[k].e, total: featMap[k].t,
                   pct: Math.round((featMap[k].e / featMap[k].t) * 100) }));

  // macsSharingStats is 30-day person-days (kept for compat); avgDailyActive is
  // the headline per-day mean over the last 7 complete UTC days.
  const activeTotal = active30.results[0]?.c || 0;
  const a7Total = active7.results[0]?.c || 0;
  const a7Days = active7.results[0]?.d || 0;
  const avgDailyActive = a7Days ? Math.round(a7Total / a7Days) : 0;

  // Quick Access: per-day mean of installs that used the pill, same window.
  const qaTotal = qaActive7.results[0]?.c || 0;
  const qaDays = qaActive7.results[0]?.d || 0;
  const avgQuickAccessActive = qaDays ? Math.round(qaTotal / qaDays) : 0;

  // Favorites adoption: share of reporting installs that pinned ≥1 favorite.
  let favWith = 0, favAll = 0;
  for (const r of favorites) {
    favAll += r.count;
    if (Number(r.value) > 0) favWith += r.count;
  }
  const favoritesPinnedPct = favAll ? Math.round((favWith / favAll) * 100) : 0;

  const payload = {
    generatedAt: new Date().toISOString(),
    window: { days: 30 },
    activeWindow: { days: 7 },
    macsSharingStats: activeTotal,
    avgDailyActive,
    avgQuickAccessActive,
    favoritesPinnedPct,
    totals: {
      emoji: totalsMap.emoji || 0,
      symbol: totalsMap.symbol || 0,
      gif: totalsMap.gif || 0,
      emoticon: totalsMap.emoticon || 0,
      quickAccess: totalsMap.quickAccess || 0,
    },
    communityDiscoveries: eggs.results[0]?.value || 0,
    // Top inserted emoji, capped — no count floor, so it never blanks at low volume.
    topEmoji: emoji.results.map((r) => ({ hexcode: r.hexcode, count: r.c })).slice(0, 12),
    // Top pinned Quick Access favorites — same hexcode-only shape as topEmoji.
    topFavorites: topFav.results.map((r) => ({ hexcode: r.hexcode, count: r.c })).slice(0, 12),
    os: os, arch: arch, lang: lang, appVersion: app, skinTone: skin,
    features: featureList,
  };

  return new Response(JSON.stringify(payload, null, 2), {
    headers: { "Content-Type": "application/json; charset=utf-8",
               "Cache-Control": "public, max-age=900", ...cors() },
  });
}

async function dim(env, name, win) {
  const r = await env.DB.prepare(
    `SELECT value, SUM(count) c FROM dim_daily WHERE dim = ? AND day >= ?
     GROUP BY value ORDER BY c DESC`
  ).bind(name, win).all();
  return r.results.map((row) => ({ value: row.value, count: row.c }));
}

// ---- helpers -------------------------------------------------------------

function cors() {
  // The stats payload is fully public data, so it's readable from anywhere.
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
}

function clampCount(v, max) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(Math.floor(n), max);
}

function cleanInt(v) {
  const s = String(v ?? "");
  return /^[0-9]{1,3}$/.test(s) ? s : null;
}

// Favorites-pinned count: an integer 0–8 (the Quick Access slot count). Stored
// as a string dimension value; out-of-range or non-integer → dropped.
function cleanFavCount(v) {
  const n = Number(v);
  if (!Number.isInteger(n) || n < 0 || n > MAX_FAVORITES_PER_PING) return null;
  return String(n);
}

function cleanLang(v) {
  const s = String(v ?? "").toLowerCase();
  return /^[a-z]{2,3}$/.test(s) ? s : null;
}

function cleanVersion(v) {
  const s = String(v ?? "");
  return /^[0-9]{1,3}(\.[0-9]{1,3}){0,3}$/.test(s) ? s : null;
}
