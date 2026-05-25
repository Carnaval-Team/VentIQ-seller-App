// POST /functions/v1/wapi-webhook?tienda=<id>
//
// Recibe eventos push de la API WAPI (OpenWA):
//   - session.status / session.qr / session.authenticated / session.disconnected
//   - message.ack (cambios de estado del mensaje)
//
// La API WAPI firma el payload con HMAC-SHA256 si se configuró un secret.
// Si no hay secret, aceptamos el payload pero registramos warning.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { serviceClient } from "../_shared/auth.ts";
import { normalizeWapiStatus } from "../_shared/status.ts";

const WEBHOOK_SECRET = Deno.env.get("WAPI_WEBHOOK_SECRET") ?? "";

async function verifySignature(body: string, signature: string | null): Promise<boolean> {
  if (!WEBHOOK_SECRET) {
    console.warn("[wapi-webhook] WAPI_WEBHOOK_SECRET no configurado, se omite verificación");
    return true;
  }
  if (!signature) return false;
  const expected = "sha256=" + (await hmacSha256Hex(WEBHOOK_SECRET, body));
  // Constant-time compare
  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) {
    diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  }
  return diff === 0;
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  const raw = await req.text();
  const signature = req.headers.get("X-Signature") ?? req.headers.get("X-OpenWA-Signature");
  if (!(await verifySignature(raw, signature))) {
    return errorResponse("Firma inválida", 401);
  }

  let payload: any;
  try { payload = JSON.parse(raw); } catch {
    return errorResponse("JSON inválido", 400);
  }

  const event = payload.event ?? payload.type;
  const sessionId: string | undefined = payload.sessionId ?? payload.data?.sessionId;
  const data = payload.data ?? {};

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

  switch (event) {
    case "session.status":
    case "session.authenticated":
    case "session.disconnected": {
      const rawStatus =
        event === "session.authenticated"
          ? "CONNECTED"
          : event === "session.disconnected"
          ? "DISCONNECTED"
          : (data.status ?? null);
      const newStatus = rawStatus ? normalizeWapiStatus(rawStatus, "INITIALIZING") : null;
      const updates: Record<string, unknown> = {
        last_status_at: new Date().toISOString(),
      };
      if (newStatus) updates.status = newStatus;
      if (data.phoneNumber) updates.phone_number = data.phoneNumber;
      await admin.from("app_wapi_sesion").update(updates).eq("id", ses.id);
      break;
    }

    case "session.qr": {
      const updates: Record<string, unknown> = {
        status: "SCAN_QR",
        last_status_at: new Date().toISOString(),
      };
      if (data.image) updates.last_qr_image = data.image;
      await admin.from("app_wapi_sesion").update(updates).eq("id", ses.id);
      break;
    }

    case "message.ack": {
      // ack levels: 0=error, 1=pending, 2=sent, 3=delivered, 4=read, 5=played
      const ack = Number(data.ack ?? data.status ?? -1);
      const msgId: string | undefined = data.id ?? data.messageId;
      if (!msgId) break;

      if (ack === 0) {
        await admin.from("app_wapi_envio_log")
          .update({
            estado: "fallido",
            error_code: "ACK_ERROR",
            error_message: data.errorMessage ?? "Mensaje rechazado por WhatsApp",
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

    default:
      // Eventos no manejados: solo log
      console.log(`[wapi-webhook] Evento ${event} recibido sin handler`);
  }

  return okResponse({ received: true });
});
