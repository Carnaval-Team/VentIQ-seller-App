// POST /functions/v1/wapi-session-create
// Body: { id_tienda: number, nombre: string }
// Crea una sesión en la API WAPI (OpenWA) y la registra en app_wapi_sesion.
//
// CAMBIOS CLAVE (ver docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md)
//   1. Se envía el `config` de reconexión por sesión, que antes no se mandaba
//      nunca: `{ reconnectBaseDelay, maxReconnectAttempts }`. Es la única
//      palanca oficial de reconexión, y sin ella el gateway usa sus defaults
//      (reintentos ilimitados con el delay estacionado en 5 minutos).
//   2. El webhook se registra por la ruta DOCUMENTADA,
//      `POST /api/sessions/:id/webhooks`, y **con `secret`**:
//        · antes se metía en el body de `POST /api/sessions` (no documentado),
//          que sólo admite `message.received`/`message.sent` → nunca llegaban
//          los eventos `session.*` y la BD no se enteraba de que la sesión se
//          caía;
//        · y no se mandaba secret, así que las firmas contra
//          WAPI_WEBHOOK_SECRET no podían validar (401 en cada entrega).
//      Ahora se declaran `session.status`, `session.disconnected`,
//      `session.reconnect_loop`, `session.restriction`, `message.ack`, ...
//   3. Se persiste el status CRUDO (`raw_status`) para poder diagnosticar
//      después (p. ej. `action_required` vs `qr_ready`).
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi, WAPI_WEBHOOK_EVENTS } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";
import { updateSessionState } from "../_shared/session_store.ts";

/** Defaults documentados por OpenWA si no se configura nada. */
const RECONNECT_BASE_DELAY_MS =
  Number(Deno.env.get("WAPI_RECONNECT_BASE_DELAY_MS") ?? 5000);
const MAX_RECONNECT_ATTEMPTS =
  Number(Deno.env.get("WAPI_MAX_RECONNECT_ATTEMPTS") ?? 10);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401, "UNAUTHORIZED");

  let body: { id_tienda?: number; nombre?: string };
  try {
    body = await req.json();
  } catch {
    return errorResponse("JSON inválido", 400, "BAD_REQUEST");
  }
  const idTienda = Number(body.id_tienda);
  const nombreOriginal = (body.nombre ?? "").toString().trim();
  if (!Number.isFinite(idTienda) || !nombreOriginal) {
    return errorResponse("id_tienda y nombre son obligatorios", 400);
  }
  if (!(await assertStoreAccess(ctx, idTienda))) {
    return errorResponse("Sin acceso a la tienda", 403, "FORBIDDEN");
  }

  // WAPI suele requerir que el `name` sea un slug ([a-z0-9_-]).
  // Generamos un identificador único y compacto basado en tienda + timestamp,
  // pero conservamos `nombreOriginal` como label visual en la DB.
  const slug =
    nombreOriginal
      .toLowerCase()
      .normalize("NFD")
      .replace(/[̀-ͯ]/g, "")
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-+|-+$/g, "")
      .slice(0, 32) || "bot";
  const wapiName = `t${idTienda}-${slug}-${Date.now().toString(36)}`;

  const supaUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const webhookUrl =
    supaUrl.startsWith("https://")
      ? `${supaUrl}/functions/v1/wapi-webhook?tienda=${idTienda}`
      : undefined;
  const webhookSecret = Deno.env.get("WAPI_WEBHOOK_SECRET") ?? "";

  console.log(
    `[wapi-session-create] tienda=${idTienda} name=${wapiName} ` +
      `webhook=${webhookUrl ?? "(omitted)"} secret=${webhookSecret ? "sí" : "NO"} ` +
      `reconnect=[base=${RECONNECT_BASE_DELAY_MS}ms max=${MAX_RECONNECT_ATTEMPTS}]`,
  );

  // Crear SIN webhook inline: el webhook se registra aparte por la ruta
  // documentada (y con secret). Así no dependemos del body no documentado ni
  // de su fallback "crear otra vez sin webhook".
  const config = {
    ...(Number.isFinite(RECONNECT_BASE_DELAY_MS) && RECONNECT_BASE_DELAY_MS > 0
      ? { reconnectBaseDelay: RECONNECT_BASE_DELAY_MS }
      : {}),
    ...(Number.isFinite(MAX_RECONNECT_ATTEMPTS) && MAX_RECONNECT_ATTEMPTS >= 0
      ? { maxReconnectAttempts: MAX_RECONNECT_ATTEMPTS }
      : {}),
  };

  const res = await wapi.createSession(
    wapiName,
    undefined,
    undefined,
    Object.keys(config).length > 0 ? config : undefined,
  );

  if (!res.success || !res.data) {
    return errorResponse(
      res.error?.message ?? "Error creando sesión en WAPI",
      502,
      res.error?.code,
    );
  }

  const dto = res.data;

  // Después de crear, hay que arrancar el engine explícitamente.
  // El endpoint /start cambia el status de INITIALIZING → SCAN_QR (y emite el QR).
  const startRes = await wapi.startSession(dto.id);
  if (!startRes.success) {
    console.warn(
      `[wapi-session-create] start falló (${startRes.error?.code}): ${startRes.error?.message}`,
    );
  }
  const dtoLatest = startRes.success && startRes.data ? startRes.data : dto;

  // Registro del webhook por la ruta documentada. Best-effort: si falla, la
  // sesión sigue siendo usable (la app sondea el estado), pero se avisa fuerte
  // porque sin eventos `session.*` una caída no se detecta sola.
  let webhookOk = false;
  let webhookError: string | null = null;
  if (webhookUrl) {
    const wh = await wapi.registerWebhook(dto.id, {
      url: webhookUrl,
      events: [...WAPI_WEBHOOK_EVENTS],
      ...(webhookSecret ? { secret: webhookSecret } : {}),
    });
    webhookOk = wh.success;
    if (!wh.success) {
      webhookError = `${wh.error?.code}: ${wh.error?.message}`;
      console.error(
        `[wapi-session-create] NO se pudo registrar el webhook (${webhookError}). ` +
          `La sesión quedará sin eventos session.*: una caída no se detectará ` +
          `sola. Se puede reintentar con wapi-session-action action=register-webhook.`,
      );
    }
  }

  const status = normalizeWapiStatus(dtoLatest.status, "INITIALIZING");
  console.log(
    `[wapi-session-create] sesión creada wapi_id=${dto.id} ` +
      `status_raw=${dtoLatest.status} status_norm=${status} webhook_ok=${webhookOk}`,
  );

  // Insertar en DB (service_role para evitar problemas si RLS bloquea)
  const { data: inserted, error: insErr } = await ctx.admin
    .from("app_wapi_sesion")
    .insert({
      id_tienda: idTienda,
      nombre: nombreOriginal,
      wapi_session_id: dto.id,
      status,
      phone_number: dtoLatest.phoneNumber ?? null,
      created_by: ctx.user.id,
    })
    .select()
    .single();

  if (insErr) {
    // Si falló el insert, intenta limpiar la sesión en WAPI
    try { await wapi.deleteSession(dto.id); } catch (_) { /* ignore */ }
    return errorResponse(`Error guardando sesión: ${insErr.message}`, 500);
  }

  // El status crudo va aparte: si la migración de recuperación aún no está
  // aplicada, `updateSessionState` degrada en vez de romper.
  const patch = await updateSessionState(ctx.admin, inserted.id, {
    rawStatus: dtoLatest.status ? String(dtoLatest.status) : null,
  });
  if (!patch.ok) {
    console.warn(`[wapi-session-create] no se pudo guardar raw_status: ${patch.error}`);
  }

  return okResponse({
    id_sesion: inserted.id,
    wapi_session_id: inserted.wapi_session_id,
    status: inserted.status,
    nombre: inserted.nombre,
    webhook_registrado: webhookOk,
    webhook_error: webhookError,
    reconexion_configurada: config,
    requiere_qr: status !== "CONNECTED",
  });
});