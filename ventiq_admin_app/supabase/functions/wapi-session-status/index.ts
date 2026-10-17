// POST /functions/v1/wapi-session-status
// Body: { id_sesion: number, include_qr?: boolean }
// Devuelve el estado actual de una sesión, e incluye QR si está en SCAN_QR.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus, rawStatusKey } from "../_shared/status.ts";
import { updateSessionState } from "../_shared/session_store.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401, "UNAUTHORIZED");

  const { id_sesion, include_qr } = await req.json().catch(() => ({}));
  const idSesion = Number(id_sesion);
  if (!Number.isFinite(idSesion)) {
    return errorResponse("id_sesion requerido", 400);
  }

  const { data: ses, error } = await ctx.sb
    .from("app_wapi_sesion")
    .select("*")
    .eq("id", idSesion)
    .maybeSingle();
  if (error || !ses) return errorResponse("Sesión no encontrada", 404);
  if (!(await assertStoreAccess(ctx, ses.id_tienda))) {
    return errorResponse("Sin acceso a la tienda", 403);
  }

  // 1) Consultar status (GET /api/sessions/:id)
  const sessionRes = await wapi.getSession(ses.wapi_session_id);
  let status = ses.status;
  let phoneNumber: string | undefined = ses.phone_number ?? undefined;
  if (sessionRes.success && sessionRes.data) {
    status = normalizeWapiStatus(sessionRes.data.status, ses.status);
    phoneNumber = sessionRes.data.phoneNumber ?? phoneNumber;
  }

  // 2) QR vive en otro endpoint (GET /api/sessions/:id/qr) y rota cada ~10s.
  //    Lo pedimos cuando el caller lo pida o el status indique que es necesario.
  //    También intentamos en INITIALIZING porque algunas builds devuelven QR
  //    antes de cambiar el status a SCAN_QR.
  let qr: { image?: string; code?: string } | undefined;
  const needsQr =
    include_qr ||
    status === "SCAN_QR" ||
    status === "INITIALIZING" ||
    status === "CONNECTING";
  if (needsQr && status !== "CONNECTED" && status !== "DISCONNECTED") {
    const qrRes = await wapi.getQr(ses.wapi_session_id);
    if (qrRes.success && qrRes.data) {
      // OpenWA actual devuelve `qrCode` (data URL) + `status: "qr_ready"`.
      // La doc oficial documenta `image` + `code`. Aceptamos ambas formas.
      const d = qrRes.data;
      const image =
        d.image ?? d.qrCode ??
        (typeof (d as Record<string, unknown>)["qr"] === "string"
          ? ((d as Record<string, unknown>)["qr"] as string)
          : undefined);
      const code = d.code ?? d.qrText;
      if (image || code) {
        qr = { image, code };
      }
      // Si el endpoint QR devolvió un status, úsalo (es más preciso que /sessions/:id)
      if (d.status) {
        status = normalizeWapiStatus(d.status, status);
      }
    } else if (qrRes.error) {
      console.log(
        `[wapi-session-status] QR no disponible (${qrRes.error.code}): ${qrRes.error.message}`,
      );
    }
  }

  // Persistir cambios. Se guarda además el status CRUDO: es lo único que
  // permite diagnosticar después un `action_required` (modal "What's new" de
  // WhatsApp) o un `failed`, que el normalizado colapsa a DISCONNECTED/FAILED.
  const res = await updateSessionState(ctx.admin, ses.id, {
    status,
    rawStatus: sessionRes.success && sessionRes.data
      ? (rawStatusKey(sessionRes.data.status) || null)
      : (rawStatusKey(ses.raw_status) || null),
    ...(phoneNumber ? { phoneNumber } : {}),
    ...(qr?.image ? { lastQrImage: qr.image } : {}),
  });
  if (!res.ok) {
    console.error(`[wapi-session-status] no se pudo guardar el estado: ${res.error}`);
  }

  return okResponse({
    id_sesion: ses.id,
    wapi_session_id: ses.wapi_session_id,
    status,
    phone_number: phoneNumber ?? null,
    qr: qr ?? null,
    // Aviso explícito para la UI: `action_required` no se arregla reiniciando
    // sin más, hay que confirmar el modal en el teléfono una vez.
    requiere_confirmacion_manual: status === "DISCONNECTED" &&
      rawStatusKey(sessionRes.data?.status) === "ACTION_REQUIRED",
  });
});
