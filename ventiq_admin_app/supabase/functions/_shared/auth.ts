// Helpers de autenticación + clientes Supabase
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;

/** Cliente con privilegios de service_role — bypasea RLS. Usar con cuidado. */
export function serviceClient(): SupabaseClient {
  return createClient(SUPABASE_URL, SERVICE_ROLE, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** Cliente impersonando al usuario que llama (respeta RLS) */
export function userClient(authHeader: string | null): SupabaseClient {
  return createClient(SUPABASE_URL, ANON_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
    global: { headers: authHeader ? { Authorization: authHeader } : {} },
  });
}

export interface AuthContext {
  user: { id: string; email?: string };
  authHeader: string;
  /** Cliente impersonando al usuario (respeta RLS) */
  sb: SupabaseClient;
  /** Cliente con service_role (sin RLS) — para writes en log y dispatcher */
  admin: SupabaseClient;
}

/** Verifica el JWT que viene en el header Authorization. Devuelve null si no válido. */
export async function getAuthContext(req: Request): Promise<AuthContext | null> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return null;

  const sb = userClient(authHeader);
  const { data, error } = await sb.auth.getUser();
  if (error || !data?.user) return null;

  return {
    user: { id: data.user.id, email: data.user.email ?? undefined },
    authHeader,
    sb,
    admin: serviceClient(),
  };
}

/** Verifica que el usuario es gerente o supervisor de la tienda dada. */
export async function assertStoreAccess(
  ctx: AuthContext,
  idTienda: number,
): Promise<boolean> {
  // Las RLS ya filtran, pero hacemos una verificación explícita para mensajes claros
  const { data: g } = await ctx.sb
    .from("app_dat_gerente")
    .select("id")
    .eq("id_tienda", idTienda)
    .eq("uuid", ctx.user.id)
    .maybeSingle();
  if (g) return true;

  const { data: s } = await ctx.sb
    .from("app_dat_supervisor")
    .select("id")
    .eq("id_tienda", idTienda)
    .eq("uuid", ctx.user.id)
    .maybeSingle();
  return !!s;
}

/**
 * Detecta si el caller está usando una service_role key.
 *
 * Aceptamos DOS rutas equivalentes:
 *   1. String-match exacto contra Deno.env.SUPABASE_SERVICE_ROLE_KEY
 *      (caso normal cuando el cron en pg_cron carga el JWT desde la misma
 *      fuente que el runtime).
 *   2. Decodificar el payload del JWT y aceptar cualquier token con
 *      `role === "service_role"` emitido por Supabase. Esto es necesario
 *      porque después de una rotación de claves (HS256↔ES256) la clave
 *      guardada en pg_vault puede ser distinta — en string-bytes — a la
 *      del runtime, aunque ambas autoricen como service_role.
 *
 * Nota: NO validamos la firma aquí. Esta función sólo decide si TRATAR
 * la request como service_role; el gateway de Supabase Edge Functions
 * ya rechazó la request antes si la firma era inválida. Si el gateway
 * está en modo --no-verify-jwt, entonces sí necesitamos algo más fuerte;
 * en ese caso, comprueba que `iss === "supabase"` y `ref === <project_ref>`
 * antes de confiar en el rol.
 */
export function isServiceRoleCall(req: Request): boolean {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return false;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  if (!token) return false;

  // Ruta rápida: match exacto contra la env var del runtime.
  if (SERVICE_ROLE && token === SERVICE_ROLE) return true;

  // Ruta robusta: decodificar el payload y aceptar role=service_role.
  const parts = token.split(".");
  if (parts.length !== 3) return false;
  try {
    // base64url → base64. Atob() de Deno acepta base64 con o sin padding,
    // pero necesitamos cambiar los chars URL-safe (-_) por (+/).
    const b64 = parts[1].replace(/-/g, "+").replace(/_/g, "/");
    const payloadJson = atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4));
    const payload = JSON.parse(payloadJson) as {
      role?: string;
      iss?: string;
      exp?: number;
    };
    if (payload.role !== "service_role") return false;
    if (payload.iss && payload.iss !== "supabase") return false;
    if (typeof payload.exp === "number" && payload.exp * 1000 < Date.now()) {
      return false; // expirado
    }
    return true;
  } catch {
    return false;
  }
}
