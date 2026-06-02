/*
 * Mojito anonymous usage stats — Cloudflare Worker.
 *
 *   POST /ingest          one daily aggregate per install (no ID, IP discarded)
 *   GET  /api/stats.json  public marginal aggregates (the dataset *is* the page)
 *
 * Privacy posture (see W-342):
 *  - We never read cf-connecting-ip / any client identifier. Nothing links one
 *    ping to another, across days or dimensions.
 *  - Stored data is per-UTC-day counters only. No raw events, no free text
 *    (GIF search terms are dropped on-device and never arrive here).
 *  - Published output is pure marginals + light long-tail trimming.
 */

const SITE_ORIGIN = "https://mojito.wells.ee";
const MAX_BODY = 16 * 1024;

// Allow-list of dimensions/features so a malformed or hostile payload can't
// invent arbitrary rows.
const FEATURE_KEYS = [
  "symbols", "symbolsDoubleColon", "emoticons", "arrows", "gifSearch",
  "frequencyBoost", "launchAtLogin", "quickAccess", "menuBarIcon",
];
const SKIN_TONES = new Set([
  "default", "light", "mediumLight", "medium", "mediumDark", "dark",
]);
const TOTAL_KINDS = ["emoji", "symbol", "gif", "emoticon"];

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
  pushDim(stmts, env, day, "os", cleanInt(body.os, 2));
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
    if (kept >= 300) break;
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

  const [emoji, os, arch, lang, app, skin, features, totals, active30, eggs] =
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
        `SELECT SUM(count) c FROM totals_daily WHERE kind = 'active' AND day >= ?`
      ).bind(win).all(),
      env.DB.prepare(`SELECT value FROM meta WHERE key = 'community_eggs'`).all(),
    ]);

  const totalsMap = {};
  for (const r of totals.results) totalsMap[r.kind] = r.c;

  const featureList = features.results
    .map((r) => ({ feature: r.feature, enabled: r.e, total: r.t,
                   pct: r.t ? Math.round((r.e / r.t) * 100) : 0 }))
    .sort((a, b) => b.pct - a.pct);

  const payload = {
    generatedAt: new Date().toISOString(),
    window: { days: 30 },
    macsSharingStats: active30.results[0]?.c || 0,
    totals: {
      emoji: totalsMap.emoji || 0,
      symbol: totalsMap.symbol || 0,
      gif: totalsMap.gif || 0,
      emoticon: totalsMap.emoticon || 0,
    },
    communityDiscoveries: eggs.results[0]?.value || 0,
    topEmoji: emoji.results.map((r) => ({ hexcode: r.hexcode, count: r.c }))
      .filter((r) => r.count >= 5), // light long-tail trim (cosmetic, not privacy)
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
  return {
    "Access-Control-Allow-Origin": SITE_ORIGIN,
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Max-Age": "86400",
  };
}

function clampCount(v, max) {
  const n = Number(v);
  if (!Number.isFinite(n) || n < 0) return 0;
  return Math.min(Math.floor(n), max);
}

function cleanInt(v, maxLen) {
  const s = String(v ?? "");
  return /^[0-9]{1,3}$/.test(s) && s.length <= maxLen + 1 ? s : null;
}

function cleanLang(v) {
  const s = String(v ?? "").toLowerCase();
  return /^[a-z]{2,3}$/.test(s) ? s : null;
}

function cleanVersion(v) {
  const s = String(v ?? "");
  return /^[0-9]{1,3}(\.[0-9]{1,3}){0,3}$/.test(s) ? s : null;
}
