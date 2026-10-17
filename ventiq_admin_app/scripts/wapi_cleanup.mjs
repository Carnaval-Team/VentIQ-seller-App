#!/usr/bin/env node
// =============================================================================
//  wapi_cleanup.mjs — Limpieza de la bitácora WAPI (OpenWA) y de las
//  "tareas pendientes" que dejan las tandas de difusión a medias.
//
//  QUÉ LIMPIA
//    1. `app_wapi_envio_log` — la bitácora de mensajes. 565 filas en
//       `pendiente` + 4.995 en `fallido` hacen que la app muestre decenas de
//       tandas "interrumpidas" con botón *Reanudar*, aunque ya no haya nada
//       que reanudar. Este script las borra (o las borra todas, con --logs).
//    2. `app_wapi_sesion.last_qr_image` — el QR vive ahí como data-URI base64
//       (decenas de KB por sesión). Con `--qr` se vacía.
//
//  QUÉ **NO** HACE
//    No toca las sesiones en el servidor OpenWA, ni las programaciones, ni los
//    destinatarios. Tampoco borra los logs de infraestructura de Postgres
//    (`net._http_response`, `cron.job_run_details`): para eso está el SQL que
//    acompaña a este script, ver `ventiq_admin_app/sql/wapi_cleanup.sql`.
//
//  SEGURIDAD
//    · Por defecto corre en **dry-run**: sólo cuenta y reporta. Nada se borra
//      hasta que pases `--apply` explícitamente.
//    · Los borrados se hacen en lotes por ventanas de `id`, así que una tabla
//      de millones de filas no abre una transacción gigante ni tumba PostgREST.
//    · Requiere la service_role key (bypassa RLS). NO la escribas en el repo:
//      pásala por variable de entorno.
//
//  USO
//    # 1) Informe (no borra nada). Es lo que se corre para mirar primero:
//    node ventiq_admin_app/scripts/wapi_cleanup.mjs
//
//    # 2) Borrar sólo las tareas pendientes de la tienda 177:
//    node ventiq_admin_app/scripts/wapi_cleanup.mjs --pendientes --tienda 177 --apply
//
//    # 3) Vaciar TODA la bitácora + los QR guardados:
//    node ventiq_admin_app/scripts/wapi_cleanup.mjs --all --apply
//
//    # 4) Retención: conservar 30 días de bitácora:
//    node ventiq_admin_app/scripts/wapi_cleanup.mjs --logs --older-than 30 --apply
//
//  CREDENCIALES (en este orden)
//    · --url / --key
//    · SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
//    · WAPI_SUPABASE_URL / WAPI_SERVICE_ROLE_KEY
//    · --env-file <ruta>  (archivo KEY=VALUE, se ignoran # y líneas vacías)
//
//  Node 18+ (usa fetch global). Sin dependencias.
// =============================================================================

import fs from "node:fs";
import path from "node:path";
import process from "node:process";

// -----------------------------------------------------------------------------
//  Argumentos
// -----------------------------------------------------------------------------
const USAGE = `wapi_cleanup.mjs — limpieza de la bitácora WAPI y tareas pendientes

Objetivos (elige uno o varios; por defecto: --pendientes)
  --pendientes        Borra app_wapi_envio_log con estado='pendiente'
  --fallidos          Borra app_wapi_envio_log con estado='fallido'
  --enviados          Borra app_wapi_envio_log con estado='enviado'
  --logs              Borra TODA la bitácora app_wapi_envio_log
  --qr                Vacia app_wapi_sesion.last_qr_image
  --all               --logs + --qr

Filtros y ajustes
  --older-than DAYS   Sólo filas con created_at anterior a now()-DAYS
  --tienda ID         Sólo esa tienda
  --sesion ID         Sólo esa sesión
  --batch N           Filas por lote de borrado (default 5000)
  --apply             Ejecuta de verdad (sin esto: DRY-RUN, no borra nada)
  --json              Salida en JSON
  --help              Esta ayuda

Credenciales
  --url URL  --key KEY  --env-file RUTA
  o las variables SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY
     (o WAPI_SUPABASE_URL / WAPI_SERVICE_ROLE_KEY)
`;

function parseArgs(argv) {
  const o = {
    targets: new Set(),
    apply: false,
    json: false,
    help: false,
    olderThanDays: null,
    tienda: null,
    sesion: null,
    batch: 5000,
    url: null,
    key: null,
    envFile: null,
  };
  const need = (i, name) => {
    if (i + 1 >= argv.length) {
      throw new Error(`Falta el valor de ${name}`);
    }
    return argv[i + 1];
  };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    switch (a) {
      case "--pendientes": o.targets.add("pendientes"); break;
      case "--fallidos": o.targets.add("fallidos"); break;
      case "--enviados": o.targets.add("enviados"); break;
      case "--logs": o.targets.add("logs"); break;
      case "--qr": o.targets.add("qr"); break;
      case "--all": o.targets.add("logs"); o.targets.add("qr"); break;
      case "--apply": o.apply = true; break;
      case "--json": o.json = true; break;
      case "--help":
      case "-h": o.help = true; break;
      case "--older-than": o.olderThanDays = Number(need(i, a)); i++; break;
      case "--tienda": o.tienda = Number(need(i, a)); i++; break;
      case "--sesion": o.sesion = Number(need(i, a)); i++; break;
      case "--batch": o.batch = Number(need(i, a)); i++; break;
      case "--url": o.url = need(i, a); i++; break;
      case "--key": o.key = need(i, a); i++; break;
      case "--env-file": o.envFile = need(i, a); i++; break;
      default:
        throw new Error(`Argumento desconocido: ${a}`);
    }
  }
  if (o.targets.size === 0) o.targets.add("pendientes");
  if (o.targets.has("logs")) {
    o.targets.add("pendientes");
    o.targets.add("fallidos");
    o.targets.add("enviados");
  }
  if (o.olderThanDays != null && (!Number.isFinite(o.olderThanDays) || o.olderThanDays < 0)) {
    throw new Error("--older-than debe ser un número de días >= 0");
  }
  if (!Number.isFinite(o.batch) || o.batch < 1) {
    throw new Error("--batch debe ser un entero >= 1");
  }
  return o;
}

// -----------------------------------------------------------------------------
//  Configuración (URL + service_role)
// -----------------------------------------------------------------------------
function loadEnvFile(file) {
  const abs = path.resolve(file);
  if (!fs.existsSync(abs)) throw new Error(`--env-file no existe: ${abs}`);
  const out = {};
  for (const linea of fs.readFileSync(abs, "utf8").split(/\r?\n/)) {
    const t = linea.trim();
    if (!t || t.startsWith("#")) continue;
    const eq = t.indexOf("=");
    if (eq < 0) continue;
    let v = t.slice(eq + 1).trim();
    if ((v.startsWith('"') && v.endsWith('"')) || (v.startsWith("'") && v.endsWith("'"))) {
      v = v.slice(1, -1);
    }
    out[t.slice(0, eq).trim()] = v;
  }
  return out;
}

function resolveConfig(o) {
  const fromFile = o.envFile ? loadEnvFile(o.envFile) : {};
  const pick = (...names) => {
    for (const n of names) {
      if (fromFile[n]) return fromFile[n];
      if (process.env[n]) return process.env[n];
    }
    return null;
  };
  const url = (o.url ?? pick("SUPABASE_URL", "WAPI_SUPABASE_URL") ?? "").replace(/\/+$/, "");
  const key = o.key ?? pick("SUPABASE_SERVICE_ROLE_KEY", "WAPI_SERVICE_ROLE_KEY");

  if (!url || !key) {
    const faltan = [
      !url ? "URL del proyecto" : null,
      !key ? "service_role key" : null,
    ].filter(Boolean).join(" y ");
    throw new Error(
      `Faltan credenciales: ${faltan}.\n` +
        `  Pásalas por entorno o por flag, p.ej.:\n` +
        `    $env:SUPABASE_URL="https://<ref>.supabase.co"; ` +
        `$env:SUPABASE_SERVICE_ROLE_KEY="<key>"; node ventiq_admin_app/scripts/wapi_cleanup.mjs\n` +
        `  (o usa --url / --key / --env-file)`,
    );
  }
  return { url, key };
}

// -----------------------------------------------------------------------------
//  Cliente PostgREST mínimo
// -----------------------------------------------------------------------------
function makeClient({ url, key }) {
  const base = `${url}/rest/v1`;

  async function call(pathAndQuery, init = {}) {
    const res = await fetch(`${base}${pathAndQuery}`, {
      ...init,
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        ...(init.headers ?? {}),
      },
    });
    if (!res.ok) {
      const body = await res.text().catch(() => "");
      throw new Error(`PostgREST ${init.method ?? "GET"} ${pathAndQuery} → ${res.status}: ${body.slice(0, 300)}`);
    }
    return res;
  }

  /** Cuenta filas sin traerlas. Devuelve null si PostgREST no reporta conteo. */
  async function count(table, filters) {
    const qs = buildQuery([...filters, ["select", "id"], ["limit", "1"]]);
    const res = await call(`/${table}${qs}`, {
      headers: { Prefer: "count=exact" },
    });
    const rango = res.headers.get("content-range") ?? "";
    const total = Number(rango.split("/")[1]);
    return Number.isFinite(total) ? total : null;
  }

  /** Trae filas (paginado). */
  async function select(table, columns, filters, extra = []) {
    const qs = buildQuery([...filters, ["select", columns], ...extra]);
    const res = await call(`/${table}${qs}`);
    return await res.json();
  }

  async function deleteWhere(table, filters, { limit } = {}) {
    const q = [...filters];
    if (limit) q.push(["limit", String(limit)]);
    const qs = buildQuery([...q, ["select", "id"]]);
    const res = await call(`/${table}${qs}`, {
      method: "DELETE",
      headers: { Prefer: "count=exact, return=representation" },
    });
    const cuerpo = await res.json().catch(() => []);
    const rango = res.headers.get("content-range") ?? "";
    const total = Number(rango.split("/")[1]);
    return {
      borrados: Number.isFinite(total) ? total : (Array.isArray(cuerpo) ? cuerpo.length : 0),
      ids: Array.isArray(cuerpo) ? cuerpo.map((r) => Number(r.id)) : [],
    };
  }

  async function updateWhere(table, values, filters) {
    const qs = buildQuery([...filters, ["select", "id"]]);
    const res = await call(`/${table}${qs}`, {
      method: "PATCH",
      headers: { Prefer: "count=exact, return=representation" },
      body: JSON.stringify(values),
    });
    const cuerpo = await res.json().catch(() => []);
    const rango = res.headers.get("content-range") ?? "";
    const total = Number(rango.split("/")[1]);
    return Number.isFinite(total) ? total : (Array.isArray(cuerpo) ? cuerpo.length : 0);
  }

  return { call, count, select, deleteWhere, updateWhere };
}

function buildQuery(pairs) {
  const partes = pairs
    .filter(([, v]) => v !== undefined && v !== null && v !== "")
    .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`);
  return partes.length ? `?${partes.join("&")}` : "";
}

// -----------------------------------------------------------------------------
//  Borrado por ventanas de id
//  PostgREST no garantiza `LIMIT` en DELETE, así que en vez de fiarnos de eso
//  partimos el rango [minId, maxId] en ventanas y borramos cada una. Es
//  idempotente: repetir el script hasta que el conteo llegue a 0.
// -----------------------------------------------------------------------------
async function purgeByWindows(client, table, filters, { batch, dryRun, log }) {
  const total = await client.count(table, filters);
  if (dryRun) return { total: total ?? 0, borrados: 0, lotes: 0 };
  if (!total) return { total: 0, borrados: 0, lotes: 0 };

  // Límites reales del conjunto filtrado.
  const min = await client.select(table, "id", filters, [["order", "id.asc"], ["limit", "1"]]);
  const max = await client.select(table, "id", filters, [["order", "id.desc"], ["limit", "1"]]);
  let cursor = Number(min?.[0]?.id);
  const maxId = Number(max?.[0]?.id);
  if (!Number.isFinite(cursor) || !Number.isFinite(maxId)) {
    return { total, borrados: 0, lotes: 0 };
  }

  let borrados = 0;
  let lotes = 0;
  // Ventana adaptativa: arranca en `batch` y se estira hasta 20x si un lote
  // sale "lleno" (señal de que el rango de ids es denso y conviene acelerar).
  let ventana = batch;
  while (cursor <= maxId) {
    const fin = Math.min(maxId, cursor + ventana - 1);
    const { borrados: n } = await client.deleteWhere(
      table,
      [...filters, ["id", `gte.${cursor}`], ["id", `lte.${fin}`]],
    );
    borrados += n;
    lotes++;
    log(`      lote ${String(lotes).padStart(3)} · ids ${cursor}–${fin} · borradas ${n} (acumulado ${borrados})`);
    if (n >= Math.floor(ventana * 0.9) && ventana < batch * 20) ventana = Math.min(batch * 20, ventana * 2);
    cursor = fin + 1;
  }
  return { total, borrados, lotes };
}

// -----------------------------------------------------------------------------
//  Programa
// -----------------------------------------------------------------------------
const ESTADOS = ["pendiente", "fallido", "enviado"];

function filtrosBase(o) {
  const f = [];
  if (o.tienda != null) f.push(["id_tienda", `eq.${o.tienda}`]);
  if (o.sesion != null) f.push(["id_sesion", `eq.${o.sesion}`]);
  return f;
}

function filtroAntiguedad(o) {
  if (o.olderThanDays == null) return [];
  const corte = new Date(Date.now() - o.olderThanDays * 86_400_000).toISOString();
  return [["created_at", `lt.${corte}`]];
}

async function inventario(client, o) {
  const base = filtrosBase(o);
  const inv = { total: await client.count("app_wapi_envio_log", base), por_estado: {} };
  for (const e of ESTADOS) {
    inv.por_estado[e] = await client.count("app_wapi_envio_log", [...base, ["estado", `eq.${e}`]]);
  }
  if (o.olderThanDays != null) {
    const anti = filtroAntiguedad(o);
    inv.dentro_de_la_ventana = await client.count("app_wapi_envio_log", [...base, ...anti]);
  }
  // Detalle de "tareas pendientes": qué tiendas/sesiones/tandas las generan.
  inv.pendientes_por_origen = await client.select(
    "app_wapi_envio_log",
    "id_tienda,id_sesion,id_programacion,tipo_envio",
    [...base, ["estado", "eq.pendiente"]],
  );
  return inv;
}

function planDeBorrado(o) {
  const f = filtrosBase(o);
  const anti = filtroAntiguedad(o);
  const plan = [];
  // --logs borra todo: un único barrido sin filtro de estado (más simple y más
  // rápido que tres borrados por estado que dejan la tabla con las mismas filas
  // si algo falla a mitad).
  if (o.targets.has("logs")) {
    plan.push({ etiqueta: "TODA la bitácora (app_wapi_envio_log)", table: "app_wapi_envio_log", filtros: [...f, ...anti] });
  } else {
    for (const e of ESTADOS) {
      if (!o.targets.has(e + "s")) continue;
      plan.push({
        etiqueta: `bitácora estado='${e}'`,
        table: "app_wapi_envio_log",
        filtros: [...f, ["estado", `eq.${e}`], ...anti],
      });
    }
  }
  return plan;
}

async function main() {
  let o;
  try {
    o = parseArgs(process.argv.slice(2));
  } catch (e) {
    console.error(`\n✖ ${e.message}\n\n${USAGE}`);
    process.exit(2);
  }
  if (o.help) {
    console.log(USAGE);
    return;
  }

  const cfg = resolveConfig(o);
  const client = makeClient(cfg);
  const dryRun = !o.apply;
  const out = {
    modo: dryRun ? "DRY-RUN (no se borra nada)" : "APPLY (borrado real)",
    proyecto: cfg.url,
    filtros: {
      tienda: o.tienda,
      sesion: o.sesion,
      older_than_days: o.olderThanDays,
    },
    objetivos: [...o.targets].sort(),
    inventario: null,
    acciones: [],
  };

  const log = (m) => {
    if (!o.json) console.log(m);
  };

  log("");
  log("═══════════════════════════════════════════════════════════════════════");
  log(`  Limpieza WAPI · ${out.modo}`);
  log(`  Proyecto: ${cfg.url}`);
  log(`  Filtros : tienda=${o.tienda ?? "(todas)"} sesion=${o.sesion ?? "(todas)"} ` +
      `antigüedad=${o.olderThanDays != null ? `>${o.olderThanDays}d` : "(sin corte)"}`);
  log("═══════════════════════════════════════════════════════════════════════");

  // ── Inventario ────────────────────────────────────────────────────────────
  log("\n▸ Inventario de app_wapi_envio_log");
  const inv = await inventario(client, o);
  out.inventario = {
    total: inv.total,
    por_estado: inv.por_estado,
    dentro_de_la_ventana: inv.dentro_de_la_ventana ?? null,
  };
  log(`    total .......... ${fmt(inv.total)}`);
  for (const e of ESTADOS) log(`    ${e.padEnd(10)} ... ${fmt(inv.por_estado[e])}`);
  if (inv.dentro_de_la_ventana != null) {
    log(`    dentro del corte (--older-than) ... ${fmt(inv.dentro_de_la_ventana)}`);
  }

  // Tareas pendientes: en la app cada fila `pendiente` sin actividad >10 min se
  // pinta como tanda "interrumpida" con botón Reanudar. Resumimos el origen.
  const pend = inv.pendientes_por_origen ?? [];
  if (pend.length > 0) {
    const porTienda = new Map();
    for (const r of pend) {
      const k = `${r.id_tienda}`;
      const v = porTienda.get(k) ?? { tienda: r.id_tienda, n: 0, sesiones: new Set(), programado: 0 };
      v.n++;
      if (r.id_sesion != null) v.sesiones.add(r.id_sesion);
      if (r.tipo_envio === "programado") v.programado++;
      porTienda.set(k, v);
    }
    log("\n    Detalle de tareas pendientes (lo que la app muestra como 'interrumpida'):");
    for (const v of [...porTienda.values()].sort((a, b) => b.n - a.n)) {
      log(`      tienda ${v.tienda}: ${fmt(v.n)} pendientes · sesiones [${[...v.sesiones].join(", ") || "-"}] · programados ${v.programado}`);
    }
  }

  // QR guardados.
  if (o.targets.has("qr")) {
    log("\n▸ Inventario de app_wapi_sesion.last_qr_image");
    const f = [];
    if (o.tienda != null) f.push(["id_tienda", `eq.${o.tienda}`]);
    if (o.sesion != null) f.push(["id", `eq.${o.sesion}`]);
    const conQr = await client.count("app_wapi_sesion", [...f, ["last_qr_image", "not.is.null"]]);
    out.inventario.qr_sesiones = conQr;
    log(`    sesiones con QR guardado ... ${fmt(conQr)}`);
  }

  // ── Plan ──────────────────────────────────────────────────────────────────
  const plan = planDeBorrado(o);
  log("\n▸ Plan");
  if (plan.length === 0 && !o.targets.has("qr")) {
    log("    (sin objetivos que ejecutar)");
  }
  for (const p of plan) log(`    · borrar ${p.etiqueta}`);
  if (o.targets.has("qr")) log("    · vaciar app_wapi_sesion.last_qr_image");

  // ── Ejecución ─────────────────────────────────────────────────────────────
  for (const p of plan) {
    const n = await client.count(p.table, p.filtros);
    log(`\n▸ ${p.etiqueta}`);
    log(`    filas a borrar: ${fmt(n)}`);
    if (dryRun) {
      out.acciones.push({ objetivo: p.etiqueta, filas: n ?? 0, borrados: 0, dry_run: true });
      continue;
    }
    const r = await purgeByWindows(client, p.table, p.filtros, { batch: o.batch, dryRun, log });
    log(`    ✔ borradas ${fmt(r.borrados)} en ${r.lotes} lote(s)`);
    out.acciones.push({ objetivo: p.etiqueta, filas: r.total, borrados: r.borrados, lotes: r.lotes, dry_run: false });
  }

  if (o.targets.has("qr")) {
    const f = [];
    if (o.tienda != null) f.push(["id_tienda", `eq.${o.tienda}`]);
    if (o.sesion != null) f.push(["id", `eq.${o.sesion}`]);
    const filtros = [...f, ["last_qr_image", "not.is.null"]];
    if (dryRun) {
      const n = await client.count("app_wapi_sesion", filtros);
      log(`\n▸ QR guardado\n    sesiones a limpiar: ${fmt(n)}`);
      out.acciones.push({ objetivo: "app_wapi_sesion.last_qr_image", filas: n ?? 0, borrados: 0, dry_run: true });
    } else {
      const n = await client.updateWhere("app_wapi_sesion", { last_qr_image: null }, filtros);
      log(`\n▸ QR guardado\n    ✔ ${fmt(n)} sesión(es) limpiada(s)`);
      out.acciones.push({ objetivo: "app_wapi_sesion.last_qr_image", borrados: n, dry_run: false });
    }
  }

  // ── Cierre ────────────────────────────────────────────────────────────────
  if (dryRun) {
    log("\n───────────────────────────────────────────────────────────────────────");
    log("  DRY-RUN: no se borró nada. Para ejecutar de verdad añade --apply.");
    log("  Sugerencia: `--all --apply` vacía bitácora + QR.");
    log("───────────────────────────────────────────────────────────────────────");
  } else {
    const restante = await client.count("app_wapi_envio_log", filtrosBase(o));
    log("\n───────────────────────────────────────────────────────────────────────");
    log(`  ✔ Limpieza aplicada. Filas restantes en la bitácora: ${fmt(restante)}`);
    log("  Recuerda: los logs de infraestructura (net._http_response,");
    log("  cron.job_run_details) se limpian con ventiq_admin_app/sql/wapi_cleanup.sql");
    log("───────────────────────────────────────────────────────────────────────");
    out.restante = restante;
  }

  if (o.json) console.log(JSON.stringify(out, null, 2));
}

function fmt(n) {
  if (n == null) return "?";
  return n.toLocaleString("es-ES");
}

main().catch((e) => {
  console.error(`\n✖ ${e.message}`);
  process.exit(1);
});