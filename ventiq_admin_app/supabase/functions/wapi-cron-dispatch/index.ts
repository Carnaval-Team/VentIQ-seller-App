// POST /functions/v1/wapi-cron-dispatch
// Body: { id_programacion: number }
//
// Invocada por pg_cron (con service_role en el Authorization header).
// Resuelve productos y destinatarios de la programación y delega
// en la lógica core de wapi-send-products (anti-ban incluido).
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { isServiceRoleCall, serviceClient } from "../_shared/auth.ts";
import { dispatchProducts } from "../wapi-send-products/index.ts";

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
  if (error || !prog || !prog.sesion) {
    return errorResponse("Programación no encontrada", 404);
  }
  if (!prog.activa) {
    return okResponse({ enviados: 0, fallidos: 0, skipped: true, reason: "inactive" });
  }
  if (prog.sesion.status !== "CONNECTED") {
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

  try {
    const res = await dispatchProducts({
      admin,
      idSesion: prog.id_sesion,
      idTienda: prog.id_tienda,
      wapiSessionId: prog.sesion.wapi_session_id,
      productIds,
      destinations,
      delayMin: prog.delay_min_seconds ?? 30,
      delayMax: prog.delay_max_seconds ?? 90,
      tipoEnvio: "programado",
      idProgramacion: idProg,
    });

    // last_run_at ya se actualizó desde fn_wapi_dispatch_diario; el trigger
    // recalculará next_run_at +1 día.
    return okResponse(res);
  } catch (err) {
    return errorResponse((err as Error).message ?? String(err), 500);
  }
});
