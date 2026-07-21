/* Mojito site i18n — client-side string swap + nav language picker.
 *
 * English is the inline baseline in index.html (so crawlers and no-JS users
 * get real content). For any other locale we fetch i18n/<code>.json and swap
 * [data-i18n] / [data-i18n-html] / [data-i18n-attr] nodes. The picked locale
 * persists in localStorage and is reflected in ?lang= for shareable links.
 *
 * Public API on window.MojitoI18n:
 *   .locale            current BCP-47 code
 *   .rtl               boolean
 *   .ready             Promise resolved once the initial locale is applied
 *   .t(key, fallback)  lookup for strings that live in JS (picker.js scenes)
 *   .localeName(code)  native display name
 *   .onChange(cb)      subscribe to locale changes
 *   .setLocale(code)   programmatic switch (persists + updates URL)
 *
 * The hero demo subtree is forced dir="ltr" in the HTML so RTL locales flip
 * the page copy without breaking the mock-app layout or the picker caret math.
 */
(function () {
  "use strict";

  var LOCALES = [
    { code: "en",      flag: "🇺🇸", name: "English" },
    { code: "en-GB",   flag: "🇬🇧", name: "English (UK)" },
    { code: "de",      flag: "🇩🇪", name: "Deutsch" },
    { code: "es",      flag: "🇪🇸", name: "Español" },
    { code: "es-419",  flag: "🌎", name: "Español (Latinoamérica)" },
    { code: "fr",      flag: "🇫🇷", name: "Français" },
    { code: "it",      flag: "🇮🇹", name: "Italiano" },
    { code: "pt-BR",   flag: "🇧🇷", name: "Português (Brasil)" },
    { code: "ja",      flag: "🇯🇵", name: "日本語" },
    { code: "zh-Hans", flag: "🇨🇳", name: "简体中文" },
    { code: "zh-Hant", flag: "🇹🇼", name: "繁體中文" },
    { code: "ko",      flag: "🇰🇷", name: "한국어" },
    { code: "hi",      flag: "🇮🇳", name: "हिन्दी" },
    { code: "ru",      flag: "🇷🇺", name: "Русский" },
    { code: "pl",      flag: "🇵🇱", name: "Polski" },
    { code: "nl",      flag: "🇳🇱", name: "Nederlands" },
    { code: "ar",      flag: "🇸🇦", name: "العربية" },
    { code: "fa",      flag: "🇮🇷", name: "فارسی" },
    { code: "he",      flag: "🇮🇱", name: "עברית" }
  ];
  var RTL = { ar: 1, fa: 1, he: 1 };
  var STORAGE_KEY = "mojito.lang";
  var DICT_VERSION = "2"; // bump alongside i18n/*.json edits to bust caches

  var byCode = {};
  LOCALES.forEach(function (l) { byCode[l.code.toLowerCase()] = l.code; });

  // Map an arbitrary BCP-47 tag to one of our supported codes, or null.
  function resolveOne(tag) {
    if (!tag) return null;
    var t = String(tag).toLowerCase();
    if (byCode[t]) return byCode[t];
    var primary = t.split("-")[0];
    if (primary === "en") return t === "en-gb" ? "en-GB" : "en";
    if (primary === "es") return (t === "es" || t === "es-es") ? "es" : "es-419";
    if (primary === "pt") return "pt-BR";
    if (primary === "zh") {
      if (t.indexOf("hant") >= 0 || t.indexOf("tw") >= 0 ||
          t.indexOf("hk") >= 0 || t.indexOf("mo") >= 0) return "zh-Hant";
      return "zh-Hans";
    }
    for (var i = 0; i < LOCALES.length; i++) {
      if (LOCALES[i].code.toLowerCase().split("-")[0] === primary) return LOCALES[i].code;
    }
    return null;
  }

  function paramLang() {
    try { return new URLSearchParams(location.search).get("lang"); } catch (e) { return null; }
  }
  function storedLang() {
    try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }

  // Resolution order: ?lang= → localStorage → navigator languages → en.
  // `explicit` is true only when the choice came from the URL or a prior pick,
  // which is what lets us avoid rewriting the URL on plain auto-detect.
  function resolveLocale() {
    var p = paramLang();
    if (p) { var rp = resolveOne(p); if (rp) return { code: rp, explicit: true }; }
    var s = storedLang();
    if (s) { var rs = resolveOne(s); if (rs) return { code: rs, explicit: true }; }
    var navs = (navigator.languages && navigator.languages.length)
      ? navigator.languages : [navigator.language || "en"];
    for (var i = 0; i < navs.length; i++) {
      var r = resolveOne(navs[i]);
      if (r) return { code: r, explicit: false };
    }
    return { code: "en", explicit: false };
  }

  var initial = resolveLocale();
  var state = { locale: initial.code, rtl: !!RTL[initial.code] };

  // Set lang/dir synchronously (this script is parser-blocking in <head>), so
  // RTL locales don't flash an LTR layout before the dict loads.
  document.documentElement.lang = state.locale;
  document.documentElement.dir = state.rtl ? "rtl" : "ltr";

  var currentDict = null;       // active non-en dictionary, or null for en
  var dictCache = {};           // code → Promise<dict>
  var baseline = [];            // captured English DOM values, for restore
  var changeCbs = [];
  var readyResolve;
  var ready = new Promise(function (res) { readyResolve = res; });

  function t(key, fallback) {
    if (currentDict && currentDict[key] != null) return currentDict[key];
    return fallback != null ? fallback : key;
  }
  function localeName(code) {
    var l = byCode[String(code).toLowerCase()];
    if (!l) return code;
    for (var i = 0; i < LOCALES.length; i++) if (LOCALES[i].code === l) return LOCALES[i].name;
    return code;
  }

  function attrPairs(el) {
    return (el.getAttribute("data-i18n-attr") || "").split(";").map(function (p) {
      var idx = p.indexOf(":");
      if (idx < 0) return null;
      return { attr: p.slice(0, idx).trim(), key: p.slice(idx + 1).trim() };
    }).filter(Boolean);
  }

  function captureBaseline() {
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      baseline.push({ el: el, kind: "text", value: el.textContent });
    });
    document.querySelectorAll("[data-i18n-html]").forEach(function (el) {
      baseline.push({ el: el, kind: "html", value: el.innerHTML });
    });
    document.querySelectorAll("[data-i18n-attr]").forEach(function (el) {
      attrPairs(el).forEach(function (p) {
        baseline.push({ el: el, kind: "attr", name: p.attr, value: el.getAttribute(p.attr) });
      });
    });
  }

  function restoreBaseline() {
    baseline.forEach(function (b) {
      if (b.kind === "text") b.el.textContent = b.value;
      else if (b.kind === "html") b.el.innerHTML = b.value;
      else if (b.kind === "attr") { if (b.value != null) b.el.setAttribute(b.name, b.value); }
    });
  }

  function applyDict(dict) {
    document.querySelectorAll("[data-i18n]").forEach(function (el) {
      var k = el.getAttribute("data-i18n");
      if (dict[k] != null) el.textContent = dict[k];
    });
    document.querySelectorAll("[data-i18n-html]").forEach(function (el) {
      var k = el.getAttribute("data-i18n-html");
      if (dict[k] != null) el.innerHTML = dict[k];
    });
    document.querySelectorAll("[data-i18n-attr]").forEach(function (el) {
      attrPairs(el).forEach(function (p) {
        if (dict[p.key] != null) el.setAttribute(p.attr, dict[p.key]);
      });
    });
  }

  function loadDict(code) {
    if (dictCache[code]) return dictCache[code];
    var url = "i18n/" + code + ".json?v=" + DICT_VERSION;
    dictCache[code] = fetch(url).then(function (r) {
      if (!r.ok) throw new Error("dict " + code + " " + r.status);
      return r.json();
    });
    return dictCache[code];
  }

  // Apply a locale to the DOM. Does NOT touch localStorage/URL — callers that
  // represent an explicit user choice handle persistence separately.
  function applyLocale(code) {
    if (!byCode[code.toLowerCase()]) code = "en";
    state.locale = code;
    state.rtl = !!RTL[code];
    document.documentElement.lang = code;
    document.documentElement.dir = state.rtl ? "rtl" : "ltr";

    var done;
    if (code === "en") {
      currentDict = null;
      restoreBaseline();
      done = Promise.resolve();
    } else {
      done = loadDict(code).then(function (dict) {
        currentDict = dict;
        restoreBaseline();   // reset first so keys missing from a translation fall back to English
        applyDict(dict);
      }).catch(function () {
        currentDict = null;
        state.locale = "en";
        state.rtl = false;
        document.documentElement.lang = "en";
        document.documentElement.dir = "ltr";
        restoreBaseline();
      });
    }
    return done.then(function () {
      updatePickerButton();
      changeCbs.forEach(function (cb) { try { cb(state.locale); } catch (e) {} });
    });
  }

  function updateUrl(code) {
    try {
      var url = new URL(location.href);
      if (code === "en") url.searchParams.delete("lang");
      else url.searchParams.set("lang", code);
      history.replaceState(null, "", url);
    } catch (e) {}
  }

  // Explicit user pick: persist + reflect in URL.
  function setLocale(code) {
    var r = resolveOne(code) || "en";
    return applyLocale(r).then(function () {
      try { localStorage.setItem(STORAGE_KEY, r); } catch (e) {}
      updateUrl(r);
    });
  }

  /* ----- nav language picker ----------------------------------------- */

  var btn, menu, menuOpen = false, activeIdx = 0;

  function currentMeta() {
    for (var i = 0; i < LOCALES.length; i++) if (LOCALES[i].code === state.locale) return LOCALES[i];
    return LOCALES[0];
  }

  function updatePickerButton() {
    if (!btn) return;
    var m = currentMeta();
    btn.querySelector(".lang-btn-flag").textContent = m.flag;
    btn.setAttribute("title", m.name);
    menu.querySelectorAll('[role="option"]').forEach(function (opt) {
      opt.setAttribute("aria-selected", opt.getAttribute("data-code") === state.locale ? "true" : "false");
    });
  }

  // The menu is portaled to <body> (out of the backdrop-filtered .topbar so its
  // own backdrop-filter can actually blur the page), so position it under the
  // button by hand — aligning its inline-end edge to the button's.
  function positionMenu() {
    var r = btn.getBoundingClientRect();
    menu.style.top = (r.bottom + 8) + "px";
    if (document.documentElement.dir === "rtl") {
      menu.style.left = r.left + "px";
      menu.style.right = "auto";
    } else {
      menu.style.right = (window.innerWidth - r.right) + "px";
      menu.style.left = "auto";
    }
  }

  function openMenu() {
    if (menuOpen) return;
    menuOpen = true;
    positionMenu();
    menu.hidden = false;
    btn.setAttribute("aria-expanded", "true");
    var opts = menu.querySelectorAll('[role="option"]');
    for (var i = 0; i < opts.length; i++) {
      if (opts[i].getAttribute("data-code") === state.locale) { activeIdx = i; break; }
    }
    setActive(activeIdx);
    menu.focus();
  }
  function closeMenu(focusBtn) {
    if (!menuOpen) return;
    menuOpen = false;
    menu.hidden = true;
    btn.setAttribute("aria-expanded", "false");
    if (focusBtn) btn.focus();
  }
  function setActive(idx) {
    var opts = menu.querySelectorAll('[role="option"]');
    if (!opts.length) return;
    activeIdx = (idx + opts.length) % opts.length;
    for (var i = 0; i < opts.length; i++) opts[i].classList.toggle("is-active", i === activeIdx);
    var el = opts[activeIdx];
    menu.setAttribute("aria-activedescendant", el.id);
    el.scrollIntoView({ block: "nearest" });
  }

  function buildPicker() {
    var nav = document.querySelector(".nav-links");
    if (!nav) return;

    var wrap = document.createElement("div");
    wrap.className = "lang-picker";

    btn = document.createElement("button");
    btn.className = "lang-btn";
    btn.type = "button";
    btn.setAttribute("aria-haspopup", "listbox");
    btn.setAttribute("aria-expanded", "false");
    btn.setAttribute("aria-label", t("lang.aria.picker", "Language"));
    btn.innerHTML = '<span class="lang-btn-flag" aria-hidden="true"></span>' +
      '<svg class="lang-btn-caret" viewBox="0 0 10 6" width="10" height="6" aria-hidden="true">' +
      '<path fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round" ' +
      'stroke-linejoin="round" d="M1 1l4 4 4-4"/></svg>';

    menu = document.createElement("ul");
    menu.className = "lang-menu";
    menu.setAttribute("role", "listbox");
    menu.setAttribute("tabindex", "-1");
    menu.setAttribute("aria-label", t("lang.menu.title", "Choose language"));
    menu.hidden = true;
    LOCALES.forEach(function (l, i) {
      var li = document.createElement("li");
      li.className = "lang-option";
      li.id = "lang-opt-" + l.code;
      li.setAttribute("role", "option");
      li.setAttribute("data-code", l.code);
      li.setAttribute("aria-selected", l.code === state.locale ? "true" : "false");
      li.innerHTML = '<span class="lang-flag" aria-hidden="true">' + l.flag + "</span>" +
        '<span class="lang-name">' + l.name + "</span>";
      li.addEventListener("click", function () { setLocale(l.code); closeMenu(true); });
      li.addEventListener("mousemove", function () { setActive(i); });
      menu.appendChild(li);
    });

    btn.addEventListener("click", function (e) {
      e.stopPropagation();
      if (menuOpen) closeMenu(true); else openMenu();
    });
    btn.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown" || e.key === "Enter" || e.key === " ") {
        e.preventDefault(); openMenu();
      }
    });
    menu.addEventListener("keydown", function (e) {
      if (e.key === "ArrowDown") { e.preventDefault(); setActive(activeIdx + 1); }
      else if (e.key === "ArrowUp") { e.preventDefault(); setActive(activeIdx - 1); }
      else if (e.key === "Home") { e.preventDefault(); setActive(0); }
      else if (e.key === "End") { e.preventDefault(); setActive(LOCALES.length - 1); }
      else if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        var opt = menu.querySelectorAll('[role="option"]')[activeIdx];
        if (opt) { setLocale(opt.getAttribute("data-code")); closeMenu(true); }
      } else if (e.key === "Escape") { e.preventDefault(); closeMenu(true); }
      else if (e.key === "Tab") { closeMenu(false); }
    });
    document.addEventListener("click", function (e) {
      if (menuOpen && !wrap.contains(e.target) && !menu.contains(e.target)) closeMenu(false);
    });
    window.addEventListener("resize", function () { if (menuOpen) positionMenu(); });

    wrap.appendChild(btn);
    nav.insertBefore(wrap, nav.firstChild);
    document.body.appendChild(menu); // portal out of .topbar's backdrop-filter
  }

  /* ----- boot --------------------------------------------------------- */

  var booted = false;
  function boot() {
    if (booted) return;
    booted = true;
    captureBaseline();
    buildPicker();
    applyLocale(state.locale).then(function () { readyResolve(state.locale); });
  }
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", boot);
  } else {
    boot();
  }

  window.MojitoI18n = {
    get locale() { return state.locale; },
    get rtl() { return state.rtl; },
    ready: ready,
    t: t,
    localeName: localeName,
    onChange: function (cb) { if (typeof cb === "function") changeCbs.push(cb); },
    setLocale: setLocale
  };
})();
