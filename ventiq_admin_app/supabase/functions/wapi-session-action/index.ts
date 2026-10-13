// POST /functions/v1/wapi-session-action
// Body: { id_sesion: number, action: 'qr' | 'logout' | 'restart' | 'delete' }
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401);

  const { id_sesion, action } = await req.json().catch(() => ({}));
  const idSesion = Number(id_sesion);
  if (!Number.isFinite(idSesion) || !["qr", "logout", "restart", "delete"].includes(action)) {
    return errorResponse("Parámetros inválidos", 400);
  }

  const { data: ses } = await ctx.sb
    .from("app_wapi_sesion").select("*").eq("id", idSesion).maybeSingle();
  if (!ses) return errorResponse("Sesión no encontrada", 404);
  if (!(await assertStoreAccess(ctx, ses.id_tienda))) {
    return errorResponse("Sin acceso", 403);
  }

  if (action === "qr") {
    const qrRes = await wapi.getQr(ses.wapi_session_id);
    if (!qrRes.success) {
      return errorResponse(
        qrRes.error?.message ?? "No se pudo obtener el QR",
        502,
        qrRes.error?.code,
      );
    }
    return okResponse({ ok: true, status: "SCAN_QR", qr: qrRes.data });
  }

  let apiRes;
  let newStatus = ses.status as string;
  switch (action) {
    case "logout":
      apiRes = await wapi.logout(ses.wapi_session_id);
      newStatus = "DISCONNECTED";
      break;
    case "restart":
      apiRes = await wapi.restart(ses.wapi_session_id);
      newStatus = "INITIALIZING";
      if (
        !apiRes.success &&
        apiRes.error?.code === "HTTP_400" &&
        apiRes.error.message.toLowerCase().includes("already started")
      ) {
        apiRes = await wapi.getQr(ses.wapi_session_id);
        newStatus = "SCAN_QR";
      }
      break;
    case "delete":
      apiRes = await wapi.deleteSession(ses.wapi_session_id);
      break;
  }

  if (!apiRes!.success) {
    // No bloquear si la API ya no la tiene (404). Continuamos limpiando DB.
    console.warn("WAPI action failed:", apiRes!.error);
  }

  if (action === "delete") {
    await ctx.admin.from("app_wapi_sesion").delete().eq("id", ses.id);
    return okResponse({ ok: true });
  }

  await ctx.admin.from("app_wapi_sesion")
    .update({ status: newStatus, last_status_at: new Date().toISOString() })
    .eq("id", ses.id);

  return okResponse({ ok: true, status: newStatus });
});
