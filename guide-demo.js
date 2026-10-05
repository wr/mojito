// Guide-page interactions (W-974). Small, dependency-free, deferred.
//
// 1. .mdemo     — a scripted mini macOS window that types the page's own
//                 shortcode and shows Mojito's picker. The figure's static
//                 markup is the finished state (what crawlers and no-JS
//                 readers see); the script only animates on top of it and
//                 restores it whenever it stops.
// 2. .key-answer — presses the keycaps in sequence, then pops the glyph.
// 3. .kbmap     — renders the US Option / Shift-Option layers as a clickable
//                 keyboard. Characters verified against RedBearAK/optspecialchars.
// 4. [data-copy] — copy-to-clipboard buttons (the Homebrew line).
//
// Everything honors prefers-reduced-motion: demos stay on their static final
// frame and the keycaps don't animate.

(function () {
  'use strict';

  const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const jitter = (ms) => ms + (Math.random() - 0.5) * ms * 0.6;
  const CANCEL = {};

  // Fire `cb(true|false)` as the element enters / leaves the viewport.
  function watch(el, cb, threshold) {
    if (!('IntersectionObserver' in window)) { cb(true); return; }
    new IntersectionObserver((entries) => {
      entries.forEach((e) => cb(e.isIntersecting));
    }, { threshold: threshold || 0.35 }).observe(el);
  }

  function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text != null) n.textContent = text;
    return n;
  }

  // ---------------------------------------------------------------- demos

  // Bold the query letters inside a shortcode, in order (fuzzy subsequence),
  // the way the real picker highlights matches.
  function highlight(code, query) {
    const q = query.replace(/^:+/, '').toLowerCase();
    const frag = document.createDocumentFragment();
    // Rows that matched on a keyword rather than the code itself (`:tada`
    // → 🎊 confetti_ball) get no bold, same as the real picker.
    let probe = 0;
    for (const ch of code.toLowerCase()) if (probe < q.length && ch === q[probe]) probe++;
    if (probe < q.length) { frag.appendChild(document.createTextNode(code)); return frag; }
    // A contiguous run reads better than scattered letters (`copy` in
    // sound_recording_copyright), so prefer it when there is one.
    const at = q ? code.toLowerCase().indexOf(q) : -1;
    if (at >= 0) {
      frag.append(code.slice(0, at), el('b', null, code.slice(at, at + q.length)), code.slice(at + q.length));
      return frag;
    }
    let qi = 0;
    for (const ch of code) {
      if (qi < q.length && ch.toLowerCase() === q[qi] && /[a-z0-9_+-]/i.test(ch)) {
        frag.appendChild(el('b', null, ch));
        qi++;
      } else {
        frag.appendChild(document.createTextNode(ch));
      }
    }
    return frag;
  }

  function setupDemo(fig) {
    const d = fig.dataset;
    const win = fig.querySelector('.mdemo-win');
    const line = fig.querySelector('[data-line]');
    if (!win || !line) return;

    const mode = d.mode || 'pick';
    const typed = d.type || '';
    const colonRun = (typed.match(/^:+/) || [''])[0].length;
    const isImessage = fig.classList.contains('mdemo-imessage');
    const body = fig.querySelector('.mdemo-body');
    const finalTpl = fig.querySelector('[data-final]');
    const finalBubble = finalTpl ? finalTpl.cloneNode(true) : null;
    if (finalBubble) finalBubble.removeAttribute('data-final');
    const staticBody = body.innerHTML;

    // Build the popover once.
    const pop = el('div', 'mdemo-pop');
    let rowEls = [];
    let gifEls = [];
    let gifQ = null;
    if (mode === 'gif') {
      pop.classList.add('is-gif');
      gifQ = el('div', 'mdemo-gifq');
      const grid = el('div', 'mdemo-gifs');
      (d.gifs || '').split('|').filter(Boolean).forEach((src) => {
        const img = el('img');
        img.alt = '';
        img.width = 100;
        img.height = 100;
        img.dataset.src = src;
        grid.appendChild(img);
        gifEls.push(img);
      });
      pop.append(gifQ, grid);
    } else if (mode === 'pick') {
      const ol = el('ol');
      (d.rows || '').split('|').filter(Boolean).forEach((row) => {
        const i = row.indexOf(' ');
        const li = el('li');
        li.append(el('span', 'mx-g', row.slice(0, i)), el('span', 'mx-c', row.slice(i + 1)));
        ol.appendChild(li);
        rowEls.push(li);
      });
      const foot = el('div', 'mdemo-foot');
      foot.innerHTML = '<span><kbd>↑↓</kbd> select</span><span><kbd>↵</kbd> insert</span><span><kbd>⎋</kbd> dismiss</span>';
      pop.append(ol, foot);
    }
    win.appendChild(pop);

    // Toggle button.
    const btn = el('button', 'mdemo-toggle');
    btn.type = 'button';
    btn.setAttribute('aria-label', 'Pause animation');
    btn.innerHTML =
      '<svg class="i-pause" viewBox="0 0 12 12" aria-hidden="true"><path fill="currentColor" d="M2 1h3v10H2zM7 1h3v10H7z"/></svg>' +
      '<svg class="i-play" viewBox="0 0 12 12" aria-hidden="true"><path fill="currentColor" d="M2.5 1.2v9.6L10.5 6z"/></svg>';
    fig.appendChild(btn);

    let token = 0;
    let visible = false;
    let paused = false;

    function restore() {
      pop.classList.remove('show');
      body.innerHTML = staticBody;
    }

    function place(anchor) {
      const w = win.getBoundingClientRect();
      const a = anchor.getBoundingClientRect();
      let left = a.left - w.left - 12;
      left = Math.max(8, Math.min(left, w.width - pop.offsetWidth - 8));
      // Open below the caret line unless that would spill out of the
      // window (or we're in Messages, where the compose field is at the
      // bottom) — then flip above, like the real picker.
      const below = a.bottom - w.top + 6;
      const roomBelow = w.height - 6 - below;
      const roomAbove = a.top - w.top - 6;
      const above = isImessage ||
        (pop.offsetHeight > roomBelow && roomAbove > roomBelow);
      pop.classList.toggle('is-above', above);
      const top = above ? a.top - w.top - pop.offsetHeight - 6 : below;
      pop.style.left = left + 'px';
      pop.style.top = top + 'px';
    }

    async function play(my) {
      const step = async (ms) => {
        await sleep(ms);
        if (my !== token) throw CANCEL;
      };
      // Live references: restore() swaps body.innerHTML, so re-query.
      const ln = body.querySelector('[data-line]');
      const thread = body.querySelector('.mdemo-thread');
      const fin = body.querySelector('[data-final]');
      if (fin) fin.remove();
      ln.textContent = '';
      const pre = document.createTextNode(d.pre || '');
      const q = el('span', 'mdemo-q');
      const post = document.createTextNode('');
      const caret = el('span', 'mdemo-caret');
      ln.append(pre, q, post, caret);

      await step(700);

      // Type the trigger + query.
      for (let i = 0; i < typed.length; i++) {
        q.textContent = typed.slice(0, i + 1);
        const queryLen = i + 1 - colonRun;
        if (mode !== 'convert' && queryLen >= 1) {
          if (mode === 'gif') {
            gifQ.textContent = typed.slice(colonRun, i + 1);
            gifEls.forEach((g, gi) => {
              if (!g.src) g.src = g.dataset.src;
              g.classList.toggle('active', gi === 0);
            });
          } else {
            rowEls.forEach((li, ri) => {
              const c = li.querySelector('.mx-c');
              const code = c.textContent;
              c.textContent = '';
              c.appendChild(highlight(code, q.textContent));
              li.classList.toggle('active', ri === 0);
            });
          }
          if (!pop.classList.contains('show')) {
            place(q);
            pop.classList.add('show');
          }
        }
        await step(jitter(mode === 'convert' ? 150 : 115));
      }

      if (mode !== 'convert') {
        await step(650);
        // "Press Return".
        const pressed = mode === 'gif' ? gifEls[0] : rowEls[0];
        const ret = pop.querySelectorAll('.mdemo-foot kbd')[1];
        if (pressed) pressed.classList.add('is-pressed');
        if (ret) ret.classList.add('is-pressed');
        await step(200);
        if (pressed) pressed.classList.remove('is-pressed');
        if (ret) ret.classList.remove('is-pressed');
        pop.classList.remove('show');
      } else {
        await step(120);
      }

      if (mode === 'gif') {
        q.textContent = '';
        if (isImessage) {
          // The pick is "sent": the GIF lands in the thread, compose clears.
          if (thread && finalBubble) {
            const b = finalBubble.cloneNode(true);
            b.classList.add('is-new');
            thread.appendChild(b);
          }
          ln.textContent = '';
          ln.appendChild(el('span', 'mdemo-placeholder', 'iMessage'));
        } else {
          // Anywhere else the GIF is pasted inline at the cursor.
          const img = el('img', 'mdemo-gif-inline is-new');
          img.alt = '';
          img.src = (gifEls[0] && (gifEls[0].src || gifEls[0].dataset.src)) || '';
          ln.insertBefore(img, post);
          for (const ch of d.post || '') {
            post.data += ch;
            await step(jitter(55));
          }
        }
        await step(3200);
        return;
      }

      // Swap the query for the result, flash it.
      q.textContent = d.result || '';
      q.classList.add('mdemo-res', 'is-new');
      await step(320);

      for (const ch of d.post || '') {
        post.data += ch;
        await step(jitter(55));
      }

      if (isImessage && thread && finalBubble) {
        await step(500);
        const b = finalBubble.cloneNode(true);
        b.classList.add('is-new');
        thread.appendChild(b);
        ln.textContent = '';
        ln.appendChild(el('span', 'mdemo-placeholder', 'iMessage'));
      }
      await step(2800);
    }

    async function loop(my) {
      while (my === token) {
        try {
          await play(my);
        } catch (e) {
          if (e !== CANCEL) throw e;
          return;
        }
        if (my !== token) return;
        restore();
      }
    }

    function start() {
      if (paused || !visible) return;
      fig.classList.add('is-anim');
      const my = ++token;
      loop(my);
    }
    function stop() {
      token++;
      restore();
    }

    btn.addEventListener('click', () => {
      paused = !paused;
      fig.classList.toggle('is-paused', paused);
      btn.setAttribute('aria-label', paused ? 'Play animation' : 'Pause animation');
      if (paused) stop(); else start();
    });

    fig.classList.add('is-anim');
    watch(fig, (inView) => {
      visible = inView;
      if (inView) start(); else stop();
    });
  }

  // ------------------------------------------------------ keycap answers

  function setupKeys(card) {
    const keys = Array.from(card.querySelectorAll('.key-cap, .key-type'));
    const res = card.querySelector('.key-result');
    if (!keys.length || !res) return;
    const typeChip = card.querySelector('.key-type');
    const chipText = typeChip ? typeChip.textContent : '';
    card.classList.add('is-armed');
    let running = false;

    async function play() {
      if (running) return;
      running = true;
      res.classList.remove('is-shown');
      keys.forEach((k) => k.classList.remove('is-down'));
      await sleep(250);
      if (typeChip) {
        typeChip.classList.add('is-down');
        for (let i = 1; i <= chipText.length; i++) {
          typeChip.textContent = chipText.slice(0, i);
          await sleep(jitter(95));
        }
      } else {
        for (const k of keys) {
          k.classList.add('is-down');
          await sleep(190);
        }
      }
      await sleep(160);
      res.classList.add('is-shown');
      await sleep(650);
      keys.forEach((k) => k.classList.remove('is-down'));
      running = false;
    }

    let played = false;
    watch(card, (inView) => {
      if (inView && !played) { played = true; play(); }
    }, 0.6);
    card.addEventListener('pointerenter', play);
    card.addEventListener('click', play);
  }

  // ------------------------------------------------ Option-key keyboard

  // [base key, Option char, Shift-Option char, Option name, Shift-Option name].
  // A leading "*" marks a dead key (an accent that waits for the next letter).
  const KB = [
    [
      ['`', '*`', '`', 'Grave accent (dead key)', 'Grave accent'],
      ['1', '¡', '⁄', 'Inverted exclamation mark', 'Fraction slash'],
      ['2', '™', '€', 'Trade mark sign', 'Euro sign'],
      ['3', '£', '‹', 'Pound sign', 'Single left angle quote'],
      ['4', '¢', '›', 'Cent sign', 'Single right angle quote'],
      ['5', '∞', 'ﬁ', 'Infinity', 'fi ligature'],
      ['6', '§', 'ﬂ', 'Section sign', 'fl ligature'],
      ['7', '¶', '‡', 'Pilcrow (paragraph sign)', 'Double dagger'],
      ['8', '•', '°', 'Bullet', 'Degree sign'],
      ['9', 'ª', '·', 'Feminine ordinal', 'Middle dot'],
      ['0', 'º', '‚', 'Masculine ordinal', 'Single low quote'],
      ['-', '–', '—', 'En dash', 'Em dash'],
      ['=', '≠', '±', 'Not equal to', 'Plus-minus sign'],
    ],
    [
      ['Q', 'œ', 'Œ', 'oe ligature', 'OE ligature'],
      ['W', '∑', '„', 'Summation (sigma)', 'Double low quote'],
      ['E', '*´', '´', 'Acute accent (dead key)', 'Acute accent'],
      ['R', '®', '‰', 'Registered sign', 'Per mille sign'],
      ['T', '†', 'ˇ', 'Dagger', 'Caron'],
      ['Y', '¥', 'Á', 'Yen sign', 'A with acute'],
      ['U', '*¨', '¨', 'Umlaut (dead key)', 'Diaeresis'],
      ['I', '*ˆ', 'ˆ', 'Circumflex (dead key)', 'Circumflex'],
      ['O', 'ø', 'Ø', 'o with stroke', 'O with stroke'],
      ['P', 'π', '∏', 'Pi', 'N-ary product'],
      ['[', '“', '”', 'Left double quote', 'Right double quote'],
      [']', '‘', '’', 'Left single quote', 'Right single quote (apostrophe)'],
      ['\\', '«', '»', 'Left double angle quote', 'Right double angle quote'],
    ],
    [
      ['A', 'å', 'Å', 'a with ring', 'A with ring'],
      ['S', 'ß', 'Í', 'Sharp s (eszett)', 'I with acute'],
      ['D', '∂', 'Î', 'Partial differential', 'I with circumflex'],
      ['F', 'ƒ', 'Ï', 'Florin', 'I with diaeresis'],
      ['G', '©', '˝', 'Copyright sign', 'Double acute accent'],
      ['H', '˙', 'Ó', 'Dot above', 'O with acute'],
      ['J', '∆', 'Ô', 'Increment (delta)', 'O with circumflex'],
      ['K', '˚', '', 'Ring above', 'Apple logo'],
      ['L', '¬', 'Ò', 'Not sign', 'O with grave'],
      [';', '…', 'Ú', 'Ellipsis', 'U with acute'],
      ["'", 'æ', 'Æ', 'ae ligature', 'AE ligature'],
    ],
    [
      ['Z', 'Ω', '¸', 'Omega', 'Cedilla'],
      ['X', '≈', '˛', 'Almost equal to', 'Ogonek'],
      ['C', 'ç', 'Ç', 'c with cedilla', 'C with cedilla'],
      ['V', '√', '◊', 'Square root', 'Lozenge'],
      ['B', '∫', 'ı', 'Integral', 'Dotless i'],
      ['N', '*˜', '˜', 'Tilde (dead key)', 'Small tilde'],
      ['M', 'µ', 'Â', 'Micro sign', 'A with circumflex'],
      [',', '≤', '¯', 'Less than or equal to', 'Macron'],
      ['.', '≥', '˘', 'Greater than or equal to', 'Breve'],
      ['/', '÷', '¿', 'Division sign', 'Inverted question mark'],
    ],
  ];
  // Row stagger, in key widths, like a real keyboard.
  const PAD = [[0, 0], [0.5, 0], [0.75, 0.75], [1.25, 1.25]];

  function hex(ch) {
    return 'U+' + ch.codePointAt(0).toString(16).toUpperCase().padStart(4, '0');
  }

  function setupKbmap(fig) {
    // data-mark="shift-option:8 option:-" — keys to ring, first one selected.
    const marks = (fig.dataset.mark || '').split(/\s+/).filter(Boolean).map((m) => {
      const i = m.indexOf(':');
      return { layer: m.slice(0, i), key: m.slice(i + 1).toUpperCase() };
    });
    let layer = marks[0] ? marks[0].layer : 'option';
    let selected = marks[0] ? marks[0].key : null;

    const ui = el('div', 'kbmap-ui');
    const head = el('div', 'kbmap-head');
    head.appendChild(el('p', 'kbmap-title', 'Hold a modifier, press a key'));
    const seg = el('div', 'kbmap-seg');
    seg.setAttribute('role', 'group');
    seg.setAttribute('aria-label', 'Modifier keys');
    const layers = [['option', '⌥ Option'], ['shift-option', '⇧ ⌥ Shift-Option']];
    const segBtns = layers.map(([id, label]) => {
      const b = el('button', null, label);
      b.type = 'button';
      b.addEventListener('click', () => { layer = id; render(); });
      seg.appendChild(b);
      return [id, b];
    });
    head.appendChild(seg);
    const rows = el('div', 'kbmap-rows');
    const info = el('div', 'kbmap-info');
    info.setAttribute('aria-live', 'polite');
    const legend = el('p', 'kbmap-legend');
    legend.innerHTML = 'US layout. <span class="dead">Dashed orange</span> keys are accent keys: press one, then a letter (⌥E, then E types é).';
    ui.append(head, rows, info, legend);
    fig.insertBefore(ui, fig.firstChild);
    fig.hidden = false;

    function render() {
      segBtns.forEach(([id, b]) => b.setAttribute('aria-pressed', String(id === layer)));
      rows.textContent = '';
      const col = layer === 'option' ? 1 : 2;
      KB.forEach((row, ri) => {
        const r = el('div', 'kbmap-row');
        const lead = el('span', 'kbmap-pad');
        lead.style.setProperty('--w', PAD[ri][0] || 0.0001);
        if (PAD[ri][0]) r.appendChild(lead);
        row.forEach((k) => {
          let ch = k[col];
          const dead = ch.length > 1 && ch[0] === '*';
          if (dead) ch = ch.slice(1);
          const b = el('button', 'kbmap-key');
          b.type = 'button';
          if (dead) b.classList.add('is-dead');
          if (marks.some((m) => m.layer === layer && m.key === k[0])) b.classList.add('is-mark');
          b.setAttribute('aria-pressed', String(selected === k[0]));
          const mods = layer === 'option' ? 'Option' : 'Shift-Option';
          b.setAttribute('aria-label', mods + ' ' + k[0] + ': ' + k[col + 2]);
          b.append(el('span', 'kb-base', k[0]), document.createTextNode(ch));
          b.addEventListener('click', () => { selected = k[0]; render(); });
          r.appendChild(b);
        });
        if (PAD[ri][1]) {
          const tail = el('span', 'kbmap-pad');
          tail.style.setProperty('--w', PAD[ri][1]);
          r.appendChild(tail);
        }
        rows.appendChild(r);
      });
      info.textContent = '';
      const k = KB.flat().find((x) => x[0] === selected);
      if (!k) {
        info.appendChild(el('span', 'kb-name', 'Click any key to see what it types.'));
        return;
      }
      let ch = k[col];
      const dead = ch.length > 1 && ch[0] === '*';
      if (dead) ch = ch.slice(1);
      const combo = (layer === 'option' ? '⌥ Option' : '⇧ Shift + ⌥ Option') + ' + ' + k[0];
      info.append(
        el('span', 'kb-glyph', ch),
        el('strong', null, combo),
        el('span', 'kb-name', k[col + 2] + ' · ' + hex(ch)),
      );
      if (!dead) {
        const c = el('button', 'copy-btn', 'Copy');
        c.type = 'button';
        c.dataset.copy = ch;
        info.appendChild(c);
      }
    }
    render();
  }

  // --------------------------------------------------------------- copy

  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-copy]');
    if (!b || !navigator.clipboard) return;
    navigator.clipboard.writeText(b.dataset.copy).then(() => {
      const t = b.textContent;
      b.textContent = 'Copied';
      b.classList.add('is-done');
      setTimeout(() => { b.textContent = t; b.classList.remove('is-done'); }, 1400);
    });
  });

  // --------------------------------------------------------------- boot

  document.querySelectorAll('.kbmap').forEach(setupKbmap);
  if (!reduceMotion) {
    document.querySelectorAll('.mdemo').forEach(setupDemo);
    document.querySelectorAll('.key-answer').forEach(setupKeys);
  }
})();
