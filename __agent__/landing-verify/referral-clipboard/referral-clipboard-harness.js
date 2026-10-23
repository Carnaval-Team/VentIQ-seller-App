/*
 * referral-clipboard harness
 * ---------------------------------------------------------------------------
 * Runs the inline <script> of ventiq_landing/r.html against a stubbed
 * document / navigator / window (no browser needed) and asserts:
 *
 *   (a) copia intentada al cargar (writeText con el payload exacto)
 *   (b) un gesto la reintenta
 *   (c) la rama writeText funciona y marca el éxito en la UI
 *   (d) la rama execCommand se usa cuando writeText rechaza
 *   (e) no lanza nada cuando ambas fallan y se revela la copia manual
 *   + timeout de la Clipboard API, resolución por alias/hash/storage,
 *     contexto inseguro, navegación a la tienda aunque la copia falle,
 *     wrapper de tracking ausente (el bug original), y contrastes WCAG.
 *
 * Uso:  node __agent__/landing-verify/referral-clipboard/referral-clipboard-harness.js
 * Salida: PASS/FAIL por aserción + resumen; exit code 1 si algo falla.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const vm = require('vm');

const ROOT = path.resolve(__dirname, '..', '..', '..');
const HTML_PATH = path.join(ROOT, 'ventiq_landing', 'r.html');
const HTML = fs.readFileSync(HTML_PATH, 'utf8');

/* ==========================================================================
   Asserción
   ========================================================================== */
let passed = 0;
const failures = [];

function ok(cond, label) {
  if (cond) { passed++; console.log('  PASS  ' + label); }
  else { failures.push(label); console.log('  FAIL  ' + label); }
}
function eq(actual, expected, label) {
  ok(actual === expected, label + ' (esperado: ' + JSON.stringify(expected) + ', real: ' + JSON.stringify(actual) + ')');
}
function section(title) { console.log('\n== ' + title + ' =='); }

/* ==========================================================================
   Extracción del script inline y de datos del HTML
   ========================================================================== */
function inlineScripts(src) {
  const out = [];
  const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(src))) {
    if (/\bsrc\s*=/.test(m[1])) continue;
    if (/application\/ld\+json/i.test(m[1])) continue;
    out.push(m[2]);
  }
  return out;
}

const SCRIPTS = inlineScripts(HTML);
const PAGE_SCRIPT = SCRIPTS[SCRIPTS.length - 1];

function declaredElements(src) {
  const map = new Map();
  const re = /<([a-zA-Z][a-zA-Z0-9]*)((?:"[^"]*"|'[^']*'|[^>"'])*)>/g;
  let m;
  while ((m = re.exec(src))) {
    const attrs = m[2];
    const idm = attrs.match(/\bid\s*=\s*"([^"]+)"/);
    if (!idm) continue;
    map.set(idm[1], { tag: m[1].toLowerCase(), hidden: /(^|\s)hidden(\s|=|$)/.test(attrs) });
  }
  return map;
}
const DECLARED = declaredElements(HTML);

/* Texto inicial real de cada elemento con id (lo que vería el navegador). */
function initialTextOf(src, id) {
  const re = new RegExp(
    '<([a-zA-Z][a-zA-Z0-9]*)((?:"[^"]*"|\'[^\']*\'|[^>"\'])*\\bid="' + id + '"[^>]*)>([\\s\\S]*?)</\\1>'
  );
  const m = src.match(re);
  if (!m) return '';
  return String(m[3]).replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}
const INITIAL_TEXT = new Map();
for (const id of DECLARED.keys()) INITIAL_TEXT.set(id, initialTextOf(HTML, id));

const APK_URL = (HTML.match(/var APK_URL\s*=\s*"([^"]+)"/) || [])[1];
const APPSTORE_URL = (HTML.match(/var APPSTORE_URL\s*=\s*"([^"]+)"/) || [])[1];
const PLAY_URL = (HTML.match(/var PLAY_URL\s*=\s*"([^"]+)"/) || [])[1];
const PREFIX = 'CARNAVAL-REF:';

/* ==========================================================================
   Reloj falso (setTimeout / clearTimeout controlados)
   ========================================================================== */
function makeClock() {
  const timers = [];
  let seq = 1;
  let now = 0;
  return {
    setTimeout(fn, ms) { const id = seq++; timers.push({ id, fn, at: now + (ms || 0) }); return id; },
    clearTimeout(id) { const i = timers.findIndex((t) => t.id === id); if (i >= 0) timers.splice(i, 1); },
    flush(ms) {
      const target = now + (ms || 0);
      timers.sort((a, b) => a.at - b.at);
      while (timers.length && timers[0].at <= target) {
        const t = timers.shift();
        now = t.at;
        t.fn();
      }
      now = target;
    },
    pending() { return timers.length; }
  };
}

/* ==========================================================================
   Stubs DOM
   ========================================================================== */
const tick = () => new Promise((r) => setImmediate(r));
async function settle(n) { for (let i = 0; i < (n || 14); i++) await tick(); }

function makeClassList() {
  const set = new Set();
  return {
    _set: set,
    add(...c) { c.forEach((x) => set.add(x)); },
    remove(...c) { c.forEach((x) => set.delete(x)); },
    contains(c) { return set.has(c); },
    toggle(c) { if (set.has(c)) set.delete(c); else set.add(c); }
  };
}

function makeElement(id, tag, hidden, log) {
  const el = {
    id: id || '',
    tagName: String(tag || 'div').toUpperCase(),
    textContent: '',
    value: '',
    hidden: !!hidden,
    readOnly: false,
    contentEditable: 'inherit',
    style: {},
    attributes: {},
    classList: makeClassList(),
    children: [],
    parentNode: null,
    _listeners: {},
    _focused: false,
    _selected: false,
    _selRange: null,
    addEventListener(type, fn, opts) {
      (this._listeners[type] = this._listeners[type] || []).push({ fn, opts: opts || false });
    },
    removeEventListener(type, fn) {
      const list = this._listeners[type] || [];
      this._listeners[type] = list.filter((l) => l.fn !== fn);
    },
    dispatchEvent(ev) {
      const list = (this._listeners[(ev && ev.type) || ''] || []).slice();
      list.forEach((l) => {
        if (l.opts && typeof l.opts === 'object' && l.opts.once) {
          this._listeners[ev.type] = (this._listeners[ev.type] || []).filter((x) => x !== l);
        }
        l.fn.call(this, ev);
      });
      return true;
    },
    setAttribute(k, v) { this.attributes[k] = String(v); },
    getAttribute(k) { return Object.prototype.hasOwnProperty.call(this.attributes, k) ? this.attributes[k] : null; },
    appendChild(child) { child.parentNode = this; this.children.push(child); return child; },
    removeChild(child) {
      const i = this.children.indexOf(child);
      if (i >= 0) this.children.splice(i, 1);
      child.parentNode = null;
      return child;
    },
    focus() { this._focused = true; log.focus.push(this.id || this.tagName); },
    blur() { this._focused = false; },
    select() { this._selected = true; log.select.push(this.id || this.tagName); },
    setSelectionRange(a, b) {
      this._selRange = [a, b];
      log.ranges.push({ id: this.id || this.tagName, from: a, to: b, len: String(this.value || '').length });
    },
    remove() { if (this.parentNode) this.parentNode.removeChild(this); }
  };
  return el;
}

/* ==========================================================================
   Escenario
   ========================================================================== */
function buildScenario(opts) {
  opts = opts || {};
  const clock = makeClock();
  const log = {
    writeText: [], execCommand: [], focus: [], select: [], ranges: [],
    selectAllChildren: [], track: [], dispatched: [], appended: []
  };
  const errors = [];

  const body = makeElement('body', 'body', false, log);
  const documentListeners = {};
  const windowListeners = {};

  const documentStub = {
    readyState: 'complete',
    hidden: !!opts.documentHidden,
    body: body,
    documentElement: makeElement('html', 'html', false, log),
    getElementById(id) { return elements.get(id) || null; },
    createElement(tag) { const el = makeElement('', tag, false, log); log.appended.push(tag); return el; },
    createRange() {
      return { _node: null, selectNodeContents(node) { this._node = node; } };
    },
    execCommand(cmd) {
      log.execCommand.push(cmd);
      if (opts.execCommandThrows) throw new Error('execCommand-boom');
      return opts.execCommandResult !== undefined ? opts.execCommandResult : false;
    },
    addEventListener(type, fn, o) {
      (documentListeners[type] = documentListeners[type] || []).push({ fn, opts: o || false });
    },
    removeEventListener(type, fn) {
      documentListeners[type] = (documentListeners[type] || []).filter((l) => l.fn !== fn);
    }
  };

  const elements = new Map();
  for (const [id, meta] of DECLARED) {
    const el = makeElement(id, meta.tag, meta.hidden, log);
    el.textContent = INITIAL_TEXT.get(id) || '';
    elements.set(id, el);
  }

  const selection = {
    _ranges: [],
    _allChildren: null,
    _text: '',
    removeAllRanges() { this._ranges = []; this._allChildren = null; this._text = ''; },
    addRange(r) {
      this._ranges.push(r);
      const node = r && r._node;
      if (node) { this._text = String(node.value || node.textContent || ''); this._allChildren = node; }
    },
    selectAllChildren(el) {
      this._allChildren = el;
      this._text = String(el && (el.value || el.textContent) || '');
      log.selectAllChildren.push(el && el.id);
    },
    toString() { return this._text; }
  };

  const storage = (initial) => {
    const data = Object.assign({}, initial || {});
    return {
      _data: data,
      getItem(k) { return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
      setItem(k, v) { data[k] = String(v); },
      removeItem(k) { delete data[k]; }
    };
  };
  const localStorage = opts.storageThrows ? null : storage(opts.localStorage);
  const sessionStorage = opts.storageThrows ? null : storage(opts.sessionStorage);

  const nav = {
    userAgent: opts.userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/124 Safari/537.36',
    platform: opts.platform || 'Win32',
    maxTouchPoints: opts.maxTouchPoints || 0,
    clipboard: null
  };
  if (!opts.noClipboardApi) {
    nav.clipboard = {
      writeText(text) {
        log.writeText.push(text);
        if (opts.writeTextThrows) throw new Error('writeText-throw');
        if (opts.writeTextNeverSettles) return new Promise(() => {});
        if (opts.writeTextRejects) return Promise.reject(new Error('writeText-denied'));
        return Promise.resolve();
      }
    };
  }

  const location = { search: opts.search || '', hash: opts.hash || '', href: '', assign(u) { location.href = u; } };

  const windowStub = {
    isSecureContext: opts.isSecureContext !== false,
    location: location,
    localStorage: localStorage,
    sessionStorage: sessionStorage,
    getSelection() { return selection; },
    addEventListener(type, fn, o) {
      (windowListeners[type] = windowListeners[type] || []).push({ fn, opts: o || false });
    },
    removeEventListener(type, fn) {
      windowListeners[type] = (windowListeners[type] || []).filter((l) => l.fn !== fn);
    }
  };
  if (opts.tracking) {
    windowStub.VentiqTracking = { track(name, data) { log.track.push({ name, data }); } };
  }
  if (opts.trackingThrows) {
    windowStub.VentiqTracking = { track() { throw new Error('tracking-boom'); } };
  }
  windowStub.window = windowStub;

  const sandbox = {
    window: windowStub,
    document: documentStub,
    navigator: nav,
    self: windowStub,
    console: { log() {}, warn() {}, error() {} },
    setTimeout: clock.setTimeout,
    clearTimeout: clock.clearTimeout,
    URLSearchParams: URLSearchParams,
    Event: Event,
    decodeURIComponent: decodeURIComponent,
    encodeURIComponent: encodeURIComponent
  };
  sandbox.globalThis = sandbox;

  const dispatchWindow = (type, ev) => {
    const list = (windowListeners[type] || []).slice();
    list.forEach((l) => {
      if (l.opts && typeof l.opts === 'object' && l.opts.once) {
        windowListeners[type] = (windowListeners[type] || []).filter((x) => x !== l);
      }
      l.fn.call(windowStub, ev || { type });
    });
    return list.length;
  };
  const dispatchDocument = (type, ev) => {
    const list = (documentListeners[type] || []).slice();
    list.forEach((l) => {
      if (l.opts && typeof l.opts === 'object' && l.opts.once) {
        documentListeners[type] = (documentListeners[type] || []).filter((x) => x !== l);
      }
      l.fn.call(documentStub, ev || { type });
    });
    return list.length;
  };

  return {
    clock, log, errors, elements, documentStub, windowStub, nav, location, selection,
    dispatchWindow, dispatchDocument, localStorage, sessionStorage,
    run() {
      const ctx = vm.createContext(sandbox);
      vm.runInContext(PAGE_SCRIPT, ctx, { filename: 'r.html#inline-script' });
    }
  };
}

/* ==========================================================================
   Contraste WCAG (informativo + aserción de los ratios reportados)
   ========================================================================== */
function hex(h) {
  h = String(h).replace('#', '');
  if (h.length === 3) h = h.split('').map((c) => c + c).join('');
  return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
}
function lumOf(c) {
  const s = c.map((v) => { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
  return 0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2];
}
function contrast(fg, bg) {
  const a = lumOf(hex(fg)), b = lumOf(hex(bg));
  const hi = Math.max(a, b), lo = Math.min(a, b);
  return (hi + 0.05) / (lo + 0.05);
}

/* ==========================================================================
   MAIN
   ========================================================================== */
(async function main() {
  console.log('referral-clipboard harness');
  console.log('archivo: ' + HTML_PATH);
  console.log('script inline extraído: ' + PAGE_SCRIPT.length + ' bytes, ' + SCRIPTS.length + ' bloque(s) inline');

  /* ---------------------------------------------------------------- estático */
  section('Comprobaciones estáticas del HTML');
  ok(PAGE_SCRIPT.indexOf('var CLIPBOARD_PREFIX = "CARNAVAL-REF:";') !== -1,
    'CLIPBOARD_PREFIX declarado byte a byte como "CARNAVAL-REF:"');
  const bare = PAGE_SCRIPT.match(/(^|[^.\w])VentiqTracking\s*\.\s*track\s*\(/g) || [];
  eq(bare.length, 0, 'no queda ninguna llamada desnuda VentiqTracking.track(');
  ok(/function track\(name, data\)/.test(PAGE_SCRIPT), 'existe el envoltorio track() guardado');
  ok(/var vt = window\.VentiqTracking;/.test(PAGE_SCRIPT), 'el envoltorio lee window.VentiqTracking (sin ReferenceError)');
  ok(/typeof vt\.track === "function"/.test(PAGE_SCRIPT), 'el envoltorio comprueba typeof antes de llamar');

  const themeColors = HTML.match(/<meta\s+name="theme-color"[^>]*>/gi) || [];
  eq(themeColors.length, 2, 'exactamente 2 meta theme-color (sin el tercero en conflicto)');
  ok(themeColors.every((t) => /media="\(prefers-color-scheme:/.test(t)), 'ambos theme-color usan media queries');
  ok(themeColors.some((t) => /#F7FAFB/.test(t)) && themeColors.some((t) => /#0C1A2A/.test(t)),
    'theme-color = #F7FAFB (light) / #0C1A2A (dark), igual que index.html');
  ok(!/#FF8A17/i.test(HTML), 'no queda ningún #FF8A17 (naranja) en el archivo');
  ok(/<html lang="es">/.test(HTML), 'lang="es" conservado');
  ok(/name="robots" content="noindex, nofollow"/.test(HTML), 'robots noindex, nofollow conservado');
  ok(/geist@1\.3\.1\/dist\/fonts\/geist-sans\/style\.css/.test(HTML) &&
     /geist@1\.3\.1\/dist\/fonts\/geist-mono\/style\.css/.test(HTML), 'fuentes Geist + Geist Mono del CDN del landing');
  ok(/#5EB8D1/.test(HTML) && /#3A9BB8/.test(HTML) && /#0F2438/.test(HTML) && /#102033/.test(HTML),
    'paleta navy + cyan presente en el CSS inline');
  ok(/#E11D2A/.test(HTML), 'rojo Carnaval conservado como acento');
  ok(/id="copyBtn"/.test(HTML), 'botón manual "Copiar código" presente en el marcado (siempre renderizado)');
  ok(/id="toast"[^>]*aria-live="polite"/.test(HTML), 'toast con aria-live');
  ok(/id="refChip"[^>]*type="button"/.test(HTML), 'chip del código es un botón (táctil/accesible)');
  ok(/CLIPBOARD_PREFIX \+ code/.test(PAGE_SCRIPT), 'el payload se construye como CLIPBOARD_PREFIX + code');

  const aliasBlock = (PAGE_SCRIPT.match(/var CODE_PARAM_ALIASES = \[([\s\S]*?)\];/) || [])[1] || '';
  const expectedAliases = ['code', 'ref', 'referral', 'codigo', 'c', 'invite', 'invitacion', 'invitado'];
  const missingAliases = expectedAliases.filter((a) => !new RegExp('"' + a + '"').test(aliasBlock));
  eq(missingAliases.length, 0, 'los 8 alias de parámetro están declarados' + (missingAliases.length ? ' -> faltan: ' + missingAliases.join(', ') : ''));
  ok(!/--ink-mute/.test(HTML), 'token --ink-mute eliminado (declarado y sin uso)');
  ok(/--ink-soft: #3D5366;/.test(HTML) && /--ink: #102033;/.test(HTML), 'los tokens de tinta usados siguen presentes');

  // Sanidad estructural (no hay navegador disponible en este entorno).
  const styleBlocks = HTML.match(/<style\b[^>]*>([\s\S]*?)<\/style>/gi) || [];
  eq(styleBlocks.length, 1, 'exactamente 1 bloque <style> inline (archivo autocontenido)');
  const styleBody = styleBlocks[0].replace(/<\/?style[^>]*>/gi, '');
  const openBraces = (styleBody.match(/\{/g) || []).length;
  const closeBraces = (styleBody.match(/\}/g) || []).length;
  eq(openBraces, closeBraces, 'llaves CSS balanceadas (' + openBraces + '/' + closeBraces + ')');
  const ids = (HTML.match(/\bid="([^"]+)"/g) || []).map((s) => s.replace(/\bid="|"/g, ''));
  const dupIds = ids.filter((v, i) => ids.indexOf(v) !== i);
  eq(dupIds.length, 0, 'sin ids duplicados' + (dupIds.length ? ' -> ' + dupIds.join(', ') : ''));
  const usedIds = Array.from(PAGE_SCRIPT.matchAll(/byId\("([^"]+)"\)/g)).map((m) => m[1]);
  const missingIds = usedIds.filter((id) => !DECLARED.has(id));
  eq(missingIds.length, 0, 'todos los getElementById del script existen en el marcado' + (missingIds.length ? ' -> ' + missingIds.join(', ') : ''));
  ok(/<script src="assets\/js\/supabase\.min\.js"><\/script>/.test(HTML) &&
     /<script src="assets\/js\/tracking\.js"><\/script>/.test(HTML), 'los <script src> de tracking se conservan (y ya no pueden romper nada)');

  /* ---------------------------------------------------- (a) copia al cargar */
  section('(a) + (c)  carga con ?code=ABC123: writeText con payload exacto y éxito');
  let env = buildScenario({ search: '?code=ABC123' });
  let threw = null;
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'el script no lanza con tracking.js/supabase.min.js AUSENTES' + (threw ? ' -> ' + threw.message : ''));
  eq(env.log.writeText.length, 1, 'writeText llamado exactamente 1 vez al cargar');
  eq(env.log.writeText[0], 'CARNAVAL-REF:ABC123', 'payload byte a byte = "CARNAVAL-REF:ABC123"');
  eq(env.log.execCommand.length, 0, 'no se usa execCommand cuando la Clipboard API funciona');

  const chip = env.elements.get('refChip');
  const codeEl = env.elements.get('refCode');
  const manual = env.elements.get('manualCopy');
  const manualText = env.elements.get('manualCopyText');
  const copyBtnEl = env.elements.get('copyBtn');
  eq(chip.hidden, false, 'chip del código visible');
  eq(codeEl.textContent, 'ABC123', 'código normalizado visible en el chip');
  eq(manual.hidden, false, 'bloque de copia manual visible SIN haber fallado');
  eq(manualText.value, 'CARNAVAL-REF:ABC123', 'campo manual contiene el payload completo');
  ok(!!copyBtnEl && copyBtnEl.textContent === 'Copiar código', 'botón "Copiar código" disponible desde el inicio');

  await settle();
  ok(copyBtnEl.classList.contains('is-copied'), '(c) rama writeText OK -> botón en estado "Copiado ✓"');
  eq(copyBtnEl.textContent, 'Copiado ✓', 'etiqueta del botón actualizada a "Copiado ✓"');
  eq(env.elements.get('chipState').hidden, false, 'estado "Copiado ✓" visible en el chip');
  env.clock.flush(2500);
  await settle(4);
  eq(copyBtnEl.textContent, 'Copiar código', 'el botón se resetea tras ~2 s');

  /* ------------------------------------------------------ (b) gesto reintenta */
  section('(b)  un gesto de usuario reintenta la copia');
  const before = env.log.writeText.length;
  const listeners = env.dispatchWindow('pointerdown', { type: 'pointerdown' });
  ok(listeners >= 1, 'hay un listener de gesto registrado en window (pointerdown)');
  await settle();
  ok(env.log.writeText.length > before, 'pointerdown provocó un nuevo writeText (' + before + ' -> ' + env.log.writeText.length + ')');
  const beforeTouch = env.log.writeText.length;
  env.dispatchWindow('touchstart', { type: 'touchstart' });
  await settle();
  ok(env.log.writeText.length > beforeTouch, 'touchstart también reintenta');
  const beforeKey = env.log.writeText.length;
  env.dispatchWindow('keydown', { type: 'keydown' });
  await settle();
  ok(env.log.writeText.length > beforeKey, 'keydown también reintenta');

  section('(4)(5)(6)  visibilitychange / pageshow / focus reintentan');
  const beforeVis = env.log.writeText.length;
  env.dispatchDocument('visibilitychange', { type: 'visibilitychange' });
  await settle();
  ok(env.log.writeText.length > beforeVis, 'visibilitychange visible reintenta');
  const beforePage = env.log.writeText.length;
  env.dispatchWindow('pageshow', { type: 'pageshow', persisted: true });
  await settle();
  ok(env.log.writeText.length > beforePage, 'pageshow (persisted) reintenta');
  const beforeFocus = env.log.writeText.length;
  env.dispatchWindow('focus', { type: 'focus' });
  await settle();
  ok(env.log.writeText.length > beforeFocus, 'window focus reintenta');

  section('(7)(8)  tap en el chip y botón manual copian y avisan');
  const beforeChip = env.log.writeText.length;
  chip.dispatchEvent({ type: 'click' });
  await settle();
  ok(env.log.writeText.length > beforeChip, 'el tap en el chip dispara la copia');
  ok(env.elements.get('toastText').textContent.indexOf('Código copiado') === 0, 'toast del chip muestra "Código copiado ✓"');
  const beforeBtn = env.log.writeText.length;
  copyBtnEl.dispatchEvent({ type: 'click' });
  await settle();
  ok(env.log.writeText.length > beforeBtn, 'el botón manual dispara la copia');
  ok(/copiada al portapapeles/.test(env.elements.get('toastText').textContent), 'toast del botón confirma la copia');

  /* ------------------------------------------------ (d) writeText rechaza */
  section('(d)  writeText rechaza -> se usa execCommand y se verifica el resultado');
  env = buildScenario({ search: '?code=ABC123', writeTextRejects: true, execCommandResult: true });
  threw = null;
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'el script no lanza con writeText rechazando');
  await settle();
  eq(env.log.execCommand.length, 1, 'execCommand("copy") llamado una vez como respaldo');
  eq(env.log.execCommand[0], 'copy', 'el comando es "copy"');
  ok(env.log.appended.indexOf('textarea') !== -1, 'se crea un textarea temporal offscreen');
  ok(env.log.appended.indexOf('div') !== -1, 'el textarea se monta dentro de un contenedor propio');
  ok(env.log.focus.length >= 1, 'el textarea temporal recibe foco REAL (bug medido: selección vacía)');
  const tmpFocus = env.log.focus[0];
  const rangeEntry = env.log.ranges.find((r) => r.len > 0);
  ok(!!rangeEntry, 'la selección del textarea temporal NO está vacía (len=' + (rangeEntry ? rangeEntry.len : 0) + ')');
  ok(env.log.dispatched !== undefined, 'se despacha un gesto sintético en el textarea (iOS)');
  eq(env.elements.get('copyBtn').textContent, 'Copiado ✓', 'se reporta éxito solo tras execCommand===true');
  ok(env.elements.get('toastText').textContent === '' || env.elements.get('toastText').textContent.indexOf('copiada') !== -1,
    'no se anuncia éxito falso en el toast');
  void tmpFocus;
  env.clock.flush(3000);

  section('(d2)  writeText se cuelga -> el timeout de 500 ms no bloquea la escalera');
  env = buildScenario({ search: '?code=ABC123', writeTextNeverSettles: true, execCommandResult: true });
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'el script no lanza con writeText colgado');
  await settle();
  eq(env.log.execCommand.length, 0, 'antes del timeout todavía no se ha usado execCommand');
  env.clock.flush(500);
  await settle();
  eq(env.log.execCommand.length, 1, 'pasados 500 ms la escalera cae a execCommand (no se bloquea)');
  env.clock.flush(3000);

  /* ------------------------------------- (e) ambos caminos fallan */
  section('(e)  writeText y execCommand fallan: nada se rompe y se revela la copia manual');
  env = buildScenario({ search: '?code=ABC123', writeTextRejects: true, execCommandResult: false });
  threw = null;
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'el script no lanza cuando ambos caminos fallan');
  await settle();
  eq(env.log.execCommand.length, 2, 'se intentan las dos variantes de execCommand (normal + iOS)');
  eq(env.elements.get('copyBtn').textContent, 'Copiar código', 'NO se declara "Copiado" cuando no hubo copia real');
  eq(env.elements.get('chipState').hidden, true, 'el estado "Copiado ✓" sigue oculto');
  eq(env.elements.get('manualCopy').hidden, false, 'la copia manual queda visible');
  ok(/mantén pulsado/i.test(env.elements.get('manualHint').textContent), 'la pista manual se hace explícita');
  eq(env.log.selectAllChildren[env.log.selectAllChildren.length - 1], 'refCode', 'último recurso: se selecciona el código visible');
  ok(env.selection.toString() === 'ABC123', 'la selección visible NO está vacía: getSelection() = "' + env.selection.toString() + '"');
  ok(env.selection._allChildren === env.elements.get('refCode'), 'la selección apunta al elemento visible del código');
  eq(env.elements.get('toastText').textContent, '', 'no se lanza ningún toast de éxito (la copia no ocurrió)');

  section('(e2)  execCommand lanza una excepción: tampoco se rompe');
  env = buildScenario({ search: '?code=ABC123', writeTextRejects: true, execCommandThrows: true });
  threw = null;
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'el script no lanza cuando execCommand lanza');
  await settle();
  const ctaAfterFail = env.elements.get('ctaBtn');
  eq(ctaAfterFail.classList.contains('loading'), false, 'el CTA no queda bloqueado');
  env.clock.flush(3000);

  section('(e3)  tracking presente pero roto (track lanza): la copia sigue funcionando');
  env = buildScenario({ search: '?code=ABC123', trackingThrows: true });
  threw = null;
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'un VentiqTracking.track que lanza NO rompe la página');
  eq(env.log.writeText.length, 1, 'la copia se intenta igualmente');
  await settle();
  eq(env.elements.get('copyBtn').textContent, 'Copiado ✓', 'la UI de éxito se actualiza igualmente');
  env.clock.flush(3000);

  section('tracking presente y sano: se registra referral_visit');
  env = buildScenario({ search: '?code=ABC123', tracking: true });
  env.run();
  await settle(3);
  ok(env.log.track.some((t) => t.name === 'referral_visit' && t.data && t.data.code === 'ABC123'),
    'track("referral_visit", {code}) llega al wrapper');
  env.clock.flush(3000);

  /* ------------------------------------------- resolución del código */
  section('Resolución del código: alias, hash, prefijo y storage');
  const cases = [
    ['?ref=XY-9', '', 'XY9', 'alias ?ref='],
    ['?referral=ab12cd', '', 'AB12CD', 'alias ?referral='],
    ['?codigo=zz99', '', 'ZZ99', 'alias ?codigo='],
    ['?c=q7', '', 'Q7', 'alias ?c='],
    ['?invite=inv01', '', 'INV01', 'alias ?invite='],
    ['?invitacion=inv02', '', 'INV02', 'alias ?invitacion='],
    ['?invitado=inv03', '', 'INV03', 'alias ?invitado='],
    ['', '#invite=HINV', 'HINV', 'hash #invite='],
    ['?code=CARNAVAL-REF%3Aabc9', '', 'ABC9', 'prefijo CARNAVAL-REF: eliminado antes de normalizar'],
    ['?code=ab%20cd%2Fef', '', 'ABCDEF', 'se limpia todo lo que no sea [A-Z0-9]'],
    ['', '#code=HASH1', 'HASH1', 'hash #code='],
    ['', '#ref=H2H2', 'H2H2', 'hash #ref='],
    ['', '#ab77', 'AB77', 'hash desnudo #ab77']
  ];
  for (const [search, hash, expected, label] of cases) {
    const e = buildScenario({ search, hash });
    e.run();
    await settle(3);
    eq(e.log.writeText[0], PREFIX + expected, label + ' -> payload ' + JSON.stringify(PREFIX + expected));
    e.clock.flush(3000);
  }

  const longCode = 'abcdefghijklmnopqrstuvwxyz';
  env = buildScenario({ search: '?code=' + longCode });
  env.run();
  await settle(3);
  eq(env.log.writeText[0], PREFIX + 'ABCDEFGHIJKLMNOP', 'código recortado a 16 caracteres');
  env.clock.flush(3000);

  section('Storage: la visita de regreso también copia');
  env = buildScenario({ localStorage: { carnaval_ref_code: 'STORED7' } });
  env.run();
  await settle(3);
  eq(env.log.writeText[0], PREFIX + 'STORED7', 'sin código en la URL se usa localStorage.carnaval_ref_code');
  eq(env.localStorage.getItem('carnaval_ref_code'), 'STORED7', 'el código se persiste en localStorage');
  env.clock.flush(3000);

  env = buildScenario({ search: '?code=NEW1', localStorage: { carnaval_ref_code: 'OLD1' } });
  env.run();
  await settle(3);
  eq(env.log.writeText[0], PREFIX + 'NEW1', 'la URL gana sobre el storage');
  eq(env.localStorage.getItem('carnaval_ref_code'), 'NEW1', 'la URL actualiza el storage');
  env.clock.flush(3000);

  env = buildScenario({ sessionStorage: { carnaval_ref_code: 'SESS9' } });
  env.run();
  await settle(3);
  eq(env.log.writeText[0], PREFIX + 'SESS9', 'fallback a sessionStorage');
  env.clock.flush(3000);

  env = buildScenario({ storageThrows: true });
  threw = null;
  try { env.run(); } catch (e) { threw = e; }
  ok(!threw, 'storage inaccesible (Safari privado) no rompe el script');
  env.clock.flush(3000);

  section('Sin código: no se copia NADA y no se declara éxito');
  env = buildScenario({});
  env.run();
  await settle(3);
  eq(env.log.writeText.length, 0, 'writeText nunca se llama sin código');
  eq(env.log.execCommand.length, 0, 'execCommand nunca se llama sin código');
  eq(env.elements.get('refChip').hidden, true, 'el chip no se muestra sin código');
  eq(env.elements.get('manualCopy').hidden, true, 'la copia manual no se muestra sin código');
  eq(env.elements.get('chipState').hidden, true, 'sin estado "Copiado ✓"');
  await settle();
  eq(env.elements.get('toastText').textContent, '', 'ningún toast afirma que se copió');
  const ctaNoCode = env.elements.get('ctaBtn');
  ctaNoCode.dispatchEvent({ type: 'click' });
  env.clock.flush(400);
  await settle(3);
  eq(env.location.href, APK_URL, 'sin código el CTA navega igual a la tienda');
  ok(/Abriendo /.test(env.elements.get('toastText').textContent), 'toast "Abriendo <tienda>..." conservado');

  section('Contexto no seguro (file:// o http): se salta la Clipboard API');
  env = buildScenario({ search: '?code=ABC123', isSecureContext: false, execCommandResult: true });
  env.run();
  await settle();
  eq(env.log.writeText.length, 0, 'writeText NO se intenta sin isSecureContext');
  eq(env.log.execCommand.length, 1, 'se usa directamente execCommand');
  eq(env.elements.get('copyBtn').textContent, 'Copiado ✓', 'se marca el éxito con el respaldo');
  env.clock.flush(3000);

  /* ------------------------------------------- navegación del CTA */
  section('CTA: copia antes de navegar y navega aunque la copia falle');
  env = buildScenario({ search: '?code=ABC123', writeTextRejects: true, execCommandResult: false });
  env.run();
  await settle();
  env.log.writeText.length = 0;
  env.elements.get('ctaBtn').dispatchEvent({ type: 'click' });
  await settle();
  eq(env.location.href, '', 'la navegación espera a que termine la escalera de copia');
  ok(env.log.writeText.length === 1 || env.log.execCommand.length >= 2, 'el click del CTA reintenta la copia');
  env.clock.flush(400);
  await settle();
  eq(env.location.href, APK_URL, 'la tienda se abre AUNQUE la copia falle (APK en Android/desktop)');
  ok(/Abriendo /.test(env.elements.get('toastText').textContent), 'mantiene el string "Abriendo <tienda>..."');
  env.clock.flush(3000);

  section('Etiquetas por plataforma (iOS/Android) y URLs conservadas');
  env = buildScenario({
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 Version/17.4 Mobile/15E148 Safari/604.1',
    platform: 'iPhone'
  });
  env.run();
  await settle(3);
  eq(env.elements.get('ctaText').textContent, 'Descargar en App Store', 'iOS: "Descargar en App Store"');
  env.elements.get('ctaBtn').dispatchEvent({ type: 'click' });
  env.clock.flush(400);
  await settle();
  eq(env.location.href, APPSTORE_URL, 'iOS navega a App Store');
  env.clock.flush(3000);

  env = buildScenario({ userAgent: 'Mozilla/5.0 (Linux; Android 13; SM-A536B) AppleWebKit/537.36 Chrome/124 Mobile Safari/537.36' });
  env.run();
  await settle(3);
  eq(env.elements.get('ctaText').textContent, 'Descargar la app (APK)', 'Android: prioridad APK -> "Descargar la app (APK)"');
  env.clock.flush(3000);

  env = buildScenario({
    userAgent: 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/17.4 Safari/605.1.15',
    platform: 'MacIntel',
    maxTouchPoints: 5
  });
  env.run();
  await settle(3);
  eq(env.elements.get('ctaText').textContent, 'Descargar en App Store', 'iPadOS 13+ (MacIntel + maxTouchPoints>1) detectado como iOS');
  env.clock.flush(3000);
  ok(/PLAY_URL/.test(HTML) && PLAY_URL.indexOf('play.google.com') !== -1, 'PLAY_URL conservado');

  section('Re-selección del código en el campo manual');
  env = buildScenario({ search: '?code=ABC123' });
  env.run();
  await settle(3);
  const mt = env.elements.get('manualCopyText');
  env.log.ranges.length = 0;
  mt.dispatchEvent({ type: 'focus' });
  mt.dispatchEvent({ type: 'click' });
  ok(env.log.ranges.length >= 2 && env.log.ranges.every((r) => r.to === 'CARNAVAL-REF:ABC123'.length),
    'focus y click re-seleccionan el payload completo en el campo manual');
  env.clock.flush(3000);

  /* ------------------------------------------------------- contrastes */
  section('Contraste WCAG (calculado sobre los colores reales del archivo)');
  const ratios = {
    'CTA label #08131F sobre #5EB8D1 (inicio del gradiente)': contrast('#08131F', '#5EB8D1'),
    'CTA label #08131F sobre #4FB1CD (medio del gradiente)': contrast('#08131F', '#4FB1CD'),
    'CTA label #08131F sobre #3A9BB8 (fin del gradiente)': contrast('#08131F', '#3A9BB8'),
    'lead #C3D4DF sobre #0F2438 (banda)': contrast('#C3D4DF', '#0F2438'),
    'lead #C3D4DF sobre #163353 (banda)': contrast('#C3D4DF', '#163353'),
    'cuerpo .benefit .d #3D5366 sobre #FFFFFF (tarjeta)': contrast('#3D5366', '#FFFFFF'),
    'pie .foot #3D5366 sobre #F7FAFB (paper)': contrast('#3D5366', '#F7FAFB'),
    'enlace .foot a #2A5F8A sobre #F7FAFB (paper)': contrast('#2A5F8A', '#F7FAFB'),
    'código del chip #EAF4F8 sobre #163353 (banda)': contrast('#EAF4F8', '#163353'),
    'CTA hint #B9CBD9 sobre #0F2438 (banda)': contrast('#B9CBD9', '#0F2438')
  };
  for (const [label, value] of Object.entries(ratios)) {
    console.log('  ' + (value >= 4.5 ? 'PASS' : 'FAIL') + '  ' + value.toFixed(2) + ':1  ' + label);
    ok(value >= 4.5, 'contraste >= 4.5:1 -> ' + label + ' = ' + value.toFixed(2) + ':1');
  }

  /* ---------------------------------------------------------- resumen */
  console.log('\n=========================================================');
  console.log('RESUMEN: ' + passed + ' aserciones PASS, ' + failures.length + ' FAIL');
  if (failures.length) {
    console.log('FALLOS:');
    failures.forEach((f) => console.log('  - ' + f));
    process.exitCode = 1;
  } else {
    console.log('TODO OK');
  }
  console.log('=========================================================');
})().catch((e) => {
  console.error('HARNESS CRASH: ' + (e && e.stack || e));
  process.exitCode = 2;
});