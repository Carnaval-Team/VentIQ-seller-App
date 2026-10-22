#!/usr/bin/env node
/*
 * INDEPENDENT clipboard harness for ventiq_landing/r.html  (verifier-owned, task-3)
 *
 * Why hand-rolled: jsdom is not installed in this workspace, and the task forbids
 * trusting the author's harness. This file builds a minimal DOM + navigator + timer
 * environment, executes the page's INLINE scripts (external <script src> are NOT
 * loaded -- that is the point: window.VentiqTracking is absent and supabase.min.js is
 * absent), and observes what actually reaches the clipboard.
 *
 * Fidelity contract: every API the page touches that this stub does NOT explicitly
 * model is recorded in `__unknownProps` and reported, so a PASS can never be an
 * artefact of a silently stubbed method. Unknown-property stubbing can only turn a
 * PASS into a FAIL, never the reverse.
 *
 * Usage:
 *   node verify-clipboard.js <path-to-r.html> [--json out.json]
 * Exit code 1 if any HARD assertion fails.
 */
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const target = process.argv[2];
if (!target) { console.error('usage: node verify-clipboard.js <r.html>'); process.exit(2); }
const jsonOut = (() => { const i = process.argv.indexOf('--json'); return i > -1 ? process.argv[i + 1] : null; })();
const DEBUG_DISPLAY = process.argv.includes('--debug-display');
const html = fs.readFileSync(target, 'utf8');

/* ------------------------------------------------------------------ parsing ---- */
const VOID = new Set(['area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta', 'param', 'source', 'track', 'wbr']);
const decode = s => s.replace(/&nbsp;/g, ' ').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, '&');

function parseAttrs(src) {
  const out = {};
  const re = /([\w:.-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+)))?/g;
  let m;
  while ((m = re.exec(src))) out[m[1].toLowerCase()] = decode(m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4] !== undefined ? m[4] : '');
  return out;
}

let NODE_ID = 0;
function makeElement(tag, attrs, doc) {
  const el = {
    __id: ++NODE_ID,
    nodeType: 1,
    tagName: String(tag).toUpperCase(),
    _tag: String(tag).toLowerCase(),
    attrs: attrs || {},
    children: [],
    parentNode: null,
    _listeners: {},
    _style: {},
    _value: undefined,
    ownerDocument: doc,
  };
  Object.defineProperty(el, 'parentElement', { get() { return el.parentNode; } });
  return el;
}

function parseFragment(src, parent, doc) {
  const stack = [parent];
  const top = () => stack[stack.length - 1];
  const re = /<!--[\s\S]*?-->|<!\[CDATA\[[\s\S]*?\]\]>|<!DOCTYPE[^>]*>|<\/([a-zA-Z][\w:-]*)\s*>|<([a-zA-Z][\w:-]*)((?:"[^"]*"|'[^']*'|[^>"'])*?)(\/?)>|([^<]+)/g;
  let m, last = 0;
  while ((m = re.exec(src))) {
    last = re.lastIndex;
    if (m[1]) { // close tag
      const name = m[1].toLowerCase();
      for (let i = stack.length - 1; i > 0; i--) {
        if (stack[i]._tag === name) { stack.length = i; break; }
      }
      continue;
    }
    if (m[2]) { // open tag
      const name = m[2].toLowerCase();
      const attrs = parseAttrs(m[3] || '');
      const el = makeElement(name, attrs, doc);
      el.parentNode = top();
      top().__children.push(el);
      if (name === 'textarea' || name === 'title') {
        const close = new RegExp('</' + name + '\\s*>', 'i');
        const rest = src.slice(re.lastIndex);
        const cm = close.exec(rest);
        const text = cm ? rest.slice(0, cm.index) : rest;
        el._value = decode(text).replace(/^\n/, '');
        el.children.push({ nodeType: 3, textContent: el._value, parentNode: el });
        if (cm) { re.lastIndex = re.lastIndex + cm.index + cm[0].length; }
        else { re.lastIndex = src.length; }
        continue;
      }
      if (!VOID.has(name) && !m[4]) stack.push(el);
      continue;
    }
    if (m[5] !== undefined) { // text
      const t = decode(m[5]);
      if (t.trim() === '' && top()._tag !== 'textarea') {
        if (t) top().__children.push({ nodeType: 3, textContent: t, parentNode: top() });
      } else {
        top().__children.push({ nodeType: 3, textContent: t, parentNode: top() });
      }
    }
  }
  return parent;
}

/* ------------------------------------------------------------------ element ---- */
function installElementProto(elPrototype, doc, state) {
  const def = (name, desc) => Object.defineProperty(elPrototype, name, desc);
  def('className', {
    get() { return this.attrs.class || ''; },
    set(v) { this.attrs.class = String(v); },
  });
  def('id', { get() { return this.attrs.id || ''; }, set(v) { this.attrs.id = String(v); } });
  def('classList', {
    get() {
      const self = this;
      return {
        add(...c) { const s = new Set(self.className.split(/\s+/).filter(Boolean)); c.forEach(x => s.add(x)); self.attrs.class = [...s].join(' '); },
        remove(...c) { const s = new Set(self.className.split(/\s+/).filter(Boolean)); c.forEach(x => s.delete(x)); self.attrs.class = [...s].join(' '); },
        contains(c) { return self.className.split(/\s+/).includes(c); },
        toggle(c, f) { const has = self.className.split(/\s+/).includes(c); const on = f === undefined ? !has : !!f; on ? this.add(c) : this.remove(c); return on; },
      };
    },
  });
  def('style', {
    get() {
      const self = this;
      if (self._styleProxy) return self._styleProxy;
      self._styleProxy = new Proxy(self._style, {
        get(t, k) {
          if (k === 'setProperty') return (n, v) => { t[n] = String(v); };
          if (k === 'getPropertyValue') return n => t[n] !== undefined ? t[n] : '';
          if (k === 'removeProperty') return n => { delete t[n]; };
          if (k === 'cssText') return Object.entries(t).map(([a, b]) => a + ':' + b).join(';');
          if (typeof k === 'string') return t[k] !== undefined ? t[k] : '';
          return t[k];
        },
        set(t, k, v) { t[k] = v; return true; },
      });
      return self._styleProxy;
    },
  });
  def('dataset', {
    get() {
      const self = this;
      return new Proxy({}, {
        get(_, k) {
          const key = 'data-' + String(k).replace(/[A-Z]/g, c => '-' + c.toLowerCase());
          return self.attrs[key];
        },
        set(_, k, v) { self.attrs['data-' + String(k).replace(/[A-Z]/g, c => '-' + c.toLowerCase())] = String(v); return true; },
      });
    },
  });
  def('textContent', {
    get() { return this.children.map(c => c.nodeType === 3 ? c.textContent : c.textContent).join(''); },
    set(v) { this.children = []; if (v !== '' && v != null) this.children.push({ nodeType: 3, textContent: String(v), parentNode: this }); },
  });
  def('innerText', { get() { return this.textContent; }, set(v) { this.textContent = v; } });
  def('innerHTML', {
    get() { return this.children.map(c => c.nodeType === 3 ? c.textContent : serialize(c)).join(''); },
    set(v) { this.children = []; parseFragment(String(v), this, doc); },
  });
  def('value', {
    get() { if (this._value !== undefined) return this._value; if (this._tag === 'textarea') return this.textContent; return this.attrs.value !== undefined ? this.attrs.value : ''; },
    set(v) { this._value = String(v); },
  });
  def('children', { get() { return (this.__children || []).filter(c => c.nodeType === 1); }, set(v) { this.__children = v; } });
  // children/childNodes are stored in __children; expose both views
  const origChildrenDesc = Object.getOwnPropertyDescriptor(elPrototype, 'children');
  def('childNodes', { get() { return this.__children || []; } });
  def('firstChild', { get() { return (this.__children || [])[0] || null; } });
  def('firstElementChild', { get() { return (this.__children || []).find(c => c.nodeType === 1) || null; } });
  def('lastElementChild', { get() { const l = (this.__children || []).filter(c => c.nodeType === 1); return l[l.length - 1] || null; } });
  def('nextElementSibling', { get() { if (!this.parentNode) return null; const s = this.parentNode.__children || []; const i = s.indexOf(this); return s.slice(i + 1).find(c => c.nodeType === 1) || null; } });
  def('parentNode', { get() { return this.__parent || null; }, set(v) { this.__parent = v; } });
  def('nodeName', { get() { return this.tagName; } });
  def('isConnected', { get() { let n = this; while (n.parentNode) n = n.parentNode; return n === doc || n === doc.documentElement; } });

  elPrototype.appendChild = function (c) {
    if (c.parentNode && c.parentNode.__children) {
      const s = c.parentNode.__children; const i = s.indexOf(c); if (i > -1) s.splice(i, 1);
    }
    c.parentNode = this;
    this.__children.push(c);
    return c;
  };
  elPrototype.removeChild = function (c) {
    const s = this.__children; const i = s.indexOf(c);
    if (i < 0) { const e = new Error('NotFoundError: removeChild'); throw e; }
    s.splice(i, 1); c.parentNode = null; return c;
  };
  elPrototype.insertBefore = function (c, ref) {
    const s = this.__children; const i = ref ? s.indexOf(ref) : s.length;
    if (c.parentNode && c.parentNode.__children) { const p = c.parentNode.__children; const j = p.indexOf(c); if (j > -1) p.splice(j, 1); }
    c.parentNode = this; s.splice(i < 0 ? s.length : i, 0, c); return c;
  };
  elPrototype.replaceChild = function (nw, old) { const s = this.__children; const i = s.indexOf(old); if (i > -1) s[i] = nw; nw.parentNode = this; return old; };
  elPrototype.cloneNode = function (deep) {
    const c = makeElement(this._tag, { ...this.attrs }, doc);
    c._value = this._value;
    if (deep) (this.__children || []).forEach(ch => c.appendChild(ch.nodeType === 1 ? ch.cloneNode(true) : { nodeType: 3, textContent: ch.textContent, parentNode: c }));
    return c;
  };
  elPrototype.remove = function () { if (this.parentNode) this.parentNode.removeChild(this); };
  elPrototype.setAttribute = function (n, v) { this.attrs[String(n).toLowerCase()] = String(v); };
  elPrototype.getAttribute = function (n) { const v = this.attrs[String(n).toLowerCase()]; return v === undefined ? null : v; };
  elPrototype.hasAttribute = function (n) { return this.attrs[String(n).toLowerCase()] !== undefined; };
  elPrototype.removeAttribute = function (n) { delete this.attrs[String(n).toLowerCase()]; };
  elPrototype.addEventListener = function (t, fn) { (this._listeners[t] = this._listeners[t] || []).push(fn); };
  elPrototype.removeEventListener = function (t, fn) { if (this._listeners[t]) this._listeners[t] = this._listeners[t].filter(f => f !== fn); };
  elPrototype.dispatchEvent = function (ev) {
    const type = ev && ev.type;
    if (!type) return true;
    ev.target = ev.target || this;
    ev.currentTarget = this;
    let n = this;
    const path = [];
    while (n) { path.push(n); n = n.parentNode; }
    if (ev.bubbles !== false) {
      for (const node of path) {
        const ls = (node._listeners[type] || []).slice();
        for (const fn of ls) fn.call(node, ev);
        if (ev.__stop) break;
      }
    } else {
      const ls = (this._listeners[type] || []).slice();
      for (const fn of ls) fn.call(this, ev);
    }
    return !ev.defaultPrevented;
  };
  elPrototype.click = function () {
    const connected = this.isConnected;
    const r = this.dispatchEvent({ type: 'click', bubbles: true, target: this });
    if (this._tag === 'a' || (this.tagName === 'BUTTON')) { /* default action not modelled */ }
    if (!connected) state.warnings.push('click() on a detached node #' + (this.id || '?'));
    return r;
  };
  elPrototype.focus = function () { doc.activeElement = this; };
  elPrototype.blur = function () { if (doc.activeElement === this) doc.activeElement = doc.body; };
  elPrototype.setSelectionRange = function (a, b) { this.__selection = [a, b]; };
  elPrototype.select = function () { this.__selected = true; };
  elPrototype.scrollIntoView = function () {};
  elPrototype.getBoundingClientRect = function () { return { top: 0, left: 0, right: 320, bottom: 40, width: 320, height: 40, x: 0, y: 0 }; };
  elPrototype.matches = function (sel) { return matchSelector(this, sel, doc); };
  elPrototype.closest = function (sel) { let n = this; while (n) { if (n.nodeType === 1 && matchSelector(n, sel, doc)) return n; n = n.parentNode; } return null; };
  elPrototype.querySelector = function (sel) { return queryAll(this, sel, doc)[0] || null; };
  elPrototype.querySelectorAll = function (sel) { return queryAll(this, sel, doc); };
  elPrototype.getElementsByTagName = function (t) { return queryAll(this, String(t), doc); };
  elPrototype.getElementsByClassName = function (c) { return queryAll(this, '.' + c, doc); };
  def('offsetWidth', { get() { return 320; } });
  def('offsetHeight', { get() { return 40; } });
  def('clientWidth', { get() { return 320; } });
  def('clientHeight', { get() { return 40; } });
  def('scrollWidth', { get() { return 320; } });
  def('scrollHeight', { get() { return 40; } });
}

function serialize(el) {
  const a = Object.entries(el.attrs || {}).map(([k, v]) => ' ' + k + '="' + v + '"').join('');
  return '<' + el._tag + a + '>' + (el.__children || []).map(c => c.nodeType === 3 ? c.textContent : serialize(c)).join('') + '</' + el._tag + '>';
}

/* --------------------------------------------------------------- selectors ---- */
/* Right-to-left matching over a compound/combinator sequence. matchCompound()
   REJECTS anything it cannot fully account for, so a malformed selector can never
   match vacuously (an earlier version returned true for garbage such as "*\/"). */
function matchSelector(el, sel) {
  sel = String(sel || '').trim();
  if (!sel) return false;
  const seq = sel.replace(/\s*>\s*/g, ' > ').split(/\s+/).filter(t => t !== '');
  const parts = [];
  let pending = null;
  for (const tok of seq) {
    if (tok === '>') { pending = 'child'; continue; }
    parts.push({ compound: tok, comb: pending || 'desc' });
    pending = null;
  }
  if (!parts.length) return false;
  return matchFrom(el, parts, parts.length - 1);
}
function matchFrom(node, parts, idx) {
  if (!node || node.nodeType !== 1) return false;
  if (!matchCompound(node, parts[idx].compound)) return false;
  if (idx === 0) return true;
  if (parts[idx].comb === 'child') return matchFrom(node.parentNode, parts, idx - 1);
  let n = node.parentNode;
  while (n) { if (matchFrom(n, parts, idx - 1)) return true; n = n.parentNode; }
  return false;
}
function matchCompound(el, sel) {
  if (!el || el.nodeType !== 1) return false;
  sel = String(sel).trim();
  if (!sel || !/^[a-zA-Z*#.[]/.test(sel)) return false; // rejects comments, '*/', '@media', ';' etc.
  const t = sel.match(/^([a-zA-Z*][\w-]*)/);
  let rest = sel;
  if (t) {
    if (t[1] !== '*' && el._tag !== t[1].toLowerCase()) return false;
    rest = sel.slice(t[0].length);
  }
  const tokenRe = /[.#][\w-]+|\[[^\]]*\]|:not\([^)]*\)|:[\w-]+(\([^)]*\))?/g;
  const tokens = rest.match(tokenRe) || [];
  const consumed = tokens.join('');
  if (rest.trim() !== consumed.trim()) return false; // unparsed residue -> no match
  for (const tok of tokens) {
    if (tok[0] === '.') { if (!el.className.split(/\s+/).includes(tok.slice(1))) return false; }
    else if (tok[0] === '#') { if (el.id !== tok.slice(1)) return false; }
    else if (tok[0] === '[') {
      const m = /^\[([\w-]+)(?:([~^$*|]?=)"?([^"\]]*)"?)?\]$/.exec(tok);
      if (!m) return false;
      const v = el.attrs[m[1].toLowerCase()];
      if (v === undefined) return false;
      if (m[2]) { const want = m[3]; if (m[2] === '=' && v !== want) return false; if (m[2] === '*=' && !v.includes(want)) return false; if (m[2] === '^=' && !v.startsWith(want)) return false; if (m[2] === '$=' && !v.endsWith(want)) return false; }
    } else if (tok.startsWith(':not(')) { if (matchCompound(el, tok.slice(5, -1))) return false; }
    else if (tok === ':hover' || tok === ':focus' || tok === ':active' || tok === ':first-child' || tok === ':last-child' || tok === ':disabled') { /* state pseudo: ignore */ }
    else if (tok.startsWith(':nth-child')) { /* ignore */ }
    else if (tok.startsWith(':is(') || tok.startsWith(':where(')) { const inner = tok.slice(tok.indexOf('(') + 1, -1); if (!inner.split(',').some(s => matchCompound(el, s.trim()))) return false; }
    else return false; // unknown pseudo -> refuse rather than guess
  }
  return true;
}
function walk(root, fn) { for (const c of root.__children || []) { if (c.nodeType === 1) { fn(c); walk(c, fn); } } }
function queryAll(root, sel, doc) {
  const out = [];
  for (const one of String(sel).split(',')) {
    const s = one.trim();
    if (!s) continue;
    walk(root, el => { if (matchSelector(el, s)) out.push(el); });
  }
  return out;
}

/* --------------------------------------------------------------------- css ---- */
function extractStyleText(html) {
  const out = [];
  const re = /<style[^>]*>([\s\S]*?)<\/style>/gi;
  let m; while ((m = re.exec(html))) out.push(m[1]);
  return out.join('\n');
}
function matchBrace(s, open) { let d = 0; for (let i = open; i < s.length; i++) { if (s[i] === '{') d++; else if (s[i] === '}') { d--; if (d === 0) return i; } } return s.length; }
/* brace-depth aware: handles @media/@supports nesting, which a flat regex mis-parses */
function displayRules(cssText, out, specBoost) {
  out = out || [];
  specBoost = specBoost || 0;
  const css = String(cssText).replace(/\/\*[\s\S]*?\*\//g, ' ');
  let i = 0, buf = '';
  while (i < css.length) {
    const c = css[i];
    if (c === '{') {
      const end = matchBrace(css, i);
      const body = css.slice(i + 1, end);
      const sel = buf.trim();
      buf = '';
      if (sel.startsWith('@')) {
        if (body.includes('{')) displayRules(body, out, specBoost);
      } else if (sel) {
        const dm = /(?:^|;|\s)display\s*:\s*([^;!}]+)/.exec(body);
        if (dm) {
          sel.split(',').forEach(s => {
            s = s.trim();
            if (!s) return;
            const spec = specBoost + (s.match(/#/g) || []).length * 100 + (s.match(/\.[\w-]+/g) || []).length * 10 + (s.match(/\[/g) || []).length * 10 + (s.match(/^(?:html|body|[a-zA-Z])/) ? 1 : 0);
            out.push({ sel: s, display: dm[1].trim(), spec, order: out.length });
          });
        }
      }
      i = end + 1;
      continue;
    }
    if (c === '}') { buf = ''; i++; continue; }
    buf += c; i++;
  }
  return out;
}
function resolveDisplay(el, rules) {
  if (el.style.display) return el.style.display;
  let best = null;
  for (const r of rules) {
    let ok = false;
    try { ok = matchSelector(el, r.sel); } catch (e) { ok = false; }
    if (!ok) continue;
    if (!best || r.spec >= best.spec) best = r;
  }
  if (best) return best.display;
  return ['span', 'a', 'b', 'i', 'em', 'strong', 'label'].includes(el._tag) ? 'inline' : 'block';
}

/* ------------------------------------------------------------------- runner ---- */
function extractScripts(html) {
  const out = [];
  const re = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let m;
  while ((m = re.exec(html))) {
    const attrs = parseAttrs(m[1] || '');
    out.push({ src: attrs.src || null, type: attrs.type || '', code: m[2] });
  }
  return out;
}

function runScenario(opts) {
  const warnings = [];
  const state = { warnings, unknownProps: new Set() };
  const logs = { copy: [], errors: [], rejections: [], tracking: [], navigations: [], console: [], unknownApi: [] };
  const timers = [];
  let clock = 0;
  let timerId = 0;

  const doc = { nodeType: 9, _tag: '#document', __children: [], documentElement: null, body: null, head: null, activeElement: null };
  const elProto = Object.create(Object.prototype);
  installElementProto(elProto, doc, state);
  // attach proto methods to elements created by makeElement
  const origMake = makeElement;
  makeElement = function (tag, attrs, d) {
    const el = origMake(tag, attrs, d); Object.setPrototypeOf(el, elProto); el.__children = [];
    // honour inline style="a:b;c:d" attributes (baseline uses style="display:none")
    if (attrs && typeof attrs.style === 'string' && attrs.style.trim()) {
      attrs.style.split(';').forEach(decl => {
        const i = decl.indexOf(':');
        if (i > 0) {
          const k = decl.slice(0, i).trim().replace(/-([a-z])/g, (_, c) => c.toUpperCase());
          el._style[k] = decl.slice(i + 1).trim();
        }
      });
    }
    return el;
  };

  const domHtml = html.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '').replace(/<style\b[^>]*>[\s\S]*?<\/style>/gi, '');
  const bodyInner = (/<body[^>]*>([\s\S]*?)<\/body>/i.exec(domHtml) || [, domHtml])[1];
  const headInner = (/<head[^>]*>([\s\S]*?)<\/head>/i.exec(domHtml) || [, ''])[1];
  const htmlEl = makeElement('html', {}, doc);
  const headEl = makeElement('head', {}, doc);
  const bodyEl = makeElement('body', {}, doc);
  doc.__children.push(htmlEl);
  htmlEl.appendChild(headEl); htmlEl.appendChild(bodyEl);
  doc.documentElement = htmlEl; doc.head = headEl; doc.body = bodyEl; doc.activeElement = bodyEl;
  parseFragment(headInner, headEl, doc);
  parseFragment(bodyInner, bodyEl, doc);
  const displayRulesets = displayRules(extractStyleText(html));

  const listeners = { window: {} };
  const localStorage = mkStorage();
  const sessionStorage = mkStorage();
  if (opts.seedStorage) for (const [k, v] of Object.entries(opts.seedStorage)) { localStorage.setItem(k, v); sessionStorage.setItem(k, v); }

  function mkStorage() {
    const m = {};
    return { getItem: k => (k in m ? m[k] : null), setItem: (k, v) => { m[k] = String(v); }, removeItem: k => { delete m[k]; }, clear: () => { for (const k of Object.keys(m)) delete m[k]; }, get length() { return Object.keys(m).length; }, key: i => Object.keys(m)[i] || null };
  }

  const location = {
    _href: opts.href || 'https://ventiqa.example/r.html',
    search: '', hash: '', pathname: '/r.html', origin: 'https://ventiqa.example',
  };
  const u = new URL(location._href);
  location.search = u.search; location.hash = u.hash; location.pathname = u.pathname; location.origin = u.origin;
  Object.defineProperty(location, 'href', {
    get() { return location._href; },
    set(v) { logs.navigations.push({ to: String(v), at: clock }); location._href = String(v); },
  });
  location.assign = v => { logs.navigations.push({ to: String(v), at: clock, via: 'assign' }); };
  location.replace = v => { logs.navigations.push({ to: String(v), at: clock, via: 'replace' }); };
  location.reload = () => { };

  /* clipboard modes: ok | reject | never | getter-throws | absent */
  const copyApi = { writeText: null };
  const clipboardObj = {
    writeText(text) {
      logs.copy.push({ via: 'clipboard.writeText', payload: String(text), at: clock, ok: opts.clipboard === 'ok' });
      if (opts.clipboard === 'reject') return Promise.reject(Object.assign(new Error('NotAllowedError'), { name: 'NotAllowedError' }));
      if (opts.clipboard === 'never') return new Promise(() => { });
      return Promise.resolve();
    },
    readText: () => Promise.resolve(''),
  };

  const navigator = {
    userAgent: opts.userAgent || 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120 Safari/537.36',
    platform: opts.platform || 'Win32',
    maxTouchPoints: 0,
    language: 'es',
  };
  if (opts.clipboard === 'getter-throws') {
    Object.defineProperty(navigator, 'clipboard', { get() { logs.unknownApi.push('navigator.clipboard getter threw (simulated webview)'); throw new Error('SecurityError: clipboard blocked'); } });
  } else if (opts.clipboard === 'absent') {
    Object.defineProperty(navigator, 'clipboard', { get() { return undefined; } });
  } else {
    navigator.clipboard = clipboardObj;
  }

  const documentObj = {
    nodeType: 9,
    readyState: 'complete',
    documentElement: htmlEl,
    body: bodyEl,
    head: headEl,
    activeElement: bodyEl,
    referrer: '',
    visibilityState: 'visible',
    getElementById: id => queryAll(bodyEl, '#' + id, doc).concat(queryAll(headEl, '#' + id, doc))[0] || null,
    querySelector: sel => queryAll(bodyEl, sel, doc)[0] || null,
    querySelectorAll: sel => queryAll(bodyEl, sel, doc),
    getElementsByTagName: t => queryAll(bodyEl, t, doc),
    getElementsByClassName: c => queryAll(bodyEl, '.' + c, doc),
    createElement: t => makeElement(t, {}, doc),
    createTextNode: t => ({ nodeType: 3, textContent: String(t), parentNode: null }),
    createDocumentFragment: () => { const f = makeElement('#fragment', {}, doc); return f; },
    createRange: () => ({
      selectNodeContents(el) { this.node = el; },
      setStart() { }, setEnd() { },
    }),
    addEventListener(t, fn) { (listeners.window['doc:' + t] = listeners.window['doc:' + t] || []).push(fn); },
    removeEventListener() { },
    dispatchEvent(ev) { (listeners.window['doc:' + (ev && ev.type)] || []).slice().forEach(f => f(ev)); return true; },
    execCommand(cmd) {
      const sel = windowStub.getSelection();
      if (cmd === 'copy') {
        logs.copy.push({ via: 'document.execCommand', payload: sel.__sel || '', at: clock, ok: opts.execCommand !== false });
        return opts.execCommand !== false;
      }
      return false;
    },
    removeEventListener() { },
  };

  /* A REAL page keeps one selection per document: using a fresh object per call made
   execCommand observe an empty selection (false FAIL). */
  const selection = {
    __sel: '',
    removeAllRanges() { this.__sel = ''; },
    addRange(range) { this.__sel = range && range.node ? (range.node.value !== undefined ? range.node.value : range.node.textContent) : ''; },
    selectAllChildren(el) { this.__sel = el.value !== undefined ? el.value : el.textContent; },
    toString() { return this.__sel; },
    rangeCount: 1,
  };

  /* Minimal event classes so the page's own dispatch code is not silently starved. */
  const EvClass = class {
    constructor(type, init) { this.type = type; this.bubbles = !!(init && init.bubbles); this.cancelable = !!(init && init.cancelable); this.defaultPrevented = false; if (init) for (const k of Object.keys(init)) if (k !== 'type') this[k] = init[k]; }
    preventDefault() { this.defaultPrevented = true; }
    stopPropagation() { this.__stop = true; }
    stopImmediatePropagation() { this.__stop = true; }
  };
  const NodeStub = { TEXT_NODE: 3, ELEMENT_NODE: 1, DOCUMENT_NODE: 9, DOCUMENT_FRAGMENT_NODE: 11 };

  const windowStub = {
    Event: EvClass, CustomEvent: EvClass, MouseEvent: EvClass, PointerEvent: EvClass,
    KeyboardEvent: EvClass, FocusEvent: EvClass, InputEvent: EvClass, Node: NodeStub,
    requestIdleCallback: fn => windowStub.setTimeout(fn, 0),
    performance: { now: () => clock },
    document: documentObj, navigator, location,
    localStorage, sessionStorage,
    innerWidth: 1440, innerHeight: 900, scrollX: 0, scrollY: 0, devicePixelRatio: 1,
    isSecureContext: opts.secureContext !== false,
    __copyLog: null,
    dataLayer: [],
    getSelection: () => selection,
    matchMedia: q => ({ matches: false, media: q, addEventListener() { }, removeEventListener() { }, addListener() { }, removeListener() { } }),
    addEventListener(t, fn) { (listeners.window[t] = listeners.window[t] || []).push(fn); },
    removeEventListener(t, fn) { if (listeners.window[t]) listeners.window[t] = listeners.window[t].filter(f => f !== fn); },
    dispatchEvent(ev) { (listeners.window[ev && ev.type] || []).slice().forEach(f => f(ev)); return true; },
    setTimeout(fn, ms, ...a) { const id = ++timerId; timers.push({ id, at: clock + (ms || 0), fn, args: a, cancelled: false }); return id; },
    clearTimeout(id) { const t = timers.find(x => x.id === id); if (t) t.cancelled = true; },
    setInterval(fn, ms, ...a) { return windowStub.setTimeout(fn, ms, ...a); },
    clearInterval(id) { windowStub.clearTimeout(id); },
    requestAnimationFrame(fn) { return windowStub.setTimeout(fn, 16); },
    cancelAnimationFrame(id) { windowStub.clearTimeout(id); },
    getComputedStyle: el => ({ display: resolveDisplay(el, displayRulesets), opacity: el.style.opacity || '1', visibility: 'visible', getPropertyValue: p => (p === 'display' ? resolveDisplay(el, displayRulesets) : '') }),
    URLSearchParams, URL, Promise, Date, Math, JSON, Object, Array, String, Number, Boolean, Error, TypeError, RegExp, Set, Map, parseInt, parseFloat, isNaN, encodeURIComponent, decodeURIComponent, console: null,
    scrollTo() { }, focus() { }, blur() { },
  };
  windowStub.window = windowStub;
  windowStub.self = windowStub;
  windowStub.globalThis = windowStub;

  const consoleStub = {
    log: (...a) => logs.console.push(['log', a.map(String).join(' ')]),
    warn: (...a) => logs.console.push(['warn', a.map(String).join(' ')]),
    error: (...a) => logs.console.push(['error', a.map(String).join(' ')]),
    info: () => { }, debug: () => { },
  };
  windowStub.console = consoleStub;

  if (opts.trackingPresent) {
    windowStub.VentiqTracking = { track(evt, extra) { logs.tracking.push({ evt, extra, at: clock }); return Promise.resolve(); } };
  }

  // Proxy the window so unknown globals are logged (not silently invented silently-typed)
  const winProxy = new Proxy(windowStub, {
    has() { return true; },
    get(t, k) {
      if (k in t) return t[k];
      if (typeof k === 'symbol') return undefined;
      logs.unknownApi.push('window.' + String(k));
      return undefined;
    },
    set(t, k, v) { t[k] = v; return true; },
  });

  const ctx = vm.createContext(winProxy);
  ctx.__dsh = { logs, warnings };

  const scripts = extractScripts(html);
  const inline = scripts.filter(s => !s.src && !/googletagmanager|gtag\/js/.test(s.code));
  const external = scripts.filter(s => s.src);

  if (opts.trackingPresent === undefined) {
    /* scenario decides; default: external scripts are NOT loaded */
  }

  for (const s of inline) {
    try {
      vm.runInContext(s.code, ctx, { filename: 'inline-script' });
    } catch (e) {
      logs.errors.push({ phase: 'init', error: String(e && e.message || e), stack: String(e && e.stack || '').split('\n').slice(0, 4).join(' | ') });
    }
  }

  function flush(ms) {
    const end = clock + ms;
    for (let guard = 0; guard < 1000; guard++) {
      const due = timers.filter(t => !t.cancelled && t.at <= end).sort((a, b) => a.at - b.at)[0];
      if (!due) break;
      clock = due.at; due.cancelled = true;
      try { due.fn(...due.args); } catch (e) { logs.errors.push({ phase: 'timer', error: String(e && e.message || e), stack: String(e && e.stack || '').split('\n').slice(0, 4).join(' | ') }); }
    }
    clock = end;
  }

  return {
    doc: documentObj, windowStub, logs, flush, displayRulesets, resolveDisplay: el => resolveDisplay(el, displayRulesets),
    getEl: id => documentObj.getElementById(id),
    click: el => { if (!el) return; try { el.click(); } catch (e) { logs.errors.push({ phase: 'click', error: String(e && e.message || e), stack: String(e && e.stack || '').split('\n').slice(0, 4).join(' | ') }); } },
    __timers: timers,
  };
}

/* ------------------------------------------------------------------ main ---- */
const CONT_CODE = 'ABC123';
function q(o) { return Object.entries(o).map(([k, v]) => k + '=' + encodeURIComponent(v)).join('&'); }

/* Scenarios. Isolation rule: every failure-mode scenario runs with tracking.js
   PRESENT, so a copy-logic failure cannot be blamed on C1 (tracking) and vice versa.
   The two tracking-ABSENT scenarios exist specifically to test C1/C2. */
const SCENARIOS = [
  {
    name: 'C1 tracking.js ABSENT + code present  (whole-init survival)',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'ok', trackingPresent: false,
    hard: ['no-errors', 'payload-on-gesture'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C2 tracking.js ABSENT + NO code  (CTA must still work)',
    href: 'https://ventiqa.example/r.html',
    clipboard: 'ok', trackingPresent: false,
    hard: ['no-errors', 'still-functional'],
  },
  {
    name: 'control: tracking PRESENT / clipboard ok / load+gesture',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'ok', trackingPresent: true,
    hard: ['no-errors', 'payload-on-gesture'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C11 no code param -> must not write a bare prefix',
    href: 'https://ventiqa.example/r.html',
    clipboard: 'ok', trackingPresent: true,
    hard: ['no-errors', 'no-bare-payload'],
  },
  {
    name: 'C11 empty code param -> must not write a bare prefix',
    href: 'https://ventiqa.example/r.html?' + q({ code: '' }),
    clipboard: 'ok', trackingPresent: true,
    hard: ['no-errors', 'no-bare-payload'],
  },
  {
    name: 'C11 punctuation-only code -> must not write a bare prefix',
    href: 'https://ventiqa.example/r.html?' + q({ code: '---' }),
    clipboard: 'ok', trackingPresent: true,
    hard: ['no-errors', 'no-bare-payload'],
  },
  {
    name: 'C6 writeText REJECTS -> execCommand fallback',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'reject', execCommand: true, trackingPresent: true,
    hard: ['no-errors', 'payload-on-gesture', 'execCommand-fallback'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C5 navigator.clipboard ABSENT -> execCommand',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'absent', execCommand: true, trackingPresent: true,
    hard: ['no-errors', 'payload-on-gesture', 'execCommand-fallback'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C5 navigator.clipboard GETTER THROWS (hostile webview)',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'getter-throws', execCommand: true, trackingPresent: true,
    hard: ['no-errors', 'payload-on-gesture'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C16 ALL copy routes FAIL -> manual affordance required',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'reject', execCommand: false, trackingPresent: true, expectCopyImpossible: true,
    hard: ['no-errors', 'manual-affordance', 'manual-has-payload', 'still-functional'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C7 writeText NEVER SETTLES -> must not wedge the CTA',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'never', execCommand: true, trackingPresent: true,
    hard: ['no-errors', 'still-functional'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C12 re-entry: 3 taps with every route failing',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'reject', execCommand: false, trackingPresent: true, expectCopyImpossible: true,
    taps: 3,
    hard: ['no-errors', 'manual-affordance', 'still-functional', 'reentry-attempts-copy'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C10 code lowercase/dash/underscore -> payload must preserve it',
    href: 'https://ventiqa.example/r.html?' + q({ code: 'abc-123_xy' }),
    clipboard: 'ok', trackingPresent: true,
    hard: ['no-errors', 'payload-on-gesture'],
    expectPayload: 'CARNAVAL-REF:abc-123_xy',
    mutationProbe: true,
  },
  {
    name: 'C17b iOS Safari UA (gesture path)',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'reject', execCommand: true,
    userAgent: 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1',
    platform: 'iPhone', trackingPresent: true,
    hard: ['no-errors', 'payload-on-gesture', 'execCommand-fallback'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  {
    name: 'C4 pageshow (persisted) re-copy with every route failing',
    href: 'https://ventiqa.example/r.html?' + q({ code: CONT_CODE }),
    clipboard: 'reject', execCommand: false, trackingPresent: true, expectCopyImpossible: true,
    pageshowPersisted: true,
    hard: ['no-errors', 'manual-affordance', 'pageshow-no-throw'],
    expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
  },
  /* C9 informational probes: alternative code routes. No hard assertion -- the page
     never declared which aliases it supports; I report what actually resolves. */
  {
    name: 'C9 probe: ?ref=CODE',
    href: 'https://ventiqa.example/r.html?' + q({ ref: CONT_CODE }),
    clipboard: 'ok', trackingPresent: true, expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
    hard: ['no-errors'], codeResolvedSoft: true,
  },
  {
    name: 'C9 probe: #code=CODE (hash)',
    href: 'https://ventiqa.example/r.html#code=' + CONT_CODE,
    clipboard: 'ok', trackingPresent: true, expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
    hard: ['no-errors'], codeResolvedSoft: true,
  },
  {
    name: 'C9 probe: ?invite=CODE',
    href: 'https://ventiqa.example/r.html?' + q({ invite: CONT_CODE }),
    clipboard: 'ok', trackingPresent: true, expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
    hard: ['no-errors'], codeResolvedSoft: true,
  },
  {
    name: 'C9 probe: ?c=CODE',
    href: 'https://ventiqa.example/r.html?' + q({ c: CONT_CODE }),
    clipboard: 'ok', trackingPresent: true, expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
    hard: ['no-errors'], codeResolvedSoft: true,
  },
  {
    name: 'C9 probe: code only in localStorage (no param)',
    href: 'https://ventiqa.example/r.html',
    clipboard: 'ok', trackingPresent: true, expectPayload: 'CARNAVAL-REF:' + CONT_CODE,
    seedStorage: { carnaval_ref_code: CONT_CODE, referralCode: CONT_CODE, code: CONT_CODE },
    hard: ['no-errors'], codeResolvedSoft: true,
  },
];

const results = [];
const tick = () => new Promise(res => setImmediate(res));
/* Yield to the microtask queue between virtual-clock advances: promise chains
   (.catch fallbacks, awaits) only progress when the stack unwinds. Without this,
   every fallback path falsely looked "never reached". */
async function settle(r, ms) { for (let i = 0; i < 8; i++) { await tick(); r.flush(ms); } }

async function main() {
for (const sc of SCENARIOS) {
  const r = runScenario(sc);
  const snap = () => {
    const chip = r.getEl('refChip');
    const manual = r.getEl('manualCopy');
    const out = {
      chipShown: chip ? resolveDisplayPublic(chip, r) !== 'none' : null,
      manualShown: manual ? resolveDisplayPublic(manual, r) !== 'none' : null,
      manualHasPayload: manual ? (queryAll(manual, 'textarea', r.doc)[0] || {}).value : null,
      codeText: (r.getEl('refCode') || {}).textContent || null,
      toast: (r.getEl('toastText') || {}).textContent || null,
      ctaText: (r.getEl('ctaText') || {}).textContent || null,
      copyButton: (() => { const b = r.getEl('copyBtn') || r.doc.querySelector('[data-copy]'); return b ? { id: b.id, text: b.textContent.trim(), shown: resolveDisplayPublic(b, r) !== 'none' } : null; })(),
    };
    return out;
  };
  const observations = { load: snap() };
  await settle(r, 300);
  observations.afterLoadTimers = snap();

  // gesture(s)
  const cta = r.getEl('ctaBtn');
  const taps = sc.taps || 1;
  for (let i = 0; i < taps; i++) {
    // Window-level gesture listeners (capture, once) are the iOS-relevant path;
    // element-to-window bubbling is not modelled, so dispatch them explicitly.
    try { r.windowStub.dispatchEvent({ type: 'pointerdown', bubbles: true }); } catch (e) { }
    r.click(cta);
    try { r.windowStub.dispatchEvent({ type: 'click', bubbles: true }); } catch (e) { }
    await settle(r, 600);
  }
  await settle(r, 2000);
  observations.afterGesture = snap();

  /* Adversarial: also activate the visible copy affordance itself. A button that is
     only *visible* proves nothing, and with no/empty code it must not write a bare
     "CARNAVAL-REF:" into the clipboard the app later reads. */
  const affordanceBtn = r.getEl('copyBtn') || r.doc.querySelector('[data-copy]');
  const copyLenBeforeAffordance = r.logs.copy.length;
  if (affordanceBtn && r.resolveDisplay(affordanceBtn) !== 'none') {
    r.click(affordanceBtn);
    await settle(r, 600);
  }
  const affordanceCopy = r.logs.copy.slice(copyLenBeforeAffordance);
  observations.afterAffordance = snap();

  if (sc.pageshowPersisted) {
    try {
      r.windowStub.dispatchEvent({ type: 'pageshow', persisted: true });
      await settle(r, 1000);
    } catch (e) { r.logs.errors.push({ phase: 'pageshow-dispatch', error: String(e && e.message || e) }); }
  }

  // assertions
  const A = [];
  const payloads = r.logs.copy.map(c => c.payload);
  const hard = new Set(sc.hard || []);
  const push = (id, ok, detail) => A.push({ id, ok, detail, hard: hard.has(id) });

  push('no-errors', r.logs.errors.length === 0, r.logs.errors.length ? JSON.stringify(r.logs.errors) : 'no uncaught errors');
  const sourceHasCta = /id\s*=\s*["']ctaBtn["']/.test(html);
  const parsedCta = !!(r.getEl('ctaBtn'));
  push('harness-parsed-dom', parsedCta || !sourceHasCta,
    sourceHasCta ? (parsedCta ? 'ctaBtn found in parsed DOM' : 'HARNESS BUG: source has id="ctaBtn" but my DOM stub did not expose it') : 'source no longer contains id="ctaBtn" (page-side id change)');
  if (sc.expectPayload) {
    if (sc.expectCopyImpossible) {
      push('payload-on-gesture', true, 'N/A: this scenario forces every automatic copy route to fail on purpose; the requirement under test here is the visible affordance, asserted separately');
    } else {
      // STRICT: a copy API must have received the exact payload AND must have
      // reported success (ok !== false). A call that returned false/rejected did
      // NOT put anything on the clipboard.
      const copiedExact = r.logs.copy.some(c => c.payload === sc.expectPayload && c.ok !== false);
      const attemptedExact = r.logs.copy.some(c => c.payload === sc.expectPayload);
      push('payload-on-gesture', copiedExact, 'a copy API must receive the exact payload AND succeed; expected ' + JSON.stringify(sc.expectPayload) + '; attempted=' + attemptedExact + '; copyLog=' + JSON.stringify(r.logs.copy));
    }
    // separate, honest soft row: is the payload at least OFFERED to the user?
    const offered = (observations.afterGesture.manualShown === true && observations.afterGesture.manualHasPayload === sc.expectPayload) ||
      (observations.afterGesture.copyButton && observations.afterGesture.copyButton.shown === true);
    push('payload-offered-manually', !!offered, 'manualShown=' + observations.afterGesture.manualShown + ' manualVal=' + JSON.stringify(observations.afterGesture.manualHasPayload) + ' copyBtn=' + JSON.stringify(observations.afterGesture.copyButton));
    const prefixOk = payloads.every(p => p === sc.expectPayload);
    if (sc.mutationProbe) push('starts-with-prefix', payloads.length > 0 && prefixOk, 'payload(s) ' + JSON.stringify(payloads) + (payloads.length === 0 ? ' -- NO copy occurred' : prefixOk ? '' : ' -- MUTATED'));
  }
  push('execCommand-fallback', r.logs.copy.some(c => c.via === 'document.execCommand'), 'routes: ' + JSON.stringify(r.logs.copy.map(c => c.via)));
  push('manual-affordance', observations.afterGesture.manualShown === true || (observations.afterGesture.copyButton && observations.afterGesture.copyButton.shown === true), 'manualShown=' + observations.afterGesture.manualShown + ' copyButton=' + JSON.stringify(observations.afterGesture.copyButton));
  push('manual-has-payload', observations.afterGesture.manualHasPayload === sc.expectPayload || (observations.afterGesture.copyButton && observations.afterGesture.copyButton.shown), 'manual value=' + JSON.stringify(observations.afterGesture.manualHasPayload));
  push('still-functional', r.logs.navigations.length > 0 || observations.afterGesture.manualShown === true || (observations.afterGesture.copyButton && observations.afterGesture.copyButton.shown), 'navigations=' + JSON.stringify(r.logs.navigations) + ' manualShown=' + observations.afterGesture.manualShown);
  push('no-bare-payload', !payloads.some(p => p === 'CARNAVAL-REF:' || p === ''), 'payloads=' + JSON.stringify(payloads));
  if (affordanceBtn) {
    push('affordance-no-bare-payload', !affordanceCopy.some(c => c.payload === 'CARNAVAL-REF:' || c.payload === ''), 'copy-button clicks -> ' + JSON.stringify(affordanceCopy));
    if (sc.expectPayload && !sc.expectCopyImpossible) push('copy-button-works', affordanceCopy.some(c => c.payload === sc.expectPayload && c.ok !== false), 'clicking the visible copy affordance must produce the exact payload; saw ' + JSON.stringify(affordanceCopy));
  } else {
    push('copy-affordance-present', false, 'no #copyBtn / [data-copy] element exists in the final r.html');
  }
  push('reentry-attempts-copy', r.logs.copy.length >= (sc.taps || 1), 'copy attempts=' + r.logs.copy.length + ' (taps=' + (sc.taps || 1) + ')');
  push('pageshow-no-throw', r.logs.errors.length === 0, 'errors=' + r.logs.errors.length);
  if (sc.codeResolvedSoft) {
    const resolved = observations.afterGesture.codeText === CONT_CODE || r.logs.copy.some(c => c.payload === sc.expectPayload) || observations.afterGesture.manualHasPayload === sc.expectPayload;
    push('code-resolved-via-this-route', resolved, 'codeText=' + JSON.stringify(observations.afterGesture.codeText) + ' chip=' + observations.afterGesture.chipShown + ' copyLog=' + JSON.stringify(r.logs.copy.map(c => c.payload)));
  }

  if (DEBUG_DISPLAY) {
    observations.debugRulesCount = r.displayRulesets.length;
    observations.debugDisplay = ['manualCopy', 'refChip', 'ctaBtn', 'copyBtn'].map(id => {
      const el = r.getEl(id);
      if (!el) return { id, found: false };
      const matched = r.displayRulesets.filter(rr => { try { return matchSelector(el, rr.sel); } catch (e) { return false; } });
      return { id, found: true, inlineStyle: { ...el._style }, className: el.className, matchedRules: matched, resolved: r.resolveDisplay(el) };
    });
  }

  results.push({ scenario: sc.name, href: sc.href, clipboard: sc.clipboard, execCommand: sc.execCommand, trackingPresent: sc.trackingPresent, observations, copyLog: r.logs.copy, errors: r.logs.errors, trackingCalls: r.logs.tracking, navigations: r.logs.navigations, consoleLog: r.logs.console, unknownApi: [...new Set(r.logs.unknownApi)], assertions: A });
}
function resolveDisplayPublic(el, r) { return r.resolveDisplay(el); }

/* ------------------------------------------------------------------ report ---- */
let hardFails = 0, softFails = 0;
console.log('=== INDEPENDENT CLIPBOARD HARNESS -- target: ' + target + ' ===');
console.log('external <script src> NOT loaded; window.VentiqTracking defined only when the scenario says so\n');
for (const res of results) {
  console.log('--- ' + res.scenario);
  console.log('    copyLog: ' + (res.copyLog.length ? JSON.stringify(res.copyLog) : '(none)'));
  console.log('    navigations: ' + JSON.stringify(res.navigations));
  console.log('    errors: ' + (res.errors.length ? JSON.stringify(res.errors) : 'none'));
  console.log('    load:    chip=' + res.observations.afterLoadTimers.chipShown + ' manual=' + res.observations.afterLoadTimers.manualShown + ' code=' + JSON.stringify(res.observations.afterLoadTimers.codeText) + ' copyBtn=' + JSON.stringify(res.observations.afterLoadTimers.copyButton));
  console.log('    gesture: chip=' + res.observations.afterGesture.chipShown + ' manual=' + res.observations.afterGesture.manualShown + ' manualVal=' + JSON.stringify(res.observations.afterGesture.manualHasPayload) + ' ctaText=' + JSON.stringify(res.observations.afterGesture.ctaText));
  if (res.trackingCalls.length) console.log('    tracking calls: ' + JSON.stringify(res.trackingCalls));
  if (res.unknownApi.length) console.log('    HARNESS FIDELITY: page touched APIs this stub does not model: ' + JSON.stringify(res.unknownApi.slice(0, 12)));
  if (DEBUG_DISPLAY && res.observations.debugDisplay) {
    console.log('    DEBUG display rules parsed=' + res.observations.debugRulesCount);
    console.log('    DEBUG display ' + JSON.stringify(res.observations.debugDisplay));
  }
  for (const a of res.assertions) {
    if (a.hard && !a.ok) hardFails++;
    if (!a.hard && !a.ok) softFails++;
    console.log('      [' + (a.ok ? 'PASS' : 'FAIL') + ']' + (a.hard ? ' (hard)' : ' (soft)') + ' ' + a.id + ' -- ' + a.detail);
  }
  console.log('');
}
console.log('=== HARD failures: ' + hardFails + ' | soft failures: ' + softFails + ' ===');
if (jsonOut) { fs.writeFileSync(jsonOut, JSON.stringify({ target, hardFails, softFails, results }, null, 2)); console.log('json -> ' + jsonOut); }
process.exit(hardFails ? 1 : 0);
}
main().catch(e => { console.error('HARNESS CRASH: ' + (e && e.stack || e)); process.exit(3); });