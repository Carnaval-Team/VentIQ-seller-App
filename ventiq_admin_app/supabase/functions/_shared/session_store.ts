// ============================================================================
//  Persistencia del estado de una sesión OpenWA — tolerante a migraciones
//
//  POR QUÉ ESTE ARCHIVO
//    Varias funciones (wapi-session-status, wapi-session-action,
//    wapi-session-health, wapi-send-products) escriben lo mismo:
//    status normalizado + teléfono + (si aplica) contabilidad de recuperación.
//    El problema es que las columnas de recuperación
//    (`raw_status`, `last_recovery_at`, `recovery_attempts`,
//    `last_error_code`, `last_error_message`) llegan con una migración
//    aparte; si el código nuevo se despliega ANTES que la migración, un
//    `update()` que las incluya falla con "column does not exist" y se lleva
//    por delante la función entera.
//
//    Aquí se intenta el update completo y, si falla por columna inexistente,
//    se reintenta sólo con las columnas base. Así el código se puede desplegar
//    antes o después de la migración, sin ventana de caída.
//
//  Sin dependencias: no importa supabase-js ni `Deno.env`, así que este módulo
//  es testeable fuera de Deno.
// ============================================================================

/** Cliente mínimo (SupabaseClient lo cumple estructuralmente). */
// deno-lint-ignore no-explicit-any
export type AdminLike = { from(table: string): any };

/** Columnas que existen desde la migración inicial de WAPI. */
const COLUMNAS_BASE = new Set([
  "status",
  "phone_number",
  "last_qr_image",
  "last_status_at",
]);

/** Columnas que añade 20261017_wapi_session_recovery.sql. */
const COLUMNAS_EXTRA = new Set([
  "raw_status",
  "last_recovery_at",
  "recovery_attempts",
  "last_error_code",
  "last_error_message",
  "watchdog_enabled",
]);

export interface SessionStatePatch {
  /** Status canónico (CHECK de la tabla: las 6 valores de siempre). */
  status?: string;
  /** Status CRUDO que reportó OpenWA ("action_required", "qr_ready", ...).
   *  Es lo único que permite diagnosticar después por qué se cayó. */
  rawStatus?: string | null;
  phoneNumber?: string | null;
  lastQrImage?: string | null;
  /** Marca `last_recovery_at = now()` y suma 1 a `recovery_attempts`. */
  recoveryAttempt?: boolean;
  /** Pone `recovery_attempts = 0` (la sesión volvió a estar sana). */
  resetRecovery?: boolean;
  /**
   * Si el watchdog puede recuperar esta sesión. Se apaga con un `stop`
   * intencionado (`wapi-session-action action=stop`) para que el watchdog no
   * resucite lo que el usuario quiso parar; se enciende al reiniciar.
   */
  watchdogEnabled?: boolean;
  errorCode?: string | null;
  errorMessage?: string | null;
}

export interface UpdateResult {
  ok: boolean;
  /** Se aplicó sin las columnas de la migración de recuperación. */
  degraded: boolean;
  error?: string;
}

function separar(patch: SessionStatePatch): {
  base: Record<string, unknown>;
  extra: Record<string, unknown>;
} {
  const base: Record<string, unknown> = {
    last_status_at: new Date().toISOString(),
  };
  const extra: Record<string, unknown> = {};

  if (patch.status !== undefined) base.status = patch.status;
  if (patch.phoneNumber !== undefined) base.phone_number = patch.phoneNumber;
  if (patch.lastQrImage !== undefined) base.last_qr_image = patch.lastQrImage;

  if (patch.rawStatus !== undefined) extra.raw_status = patch.rawStatus;
  if (patch.watchdogEnabled !== undefined) {
    extra.watchdog_enabled = patch.watchdogEnabled;
  }
  if (patch.errorCode !== undefined) extra.last_error_code = patch.errorCode;
  if (patch.errorMessage !== undefined) {
    extra.last_error_message = patch.errorMessage;
  }
  if (patch.recoveryAttempt) extra.last_recovery_at = new Date().toISOString();
  if (patch.resetRecovery) extra.recovery_attempts = 0;

  return { base, extra };
}

/** ¿El error de Postgres/PostgREST es "esa columna no existe"? */
function columnaInexistente(msg: string | undefined): boolean {
  if (!msg) return false;
  const m = msg.toLowerCase();
  return (m.includes("column") && m.includes("does not exist")) ||
    m.includes("schema cache") || m.includes("could not find");
}

/**
 * Aplica el patch. Nunca lanza: devuelve `ok/degraded/error` para que quien
 * llama decida si merece la pena loguear o abortar.
 *
 * `recoveryAttempt` sólo se puede incrementar con SQL (requiere leer el valor
 * actual para sumarle 1), así que aquí se hace en dos pasos: leer y escribir.
 * Si la lectura falla, se deja sin tocar el contador en vez de inventar un 1.
 */
export async function updateSessionState(
  admin: AdminLike,
  idSesion: number,
  patch: SessionStatePatch,
): Promise<UpdateResult> {
  const { base, extra } = separar(patch);

  if (patch.recoveryAttempt) {
    extra.recovery_attempts = await nextRecoveryAttempt(admin, idSesion);
  }

  const completo = { ...base, ...extra };
  if (Object.keys(extra).length === 0) {
    return await aplicar(admin, idSesion, base);
  }

  const res = await aplicar(admin, idSesion, completo);
  if (res.ok || !columnaInexistente(res.error)) return res;

  // La migración de recuperación no está aplicada: seguimos con lo básico.
  console.warn(
    `[session_store] la columna extra no existe todavía ` +
      `(${res.error}) — se guarda sólo el estado base. ` +
      `Aplica supabase/migrations/20261017_wapi_session_recovery.sql.`,
  );
  const degradado = await aplicar(admin, idSesion, base);
  return { ...degradado, degraded: true };
}

async function aplicar(
  admin: AdminLike,
  idSesion: number,
  valores: Record<string, unknown>,
): Promise<UpdateResult> {
  try {
    const { error } = await admin
      .from("app_wapi_sesion")
      .update(valores)
      .eq("id", idSesion);
    if (error) return { ok: false, degraded: false, error: error.message };
    return { ok: true, degraded: false };
  } catch (e) {
    return { ok: false, degraded: false, error: (e as Error).message ?? String(e) };
  }
}

async function nextRecoveryAttempt(
  admin: AdminLike,
  idSesion: number,
): Promise<number> {
  try {
    const { data, error } = await admin
      .from("app_wapi_sesion")
      .select("recovery_attempts")
      .eq("id", idSesion)
      .maybeSingle();
    if (error || !data) return 1;
    return Number((data as { recovery_attempts?: number }).recovery_attempts ?? 0) + 1;
  } catch {
    return 1;
  }
}

/** Marca el update como "sólo columnas base" (para tests/uso manual). */
export function columnasConocidas(): { base: string[]; extra: string[] } {
  return { base: [...COLUMNAS_BASE], extra: [...COLUMNAS_EXTRA] };
}