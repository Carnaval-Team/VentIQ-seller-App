// POST /functions/v1/wapi-notify-agotado
//
// Aviso a los grupos/números guardados cuando un producto llega a stock 0.
//
// Body (dos modos):
//   { log_ids: number[] }                     ← lo llama el trigger de la BD
//   { id_tienda: number, id_producto: number } ← botón "avisar ahora" de la app
//
// ── AUTENTICACIÓN ──────────────────────────────────────────────────────────
// Se despliega con `verify_jwt = TRUE`. Los dos llamadores posibles mandan
// SIEMPRE un JWT válido del proyecto, así que el gateway puede verificarlo:
//   · el trigger `trg_wapi_agotado_notificar` (pg_net) manda la service_role
//     key del Vault en `Authorization` + `apikey` — exactamente igual que
//     `fn_wapi_dispatch_diario` → `wapi-cron-dispatch`, que está desplegada
//     con verify_jwt=true y responde 200 en producción cada minuto
//     (comprobado en net._http_response).
//   · el botón "avisar ahora" de la app manda el JWT del usuario.
// NO se usa verify_jwt=false a propósito: esta función manda WhatsApp a grupos
// de clientes y `_shared/auth.ts:isServiceRoleCall()` acepta un JWT con
// `role=service_role` SIN comprobar la firma (decisión documentada allí,
// asumiendo que el gateway ya la validó). Con verify_jwt=false esa suposición
// se rompe y un token forjado a mano pasaría el filtro.
//
// Además, dentro de la función (defensa en profundidad):
//   · service_role (trigger)                              → permitido
//   · usuario autenticado gerente/supervisor de la tienda → permitido
//   · cualquier otro                                      → 401/403
//
// ── IDEMPOTENCIA ───────────────────────────────────────────────────────────
// Cada fila de `app_wapi_agotado_log` es un mensaje. La clave de idempotencia
// que viaja a OpenWA es `wa-ago-<id_log>`: estable entre reintentos (mismo
// logId ⇒ misma clave ⇒ OpenWA reproduce la respuesta guardada en vez de
// mandar dos veces). Una fila ya `enviado` NO se vuelve a mandar: re-invocar
// con los mismos `log_ids` es seguro.
//
// ── RITMO (anti-ban) ───────────────────────────────────────────────────────
// `delay_min_seconds`/`delay_max_seconds` de la config marcan la pausa
// aleatoria ENTRE destinatarios. La sesión WAPI es UNA sola instancia de
// Puppeteer: los envíos van EN SERIE, nunca en paralelo.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import {
  assertStoreAccess,
  getAuthContext,
  isServiceRoleCall,
  serviceClient,
} from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { isSessionSendable, normalizeWapiStatus } from "../_shared/status.ts";
import { runRecovery } from "../_shared/session_recovery.ts";
import { updateSessionState } from "../_shared/session_store.ts";

// ───────────────────────────────────────────────────────────────────────
//  Constantes
// ───────────────────────────────────────────────────────────────────────

/** Plantilla cuando la config trae `plantilla` NULL o vacía (espejo del
 *  DEFAULT de la migración 20261028_wapi_agotado_notificaciones.sql). */
const PLANTILLA_DEFAULT =
  "⚠️ *PRODUCTO AGOTADO*\n\n🔴 *{producto}*\n🏷️ {categoria}\n💰 {precio}\n📦 Existencias: {stock}\n\nPronto volverá a estar disponible. — {tienda}";

/** Reintentos por mensaje. Los fallos de WAPI son casi siempre transitorios. */
const RETRY_MAX_ATTEMPTS = 3;
const RETRY_BASE_MS = 4_000;

/** Techo de espera que aceptamos cuando el server pide frenar (429/SEND_PACING). */
const PACING_WAIT_MAX_MS = 60_000;

/** Presupuesto de reloj de este worker (los de Edge mueren a los ~400s). Si se
 *  agota, lo que falte queda `pendiente` — re-invocable con los mismos ids. */
const WORKER_BUDGET_MS = 150_000;

/** Tope de longitud del texto (WhatsApp corta por encima de 4096). */
const TEXTO_MAX_CHARS = 1_500;

interface WorkItem {
  logId: number;
  idTienda: number;
  idProducto: number | null;
  idDestinatario: number | null;
  chatId: string;
}

interface Grupo {
  idTienda: number;
  idProducto: number | null;
  items: WorkItem[];
}

// ───────────────────────────────────────────────────────────────────────
//  Utilidades
// ───────────────────────────────────────────────────────────────────────

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function num(v: unknown): number | null {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/** Separador de miles respetando la parte decimal. */
function withThousands(s: string): string {
  const [ent, dec] = s.split(".");
  return ent.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (dec ? `.${dec}` : "");
}

/** Precio con formato; "" si no hay precio utilizable. */
function formatPrice(n: number | null): string {
  if (n == null || !Number.isFinite(n) || n <= 0) return "";
  return `$${withThousands(n % 1 === 0 ? n.toFixed(0) : n.toFixed(2))} CUP`;
}

/** Cantidad sin decimales innecesarios (2.50 → "2.5", 2.00 → "2"). */
function formatQty(n: number | null): string {
  if (n == null || !Number.isFinite(n)) return "";
  const s = Number.isInteger(n)
    ? n.toFixed(0)
    : n.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  return withThousands(s);
}

/**
 * ¿Merece reintento? Los 4xx de validación no (volverían a fallar); los 429
 * NO se resuelven aquí: llevan `retryAfterSeconds` y se respeta esa espera.
 */
function esReintentable(code: string | undefined): boolean {
  if (!code) return true;
  if (code === "NETWORK_ERROR" || code === "SEND_ERROR" || code === "TIMEOUT") {
    return true;
  }
  const m = /^HTTP_(\d{3})$/.exec(code);
  if (m) {
    const status = Number(m[1]);
    return status === 408 || status === 429 || status >= 500;
  }
  return false;
}

/** Sustituye los placeholders del contrato (contrato FROZEN con Flutter). */
function renderPlantilla(
  plantilla: string | null | undefined,
  vars: Record<string, string>,
): string {
  const base = (plantilla ?? "").trim() || PLANTILLA_DEFAULT;
  let out = base;
  for (const [k, v] of Object.entries(vars)) {
    out = out.replaceAll(`{${k}}`, v);
  }
  // Placeholders desconocidos: se dejan tal cual (así se ven en el mensaje y
  // es evidente que la plantilla del usuario tiene una errata), salvo los
  // conocidos que hayan quedado sin valor.
  out = out.replace(/\n{3,}/g, "\n\n").trim();
  return out.length <= TEXTO_MAX_CHARS
    ? out
    : `${out.slice(0, TEXTO_MAX_CHARS - 3)}...`;
}

/** Sesión con la que mandar: la de la config, o la de la tienda. */
async function resolverSesion(
  admin: ReturnType<typeof serviceClient>,
  idTienda: number,
  idSesionPreferida: number | null,
): Promise<any | null> {
  const cols =
    "id, wapi_session_id, status, last_recovery_at, recovery_attempts";

  if (idSesionPreferida) {
    const { data } = await admin
      .from("app_wapi_sesion")
      .select(cols)
      .eq("id", idSesionPreferida)
      .maybeSingle();
    if (data) return data;
  }

  const { data } = await admin
    .from("app_wapi_sesion")
    .select(cols)
    .eq("id_tienda", idTienda)
    .order("last_status_at", { ascending: false })
    .limit(10);

  const lista = (data ?? []) as any[];
  return lista.find((s) => s.status === "CONNECTED") ?? lista[0] ?? null;
}

// ───────────────────────────────────────────────────────────────────────
//  Handler
// ───────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const body: Record<string, unknown> = await req.json().catch(() => ({}));
  const admin = serviceClient();

  const logIds: number[] = Array.isArray(body.log_ids)
    ? (body.log_ids as unknown[]).map(Number).filter((n) => Number.isFinite(n))
    : [];
  let idTienda = num(body.id_tienda);
  const idProducto = num(body.id_producto);

  const esServicio = isServiceRoleCall(req);

  // ── 1. Construir la lista de trabajo ─────────────────────────────────
  let trabajo: WorkItem[] = [];

  if (logIds.length > 0) {
    const { data: filas, error } = await admin
      .from("app_wapi_agotado_log")
      .select("id, id_tienda, id_producto, id_destinatario, chat_id, estado")
      .in("id", logIds);

    if (error) {
      return errorResponse(`Error leyendo app_wapi_agotado_log: ${error.message}`, 500);
    }
    if (!filas || filas.length === 0) {
      return okResponse({ enviados: 0, fallidos: 0, motivo: "sin_filas" });
    }

    if (idTienda == null) {
      idTienda = num((filas[0] as any).id_tienda);
    }

    trabajo = (filas as any[])
      .filter((f) => f.estado !== "enviado")
      .map((f) => ({
        logId: Number(f.id),
        idTienda: Number(f.id_tienda),
        idProducto: num(f.id_producto),
        idDestinatario: num(f.id_destinatario),
        chatId: String(f.chat_id ?? "").trim(),
      }));
  }

  // ── 2. Autorización ──────────────────────────────────────────────────
  // (Se hace después de resolver la tienda porque en modo `log_ids` la tienda
  //  viene de las propias filas.)
  if (!esServicio) {
    if (idTienda == null) {
      return errorResponse("id_tienda o log_ids requeridos", 400, "BAD_REQUEST");
    }
    const ctx = await getAuthContext(req);
    if (!ctx) return errorResponse("No autenticado", 401, "UNAUTHENTICATED");
    const autorizado = await assertStoreAccess(ctx, idTienda);
    if (!autorizado) {
      return errorResponse("No autorizado para esa tienda", 403, "FORBIDDEN");
    }
  }

  if (idTienda == null) {
    return errorResponse("id_tienda requerido", 400, "BAD_REQUEST");
  }

  // ── 3. Config de la tienda ───────────────────────────────────────────
  const { data: config } = await admin
    .from("app_wapi_agotado_config")
    .select("id, id_tienda, id_sesion, activo, plantilla, delay_min_seconds, delay_max_seconds, cooldown_minutos")
    .eq("id_tienda", idTienda)
    .maybeSingle();

  if (!config) {
    if (trabajo.length > 0) {
      await marcar(
        admin,
        trabajo.map((t) => t.logId),
        "omitido",
        "SIN_CONFIG",
        "La tienda no tiene config de aviso de agotado",
      );
    }
    return okResponse({ enviados: 0, fallidos: 0, motivo: "sin_config" });
  }

  if (config.activo !== true) {
    if (trabajo.length > 0) {
      await marcar(
        admin,
        trabajo.map((t) => t.logId),
        "omitido",
        "CONFIG_INACTIVA",
        "El aviso de agotado está desactivado para esta tienda",
      );
    }
    return okResponse({ enviados: 0, fallidos: 0, motivo: "config_inactiva" });
  }

  // ── 4. Modo app: { id_tienda, id_producto } sin logs previos ─────────
  if (trabajo.length === 0) {
    if (idProducto == null) {
      return errorResponse("id_producto requerido", 400, "BAD_REQUEST");
    }

    const { data: dests } = await admin
      .from("app_wapi_agotado_destinatario")
      .select("id_destinatario, app_wapi_destinatario!inner(id, chat_id)")
      .eq("id_config", config.id);

    const destinatarios = ((dests ?? []) as any[])
      .map((d) => ({
        idDestinatario: num(d.id_destinatario),
        chatId: String(
          (Array.isArray(d.app_wapi_destinatario)
            ? d.app_wapi_destinatario[0]?.chat_id
            : d.app_wapi_destinatario?.chat_id) ?? "",
        ).trim(),
      }))
      .filter((d) => d.chatId && /@(c|g)\.us$/.test(d.chatId));

    if (destinatarios.length === 0) {
      return okResponse({
        enviados: 0,
        fallidos: 0,
        motivo: "sin_destinatarios",
      });
    }

    // Reutiliza filas pendientes/fallidas recientes del mismo producto (así el
    // botón "avisar ahora" no duplica el historial del aviso automático).
    const { data: previos } = await admin
      .from("app_wapi_agotado_log")
      .select("id, id_destinatario, estado")
      .eq("id_tienda", idTienda)
      .eq("id_producto", idProducto)
      .in("estado", ["pendiente", "fallido"])
      .order("id", { ascending: false })
      .limit(50);

    const reutilizable = new Map<number, number>();
    for (const p of (previos ?? []) as any[]) {
      const idDest = num(p.id_destinatario);
      if (idDest != null && !reutilizable.has(idDest)) {
        reutilizable.set(idDest, Number(p.id));
      }
    }

    const items: WorkItem[] = [];
    for (const d of destinatarios) {
      let logId = d.idDestinatario != null
        ? reutilizable.get(d.idDestinatario)
        : undefined;

      if (logId == null) {
        const { data: nuevo, error } = await admin
          .from("app_wapi_agotado_log")
          .insert({
            id_tienda: idTienda,
            id_producto: idProducto,
            id_destinatario: d.idDestinatario,
            chat_id: d.chatId,
            estado: "pendiente",
          })
          .select("id")
          .single();
        if (error || !nuevo) {
          console.error(
            `[wapi-notify-agotado] no se pudo encolar para ${d.chatId}: ${error?.message}`,
          );
          continue;
        }
        logId = Number((nuevo as any).id);
      }

      items.push({
        logId,
        idTienda,
        idProducto,
        idDestinatario: d.idDestinatario,
        chatId: d.chatId,
      });
    }

    trabajo = items;
  }

  if (trabajo.length === 0) {
    return okResponse({ enviados: 0, fallidos: 0, motivo: "sin_trabajo" });
  }

  // ── 5. Agrupar por (tienda, producto) ────────────────────────────────
  const grupos = new Map<string, Grupo>();
  for (const item of trabajo) {
    const key = `${item.idTienda}|${item.idProducto ?? 0}`;
    let g = grupos.get(key);
    if (!g) {
      g = { idTienda: item.idTienda, idProducto: item.idProducto, items: [] };
      grupos.set(key, g);
    }
    g.items.push(item);
  }

  // ── 6. Sesión WAPI ───────────────────────────────────────────────────
  const sesion = await resolverSesion(admin, idTienda, num(config.id_sesion));
  if (!sesion?.wapi_session_id) {
    await marcar(
      admin,
      trabajo.map((t) => t.logId),
      "fallido",
      "SIN_SESION",
      "La tienda no tiene sesión WAPI configurada",
    );
    return okResponse({
      enviados: 0,
      fallidos: trabajo.length,
      motivo: "sin_sesion",
    });
  }

  // ¿La sesión está lista de verdad? La copia en BD puede estar obsoleta.
  let statusCrudo: string | null = sesion.status ?? null;
  let listaParaEnviar = isSessionSendable(statusCrudo);

  if (!listaParaEnviar) {
    const live = await wapi.getSession(sesion.wapi_session_id);
    statusCrudo = live.success
      ? ((live.data?.status as string | undefined) ?? null)
      : statusCrudo;

    if (live.success && isSessionSendable(statusCrudo)) {
      listaParaEnviar = true;
      await updateSessionState(admin, sesion.id, {
        status: normalizeWapiStatus(statusCrudo, "CONNECTED"),
        rawStatus: statusCrudo,
        ...(live.data?.phoneNumber ? { phoneNumber: live.data.phoneNumber } : {}),
        resetRecovery: true,
      });
    } else {
      const outcome = await runRecovery(
        wapi,
        sesion.wapi_session_id,
        statusCrudo ?? sesion.status,
        {
          lastRecoveryAt: sesion.last_recovery_at ?? null,
          recoveryAttempts: Number(sesion.recovery_attempts ?? 0),
          linked: Boolean(live.data?.phoneNumber),
        },
      );
      await updateSessionState(admin, sesion.id, {
        status: normalizeWapiStatus(
          outcome.finalRawStatus ?? statusCrudo,
          "DISCONNECTED",
        ),
        rawStatus: outcome.finalRawStatus ?? statusCrudo,
        recoveryAttempt: outcome.action !== "none" && outcome.action !== "cooldown",
        errorCode: outcome.ok ? null : "AGOTADO_SKIPPED_SESSION_DOWN",
        errorMessage: outcome.ok
          ? null
          : `aviso de agotado no enviado: recuperación ${outcome.action} sin éxito`,
      });
      listaParaEnviar = outcome.ok;
    }
  }

  if (!listaParaEnviar) {
    await marcar(
      admin,
      trabajo.map((t) => t.logId),
      "fallido",
      "SESION_CAIDA",
      `La sesión WAPI no está conectada (status=${statusCrudo ?? "?"})`,
    );
    console.error(
      `[wapi-notify-agotado] aviso NO enviado (tienda=${idTienda}): sesión caída ` +
        `(status=${statusCrudo ?? "?"}). Las filas quedan 'fallido' y son re-intentables.`,
    );
    return okResponse({
      enviados: 0,
      fallidos: trabajo.length,
      motivo: "sesion_caida",
      sesion_estado_openwa: statusCrudo,
    });
  }

  const delayMinMs = Math.max(0, Number(config.delay_min_seconds ?? 5)) * 1000;
  const delayMaxMs = Math.max(
    delayMinMs,
    Number(config.delay_max_seconds ?? 10) * 1000,
  );

  const startedAt = Date.now();
  let enviados = 0;
  let fallidos = 0;
  let pendientes = 0;
  const detalles: Record<string, unknown>[] = [];

  // ── 7. Envío EN SERIE ────────────────────────────────────────────────
  let primerEnvio = true;

  for (const grupo of grupos.values()) {
    if (grupo.idProducto == null) {
      await marcar(
        admin,
        grupo.items.map((i) => i.logId),
        "omitido",
        "SIN_PRODUCTO",
        "El producto ya no existe",
      );
      continue;
    }

    // Datos del producto (nombre, categoría, precio vigente, stock, tienda).
    const { data: prod } = await admin
      .from("app_dat_producto")
      .select("id, denominacion, denominacion_corta, id_tienda, app_dat_categoria(denominacion)")
      .eq("id", grupo.idProducto)
      .maybeSingle();

    if (!prod) {
      await marcar(
        admin,
        grupo.items.map((i) => i.logId),
        "omitido",
        "SIN_PRODUCTO",
        "El producto no existe",
      );
      continue;
    }

    const catRaw = (prod as any).app_dat_categoria;
    const categoria = String(
      (Array.isArray(catRaw) ? catRaw[0]?.denominacion : catRaw?.denominacion) ??
        "",
    ).trim();

    // Precio vigente = fila de mayor id (misma semántica que
    // loadProductInfo de wapi-send-products).
    const { data: precioRow } = await admin
      .from("app_dat_precio_venta")
      .select("precio_venta_cup, precio_venta_usd")
      .eq("id_producto", grupo.idProducto)
      .order("id", { ascending: false })
      .limit(1)
      .maybeSingle();

    const precio = num(
      (precioRow as any)?.precio_venta_cup ?? (precioRow as any)?.precio_venta_usd,
    );

    // Stock total con la MISMA función SQL que usa el trigger: una sola
    // semántica para la detección y para el texto del mensaje.
    // `p_hasta_id = null` → total actual (el trigger manda el id del
    // movimiento para calcular el stock previo).
    let stock: number | null = null;
    const { data: stockRpc, error: stockErr } = await admin.rpc(
      "fn_wapi_agotado_stock_total",
      { p_id_producto: grupo.idProducto, p_hasta_id: null },
    );
    if (!stockErr) stock = num(stockRpc);

    const { data: tiendaRow } = await admin
      .from("app_dat_tienda")
      .select("denominacion")
      .eq("id", grupo.idTienda)
      .maybeSingle();

    const texto = renderPlantilla(config.plantilla, {
      producto: String((prod as any).denominacion ?? "").trim() ||
        String((prod as any).denominacion_corta ?? "").trim() || "Producto",
      precio: formatPrice(precio) || "Consultar",
      stock: formatQty(stock ?? 0) || "0",
      categoria: categoria || "General",
      tienda: String((tiendaRow as any)?.denominacion ?? "").trim() || "la tienda",
    });

    for (const item of grupo.items) {
      if (Date.now() - startedAt > WORKER_BUDGET_MS) {
        // Sin presupuesto: la fila se queda `pendiente` (re-invocable con los
        // mismos log_ids). No se pierde ni se marca en falso.
        pendientes += 1;
        continue;
      }

      if (!primerEnvio) {
        const pausa = delayMinMs === delayMaxMs
          ? delayMinMs
          : delayMinMs + Math.round(Math.random() * (delayMaxMs - delayMinMs));
        if (pausa > 0) await sleep(pausa);
      }
      primerEnvio = false;

      const res = await enviarConReintentos(
        sesion.wapi_session_id,
        item.chatId,
        texto,
        `wa-ago-${item.logId}`,
      );

      if (res.ok) {
        await admin
          .from("app_wapi_agotado_log")
          .update({
            estado: "enviado",
            mensaje_id: res.mensajeId ?? null,
            sent_at: new Date().toISOString(),
            error_code: null,
            error_message: null,
          })
          .eq("id", item.logId);
        enviados += 1;
        detalles.push({ log_id: item.logId, chat_id: item.chatId, estado: "enviado" });
      } else {
        await admin
          .from("app_wapi_agotado_log")
          .update({
            estado: "fallido",
            error_code: res.code ?? "SEND_ERROR",
            error_message: (res.message ?? "Error desconocido").slice(0, 500),
          })
          .eq("id", item.logId);
        fallidos += 1;
        detalles.push({
          log_id: item.logId,
          chat_id: item.chatId,
          estado: "fallido",
          error_code: res.code,
        });
      }
    }
  }

  return okResponse({
    enviados,
    fallidos,
    pendientes,
    mensaje: textoResumen(enviados, fallidos, pendientes),
    detalles,
  });
});

// ───────────────────────────────────────────────────────────────────────
//  Envío de un mensaje de texto con reintentos cortos
// ───────────────────────────────────────────────────────────────────────
async function enviarConReintentos(
  wapiSessionId: string,
  chatId: string,
  texto: string,
  idemKey: string,
): Promise<{ ok: boolean; mensajeId?: string; code?: string; message?: string }> {
  let ultimo: { code?: string; message?: string } = {};

  for (let intento = 1; intento <= RETRY_MAX_ATTEMPTS; intento++) {
    const r = await wapi.sendText(wapiSessionId, chatId, texto, idemKey);
    if (r.success) {
      return { ok: true, mensajeId: (r.data as any)?.messageId ?? undefined };
    }

    const code = r.error?.code ?? "SEND_ERROR";
    const message = r.error?.message ?? "Error desconocido";
    ultimo = { code, message };

    // Si el server pide frenar (rate limiter / SEND_PACING), se respeta su
    // plazo: insistir antes sólo alarga el cooldown.
    const pausaSeg = r.error?.retryAfterSeconds ??
      (code === "SEND_PACING_LIMITED" ? 60 : undefined);
    if (pausaSeg && pausaSeg > 0 && intento < RETRY_MAX_ATTEMPTS) {
      const espera = Math.min(pausaSeg * 1000, PACING_WAIT_MAX_MS);
      console.warn(
        `[wapi-notify-agotado] chat=${chatId} ${code}: el server pide ` +
          `${pausaSeg}s — esperando ${Math.round(espera / 1000)}s`,
      );
      await sleep(espera);
      continue;
    }

    const puedeReintentar = intento < RETRY_MAX_ATTEMPTS && esReintentable(code);
    console.error(
      `[wapi-notify-agotado] chat=${chatId} intento ${intento}/${RETRY_MAX_ATTEMPTS} ` +
        `(${code}): ${message}${puedeReintentar ? " — reintentando" : ""}`,
    );
    if (!puedeReintentar) break;

    const base = RETRY_BASE_MS * Math.pow(2, intento - 1);
    await sleep(Math.round(base * (0.75 + Math.random() * 0.5)));
  }

  return { ok: false, ...ultimo };
}

/** Marca un lote de filas del log. Nunca lanza: un fallo aquí no debe tumbar
 *  la respuesta de la función. */
async function marcar(
  admin: ReturnType<typeof serviceClient>,
  ids: number[],
  estado: "pendiente" | "enviado" | "fallido" | "omitido",
  code: string | null,
  message: string | null,
): Promise<void> {
  if (ids.length === 0) return;
  try {
    const { error } = await admin
      .from("app_wapi_agotado_log")
      .update({ estado, error_code: code, error_message: message })
      .in("id", ids);
    if (error) {
      console.error(`[wapi-notify-agotado] no se pudo marcar ${estado}: ${error.message}`);
    }
  } catch (e) {
    console.error(
      `[wapi-notify-agotado] no se pudo marcar ${estado}: ${(e as Error).message}`,
    );
  }
}

function textoResumen(enviados: number, fallidos: number, pendientes: number): string {
  const partes: string[] = [];
  if (enviados > 0) partes.push(`${enviados} enviado(s)`);
  if (fallidos > 0) partes.push(`${fallidos} fallido(s)`);
  if (pendientes > 0) partes.push(`${pendientes} pendiente(s) sin presupuesto`);
  return partes.length > 0 ? partes.join(", ") : "nada que enviar";
}
