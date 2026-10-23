// GENERADO por build_harness.mjs — NO EDITAR A MANO.
// Fuente: ventiq_admin_app/supabase/functions/wapi-send-products/index.ts
// SHA256 verificado: C94F8257EF3A1F2FDD44736B6579F76A5621D844ED5CF110B5F21FFD68A8FC4D
// Bloques verbatim: chatsValidos L1033, resume+orden L883, plan L1076,
//                  registrarPendientesPares L1164, bucle L1930, cierre L2060
/* eslint-disable */

type Par = { idProducto: number; chatId: string };
function clavePar(p: Par): string { return `${p.idProducto}|${p.chatId}`; }
function chunkArray<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}
const noopConsole = { error: () => {}, warn: () => {}, log: () => {} };

// ─────────────────────────── Mock de Supabase ───────────────────────────
type Fila = { id: number; id_producto: number; chat_id: string; estado: string; error_code?: string | null };
type DB = {
  filas: Fila[];
  inserts: any[][];
  updates: Array<{ patch: any; ids?: number[]; eq?: number }>;
  fallaInsert: boolean;
  nextId: number;
  pendRows: any[];
};
function nuevoDB(): DB {
  return { filas: [], inserts: [], updates: [], fallaInsert: false, nextId: 1000, pendRows: [] };
}
function thenable(resultado: any) {
  const o: any = {
    in: () => o, eq: () => o, neq: () => o, order: () => o, limit: () => o,
    single: () => o, maybeSingle: () => o,
    then: (res: any, rej: any) => Promise.resolve(resultado).then(res, rej),
    catch: (rej: any) => Promise.resolve(resultado).catch(rej),
  };
  return o;
}
function mockAdmin(db: DB) {
  const cadena: any = {
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
        select: () => thenable({
          data: db.fallaInsert ? null : creadas.map((f) => ({ id: f.id, id_producto: f.id_producto, chat_id: f.chat_id })),
          error: db.fallaInsert ? { message: "insert simulado falla" } : null,
        }),
      };
    },
    select: (_cols: string) => thenable({ data: db.pendRows, error: null }),
    update: (patch: any) => ({
      in: async (_col: string, ids: number[]) => {
        db.updates.push({ patch, ids: [...ids] });
        for (const f of db.filas) if (ids.includes(f.id)) Object.assign(f, patch);
        return { error: null };
      },
      eq: async (_col: string, id: number) => {
        db.updates.push({ patch, eq: id });
        for (const f of db.filas) if (f.id === id) Object.assign(f, patch);
        return { error: null };
      },
    }),
  };
  return { from: (_t: string) => cadena };
}

// ── chatsValidos: EXTRAÍDO VERBATIM L1033 ──
function construirChatsValidos(effDestinations: any[]) {
  const chatsValidos = Array.from(
    new Set(
      effDestinations
        .map((d) => (typeof d.chat_id === "string" ? d.chat_id.trim() : ""))
        .filter((c) => /@(c|g)\.us$/.test(c)),
    ),
  );
  return chatsValidos;
}

// ── plan: EXTRAÍDO VERBATIM L1076 ──
function construirPlan(chatsValidos: string[], effProductIds: number[], logIdPorPar: Map<string, number>, esReanudacion: boolean) {
  const plan: Par[] = [];
  for (const chatId of chatsValidos) {
    for (const idProd of effProductIds) {
      const par: Par = { idProducto: idProd, chatId };
      if (esReanudacion && !logIdPorPar.has(clavePar(par))) continue;
      plan.push(par);
    }
  }
  return plan;
}

// ── REANUDAR (reconstrucción + orden canónico): EXTRAÍDO VERBATIM L883 ──
function reconstruirDesdeLogs(pend: any[], destinations: any[], summaryProductIds: number[] = []) {
  const args = { summaryProductIds };
  const logIdPorPar = new Map<string, number>();
  const logIdDePar = new Map<string, number>();
  let effProductIds: number[] = [];
  let effDestinations: any[] = [];
  const console = noopConsole;
    const ordenProd: number[] = [];
    const vistosProd = new Set<number>();
    const chats = new Map<string, Destino>();
    // Los destinos originales traen `etiqueta`/`tipo`; los reaprovechamos.
    const metaPorChat = new Map(destinations.map((d) => [d.chat_id, d]));

    for (const row of pend ?? []) {
      const idProd = Number((row as any).id_producto);
      const chatId = String((row as any).chat_id ?? "");
      if (!Number.isFinite(idProd) || !chatId) continue;
      const key = `${idProd}|${chatId}`;
      // Si el mismo par apareciera dos veces nos quedamos con el primer log.
      if (!logIdPorPar.has(key)) {
        logIdPorPar.set(key, Number((row as any).id));
        logIdDePar.set(key, Number((row as any).id));
      }
      if (!vistosProd.has(idProd)) {
        vistosProd.add(idProd);
        ordenProd.push(idProd);
      }
      if (!chats.has(chatId)) {
        chats.set(
          chatId,
          metaPorChat.get(chatId) ?? {
            tipo: chatId.endsWith("@g.us") ? "grupo" : "numero",
            chat_id: chatId,
          },
        );
      }
    }

    // ── ORDEN CANÓNICO AL REANUDAR ──────────────────────────────────────
    // El orden de los pares se reconstruye desde los logs, pero el `id` de las
    // filas NO refleja el orden destino-mayor: durante el envío las filas se
    // insertan por producto. Sin corregirlo, el grupo que se estaba sirviendo
    // cuando se cortó el chunk pasaba al FINAL de la cadena, y el "un grupo
    // detrás de otro" se degradaba en cada corte.
    //
    // La petición sí trae el orden bueno:
    //   · `destinations` — la continuación hereda `effDestinations` del worker
    //     anterior (la reanudación manual desde la app manda `[]`).
    //   · `summary_product_ids` — la cadena lo hereda COMPLETO desde el primer
    //     chunk, así que sirve de orden canónico de productos.
    // Si no llegan (reanudación manual sin ellos) se cae al orden de los logs,
    // que es el comportamiento anterior.
    const ordenDestinos = destinations
      .map((d) => String(d.chat_id ?? "").trim())
      .filter((c) => c.length > 0);
    if (ordenDestinos.length > 0) {
      const posDestino = new Map<string, number>();
      ordenDestinos.forEach((c, i) => {
        if (!posDestino.has(c)) posDestino.set(c, i);
      });
      const ultimo = Number.MAX_SAFE_INTEGER;
      effDestinations = Array.from(chats.values()).sort(
        (a, b) =>
          (posDestino.get(a.chat_id) ?? ultimo) -
          (posDestino.get(b.chat_id) ?? ultimo),
      );
    } else {
      effDestinations = Array.from(chats.values());
    }

    const ordenProductos = (args.summaryProductIds ?? [])
      .map((n) => Number(n))
      .filter((n) => Number.isFinite(n));
    if (ordenProductos.length > 0) {
      const posProducto = new Map<number, number>();
      ordenProductos.forEach((id, i) => {
        if (!posProducto.has(id)) posProducto.set(id, i);
      });
      const ultimo = Number.MAX_SAFE_INTEGER;
      effProductIds = [...ordenProd].sort(
        (a, b) =>
          (posProducto.get(a) ?? ultimo) - (posProducto.get(b) ?? ultimo),
      );
    } else {
      effProductIds = ordenProd;
    }
  return { effProductIds, effDestinations, logIdPorPar, logIdDePar };
}

// ── registrarPendientesPares: cuerpo EXTRAÍDO VERBATIM L1164 ──
function makeRegistrar(env: any) {
  const admin = env.admin;
  const chatsValidos: string[] = env.chatsValidos;
  const logIdDePar: Map<string, number> = env.logIdDePar;
  const idTienda = 1, idSesion = 1, idProgramacion = null, tipoEnvio = "manual";
  const console = env.log ?? noopConsole;
  return async function registrarPendientesPares(pares: Par[], motivo?: { code: string; message: string }): Promise<{ ids: number[]; ok: boolean }> {
    if (pares.length === 0 || chatsValidos.length === 0) {
      return { ids: [], ok: true };
    }

    const implicados = new Set<number>();
    // Deduplicado por par: si la petición repitiera un producto, sin esto se
    // insertarían DOS filas del mismo (producto, chat) y la segunda quedaría
    // `pendiente` para siempre — la reanudación conserva el primer log y la
    // tanda se vería "interrumpida" sin poder avanzar nunca.
    const faltantes = new Map<string, Par>();
    for (const par of pares) {
      const clave = clavePar(par);
      const id = logIdDePar.get(clave);
      if (id != null) implicados.add(id);
      else faltantes.set(clave, par);
    }

    let ok = true;
    if (faltantes.size > 0) {
      const filas = Array.from(faltantes.values()).map((p) => ({
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
        // CRÍTICO: si el insert falla, estos mensajes se despacharán SIN fila
        // de log y SIN `Idempotency-Key` (`logId` null) → invisibles en el
        // historial y no reanudables. Además la continuación, que se guía por
        // logIds, se quedaría sin ellos. Hay que decirlo ALTO.
        ok = false;
        console.error(
          `[wapi-send-products] FALLO al registrar ${faltantes.size} ` +
            `mensaje(s) pendientes: ${(e as Error).message ?? e}. Se ` +
            `despacharían SIN fila ni clave de idempotencia.`,
        );
      }
      // Si algún par se ha quedado sin fila, la operación no está completa.
      for (const clave of faltantes.keys()) {
        if (!logIdDePar.has(clave)) {
          ok = false;
          break;
        }
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
    return { ids, ok };
  };
}

// ── Bucle principal: EXTRAÍDO VERBATIM L1930 ──
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
  const console = env.log ?? noopConsole;

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
  // Declaraciones verbatim (quedan fuera del bloque del for).
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
    if (!listo) {
      // Producto descartado: `descartar` ya marcó sus filas como `fallido`
      // (SKIPPED) y dejó constancia en `skipped`. Por eso NO va a ningún cubo
      // de pendientes: no hay nada que reanudar.
      continue;
    }
    if (!listo.chats.includes(par.chatId)) {
      // No debería ocurrir nunca: el `plan` y `prepararProducto` usan el mismo
      // filtro (`logIdPorPar`). Si pasara, el par quedaría fuera de todos los
      // cubos, así que se avisa en vez de perderlo en silencio.
      console.error(
        `[wapi-send-products] par sin destino preparado: ` +
          `prod=${par.idProducto} chat=${par.chatId} — se omite`,
      );
      continue;
    }

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

// ── Cierre completo: EXTRAÍDO VERBATIM L2060 ──
async function correrCierre(env: any, st: any) {
  let remainingPares: Par[] = st.remainingPares;
  let saltadosPares: Par[] = st.saltadosPares;
  const destinosSaltados: Set<string> = st.destinosSaltados;
  const descartados: Set<number> = st.descartados;
  const registrarPendientesPares = env.registrarPendientesPares;
  const reinvokeRemaining = env.reinvokeRemaining;
  const pacingAbort = st.pacingAbort;
  const sessionAbort = st.sessionAbort;
  const DESTINO_FALLOS_MAX = 3;
  const console = env.log ?? noopConsole;
  let continuacionOk = false;

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
    const { ids, ok } = await registrarPendientesPares(saltadosRegistrables, {
      code: "DESTINO_CAIDO",
      message:
        `El destino acumuló ${DESTINO_FALLOS_MAX} fallos seguidos; sus ` +
        `mensajes quedan pendientes de reanudar`,
    });
    console.warn(
      `[wapi-send-products] ${saltadosRegistrables.length} mensaje(s) de ` +
        `destino(s) saltado(s) quedan pendientes (${ids.length} fila(s)` +
        `${ok ? "" : ", REGISTRO INCOMPLETO"})`,
    );
  }

  const remainingRegistrables = remainingPares
    .filter((p) => !descartados.has(p.idProducto));

  if (pacingAbort) {
    // WAPI está en cooldown: encadenar sería chocar con el mismo 429 desde
    // un worker nuevo. Se registran los pendientes para reanudar después.
    console.warn(
      `[wapi-send-products] cortado por pacing ` +
        `(${pacingAbort.retryAfterSeconds}s): ${remainingRegistrables.length} ` +
        `mensaje(s) quedan pendientes de reanudar`,
    );
    await registrarPendientesPares(remainingRegistrables);
  } else if (sessionAbort) {
    // La sesión se cayó y la escalera de recuperación falló. Encadenar un
    // worker nuevo sería inútil (haría lo mismo contra una sesión muerta) y
    // gastaría una invocación: se registran los pendientes y se avisa.
    console.error(
      `[wapi-send-products] cortado por SESIÓN CAÍDA ` +
        `(acción=${sessionAbort.action}, estado final=${sessionAbort.rawStatus ?? "?"}): ` +
        `${remainingRegistrables.length} mensaje(s) quedan pendientes de reanudar. ` +
        `El watchdog (wapi-session-health) y el cron revisan la sesión.`,
    );
    await registrarPendientesPares(remainingRegistrables);
  } else if (remainingRegistrables.length > 0) {
    // Primero se aseguran las filas (la continuación se guía por logIds) y
    // después se encola. Al revés, la continuación iría sin ids.
    const { ids, ok } = await registrarPendientesPares(remainingRegistrables);
    if (!ok || ids.length === 0) {
      // Sin filas no hay continuación posible: hay que gritarlo, porque si no
      // la tanda se queda "a medias" sin ninguna señal (era el fallo silencioso
      // que rompía la cadena de chunks).
      console.error(
        `[wapi-send-products] CADENA ROTA: no se pudieron registrar ` +
          `${remainingRegistrables.length} mensaje(s) que faltaban ` +
          `(ids=${ids.length}, ok=${ok}). Esos mensajes NO se despacharán ` +
          `hasta que se reanude la tanda a mano.`,
      );
      continuacionOk = false;
    } else {
      continuacionOk = await reinvokeRemaining(ids);
    }
  }

  return { remainingPares, saltadosPares, deDestinoSaltado, continuacionOk };
}

// ─────────────────────────────────────────────────────────────────────────
//  Runner de escenarios (se incrusta al final de harness.mts)
//  Revisión 2: registrar devuelve {ids, ok}, el cierre incluye las ramas de
//  continuación (CADENA ROTA), y `elapsed()` modela el reloj real (avanza en
//  CADA llamada, no solo al despachar).
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

  const log = [];
  const logCap = {
    error: (...a) => log.push("ERROR " + a.map(String).join(" ")),
    warn: (...a) => log.push("WARN " + a.map(String).join(" ")),
    log: (...a) => log.push("LOG " + a.map(String).join(" ")),
  };

  const llamadas = [];
  const claves = [];
  const stepMs = e.stepMs ?? 1000;
  const drift = e.driftPerCallMs ?? 0;
  let clicks = 0;
  let calls = 0;
  let invocacionesReinvoke = 0;

  const env = {
    plan, effProductIds, posDeProducto, descartados, chatsValidos, logIdDePar, admin, log: logCap,
    WORKER_BUDGET_MS: e.budget ?? 270000, minMs: 0, maxMs: 0,
    elapsed: () => { calls++; return clicks * stepMs + drift * calls; },
    reservaMensajeMs: () => 0,
    ensureInfo: async () => {},
    reinvokeRemaining: async (ids) => { invocacionesReinvoke++; return ids.length > 0; },
  };
  const registrar = makeRegistrar(env);
  env.registrarPendientesPares = registrar;

  // Espejo fiel de `prepararProducto()` + `obtenerProductoListo()` (caché incluida)
  // y de `descartar()` (L1435+, ahora con `{ids, ok}`).
  const cache = new Map();
  const preparar = async (idProd) => {
    if (malos.has(idProd)) {
      if (!descartados.has(idProd)) {
        descartados.add(idProd);
        const objetivo = esReanudacion
          ? chatsValidos.filter((c) => logIdPorPar.has(`${idProd}|${c}`))
          : chatsValidos;
        const { ids, ok } = await registrar(objetivo.map((c) => ({ idProducto: idProd, chatId: c })));
        if (!ok) logCap.error(`[espejo descartar] producto ${idProd} sin filas`);
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
      if (error) { /* el código real solo loguea */ }
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
  const sinBucket = [];
  for (const [k, n] of planCount) if ((bucketCount.get(k) ?? 0) < n) sinBucket.push(k);

  const filasPorPar = new Map();
  for (const f of db.filas) {
    const k = `${f.id_producto}|${f.chat_id}`;
    filasPorPar.set(k, (filasPorPar.get(k) ?? 0) + 1);
  }
  const perdidosSinFila = sinBucket.filter((k) => !filasPorPar.has(k));
  const duplicados = [...filasPorPar.entries()].filter(([, n]) => n > 1).map(([k, n]) => `${k} x${n}`);
  const ip = claves.filter((k) => k !== null);
  const pendientesSinFila = st.remainingPares.filter((p) => !filasPorPar.has(clavePar(p)))
    .concat(st.saltadosPares.filter((p) => !filasPorPar.has(clavePar(p))))
    .map(clavePar);

  return {
    nombre: e.nombre, plan, llamadas, claves, db, st, cierre, log,
    planLen: plan.length, llam: llamadas.length,
    ok: db.filas.filter((f) => f.estado === "enviado").length,
    fallidas: db.filas.filter((f) => f.estado === "fallido").length,
    pendientes: db.filas.filter((f) => f.estado === "pendiente").length,
    remaining: st.remainingPares.length, saltados: st.saltadosPares.length,
    mov: cierre.deDestinoSaltado.length, continuacionOk: cierre.continuacionOk,
    invocacionesReinvoke,
    filas: db.filas.length,
    sinBucket, perdidosSinFila, duplicados, pendientesSinFila,
    fueraDeEnum: db.filas.filter((f) => !["pendiente", "enviado", "fallido"].includes(f.estado)).map((f) => f.estado),
    cadenaRota: log.filter((l) => l.includes("CADENA ROTA")).length,
    clavesIdem: ip.length, clavesIdemUnicas: new Set(ip).size,
    clavesIdemSinLog: claves.filter((k) => k === null).length,
  };
}

function linea(r) {
  return [
    r.nombre.padEnd(30),
    `plan=${String(r.planLen).padStart(2)}`,
    `llam=${String(r.llam).padStart(2)}`,
    `ok=${String(r.ok).padStart(2)}`,
    `fall=${String(r.fallidas).padStart(2)}`,
    `pend=${String(r.pendientes).padStart(2)}`,
    `rem=${String(r.remaining).padStart(2)}`,
    `salt=${String(r.saltados).padStart(2)}`,
    `mov=${r.mov}`,
    `cont=${r.continuacionOk ? "ok" : "NO"}`,
    `CR=${r.cadenaRota}`,
    `reinv=${r.invocacionesReinvoke}`,
    `filas=${String(r.filas).padStart(2)}`,
    `sinBucket=${r.sinBucket.length ? r.sinBucket.join(",") : "0"}`,
    `perdidos=${r.perdidosSinFila.length ? r.perdidosSinFila.join(",") : "0"}`,
    `pendSinFila=${r.pendientesSinFila.length ? r.pendientesSinFila.join(",") : "0"}`,
    `dup=${r.duplicados.length ? r.duplicados.join(",") : "0"}`,
    `enum=${r.fueraDeEnum.length ? r.fueraDeEnum.join(",") : "ok"}`,
    `idem=${r.clavesIdem}/${r.clavesIdemUnicas}${r.clavesIdemSinLog ? `(sinLog=${r.clavesIdemSinLog})` : ""}`,
  ].join(" ");
}

// ── Cadena de chunks + reanudación ───────────────────────────────────────
/** `pasaDestinos`/`pasaProductos` imitan lo que manda la petición al reanudar:
 *  la continuación hereda ambos; la app manda destinations=[] y summary_product_ids. */
async function correrCadena(e) {
  const db = nuevoDB();
  const chunk1 = await correr({ ...e, db, nombre: "chunk1" });
  const pendRows = (e.soloRemaining
    ? db.filas.filter((f) =>
      f.estado !== "enviado" &&
      chunk1.st.remainingPares.some((p) => clavePar(p) === `${f.id_producto}|${f.chat_id}`))
    : db.filas.filter((f) => f.estado !== "enviado"))
    .sort((a, b) => a.id - b.id)
    .map((f) => ({ id: f.id, id_producto: f.id_producto, chat_id: f.chat_id, estado: f.estado }));
  const destinosPayload = e.pasaDestinos === false ? [] : e.chats.map((c) => ({ tipo: "grupo", chat_id: c }));
  const prodsPayload = e.pasaProductos === false ? [] : e.products;
  const rec = reconstruirDesdeLogs(pendRows, destinosPayload, prodsPayload);
  const chatsValidos2 = construirChatsValidos(rec.effDestinations);
  const plan2 = construirPlan(chatsValidos2, rec.effProductIds, rec.logIdPorPar, true);
  const filasAntes = db.filas.length;
  const chunk2 = await correr({
    ...e, db, nombre: "chunk2", outcomes: {}, products: e.products,
    resume: {
      plan: plan2, effProductIds: rec.effProductIds, chatsValidos: chatsValidos2,
      logIdPorPar: rec.logIdPorPar, logIdDePar: rec.logIdDePar,
    },
  });
  const ordenChunk1 = chunk1.st.remainingPares.map(clavePar);
  const ordenChunk2 = plan2.map(clavePar);
  const mismoConjunto = ordenChunk1.length === ordenChunk2.length &&
    [...ordenChunk1].sort().join(";") === [...ordenChunk2].sort().join(";");
  const mismoOrden = ordenChunk1.join(";") === ordenChunk2.join(";");
  const m = new Map();
  for (const f of db.filas) { const k = `${f.id_producto}|${f.chat_id}`; m.set(k, (m.get(k) ?? 0) + 1); }
  const dup = [...m.entries()].filter(([, n]) => n > 1).map(([k, n]) => `${k} x${n}`);
  return { ordenChunk1, ordenChunk2, mismoConjunto, mismoOrden, nuevos: db.filas.length - filasAntes, dup, chunk1, chunk2 };
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
  { nombre: "E9 dup product_ids directo", products: [1, 2, 3, 4, 4], chats: [A], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" } },
  { nombre: "E10 insert DB falla", products: [1, 2, 3, 4], chats: [A, B], outcomes: {}, stepMs: 1, budget: 5, db: Object.assign(nuevoDB(), { fallaInsert: true }) },
  { nombre: "E11 deriva de reloj 1ms", products: [1, 2, 3, 4, 5], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" }, stepMs: 0, budget: 7, driftPerCallMs: 1 },
];

console.log("=== ESCENARIOS (una invocación) ===");
const resultados = [];
for (const e of escenarios) {
  const r = await correr(e);
  resultados.push(r);
  console.log(linea(r));
}

console.log("\n=== CADENA + REANUDACIÓN ===");
const cadenas = [
  { nombre: "C1 corte tras 7 msgs (3dest x 4prod)", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 6 },
  { nombre: "C2 corte dentro del 2º destino", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 3 },
  { nombre: "C3 corte + producto descartado", products: [1, 2, 3, 4], chats: [A, B], outcomes: {}, malos: [4], stepMs: 1, budget: 2 },
  { nombre: "C4 destino A caido + corte", products: [1, 2, 3, 4, 5, 6], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" }, stepMs: 1, budget: 6 },
  { nombre: "C4b C4 con semántica de CADENA (solo remaining)", products: [1, 2, 3, 4, 5, 6], chats: [A, B], outcomes: { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" }, stepMs: 1, budget: 6, soloRemaining: true },
  { nombre: "C5 DEFAULTS 5 dest x 25 prod", products: Array.from({ length: 25 }, (_, i) => i + 1), chats: [A, B, "444@g.us", "555@g.us", "666@g.us"], outcomes: {}, stepMs: 1, budget: 15 },
  { nombre: "C6 MANUAL dest=[] + prods", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 3, pasaDestinos: false },
  { nombre: "C7 MANUAL dest=[] sin prods", products: [1, 2, 3, 4], chats: [A, B, C], outcomes: {}, stepMs: 1, budget: 3, pasaDestinos: false, pasaProductos: false },
];
for (const e of cadenas) {
  const r = await correrCadena(e);
  const seq = (arr) => [...new Set(arr.map((k) => k.split("|")[1]))].join(" → ");
  console.log(`${e.nombre}`);
  console.log(`  destinos chunk1 (orden)   : ${seq(r.ordenChunk1)}`);
  console.log(`  destinos reanudación      : ${seq(r.ordenChunk2)}`);
  if (r.ordenChunk1.length <= 12) {
    console.log(`  pares chunk1 (orden)      : ${r.ordenChunk1.join(" ")}`);
    console.log(`  pares reanudación (orden) : ${r.ordenChunk2.join(" ")}`);
  } else {
    console.log(`  pares: chunk1=${r.ordenChunk1.length} reanudación=${r.ordenChunk2.length}`);
  }
  console.log(`  mismoConjunto=${r.mismoConjunto}  mismoOrden=${r.mismoOrden}  filasNuevas=${r.nuevos}  duplicadas=${r.dup.length ? r.dup.join(",") : "0"}`);
}

// ── Búsqueda exhaustiva: ¿es alcanzable `deDestinoSaltado`? ──────────────
const ALFA = ["ok", "fallo", "pendiente"];
const BREAK = ["sessionDown", "pacing"];
let runs = 0, noVacios = 0, ejemplo = null;
let runsD = 0, noVaciosD = 0, ejemploD = null;
async function barrer(chats, products, conBreaks, drift, fijos = {}) {
  const pares = [];
  for (const c of chats) for (const p of products) pares.push({ idProducto: p, chatId: c });
  const n = pares.length;
  const libres = [];
  const baseFija = pares.map((p) => fijos[clavePar(p)] ?? null);
  pares.forEach((p, i) => { if (baseFija[i] === null) libres.push(i); });
  const bases = [];
  const acc0 = [...baseFija];
  const rec = (j) => {
    if (j === libres.length) return bases.push([...acc0]);
    for (const o of ALFA) { acc0[libres[j]] = o; rec(j + 1); }
  };
  rec(0);
  const combos = bases.map((b) => [...b]);
  if (conBreaks) {
    for (let pos = 0; pos < n; pos++) {
      if (baseFija[pos] !== null) continue;
      for (const b of BREAK) for (const base of bases) { const a = [...base]; a[pos] = b; combos.push(a); }
    }
  }
  const budgets = drift > 0
    ? Array.from({ length: n >= 10 ? 20 : 40 }, (_, k) => k + 1)
    : [1e9, 1, 3, n];
  for (const outs of combos) {
    const outcomes = {};
    pares.forEach((p, i) => { outcomes[clavePar(p)] = outs[i]; });
    for (const b of budgets) {
      const r = await correr({
        nombre: "bf", products, chats, outcomes, stepMs: drift > 0 ? 0 : 100,
        budget: drift > 0 ? b : (b === 1e9 ? 1e9 : b * 100 + 1),
        driftPerCallMs: drift,
      });
      if (drift > 0) {
        runsD++;
        if (r.mov > 0) { noVaciosD++; if (!ejemploD) ejemploD = { chats, products, outs, b, linea: linea(r) }; }
      } else {
        runs++;
        if (r.mov > 0) { noVacios++; if (!ejemplo) ejemplo = { chats, products, outs, b, linea: linea(r) }; }
      }
    }
  }
}
for (const nD of [1, 2, 3]) {
  for (const nP of [1, 2, 3]) {
    if (nD * nP > 4) continue;
    await barrer([A, B, C].slice(0, nD), Array.from({ length: nP }, (_, i) => i + 1), true, 0);
  }
}
for (const nD of [1, 2, 3]) {
  for (const nP of [1, 2, 3]) {
    if (nD * nP > 4) continue;
    await barrer([A, B, C].slice(0, nD), Array.from({ length: nP }, (_, i) => i + 1), true, 1);
  }
}
// Familias donde SÍ se puede marcar un destino y cortar después: una sola
// lista con ≥5 productos, y 2 destinos con los 3 primeros fallos fijos.
await barrer([A], [1, 2, 3, 4, 5], false, 1);
await barrer([A, B], [1, 2, 3, 4, 5], false, 1, { [`1|${A}`]: "fallo", [`2|${A}`]: "fallo", [`3|${A}`]: "fallo" });
console.log("\n=== BÚSQUEDA EXHAUSTIVA deDestinoSaltado>0 ===");
console.log(`SIN deriva de reloj : ejecuciones=${runs}  conMovimientoNoVacio=${noVacios}`);
console.log(`CON deriva (1ms/llamada a elapsed) : ejecuciones=${runsD}  conMovimientoNoVacio=${noVaciosD}`);
if (ejemploD) console.log("EJEMPLO CON DERIVA:", JSON.stringify(ejemploD));

// ── Idempotencia ─────────────────────────────────────────────────────────
console.log("\n=== CLAVES DE IDEMPOTENCIA ===");
console.log(`llamadas con clave wa-log-<logId>: ${resultados.reduce((a, r) => a + r.clavesIdem, 0)}, ` +
  `claves distintas: ${resultados.reduce((a, r) => a + r.clavesIdemUnicas, 0)}`);
console.log(`claves sin logId: ${resultados.reduce((a, r) => a + r.clavesIdemSinLog, 0)}`);
console.log(`escenariosConSinBucket=${resultados.filter((r) => r.sinBucket.length > 0).map((r) => `${r.nombre}(${r.sinBucket.join(",")})`).join(" ") || "ninguno"}`);
for (const r of resultados) {
  if (r.duplicados.length || r.perdidosSinFila.length || r.pendientesSinFila.length || r.fueraDeEnum.length) {
    console.log(`AVISO ${r.nombre}: dup=${JSON.stringify(r.duplicados)} perdidos=${JSON.stringify(r.perdidosSinFila)} pendSinFila=${JSON.stringify(r.pendientesSinFila)} enum=${JSON.stringify(r.fueraDeEnum)}`);
  }
}
