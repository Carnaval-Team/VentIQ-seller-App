#!/usr/bin/env node
/**
 * Diagnóstico: ¿por qué `send-image` devuelve HTTP 500 mientras `send-text` funciona?
 *
 * Este script NO manda mensajes a destinatarios reales salvo que se pase
 * explícitamente --chat <id> y --live. Por defecto usa un chatId inexistente
 * (`000000000000000000@c.us`) para provocar el fallo sin publicar nada.
 *
 * Uso:
 *   node scripts/diag_openwa_send_image.mjs urls      # inspecciona las imágenes
 *   node scripts/diag_openwa_send_image.mjs infra     # versión/engine/config del server
 *   node scripts/diag_openwa_send_image.mjs fetch     # ¿puede el server bajar la URL?
 *   node scripts/diag_openwa_send_image.mjs send      # reproducción del 500 (chat dummy)
 *   node scripts/diag_openwa_send_image.mjs all
 *
 * Env: OWA_BASE, OWA_KEY, OWA_SESSION
 */

// Sin valores por defecto a propósito: la URL del gateway y el id de sesión no
// se versionan. Ejemplo:
//   OWA_BASE=http://<host-del-gateway>:2785 OWA_KEY=owa_... OWA_SESSION=<uuid> node scripts/diag_openwa_send_image.mjs self
const BASE = (process.env.OWA_BASE ?? "").replace(/\/$/, "");
const KEY = process.env.OWA_KEY ?? "";
const SESSION = process.env.OWA_SESSION ?? "";

if (!BASE || !SESSION) {
  console.error("Faltan OWA_BASE y/o OWA_SESSION en el entorno.");
  process.exit(2);
}

const CHAT_DUMMY = "000000000000000000@c.us";

const IMAGES = [
  "https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/product_1771929928176_product_7345_1771929928176.jpg",
  "https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/product_1768173961361_product_5260_1768173961361.jpg",
  "https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/product_1784905034007_product_10447_1784905034007.jpg",
];

/** PNG 1x1 válido (para probar la ruta base64 sin depender de ninguna URL). */
const PNG_1X1_B64 =
  "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFAAH/q842iQAAAABJRU5ErkJggg==";

function log(...a) {
  console.log(...a);
}
function head(t) {
  log(`\n=== ${t} ${"=".repeat(Math.max(0, 62 - t.length))}`);
}

async function req(method, path, body, { key = KEY, timeoutMs = 60_000 } = {}) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${BASE}${path}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        ...(key ? { "X-API-Key": key } : {}),
      },
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });
    const text = await res.text();
    let json = null;
    try {
      json = text ? JSON.parse(text) : null;
    } catch {
      /* respuesta no-JSON */
    }
    return { status: res.status, json, text, headers: Object.fromEntries(res.headers) };
  } catch (err) {
    return { status: 0, error: String(err?.cause?.code ?? err?.name ?? err) };
  } finally {
    clearTimeout(timer);
  }
}

function fmt(r) {
  const body = r.json ? JSON.stringify(r.json) : (r.text ?? "");
  return `${r.status} ${body.slice(0, 600)}${r.error ? ` [${r.error}]` : ""}`;
}

/** Detecta el formato real por los bytes mágicos. */
function magic(buf) {
  const b = Buffer.from(buf);
  if (b.length < 12) return "?";
  if (b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return "jpeg";
  if (b.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return "png";
  if (b.subarray(0, 3).toString("ascii") === "GIF") return "gif";
  if (b.subarray(0, 4).toString("ascii") === "RIFF" && b.subarray(8, 12).toString("ascii") === "WEBP") return "webp";
  if (b.subarray(4, 12).toString("ascii") === "ftypheic" || b.subarray(4, 12).toString("ascii") === "ftypheix") return "heic";
  if (b.subarray(0, 5).toString("ascii") === "%PDF-") return "pdf";
  if (b.subarray(0, 2).toString("ascii") === "BM") return "bmp";
  if (b.subarray(0, 4).toString("ascii") === "II*\u0000" || b.subarray(0, 4).toString("ascii").startsWith("MM")) return "tiff";
  return `desconocido(${[...b.subarray(0, 8)].map((x) => x.toString(16).padStart(2, "0")).join(" ")})`;
}

async function stepUrls() {
  head("Imágenes del producto (lo que ve el servidor OpenWA)");
  for (const url of IMAGES) {
    const nombre = url.split("/").pop();
    try {
      const headRes = await fetch(url, { method: "HEAD" });
      const hdr = {
        status: headRes.status,
        "content-type": headRes.headers.get("content-type"),
        "content-length": headRes.headers.get("content-length"),
        "content-encoding": headRes.headers.get("content-encoding"),
        "cache-control": headRes.headers.get("cache-control"),
      };
      const r = await fetch(url, { headers: { Range: "bytes=0-65535" } });
      const buf = await r.arrayBuffer();
      log(`\n${nombre}`);
      log(`  headers   : ${JSON.stringify(hdr)}`);
      log(`  bytes leidos: ${buf.byteLength}  formato real: ${magic(buf)}`);
    } catch (e) {
      log(`\n${nombre}\n  ERROR local: ${String(e?.cause?.code ?? e)}`);
    }
  }
}

async function stepInfra() {
  head("Versión / engine / config del servidor");
  for (const p of [
    "/api/health",
    "/api/health/ready",
    "/api/infra/status",
    "/api/infra/engines/current",
    "/api/key",
    "/api/infra/config",
  ]) {
    const r = await req("GET", p, undefined, { timeoutMs: 20_000 });
    log(`\nGET ${p} → ${fmt(r).slice(0, 900)}`);
  }
}

async function stepFetch() {
  head("¿Puede el server bajar la URL? (proxy de conversión, no envía nada)");
  // `/media/convert/voice` con la imagen: ffmpeg la rechazará, pero si el fallo es
  // de descarga el mensaje será de fetch, no de ffmpeg. Distingue una cosa de otra.
  for (const url of IMAGES.slice(0, 1)) {
    const r = await req("POST", `/api/sessions/${SESSION}/media/convert/voice`, { url }, { timeoutMs: 60_000 });
    log(`\nPOST media/convert/voice url=${url.split("/").pop()}\n  → ${fmt(r)}`);
  }
  // Control: una URL que no existe debe dar 400 (y así sabemos cómo se ve un fallo de fetch).
  const ctl = await req("POST", `/api/sessions/${SESSION}/media/convert/voice`, {
    url: "https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/NO_EXISTE_XYZ.jpg",
  });
  log(`\nCONTROL url inexistente → ${fmt(ctl)}`);
}

async function stepSessions() {
  head("Sesiones (para sacar el número propio)");
  const r = await req("GET", "/api/sessions");
  log(JSON.stringify(r.json, null, 2));
}

/**
 * Matriz de aislamiento sobre el CHAT PROPIO (`<numero>@c.us`, el "mensaje a ti
 * mismo"). No molesta a ningún cliente y permite separar:
 *   - ¿es el envío de media en general?  (I1..I4)
 *   - ¿es la descarga de la URL?         (I1 vs I2)
 *   - ¿es el mimetype/formato?           (I3 vs I2)
 *   - ¿es sólo imágenes o todo media?    (D1)
 */
async function stepSelf() {
  const self = (process.env.OWA_SELF ?? "").replace(/[^0-9]/g, "");
  if (!self) {
    console.error("Falta OWA_SELF=<numero con código de país, sólo dígitos>");
    process.exit(2);
  }
  const chat = `${self}@c.us`;
  head(`Matriz sobre el chat propio: ${chat}`);

  // JPEG real de uno de los productos (mismo fichero que falla por URL).
  let jpegB64 = "";
  try {
    const r = await fetch(IMAGES[1]);
    jpegB64 = Buffer.from(await r.arrayBuffer()).toString("base64");
  } catch (e) {
    log(`  (no se pudo descargar el JPEG de referencia: ${e})`);
  }

  const casos = [
    { n: "T1 send-text (baseline)", path: "send-text", body: { chatId: chat, text: "diag T1 texto" } },
    { n: "I1 send-image  url (jpeg real)", path: "send-image", body: { chatId: chat, url: IMAGES[1] } },
    { n: "I2 send-image  base64 jpeg real", path: "send-image", body: jpegB64 ? { chatId: chat, base64: jpegB64, mimetype: "image/jpeg", filename: "p.jpg" } : null },
    { n: "I3 send-image  base64 png 1x1", path: "send-image", body: { chatId: chat, base64: PNG_1X1_B64, mimetype: "image/png", filename: "p.png" } },
    {
      n: "I4 send-image  url png servido como .jpg (mime mismatch)",
      path: "send-image",
      body: { chatId: chat, url: IMAGES[0] },
    },
    {
      n: "D1 send-document url (mismo jpeg, como documento)",
      path: "send-document",
      body: { chatId: chat, url: IMAGES[1], filename: "d.jpg", mimetype: "image/jpeg" },
    },
    { n: "T2 send-text (baseline de cierre)", path: "send-text", body: { chatId: chat, text: "diag T2 texto" } },
  ];

  for (const c of casos) {
    if (!c.body) {
      log(`\n${c.n} → (omitido: sin datos)`);
      continue;
    }
    const t0 = Date.now();
    const r = await req("POST", `/api/sessions/${SESSION}/messages/${c.path}`, c.body, { timeoutMs: 90_000 });
    const ms = Date.now() - t0;
    log(`\n${c.n} → ${fmt(r)}   [${ms} ms]`);
  }
}

async function stepSend() {
  head("Reproducción de send-image (chatId inexistente: no se envía nada)");
  const casos = [
    { n: "A. url real del producto", body: { chatId: CHAT_DUMMY, url: IMAGES[0] } },
    { n: "B. url http/https inválida", body: { chatId: CHAT_DUMMY, url: "https://example.invalid/no.jpg" } },
    { n: "C. base64 PNG 1x1", body: { chatId: CHAT_DUMMY, base64: PNG_1X1_B64, mimetype: "image/png" } },
    { n: "D. url real + mimetype explícito", body: { chatId: CHAT_DUMMY, url: IMAGES[0], mimetype: "image/jpeg" } },
    { n: "E. sin url ni base64 (control 400)", body: { chatId: CHAT_DUMMY } },
    { n: "F. payload anidado {image:{url}} (control 400)", body: { chatId: CHAT_DUMMY, image: { url: IMAGES[0] } } },
  ];
  for (const c of casos) {
    const r = await req("POST", `/api/sessions/${SESSION}/messages/send-image`, c.body, { timeoutMs: 60_000 });
    log(`\n${c.n} → ${fmt(r)}`);
  }
  head("Control: send-text al mismo chatId inexistente");
  const t = await req("POST", `/api/sessions/${SESSION}/messages/send-text`, {
    chatId: CHAT_DUMMY,
    text: "diagnostico",
  });
  log(`\nsend-text → ${fmt(t)}`);
}

const steps = process.argv[2] ?? "all";
async function stepStart() {
  head("Arrancar la sesión y esperar a 'ready'");
  const antes = await req("GET", `/api/sessions/${SESSION}`);
  log(`antes → ${fmt(antes)}`);
  const r = await req("POST", `/api/sessions/${SESSION}/start`, undefined, { timeoutMs: 90_000 });
  log(`start → ${fmt(r)}`);
  for (let i = 1; i <= 20; i++) {
    await new Promise((res) => setTimeout(res, 6000));
    const s = await req("GET", `/api/sessions/${SESSION}`);
    const st = s.json?.status;
    log(`[${i}] status=${st}`);
    if (st === "ready") break;
    if (st === "qr_ready") {
      log("  ⚠ pide QR: la sesión perdió la vinculación");
      break;
    }
  }
}

/** Caption EXACTA que envía `wapi-send-products` (emojis, `\n` y hashtag). */
const CAPTION_PROD =
  "🌸 *Bebida Energetica 5 Shot*\n🟢 11,136 disponibles\n💰 $645 CUP\n📦 Presentación: Unidad\n#bebidas";

/**
 * Reproduce la petición EXACTA que fallaba en producción (misma imagen, mismo
 * caption) sobre el chat propio: es la comprobación de aceptación del arreglo.
 */
async function stepCapt() {
  const self = (process.env.OWA_SELF ?? "").replace(/[^0-9]/g, "");
  if (!self) {
    console.error("Falta OWA_SELF=<numero>");
    process.exit(2);
  }
  const chat = `${self}@c.us`;
  head("Payload EXACTO de producción (imagen + caption con emojis)");
  const r = await req(
    "POST",
    `/api/sessions/${SESSION}/messages/send-image`,
    { chatId: chat, url: IMAGES[0], caption: CAPTION_PROD },
    { timeoutMs: 90_000 },
  );
  log(`send-image url+caption → ${fmt(r)}`);
}

const run = {
  urls: stepUrls,
  infra: stepInfra,
  fetch: stepFetch,
  send: stepSend,
  sessions: stepSessions,
  start: stepStart,
  capt: stepCapt,
  self: stepSelf,
  all: async () => {
    await stepUrls();
    await stepInfra();
    await stepFetch();
    await stepSend();
  },
}[steps];

if (!run) {
  console.error(`Paso desconocido: ${steps}`);
  process.exit(2);
}
log(`BASE=${BASE}  SESSION=${SESSION}  KEY=${KEY ? KEY.slice(0, 12) + "…" : "(vacía)"}`);
await run();