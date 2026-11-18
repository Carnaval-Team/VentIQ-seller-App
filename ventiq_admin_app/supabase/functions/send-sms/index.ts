// Supabase Edge Function: send-sms
//
// Worker del outbox `muevete.sms_mensajes` (migración 050_sms_outbox.sql).
// Es un servicio REUTILIZABLE: cualquier app/proceso encola con
//   select muevete.fn_sms_encolar('+5355550001','texto','aviso','ventiq_app');
// y esta función lo despacha con el proveedor configurado en
// `muevete.configuracion_sms` (fila única id = 1).
//
// QUE HACE
//   1. Valida el secreto de invocación (cron o service_role).
//   2. Lee la configuración y la tanda de pendientes con fn_sms_pendientes().
//   3. Despacha cada mensaje según `proveedor`:
//        mock      → no llama a nadie; marca `enviado` con 'mock-<id>'.
//        clicksend → POST https://rest.clicksend.com/v3/sms/send
//        twilio    → adapter listo (NO sirve para Cuba, ver nota abajo).
//   4. Marca el resultado con fn_sms_marcar(); el backoff/reintentos vive en
//      la base de datos (no se duplica aquí).
//
// SEGURIDAD
//   · Requiere `x-sms-secret: <SMS_CRON_SECRET>` o
//     `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`. Si no → 401.
//   · El texto del SMS puede llevar un OTP: en los logs SÓLO se escribe
//     id, tipo y destinatario enmascarado. Nunca `texto`.
//
// TWILIO Y CUBA
//   Twilio NO entrega SMS a números cubanos (+53). El adapter se deja listo
//   para otros países, pero para Cuba el proveedor realista es ClickSend
//   (one-way, requiere Alpha Tag). Si configuras twilio con números +53 los
//   envíos fallarán y el outbox los reintentará hasta agotar max_intentos.
//
// Deploy:
//   supabase functions deploy send-sms --no-verify-jwt \
//     --project-ref <PROYECTO_DE_PRUEBAS>
//   supabase secrets set SMS_CRON_SECRET=... CLICKSEND_USERNAME=... \
//     CLICKSEND_API_KEY=... --project-ref <PROYECTO_DE_PRUEBAS>
//
// ¿POR QUÉ --no-verify-jwt?
//   Con la verificación JWT por defecto, el runtime exige un JWT válido ANTES
//   de ejecutar esta función y el cron (que manda x-sms-secret, no un JWT)
//   recibiría 401. La función ya valida su propio secreto o el Bearer de
//   service_role, así que desactivar verify_jwt no abre nada: sin secreto
//   correcto responde 401. Alternativa sin --no-verify-jwt: que el cron mande
//   `Authorization: Bearer <service_role>` (guardado en Vault).
//
// Programación (pg_cron + pg_net), cada minuto:
//   select cron.schedule('send-sms', '* * * * *', $$
//     select net.http_post(
//       url := 'https://<ref>.supabase.co/functions/v1/send-sms',
//       headers := jsonb_build_object(
//         'Content-Type','application/json',
//         'x-sms-secret', (select decrypted_secret from vault.decrypted_secrets
//                           where name = 'sms_cron_secret')),
//       body := '{}'::jsonb);
//   $$);
//
// Variables de entorno (Supabase → Edge Functions → Secrets):
//   SMS_CRON_SECRET      obligatorio para el cron (header x-sms-secret)
//   CLICKSEND_USERNAME   usuario de la API de ClickSend
//   CLICKSEND_API_KEY    API key de ClickSend
//   TWILIO_ACCOUNT_SID   (opcional, otros países)
//   TWILIO_AUTH_TOKEN    (opcional)
//   TWILIO_FROM          (opcional; si falta se usa configuracion_sms.remitente)
//
// PROVEEDOR `whatsapp` (el que usamos en Cuba):
//   Reutiliza el gateway OpenWA que ya corre para ventiq_admin_app.
//   WAPI_BASE_URL   → ej. http://<host>:2785
//   WAPI_API_KEY    → clave `owa_k1_...` (header X-API-Key)
//   WAPI_SESSION_ID → sesión WAPI; si falta se usa
//                     `configuracion_sms.whatsapp_session_id`
//   El destinatario llega en E.164 (`+5354590207`) y se envía como
//   `<digitos>@c.us` (`5354590207@c.us`), que es el formato de OpenWA.

import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-sms-secret',
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
};

/** Máximo de mensajes por invocación (la cola reintenta el resto al minuto). */
const LIMITE_POR_TANDA = 25;

/** Corte de red por proveedor para no colgar la invocación. */
const TIMEOUT_MS = 15_000;

const CLICKSEND_URL = 'https://rest.clicksend.com/v3/sms/send';
const TWILIO_URL_BASE = 'https://api.twilio.com/2010-04-01/Accounts';

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

interface MensajeSms {
  id: number;
  app: string;
  destinatario: string;
  texto: string;
  tipo: string;
  ref_tabla: string | null;
  ref_id: string | null;
  estado: string;
  intentos: number;
}

interface ConfigSms {
  proveedor: string;
  remitente: string | null;
  activo: boolean;
  max_intentos: number;
  /** Sesión WAPI a usar cuando `proveedor = 'whatsapp'`. */
  whatsapp_session_id?: string | null;
}

/** Gateway OpenWA (WhatsApp) que ya corre para el panel. */
const WAPI_BASE = (Deno.env.get('WAPI_BASE_URL') ?? '').replace(/\/$/, '');
const WAPI_KEY = Deno.env.get('WAPI_API_KEY') ?? '';

interface ResultadoEnvio {
  ok: boolean;
  estado: 'enviado' | 'error';
  proveedor_msg_id?: string | null;
  error?: string;
}

interface Detalle {
  id: number;
  tipo: string;
  destinatario: string;
  estado: 'enviado' | 'error';
  proveedor: string;
  motivo?: string;
}

/** Enmascara el teléfono para logs/respuesta: +53••••001. */
function enmascarar(telefono: string): string {
  const limpio = telefono.trim();
  if (limpio.length <= 6) return '••••';
  return `${limpio.slice(0, 3)}••••${limpio.slice(-3)}`;
}

function mensajeError(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

/** Comparación en tiempo constante para el secreto del cron. */
function iguales(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

/** Basic Auth con UTF-8 seguro (btoa directo falla con no-ASCII). */
function basicAuth(usuario: string, clave: string): string {
  const bytes = new TextEncoder().encode(`${usuario}:${clave}`);
  let binario = '';
  for (const b of bytes) binario += String.fromCharCode(b);
  return `Basic ${btoa(binario)}`;
}

function autorizado(req: Request, serviceKey: string): boolean {
  const secreto = Deno.env.get('SMS_CRON_SECRET') ?? '';
  const enviado = req.headers.get('x-sms-secret') ?? '';
  if (secreto.length > 0 && enviado.length > 0 && iguales(enviado, secreto)) {
    return true;
  }
  const auth = req.headers.get('Authorization') ?? '';
  return iguales(auth, `Bearer ${serviceKey}`);
}

// ---------------------------------------------------------------------------
// Proveedores
// ---------------------------------------------------------------------------

/** mock: modo sin SMS. No llama a nadie y deja el flujo marcado como enviado. */
function enviarMock(msg: MensajeSms): ResultadoEnvio {
  return { ok: true, estado: 'enviado', proveedor_msg_id: `mock-${msg.id}` };
}

/**
 * ClickSend (recomendado para Cuba; one-way, requiere Alpha Tag).
 * Respuesta: { data: { messages: [{ status: 'SUCCESS'|'FAILED', message_id }] } }
 */
async function enviarClicksend(
  msg: MensajeSms,
  config: ConfigSms,
): Promise<ResultadoEnvio> {
  const usuario = Deno.env.get('CLICKSEND_USERNAME') ?? '';
  const apiKey = Deno.env.get('CLICKSEND_API_KEY') ?? '';
  const remitente = (config.remitente ?? Deno.env.get('CLICKSEND_FROM') ?? '')
    .trim();

  if (!usuario || !apiKey) {
    return { ok: false, estado: 'error', error: 'clicksend_no_configurado' };
  }
  if (!remitente) {
    // ClickSend exige `from` (Alpha Tag) para Cuba.
    return { ok: false, estado: 'error', error: 'clicksend_sin_remitente' };
  }

  const resp = await fetch(CLICKSEND_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: basicAuth(usuario, apiKey),
    },
    body: JSON.stringify({
      messages: [
        {
          source: 'dart',
          from: remitente,
          body: msg.texto,
          to: msg.destinatario,
        },
      ],
    }),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  const data = await resp.json().catch(() => null) as
    | { data?: { messages?: Array<{ status?: string; message_id?: string }> } }
    | null;

  if (!resp.ok) {
    return { ok: false, estado: 'error', error: `clicksend_http_${resp.status}` };
  }

  const primero = data?.data?.messages?.[0];
  const status = String(primero?.status ?? '').toUpperCase();
  const msgId = primero?.message_id ?? null;

  if (status === 'SUCCESS') {
    return { ok: true, estado: 'enviado', proveedor_msg_id: msgId };
  }
  return {
    ok: false,
    estado: 'error',
    proveedor_msg_id: msgId,
    error: `clicksend_${status || 'sin_estado'}`,
  };
}

/**
 * Twilio (NO soporta Cuba: adapter para otros países).
 * Respuesta: { sid, status: 'queued'|'sent'|'delivered'|'failed'|... }
 */
async function enviarTwilio(
  msg: MensajeSms,
  config: ConfigSms,
): Promise<ResultadoEnvio> {
  const sid = Deno.env.get('TWILIO_ACCOUNT_SID') ?? '';
  const token = Deno.env.get('TWILIO_AUTH_TOKEN') ?? '';
  const from = (Deno.env.get('TWILIO_FROM') ?? config.remitente ?? '').trim();

  if (!sid || !token || !from) {
    return { ok: false, estado: 'error', error: 'twilio_no_configurado' };
  }

  const cuerpo = new URLSearchParams({
    To: msg.destinatario,
    From: from,
    Body: msg.texto,
  });

  const resp = await fetch(`${TWILIO_URL_BASE}/${sid}/Messages.json`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      Authorization: basicAuth(sid, token),
    },
    body: cuerpo.toString(),
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });

  const data = await resp.json().catch(() => null) as
    | { sid?: string; status?: string }
    | null;

  if (!resp.ok) {
    return { ok: false, estado: 'error', error: `twilio_http_${resp.status}` };
  }

  const status = String(data?.status ?? '').toLowerCase();
  const msgId = data?.sid ?? null;
  if (['queued', 'sent', 'delivered', 'accepted', 'sending'].includes(status)) {
    return { ok: true, estado: 'enviado', proveedor_msg_id: msgId };
  }
  return {
    ok: false,
    estado: 'error',
    proveedor_msg_id: msgId,
    error: `twilio_${status || 'sin_estado'}`,
  };
}

/**
 * WhatsApp por el gateway OpenWA que ya corre para el panel.
 *
 * `mensajes_sms.destinatario` está en E.164 (`+5354590207`) porque lo valida la
 * BD. OpenWA no entiende E.164: quiere `<digitos>@c.us` → `5354590207@c.us`
 * (sin `+`, sin espacios). Aquí se hace esa conversión, y es la única que hay
 * que conocer para mandar a Cuba.
 */
async function enviarWhatsapp(
  msg: MensajeSms,
  config: ConfigSms,
): Promise<ResultadoEnvio> {
  if (!WAPI_BASE) {
    return { ok: false, estado: 'error', error: 'whatsapp_no_configurado' };
  }
  const session = (Deno.env.get('WAPI_SESSION_ID') ?? config.whatsapp_session_id ?? '')
    .trim();
  if (!session) {
    return { ok: false, estado: 'error', error: 'whatsapp_sin_sesion' };
  }

  const digitos = msg.destinatario.replace(/[^\d]/g, '');
  if (digitos.length < 8 || digitos.length > 15) {
    return { ok: false, estado: 'error', error: 'whatsapp_numero_invalido' };
  }
  const chatId = `${digitos}@c.us`;

  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), TIMEOUT_MS);
  try {
    const resp = await fetch(
      `${WAPI_BASE}/api/sessions/${encodeURIComponent(session)}/messages/send-text`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(WAPI_KEY ? { 'X-API-Key': WAPI_KEY } : {}),
        },
        body: JSON.stringify({ chatId, text: msg.texto }),
        signal: ctrl.signal,
      },
    );

    const txt = await resp.text();
    let parsed: any = null;
    try {
      parsed = txt ? JSON.parse(txt) : null;
    } catch {
      parsed = { raw: txt };
    }

    if (!resp.ok || parsed?.success === false) {
      // Nunca el texto (lleva OTP); sólo el código de error del gateway.
      const code = parsed?.error?.code ?? `whatsapp_http_${resp.status}`;
      return { ok: false, estado: 'error', error: String(code) };
    }

    const id = parsed?.data?.id ?? parsed?.data?.messageId ?? parsed?.messageId ?? null;
    return {
      ok: true,
      estado: 'enviado',
      proveedor_msg_id: id ? String(id) : `wa-${msg.id}`,
    };
  } catch (e) {
    const err = e as Error;
    const motivo = err.name === 'AbortError' ? 'timeout' : err.message;
    return { ok: false, estado: 'error', error: `whatsapp_red: ${motivo}` };
  } finally {
    clearTimeout(timer);
  }
}

async function despachar(
  msg: MensajeSms,
  config: ConfigSms,
): Promise<ResultadoEnvio> {
  switch (config.proveedor) {
    case 'mock':
      return enviarMock(msg);
    case 'whatsapp':
      return await enviarWhatsapp(msg, config);
    case 'clicksend':
      return await enviarClicksend(msg, config);
    case 'twilio':
      return await enviarTwilio(msg, config);
    default:
      return { ok: false, estado: 'error', error: 'proveedor_no_soportado' };
  }
}

// ---------------------------------------------------------------------------
// Handler
// ---------------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST' && req.method !== 'GET') {
    return json({ ok: false, error: 'metodo_no_permitido' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceKey) {
    return json({ ok: false, error: 'config_servidor' }, 500);
  }

  if (!autorizado(req, serviceKey)) {
    // Diagnóstico sin secretos: sólo booleanos. Un 401 mudo es imposible de
    // depurar desde el cron (pg_net sólo devuelve el cuerpo de la respuesta).
    // Los nombres se calculan aquí para no exponer ningún valor.
    const secretoEnv = Deno.env.get('SMS_CRON_SECRET') ?? '';
    const secretoRecibido = req.headers.get('x-sms-secret') ?? '';
    const auth = req.headers.get('Authorization') ?? '';
    console.error(
      '[send-sms] no_autorizado ' +
        JSON.stringify({
          sms_cron_secret_configurado: secretoEnv.length > 0,
          x_sms_secret_recibido: secretoRecibido.length > 0,
          x_sms_secret_coincide: secretoEnv.length > 0 &&
            secretoRecibido.length > 0 &&
            iguales(secretoRecibido, secretoEnv),
          authorization_recibido: auth.length > 0,
          authorization_es_service_role: iguales(auth, `Bearer ${serviceKey}`),
        }),
    );
    return json({ ok: false, error: 'no_autorizado' }, 401);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) Configuración (fila única id = 1).
  const { data: cfg, error: cfgError } = await admin
    .schema('muevete')
    .from('configuracion_sms')
    .select('proveedor, remitente, activo, max_intentos, whatsapp_session_id')
    .eq('id', 1)
    .maybeSingle();

  if (cfgError) {
    console.error('[send-sms] configuracion_sms:', cfgError.message);
    return json({ ok: false, error: 'config_sms' }, 500);
  }

  const config: ConfigSms = {
    proveedor: String(cfg?.proveedor ?? 'mock').toLowerCase(),
    remitente: (cfg?.remitente as string | null) ?? null,
    activo: cfg?.activo !== false,
    max_intentos: Number(cfg?.max_intentos ?? 3),
    // Sin esta asignación la columna de la BD se ignoraba y sólo funcionaba
    // si además existía el secreto WAPI_SESSION_ID. Rompía el envío con
    // `whatsapp_sin_sesion` aunque `configuracion_sms` estuviera bien.
    whatsapp_session_id: (cfg?.whatsapp_session_id as string | null) ?? null,
  };

  // Interruptor global: si está apagado no se consume la cola.
  if (!config.activo) {
    return json({
      ok: true,
      procesados: 0,
      enviados: 0,
      errores: 0,
      simulado: false,
      activo: false,
      detalle: [],
    });
  }

  // 2) Pendientes (la RPC exige service_role; este cliente lo es).
  const { data: pendientes, error: pendError } = await admin
    .schema('muevete')
    .rpc('fn_sms_pendientes', { p_limite: LIMITE_POR_TANDA });

  if (pendError) {
    console.error('[send-sms] fn_sms_pendientes:', pendError.message);
    return json({ ok: false, error: 'cola_no_disponible' }, 500);
  }

  const mensajes: MensajeSms[] = Array.isArray(pendientes)
    ? (pendientes as MensajeSms[])
    : [];

  const simulado = config.proveedor === 'mock';
  const detalle: Detalle[] = [];
  let enviados = 0;
  let errores = 0;

  for (const msg of mensajes) {
    let resultado: ResultadoEnvio;
    try {
      resultado = await despachar(msg, config);
    } catch (e) {
      resultado = { ok: false, estado: 'error', error: mensajeError(e) };
    }

    // 3) Marcar en el outbox. El backoff/reintento lo decide fn_sms_marcar.
    const { error: marcaError } = await admin
      .schema('muevete')
      .rpc('fn_sms_marcar', {
        p_id: msg.id,
        p_estado: resultado.estado,
        p_error: resultado.ok ? null : (resultado.error ?? 'error_envio'),
        p_proveedor: config.proveedor,
        p_proveedor_msg_id: resultado.proveedor_msg_id ?? null,
      });

    if (marcaError) {
      // No se pudo registrar el resultado: la fila sigue `pendiente` y el
      // próximo minuto se reintenta (posible duplicado si el proveedor ya la
      // había aceptado). Se cuenta como error para que el cron lo delate.
      console.error('[send-sms] fn_sms_marcar:', msg.id, marcaError.message);
      errores++;
      detalle.push({
        id: msg.id,
        tipo: msg.tipo,
        destinatario: enmascarar(msg.destinatario),
        estado: resultado.estado,
        proveedor: config.proveedor,
        motivo: 'no_se_pudo_marcar',
      });
      continue;
    }

    if (resultado.ok) {
      enviados++;
    } else {
      errores++;
    }

    // Log mínimo y sin PII sensible: NUNCA el texto (puede llevar un OTP).
    console.log(
      `[send-sms] id=${msg.id} tipo=${msg.tipo} destino=${enmascarar(msg.destinatario)} estado=${resultado.estado} proveedor=${config.proveedor}`,
    );

    detalle.push({
      id: msg.id,
      tipo: msg.tipo,
      destinatario: enmascarar(msg.destinatario),
      estado: resultado.estado,
      proveedor: config.proveedor,
      ...(resultado.error ? { motivo: resultado.error } : {}),
    });
  }

  return json({
    ok: true,
    procesados: mensajes.length,
    enviados,
    errores,
    simulado,
    proveedor: config.proveedor,
    detalle,
  });
});