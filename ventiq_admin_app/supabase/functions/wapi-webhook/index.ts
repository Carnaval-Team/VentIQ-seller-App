// POST /functions/v1/wapi-webhook?tienda=<id>
//
// Recibe eventos push de la API WAPI (OpenWA):
//   session.status · session.authenticated · session.disconnected
//   session.reconnect_loop · session.restriction · session.qr
//   message.ack · message.failed
//
// CAMBIOS CLAVE (ver docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md)
//   1. Se maneja `session.reconnect_loop`, que es LA señal oficial de que la
//      sesión está muriendo (OpenWA lo emite "on every 5th consecutive
//      attempt"). Antes caía en el `default` y sólo se logueaba: la sesión se
//      moría sin que nada lo supiera. También `session.restriction` y
//      `message.failed`.
//   2. En `session.qr` se acepta `qrCode` (lo que devuelve OpenWA) además de
//      `image` (lo que dice la doc vieja).
//   3. Se persiste el status CRUDO, que es lo único que permite diagnosticar
//      después un `action_required` o un `failed`.
//   4. Firma: si `WAPI_WEBHOOK_SECRET` está configurado y NO llega firma, se
//      responde 401 con un mensaje que dice exactamente qué hacer
//      (`wapi-session-action action=register-webhook`). Antes se rechazaba en
//      silencio y el operador no tenía forma de saber que el webhook estaba
//      mal registrado. Escape hatch explícito:
//      `WAPI_WEBHOOK_ALLOW_UNSIGNED=true`.
//
// PENDIENTE CONOCIDO (documentado, no implementado): deduplicar por
// `X-OpenWA-Idempotency-Key`. OpenWA avisa que los workers de su cola
// re-ejecutan jobs al reiniciar y que los barridos del outbox pueden
// reentregar el mismo evento con la misma clave. Los handlers de aquí son
// idempotentes (escriben estado absoluto, no incrementan nada), así que la
// reentrega no corrompe datos; los headers se registran para poder rastrearla.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/auth.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";
import { updateSessionState } from "../_shared/session_store.ts";

const WEBHOOK_SECRET = Deno.env.get("WAPI_WEBHOOK_SECRET") ?? "";
const ALLOW_UNSIGNED = Deno.env.get("WAPI_WEBHOOK_ALLOW_UNSIGNED") === "true";

async function verifySignature(body: string, signature: string | null): Promise<"ok" | "missing" | "invalid"> {
  // Sin secret configurado no hay nada que verificar: se acepta (mismo
  // comportamiento de antes) pero se avisa.
  if (!WEBHOOK_SECRET) return "ok";
  if (!signature) return "missing";
  const expected = "sha256=" + (await hmacSha256Hex(WEBHOOK_SECRET, body));
  // Constant-time compare
  if (expected.length !== signature.length) return "invalid";
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return diff === 0 ? "ok" : "invalid";
}

async function hmacSha256Hex(secret: string, msg: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    enc.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, enc.encode(msg));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Extrae un status crudo útil de la carga del evento. */
function rawStatusDeEvento(evento: string, data: Record<string, unknown>): string | null {
  switch (evento) {
    case "session.authenticated":
      return "ready";
    case "session.disconnected":
      // `reason` documentado: LOGOUT, NAVIGATION, ... Se conserva para poder
      // distinguir "se desvinculó" de "se cayó la red".
      return typeof data.reason === "string" ? `disconnected:${data.reason}` : "disconnected";
    case "session.status":
      return (data.status as string) ?? null;
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const raw = await req.text();

  // La firma de OpenWA viaja en `X-OpenWA-Signature`. Se mantiene
  // `X-Signature` por compatibilidad con integraciones propias.
  const signature = req.headers.get("X-OpenWA-Signature") ??
    req.headers.get("X-Signature");
  const firma = await verifySignature(raw, signature);

  if (firma === "invalid") {
    console.error("[wapi-webhook] firma INVÁLIDA: el secret del webhook en OpenWA no coincide con WAPI_WEBHOOK_SECRET");
    return errorResponse("Firma inválida", 401);
  }
  if (firma === "missing") {
    if (!ALLOW_UNSIGNED) {
      console.error(
        "[wapi-webhook] llegó un evento SIN firma y WAPI_WEBHOOK_SECRET está " +
          "configurado. Eso significa que el webhook se registró sin secret " +
          "(se hizo así hasta ahora). Arréglalo con: " +
          "wapi-session-action { id_sesion, action: 'register-webhook' } " +
          "o, para aceptar eventos sin firma durante el diagnóstico, pon " +
          "WAPI_WEBHOOK_ALLOW_UNSIGNED=true.",
      );
      return errorResponse(
        "Webhook sin firma. Re-regístralo con wapi-session-action action=register-webhook.",
        401,
        "UNSIGNED_WEBHOOK",
      );
    }
    console.warn(
      "[wapi-webhook] evento SIN firma aceptado por WAPI_WEBHOOK_ALLOW_UNSIGNED=true",
    );
  } else if (!WEBHOOK_SECRET) {
    console.warn(
      "[wapi-webhook] WAPI_WEBHOOK_SECRET no configurado, se omite verificación",
    );
  }

  let payload: any;
  try { payload = JSON.parse(raw); } catch {
    return errorResponse("JSON inválido", 400);
  }

  const event = payload.event ?? payload.type ?? req.headers.get("X-OpenWA-Event");
  const sessionId: string | undefined = payload.sessionId ?? payload.data?.sessionId;
  const data = (payload.data ?? {}) as Record<string, unknown>;
  const idempotencyKey = payload.idempotencyKey ??
    req.headers.get("X-OpenWA-Idempotency-Key");
  const deliveryId = payload.deliveryId ?? req.headers.get("X-OpenWA-Delivery-Id");

  if (!sessionId) {
    return okResponse({ received: true, note: "sin sessionId, ignorado" });
  }

  const admin = serviceClient();
  const { data: ses } = await admin
    .from("app_wapi_sesion")
    .select("id, id_tienda")
    .eq("wapi_session_id", sessionId)
    .maybeSingle();

  if (!ses) {
    // Sesión desconocida — registramos pero no falla
    console.warn(`[wapi-webhook] Evento ${event} para sesión desconocida ${sessionId}`);
    return okResponse({ received: true, note: "session_not_tracked" });
  }

  // Rastro de la entrega: OpenWA documenta que los workers de su cola y los
  // barridos del outbox pueden reentregar el MISMO evento (misma
  // `X-OpenWA-Idempotency-Key`). Los handlers de aquí escriben estado absoluto,
  // así que la reentrega no corrompe datos; dejamos las claves en el log para
  // poder rastrear una reentrega puntual.
  if (deliveryId || idempotencyKey) {
    console.log(
      `[wapi-webhook] evento=${event} sesion=${sessionId} ` +
        `delivery=${deliveryId ?? "?"} idempotency=${idempotencyKey ?? "?"}`,
    );
  }

  switch (event) {
    // ── Ciclo de vida de la sesión ─────────────────────────────────────
    case "session.status":
    case "session.authenticated":
    case "session.disconnected": {
      const rawStatus = rawStatusDeEvento(event, data);
      const newStatus = rawStatus
        ? normalizeWapiStatus(rawStatus, "INITIALIZING")
        : null;
      const updates: Parameters<typeof updateSessionState>[2] = {};
      if (newStatus) updates.status = newStatus;
      updates.rawStatus = rawStatus;
      if (typeof data.phoneNumber === "string") updates.phoneNumber = data.phoneNumber;
      if (event === "session.authenticated") updates.errorCode = null;
      if (event === "session.disconnected") {
        updates.errorCode = "SESSION_DISCONNECTED";
        updates.errorMessage = typeof data.reason === "string"
          ? `reason=${data.reason}`
          : "sin reason";
      }
      const res = await updateSessionState(admin, ses.id, updates);
      if (!res.ok) {
        console.error(`[wapi-webhook] no se pudo guardar el estado: ${res.error}`);
      }
      if (event === "session.disconnected") {
        console.warn(
          `[wapi-webhook] sesión ${ses.id} DESCONECTADA ` +
            `(reason=${data.reason ?? "?"}): hace falta reiniciarla. ` +
            `El watchdog (wapi-session-health) debería recuperarla en el próximo ciclo.`,
        );
      }
      break;
    }

    // ── La sesión está en bucle de reconexión: se está muriendo ────────
    case "session.reconnect_loop": {
      const intentos = Number(data.attempts ?? 0);
      const esperaMs = Number(data.nextDelayMs ?? 0);
      console.error(
        `[wapi-webhook] sesión ${ses.id} en BUCLE DE RECONEXIÓN: ` +
          `intentos=${intentos} próximo delay=${esperaMs}ms. ` +
          `OpenWA sólo emite este evento cada 5º intento fallido: la sesión ` +
          `no va a recuperarse sola.`,
      );
      await updateSessionState(admin, ses.id, {
        rawStatus: "reconnect_loop",
        errorCode: "RECONNECT_LOOP",
        errorMessage: `intentos=${intentos} nextDelayMs=${esperaMs}`,
      });
      break;
    }

    // ── Restricción de WhatsApp sobre la sesión ───────────────────────
    case "session.restriction": {
      const activa = data.active === true;
      const kind = String(data.kind ?? "desconocida");
      const code = String(data.code ?? "");
      const expiresAt = data.expiresAt ?? null;
      console.error(
        `[wapi-webhook] sesión ${ses.id} RESTRINGIDA: active=${activa} ` +
          `kind=${kind} code=${code} expiresAt=${expiresAt}`,
      );
      await updateSessionState(admin, ses.id, {
        ...(activa ? { status: "DISCONNECTED" } : {}),
        rawStatus: activa ? "restricted" : "restriction_lifted",
        errorCode: activa ? `RESTRICTION_${kind.toUpperCase()}` : null,
        errorMessage: `active=${activa} kind=${kind} code=${code} expiresAt=${expiresAt}`,
      });
      break;
    }

    // ── QR ─────────────────────────────────────────────────────────────
    case "session.qr": {
      // OpenWA devuelve `qrCode` (data URL PNG). La doc vieja dice `image`.
      const imagen = (data.qrCode ?? data.image ?? data.qr) as string | undefined;
      const res = await updateSessionState(admin, ses.id, {
        status: "SCAN_QR",
        rawStatus: "qr_ready",
        ...(imagen ? { lastQrImage: imagen } : {}),
      });
      if (!res.ok) {
        console.error(`[wapi-webhook] no se pudo guardar el QR: ${res.error}`);
      }
      break;
    }

    // ── Acks de mensajes ───────────────────────────────────────────────
    case "message.ack": {
      // ack levels: 0=error, 1=pending, 2=sent, 3=delivered, 4=read, 5=played
      const ack = Number(data.ack ?? data.status ?? -1);
      const msgId: string | undefined = (data.id ?? data.messageId) as string | undefined;
      if (!msgId) break;

      if (ack === 0) {
        await admin.from("app_wapi_envio_log")
          .update({
            estado: "fallido",
            error_code: "ACK_ERROR",
            error_message: (data.errorMessage as string) ??
              "Mensaje rechazado por WhatsApp",
          })
          .eq("mensaje_id", msgId);
      } else if (ack >= 2) {
        await admin.from("app_wapi_envio_log")
          .update({
            estado: "enviado",
            mensaje_id: msgId,
            sent_at: new Date().toISOString(),
          })
          .eq("mensaje_id", msgId);
      }
      break;
    }

    // ── Fallo explícito de un mensaje ─────────────────────────────────
    case "message.failed": {
      const msgId: string | undefined = (data.id ?? data.messageId) as string | undefined;
      if (!msgId) break;
      await admin.from("app_wapi_envio_log")
        .update({
          estado: "fallido",
          error_code: "MESSAGE_FAILED",
          error_message: (data.errorMessage as string) ??
            (data.reason as string) ?? "OpenWA reportó message.failed",
        })
        .eq("mensaje_id", msgId);
      break;
    }

    default:
      // Eventos no manejados: solo log
      console.log(`[wapi-webhook] Evento ${event} recibido sin handler`);
  }

  return okResponse({ received: true });
});