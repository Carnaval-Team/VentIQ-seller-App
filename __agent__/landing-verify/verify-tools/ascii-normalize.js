// Normalizes a text file to pure ASCII (repairs a PowerShell encoding round-trip).
// usage: node ascii-normalize.js <file>
const fs = require('fs');
const p = process.argv[2];
let s = fs.readFileSync(p, 'utf8');
const found = [...new Set(s.match(/[^\x00-\x7F]+/g) || [])];
const map = { '\u00e2\u20ac\u201d': '--', '\u00e2\u20ac\u201c': '-', '\u00e2\u20ac\u2122': "'", '\u00e2\u20ac\u0153': '"', '\u00e2\u20ac\u009d': '"' };
for (const [k, v] of Object.entries(map)) s = s.split(k).join(v);
s = s.replace(/[^\x00-\x7F]/g, '?');
fs.writeFileSync(p, s);
console.log('sequences found: ' + JSON.stringify(found));
console.log('remaining non-ascii: ' + ((s.match(/[^\x00-\x7F]/g) || []).length));