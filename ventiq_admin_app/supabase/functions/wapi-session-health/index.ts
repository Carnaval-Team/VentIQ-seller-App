// ============================================================================
//  POST /functions/v1/wapi-session-health   ← EL WATCHDOG
//
//  QUÉ PROBLEMA RESUELVE
//    OpenWA pierde la sesión de forma aleatoria (OOM de Chromium, bucle de
//    reconexión, modal "What's new" no confirmado, watchdog interno que la
//    marca como caída). Hasta ahora **nada** del lado de Supabase lo detectaba:
//    la columna `app_wapi_sesion.status` sólo se refrescaba cuando el usuario
//    abría la app, y las difusiones seguían intentando enviar contra una sesión
//    muerta hasta llenar el historial de HTTP_409. El resultado era el
//    "hay que reiniciar la sesión" a mano.
//
//    Esta función es el equivalente del watchdog de OpenWA pero del lado del
//    cliente: sondea, detecta y **recupera** (stop → start, o force-kill →
//    start) sin que nadie abra la app.
//
//  CÓMO SE INVOCA
//    1. pg_cron cada 5 minutos con service_role (job `wapi_session_watchdog`,
//       ver supabase/migrations/20261017_wapi_session_recovery.sql).
//    2. La app Flutter, con JWT: { id_sesion } o { id_tienda } — botón
//       "revisar ahora". Requiere ser gerente/supervisor/auditor de la tienda.
//
//  BODY
//    { id_sesion?: number, id_tienda?: number, dry_run?: boolean, force?: boolean }
//      · sin filtros y con service_role → revisa TODAS las sesiones
//      · dry_run → sólo informa, no toca nada
//      · force   → ignora el cooldown y el contador de intentos
//
//  SEGURIDAD (deliberada)
//    · Con service_role: sólo se recuperan sesiones con `watchdog_enabled` true
//      (se apaga con un `stop` intencionado).
//    · Sesión sin vincular y esperando QR: NO se toca — reiniciar invalidaría
//      el QR que el usuario está a punto de escanear (caso real: la sesión 22
//      de la tienda 177 quedó en SCAN_QR con phone_number nulo).
//    · Cooldown de 10 min y 3 intentos por ventana: sin esto el watchdog
//      martillearía la API con stop/start y la sesión nunca estabilizaría.
// ============================================================================
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import {
  assertStoreAccess,
  getAuthContext,
  isServiceRoleCall,
  serviceClient,
} from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { normalizeWapiStatus, rawStatusKey } from "../_shared/status.ts";
import type { WapiCanonStatus } from "../_shared/status.ts";
import { planRecovery, runRecovery } from "../_shared/session_recovery.ts";
import { updateSessionState } from "../_shared/session_store.ts";

interface SesionRow {
  id: number;
  id_tienda: number;
  nombre: string;
  wapi_session_id: string;
  status: string;
  phone_number: string | null;
  last_status_at: string | null;
  last_recovery_at?: string | null;
  recovery_attempts?: number;
  watchdog_enabled?: boolean;
  raw_status?: string | null;
}

interface InformeSesion {
  id_sesion: number;
  id_tienda: number;
  nombre: string;
  status_bd: string;
  raw_antes: string | null;
  /** Estado crudo observado al cerrar (tras la recuperación, si hubo). */
  raw_despues?: string | null;
  status_normalizado: string | null;
  plan: string;
  motivo: string;
  recuperada: boolean;
  requiere_qr: boolean;
  requiere_confirmacion_manual: boolean;
  terminal: boolean;
  pasos: Array<{ step: string; ok: boolean; code?: string; message?: string }>;
  error: string | null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const fromService = isServiceRoleCall(req);
  const admin = serviceClient();

  let body: {
    id_sesion?: number;
    id_tienda?: number;
    dry_run?: boolean;
    force?: boolean;
  } = {};
  try {
    body = await req.json().catch(() => ({}));
  } catch { /* body vacío */ }

  const idSesion = Number.isFinite(Number(body.id_sesion))
    ? Number(body.id_sesion)
    : null;
  let idTienda = Number.isFinite(Number(body.id_tienda))
    ? Number(body.id_tienda)
    : null;
  const dryRun = body.dry_run === true;
  const force = body.force === true;

  // ── Autorización ───────────────────────────────────────────────────────
  let ctxUserId: string | null = null;
  if (!fromService) {
    const ctx = await getAuthContext(req);
    if (!ctx) return errorResponse("No autenticado", 401, "UNAUTHORIZED");
    ctxUserId = ctx.user.id;

    // Un usuario sólo puede revisar una sesión/tienda de la que sea
    // responsable. Sin filtros no se le permite barrer todo el parque.
    if (idSesion) {
      const { data: ses } = await ctx.sb
        .from("app_wapi_sesion").select("id_tienda").eq("id", idSesion).maybeSingle();
      if (!ses) return errorResponse("Sesión no encontrada", 404);
      if (!(await assertStoreAccess(ctx, ses.id_tienda))) {
        return errorResponse("Sin acceso a la tienda", 403, "FORBIDDEN");
      }
      idTienda = ses.id_tienda;
    } else {
      if (!idTienda) {
        return errorResponse(
          "Con JWT hay que indicar id_sesion o id_tienda",
          400,
          "MISSING_TARGET",
        );
      }
      if (!(await assertStoreAccess(ctx, idTienda))) {
        return errorResponse("Sin acceso a la tienda", 403, "FORBIDDEN");
      }
    }
  }

  // ── Salud del gateway (una sola vez para todo el barrido) ─────────────
  const [salud, listo] = await Promise.all([wapi.health(), wapi.healthReady()]);
  const gateway = {
    ok: salud.success,
    version: (salud.data as Record<string, unknown> | undefined)?.version ?? null,
    ready: listo.success,
    error: salud.error ?? null,
  };
  if (!salud.success) {
    // El gateway entero no contesta: no tiene sentido intentar recuperar
    // sesiones, sería ruido en los logs y tiempo perdido.
    console.error(
      `[wapi-session-health] gateway inalcanzable (${salud.error?.code}): ` +
        `${salud.error?.message}. No se recupera nada.`,
    );
    return okResponse({
      gateway,
      revisadas: 0,
      motivo: "gateway_inaccesible",
      aviso: "OpenWA no responde: revisa el contenedor/proceso antes de culpar a la sesión.",
    });
  }

  // ── Selección de sesiones ─────────────────────────────────────────────
  // Los filtros se aplican ANTES de `order()` para no depender de que el
  // builder conserve el tipo a través de un reasignado.
  let query = admin.from("app_wapi_sesion").select("*");
  if (idSesion) query = query.eq("id", idSesion);
  else if (idTienda) query = query.eq("id_tienda", idTienda);

  const { data: sesiones, error: selErr } = await query.order("id", {
    ascending: true,
  });
  if (selErr) return errorResponse(`Error leyendo sesiones: ${selErr.message}`, 500);

  const informe: InformeSesion[] = [];
  let recuperadas = 0;
  let pendientesQr = 0;
  let requierenHumano = 0;

  for (const s of (sesiones ?? []) as SesionRow[]) {
    const item: InformeSesion = {
      id_sesion: s.id,
      id_tienda: s.id_tienda,
      nombre: s.nombre,
      status_bd: s.status,
      raw_antes: null,
      status_normalizado: null,
      plan: "none",
      motivo: "",
      recuperada: false,
      requiere_qr: false,
      requiere_confirmacion_manual: false,
      terminal: false,
      pasos: [],
      error: null,
    };

    // ── Leer el estado REAL de OpenWA (no el de la BD) ─────────────────
    const live = await wapi.getSession(s.wapi_session_id);
    if (!live.success) {
      item.error = `${live.error?.code}: ${live.error?.message}`;
      informe.push(item);
      continue;
    }
    const raw = live.data?.status ?? null;
    const rawKey = rawStatusKey(raw);
    const canon = normalizeWapiStatus(raw, s.status as WapiCanonStatus);
    item.raw_antes = rawKey || null;
    item.status_normalizado = canon;
    item.raw_despues = rawKey || null;

    // El teléfono puede venir del sondeo aunque la columna esté vacía: es la
    // señal de que la sesión sí está vinculada.
    const vinculada = Boolean(live.data?.phoneNumber ?? s.phone_number);

    const watchdogActivo = s.watchdog_enabled !== false;
    const plan = planRecovery(raw, {
      lastRecoveryAt: s.last_recovery_at ?? null,
      recoveryAttempts: Number(s.recovery_attempts ?? 0),
      linked: vinculada,
      ...(force ? { cooldownMinutes: 0, maxAttempts: Number.MAX_SAFE_INTEGER } : {}),
    });
    item.plan = plan.action;
    item.motivo = plan.reason;
    item.requiere_qr = plan.needsQr;
    item.requiere_confirmacion_manual = plan.needsHumanAck;
    item.terminal = plan.terminal;

    // Persistir el estado observado (barato y siempre útil).
    if (!dryRun) {
      const p = await updateSessionState(admin, s.id, {
        status: canon,
        rawStatus: rawKey || null,
        ...(live.data?.phoneNumber ? { phoneNumber: live.data.phoneNumber } : {}),
        // Volvió a estar sana: el contador de recuperaciones se resetea.
        ...(canon === "CONNECTED" ? { resetRecovery: true } : {}),
      });
      if (!p.ok) item.error = `no se pudo guardar el estado: ${p.error}`;
    }

    if (!watchdogActivo) {
      item.motivo = "watchdog desactivado para esta sesión (se paró a propósito)";
      informe.push(item);
      continue;
    }
    if (plan.action === "none" || plan.action === "cooldown") {
      if (plan.needsQr) pendientesQr++;
      if (plan.needsHumanAck) requierenHumano++;
      informe.push(item);
      continue;
    }

    if (dryRun) {
      informe.push(item);
      continue;
    }

    // ── Recuperar ─────────────────────────────────────────────────────
    console.warn(
      `[wapi-session-health] sesión ${s.id} (${rawKey}) → ${plan.action}: ${plan.reason}`,
    );
    const outcome = await runRecovery(wapi, s.wapi_session_id, raw, {
      lastRecoveryAt: s.last_recovery_at ?? null,
      recoveryAttempts: Number(s.recovery_attempts ?? 0),
      linked: vinculada,
      ...(force ? { cooldownMinutes: 0, maxAttempts: Number.MAX_SAFE_INTEGER } : {}),
    });

    item.pasos = outcome.steps;
    item.recuperada = outcome.ok;
    item.requiere_qr = outcome.needsQr;
    item.requiere_confirmacion_manual = outcome.needsHumanAck;
    item.terminal = outcome.terminal;
    const rawFinal = outcome.finalRawStatus ?? rawKey;
    const canonFinal = normalizeWapiStatus(rawFinal, canon);
    item.status_normalizado = canonFinal;
    // `raw_antes` se conserva: es el estado en el que se cayó. El de después
    // queda en `raw_despues`.
    item.raw_despues = rawFinal || null;

    const fallo = outcome.steps.find((x) => !x.ok);
    const p = await updateSessionState(admin, s.id, {
      status: canonFinal,
      rawStatus: rawFinal || null,
      recoveryAttempt: true,
      ...(canonFinal === "CONNECTED" ? { resetRecovery: true } : {}),
      errorCode: outcome.ok
        ? null
        : (fallo?.code ?? "RECOVERY_FAILED"),
      errorMessage: outcome.ok
        ? null
        : `${fallo?.message ?? plan.reason}`.slice(0, 500),
    });
    if (!p.ok) item.error = `recuperada pero no se pudo guardar: ${p.error}`;

    if (outcome.ok) {
      recuperadas++;
      console.log(
        `[wapi-session-health] sesión ${s.id} recuperada → ${rawFinal} ` +
          `(${outcome.steps.map((x) => `${x.step}:${x.ok ? "ok" : x.code}`).join(",")})`,
      );
    } else {
      console.error(
        `[wapi-session-health] sesión ${s.id} NO se pudo recuperar ` +
          `(${outcome.action}, estado final ${rawFinal}). ` +
          (outcome.needsHumanAck
            ? "Requiere confirmar el modal \"What's new\" en el teléfono."
            : outcome.terminal
            ? "Estado FAILED (terminal en OpenWA): puede hacer falta borrar y revincular."
            : "Revisa los logs de OpenWA.")
      );
      if (outcome.needsQr) pendientesQr++;
      if (outcome.needsHumanAck) requierenHumano++;
    }

    informe.push(item);
  }

  const resumen = {
    gateway,
    modo: dryRun ? "dry-run" : (force ? "forzado" : "normal"),
    filtro: { id_sesion: idSesion, id_tienda: idTienda },
    revisadas: informe.length,
    recuperadas,
    pendientes_de_qr: pendientesQr,
    requieren_confirmacion_manual: requierenHumano,
    iniciado_por: fromService ? "service_role" : `usuario:${ctxUserId}`,
    sesiones: informe,
  };

  console.log(
    `[wapi-session-health] revisadas=${resumen.revisadas} ` +
      `recuperadas=${recuperadas} qr=${pendientesQr} humano=${requierenHumano}`,
  );

  return okResponse(resumen);
});