// POST /functions/v1/wapi-cron-dispatch
// Body: { id_programacion: number }
//
// Invocada por pg_cron (con service_role en el Authorization header).
// Resuelve productos y destinatarios de la programación y DELEGA el envío
// en `wapi-send-products` mediante una invocación HTTP nueva.
//
// ¿Por qué delegar en vez de llamar a `dispatchProducts` aquí?
// Cada worker de Edge Functions tiene un techo de wall-clock (~400s). Si el
// envío corriera dentro del worker de esta invocación, ese techo se
// consumiría con el tiempo que ya gastó el cron (resolver la programación,
// leer productos y destinos) y —peor— el envío quedaría atado a un worker
// que Supabase puede reciclar en cualquier momento, matando la cadena de
// chunks a mitad de camino. Invocando `wapi-send-products` conseguimos un
// worker limpio con su presupuesto completo, y esa función ya sabe
// encadenarse sola cuando el envío no cabe en un solo chunk.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { isServiceRoleCall, serviceClient } from "../_shared/auth.ts";
import { invokeEdgeFunction } from "../_shared/invoke.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { isSessionSendable, normalizeWapiStatus } from "../_shared/status.ts";
import { runRecovery } from "../_shared/session_recovery.ts";
import { updateSessionState } from "../_shared/session_store.ts";

// ───────────────────────────────────────────────────────────────────────
//  Select de la programación + BLINDAJE DEL ORDEN DE DESPLIEGUE
//
//  `solo_disponibles` es una columna NUEVA (migración
//  20261028_wapi_programacion_solo_disponibles). El usuario aplica los
//  cambios a mano, así que puede desplegar esta función ANTES de la
//  migración. Sin blindaje, el `select` fallaría con "column ... does not
//  exist", esta función devolvería 404 "Programación no encontrada" y el cron
//  se saltaría la difusión diaria EN SILENCIO ese día — exactamente la clase
//  de fallo silencioso que ya dejó la programación 13 un mes sin enviar.
//
//  Solución: si (y sólo si) el error es "la columna solo_disponibles no
//  existe", se reintenta el `select` SIN ella, se asume `false` (= el
//  comportamiento anterior: enviar todo) y se avisa en los logs. Cualquier
//  otro orden de despliegue es seguro.
// ───────────────────────────────────────────────────────────────────────

/** Columnas de `app_wapi_programacion` que necesita el dispatcher. */
const COLS_PROG_BASE = `id, id_tienda, id_sesion, activa,
      delay_min_seconds, delay_max_seconds`;

/** Embed de la sesión (FK única → objeto, pero se aceptan las dos formas). */
const COLS_PROG_SESION = `sesion:app_wapi_sesion!app_wapi_programacion_id_sesion_fkey(
        id, wapi_session_id, status
      )`;

/**
 * ¿El error de PostgREST significa "la columna `solo_disponibles` no existe"
 * (migración sin aplicar)?
 *
 * Códigos: `42703` (undefined_column de Postgres) y `PGRST204` (columna no
 * encontrada en el schema cache de PostgREST); también se acepta el mensaje
 * textual, porque según la versión de PostgREST el código varía.
 */
function esErrorColumnaSoloDisponibles(
  error: { code?: string | null; message?: string | null } | null | undefined,
): boolean {
  if (!error) return false;
  const code = String(error.code ?? "");
  const m = String(error.message ?? "").toLowerCase();
  if (m.includes("solo_disponibles")) {
    return m.includes("does not exist") || m.includes("not found") ||
      m.includes("could not find") || m.includes("no existe") ||
      m.includes("unknown");
  }
  // Sin mención explícita a la columna sólo se acepta el código inequívoco de
  // columna inexistente (`42703`); PGRST204/PGRST100 se reservan al caso con
  // mensaje, para no enmascarar otros errores de consulta.
  return code === "42703";
}

/**
 * Carga la programación tolerando que la migración de `solo_disponibles`
 * todavía no esté aplicada (ver el bloque de arriba).
 */
async function cargarProgramacion(
  admin: ReturnType<typeof serviceClient>,
  idProg: number,
): Promise<{
  prog: any;
  error: { code?: string | null; message?: string | null } | null;
  /** `true` si la columna no existe y se ha caído al select antiguo. */
  columnaSoloDisponiblesAusente: boolean;
}> {
  const consultar = (conSoloDisponibles: boolean) =>
    admin
      .from("app_wapi_programacion")
      .select(
        `${COLS_PROG_BASE}${
          conSoloDisponibles ? ", solo_disponibles" : ""
        }, ${COLS_PROG_SESION}`,
      )
      .eq("id", idProg)
      .maybeSingle();

  const primero = await consultar(true);
  if (!primero.error) {
    return { prog: primero.data, error: null, columnaSoloDisponiblesAusente: false };
  }
  if (!esErrorColumnaSoloDisponibles(primero.error)) {
    return {
      prog: null,
      error: primero.error,
      columnaSoloDisponiblesAusente: false,
    };
  }
  console.warn(
    `[wapi-cron-dispatch] la columna app_wapi_programacion.solo_disponibles ` +
      `NO existe todavía (${primero.error.code ?? "?"}: ` +
      `${primero.error.message ?? ""}). Se reintenta el select SIN ella y se ` +
      `asume solo_disponibles=false: la difusión se envía sin filtro de stock ` +
      `(no se pierde). ACCIÓN: aplica la migración ` +
      `20261028_wapi_programacion_solo_disponibles para activar el filtro.`,
  );
  const segundo = await consultar(false);
  return {
    prog: segundo.data,
    error: segundo.error,
    columnaSoloDisponiblesAusente: true,
  };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  if (!isServiceRoleCall(req)) {
    return errorResponse("Solo invocable por service_role", 403);
  }

  const { id_programacion } = await req.json().catch(() => ({}));
  const idProg = Number(id_programacion);
  if (!Number.isFinite(idProg)) return errorResponse("id_programacion requerido", 400);

  const admin = serviceClient();

  const { prog, error, columnaSoloDisponiblesAusente } =
    await cargarProgramacion(admin, idProg);

  // PostgREST devuelve la relación embebida como objeto cuando la FK es única,
  // pero el generador de tipos la infiere como array. Aceptamos las dos formas
  // en vez de asumir una.
  const sesion = (() => {
    const s = (prog as any)?.sesion;
    return (Array.isArray(s) ? s[0] : s) as
      | { id: number; wapi_session_id: string; status: string }
      | undefined;
  })();

  if (error || !prog || !sesion) {
    return errorResponse("Programación no encontrada", 404);
  }
  if (!prog.activa) {
    return okResponse({ enviados: 0, fallidos: 0, skipped: true, reason: "inactive" });
  }
  // ── ¿Está la sesión conectada DE VERDAD? ─────────────────────────────
  // Antes esto se decidía con la copia en BD, que puede estar obsoleta (el
  // webhook llevaba meses registrado sin secret ni eventos `session.*`). El
  // resultado era que la difusión diaria se saltaba EN SILENCIO: la
  // programación 13 de la tienda 177 quedó con last_run_at del 2026-09-07 y
  // nadie se enteró de que llevaba un mes sin enviar.
  // Ahora: se pregunta a OpenWA, se intenta recuperar si hace falta y, si no
  // se puede, se deja constancia en la BD y en los logs (además del 200 con
  // `skipped`, que es lo que espera el cron).
  let sesionLista = sesion.status === "CONNECTED";
  let statusCrudo: string | null = null;
  let recuperacion: string | null = null;

  if (!sesionLista) {
    const live = await wapi.getSession(sesion.wapi_session_id);
    statusCrudo = live.success
      ? ((live.data?.status as string | undefined) ?? null)
      : null;

    if (live.success && isSessionSendable(statusCrudo)) {
      sesionLista = true;
      await updateSessionState(admin, sesion.id, {
        status: normalizeWapiStatus(statusCrudo, "CONNECTED"),
        rawStatus: statusCrudo,
        ...(live.data?.phoneNumber ? { phoneNumber: live.data.phoneNumber } : {}),
        resetRecovery: true,
      });
      console.warn(
        `[wapi-cron-dispatch] programación ${idProg}: la BD decía ` +
          `"${sesion.status}" pero OpenWA responde "${statusCrudo}"`,
      );
    } else {
      const outcome = await runRecovery(
        wapi,
        sesion.wapi_session_id,
        statusCrudo ?? sesion.status,
        {
          lastRecoveryAt: (sesion as any).last_recovery_at ?? null,
          recoveryAttempts: Number((sesion as any).recovery_attempts ?? 0),
          linked: Boolean(live.data?.phoneNumber),
        },
      );
      recuperacion = `${outcome.action}${outcome.ok ? " (ok)" : " (falló)"}`;
      await updateSessionState(admin, sesion.id, {
        status: normalizeWapiStatus(
          outcome.finalRawStatus ?? statusCrudo,
          "DISCONNECTED",
        ),
        rawStatus: outcome.finalRawStatus ?? statusCrudo,
        recoveryAttempt: outcome.action !== "none" && outcome.action !== "cooldown",
        errorCode: outcome.ok ? null : "BROADCAST_SKIPPED_SESSION_DOWN",
        errorMessage: outcome.ok
          ? null
          : `difusión programada saltada: recuperación ${outcome.action} sin éxito`,
      });

      if (!outcome.ok) {
        console.error(
          `[wapi-cron-dispatch] DIFUSIÓN PROGRAMADA SALTADA (prog=${idProg}, ` +
            `tienda=${prog.id_tienda}): la sesión no está conectada ` +
            `(OpenWA="${statusCrudo ?? "?"}", recuperación: ${recuperacion}). ` +
            `Esta programación NO envió nada.`,
        );
        return okResponse({
          enviados: 0,
          fallidos: 0,
          skipped: true,
          reason: "session_not_connected",
          sesion_estado_openwa: statusCrudo,
          recuperacion_intentada: recuperacion,
          alerta: "La difusión programada se saltó por sesión caída. " +
            "Revisa app_wapi_sesion.last_error_code y los logs de OpenWA.",
        });
      }
      sesionLista = true;
      console.warn(
        `[wapi-cron-dispatch] sesión recuperada automáticamente ` +
          `(${recuperacion}) → se envía la difusión programada ${idProg}`,
      );
    }
  }

  // Productos y destinos
  const { data: prods } = await admin
    .from("app_wapi_programacion_producto")
    .select("id_producto, orden")
    .eq("id_programacion", idProg)
    .order("orden", { ascending: true });

  const { data: dests } = await admin
    .from("app_wapi_programacion_destinatario")
    .select(`
      destinatario:app_wapi_destinatario!app_wapi_programacion_destinatario_id_destinatario_fkey(
        id, tipo, chat_id, etiqueta
      )
    `)
    .eq("id_programacion", idProg);

  const productIds = (prods ?? []).map((p: any) => p.id_producto);
  const destinations = (dests ?? [])
    .map((d: any) => d.destinatario)
    .filter(Boolean)
    .map((d: any) => ({ tipo: d.tipo, chat_id: d.chat_id, etiqueta: d.etiqueta }));

  // Sin productos o sin destinos no hay nada que invocar (y
  // `wapi-send-products` respondería 400).
  if (productIds.length === 0 || destinations.length === 0) {
    return okResponse({
      enviados: 0, fallidos: 0, skipped: true,
      reason: productIds.length === 0 ? "no_products" : "no_destinations",
    });
  }

  const delayMinSeg = prog.delay_min_seconds ?? 5;
  const delayMaxSeg = prog.delay_max_seconds ?? 10;
  // `solo_disponibles` (columna añadida en 20261028_wapi_programacion_solo_disponibles):
  // si la programación lo pide, `wapi-send-products` no anuncia productos con
  // stock conocido <= 0. Se reenvía SÓLO cuando es true: así el payload de las
  // programaciones normales queda idéntico al de antes (compatibilidad con
  // versiones viejas de la función, que ignoran el campo de todos modos).
  //
  // Si la columna aún no existe (migración sin aplicar) `cargarProgramacion`
  // ya avisó y devolvió `columnaSoloDisponiblesAusente`: se asume false para
  // no romper la difusión.
  const soloDisponibles = !columnaSoloDisponiblesAusente &&
    (prog as any).solo_disponibles === true;

  // Worker nuevo con 400s frescos. `wapi-send-products` responde en cuanto
  // encola el trabajo, así que esta invocación no espera al envío completo.
  const outcome = await invokeEdgeFunction(
    admin,
    "wapi-send-products",
    {
      id_sesion: prog.id_sesion,
      product_ids: productIds,
      destinations,
      delay_min_seconds: delayMinSeg,
      delay_max_seconds: delayMaxSeg,
      tipo_envio: "programado",
      id_programacion: idProg,
      send_summary: true,
      ...(soloDisponibles ? { solo_disponibles: true } : {}),
    },
    "wapi-cron-dispatch",
  );

  const totalMensajes = productIds.length * destinations.length;
  // Nota: los paréntesis importan. Antes era
  // `(prog.delay_min_seconds ?? 5 + prog.delay_max_seconds ?? 10)`, que por
  // precedencia se evalúa como `min ?? (5 + max) ?? 10` — el estimado salía mal.
  const estimadoSeg = Math.round(
    Math.max(0, productIds.length - 1) * ((delayMinSeg + delayMaxSeg) / 2) +
      productIds.length * destinations.length * 7,
  );

  // Si no se pudo encolar hay que decirlo: devolver 200 haría que pg_cron
  // registrara un éxito para un envío que nunca arrancó.
  if (!outcome.ok) {
    return errorResponse(
      `No se pudo encolar el envío programado: ${outcome.error ?? "error desconocido"}`,
      502,
      "ENQUEUE_FAILED",
    );
  }

  // last_run_at ya se actualizó desde fn_wapi_dispatch_diario; el trigger
  // recalculará next_run_at +1 día.
  return okResponse({
    queued: true,
    via: outcome.via,
    solo_disponibles: soloDisponibles,
    ...(columnaSoloDisponiblesAusente
      ? {
        aviso: "la columna app_wapi_programacion.solo_disponibles no existe: " +
          "aplica la migración 20261028_wapi_programacion_solo_disponibles. " +
          "La difusión se envió SIN filtro de stock.",
      }
      : {}),
    total_mensajes_estimados: totalMensajes,
    tiempo_estimado_segundos: estimadoSeg,
    message: `Envío programado encolado en wapi-send-products. ` +
      `${totalMensajes} mensajes (~${Math.max(1, Math.ceil(estimadoSeg / 60))} min).`,
  });
});
