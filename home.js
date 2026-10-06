/* Homepage extras (W-994). Loaded after i18n.js and picker.js.
 *
 * The "Speaks 19 languages" feature card cycles its title (and the flag in
 * its icon tile) through every locale's own translation of that title. The
 * strings mirror features.languages.h in i18n/*.json (en-GB and es-419 are
 * left out because their titles match en and es). The real, translated
 * title stays in the visually hidden span for screen readers and i18n.js.
 */
(function () {
  "use strict";

  var LANGS = [
    ["en", "🇺🇸", "Speaks 19 languages"],
    ["de", "🇩🇪", "Spricht 19 Sprachen"],
    ["es", "🇪🇸", "Habla 19 idiomas"],
    ["fr", "🇫🇷", "Parle 19 langues"],
    ["it", "🇮🇹", "Parla 19 lingue"],
    ["pt-BR", "🇧🇷", "Fala 19 idiomas"],
    ["ja", "🇯🇵", "19言語に対応"],
    ["zh-Hans", "🇨🇳", "支持 19 种语言"],
    ["zh-Hant", "🇹🇼", "支援 19 種語言"],
    ["ko", "🇰🇷", "19개 언어 지원"],
    ["hi", "🇮🇳", "19 भाषाएँ बोलता है"],
    ["ru", "🇷🇺", "Говорит на 19 языках"],
    ["pl", "🇵🇱", "Mówi w 19 językach"],
    ["nl", "🇳🇱", "Spreekt 19 talen"],
    ["ar", "🇸🇦", "يتحدث 19 لغة"],
    ["fa", "🇮🇷", "به ۱۹ زبان حرف می‌زند"],
    ["he", "🇮🇱", "מדבר 19 שפות"],
  ];
  var FLAGS = {"en": "🇺🇸", "en-GB": "🇬🇧", "de": "🇩🇪", "es": "🇪🇸", "es-419": "🌎", "fr": "🇫🇷", "it": "🇮🇹", "pt-BR": "🇧🇷", "ja": "🇯🇵", "zh-Hans": "🇨🇳", "zh-Hant": "🇹🇼", "ko": "🇰🇷", "hi": "🇮🇳", "ru": "🇷🇺", "pl": "🇵🇱", "nl": "🇳🇱", "ar": "🇸🇦", "fa": "🇮🇷", "he": "🇮🇱"};
  var RTL = { ar: 1, fa: 1, he: 1 };
  var INTERVAL = 2200;
  var FADE = 250;

  var text = document.querySelector(".lang-cycle");
  var flag = document.querySelector(".lang-cycle-flag");
  if (!text || !flag) return;
  var card = text.closest(".feature-card");
  var reduce = window.matchMedia("(prefers-reduced-motion: reduce)");
  var I18N = window.MojitoI18n;

  var idx = 0;
  var timer = null;
  var fade = null;
  var visible = false;

  function currentLocale() { return (I18N && I18N.locale) || "en"; }

  // Where the cycle starts: the visitor's own locale (en-GB → en, es-419 → es).
  function startIndex() {
    var code = currentLocale();
    for (var i = 0; i < LANGS.length; i++) if (LANGS[i][0] === code) return i;
    var primary = code.split("-")[0];
    for (var j = 0; j < LANGS.length; j++) if (LANGS[j][0].split("-")[0] === primary) return j;
    return 0;
  }

  function show(i, flagChar) {
    var row = LANGS[i];
    text.textContent = row[2];
    text.lang = row[0];
    text.dir = RTL[row[0]] ? "rtl" : "ltr";
    flag.textContent = flagChar || row[1];
  }

  function step() {
    text.classList.add("is-out");
    flag.classList.add("is-out");
    fade = setTimeout(function () {
      fade = null;
      idx = (idx + 1) % LANGS.length;
      show(idx);
      text.classList.remove("is-out");
      flag.classList.remove("is-out");
    }, FADE);
  }

  // Restart from the visitor's locale whenever the card scrolls into view or
  // the language changes; only tick while the card is on screen.
  function sync() {
    clearInterval(timer);
    clearTimeout(fade);
    timer = fade = null;
    text.classList.remove("is-out");
    flag.classList.remove("is-out");
    idx = startIndex();
    show(idx, FLAGS[currentLocale()]);
    if (visible && !reduce.matches) timer = setInterval(step, INTERVAL);
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      visible = entries[entries.length - 1].isIntersecting;
      sync();
    }).observe(card);
  }
  if (I18N && I18N.onChange) I18N.onChange(sync);
  if (I18N && I18N.ready && I18N.ready.then) I18N.ready.then(sync);
  sync();
})();
