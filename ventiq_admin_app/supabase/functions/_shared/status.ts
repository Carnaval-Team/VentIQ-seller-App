// Mapeo de estados internos del engine WAPI a los estados canónicos de la API.
//
// Según docs_wapi/06-api-specification.md (líneas 413-433):
//
//   API Status   | Description
//   -------------|-------------
//   INITIALIZING | Session created, engine booting
//   SCAN_QR      | QR code ready / waiting for scan
//   CONNECTING   | QR scanned, connecting to WhatsApp
//   CONNECTED    | Connected and ready
//   DISCONNECTED | Connection lost or logged out
//   FAILED       | Fatal error
//
//   Internal Status (engine/db) | API Status
//   ---------------------------|------------
//   initializing               | INITIALIZING
//   qr_ready                   | SCAN_QR
//   connecting                 | CONNECTING
//   ready                      | CONNECTED
//   disconnected               | DISCONNECTED
//   error                      | FAILED
//
// Diferentes builds del server WAPI pueden devolver cualquiera de las dos
// formas (internal o API), o variaciones como `QR_REQUIRED`, `AUTHENTICATED`,
// `STARTING`, etc. Esta función las colapsa a las 6 canónicas que aceptamos
// en `app_wapi_sesion.status` (CHECK constraint).

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
  NEW: "INITIALIZING",

  QR: "SCAN_QR",
  QR_CODE: "SCAN_QR",
  QR_REQUIRED: "SCAN_QR",
  WAITING_FOR_QR: "SCAN_QR",
  SCAN: "SCAN_QR",

  AUTHENTICATING: "CONNECTING",
  AUTHENTICATED: "CONNECTING", // pre-CONNECTED
  PAIRING: "CONNECTING",

  ONLINE: "CONNECTED",
  OPEN: "CONNECTED",
  ACTIVE: "CONNECTED",

  OFFLINE: "DISCONNECTED",
  LOGGED_OUT: "DISCONNECTED",
  CLOSED: "DISCONNECTED",
  TIMEOUT: "DISCONNECTED",
  STOPPED: "DISCONNECTED",

  FAIL: "FAILED",
  CRASHED: "FAILED",
  FATAL: "FAILED",
};

export function normalizeWapiStatus(
  raw: unknown,
  fallback: WapiCanonStatus = "INITIALIZING",
): WapiCanonStatus {
  if (raw == null) return fallback;
  const key = String(raw).trim().toUpperCase().replace(/[\s-]+/g, "_");
  return MAP[key] ?? fallback;
}
