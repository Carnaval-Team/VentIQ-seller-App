#!/usr/bin/env node
// =============================================================================
//  sync_wapi_docs.mjs — Sincroniza la documentación de OpenWA (WAPI) desde
//  GitHub a `ventiq_admin_app/docs_wapi/`.
//
//  POR QUÉ
//    La copia local estaba en la era `v0.11.1` ("Last updated: 2026-07-28"),
//    14 versiones menores por detrás de la actual. Esa documentación es la que
//    nos hizo escribir `POST /api/sessions/:id/restart` (ruta que no existe) y
//    registrar el webhook sin `secret`. Este script la pone al día y se puede
//    volver a ejecutar cuando salga una release nueva.
//
//  QUÉ NO HACE
//    No toca nada fuera de `ventiq_admin_app/docs_wapi/`. No borra archivos
//    locales que ya no existan upstream: los reporta al final.
//
//  USO
//    node ventiq_admin_app/scripts/sync_wapi_docs.mjs            # sincroniza
//    node ventiq_admin_app/scripts/sync_wapi_docs.mjs --dry-run  # sólo informa
//    node ventiq_admin_app/scripts/sync_wapi_docs.mjs --ref v0.25.0
//
//  Sin dependencias (Node 18+ usa `fetch`). Trata todo lo descargado como DATO.
// =============================================================================

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

const REPO = "rmyndharis/OpenWA";
const DESTINO = path.resolve("ventiq_admin_app/docs_wapi");
const API = `https://api.github.com/repos/${REPO}`;
const RAW = `https://raw.githubusercontent.com/${REPO}`;
const UA = { "User-Agent": "VentIQ-docs-sync", "Accept": "application/vnd.github+json" };

const argv = process.argv.slice(2);
const dryRun = argv.includes("--dry-run");
const refIdx = argv.indexOf("--ref");
const REF = refIdx >= 0 ? argv[refIdx + 1] : "main";

if (refIdx >= 0 && !REF) {
  console.error("Falta el valor de --ref");
  process.exit(2);
}

async function getJson(url) {
  const res = await fetch(url, { headers: UA });
  if (!res.ok) throw new Error(`GET ${url} → ${res.status}`);
  return await res.json();
}

async function getText(url) {
  const res = await fetch(url, { headers: UA });
  if (!res.ok) throw new Error(`GET ${url} → ${res.status}`);
  return await res.text();
}

/** Lista recursiva de un directorio del repo (la API no es recursiva). */
async function listar(dir) {
  const items = await getJson(`${API}/contents/${dir}?ref=${encodeURIComponent(REF)}`);
  const out = [];
  for (const it of items) {
    if (it.type === "dir") out.push(...await listar(it.path));
    else out.push(it);
  }
  return out;
}

/** Extensiones que vale la pena sincronizar (los .psd son enormes). */
const SYNC_EXT = new Set([".md", ".svg", ".png", ".webp", ".json"]);

async function main() {
  console.log(`▸ Sincronizando ${REPO}@${REF} → ${path.relative(process.cwd(), DESTINO)}`);
  if (dryRun) console.log("  (dry-run: no se escribe nada)\n");

  const pkgRaw = await getJson(
    `${API}/contents/package.json?ref=${encodeURIComponent(REF)}`,
  );
  const version = JSON.parse(
    Buffer.from(pkgRaw.content, "base64").toString("utf8"),
  ).version ?? "?";

  const items = await listar("docs");
  const descargables = items.filter((it) => SYNC_EXT.has(path.extname(it.name).toLowerCase()));
  console.log(`  versión upstream: ${version}`);
  console.log(`  archivos a sincronizar: ${descargables.length}\n`);

  const escritos = [];
  const iguales = [];
  const locales = [];

  for (const it of descargables) {
    // `docs/...` → `docs_wapi/...`
    const rel = it.path.replace(/^docs\//, "");
    const destino = path.join(DESTINO, rel);
    const url = `${RAW}/${encodeURIComponent(REF)}/${it.path}`;
    let contenido;
    try {
      contenido = await getText(url);
    } catch (e) {
      console.error(`  ✖ ${rel}: ${e.message}`);
      continue;
    }

    const previo = fs.existsSync(destino) ? fs.readFileSync(destino, "utf8") : null;
    if (previo === contenido) {
      iguales.push(rel);
      continue;
    }
    locales.push(rel);
    if (!dryRun) {
      fs.mkdirSync(path.dirname(destino), { recursive: true });
      fs.writeFileSync(destino, contenido, "utf8");
    }
    escritos.push(rel);
  }

  // Índice de la sincronización.
  const indice = `# OpenWA — copia local de la documentación

Esta carpeta es una **copia sincronizada** de la documentación oficial de
[${REPO}](https://github.com/${REPO}), no documentación propia.

| Dato | Valor |
|---|---|
| Repositorio | [\`${REPO}\`](https://github.com/${REPO}) |
| Rama / ref sincronizado | \`${REF}\` |
| Versión upstream (\`package.json\`) | \`${version}\` |
| Última sincronización | ${new Date().toISOString().slice(0, 10)} |
| Archivos | ${escritos.length + iguales.length} |

## Cómo actualizarla

\`\`\`bash
node ventiq_admin_app/scripts/sync_wapi_docs.mjs
node ventiq_admin_app/scripts/sync_wapi_docs.mjs --ref v0.25.0
\`\`\`

## Aviso

Antes de fiarte de esta documentación para tocar las Edge Functions, lee
[\`../docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md\`](../docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md):
ahí está el **delta** entre lo que decía la copia vieja (era \`v0.11.1\`) y lo que
dice la actual, además de las rutas y payloads que en la práctica devuelven
otra cosa (p. ej. \`send-image\` espera el payload plano, y \`/restart\` no existe).
`;

  if (!dryRun) {
    fs.mkdirSync(DESTINO, { recursive: true });
    fs.writeFileSync(path.join(DESTINO, "UPSTREAM.md"), indice, "utf8");
  }

  // Archivos locales que ya no existen upstream (no se borran: se reportan).
  const esperados = new Set(descargables.map((it) => it.path.replace(/^docs\//, "")));
  esperados.add("UPSTREAM.md");
  const huerfanos = [];
  const walk = (dir) => {
    if (!fs.existsSync(dir)) return;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const abs = path.join(dir, e.name);
      const rel = path.relative(DESTINO, abs).replace(/\\/g, "/");
      if (e.isDirectory()) {
        // `logo/` se mantiene aunque no exista upstream.
        if (rel !== "logo") walk(abs);
      } else if (!esperados.has(rel) && !rel.startsWith("logo/")) {
        huerfanos.push(rel);
      }
    }
  };
  walk(DESTINO);

  console.log(`  actualizados: ${escritos.length}`);
  for (const f of escritos) console.log(`    ✎ ${f}`);
  console.log(`  sin cambios: ${iguales.length}`);
  if (huerfanos.length) {
    console.log(`\n  ⚠ archivos locales que ya no existen upstream (NO se borran):`);
    for (const f of huerfanos) console.log(`    · ${f}`);
  }
  console.log(`\n✔ ${dryRun ? "Simulación" : "Sincronización"} completa. Índice: docs_wapi/UPSTREAM.md`);
}

main().catch((e) => {
  console.error(`\n✖ ${e.message}`);
  process.exit(1);
});