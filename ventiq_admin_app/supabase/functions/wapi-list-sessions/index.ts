// POST /functions/v1/wapi-list-sessions
// Body: { id_tienda: number }
// Sincroniza con la API WAPI y devuelve la lista de sesiones de la tienda.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, assertStoreAccess } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus, rawStatusKey } from "../_shared/status.ts";
import { updateSessionState } from "../_shared/session_store.ts";

/** El gateway es UNA instancia: no le lanzamos N getSession en paralelo. */
const LOTE_SINCRONIZACION = 4;

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

  // Sincronizar status con WAPI (best-effort).
  // En lotes: antes era un `Promise.all` sobre TODAS las sesiones, es decir N
  // peticiones simultáneas contra la única instancia de Puppeteer del gateway.
  if (localSesiones && localSesiones.length) {
    for (let i = 0; i < localSesiones.length; i += LOTE_SINCRONIZACION) {
      const lote = localSesiones.slice(i, i + LOTE_SINCRONIZACION);
      await Promise.all(lote.map(async (s) => {
        const r = await wapi.getSession(s.wapi_session_id);
        if (!r.success || !r.data) {
          // Si el sondeo falla NO se inventa un estado: se deja el que había
          // pero se registra, porque un fallo del gateway no es lo mismo que
          // una sesión caída.
          console.warn(
            `[wapi-list-sessions] no se pudo leer la sesión ${s.id} ` +
              `(${r.error?.code}): ${r.error?.message}`,
          );
          return;
        }
        const raw = rawStatusKey(r.data.status);
        const guardado = await updateSessionState(ctx.admin, s.id, {
          status: normalizeWapiStatus(r.data.status, s.status),
          rawStatus: raw || null,
          ...(r.data.phoneNumber ? { phoneNumber: r.data.phoneNumber } : {}),
          // Volvió a estar sana: se limpia la contabilidad de recuperación para
          // que el watchdog no arrastre intentos viejos.
          ...(normalizeWapiStatus(r.data.status, s.status) === "CONNECTED"
            ? { resetRecovery: true, errorCode: null, errorMessage: null }
            : {}),
        });
        if (!guardado.ok) {
          console.error(
            `[wapi-list-sessions] no se pudo guardar el estado de ${s.id}: ${guardado.error}`,
          );
        }
      }));
    }
  }

  // Re-read tras sync
  const { data: updated } = await ctx.sb
    .from("app_wapi_sesion")
    .select("*")
    .eq("id_tienda", idTienda)
    .order("created_at", { ascending: false });

  return okResponse({ sesiones: updated ?? [] });
});
