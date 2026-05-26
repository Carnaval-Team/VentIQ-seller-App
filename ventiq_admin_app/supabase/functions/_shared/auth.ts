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

/** Detecta si el caller es la propia función dispatcher (autenticada con service role) */
export function isServiceRoleCall(req: Request): boolean {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return false;
  const token = authHeader.replace(/^Bearer\s+/i, "").trim();
  return token === SERVICE_ROLE;
}
