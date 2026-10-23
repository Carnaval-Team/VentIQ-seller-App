// Extracts the per-scenario JSON payloads from a probe transcript and prints a
// compact, targeted summary. Usage: node mine-probe.js <probe.txt> [full]
'use strict';
const fs = require('fs');
const p = process.argv[2];
const full = process.argv[3] === 'full';
const buf = fs.readFileSync(p);
const txt = (buf[0] === 0xFF && buf[1] === 0xFE) ? buf.toString('utf16le').replace(/^\uFEFF/, '') : buf.toString('utf8').replace(/^\uFEFF/, '');
const lines = txt.split(/\r?\n/);
let cur = null;
for (let i = 0; i < lines.length; i++) {
  const l = lines[i];
  const m = /^===\s*(.+?)\s*===$/.exec(l);
  if (m) { cur = m[1]; continue; }
  if (!l.trim().startsWith('{')) continue;
  let obj;
  try { obj = JSON.parse(l); } catch (e) { continue; }
  console.log('\n### ' + cur + '   (keys: ' + Object.keys(obj).join(', ') + ')');
  if (full) { console.log(JSON.stringify(obj, null, 1).slice(0, 4000)); continue; }
  // inkmetrics-style
  if (Array.isArray(obj.items)) {
    for (const it of obj.items) {
      const nums = Object.entries(it).filter(([k, v]) => typeof v === 'number' && /deficit|overshoot|excess|clip|ink|miss/i.test(k));
      console.log('  item ' + JSON.stringify({ text: it.text, cls: it.cls, fs: it.fs, fstyle: it.fstyle, ...Object.fromEntries(nums) }));
    }
  }
  if (Array.isArray(obj.stops)) {
    for (const s of obj.stops) {
      const cards = (s.cards || []).map(c => 'c' + c.i + ':pos=' + c.pos + ' op=' + c.opacity + ' prog=' + c.progress + ' t=' + (c.rect && c.rect.t));
      console.log('  stop scrollY=' + s.scrollY + ' | ' + cards.join('  '));
    }
  }
  if (Array.isArray(obj.steps)) {
    console.log('  tops = ' + JSON.stringify(obj.tops));
    for (const s of obj.steps) {
      const cards = (s.cards || []).map(c => 'c' + c.i + ' pos=' + c.pos + ' prog=' + c.prog + ' op=' + c.op + ' tf=' + (c.xf === 'matrix(1, 0, 0, 1, 0, 0)' ? 'none' : c.xf) + ' rectT=' + (c.rect && c.rect.t));
      console.log('  step ' + s.label + ' scrollY=' + s.scrollY + ' | ' + cards.join('  |  '));
    }
  }
  if (Array.isArray(obj.btns)) {
    for (const b of obj.btns) console.log('  btn ' + JSON.stringify(b).slice(0, 220));
  }
  if (Array.isArray(obj.ems)) {
    for (const e of obj.ems) console.log('  em ' + JSON.stringify({ text: e.text, padL: e.padL, padR: e.padR, marginL: e.marginL, scrollW: e.scrollW, clientW: e.clientW, fs: e.fs }).slice(0, 200));
  }
  if (Array.isArray(obj.log)) console.log('  log ' + JSON.stringify(obj.log).slice(0, 600));
  for (const k of ['note', 'verdict', 'raster', 'clip', 'clippedPixels', 'missingPixels', 'manualShown', 'chipShown', 'copyBtnText', 'codeText', 'errorsCount', 'trackingGlobal', 'bodyBg', 'text']) {
    if (obj[k] !== undefined) console.log('  ' + k + ' = ' + JSON.stringify(obj[k]).slice(0, 300));
  }
}