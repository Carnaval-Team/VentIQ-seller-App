// ─────────────────────────────────────────────────────────────────────────
//  Runner de escenarios (se incrusta al final de harness.mts)
// ─────────────────────────────────────────────────────────────────────────

/** Ejecuta UNA invocación (chunk) con el código real extraído. */
async function correr(e) {
  const db = e.db ?? nuevoDB();
  const admin = mockAdmin(db);
  const descartados = new Set();
  const malos = new Set(e.malos ?? []);
  const esReanudacion = !!e.resume;
  const logIdPorPar = e.resume ? e.resume.logIdPorPar : new Map();
  const logIdDePar = e.resume ? e.resume.logIdDePar : new Map();
  const chatsValidos = e.resume ? e.resume.chatsValidos : e.chats;
  const effProductIds = e.resume ? e.resume.effProductIds : e.products;
  const plan = e.resume ? e.resume.plan : construirPlan(e.chats, e.products, logIdPorPar, false);

  const posDeProducto = new Map();
  e.products.forEach((p, i) => { if (!posDeProducto.has(p)) posDeProducto.set(p, i); });

  const llamadas = [];
  const claves = [];
  const stepMs = e.stepMs ?? 1000;
  let clicks = 0;

  const env = {
    plan, effProductIds, posDeProducto, descartados, chatsValidos, logIdDePar, admin,
    WORKER_BUDGET_MS: e.budget ?? 270000, minMs: 0, maxMs: 0,
    elapsed: () => clicks * stepMs, reservaMensajeMs: () => 0, ensureInfo: async () => {},
  };
  const registrar = makeRegistrar(env);
  env.registrarPendientesPares = registrar;

  // Espejo fiel de `prepararProducto()` + `obtenerProductoListo()` (caché incluida,
  // L1385-1499): inserta/reutiliza filas y llena logIdPorChat/logIdDePar.
  const cache = new Map();
  const preparar = async (idProd) => {
    if (malos.has(idProd)) {
      if (!descartados.has(idProd)) {
        descartados.add(idProd);
        const objetivo = esReanudacion
          ? chatsValidos.filter((c) => logIdPorPar.has(`${idProd}|${c}`))
          : chatsValidos;
        const ids = await registrar(objetivo.map((c) => ({ idProducto: idProd, chatId: c })));
        if (ids.length > 0) {
          await admin.from("app_wapi_envio_log")
            .update({ estado: "fallido", error_code: "SKIPPED" }).in("id", ids);
        }
      }
      return null;
    }
    const chats = esReanudacion
      ? chatsValidos.filter((c) => logIdPorPar.has(`${idProd}|${c}`))
      : chatsValidos;
    if (chats.length === 0) return null;
    const logIdPorChat = new Map();
    if (esReanudacion) {
      const aReiniciar = [];
      for (const c of chats) {
        const id = logIdPorPar.get(`${idProd}|${c}`);
        if (id == null) continue;
        logIdPorChat.set(c, id);
        logIdDePar.set(`${idProd}|${c}`, id);
        aReiniciar.push(id);
      }
      await admin.from("app_wapi_envio_log")
        .update({ estado: "pendiente", error_code: null, error_message: null }).in("id", aReiniciar);
    } else {
      const filas = chats.map((c) => ({
        id_tienda: 1, id_sesion: 1, id_programacion: null,
        id_producto: idProd, chat_id: c, tipo_envio: "manual", estado: "pendiente",
      }));
      const { data, error } = await admin.from("app_wapi_envio_log").insert(filas).select("id, chat_id");
      // Fiel a L1457-1464: el código REAL solo loguea el error y sigue sin logIds.
      if (error) { /* console.error(...) */ }
      for (const row of data ?? []) {
        const c = String(row.chat_id), id = Number(row.id);
        logIdPorChat.set(c, id);
        logIdDePar.set(`${idProd}|${c}`, id);
      }
    }
    return { idProducto: idProd, url: "http://x/y.jpg", caption: "c", mimetype: "image/jpeg", chats, logIdPorChat };
  };
  env.obtenerProductoListo = async (idProd) => {
    if (cache.has(idProd)) return cache.get(idProd) ?? null;
    const r = await preparar(idProd);
    cache.set(idProd, r);
    return r;
  };

  // Espejo fiel de las escrituras de `dispatchOne` (L1563-1838): el estado
  // indeterminado va a `pendiente`, el 4xx a `fallido`, el ok a `enviado`.
  env.dispatchOne = async (envio) => {
    const p = { idProducto: envio.idProducto, chatId: envio.chatId };
    llamadas.push({ ...p, logId: envio.logId });
    claves.push(envio.logId ? `wa-log-${envio.logId}` : null);
    clicks++;
    const o = e.outcomes[clavePar(p)] ?? "ok";
    if (o === "sessionDown") return { ok: false, sessionDown: { rawStatus: "x", recuperada: false, action: "test" } };
    if (o === "pacing") return { ok: false, pacing: { retryAfterSeconds: 90 } };
    const patch = o === "ok"
      ? { estado: "enviado", error_code: null }
      : o === "pendiente"
      ? { estado: "pendiente", error_code: "TIMEOUT" }
      : { estado: "fallido", error_code: "HTTP_400" };
    if (envio.logId) await admin.from("app_wapi_envio_log").update(patch).eq("id", envio.logId);
    if (o === "ok") return { ok: true };
    if (o === "pendiente") return { ok: false, pendiente: true };
    return { ok: false };
  };

  const st = await correrBucle(env);
  const cierre = await correrCierre(env, st);

  const planCount = new Map();
  for (const p of plan) planCount.set(clavePar(p), (planCount.get(clavePar(p)) ?? 0) + 1);
  const bucketCount = new Map();
  const suma = (arr) => { for (const p of arr) bucketCount.set(clavePar(p), (bucketCount.get(clavePar(p)) ?? 0) + 1); };
  suma(llamadas); suma(st.remainingPares); suma(st.saltadosPares);
  const sinBucket = [], sobrecontado = [];
  for (const [k, n] of planCount) {
    const b = bucketCount.get(k) ?? 0;
    if (b < n) sinBucket.push(k);
    if (b > n) sobrecontado.push(`${k}(${b}>${n})`);
  }
  const filasPorPar = new Map();
  for (const f of db.filas) {
    const k = `${f.id_producto}|${f.chat_id}`;
    filasPorPar.set(k, (filasPorPar.get(k) ?? 0) + 1);
  }
  const perdidosSinFila = sinBucket.filter((k) => !filasPorPar.has(k));
  const duplicados = [...filasPorPar.entries()].filter(([, n]) => n > 1).map(([k, n]) => `${k} x${n}`);
  const ip = claves.filter((k) => k !== null);
  const ipUnicas = new Set(ip);

  return {
    nombre: e.nombre, plan, llamadas, claves, db, st, cierre,
    planLen: plan.length, llam: llamadas.length,
    ok: db.filas.filter((f) => f.estado === "enviado").length,
    fallidas: db.filas.filter((f) => f.estado === "fallido").length,
    pendientes: db.filas.filter((f) => f.estado === "pendiente").length,
    remaining: st.remainingPares.length, saltados: st.saltadosPares.length,
    mov: cierre.deDestinoSaltado.length, continuacion: cierre.continuacion.length,
    filas: db.filas.length,
    sinBucket, perdidosSinFila, duplicados,
    fueraDeEnum: db.filas.filter((f) => !["pendiente", "enviado", "fallido"].includes(f.estado)).map((f) => f.estado),
    clavesIdem: ip.length, clavesIdemUnicas: ipUnicas.size,
    clavesIdemSinLog: claves.filter((k) => k === null).length,
  };
}

function linea(r) {
  return [
    r.nombre.padEnd(32),
    `plan=${String(r.planLen).padStart(2)}`,
    `llam=${String(r.llam).padStart(2)}`,
    `ok=${String(r.ok).padStart(2)}`,
    `fall=${String(r.fallidas).padStart(2)}`,
    `pend=${String(r.pendientes).padStart(2)}`,
    `rem=${String(r.remaining).padStart(2)}`,
    `salt=${String(r.saltados).padStart(2)}`,
    `mov=${r.mov}`,
    `cont=${String(r.continuacion).padStart(2)}`,
    `filas=${String(r.filas).padStart(2)}`,
    `sinBucket=${r.sinBucket.length ? r.sinBucket.join(",") : "0"}`,
    `perdidos=${r.perdidosSinFila.length ? r.perdidosSinFila.join(",") : "0"}`,
    `dup=${r.duplicados.length ? r.duplicados.join(",") : "0"}`,
    `enum=${r.fueraDeEnum.length ? r.fueraDeEnum.join(",") : "ok"}`,
    `idem=${r.clavesIdem}/${r.clavesIdemUnicas}${r.clavesIdemSinLog ? `(sinLog=${r.clavesIdemSinLog})` : ""}`,
  ].join(" ");
}

// ── Cadena de chunks + reanudación ───────────────────────────────────────
async function correrCadena(e) {
  const db = nuevoDB();
  const chunk1 = await correr({ ...e, db, nombre: "chunk1" });
  const pendRows = db.filas
    .filter((f) => f.estado !== "enviado")           // .neq("estado","enviado")
    .sort((a, b) => a.id - b.id)                     // .order("id")
    .map((f) => ({ id: f.id, id_producto: f.id_producto, chat_id: f.chat_id, estado: f.estado }));
  const rec = reconstruirDesdeLogs(pendRows, e.chats.map((c) => ({ tipo: "grupo", chat_id: c })));
  const chatsValidos2 = construirChatsValidos(rec.effDestinations);
  const plan2 = construirPlan(chatsValidos2, rec.effProductIds, rec.logIdPorPar, true);
  const filasAntes = db.filas.length;
  const chunk2 = await correr({
    ...e, db, nombre: "chunk2 (reanudar)", outcomes: {},
    products: rec.effProductIds,
    resume: {
      plan: plan2, effProductIds: rec.effProductIds, chatsValidos: chatsValidos2,
      logIdPorPar: rec.logIdPorPar, logIdDePar: rec.logIdDePar,
    },
  });
  const ordenChunk1 = chunk1.st.remainingPares.map(clavePar);
  const ordenChunk2 = plan2.map(clavePar);
  const mismoConjunto =
    ordenChunk1.length === ordenChunk2.length &&
    [...ordenChunk1].sort().join(";") === [...ordenChunk2].sort().join(";");
  const mismoOrden = ordenChunk1.join(";") === ordenChunk2.join(";");
  const nuevos = db.filas.length - filasAntes;
  const dup = [...(function () {
    const m = new Map();
    for (const f of db.filas) {
      const k = `${f.id_producto}|${f.chat_id}`;
      m.set(k, (m.get(k) ?? 0) + 1);
    }
    return m.entries();
  })()].filter(([, n]) => n > 1).map(([k, n]) => `${k} x${n}`);
  return { ordenChunk1, ordenChunk2, mismoConjunto, mismoOrden, nuevos, dup, chunk1, chunk2 };
}

const A = "111@g.us", B = "222@g.us", C = "333@g.us";
const escenarios = [
  { nombre: "E1 feliz 3dest x 4prod", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {} },
  { nombre: "E2 corte presupuesto", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 6 },
  { nombre: "E3 destino A caido (3 fallos)", products: [1, 2, 3, 4, 5], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" } },
  { nombre: "E4 sesionDown msg 4", products: [1, 2, 3], chats: [A, B], outcomes: { [`1|${B}`]: "sessionDown" } },
  { nombre: "E5 pacing msg 4", products: [1, 2, 3], chats: [A, B], outcomes: { [`1|${B}`]: "pacing" } },
  { nombre: "E6 indeterminado msg 2", products: [1, 2, 3], chats: [A, B], outcomes: { [`2|${A}`]: "pendiente" } },
  { nombre: "E7 producto 2 descartado", products: [1, 2, 3], chats: [A, B], outcomes: {}, malos: [2] },
  { nombre: "E8 corte+destino caido", products: [1, 2, 3, 4, 5], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" }, stepMs: 1, budget: 4 },
  { nombre: "E9 product_ids dup [1,2,3,4,4]", products: [1, 2, 3, 4, 4], chats: [A], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" } },
  { nombre: "E10 dup + insert DB falla", products: [1, 2, 3, 4], chats: [A, B], outcomes: {}, stepMs: 1, budget: 5, db: Object.assign(nuevoDB(), { fallaInsert: true }) },
];

console.log("=== ESCENARIOS (una invocación) ===");
const resultados = [];
for (const e of escenarios) {
  const r = await correr(e);
  resultados.push(r);
  console.log(linea(r));
}

console.log("\n=== CADENA + REANUDACIÓN ===");
for (const e of [
  { nombre: "C1 corte tras 7 msgs (3dest x 4prod)", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 6 },
  { nombre: "C2 corte dentro del 2º destino", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 3 },
  { nombre: "C3 corte + producto descartado", products: [1, 2, 3, 4], chats: [A, B], outcomes: {}, malos: [4], stepMs: 1, budget: 2 },
  { nombre: "C4 destino A caido + corte", products: [1, 2, 3, 4, 5, 6], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" }, stepMs: 1, budget: 6 },
  { nombre: "C5 DEFAULTS 5 destinos x 25 productos", products: Array.from({ length: 25 }, (_, i) => i + 1), chats: [A, B, "444@g.us", "555@g.us", "666@g.us"], outcomes: {}, stepMs: 1, budget: 15 },
]) {
  const r = await correrCadena(e);
  const seq = (arr) => [...new Set(arr.map((k) => k.split("|")[1]))].join(" → ");
  console.log(`${e.nombre}`);
  console.log(`  destinos chunk1 (orden)   : ${seq(r.ordenChunk1)}`);
  console.log(`  destinos reanudación      : ${seq(r.ordenChunk2)}`);
  if (r.ordenChunk1.length <= 12) {
    console.log(`  pendientes chunk1 (orden) : ${r.ordenChunk1.join(" ")}`);
    console.log(`  plan reanudación  (orden) : ${r.ordenChunk2.join(" ")}`);
  } else {
    console.log(`  pares: chunk1=${r.ordenChunk1.length} reanudación=${r.ordenChunk2.length}`);
  }
  console.log(`  mismoConjunto=${r.mismoConjunto}  mismoOrden=${r.mismoOrden}  filasNuevas=${r.nuevos}  duplicadas=${r.dup.length ? r.dup.join(",") : "0"}`);
}

// ── Búsqueda exhaustiva: ¿puede `deDestinoSaltado` ser NO vacío? ──────────
const ALFA = ["ok", "fallo", "pendiente"];
const BREAK = ["sessionDown", "pacing"];
let runs = 0, noVacios = 0, ejemplo = null;
async function barrer(chats, products, conBreaks) {
  const pares = [];
  for (const c of chats) for (const p of products) pares.push({ idProducto: p, chatId: c });
  const n = pares.length;
  const bases = [];
  const rec = (i, acc) => {
    if (i === n) return bases.push([...acc]);
    for (const o of ALFA) { acc.push(o); rec(i + 1, acc); acc.pop(); }
  };
  rec(0, []);
  const combos = bases.map((b) => [...b]);
  if (conBreaks) {
    for (let pos = 0; pos < n; pos++) {
      for (const b of BREAK) for (const base of bases) { const a = [...base]; a[pos] = b; combos.push(a); }
    }
  }
  const budgets = [1e9, 1, 3, n];
  for (const outs of combos) {
    const outcomes = {};
    pares.forEach((p, i) => { outcomes[clavePar(p)] = outs[i]; });
    for (const b of budgets) {
      const r = await correr({
        nombre: "bf", products, chats, outcomes, stepMs: 100,
        budget: b === 1e9 ? 1e9 : b * 100 + 1,
      });
      runs++;
      if (r.mov > 0) { noVacios++; if (!ejemplo) ejemplo = { chats, products, outs, b, linea: linea(r) }; }
    }
  }
}
for (const nD of [1, 2, 3]) {
  for (const nP of [1, 2, 3]) {
    const n = nD * nP;
    if (n > 4) continue;
    await barrer([A, B, C].slice(0, nD), Array.from({ length: nP }, (_, i) => i + 1), true);
  }
}
for (const nD of [2, 3]) {
  for (const nP of [2, 3]) {
    const n = nD * nP;
    if (n !== 6) continue;
    await barrer([A, B, C].slice(0, nD), Array.from({ length: nP }, (_, i) => i + 1), false);
  }
}
console.log("\n=== BÚSQUEDA EXHAUSTIVA deDestinoSaltado>0 ===");
console.log(`ejecuciones=${runs}  conMovimientoNoVacio=${noVacios}`);
if (ejemplo) console.log("EJEMPLO:", JSON.stringify(ejemplo));

// ── Idempotencia: la clave depende sólo del logId ────────────────────────
console.log("\n=== CLAVES DE IDEMPOTENCIA ===");
const totLlam = resultados.reduce((a, r) => a + r.clavesIdem, 0);
const totUni = resultados.reduce((a, r) => a + r.clavesIdemUnicas, 0);
console.log(`llamadas con clave wa-log-<logId>: ${totLlam}, claves distintas: ${totUni}`);
console.log(`claves sin logId (logId NULL -> sin cabecera): ${resultados.reduce((a, r) => a + r.clavesIdemSinLog, 0)}`);
for (const r of resultados) {
  if (r.duplicados.length || r.perdidosSinFila.length || r.fueraDeEnum.length) {
    console.log(`AVISO ${r.nombre}: dup=${JSON.stringify(r.duplicados)} perdidos=${JSON.stringify(r.perdidosSinFila)} enum=${JSON.stringify(r.fueraDeEnum)}`);
  }
}
console.log(`escenariosConSinBucket=${resultados.filter((r) => r.sinBucket.length > 0).map((r) => `${r.nombre}(${r.sinBucket.join(",")})`).join(" ") || "ninguno"}`);