// ============================================================================
//  Escalera de recuperación de sesiones OpenWA
//
//  POR QUÉ EXISTE
//    OpenWA (whatsapp-web.js) pierde la sesión de forma silenciosa: el engine
//    se cae, el evento `session.disconnected`/`session.reconnect_loop` no llega
//    (o llega y nadie lo procesa) y a partir de ahí **todo envío falla** con
//    HTTP_409 "Session is not connected" o HTTP_400 "Session '…' is not
//    active", fila tras fila, hasta que una persona entra a la app y pulsa
//    "reiniciar". En producción eso dejó 4.995 filas `fallido` y 565
//    `pendiente` (ver docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md).
//
//  QUÉ HACE
//    Traduce el estado crudo que reporta OpenWA a un plan de recuperación y lo
//    ejecuta contra la API usando la escalera oficial:
//
//      ready/connected ............................ nada
//      initializing/created/qr_ready/authenticating  POST /start
//      disconnected ............................... POST /stop → /start
//      action_required ............................ POST /stop → /start, y hay
//                                                   que confirmar el modal
//                                                   "What's new" una vez
//      failed ..................................... stop → start, y si sigue
//                                                   caída: force-kill → start
//      sigue caída tras un ciclo completo ......... force-kill → /start
//
//    OJO: **no existe `/restart`** en OpenWA. Su runbook lo dice literal:
//    "Try session restart (stop then start — there is no /restart route)".
//
//  DISEÑO
//    El planificador (`planRecovery`) es una función PURA: recibe el estado y
//    devuelve la acción. El ejecutor (`runRecovery`) recibe el cliente por
//    parámetro (inyección) para poder probarlo sin red y sin Deno. Ninguno de
//    los dos toca la BD ni conoce a Supabase.
// ============================================================================

/** Forma estructural mínima de una respuesta de la API. Compatible con
 *  `WapiResult` de wapi_client.ts, pero declarada aquí para que este módulo se
 *  pueda importar (y testear) sin arrastrar `Deno.env`. */
export interface WapiCallResult<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    retryAfterSeconds?: number;
  };
}

/** Cliente mínimo que necesita la escalera. */
export interface RecoveryClient {
  stopSession(sessionId: string): Promise<WapiCallResult<unknown>>;
  startSession(sessionId: string): Promise<WapiCallResult<{ status?: string }>>;
  forceKill(sessionId: string): Promise<WapiCallResult<unknown>>;
  getSession(
    sessionId: string,
  ): Promise<WapiCallResult<{ status?: string; phoneNumber?: string }>>;
}

export type RecoveryAction =
  | "none"
  | "start"
  | "stop-start"
  | "force-kill-start"
  | "cooldown";

export interface RecoveryPlan {
  action: RecoveryAction;
  /** Por qué se eligió (para logs/telemetría). */
  reason: string;
  /** Tras recuperar habrá que volver a escanear el QR. */
  needsQr: boolean;
  /** Hay que confirmar el modal "What's new" a mano (estado action_required). */
  needsHumanAck: boolean;
  /** `failed` es terminal en OpenWA: no lo reanuda ningún camino automático. */
  terminal: boolean;
}

export interface RecoveryOptions {
  /** Última recuperación aplicada a esta sesión (ISO). null = nunca. */
  lastRecoveryAt?: string | null;
  /** Recuperaciones ya intentadas dentro de la ventana de cooldown. */
  recoveryAttempts?: number;
  /** Minutos mínimos entre recuperaciones de la misma sesión. */
  cooldownMinutes?: number;
  /** Intentos máximos dentro de la ventana antes de rendirse y avisar. */
  maxAttempts?: number;
  /**
   * ¿La sesión está vinculada a un teléfono (tiene credenciales)?
   *
   * Si es `false` y la sesión está en un estado del flujo de vinculación
   * (`created`/`initializing`/`qr_ready`/`authenticating`), NO se toca: el
   * reinicio generaría un QR nuevo e invalidaría el que el usuario está a punto
   * de escanear. Default `true` (no bloquea nada).
   */
  linked?: boolean;
  /** Inyectable para tests. */
  now?: Date;
}

export interface RecoveryOutcome {
  action: RecoveryAction;
  ok: boolean;
  /** Estado crudo final leído de OpenWA (si se pudo leer). */
  finalRawStatus: string | null;
  needsHumanAck: boolean;
  needsQr: boolean;
  terminal: boolean;
  steps: Array<{
    step: string;
    ok: boolean;
    code?: string;
    message?: string;
  }>;
  /** Horas de espera que pidió el server en algún paso (429). */
  retryAfterSeconds?: number;
}

export const RECOVERY_COOLDOWN_MINUTES = 10;
export const RECOVERY_MAX_ATTEMPTS = 3;
/** Margen entre `/stop` y `/start`: el engine necesita soltar el socket. */
export const STOP_SETTLE_MS = 3_000;

// ── Normalización local (duplicada a propósito de status.ts para no crear
//    dependencias: este módulo se ejecuta en pruebas sin Deno).
function key(raw: unknown): string {
  if (raw == null) return "";
  return String(raw).trim().toUpperCase().replace(/[\s.-]+/g, "_");
}

const SENDABLE = new Set(["READY", "CONNECTED", "ONLINE", "OPEN", "ACTIVE"]);
const TERMINAL = new Set(["FAILED", "FAIL", "FATAL", "CRASHED", "TERMINATED"]);
const DOWN = new Set([
  "DISCONNECTED",
  "OFFLINE",
  "LOGGED_OUT",
  "CLOSED",
  "STOPPED",
  "TIMEOUT",
  "DELETED",
  "UNLINKED",
  "RESTRICTED",
  "RESTRICTION",
  "SUSPENDED",
  "BANNED",
]);
/** Necesita acción humana además del reinicio. */
const HUMAN = new Set([
  "ACTION_REQUIRED",
  "ATTENTION_REQUIRED",
  "RESTRICTED",
  "RESTRICTION",
  "SUSPENDED",
  "BANNED",
]);

export function isReady(raw: unknown): boolean {
  return SENDABLE.has(key(raw));
}

export function isTerminal(raw: unknown): boolean {
  return TERMINAL.has(key(raw));
}

/**
 * Decide la acción. Pura: mismas entradas ⇒ misma salida.
 *
 * El cooldown va PRIMERO: si ya intentamos recuperar esta sesión hace menos de
 * `cooldownMinutes`, no volvemos a martillear la API (un stop/start cada
 * minuto desde el watchdog dejaría la sesión en un bucle peor que la caída).
 */
export function planRecovery(
  rawStatus: unknown,
  opts: RecoveryOptions = {},
): RecoveryPlan {
  const k = key(rawStatus);
  const terminal = TERMINAL.has(k);
  const needsHumanAck = HUMAN.has(k);

  if (SENDABLE.has(k)) {
    return {
      action: "none",
      reason: "sesión lista",
      needsQr: false,
      needsHumanAck: false,
      terminal: false,
    };
  }

  // Estados intermedios: el engine no está arrancado (o lo está a medias).
  // Basta `/start`, que es el (re)arranque universal.
  if (
    !k || k === "CREATED" || k === "INITIALIZING" || k === "STARTING" ||
    k === "PENDING" || k === "BOOTING" || k === "LOADING" ||
    k === "ENGINE_LOADING" || k === "QR_READY" || k === "QR_CODE" ||
    k === "QR_REQUIRED" || k === "WAITING_FOR_QR" || k === "QR" ||
    k === "AUTHENTICATING" || k === "AUTHENTICATED" || k === "PAIRING" ||
    k === "PAIRING_CODE" || k === "RECONNECTING" || k === "REINJECTING"
  ) {
    // Sesión sin vincular: no se toca, o el reinicio invalidaría el QR que el
    // usuario está escaneando. Esto importa: tras recrear la sesión quedó en
    // SCAN_QR con phone_number nulo, y un watchdog que la reiniciara cada 5 min
    // haría imposible vincularla nunca.
    if (opts.linked === false && !TERMINAL.has(k) && !DOWN.has(k)) {
      return {
        action: "none",
        reason: "sesión sin vincular (esperando QR): no se reinicia para no invalidar el QR",
        needsQr: true,
        needsHumanAck,
        terminal,
      };
    }
    const enQr = k.startsWith("QR") || k === "WAITING_FOR_QR";
    return {
      action: "start",
      reason: k ? `estado intermedio ${k}: hace falta arrancar el engine` : "sin estado legible",
      needsQr: enQr,
      needsHumanAck,
      terminal,
    };
  }

  const intentos = opts.recoveryAttempts ?? 0;
  const max = opts.maxAttempts ?? RECOVERY_MAX_ATTEMPTS;
  const cooldown = opts.cooldownMinutes ?? RECOVERY_COOLDOWN_MINUTES;
  const ahora = opts.now ?? new Date();

  if (intentos >= max) {
    return {
      action: "cooldown",
      reason: `ya se intentó recuperar ${intentos} vez/veces sin éxito — requiere revisión manual`,
      needsQr: true,
      needsHumanAck,
      terminal,
    };
  }
  if (opts.lastRecoveryAt) {
    const t = Date.parse(opts.lastRecoveryAt);
    if (Number.isFinite(t)) {
      const minutos = (ahora.getTime() - t) / 60_000;
      if (minutos < cooldown) {
        return {
          action: "cooldown",
          reason: `recuperación reciente (hace ${Math.round(minutos)} min < ${cooldown} min)`,
          needsQr: false,
          needsHumanAck,
          terminal,
        };
      }
    }
  }

  // `failed` es terminal: la escalada completa (matar el engine y volver a
  // arrancar) es la única que tiene algo que rascar.
  if (terminal) {
    return {
      action: "force-kill-start",
      reason: "sesión FAILED (estado terminal en OpenWA): force-kill → start",
      needsQr: true,
      needsHumanAck,
      terminal: true,
    };
  }

  // `action_required`: el reinicio es necesario pero NO suficiente; hay que
  // confirmar el modal a mano una vez.
  if (needsHumanAck) {
    return {
      action: "stop-start",
      reason: `estado ${k}: reinicio soportado + confirmar el modal "What's new" a mano`,
      needsQr: false,
      needsHumanAck: true,
      terminal: false,
    };
  }

  if (DOWN.has(k)) {
    return {
      action: "stop-start",
      reason: `sesión caída (${k}): reinicio soportado (stop → start)`,
      needsQr: false,
      needsHumanAck: false,
      terminal: false,
    };
  }

  // Estado desconocido: no asumimos. Se reporta, no se toca la sesión.
  return {
    action: "none",
    reason: `estado "${rawStatus}" no reconocido: no se actúa (revisar versión de OpenWA)`,
    needsQr: false,
    needsHumanAck: false,
    terminal: false,
  };
}

/** ¿El error de `/stop` significa "no había engine que parar"? No es un fallo. */
function stopSinEngine(err?: { code?: string; message?: string }): boolean {
  if (!err) return false;
  if (err.code === "HTTP_400" || err.code === "HTTP_404") return true;
  const m = (err.message ?? "").toLowerCase();
  return m.includes("not active") || m.includes("no live engine") ||
    m.includes("not found") || m.includes("not running");
}

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

/**
 * Ejecuta el plan. Nunca lanza: devuelve el resultado con el detalle de cada
 * paso, porque quien llama (watchdog, wapi-send-products) necesita seguir
 * funcionando aunque la recuperación falle.
 */
export async function runRecovery(
  client: RecoveryClient,
  sessionId: string,
  rawStatus: unknown,
  opts: RecoveryOptions & { settleMs?: number; verify?: boolean } = {},
): Promise<RecoveryOutcome> {
  const plan = planRecovery(rawStatus, opts);
  const out: RecoveryOutcome = {
    action: plan.action,
    ok: false,
    finalRawStatus: key(rawStatus) || null,
    needsHumanAck: plan.needsHumanAck,
    needsQr: plan.needsQr,
    terminal: plan.terminal,
    steps: [],
  };
  if (plan.action === "none" || plan.action === "cooldown") {
    out.ok = plan.action === "none";
    out.steps.push({ step: "plan", ok: plan.action === "none", message: plan.reason });
    return out;
  }

  const settleMs = opts.settleMs ?? STOP_SETTLE_MS;
  const registrar = (step: string, r: WapiCallResult<unknown>) => {
    out.steps.push({
      step,
      ok: r.success,
      code: r.error?.code,
      message: r.error?.message,
    });
    const espera = r.error?.retryAfterSeconds;
    if (espera && (!out.retryAfterSeconds || espera > out.retryAfterSeconds)) {
      out.retryAfterSeconds = espera;
    }
  };

  // ── stop (con tolerancia a "no había engine") ─────────────────────────
  if (plan.action === "stop-start" || plan.action === "force-kill-start") {
    const stop = await client.stopSession(sessionId);
    registrar("stop", stop);
    if (!stop.success && !stopSinEngine(stop.error)) {
      // 502 SESSION_STOP_INCOMPLETE es reintentable: OpenWA documenta que el
      // engine pudo no soltarse. Seguimos igualmente a /start; si el engine
      // sigue vivo, /start lo dirá.
      console.warn(
        `[session_recovery] ${sessionId}: /stop no confirmó (${stop.error?.code}): ` +
          `${stop.error?.message}`,
      );
    }
    if (settleMs > 0) await sleep(settleMs);
  }

  if (plan.action === "force-kill-start") {
    const kill = await client.forceKill(sessionId);
    registrar("force-kill", kill);
    // 400 = no había engine vivo que matar. Es el caso bueno.
    if (!kill.success && !stopSinEngine(kill.error)) {
      console.warn(
        `[session_recovery] ${sessionId}: /force-kill falló (${kill.error?.code}): ` +
          `${kill.error?.message}`,
      );
    }
    if (settleMs > 0) await sleep(settleMs);
  }

  // ── start ─────────────────────────────────────────────────────────────
  const start = await client.startSession(sessionId);
  registrar("start", start);
  if (start.success && start.data?.status) {
    out.finalRawStatus = key(start.data.status);
  }
  if (!start.success) {
    // /start sobre un engine ya arrancado responde 400 "already started": no es
    // un fallo, sólo queríamos el estado.
    const msg = (start.error?.message ?? "").toLowerCase();
    const yaArrancada = start.error?.code === "HTTP_400" &&
      (msg.includes("already") || msg.includes("running") ||
        msg.includes("started") || msg.includes("active"));
    if (!yaArrancada) {
      out.ok = false;
      return out;
    }
  }

  // ── verificación (leer el estado real, no fiarse del 2xx) ────────────
  const verificar = opts.verify !== false;
  if (verificar) {
    // `settleMs` también gobierna esta pausa: pasar 0 desactiva todas las
    // esperas (tests). Sin opción, 1.5s para dar tiempo al engine a reportar.
    await sleep(opts.settleMs ?? 1_500);
    const ses = await client.getSession(sessionId);
    registrar("getSession", ses);
    if (ses.success && ses.data?.status) {
      out.finalRawStatus = key(ses.data.status);
    }
  }

  out.ok = isReady(out.finalRawStatus) || out.finalRawStatus === "QR_READY" ||
    out.finalRawStatus === "INITIALIZING" || out.finalRawStatus === "CONNECTING" ||
    out.finalRawStatus === "AUTHENTICATING";
  if (!out.ok && out.finalRawStatus) {
    out.needsQr = out.needsQr ||
      ["QR_READY", "INITIALIZING", "CREATED", "CONNECTING"].includes(out.finalRawStatus);
  }
  return out;
}