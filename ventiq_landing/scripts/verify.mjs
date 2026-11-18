/**
 * ============================================================================
 * VERIFICADOR DEL LANDING · ventiq_landing
 * ----------------------------------------------------------------------------
 * Uso:  node scripts/verify.mjs
 *
 * Comprueba, sin dependencias externas:
 *   1. Que todos los enlaces/enlaces de assets internos existan en disco.
 *   2. Que ningún HTML tenga etiquetas desbalanceadas.
 *   3. Que no haya ids duplicados dentro de una página.
 *   4. Que el CSS tenga llaves balanceadas.
 *   5. Que todos los APK referenciados estén en el catálogo (y por tanto en el bucket).
 *   6. Que no queden enlaces rotos conocidos (p. ej. vendedor.apk).
 *
 * Sale con código 1 si encuentra errores.
 * ============================================================================
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { APPS, EXTRA_APKS, SITE } from './apps.data.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const errors = [];
const warnings = [];
const checks = [];

const rel = (p) => path.relative(ROOT, p).replace(/\\/g, '/');

const htmlFiles = [];
const walk = (dir) => {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name.startsWith('.') || entry.name === 'node_modules') continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) walk(full);
    else if (entry.name.endsWith('.html')) htmlFiles.push(full);
  }
};
walk(ROOT);

/* ------------------------------------------------------------------ 1+3+6 */

const VOID = new Set([
  'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input', 'link', 'meta',
  'param', 'source', 'track', 'wbr', '!doctype',
]);

const stripBlocks = (html) =>
  html
    .replace(/<script\b[\s\S]*?<\/script>/gi, '<script></script>')
    .replace(/<style\b[\s\S]*?<\/style>/gi, '<style></style>')
    .replace(/<!--[\s\S]*?-->/g, '');

const knownApks = new Set(
  [
    ...APPS.flatMap((a) => a.downloads.filter((d) => d.kind === 'apk').map((d) => d.href)),
    ...EXTRA_APKS.map((x) => SITE.apkBase + encodeURIComponent(x.file)),
  ].map((u) => decodeURIComponent(u)),
);

for (const file of htmlFiles) {
  const html = fs.readFileSync(file, 'utf8');
  const page = rel(file);

  /* --- enlaces e imágenes --- */
  const refs = [
    ...html.matchAll(/\b(?:href|src|poster|data-src)\s*=\s*"([^"]+)"/g),
    ...html.matchAll(/\b(?:href|src)\s*=\s*'([^']+)'/g),
  ].map((m) => m[1]);

  for (const raw of refs) {
    if (!raw) continue;
    if (/^(https?:|mailto:|tel:|#|data:|javascript:)/i.test(raw)) continue;

    const [clean] = raw.split('#');
    if (!clean) continue;
    const target = path.resolve(path.dirname(file), decodeURIComponent(clean));
    if (!fs.existsSync(target)) {
      errors.push(`${page}: enlace roto → ${raw}`);
    }
  }

  /* --- etiquetas balanceadas --- */
  const stack = [];
  const tags = stripBlocks(html).matchAll(/<(\/?)([a-zA-Z!][a-zA-Z0-9:-]*)([^>]*?)(\/?)>/g);
  for (const m of tags) {
    const [, closing, rawName, , selfClose] = m;
    const name = rawName.toLowerCase();
    if (VOID.has(name) || selfClose === '/') continue;
    if (name === 'html' || name === 'body' || name === 'head') {
      // se validan igual, pero se ignoran minúsculos desajustes de cierre
    }
    if (!closing) stack.push(name);
    else {
      const open = stack.pop();
      if (open !== name) {
        errors.push(`${page}: etiqueta mal cerrada </${name}> (esperaba </${open || 'nada'}>)`);
        // recuperación: si el nombre existe más abajo en la pila, desapila hasta él
        const idx = stack.lastIndexOf(name);
        if (idx !== -1) stack.length = idx;
      }
    }
  }
  if (stack.length) errors.push(`${page}: etiquetas sin cerrar → ${stack.slice(-5).join(', ')}`);

  /* --- ids duplicados --- */
  const ids = [...html.matchAll(/\bid\s*=\s*"([^"]+)"/g)].map((m) => m[1]);
  const dupes = ids.filter((id, i) => ids.indexOf(id) !== i);
  if (dupes.length) errors.push(`${page}: id duplicado(s) → ${[...new Set(dupes)].join(', ')}`);

  /* --- APK referenciados --- */
  const apkUrls = [...html.matchAll(/https:\/\/[^"'\s]+\.apk/g)].map((m) => m[0]);
  for (const url of apkUrls) {
    if (!knownApks.has(decodeURIComponent(url))) {
      errors.push(`${page}: APK fuera del catálogo → ${url}`);
    }
  }

  /* --- enlaces roto conocidos --- */
  if (/\/vendedor\.apk/.test(html)) errors.push(`${page}: enlace roto vendedor.apk (usa inventtia caja.apk)`);

  /* --- accesibilidad básica --- */
  const imgs = [...html.matchAll(/<img\b[^>]*>/g)].map((m) => m[0]);
  for (const img of imgs) {
    if (!/\balt\s*=/.test(img)) warnings.push(`${page}: <img> sin alt → ${img.slice(0, 80)}`);
  }
  if (!/<meta\s+name="viewport"/.test(html)) errors.push(`${page}: falta meta viewport`);
  if (!/<html\s+lang=/.test(html)) errors.push(`${page}: falta lang en <html>`);

  const h1s = (html.match(/<h1\b/g) || []).length;
  if (h1s !== 1) warnings.push(`${page}: ${h1s} <h1> (conviene exactamente 1)`);

  // Los titulares con <em> necesitan fixes.css: sin él vuelve el
  // background-clip que recortaba los descendentes ("empezar", "respuesta").
  const usaTitularConEnfasis =
    /class="[^"]*\bv2-h\b/.test(html) || /class="[^"]*\bapp-head\b/.test(html) || /class="[^"]*\bv2-hero-inner\b/.test(html);
  if (usaTitularConEnfasis && !/assets\/css\/fixes\.css/.test(html)) {
    errors.push(`${page}: usa titulares con énfasis pero no carga assets/css/fixes.css`);
  }

  const title = (html.match(/<title>([\s\S]*?)<\/title>/) || [])[1] || '';
  if (title.length > 78) warnings.push(`${page}: title de ${title.length} caracteres (SEO recomienda ≤ 60–70)`);
}

checks.push(`${htmlFiles.length} páginas HTML revisadas`);

/* --------------------------------------------------------------- 4. CSS */

const cssFiles = fs
  .readdirSync(path.join(ROOT, 'assets', 'css'))
  .filter((f) => f.endsWith('.css'))
  .map((f) => path.join(ROOT, 'assets', 'css', f));

for (const file of cssFiles) {
  const css = fs.readFileSync(file, 'utf8');
  const open = (css.match(/{/g) || []).length;
  const close = (css.match(/}/g) || []).length;
  if (open !== close) errors.push(`${rel(file)}: llaves desbalanceadas (${open} { / ${close} })`);

  // Reglas que rompían el móvil no deben reaparecer sin media query.
  if (/\.v2-eyebrow\s*{[^}]*width:\s*max-content/.test(css) && file.includes('responsive')) {
    errors.push(`${rel(file)}: .v2-eyebrow volvió a width:max-content`);
  }
}

checks.push(`${cssFiles.length} hojas CSS revisadas`);

/* --------------------------------------------------- 5. APK del catálogo */

checks.push(`APK en el catálogo: ${knownApks.size}`);

/* ---------------------------------------------------------------- salida */

console.log('\n=== VERIFICACIÓN DEL LANDING ===\n');
checks.forEach((c) => console.log('  ✓ ' + c));

if (warnings.length) {
  console.log(`\nAvisos (${warnings.length}):`);
  warnings.forEach((w) => console.log('  ! ' + w));
}

if (errors.length) {
  console.log(`\nERRORES (${errors.length}):`);
  errors.forEach((e) => console.log('  ✗ ' + e));
  process.exit(1);
}

console.log('\nTodo correcto: 0 errores.\n');