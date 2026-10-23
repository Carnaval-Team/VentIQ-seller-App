#!/usr/bin/env node
/* Independent WCAG 2.x contrast calculator (verifier-owned).
   Usage: node contrast.js <spec.json>
   Spec: { "label": "...", "items": [ {id, note, fg, bg, sizePx, bold, backdrop?, bgOverlay?} ] }
   - fg/bg accept #RGB, #RRGGBB, #RRGGBBAA, rgba(r,g,b,a)
   - "backdrop" (optional): opaque colour UNDER a translucent bg.
   - "bgOverlay" (optional): translucent layer painted ON TOP of bg (e.g. hover shine).
   - For gradient contexts, put the WORST-CASE stop in bg (lightest stop for white text).
   - Item may supply bgAlts: [{name,bg}] to evaluate several stops.
   Exit code 1 if any item fails its own threshold. */
'use strict';
const fs = require('fs');

function parseColor(c) {
  c = String(c).trim();
  let m = /^#([0-9a-f]{3,8})$/i.exec(c);
  if (m) {
    let h = m[1];
    if (h.length === 3) h = h.split('').map(x => x + x).join('') + 'ff';
    else if (h.length === 4) h = h.split('').map(x => x + x).join('');
    else if (h.length === 6) h += 'ff';
    if (h.length !== 8) throw new Error('bad hex ' + c);
    return [0, 2, 4].map(i => parseInt(h.slice(i, i + 2), 16)).concat([parseInt(h.slice(6, 8), 16) / 255]);
  }
  m = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)\s*(?:,\s*([\d.]+)\s*)?\)$/i.exec(c);
  if (m) return [+m[1], +m[2], +m[3], m[4] === undefined ? 1 : +m[4]];
  throw new Error('unsupported colour: ' + c);
}
const clamp = v => Math.max(0, Math.min(255, v));
/* source-over composite of translucent fg onto opaque bg; returns opaque rgb */
function over(fg, bg) {
  const a = fg[3];
  return [0, 1, 2].map(i => clamp(fg[i] * a + bg[i] * (1 - a))).concat([1]);
}
function hex(rgb) {
  return '#' + rgb.slice(0, 3).map(v => Math.round(v).toString(16).padStart(2, '0')).join('').toUpperCase();
}
function lum(rgb) {
  const [r, g, b] = rgb.slice(0, 3).map(v => {
    v /= 255;
    return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
  });
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}
function ratio(f, b) {
  const L1 = lum(f), L2 = lum(b);
  return (Math.max(L1, L2) + 0.05) / (Math.min(L1, L2) + 0.05);
}
function threshold(sizePx, bold) {
  // WCAG "large text": >=24px, or >=18.66px when bold
  if (sizePx >= 24 || (bold && sizePx >= 18.66)) return 3.0;
  return 4.5;
}

const specPath = process.argv[2];
if (!specPath) { console.error('usage: node contrast.js <spec.json>'); process.exit(2); }
const spec = JSON.parse(fs.readFileSync(specPath, 'utf8'));
const rows = [];
let fails = 0;
for (const it of spec.items) {
  const fg = parseColor(it.fg);
  const alts = it.bgAlts && it.bgAlts.length ? it.bgAlts : [{ name: '', bg: it.bg }];
  for (const alt of alts) {
    let bg = parseColor(alt.bg);
    if (bg[3] < 1) bg = over(bg, parseColor(it.backdrop || '#FFFFFF'));
    if (it.bgOverlay) bg = over(parseColor(it.bgOverlay), bg);
    const effFg = fg[3] < 1 ? over(fg, bg) : fg;
    const r = ratio(effFg, bg);
    const need = threshold(it.sizePx, it.bold);
    const pass = r + 1e-9 >= need;
    if (!pass) fails++;
    rows.push({
      id: it.id, variant: alt.name, note: it.note || '',
      fg: it.fg + (fg[3] < 1 ? ' -> ' + hex(effFg) : ''),
      bg: alt.bg + (parseColor(alt.bg)[3] < 1 ? ' under/over -> ' + hex(bg) : (it.bgOverlay ? ' + overlay -> ' + hex(bg) : '')),
      size: it.sizePx + 'px' + (it.bold ? ' bold' : ''),
      ratio: r.toFixed(2), need: need.toFixed(1), verdict: pass ? 'PASS' : 'FAIL'
    });
  }
}
console.log('== ' + (spec.label || specPath) + ' ==');
const w = { id: 30, variant: 22, ratio: 6, need: 5, verdict: 7 };
const pad = (s, n) => String(s).padEnd(n).slice(0, n);
console.log(pad('ID', w.id) + pad('VARIANT', w.variant) + pad('RATIO', w.ratio) + pad('NEED', w.need) + pad('VERDICT', w.verdict) + 'FG / BG');
for (const r of rows) {
  console.log(pad(r.id, w.id) + pad(r.variant, w.variant) + pad(r.ratio, w.ratio) + pad(r.need, w.need) + pad(r.verdict, w.verdict) + r.fg + '  on  ' + r.bg + (r.note ? '   [' + r.note + ']' : ''));
}
const worst = rows.slice().sort((a, b) => a.ratio - b.ratio)[0];
console.log('-- items: ' + rows.length + ', failing: ' + fails + ', worst: ' + worst.id + (worst.variant ? '/' + worst.variant : '') + ' = ' + worst.ratio + ':1 (needs ' + worst.need + ')');
console.log('JSON ' + JSON.stringify({ label: spec.label, fails, rows }));
process.exit(fails ? 1 : 0);