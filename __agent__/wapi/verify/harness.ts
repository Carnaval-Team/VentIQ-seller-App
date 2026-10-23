// GENERADO por build_harness.mjs — NO EDITAR A MANO.
// Fuente: ventiq_admin_app/supabase/functions/wapi-send-products/index.ts
// SHA256 verificado: 814A93D14D04D4DE6F4651360E99F679388BE5C0F70B21283D119FEF4EB7F58C
// Bloques verbatim: bucle L1856+, registrarPendientesPares L1118+, cierre L1971+
/* eslint-disable */

type Par = { idProducto: number; chatId: string };
function clavePar(p: Par): string { return `${p.idProducto}|${p.chatId}`; }
function chunkArray<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

// ─────────────────────────── Mock de Supabase ───────────────────────────
type Fila = { id: number; id_producto: number; chat_id: string; estado: string; error_code?: string | null };
type DB = {
  filas: Fila[];
  inserts: Fila[][];
  updates: Array<{ ids: number[]; patch: any }>;
  fallaInsert: boolean;
  nextId: number;
};
function nuevoDB(): DB {
  return { filas: [], inserts: [], updates: [], fallaInsert: false, nextId: 1000 };
}
function mockAdmin(db: DB) {
  const chain = (_tabla: string) => ({
    insert: (rows: any[]) => {
      db.inserts.push(rows);
      const creadas: Fila[] = db.fallaInsert ? [] : rows.map((r) => {
        const f: Fila = {
          id: db.nextId++, id_producto: r.id_producto, chat_id: r.chat_id,
          estado: r.estado, error_code: null,
        };
        db.filas.push(f);
        return f;
      });
      return {
        select: async (_cols: string) => ({
          data: db.fallaInsert ? null : creadas.map((f) => ({ id: f.id, id_producto: f.id_producto, chat_id: f.chat_id })),
          error: db.fallaInsert ? { message: "insert simulado falla" } : null,
        }),
      };
    },
    update: (patch: any) => ({
      in: async (_col: string, ids: number[]) => {
        db.updates.push({ ids: [...ids], patch });
        for (const f of db.filas) if (ids.includes(f.id)) Object.assign(f, patch);
        return { error: null };
      },
    }),
  });
  return { from: (t: string) => chain(t) };
}

// ───── registrarPendientesPares: cuerpo EXTRAÍDO VERBATIM L1118 ─────
function makeRegistrar(env: any) {
  const admin = env.admin;
  const chatsValidos: string[] = env.chatsValidos;
  const logIdDePar: Map<string, number> = env.logIdDePar;
  const idTienda = 1, idSesion = 1, idProgramacion = null, tipoEnvio = "manual";
  const console = { error: (..._a: any[]) => {}, warn: (..._a: any[]) => {}, log: (..._a: any[]) => {} };
  return async function registrarPendientesPares(pares: Par[], motivo?: { code: string; message: string }): Promise<number[]> {
    if (pares.length === 0 || chatsValidos.length === 0) return [];

    const implicados = new Set<number>();
    const faltantes: Par[] = [];
    for (const par of pares) {
      const id = logIdDePar.get(clavePar(par));
      if (id != null) implicados.add(id);
      else faltantes.push(par);
    }

    if (faltantes.length > 0) {
      const filas = faltantes.map((p) => ({
        id_tienda: idTienda,
        id_sesion: idSesion,
        id_programacion: idProgramacion ?? null,
        id_producto: p.idProducto,
        chat_id: p.chatId,
        tipo_envio: tipoEnvio,
        estado: "pendiente",
      }));
      try {
        for (const lote of chunkArray(filas, 500)) {
          const { data, error } = await admin
            .from("app_wapi_envio_log")
            .insert(lote)
            .select("id, id_producto, chat_id");
          if (error) throw new Error(error.message);
          for (const row of data ?? []) {
            const par: Par = {
              idProducto: Number((row as any).id_producto),
              chatId: String((row as any).chat_id),
            };
            const id = Number((row as any).id);
            logIdDePar.set(clavePar(par), id);
            implicados.add(id);
          }
        }
      } catch (e) {
        console.error(
          `[wapi-send-products] no se pudieron registrar ${faltantes.length} ` +
            `mensaje(s) pendientes: ${(e as Error).message ?? e}`,
        );
      }
    }

    const ids = Array.from(implicados);
    if (motivo && ids.length > 0) {
      for (const lote of chunkArray(ids, 500)) {
        await admin.from("app_wapi_envio_log")
          .update({
            estado: "pendiente",
            error_code: motivo.code,
            error_message: motivo.message,
          })
          .in("id", lote);
      }
    }
    return ids;
  };
}

// ─────────── Bucle principal: EXTRAÍDO VERBATIM L1856 ───────────
async function correrBucle(env: any) {
  const plan: Par[] = env.plan;
  const WORKER_BUDGET_MS: number = env.WORKER_BUDGET_MS;
  const ENTRE_DESTINOS_MS: number = env.ENTRE_DESTINOS_MS ?? 20_000;
  const DESTINO_FALLOS_MAX: number = 3;
  const WINDOW_SIZE: number = 25;
  const minMs: number = env.minMs ?? 0;
  const maxMs: number = env.maxMs ?? 0;
  const effProductIds: number[] = env.effProductIds;
  const posDeProducto: Map<number, number> = env.posDeProducto;
  const descartados: Set<number> = env.descartados;
  const ensureInfo = env.ensureInfo;
  const obtenerProductoListo = env.obtenerProductoListo;
  const dispatchOne = env.dispatchOne;
  const elapsed = env.elapsed;
  const reservaMensajeMs = env.reservaMensajeMs;
  const setTimeout = (fn: any, _ms: number) => globalThis.setTimeout(fn, 0);
  const console = { error: (..._a: any[]) => {}, warn: (..._a: any[]) => {}, log: (..._a: any[]) => {} };

  let mensajesIntentados = 0;
  let enviados = 0;
  let fallidos = 0;
  let pendientesDeTrabajo = 0;
  let pendientesPorSesion = 0;
  let peorEnvioMs = 0;
  let ventanaFin = 0;
  let remainingPares: Par[] = [];
  let saltadosPares: Par[] = [];
  let pacingAbort: any = env.pacingAbort ?? null;
  let sessionAbort: any = env.sessionAbort ?? null;
  // Declaraciones verbatim L1849-1854 (quedan fuera del bloque del for).
  let destinoActual: string | null = plan.length > 0 ? plan[0].chatId : null;
  let fallosDelDestino = 0;
  const destinosSaltados = new Set<string>();

  for (let cursor = 0; cursor < plan.length; cursor++) {
    const par = plan[cursor];

    // Cambio de grupo: pausa larga y contador de fallos a cero.
    if (par.chatId !== destinoActual) {
      destinoActual = par.chatId;
      fallosDelDestino = 0;
      const pausa = ENTRE_DESTINOS_MS +
        Math.floor(Math.random() * Math.min(minMs, 10_000));
      console.log(
        `[wapi-send-products] siguiente destino a los ` +
          `${Math.round(elapsed() / 1000)}s (pausa ${Math.round(pausa / 1000)}s)`,
      );
      if (elapsed() + pausa + reservaMensajeMs() < WORKER_BUDGET_MS) {
        await new Promise((res) => setTimeout(res, pausa));
      }
    }

    const sinPresupuesto = mensajesIntentados > 0
      ? elapsed() + reservaMensajeMs() > WORKER_BUDGET_MS
      : elapsed() > WORKER_BUDGET_MS; // el primero siempre se intenta
    if (sinPresupuesto) {
      remainingPares = plan.slice(cursor);
      console.log(
        `[wapi-send-products] corte por presupuesto a los ` +
          `${Math.round(elapsed() / 1000)}s: ${mensajesIntentados} mensaje(s) ` +
          `despachados, ${remainingPares.length} para el worker siguiente`,
      );
      break;
    }

    // Destino problemático: no se insiste contra él. Sus mensajes quedan
    // `pendiente` (reanudables a mano) y se pasa al grupo siguiente.
    if (fallosDelDestino >= DESTINO_FALLOS_MAX) {
      destinosSaltados.add(par.chatId);
      saltadosPares.push(par);
      continue;
    }
    // Producto descartado: ni se prepara ni cuenta como trabajo pendiente.
    if (descartados.has(par.idProducto)) continue;

    // Precarga por ventanas: una consulta cada WINDOW_SIZE productos, en vez
    // de una por producto (lento) o una sola gigante (se trunca).
    const posProd = posDeProducto.get(par.idProducto) ?? 0;
    if (posProd >= ventanaFin) {
      const fin = Math.min(effProductIds.length, posProd + WINDOW_SIZE);
      await ensureInfo(effProductIds.slice(posProd, fin));
      ventanaFin = fin;
    }

    const listo = await obtenerProductoListo(par.idProducto);
    if (!listo || !listo.chats.includes(par.chatId)) continue;

    const inicioMensaje = Date.now();
    const r = await dispatchOne({
      idProducto: par.idProducto,
      chatId: par.chatId,
      url: listo.url,
      caption: listo.caption,
      mimetype: listo.mimetype,
      logId: listo.logIdPorChat.get(par.chatId) ?? null,
    });
    mensajesIntentados++;
    // Coste real del mensaje: alimenta `reservaMensajeMs()` para que la
    // decisión de cortar use medidas de ESTE envío, no una estimación fija.
    peorEnvioMs = Math.max(peorEnvioMs, Date.now() - inicioMensaje);

    if (r.ok) {
      enviados++;
      fallosDelDestino = 0;
    } else if (r.sessionDown) {
      // La sesión de OpenWA se cayó y la escalera no la levantó: se corta el
      // chunk. Todo lo que queda queda `pendiente` (no `fallido`): es trabajo
      // por hacer cuando la sesión vuelva.
      pendientesPorSesion++;
      sessionAbort = r.sessionDown;
      remainingPares = plan.slice(cursor + 1);
      break;
    } else if (r.pacing) {
      // WAPI pide una pausa que no cabe en este worker: se corta y se reanuda.
      pacingAbort = r.pacing;
      remainingPares = plan.slice(cursor + 1);
      break;
    } else if (r.pendiente) {
      // Resultado indeterminado. La fila ya quedó `pendiente` y es reanudable
      // sin duplicar (misma clave). Cuenta como fallo del destino para poder
      // saltárselo si se atasca, pero NO se marca como fallo de la tanda.
      pendientesDeTrabajo++;
      fallosDelDestino++;
    } else {
      fallidos++;
      fallosDelDestino++;
    }

    // Delay anti-ban entre mensajes DEL MISMO destino. Mantiene el mismo ritmo
    // efectivo por sesión que el fan-out anterior (donde el hueco lo ponían
    // los otros destinos) pero concentrado en el grupo que se está sirviendo.
    if (cursor < plan.length - 1 && plan[cursor + 1].chatId === par.chatId) {
      const jitter = minMs +
        Math.floor(Math.random() * Math.max(1, maxMs - minMs));
      if (elapsed() + jitter + 20_000 < WORKER_BUDGET_MS) {
        await new Promise((res) => setTimeout(res, jitter));
      }
    }
  }

  return { remainingPares, saltadosPares, pacingAbort, sessionAbort, mensajesIntentados, enviados, fallidos, pendientesDeTrabajo, pendientesPorSesion, destinosSaltados, descartados };
}

// ──────────── Cierre: EXTRAÍDO VERBATIM L1971 ────────────
async function correrCierre(env: any, st: any) {
  let remainingPares: Par[] = st.remainingPares;
  let saltadosPares: Par[] = st.saltadosPares;
  const destinosSaltados: Set<string> = st.destinosSaltados;
  const descartados: Set<number> = st.descartados;
  const registrarPendientesPares = env.registrarPendientesPares;
  const DESTINO_FALLOS_MAX = 3;
  const console = { error: (..._a: any[]) => {}, warn: (..._a: any[]) => {}, log: (..._a: any[]) => {} };

  const deDestinoSaltado = remainingPares.filter((p) =>
    destinosSaltados.has(p.chatId)
  );
  if (deDestinoSaltado.length > 0) {
    saltadosPares.push(...deDestinoSaltado);
    remainingPares = remainingPares.filter((p) =>
      !destinosSaltados.has(p.chatId)
    );
  }

  // Los mensajes de un destino saltado NO se encadenan: volverían a fallar y
  // sólo gastarían workers. Quedan `pendiente` con el motivo para que el botón
  // "reanudar" de la app los recoja cuando el grupo se arregle.
  const saltadosRegistrables = saltadosPares
    .filter((p) => !descartados.has(p.idProducto));
  if (saltadosRegistrables.length > 0) {
    const ids = await registrarPendientesPares(saltadosRegistrables, {
      code: "DESTINO_CAIDO",
      message:
        `El destino acumuló ${DESTINO_FALLOS_MAX} fallos seguidos; sus ` +
        `mensajes quedan pendientes de reanudar`,
    });
    console.warn(
      `[wapi-send-products] ${saltadosRegistrables.length} mensaje(s) de ` +
        `destino(s) saltado(s) quedan pendientes (${ids.length} fila(s))`,
    );
  }

  const remainingRegistrables = remainingPares
    .filter((p) => !descartados.has(p.idProducto));

  const continuacion = await registrarPendientesPares(remainingRegistrables);
  return { remainingPares, saltadosPares, remainingRegistrables, deDestinoSaltado, continuacion };
}

// ─────────────────────────────────────────────────────────────────────────
//  Runner de escenarios (se incrusta al final de harness.ts)
// ─────────────────────────────────────────────────────────────────────────

async function correr(e) {
  const db = nuevoDB();
  db.fallaInsert = !!e.fallaInsert;
  const admin = mockAdmin(db);
  const logIdDePar = new Map();
  const descartados = new Set();
  const malos = new Set(e.descartar ?? []);
  const posDeProducto = new Map();
  e.products.forEach((p, i) => { if (!posDeProducto.has(p)) posDeProducto.set(p, i); });

  const plan = [];
  for (const c of e.chats) for (const p of e.products) plan.push({ idProducto: p, chatId: c });

  const despachados = [];
  const llamadas = [];
  const stepMs = e.stepMs ?? 1000;
  let clicks = 0;

  const env = {
    plan,
    effProductIds: e.products,
    posDeProducto,
    descartados,
    chatsValidos: e.chats,
    logIdDePar,
    admin,
    WORKER_BUDGET_MS: e.budget ?? 270000,
    minMs: 0,
    maxMs: 0,
    elapsed: () => clicks * stepMs,
    reservaMensajeMs: () => 0,
    ensureInfo: async () => {},
  };
  const registrar = makeRegistrar(env);
  env.registrarPendientesPares = registrar;

  // Espejo fiel de `descartar()` (L1362-1381, rama NO reanudación):
  // registrar filas (pendiente) y marcarlas `fallido` + SKIPPED, una vez por producto.
  env.obtenerProductoListo = async (idProd) => {
    if (malos.has(idProd)) {
      if (!descartados.has(idProd)) {
        descartados.add(idProd);
        const ids = await registrar(e.chats.map((c) => ({ idProducto: idProd, chatId: c })));
        if (ids.length > 0) {
          await admin.from("app_wapi_envio_log")
            .update({ estado: "fallido", error_code: "SKIPPED" }).in("id", ids);
        }
      }
      return null;
    }
    return {
      idProducto: idProd, chats: e.chats, logIdPorChat: new Map(),
      url: "http://x/y.jpg", caption: "c", mimetype: "image/jpeg",
    };
  };

  env.dispatchOne = async (envio) => {
    const p = { idProducto: envio.idProducto, chatId: envio.chatId };
    llamadas.push(p);
    clicks++;
    const o = e.outcomes[clavePar(p)] ?? "ok";
    if (o === "sessionDown") return { ok: false, sessionDown: { rawStatus: "x", recuperada: false, action: "test" } };
    if (o === "pacing") return { ok: false, pacing: { retryAfterSeconds: 90 } };
    if (o === "pendiente") return { ok: false, pendiente: true };
    if (o === "fallo") return { ok: false };
    despachados.push(p);
    return { ok: true };
  };

  const st = await correrBucle(env);
  const cierre = await correrCierre(env, st);

  // Conteo por clave (soporta `product_ids` repetidos en el plan).
  const planCount = new Map();
  for (const p of plan) planCount.set(clavePar(p), (planCount.get(clavePar(p)) ?? 0) + 1);
  const bucketCount = new Map();
  const suma = (arr) => { for (const p of arr) bucketCount.set(clavePar(p), (bucketCount.get(clavePar(p)) ?? 0) + 1); };
  suma(llamadas); suma(st.remainingPares); suma(st.saltadosPares);

  const sinBucket = [];
  const sobrecontado = [];
  let paresSinBucket = 0;
  for (const [k, n] of planCount) {
    const b = bucketCount.get(k) ?? 0;
    if (b < n) { sinBucket.push(k); paresSinBucket += n - b; }
    if (b > n) sobrecontado.push(`${k}(${b}>${n})`);
  }
  const filasPorPar = new Map();
  for (const f of db.filas) {
    const k = `${f.id_producto}|${f.chat_id}`;
    filasPorPar.set(k, (filasPorPar.get(k) ?? 0) + 1);
  }
  const perdidosSinFila = sinBucket.filter((k) => !filasPorPar.has(k));
  const duplicados = [...filasPorPar.entries()].filter(([, n]) => n > 1).map(([k, n]) => `${k}x${n}`);
  const fallidos = db.filas.filter((f) => f.estado === "fallido").length;
  const pendientes = db.filas.filter((f) => f.estado === "pendiente").length;

  return {
    nombre: e.nombre,
    plan: plan.length,
    llamadas: llamadas.length,
    ok: despachados.length,
    remaining: st.remainingPares.length,
    saltados: st.saltadosPares.length,
    deDestinoSaltado: cierre.deDestinoSaltado.length,
    continuacion: cierre.continuacion.length,
    filas: db.filas.length,
    fallidos,
    pendientes,
    sinBucket,
    paresSinBucket,
    sobrecontado,
    perdidosSinFila,
    duplicados,
    raw: { st, cierre, db, plan, llamadas },
  };
}

function linea(r) {
  return [
    `${r.nombre.padEnd(34)}`,
    `plan=${String(r.plan).padStart(2)}`,
    `llam=${String(r.llamadas).padStart(2)}`,
    `ok=${String(r.ok).padStart(2)}`,
    `rem=${String(r.remaining).padStart(2)}`,
    `salt=${String(r.saltados).padStart(2)}`,
    `mov=${r.deDestinoSaltado}`,
    `cont=${String(r.continuacion).padStart(2)}`,
    `filas=${String(r.filas).padStart(2)}`,
    `(fallidas=${r.fallidos} pend=${r.pendientes})`,
    `sinBucket=${r.sinBucket.length ? r.sinBucket.join(",") : "0"}`,
    `perdidosSinFila=${r.perdidosSinFila.length ? r.perdidosSinFila.join(",") : "0"}`,
    `dupFilas=${r.duplicados.length ? r.duplicados.join(",") : "0"}`,
  ].join(" ");
}

const A = "111@g.us", B = "222@g.us", C = "333@g.us";
const escenarios = [
  { nombre: "E1 feliz 3dest x 4prod", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {} },
  { nombre: "E2 corte presupuesto", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 6 },
  { nombre: "E3 destino A caido (3 fallos)", products: [1, 2, 3, 4, 5], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" } },
  { nombre: "E4 sesionDown en msg 4", products: [1, 2, 3], chats: [A, B], outcomes: { [`1|${B}`]: "sessionDown" } },
  { nombre: "E5 pacing en msg 4", products: [1, 2, 3], chats: [A, B], outcomes: { [`1|${B}`]: "pacing" } },
  { nombre: "E6 indeterminado en msg 2", products: [1, 2, 3], chats: [A, B], outcomes: { [`2|${A}`]: "pendiente" } },
  { nombre: "E7 producto 2 descartado", products: [1, 2, 3], chats: [A, B], outcomes: {}, descartar: [2] },
  { nombre: "E8 corte+destino caido", products: [1, 2, 3, 4, 5], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" }, stepMs: 1, budget: 4 },
  { nombre: "E9 product_ids dup [1,2,3,4,4]", products: [1, 2, 3, 4, 4], chats: [A], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" } },
  { nombre: "E10 dup + insert DB falla", products: [1, 2, 3, 4], chats: [A, B], outcomes: {}, stepMs: 1, budget: 5, fallaInsert: true },
];

const filas = [];
for (const e of escenarios) filas.push(await correr(e));

console.log("=== ESCENARIOS ===");
for (const r of filas) console.log(linea(r));

// ── Búsqueda exhaustiva: ¿puede `deDestinoSaltado` ser NO vacío? ──────────
const ALFA = ["ok", "fallo", "pendiente"];
const BREAK = ["sessionDown", "pacing"];
let runs = 0, noVacios = 0, ejemplo = null;
function* planes() {
  for (const nD of [1, 2, 3]) {
    for (const nP of [1, 2, 3]) {
      const n = nD * nP;
      if (n > 6) continue;
      yield { chats: [A, B, C].slice(0, nD), products: Array.from({ length: nP }, (_, i) => i + 1) };
    }
  }
}
for (const pl of planes()) {
  const pares = [];
  for (const c of pl.chats) for (const p of pl.products) pares.push({ idProducto: p, chatId: c });
  const n = pares.length;
  const combos = [];
  const rec = (i, acc) => {
    if (i === n) return combos.push([...acc]);
    for (const o of ALFA) { acc.push(o); rec(i + 1, acc); acc.pop(); }
  };
  rec(0, []);
  // variantes con UN break (sessionDown|pacing) en cada posición
  for (let pos = 0; pos < n; pos++) {
    for (const b of BREAK) {
      for (const base of combos) {
        const acc = [...base];
        acc[pos] = b;
        combos.push(acc);
      }
    }
  }
  const budgets = [1e9, ...Array.from({ length: n + 1 }, (_, k) => k)];
  for (const outs of combos) {
    const outcomes = {};
    pares.forEach((p, i) => { outcomes[clavePar(p)] = outs[i]; });
    for (const b of budgets) {
      const r = await correr({
        nombre: "bf", products: pl.products, chats: pl.chats, outcomes,
        stepMs: 100, budget: b === 1e9 ? 1e9 : b * 100 + 1,
      });
      runs++;
      if (r.deDestinoSaltado > 0) { noVacios++; if (!ejemplo) ejemplo = { pl, outs, b, r: linea(r) }; }
    }
  }
}
console.log("\n=== BÚSQUEDA EXHAUSTIVA deDestinoSaltado>0 ===");
console.log(`ejecuciones=${runs}  conMovimientoNoVacio=${noVacios}`);
if (ejemplo) console.log("EJEMPLO:", JSON.stringify(ejemplo));

// ── Idempotencia: ¿la clave depende sólo del logId? ──────────────────────
const srcIdem = await import("node:fs").then((m) => m.readFileSync(new URL("./snapshot/index.ts", import.meta.url), "utf8"));
const idemKeys = [...srcIdem.matchAll(/`wa-log-\$\{[^}]+\}`/g)].map((m) => m[0]);
console.log("\n=== CLAVES DE IDEMPOTENCIA EN EL CÓDIGO ===");
console.log(`plantillas wa-log-*: ${JSON.stringify(idemKeys)}`);
console.log(`e.logId se asigna una sola vez: ${(srcIdem.match(/logId: listo\.logIdPorChat\.get\(par\.chatId\)/g) ?? []).length} sitio(s)`);
console.log(`logIdPorChat se llena desde la fila reutilizada o insertada: ${(srcIdem.match(/logIdPorChat\.set\(/g) ?? []).length} sitio(s)`);
