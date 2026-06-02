/*
 * Progressive enhancement: replace the baked-in sample data with the live
 * public dataset when it's available and non-empty. If the fetch fails or the
 * dataset is still empty (pre-launch), the page keeps its sample data and the
 * "Sample data · preview" pill. The endpoints are tried in order so the page
 * works both in production (custom domain) and from a local preview (the
 * workers.dev fallback resolves when the custom domain hasn't propagated).
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

  fetchFirst(0);

  function fetchFirst(i) {
    if (i >= ENDPOINTS.length) return;
    var ctrl = new AbortController();
    var timer = setTimeout(function () { ctrl.abort(); }, 4000);
    fetch(ENDPOINTS[i], { signal: ctrl.signal })
      .then(function (r) { return r.ok ? r.json() : Promise.reject(r.status); })
      .then(function (data) { clearTimeout(timer); handle(data); })
      .catch(function () { clearTimeout(timer); fetchFirst(i + 1); });
  }

  function handle(d) {
    if (!d || !isPopulated(d)) return; // pre-launch: keep the sample
    window.__statsLiveTookOver = true;  // stop the sample count-up animations
    applyLive(d);
  }

  function isPopulated(d) {
    return (d.macsSharingStats > 0) ||
      (d.topEmoji && d.topEmoji.length > 0) ||
      (d.totals && d.totals.emoji > 0);
  }

  // ---- render ----

  function applyLive(d) {
    hide("pill-preview"); hide("pill-preview-sep");
    setText("updated", "Updated " + fmtDate(d.generatedAt));

    num("bn-macs", d.macsSharingStats);
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
    renderDist("bars-lang", d.lang, function (v) { return LANG[v] || v.toUpperCase(); });
    renderTones("tones", d.skinTone || []);
    renderFeatures("bars-features", d.features || []);
  }

  function renderEmoji(top) {
    var el = byId("emoji-rows");
    if (!el || !top.length) return;
    var max = top[0].count || 1;
    el.innerHTML = top.map(function (e, i) {
      var pct = Math.round((e.count / max) * 100);
      return '<div class="erow"><span class="erank">' + (i + 1) +
        '</span><span class="eglyph" aria-hidden="true">' + hexToEmoji(e.hexcode) +
        '</span><span class="ecode">' + e.hexcode.toLowerCase() +
        '</span><span class="bar-track"><span class="bar-fill" style="width:' + pct +
        '%"></span></span><span class="ecount">' + e.count.toLocaleString("en-US") +
        "</span></div>";
    }).join("");
  }

  function renderMix(t) {
    var sum = (t.emoji + t.symbol + t.gif + t.emoticon) || 1;
    var seg = { emoji: t.emoji, emoticon: t.emoticon, symbol: t.symbol, gif: t.gif };
    var bar = byId("mix-bar");
    if (bar) {
      ["emoji", "emoticon", "symbol", "gif"].forEach(function (k) {
        var s = bar.querySelector(".mixseg." + k);
        if (s) s.style.width = (seg[k] / sum) * 100 + "%";
      });
    }
    var legend = byId("mix-legend");
    if (legend) {
      var rows = [["emoji", "Emoji"], ["emoticon", "Emoticons"],
        ["symbol", "Symbols"], ["gif", "GIFs"]];
      legend.innerHTML = rows.map(function (r) {
        var pct = Math.round((seg[r[0]] / sum) * 100);
        return '<span class="mix-item"><span class="mix-swatch" style="background:var(--mix-' +
          r[0] + ')"></span><b>' + r[1] + "</b>&nbsp;<span>" + pct + "% · " +
          compact(seg[r[0]]) + "</span></span>";
      }).join("");
    }
  }

  function renderDist(id, arr, labelFn) {
    var el = byId(id);
    if (!el || !arr) return;
    var sum = arr.reduce(function (a, b) { return a + b.count; }, 0) || 1;
    el.innerHTML = arr.map(function (r) {
      var pct = Math.round((r.count / sum) * 100);
      return barRow(labelFn(r.value), pct, pct + "%");
    }).join("");
  }

  function renderFeatures(id, features) {
    var el = byId(id);
    if (!el) return;
    el.innerHTML = features.map(function (f) {
      return barRow(FEATURE[f.feature] || f.feature, f.pct, f.pct + "%");
    }).join("");
  }

  function renderTones(id, arr) {
    var el = byId(id);
    if (!el || !arr.length) return;
    var sum = arr.reduce(function (a, b) { return a + b.count; }, 0) || 1;
    var by = {};
    arr.forEach(function (r) { by[r.value] = r.count; });
    el.innerHTML = TONE_ORDER.filter(function (v) { return by[v]; }).map(function (v) {
      var pct = Math.round((by[v] / sum) * 100);
      return '<div class="tone"><span class="tone-dot" style="background:' + TONE_COLOR[v] +
        '" aria-hidden="true"></span><span class="tone-pct">' + pct +
        '%</span><span class="tone-name">' + TONE_NAME[v] + "</span></div>";
    }).join("");
  }

  // ---- helpers ----

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

  function compact(n) {
    if (n >= 1e6) return (n / 1e6).toFixed(1).replace(/\.0$/, "") + "M";
    if (n >= 1e4) return Math.round(n / 1000) + "K";
    return n.toLocaleString("en-US");
  }

  function num(id, n) { var el = byId(id); if (el) el.textContent = compact(n); }
  function setText(id, t) { var el = byId(id); if (el) el.textContent = t; }
  function hide(id) { var el = byId(id); if (el) el.style.display = "none"; }
  function byId(id) { return document.getElementById(id); }
  function fmtDate(iso) {
    try {
      return new Date(iso).toLocaleDateString("en-US",
        { year: "numeric", month: "long", day: "numeric" });
    } catch (e) { return ""; }
  }
})();
