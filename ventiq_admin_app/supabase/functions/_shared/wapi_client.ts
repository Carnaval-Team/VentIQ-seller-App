// Wrapper de la API WAPI externa (OpenWA).
// Todas las llamadas pasan por aquí para garantizar que la X-API-Key
// nunca sale del entorno seguro (Edge Functions).
//
// Configuración por env vars (supabase secrets set ...):
//   WAPI_BASE_URL  -> ej. http://3.238.37.3:2786
//   WAPI_API_KEY   -> clave API privada (opcional si la API no la exige)

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
/** Los envíos con media son más lentos: WAPI descarga la imagen y la sube. */
const TIMEOUT_MEDIA_MS = 45_000;

async function call<T>(
  method: "GET" | "POST" | "DELETE",
  path: string,
  body?: unknown,
  timeoutMs: number = TIMEOUT_DEFAULT_MS,
): Promise<WapiResult<T>> {
  const url = `${BASE}${path.startsWith("/") ? "" : "/"}${path}`;
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (API_KEY) headers["X-API-Key"] = API_KEY;

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
  status: string;        // INITIALIZING | SCAN_QR | CONNECTING | CONNECTED | DISCONNECTED | FAILED
  phoneNumber?: string;
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

export const wapi = {
  // ── Sesiones ───────────────────────────────────────────────────────
  createSession(name: string, webhookUrl?: string, webhookEvents?: string[]) {
    // La API valida estrictamente los eventos. Usamos sólo los que la
    // documentación marca como ejemplo explícito en POST /api/sessions
    // ("message.received","message.sent"). Eventos adicionales pueden
    // registrarse después vía POST /api/sessions/:id/webhooks.
    return call<WapiSessionDto>("POST", "/api/sessions", {
      name,
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

  listSessions() {
    return call<WapiSessionDto[]>("GET", "/api/sessions");
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

  logout(sessionId: string) {
    return call<{ ok: boolean }>("POST", `/api/sessions/${encodeURIComponent(sessionId)}/logout`);
  },

  restart(sessionId: string) {
    return call<{ ok: boolean }>("POST", `/api/sessions/${encodeURIComponent(sessionId)}/restart`);
  },

  deleteSession(sessionId: string) {
    return call<{ ok: boolean }>("DELETE", `/api/sessions/${encodeURIComponent(sessionId)}`);
  },

  // ── Grupos ─────────────────────────────────────────────────────────
  listGroups(sessionId: string) {
    return call<WapiGroupDto[]>(
      "GET",
      `/api/sessions/${encodeURIComponent(sessionId)}/groups`,
    );
  },

  // ── Mensajes ───────────────────────────────────────────────────────
  sendText(sessionId: string, chatId: string, text: string) {
    return call<WapiSendResultDto>(
      "POST",
      `/api/sessions/${encodeURIComponent(sessionId)}/messages/send-text`,
      { chatId, text },
    );
  },

  /**
   * Envía una imagen. ATENCIÓN: la doc oficial (docs_wapi/06-api-specification.md)
   * muestra `{chatId, image:{url}, caption}` pero el server real espera el
   * payload FLAT: `{chatId, url, caption}`. Validado contra el endpoint en vivo
   * (cualquier variante anidada devuelve 400 Bad Request).
   */
  sendImage(
    sessionId: string,
    chatId: string,
    imageUrl: string,
    caption?: string,
    _mimetype?: string, // ignorado: el server actual no lo requiere
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
      TIMEOUT_MEDIA_MS,
    );
  },

  /**
   * Envío en bulk con delays aleatorios entre mensajes (anti-ban).
   * La API WAPI procesa el batch en su lado, así que el teléfono del
   * usuario NO necesita estar encendido — la sesión vive en el servidor
   * WAPI que mantiene la conexión persistente con WhatsApp Web.
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
