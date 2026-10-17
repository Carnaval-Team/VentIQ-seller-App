// POST /functions/v1/wapi-list-groups
// Body: { id_sesion: number }
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { isSessionSendable, rawStatusKey } from "../_shared/status.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401);

  const { id_sesion } = await req.json().catch(() => ({}));
  const idSesion = Number(id_sesion);
  if (!Number.isFinite(idSesion)) return errorResponse("id_sesion requerido", 400);

  const { data: ses } = await ctx.sb
    .from("app_wapi_sesion").select("*").eq("id", idSesion).maybeSingle();
  if (!ses) return errorResponse("Sesión no encontrada", 404);
  if (!(await assertStoreAccess(ctx, ses.id_tienda))) return errorResponse("Sin acceso", 403);
  // La columna `status` puede estar obsoleta: se pregunta al gateway antes de
  // rechazar. Listar grupos sólo necesita que la sesión esté viva; no se
  // intenta recuperar aquí (es una lectura, no una difusión).
  if (ses.status !== "CONNECTED") {
    const live = await wapi.getSession(ses.wapi_session_id);
    const raw = live.success ? (live.data?.status as string | undefined) : undefined;
    if (!live.success || !isSessionSendable(raw)) {
      return errorResponse(
        `La sesión no está conectada (OpenWA: ${rawStatusKey(raw) || "desconocido"}). ` +
          `Reiníciala con wapi-session-action action=restart.`,
        409,
        "NOT_CONNECTED",
      );
    }
    console.warn(
      `[wapi-list-groups] BD="${ses.status}" pero OpenWA="${raw}": se continúa`,
    );
  }

  const r = await wapi.listGroups(ses.wapi_session_id);
  if (!r.success) {
    return errorResponse(r.error?.message ?? "Error listando grupos", 502, r.error?.code);
  }

  const grupos = (r.data ?? []).map((g) => ({
    chatId: g.id,
    name: g.name,
    description: g.description ?? null,
    participantsCount: g.participantsCount ?? null,
  }));
  return okResponse({ grupos });
});
