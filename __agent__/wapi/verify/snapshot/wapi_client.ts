// Wrapper de la API WAPI externa (OpenWA).
// Todas las llamadas pasan por aquí para garantizar que la X-API-Key
// nunca sale del entorno seguro (Edge Functions).
//
// Configuración por env vars (supabase secrets set ...):
//   WAPI_BASE_URL  -> ej. http://3.238.37.3:2786
//   WAPI_API_KEY   -> clave API privada (opcional si la API no la exige)
//
// Nota sobre rutas (verificado contra la doc upstream de OpenWA, v0.25.0):
//   · El ciclo de vida de una sesión es
//       POST /api/sessions/:id/start | /stop | /logout | /force-kill
//       DELETE /api/sessions/:id
//     **No existe `/restart`** — el runbook oficial dice literalmente
//     "Try session restart (stop then start — there is no /restart route)".
//     Por eso `restart()` aquí está implementado como stop → start.
//   · Health: GET /api/health, /api/health/live, /api/health/ready,
//     /api/infra/health.
//   · Webhooks se registran en POST /api/sessions/:id/webhooks (no en el body
//     de POST /api/sessions) y aceptan `secret` + `retryCount`.

const BASE = (Deno.env.get("WAPI_BASE_URL") ?? "").replace(/\/$/, "");
const API_KEY = Deno.env.get("WAPI_API_KEY") ?? "";

if (!BASE) {
  console.warn(
    "[wapi_client] WAPI_BASE_URL no está configurado. Las llamadas externas fallarán.",
  );
}

export interface WapiResult<T> {
  success: boolean;
  data?: T;
  error?: {
    code: string;
    message: string;
    /**
     * Segundos que el server pide esperar antes de reintentar. Viene del
     * header `Retry-After` o del campo `retryAfterSeconds` que devuelve el
     * SEND_PACING de WAPI en sus 429. Quien llama debe respetarlo: insistir
     * antes sólo alarga el cooldown.
     */
    retryAfterSeconds?: number;
  };
}

/**
 * Timeouts por operación. CRÍTICO: sin esto, `fetch` espera indefinidamente.
 * Una request que abre conexión y nunca responde (sesión WAPI colgada,
 * Puppeteer atascado descargando una imagen) congelaba el worker hasta el
 * techo de wall-clock de Supabase (~400s) — se lo llevaba por delante junto
 * con toda la cadena de chunks pendientes. Ese era el "a veces se para el
 * envío": no fallaba, se quedaba esperando.
 */
const TIMEOUT_DEFAULT_MS = 20_000;
/**
 * Los envíos con media son más lentos: WAPI descarga la imagen y la sube.
 *
 * El valor anterior (45s) estaba JUSTO encima de la latencia real medida en
 * producción (27-45s por imagen en la sesión de la tienda 177). Resultado: el
 * cliente abortaba mientras el servidor seguía enviando, y el reintento con la
 * misma `Idempotency-Key` se encontraba la petición original todavía en vuelo
 * → tormenta de `IDEMPOTENCY_KEY_IN_PROGRESS` y filas marcadas `fallido` que
 * en realidad SÍ habían llegado al grupo. Con 90s el aborto deja de ser la
 * norma; si el servidor se atasca de verdad, el guarda-raíl por mensaje de
 * `wapi-send-products` (MENSAJE_MAX_MS) corta por presupuesto.
 *
 * Ajustable sin redesplegar la función: `WAPI_TIMEOUT_MEDIA_MS`.
 */
const TIMEOUT_MEDIA_MS = Number(
  Deno.env.get("WAPI_TIMEOUT_MEDIA_MS") ?? 90_000,
);
/** El health debe contestar rápido o el watchdog se queda colgado. */
const TIMEOUT_HEALTH_MS = 8_000;

interface CallOptions {
  timeoutMs?: number;
  /** Header `Idempotency-Key` (OpenWA 0.25.0+). Se ignora en builds viejas. */
  idempotencyKey?: string;
}

async function call<T>(
  method: "GET" | "POST" | "PUT" | "DELETE",
  path: string,
  body?: unknown,
  timeoutOrOpts: number | CallOptions = TIMEOUT_DEFAULT_MS,
): Promise<WapiResult<T>> {
  const opts: CallOptions = typeof timeoutOrOpts === "number"
    ? { timeoutMs: timeoutOrOpts }
    : timeoutOrOpts;
  const timeoutMs = opts.timeoutMs ?? TIMEOUT_DEFAULT_MS;

  const url = `${BASE}${path.startsWith("/") ? "" : "/"}${path}`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (API_KEY) headers["X-API-Key"] = API_KEY;
  if (opts.idempotencyKey) headers["Idempotency-Key"] = opts.idempotencyKey;

  // AbortController manual (en vez de AbortSignal.timeout) para poder limpiar
  // el temporizador: un timer huérfano mantiene vivo el isolate sin motivo.
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);

  try {
    const res = await fetch(url, {
      method,
      headers,
      body: body !== undefined ? JSON.stringify(body) : undefined,
      signal: ctrl.signal,
    });

    const text = await res.text();
    let parsed: any = null;
    try {
      parsed = text ? JSON.parse(text) : null;
    } catch {
      parsed = { raw: text };
    }

    if (!res.ok) {
      // Log para debugging upstream (visible en logs de supabase functions)
      console.error(
        `[wapi_client] ${method} ${url} → ${res.status}`,
        JSON.stringify({ requestBody: body, responseBody: parsed ?? text }),
      );

      // `retryAfterSeconds` sale del body (SEND_PACING) o del header estándar.
      const desdeBody = Number(parsed?.retryAfterSeconds ?? parsed?.error?.retryAfterSeconds);
      const desdeHeader = Number(res.headers.get("Retry-After") ?? "");
      const retryAfterSeconds = Number.isFinite(desdeBody) && desdeBody > 0
        ? desdeBody
        : Number.isFinite(desdeHeader) && desdeHeader > 0
        ? desdeHeader
        : undefined;

      return {
        success: false,
        error: {
          // El 429 del SEND_PACING trae `code` en la RAÍZ del body, no dentro
          // de `error` (que ahí es el string "Too Many Requests"). Miramos las
          // dos formas antes de caer al genérico HTTP_<status>.
          code: (typeof parsed?.error === "object" ? parsed?.error?.code : undefined) ??
            (typeof parsed?.code === "string" ? parsed.code : undefined) ??
            `HTTP_${res.status}`,
          message:
            (typeof parsed?.error === "object" ? parsed?.error?.message : undefined) ??
            parsed?.message ??
            (typeof text === "string" && text.length > 0 ? text : `HTTP ${res.status}`),
          ...(retryAfterSeconds ? { retryAfterSeconds } : {}),
        },
      };
    }

    // La API WAPI devuelve `{ success, data, ... }`. Lo normalizamos.
    if (parsed && typeof parsed === "object" && "success" in parsed) {
      return parsed as WapiResult<T>;
    }
    return { success: true, data: parsed as T };
  } catch (err) {
    const e = err as Error;
    // Un abort es nuestro propio timeout, no un fallo de red: lo distinguimos
    // para que quien llama pueda reintentarlo con criterio.
    const abortado = e?.name === "AbortError" || e?.name === "TimeoutError" ||
      ctrl.signal.aborted;
    if (abortado) {
      console.error(
        `[wapi_client] ${method} ${url} → TIMEOUT tras ${timeoutMs}ms`,
      );
    }
    return {
      success: false,
      error: abortado
        ? {
          code: "TIMEOUT",
          message: `WAPI no respondió en ${Math.round(timeoutMs / 1000)}s`,
        }
        : { code: "NETWORK_ERROR", message: e?.message ?? String(err) },
    };
  } finally {
    clearTimeout(timer);
  }
}

// =========================================================================
// Endpoints tipados
// =========================================================================

export interface WapiSessionDto {
  id: string;            // sess_xxx
  name: string;
  status: string;        // created|initializing|qr_ready|authenticating|ready|disconnected|action_required|failed
  phoneNumber?: string;
  engineLoaded?: boolean;
  createdAt?: string;
  qr?: string | null;    // a veces incluido en respuestas
}

export interface WapiQrDto {
  // La doc dice `code` (texto del QR) + `image` (data URL base64).
  // En la práctica el server devuelve `qrCode` con el data URL y a veces
  // `status` ("qr_ready"). Aceptamos todas las variantes.
  code?: string;
  image?: string;        // data:image/png;base64,...
  qrCode?: string;       // alias: data URL base64 (lo que devuelve OpenWA actual)
  qrText?: string;       // alias: texto del QR
  status?: string;
  expiresAt?: string;
}

export interface WapiGroupDto {
  id: string;            // xxx-yyy@g.us
  name: string;
  description?: string;
  participantsCount?: number;
}

export interface WapiSendResultDto {
  messageId?: string;
  status?: string;
  timestamp?: string;
}

export interface WapiBulkAcceptedDto {
  batchId: string;
  status: string;
  totalMessages: number;
}

export interface WapiHealthDto {
  status?: string;       // "ok"
  version?: string;      // sólo presente si se manda una key válida
  uptime?: number;
  [k: string]: unknown;
}

export interface WapiWebhookDto {
  id: string;
  url: string;
  events: string[];
  retryCount?: number;
  active?: boolean;
  createdAt?: string;
}

/** Configuración de reconexión por sesión (OpenWA). */
export interface WapiReconnectConfig {
  /** ms, 1000–300000. Default del server: 5000. */
  reconnectBaseDelay?: number;
  /** 0–20. 0 desactiva el auto-reconnect; sin poner: ilimitado (tope 5 min). */
  maxReconnectAttempts?: number;
}

/**
 * Eventos de webhook que nos interesan.
 *
 * IMPORTANTE: los eventos `session.*` son los que nos avisan de que la sesión
 * se está muriendo. La versión anterior de `wapi-session-create` sólo podía
 * declarar message.received/message.sent, así que la BD nunca se enteraba de
 * una caída (ver docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md).
 */
export const WAPI_WEBHOOK_EVENTS = [
  "session.status",
  "session.authenticated",
  "session.disconnected",
  "session.reconnect_loop",
  "session.restriction",
  "session.qr",
  "message.ack",
  "message.failed",
] as const;

/** Margen entre `/stop` y `/start`: el engine necesita soltar el socket. */
const STOP_SETTLE_MS = 2_500;

/**
 * Reinicio soportado: `/stop` → margen → `/start`.
 *
 * Se implementa como función suelta (no como método que use `this`) para que
 * seguir funcionando aunque alguien destructure `const { restart } = wapi`.
 * El `/stop` puede devolver 400 ("no hay engine vivo") o 502
 * SESSION_STOP_INCOMPLETE: ninguno de los dos impide intentar el `/start`.
 */
async function restartByStopStart(
  sessionId: string,
): Promise<WapiResult<WapiSessionDto>> {
  const stop = await call<{ ok?: boolean }>(
    "POST",
    `/api/sessions/${encodeURIComponent(sessionId)}/stop`,
  );
  if (!stop.success) {
    console.warn(
      `[wapi_client] /stop no confirmó (${stop.error?.code}): ${stop.error?.message} ` +
        `— se intenta /start de todas formas`,
    );
  }
  await new Promise((r) => setTimeout(r, STOP_SETTLE_MS));
  return await call<WapiSessionDto>(
    "POST",
    `/api/sessions/${encodeURIComponent(sessionId)}/start`,
  );
}

export const wapi = {
  // ── Sesiones ───────────────────────────────────────────────────────
  createSession(
    name: string,
    webhookUrl?: string,
    webhookEvents?: string[],
    config?: WapiReconnectConfig,
  ) {
    // La API valida estrictamente los eventos. Usamos sólo los que la
    // documentación marca como ejemplo explícito en POST /api/sessions
    // ("message.received","message.sent") para el webhook inline; el resto
    // (session.*) se registra aparte con registerWebhook().
    return call<WapiSessionDto>("POST", "/api/sessions", {
      name,
      ...(config ? { config } : {}),
      ...(webhookUrl
        ? {
            webhook: {
              url: webhookUrl,
              events: webhookEvents ?? ["message.received", "message.sent"],
            },
          }
        : {}),
    });
  },

  listSessions(limit?: number) {
    return call<WapiSessionDto[]>(
      "GET",
      `/api/sessions${limit ? `?limit=${encodeURIComponent(String(limit))}` : ""}`,
    );
  },

  getSession(sessionId: string) {
    return call<WapiSessionDto>("GET", `/api/sessions/${encodeURIComponent(sessionId)}`);
  },

  getQr(sessionId: string) {
    return call<WapiQrDto>("GET", `/api/sessions/${encodeURIComponent(sessionId)}/qr`);
  },

  // Arranca el engine de una sesión recién creada (status INITIALIZING → SCAN_QR).
  // OBLIGATORIO después de createSession; sin esto la sesión queda inerte.
  startSession(sessionId: string) {
    return call<WapiSessionDto>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/start`,
    );
  },

  /**
   * Detiene el engine sin desvincular la cuenta (a diferencia de `logout`).
   * Es la primera mitad del reinicio soportado. Puede responder
   * 502 SESSION_STOP_INCOMPLETE (reintentable) o 400 si no hay engine vivo.
   */
  stopSession(sessionId: string) {
    return call<{ ok?: boolean }>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/stop`,
    );
  },

  /**
   * Mata a la fuerza un engine colgado (segunda marcha de la escalada).
   * Devuelve 400 si no había engine vivo (que es el caso bueno) y
   * 502 SESSION_FORCE_KILL_INCOMPLETE si no pudo.
   */
  forceKill(sessionId: string) {
    return call<{ ok?: boolean }>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/force-kill`,
    );
  },

  logout(sessionId: string) {
    return call<{ ok: boolean }>("POST", `/api/sessions/${encodeURIComponent(sessionId)}/logout`);
  },

  /**
   * "Reiniciar" en OpenWA = **stop → start**. No existe `/restart`: la ruta
   * documentada es el par stop/start, y sobre una sesión ya arrancada `/start`
   * responde 400 "already started" (que el caller debe tolerar).
   *
   * Para la escalada completa (force-kill → start, cooldowns, verificación)
   * usa `_shared/session_recovery.ts`.
   */
  restart(sessionId: string): Promise<WapiResult<WapiSessionDto>> {
    return restartByStopStart(sessionId);
  },

  deleteSession(sessionId: string) {
    return call<{ ok: boolean }>("DELETE", `/api/sessions/${encodeURIComponent(sessionId)}`);
  },

  // ── Health / diagnóstico ───────────────────────────────────────────
  /** `GET /api/health` — la única que devuelve `version` (con key válida). */
  health() {
    return call<WapiHealthDto>("GET", "/api/health", undefined, TIMEOUT_HEALTH_MS);
  },
  /** `GET /api/health/live` — siempre ok, incluso durante el teardown. */
  healthLive() {
    return call<WapiHealthDto>("GET", "/api/health/live", undefined, TIMEOUT_HEALTH_MS);
  },
  /** `GET /api/health/ready` — 503 mientras drena o si una BD está caída. */
  healthReady() {
    return call<WapiHealthDto>("GET", "/api/health/ready", undefined, TIMEOUT_HEALTH_MS);
  },
  /** `GET /api/infra/health` — 503 cuando empieza el teardown. */
  healthInfra() {
    return call<WapiHealthDto>("GET", "/api/infra/health", undefined, TIMEOUT_HEALTH_MS);
  },

  // ── Webhooks ───────────────────────────────────────────────────────
  listWebhooks(sessionId: string) {
    return call<WapiWebhookDto[]>(
      "GET",
      `/api/sessions/${encodeURIComponent(sessionId)}/webhooks`,
    );
  },

  /**
   * Registra el webhook por la ruta documentada. `secret` es write-only: la API
   * nunca lo devuelve, así que para rotarlo hay que re-registrar (PUT) o borrar
   * y crear. `retryCount` documentado: 0–5, default 3.
   */
  registerWebhook(
    sessionId: string,
    body: { url: string; events: string[]; secret?: string; retryCount?: number },
  ) {
    return call<WapiWebhookDto>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/webhooks`,
      body,
    );
  },

  updateWebhook(
    sessionId: string,
    webhookId: string,
    body: { url?: string; events?: string[]; secret?: string; retryCount?: number },
  ) {
    return call<WapiWebhookDto>(
      "PUT",
      `/api/sessions/${encodeURIComponent(sessionId)}/webhooks/${encodeURIComponent(webhookId)}`,
      body,
    );
  },

  deleteWebhook(sessionId: string, webhookId: string) {
    return call<{ ok?: boolean }>(
      "DELETE",
      `/api/sessions/${encodeURIComponent(sessionId)}/webhooks/${encodeURIComponent(webhookId)}`,
    );
  },

  // ── Grupos ─────────────────────────────────────────────────────────
  listGroups(sessionId: string) {
    return call<WapiGroupDto[]>(
      "GET",
      `/api/sessions/${encodeURIComponent(sessionId)}/groups`,
    );
  },

  // ── Mensajes ───────────────────────────────────────────────────────
  /**
   * `idempotencyKey` (OpenWA 0.25.0+): si el envío se reintenta tras un
   * TIMEOUT, el server reconoce la clave y responde con el mismo mensaje en vez
   * de mandar dos veces. En builds anteriores el header se ignora sin daño.
   */
  sendText(
    sessionId: string,
    chatId: string,
    text: string,
    idempotencyKey?: string,
  ) {
    return call<WapiSendResultDto>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/messages/send-text`,
      { chatId, text },
      { idempotencyKey },
    );
  },

  /**
   * Envía una imagen. ATENCIÓN: la doc oficial muestra `{chatId, image:{url},
   * caption}` pero el server real espera el payload FLAT: `{chatId, url,
   * caption}`. Validado contra el endpoint en vivo (cualquier variante anidada
   * devuelve 400 Bad Request).
   */
  sendImage(
    sessionId: string,
    chatId: string,
    imageUrl: string,
    caption?: string,
    _mimetype?: string, // ignorado: el server actual no lo requiere
    idempotencyKey?: string,
  ) {
    const body: Record<string, unknown> = {
      chatId,
      url: imageUrl,
    };
    if (caption && caption.length > 0) body.caption = caption;
    return call<WapiSendResultDto>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/messages/send-image`,
      body,
      { timeoutMs: TIMEOUT_MEDIA_MS, idempotencyKey },
    );
  },

  /**
   * Envío en bulk con delays aleatorios entre mensajes (anti-ban).
   * La API WAPI procesa el batch en su lado, así que el teléfono del
   * usuario NO necesita estar encendido — la sesión vive en el servidor
   * WAPI que mantiene la conexión persistente con WhatsApp Web.
   *
   * OJO: máximo 100 mensajes por batch (OpenWA). No lo usa `dispatchProducts`
   * porque colapsa los chatId repetidos (N productos al mismo grupo son N
   * mensajes al mismo chatId).
   */
  sendBulk(
    sessionId: string,
    messages: Array<
      | { chatId: string; type: "text"; content: { text: string } }
      | {
          chatId: string;
          type: "image";
          content: {
            image: { url: string; mimetype?: string };
            caption?: string;
          };
        }
    >,
    options?: {
      batchId?: string;
      delayBetweenMessages?: number;  // ms — usaremos delays grandes
      randomizeDelay?: boolean;
      stopOnError?: boolean;
    },
  ) {
    if (messages.length > 100) {
      console.warn(
        `[wapi_client] sendBulk con ${messages.length} mensajes: OpenWA acepta ` +
          `como máximo 100 por batch — hay que trocear.`,
      );
    }
    return call<WapiBulkAcceptedDto>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/messages/send-bulk`,
      {
        ...(options?.batchId ? { batchId: options.batchId } : {}),
        messages,
        options: {
          delayBetweenMessages: options?.delayBetweenMessages ?? 45000,
          randomizeDelay: options?.randomizeDelay ?? true,
          stopOnError: options?.stopOnError ?? false,
        },
      },
      TIMEOUT_MEDIA_MS,
    );
  },
};