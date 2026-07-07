// POST /functions/v1/wapi-list-sessions
// Body: { id_tienda: number }
// Sincroniza con la API WAPI y devuelve la lista de sesiones de la tienda.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const ctx = await getAuthContext(req);
  if (!ctx) return errorResponse("No autenticado", 401);

  const { id_tienda } = await req.json().catch(() => ({}));
  const idTienda = Number(id_tienda);
  if (!Number.isFinite(idTienda)) return errorResponse("id_tienda requerido", 400);
  if (!(await assertStoreAccess(ctx, idTienda))) return errorResponse("Sin acceso", 403);

  // Sesiones locales
  const { data: localSesiones } = await ctx.sb
    .from("app_wapi_sesion")
    .select("*")
    .eq("id_tienda", idTienda)
    .order("created_at", { ascending: false });

  // Sincronizar status con WAPI (best-effort)
  if (localSesiones && localSesiones.length) {
    await Promise.all(localSesiones.map(async (s) => {
      const r = await wapi.getSession(s.wapi_session_id);
      if (r.success && r.data) {
        await ctx.admin.from("app_wapi_sesion").update({
          status: normalizeWapiStatus(r.data.status, s.status),
          phone_number: r.data.phoneNumber ?? s.phone_number,
          last_status_at: new Date().toISOString(),
        }).eq("id", s.id);
      }
    }));
  }

  // Re-read tras sync
  const { data: updated } = await ctx.sb
    .from("app_wapi_sesion")
    .select("*")
    .eq("id_tienda", idTienda)
    .order("created_at", { ascending: false });

  return okResponse({ sesiones: updated ?? [] });
});
