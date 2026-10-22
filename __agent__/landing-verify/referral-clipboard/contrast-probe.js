// Ad-hoc WCAG contrast probe used while choosing r.html tokens.
// Run: node contrast-probe.js
'use strict';

function hex(h) {
  h = String(h).replace('#', '');
  if (h.length === 3) h = h.split('').map(function (c) { return c + c; }).join('');
  return [parseInt(h.substr(0, 2), 16), parseInt(h.substr(2, 2), 16), parseInt(h.substr(4, 2), 16)];
}
function blend(fg, bg, a) {
  return [fg[0] * a + bg[0] * (1 - a), fg[1] * a + bg[1] * (1 - a), fg[2] * a + bg[2] * (1 - a)];
}
function lum(c) {
  var s = c.slice(0, 3).map(function (v) { v /= 255; return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4); });
  return 0.2126 * s[0] + 0.7152 * s[1] + 0.0722 * s[2];
}
function ratio(a, b) {
  var l1 = lum(a), l2 = lum(b);
  if (l2 > l1) { var t = l1; l1 = l2; l2 = t; }
  return (l1 + 0.05) / (l2 + 0.05);
}

var candidates = [
  ['hero hint #C3D4DF on band #0F2438', '#C3D4DF', '#0F2438'],
  ['hero hint #C3D4DF on band #163353', '#C3D4DF', '#163353'],
  ['hero hint #B9CBD9 on band #0F2438', '#B9CBD9', '#0F2438'],
  ['chip code #EAF4F8 on band #163353', '#EAF4F8', '#163353'],
  ['white on navy-700 #1E4A6E', '#FFFFFF', '#1E4A6E'],
  ['card text #3D5366 on white', '#3D5366', '#FFFFFF'],
  ['foot text #3D5366 on paper #F7FAFB', '#3D5366', '#F7FAFB'],
  ['link #2A5F8A on paper #F7FAFB', '#2A5F8A', '#F7FAFB']
];
candidates.forEach(function (row) {
  var r = ratio(hex(row[1]), hex(row[2]));
  console.log((r >= 4.5 ? 'PASS' : 'FAIL') + '  ' + r.toFixed(2).padStart(6) + '  ' + row[0]);
});

// Translucent chips are measured against their real composited background.
var badgeBg = blend(hex('#5EB8D1'), hex('#0F2438'), 0.16);
console.log('badge text #B8E3F0 on cyan 16% over navy-900 = ' + ratio(hex('#B8E3F0'), badgeBg).toFixed(2));
var chipBg = blend(hex('#FFFFFF'), hex('#163353'), 0.06);
console.log('chip text #EAF4F8 on white 6% over navy-800 = ' + ratio(hex('#EAF4F8'), chipBg).toFixed(2));