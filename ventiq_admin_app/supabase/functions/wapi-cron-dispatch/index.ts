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

  const { data: prog, error } = await admin
    .from("app_wapi_programacion")
    .select(`
      id, id_tienda, id_sesion, activa,
      delay_min_seconds, delay_max_seconds,
      sesion:app_wapi_sesion!app_wapi_programacion_id_sesion_fkey(
        id, wapi_session_id, status
      )
    `)
    .eq("id", idProg)
    .maybeSingle();

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
  if (sesion.status !== "CONNECTED") {
    return okResponse({
      enviados: 0, fallidos: 0, skipped: true, reason: "session_not_connected",
    });
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
    total_mensajes_estimados: totalMensajes,
    tiempo_estimado_segundos: estimadoSeg,
    message: `Envío programado encolado en wapi-send-products. ` +
      `${totalMensajes} mensajes (~${Math.max(1, Math.ceil(estimadoSeg / 60))} min).`,
  });
});
