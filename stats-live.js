/*
 * Renders the live public dataset onto the page. The page ships with sample
 * markup so it looks right before any JS runs and as a fallback if the API is
 * unreachable; on a successful fetch the live data always wins — even when
 * it's all zeros (pre-launch), in which case empty sections show a tidy
 * placeholder rather than leftover sample. Endpoints are tried in order so it
 * works in production (custom domain) and from a local preview (workers.dev).
 */
(function () {
  var ENDPOINTS = [
    "https://stats.mojito.wells.ee/api/stats.json",
    "https://mojito-stats.wells-riley.workers.dev/api/stats.json",
  ];

  var LANG = { en: "English", de: "German", ja: "Japanese", fr: "French",
    es: "Spanish", zh: "Chinese", ko: "Korean", pt: "Portuguese", it: "Italian",
    ru: "Russian", nl: "Dutch", pl: "Polish", hi: "Hindi", ar: "Arabic",
    fa: "Persian", he: "Hebrew", und: "Other" };
  var FEATURE = { symbols: "Symbols", symbolsDoubleColon: "Require ::",
    emoticons: "Emoticons", arrows: "Arrow conversion", gifSearch: "GIF search",
    frequencyBoost: "Frequency boost", launchAtLogin: "Launch at login",
    quickAccess: "Quick Access", menuBarIcon: "Menu-bar icon" };
  var TONE_ORDER = ["default", "light", "mediumLight", "medium", "mediumDark", "dark"];
  var TONE_COLOR = { default: "#ffce4a", light: "#f3d3b0", mediumLight: "#e7b78c",
    medium: "#c68a52", mediumDark: "#9c6438", dark: "#5e4129" };
  var TONE_NAME = { default: "Default", light: "Light", mediumLight: "Med-light",
    medium: "Medium", mediumDark: "Med-dark", dark: "Dark" };
  var TONE_HAND = { default: "🖖", light: "🖖🏻", mediumLight: "🖖🏼",
    medium: "🖖🏽", mediumDark: "🖖🏾", dark: "🖖🏿" };

  // i18n: labels are localized through window.MojitoI18n (i18n.js), with the
  // English tables above as fallbacks. The worker returns only opaque codes.
  var I18N = window.MojitoI18n;
  function t(k, f) { return (I18N && I18N.t) ? I18N.t(k, f) : f; }
  function loc() { return (I18N && I18N.locale) ? I18N.locale : "en"; }
  var lastData = null;

  fetchFirst(0);
  // Re-render with localized labels once i18n is ready and whenever the visitor
  // switches languages (the fetched data is cached in lastData).
  if (I18N && I18N.onChange) I18N.onChange(render);

  function fetchFirst(i) {
    if (i >= ENDPOINTS.length) return; // all endpoints failed: keep the sample
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, 4000);
    fetch(ENDPOINTS[i], { signal: ctrl.signal })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (data) { clearTimeout(timer); handle(data); })
      .catch(function () { clearTimeout(timer); fetchFirst(i + 1); });
  }

  function handle(d) {
    if (!d) return;
    window.__statsLiveTookOver = true; // stop the sample count-up animations
    lastData = d;                      // live data wins, even when it's all zeros
    whenReady(render);
  }
  function render() { if (lastData) applyLive(lastData); }
  function whenReady(fn) {
    if (I18N && I18N.ready && I18N.ready.then) I18N.ready.then(fn); else fn();
  }

  // ---- render ----

  function applyLive(d) {
    setText("updated", t("stats.lastUpdate", "last update {date}").replace("{date}", fmtDate(d.generatedAt)));

    num("bn-macs", d.avgDailyActive != null
      ? d.avgDailyActive
      : Math.round((d.macsSharingStats || 0) / ((d.window && d.window.days) || 30)));
    num("bn-emoji", d.totals.emoji);
    num("bn-gif", d.totals.gif);
    num("bn-emoticon", d.totals.emoticon);
    num("egg-num", d.communityDiscoveries);

    renderEmoji(d.topEmoji || []);
    renderMix(d.totals);
    renderDist("bars-os", d.os, function (v) { return "macOS " + v; });
    renderDist("bars-arch", d.arch, function (v) {
      return v === "arm64" ? "Apple Silicon" : v === "x86_64" ? "Intel" : v;
    });
    renderDist("bars-app", d.appVersion, function (v) { return v; });
    renderDist("bars-lang", d.lang, function (v) { return t("stats.lang." + v, LANG[v] || v.toUpperCase()); });
    renderTones("tones", d.skinTone || []);
    renderFeatures("bars-features", d.features || []);
  }

  function renderEmoji(top) {
    var el = byId("emoji-rows");
    if (!el) return;
    if (!top.length) { el.innerHTML = note(t("stats.empty.emoji", "No emoji inserted yet.")); return; }
    var max = top[0].count || 1;
    el.innerHTML = top.map(function (e, i) {
      var pct = Math.round((e.count / max) * 100);
      return '<div class="erow"><span class="erank">' + (i + 1) +
        '</span><span class="eglyph" aria-hidden="true">' + hexToEmoji(e.hexcode) +
        '</span><span class="ecode">' + shortcode(e.hexcode) +
        '</span><span class="bar-track"><span class="bar-fill" style="width:' + pct +
        '%"></span></span><span class="ecount">' + e.count.toLocaleString(loc()) +
        "</span></div>";
    }).join("");
  }

  function renderMix(tot) {
    var sum = tot.emoji + tot.symbol + tot.gif + tot.emoticon;
    var bar = byId("mix-bar");
    var legend = byId("mix-legend");
    if (!sum) {
      if (bar) bar.querySelectorAll(".mixseg").forEach(function (s) { s.style.width = "0%"; });
      if (legend) legend.innerHTML = note(t("stats.empty.mix", "No insertions yet."));
      return;
    }
    var seg = { emoji: tot.emoji, emoticon: tot.emoticon, symbol: tot.symbol, gif: tot.gif };
    if (bar) {
      ["emoji", "emoticon", "symbol", "gif"].forEach(function (k) {
        var s = bar.querySelector(".mixseg." + k);
        if (s) s.style.width = (seg[k] / sum) * 100 + "%";
      });
    }
    if (legend) {
      var rows = [["emoji", "Emoji"], ["emoticon", "Emoticons"],
        ["symbol", "Symbols"], ["gif", "GIFs"]];
      legend.innerHTML = rows.map(function (r) {
        var pct = Math.round((seg[r[0]] / sum) * 100);
        return '<span class="mix-item"><span class="mix-swatch" style="background:var(--mix-' +
          r[0] + ')"></span><b>' + t("stats.mix." + r[0], r[1]) + "</b>&nbsp;<span>" + pct + "% · " +
          compact(seg[r[0]]) + "</span></span>";
      }).join("");
    }
  }

  function renderDist(id, arr, labelFn) {
    var el = byId(id);
    if (!el || !arr) return;
    if (!arr.length) { el.innerHTML = note(t("stats.empty.data", "No data yet.")); return; }
    var sum = arr.reduce(function (a, b) { return a + b.count; }, 0) || 1;
    el.innerHTML = arr.map(function (r) {
      var pct = Math.round((r.count / sum) * 100);
      return barRow(labelFn(r.value), pct, pct + "%");
    }).join("");
  }

  function renderFeatures(id, features) {
    var el = byId(id);
    if (!el) return;
    if (!features.length) { el.innerHTML = note(t("stats.empty.data", "No data yet.")); return; }
    el.innerHTML = features.map(function (f) {
      return '<div class="feat-tile"><div class="feat-gauge" style="--p:' + f.pct +
        '"></div><span class="feat-pct">' + f.pct + '%</span><span class="feat-name">' +
        t("stats.feature." + f.feature, FEATURE[f.feature] || f.feature) + "</span></div>";
    }).join("");
  }

  function renderTones(id, arr) {
    var el = byId(id);
    if (!el) return;
    if (!arr.length) { el.innerHTML = note(t("stats.empty.data", "No data yet.")); return; }
    var sum = arr.reduce(function (a, b) { return a + b.count; }, 0) || 1;
    var by = {};
    arr.forEach(function (r) { by[r.value] = r.count; });
    el.innerHTML = TONE_ORDER.filter(function (v) { return by[v]; }).map(function (v) {
      var pct = Math.round((by[v] / sum) * 100);
      return '<div class="tone"><span class="tone-hand" aria-hidden="true">' + TONE_HAND[v] +
        '</span><span class="tone-pct">' + pct +
        '%</span><span class="tone-name">' + t("stats.tone." + v, TONE_NAME[v]) + "</span></div>";
    }).join("");
  }

  // ---- helpers ----

  function note(t) {
    return '<p style="color:var(--text-soft);font-size:14px;margin:16px 0 0;">' + t + "</p>";
  }

  function barRow(label, pct, val) {
    return '<div class="bar"><span class="bar-label">' + label +
      '</span><span class="bar-track"><span class="bar-fill" style="width:' + pct +
      '%"></span></span><span class="bar-val">' + val + "</span></div>";
  }

  function hexToEmoji(hex) {
    try {
      return String.fromCodePoint.apply(null, hex.split("-").map(function (h) {
        return parseInt(h, 16);
      }));
    } catch (e) { return "·"; }
  }

  // The worker returns only hexcodes; map to the canonical :shortcode: from the
  // baked-in table (emoji-codes.js). Fall back to the bare hexcode if absent.
  function shortcode(hex) {
    var h = hex.toLowerCase();
    var codes = window.MojitoEmojiCodes;
    return (codes && codes[h]) ? ":" + codes[h] + ":" : h;
  }

  function compact(n) {
    if (n >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
    if (n >= 1e4) return Math.round(n / 1000) + "K";
    return n.toLocaleString(loc());
  }

  function num(id, n) { var el = byId(id); if (el) el.textContent = compact(n); }
  function setText(id, t) { var el = byId(id); if (el) el.textContent = t; }
  function byId(id) { return document.getElementById(id); }
  function fmtDate(iso) {
    try {
      return new Date(iso).toLocaleDateString(loc(),
        { year: "numeric", month: "long", day: "numeric" });
    } catch (e) { return ""; }
  }
})();
