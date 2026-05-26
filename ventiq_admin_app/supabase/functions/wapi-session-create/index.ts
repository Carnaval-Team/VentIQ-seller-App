// POST /functions/v1/wapi-session-create
// Body: { id_tienda: number, nombre: string }
// Crea una sesión en la API WAPI y la registra en app_wapi_sesion.
import { corsHeaders, handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";

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

  // Webhook apuntando a nuestra función receptora.
  // Si SUPABASE_URL no está set o no es https, omitimos el webhook
  // (WAPI rechaza URLs no-HTTPS o no alcanzables con HTTP 400).
  const supaUrl = (Deno.env.get("SUPABASE_URL") ?? "").replace(/\/$/, "");
  const webhookUrl =
    supaUrl.startsWith("https://")
      ? `${supaUrl}/functions/v1/wapi-webhook?tienda=${idTienda}`
      : undefined;

  console.log(
    `[wapi-session-create] tienda=${idTienda} name=${wapiName} webhook=${webhookUrl ?? "(omitted)"}`,
  );

  // Intento 1: con webhook
  let res = await wapi.createSession(wapiName, webhookUrl);

  // Intento 2: si falló y se mandó webhook, reintentar sin él
  // (el webhook puede registrarse después vía /api/sessions/:id/webhooks)
  if ((!res.success || !res.data) && webhookUrl) {
    console.warn(
      `[wapi-session-create] retry sin webhook (causa: ${res.error?.code} ${res.error?.message})`,
    );
    res = await wapi.createSession(wapiName);
  }

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

  const status = normalizeWapiStatus(dtoLatest.status, "INITIALIZING");
  console.log(
    `[wapi-session-create] sesión creada wapi_id=${dto.id} status_raw=${dtoLatest.status} status_norm=${status}`,
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

  return okResponse({
    id_sesion: inserted.id,
    wapi_session_id: inserted.wapi_session_id,
    status: inserted.status,
    nombre: inserted.nombre,
  });
});
