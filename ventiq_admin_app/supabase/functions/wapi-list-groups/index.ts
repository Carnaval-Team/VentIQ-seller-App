// POST /functions/v1/wapi-list-groups
// Body: { id_sesion: number }
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";

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
  if (ses.status !== "CONNECTED") {
    return errorResponse("La sesión no está conectada", 409, "NOT_CONNECTED");
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
