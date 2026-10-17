// Mapeo de estados internos del engine WAPI a los estados canónicos de la API.
//
// Según la doc oficial de OpenWA (docs/06-api-specification.md §6.2) los
// estados que viajan por el cable son:
//
//   created | initializing | qr_ready | authenticating | ready |
//   disconnected | action_required | failed
//
// (Nota: la copia local en docs_wapi/ es de la era v0.11.1 y NO incluye
//  `action_required`; ver docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md.)
//
// La tabla `app_wapi_sesion.status` sólo admite 6 valores (CHECK constraint):
//
//   INITIALIZING | SCAN_QR | CONNECTING | CONNECTED | DISCONNECTED | FAILED
//
// `action_required` NO se puede guardar tal cual. Además es un estado que
// requiere intervención humana (el modal "What's new" de WhatsApp), así que lo
// colapsamos a DISCONNECTED: es la verdad útil para la UI (rojo, "Desconectado",
// con botón de reiniciar) en vez de INITIALIZING (ámbar, "Inicializando"), que
// era el comportamiento anterior y hacía que una sesión atascada pareciera
// estar arrancando para siempre.
//
// Diferentes builds del server pueden devolver cualquiera de las dos formas
// (internal o API), o variaciones. Esta función las colapsa a las 6 canónicas.

export type WapiCanonStatus =
  | "INITIALIZING"
  | "SCAN_QR"
  | "CONNECTING"
  | "CONNECTED"
  | "DISCONNECTED"
  | "FAILED";

// La key se normaliza a UPPERCASE + reemplazo de espacios/dashes por `_`
// antes de la búsqueda. P.ej. "qr_ready", "Qr-Ready", "QR ready" → "QR_READY".
const MAP: Record<string, WapiCanonStatus> = {
  // Canónicos (passthrough)
  INITIALIZING: "INITIALIZING",
  SCAN_QR: "SCAN_QR",
  CONNECTING: "CONNECTING",
  CONNECTED: "CONNECTED",
  DISCONNECTED: "DISCONNECTED",
  FAILED: "FAILED",

  // Internal status (docs)
  QR_READY: "SCAN_QR",
  READY: "CONNECTED",
  ERROR: "FAILED",

  // Variantes/alias observados
  PENDING: "INITIALIZING",
  STARTING: "INITIALIZING",
  BOOTING: "INITIALIZING",
  CREATED: "INITIALIZING",
  LOADING: "INITIALIZING",
  ENGINE_LOADING: "INITIALIZING",
  NEW: "INITIALIZING",
  RESTORING: "INITIALIZING",

  QR: "SCAN_QR",
  QR_CODE: "SCAN_QR",
  QR_REQUIRED: "SCAN_QR",
  WAITING_FOR_QR: "SCAN_QR",
  SCAN: "SCAN_QR",

  AUTHENTICATING: "CONNECTING",
  AUTHENTICATED: "CONNECTING", // pre-CONNECTED
  PAIRING: "CONNECTING",
  PAIRING_CODE: "CONNECTING",
  RECONNECTING: "CONNECTING",
  REINJECTING: "CONNECTING", // 409 "WhatsApp Web is reloading its page..."

  ONLINE: "CONNECTED",
  OPEN: "CONNECTED",
  ACTIVE: "CONNECTED",

  OFFLINE: "DISCONNECTED",
  LOGGED_OUT: "DISCONNECTED",
  CLOSED: "DISCONNECTED",
  TIMEOUT: "DISCONNECTED",
  STOPPED: "DISCONNECTED",
  DELETED: "DISCONNECTED",
  // Estados que exigen intervención humana o que anuncian que la sesión ya no
  // sirve. Todos van a DISCONNECTED (ver cabecera).
  ACTION_REQUIRED: "DISCONNECTED",
  ATTENTION_REQUIRED: "DISCONNECTED",
  RESTRICTED: "DISCONNECTED",
  RESTRICTION: "DISCONNECTED",
  SUSPENDED: "DISCONNECTED",
  BANNED: "DISCONNECTED",
  UNLINKED: "DISCONNECTED",

  FAIL: "FAILED",
  CRASHED: "FAILED",
  FATAL: "FAILED",
  TERMINATED: "FAILED",
};

/** Clave normalizada de un status crudo ("Qr-Ready" → "QR_READY"). */
export function rawStatusKey(raw: unknown): string {
  if (raw == null) return "";
  return String(raw).trim().toUpperCase().replace(/[\s.-]+/g, "_");
}

// Avisos de status desconocido: uno por status por isolate. Si OpenWA añade un
// estado nuevo (como pasó con `action_required`), queremos verlo en los logs en
// vez de que se convierta en silencio en el `fallback`.
const avisados = new Set<string>();

export function normalizeWapiStatus(
  raw: unknown,
  fallback: WapiCanonStatus = "INITIALIZING",
): WapiCanonStatus {
  const key = rawStatusKey(raw);
  if (!key) return fallback;
  const canon = MAP[key];
  if (canon) return canon;

  if (!avisados.has(key)) {
    avisados.add(key);
    console.warn(
      `[status] status de WAPI desconocido: "${raw}" → se asume ${fallback}. ` +
        `Añádelo al MAP de _shared/status.ts si es un estado real.`,
    );
  }
  return fallback;
}

/**
 * ¿La sesión está caída y hay que recuperarla? Se evalúa sobre el status CRUDO
 * (lo que responde OpenWA), porque el normalizado puede haber perdido matices.
 *
 * `action_required` entra aquí a propósito: necesita acción humana, y tratarlo
 * como "vivo" es justo lo que dejaba el bot muerto sin que nadie se enterara.
 */
export function isSessionDown(raw: unknown): boolean {
  const key = rawStatusKey(raw);
  if (!key) return false;
  switch (key) {
    case "DISCONNECTED":
    case "FAILED":
    case "FAIL":
    case "CRASHED":
    case "FATAL":
    case "ERROR":
    case "OFFLINE":
    case "LOGGED_OUT":
    case "CLOSED":
    case "STOPPED":
    case "TIMEOUT":
    case "ACTION_REQUIRED":
    case "ATTENTION_REQUIRED":
    case "RESTRICTED":
    case "RESTRICTION":
    case "SUSPENDED":
    case "BANNED":
    case "UNLINKED":
    case "TERMINATED":
      return true;
    default:
      return false;
  }
}

/**
 * ¿La sesión está viva y puede enviar? Sólo `ready`/`connected`. Cualquier
 * estado intermedio (qr_ready, authenticating, action_required, ...) NO sirve
 * para enviar, aunque no sea un "fallo".
 */
export function isSessionSendable(raw: unknown): boolean {
  const key = rawStatusKey(raw);
  return key === "READY" || key === "CONNECTED" || key === "ONLINE" ||
    key === "OPEN" || key === "ACTIVE";
}

/**
 * `failed` es TERMINAL en OpenWA: ni el reset de arranque ni el barrido de
 * takeover reanudan una sesión FAILED. La recuperación tiene que ser explícita
 * (stop → start, o delete + recrear). Sirve para no insistir en bucle.
 */
export function isSessionTerminal(raw: unknown): boolean {
  const key = rawStatusKey(raw);
  return key === "FAILED" || key === "FAIL" || key === "FATAL" ||
    key === "CRASHED" || key === "TERMINATED";
}