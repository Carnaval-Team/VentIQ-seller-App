// POST /functions/v1/wapi-session-action
// Body: { id_sesion: number, action: 'qr' | 'logout' | 'restart' | 'delete' }
//
// Nota: esta versión fusiona dos linajes que habían divergido:
//   * el artefacto desplegado (v14) → fallback /restart → /start y
//     normalizeWapiStatus(apiRes.data.status, ...)
//   * el código local → acción 'qr' y detección de "already started"
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi, type WapiResult } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";

const ACTIONS: string[] = ["qr", "logout", "restart", "delete"];

/** Sólo nos interesa el `status` de la respuesta; /restart no lo tipa. */
type SessionStatusResult = WapiResult<{ status?: string }>;

/** Un HTTP_400 de WAPI suele significar "el engine ya estaba arrancado". */
function looksAlreadyStarted(
  err?: { code: string; message: string },
): boolean {
  if (!err || err.code !== "HTTP_400") return false;
  const m = err.message.toLowerCase();
  return m.includes("already") || m.includes("running") || m.includes("started");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401);

  const { id_sesion, action } = await req.json().catch(() => ({}));
  const idSesion = Number(id_sesion);
  if (!Number.isFinite(idSesion) || !ACTIONS.includes(action)) {
    return errorResponse("Parámetros inválidos", 400);
  }

  const { data: ses } = await ctx.sb
    .from("app_wapi_sesion").select("*").eq("id", idSesion).maybeSingle();
  if (!ses) return errorResponse("Sesión no encontrada", 404);
  if (!(await assertStoreAccess(ctx, ses.id_tienda))) {
    return errorResponse("Sin acceso", 403);
  }

  // ── qr ────────────────────────────────────────────────────────────────
  // Devuelve el QR. No tocamos la columna status en DB: de eso ya se encarga
  // wapi-session-status, que además persiste last_qr_image.
  if (action === "qr") {
    let qrRes = await wapi.getQr(ses.wapi_session_id);

    // Si el engine está detenido, /qr no devuelve nada útil. Lo arrancamos y
    // reintentamos (mismo patrón que en 'restart').
    if (!qrRes.success) {
      console.warn(
        `[wapi-session-action] /qr falló (${qrRes.error?.code}): ${qrRes.error?.message}. Arrancando engine…`,
      );
      const startRes = await wapi.startSession(ses.wapi_session_id);
      if (!startRes.success) {
        console.warn(
          `[wapi-session-action] /start falló (${startRes.error?.code}): ${startRes.error?.message}`,
        );
      }
      qrRes = await wapi.getQr(ses.wapi_session_id);
    }

    if (!qrRes.success) {
      return errorResponse(
        qrRes.error?.message ?? "No se pudo obtener el QR",
        502,
        qrRes.error?.code,
      );
    }
    return okResponse({ ok: true, status: "SCAN_QR", qr: qrRes.data });
  }

  // ── delete ────────────────────────────────────────────────────────────
  if (action === "delete") {
    const apiRes = await wapi.deleteSession(ses.wapi_session_id);
    if (!apiRes.success) {
      // No bloquear si la API ya no la tiene (404). Limpiamos DB igual.
      console.warn("[wapi-session-action] delete falló:", apiRes.error);
    }
    await ctx.admin.from("app_wapi_sesion").delete().eq("id", ses.id);
    return okResponse({ ok: true });
  }

  let newStatus = ses.status as string;

  if (action === "logout") {
    const apiRes = await wapi.logout(ses.wapi_session_id);
    if (!apiRes.success) {
      return errorResponse(
        apiRes.error?.message ?? "No se pudo desconectar la sesión",
        502,
        apiRes.error?.code,
      );
    }
    newStatus = "DISCONNECTED";
  } else if (action === "restart") {
    // En algunas builds del server WAPI no existe /restart; el endpoint
    // universal para (re)arrancar el engine es POST /api/sessions/:id/start,
    // que además devuelve el status resultante (normalmente qr_ready).
    const restartRes =
      (await wapi.restart(ses.wapi_session_id)) as SessionStatusResult;
    let apiRes = restartRes;
    if (!apiRes.success) {
      console.warn(
        `[wapi-session-action] /restart falló (${apiRes.error?.code}): ${apiRes.error?.message}. Intentando /start…`,
      );
      apiRes =
        (await wapi.startSession(ses.wapi_session_id)) as SessionStatusResult;
    }

    if (apiRes.success) {
      // El server devuelve el objeto sesión con su status actual (p.ej.
      // "qr_ready"). Lo normalizamos; si no trajo status asumimos INITIALIZING.
      newStatus = normalizeWapiStatus(apiRes.data?.status, "INITIALIZING");
    } else if (
      looksAlreadyStarted(apiRes.error) || looksAlreadyStarted(restartRes.error)
    ) {
      // /restart y /start "fallaron" porque el engine YA estaba arrancado:
      // no es un error real, sólo queremos su estado. Antes esto devolvía 502.
      const sesRes = await wapi.getSession(ses.wapi_session_id);
      newStatus = sesRes.success
        ? normalizeWapiStatus(sesRes.data?.status, "INITIALIZING")
        : "SCAN_QR";
    } else {
      return errorResponse(
        apiRes.error?.message ?? "No se pudo reiniciar la sesión en WAPI",
        502,
        apiRes.error?.code,
      );
    }
  }

  await ctx.admin.from("app_wapi_sesion")
    .update({ status: newStatus, last_status_at: new Date().toISOString() })
    .eq("id", ses.id);

  return okResponse({ ok: true, status: newStatus });
});
