// POST /functions/v1/wapi-send-text
//
// Envía un mensaje de TEXTO por WhatsApp usando el gateway OpenWA que ya
// tenemos corriendo (el mismo que usa ventiq_admin_app para avisar a los
// grupos). Es genérica: cualquier app/proceso del ecosistema puede pedirle un
// envío a un número concreto.
//
// ── BODY ───────────────────────────────────────────────────────────────────
//   {
//     "to": "+5354590207",          // o "5354590207" o "5354590207@c.us"
//     "text": "Hola, tu código es 1234",
//     "session_id": "<uuid>",       // opcional: sesión WAPI concreta
//     "id_tienda": 177,             // opcional: resolver la sesión de esa tienda
//     "idempotency_key": "wa-otp-42",// opcional (recomendado en reintentos)
//     "dry_run": false              // true = no envía, sólo devuelve el chatId
//   }
//
// ── FORMATO DEL NÚMERO (lo que preguntabas) ────────────────────────────────
// OpenWA usa «chatId» con la forma `<numero>@c.us`, donde `<numero>` va en
// DÍGITOS con código de país, SIN «+», SIN espacios y SIN guiones:
//     Cuba +53 54590207  →  chatId: "5354590207@c.us"
// Esta función normaliza por ti: acepta «+53 545 90 207», «5354590207» o
// «5354590207@c.us» y siempre manda «5354590207@c.us».
// (Referencia: docs_wapi/03-system-architecture.md y 07-api-collection.md.)
//
// ── RESPUESTA ──────────────────────────────────────────────────────────────
// 200 { ok:true, session_id, chat_id, numero, idempotency_key, resultado }
// 4xx { ok:false, error:{code,message}, chat_id, numero } ← útil para depurar
//     un número que no tiene WhatsApp, sesión caída o API key inválida.
//
// ── AUTENTICACIÓN ──────────────────────────────────────────────────────────
// Se despliega con verify_jwt = TRUE (el gateway valida la firma). Dentro:
//   · llamada con service_role (Edge Function, trigger con pg_net, cron) → OK
//   · usuario autenticado → OK (el proyecto decide si restringe más)
// Esto la hace reutilizable desde muevete (OTP del contacto de emergencia),
// ventiq_app (avisos) o cualquier proceso con la service_role.
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import { getAuthContext, isServiceRoleCall } from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";

/** Presupuesto de reloj: el envío de texto es rápido (los media son otra cosa). */
const ENVIO_TIMEOUT_MS = 25_000;

/** Convierte cualquier forma del número al chatId de OpenWA (`<digitos>@c.us`). */
function aChatId(to: string): { chatId: string; numero: string } | null {
  let s = (to ?? "").trim();
  if (!s) return null;

  // Quitar sufijo de WhatsApp si ya viene puesto
  s = s.replace(/@(c\.us|s\.whatsapp\.net)$/i, "");
  // Quitar todo lo que no sea dígito (espacios, +, -, paréntesis, puntos)
  const digits = s.replace(/[^\d]/g, "");

  // E.164 razonable para Cuba y resto: 8..15 dígitos
  if (digits.length < 8 || digits.length > 15) return null;

  return { chatId: `${digits}@c.us`, numero: digits };
}

/**
 * OpenWA exige que `Idempotency-Key` sea 1..255 caracteres ASCII *visibles*.
 * Un acento (p. ej. "muévete-42") devuelve 400 IDEMPOTENCY_KEY_INVALID, así que
 * se filtra aquí en vez de romper el envío por un detalle del caller.
 */
function aIdempotencyKey(raw: unknown): string | undefined {
  if (raw === undefined || raw === null) return undefined;
  const limpio = String(raw).replace(/[^\x20-\x7E]/g, "").trim().slice(0, 255);
  return limpio.length > 0 ? limpio : undefined;
}

Deno.serve(async (req: Request) => {
  const pre = handleOptions(req);
  if (pre) return pre;

  if (req.method !== "POST") {
    return errorResponse(405, "metodo_no_permitido", "Usa POST");
  }

  // ── Autenticación ────────────────────────────────────────────────────────
  const esServicio = isServiceRoleCall(req);
  if (!esServicio) {
    const ctx = await getAuthContext(req);
    if (!ctx) {
      return errorResponse(401, "no_autenticado", "Falta un JWT válido");
    }
  }

  // ── Body ─────────────────────────────────────────────────────────────────
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return errorResponse(400, "body_invalido", "El body debe ser JSON");
  }

  const to = String(body.to ?? "");
  const texto = String(body.text ?? "").trim();
  const dryRun = body.dry_run === true;

  if (!texto) {
    return errorResponse(400, "texto_vacio", "Falta el texto del mensaje");
  }
  if (texto.length > 4000) {
    return errorResponse(400, "texto_largo", "Máximo 4000 caracteres");
  }

  const normalizado = aChatId(to);
  if (!normalizado) {
    return errorResponse(
      400,
      "numero_invalido",
      "Número inválido. Usa dígitos con código de país, ej. +5354590207",
    );
  }

  // ── Resolver la sesión WAPI ──────────────────────────────────────────────
  let sessionId = String(body.session_id ?? "").trim();

  if (!sessionId) {
    const ctx = await getAuthContext(req);
    const sb = ctx?.sb ?? (await import("../_shared/auth.ts")).serviceClient();
    let q = sb
      .from("app_wapi_sesion")
      .select("id, wapi_session_id, status, nombre")
      .eq("status", "CONNECTED")
      .limit(2);

    if (body.id_tienda !== undefined && body.id_tienda !== null) {
      q = q.eq("id_tienda", Number(body.id_tienda));
    }

    const { data, error } = await q;
    if (error) {
      return errorResponse(500, "consulta_sesion_fallo", error.message);
    }
    if (!data || data.length === 0) {
      return errorResponse(
        409,
        "sin_sesion_conectada",
        "No hay ninguna sesión de WhatsApp conectada",
      );
    }
    if (data.length > 1 && body.id_tienda === undefined) {
      return errorResponse(
        409,
        "varias_sesiones",
        "Hay varias sesiones conectadas: indica session_id o id_tienda",
      );
    }
    sessionId = String(data[0].wapi_session_id);
  }

  // ── Dry run: sirve para CONFIRMAR el formato sin enviar nada ────────────
  if (dryRun) {
    return okResponse({
      ok: true,
      dry_run: true,
      session_id: sessionId,
      chat_id: normalizado.chatId,
      numero: normalizado.numero,
      largo_texto: texto.length,
      mensaje: "No se envió nada (dry_run). El chatId es el que se usaría.",
    });
  }

  // ── Envío ────────────────────────────────────────────────────────────────
  const idem = aIdempotencyKey(body.idempotency_key);

  const r = await wapi.sendText(
    sessionId,
    normalizado.chatId,
    texto,
    idem,
  );

  if (!r.success) {
    // Nunca logueamos el texto (puede llevar un OTP); sí el número enmascarado.
    console.error(
      `[wapi-send-text] fallo session=${sessionId} numero=***${normalizado.numero.slice(-4)} ` +
        `code=${r.error?.code ?? "?"} msg=${r.error?.message ?? "?"}`,
    );
    return errorResponse(
      502,
      r.error?.code ?? "wapi_error",
      r.error?.message ?? "El gateway de WhatsApp rechazó el envío",
      {
        session_id: sessionId,
        chat_id: normalizado.chatId,
        numero: normalizado.numero,
        reintentar_con: r.error?.retryAfterSeconds,
      },
    );
  }

  return okResponse({
    ok: true,
    session_id: sessionId,
    chat_id: normalizado.chatId,
    numero: normalizado.numero,
    idempotency_key: idem ?? null,
    resultado: r.data ?? null,
  });
});