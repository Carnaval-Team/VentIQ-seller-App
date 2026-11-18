#!/usr/bin/env node
// ============================================================================
// wa-dispatcher.mjs
// Worker del outbox de mensajes (`muevete.sms_mensajes`) que los envía por
// WhatsApp usando el gateway OpenWA.
//
// ── POR QUÉ CORRE EN TU VPS Y NO EN SUPABASE ───────────────────────────────
// El firewall de `89.40.7.25:2785` descarta las IPs de Supabase (pg_net se
// queda en el handshake TCP). Comprobado:
//     desde internet  → GET /api/health = 200
//     desde Supabase  → timeout a los 15 s, 3 intentos
// Por eso el worker vive al lado del gateway y es él quien llama a Supabase.
//
// ── USO ───────────────────────────────────────────────────────────────────
//   node wa-dispatcher.mjs --once     # un ciclo (lo ideal para cron)
//   node wa-dispatcher.mjs --loop 20  # bucle cada 20 s
//
// ── VARIABLES DE ENTORNO ──────────────────────────────────────────────────
//   SUPABASE_URL               https://vsieeihstajlrdvpuooh.supabase.co
//   SUPABASE_SERVICE_ROLE_KEY  service_role del proyecto (NO la anon)
//   WAPI_BASE_URL              http://127.0.0.1:2785  (o el host que uses)
//   WAPI_API_KEY               owa_k1_...
//   WAPI_SESSION_ID            (opcional) uuid de la sesión; si falta se lee
//                              de muevete.configuracion_sms.whatsapp_session_id
//   LIMITE                     (opcional) mensajes por ciclo, default 25
//
// ── CRON (cada minuto) ────────────────────────────────────────────────────
//   * * * * * cd /ruta/app && /usr/bin/node scripts/wa-dispatcher.mjs --once >> /var/log/wa-dispatcher.log 2>&1
// ============================================================================

const SUPABASE_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '');
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const WAPI_BASE = (process.env.WAPI_BASE_URL || 'http://127.0.0.1:2785').replace(/\/$/, '');
const WAPI_KEY = process.env.WAPI_API_KEY || '';
const WAPI_SESSION = (process.env.WAPI_SESSION_ID || '').trim();
const LIMITE = Number(process.env.LIMITE || 25);

if (!SUPABASE_URL || !SERVICE_KEY) {
  console.error('[wa-dispatcher] faltan SUPABASE_URL o SUPABASE_SERVICE_ROLE_KEY');
  process.exit(2);
}

const H = {
  apikey: SERVICE_KEY,
  Authorization: `Bearer ${SERVICE_KEY}`,
  'Content-Type': 'application/json',
};

/** Llama a una RPC de PostgREST. */
async function rpc(nombre, params) {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${nombre}`, {
    method: 'POST',
    headers: H,
    body: JSON.stringify(params ?? {}),
    signal: AbortSignal.timeout(20000),
  });
  const txt = await r.text();
  if (!r.ok) throw new Error(`${nombre} ${r.status}: ${txt.slice(0, 300)}`);
  return txt ? JSON.parse(txt) : null;
}

/** +5353765120 → 5353765120@c.us (formato OpenWA). */
function aChatId(destinatario) {
  const digitos = String(destinatario || '').replace(/[^\d]/g, '');
  if (digitos.length < 8 || digitos.length > 15) return null;
  return `${digitos}@c.us`;
}

function enmascarar(tel) {
  const t = String(tel || '');
  return t.length <= 6 ? '••••' : `${t.slice(0, 3)}••••${t.slice(-3)}`;
}

/** Envía un mensaje por el gateway. Devuelve {ok, id, error}. */
async function enviarWhatsapp(sessionId, msg) {
  const chatId = aChatId(msg.destinatario);
  if (!chatId) return { ok: false, error: 'numero_invalido' };

  try {
    const r = await fetch(
      `${WAPI_BASE}/api/sessions/${encodeURIComponent(sessionId)}/messages/send-text`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(WAPI_KEY ? { 'X-API-Key': WAPI_KEY } : {}),
          // Idempotency-Key: sólo ASCII visible 1..255 (acentos dan 400).
          'Idempotency-Key': `sms-${msg.id}`,
        },
        body: JSON.stringify({ chatId, text: msg.texto }),
        signal: AbortSignal.timeout(30000),
      },
    );
    const txt = await r.text();
    let j = null;
    try { j = txt ? JSON.parse(txt) : null; } catch { j = { raw: txt }; }

    if (!r.ok || j?.success === false) {
      const code = j?.error?.code || j?.code || `http_${r.status}`;
      return { ok: false, error: String(code) };
    }
    const id = j?.data?.id || j?.messageId || j?.id || `wa-${msg.id}`;
    return { ok: true, id: String(id), chatId };
  } catch (e) {
    const motivo = e?.name === 'AbortError' || e?.name === 'TimeoutError' ? 'timeout' : e.message;
    return { ok: false, error: `red: ${motivo}` };
  }
}

async function ciclo() {
  // 1) Sesión: env o configuración de la BD
  let sessionId = WAPI_SESSION;
  if (!sessionId) {
    const cfg = await fetch(
      `${SUPABASE_URL}/rest/v1/configuracion_sms?select=whatsapp_session_id,proveedor,activo&id=eq.1`,
      { headers: H, signal: AbortSignal.timeout(15000) },
    ).then((r) => (r.ok ? r.json() : null));
    const fila = Array.isArray(cfg) ? cfg[0] : null;
    if (fila && fila.activo === false) {
      console.log('[wa-dispatcher] proveedor inactivo (activo=false); no se envía');
      return { procesados: 0 };
    }
    sessionId = fila?.whatsapp_session_id;
  }
  if (!sessionId) {
    console.error('[wa-dispatcher] sin sesión WAPI: define WAPI_SESSION_ID o whatsapp_session_id');
    return { procesados: 0 };
  }

  // 2) Pendientes (RPC sólo service_role)
  const pendientes = await rpc('fn_sms_pendientes', { p_limite: LIMITE });
  const lista = Array.isArray(pendientes) ? pendientes : [];
  if (lista.length === 0) return { procesados: 0 };

  let enviados = 0, errores = 0;

  for (const msg of lista) {
    const res = await enviarWhatsapp(sessionId, msg);

    // 3) Marcar resultado (la BD gestiona reintentos/backoff)
    await rpc('fn_sms_marcar', {
      p_id: msg.id,
      p_estado: res.ok ? 'enviado' : 'error',
      p_error: res.ok ? null : res.error,
      p_proveedor: 'whatsapp',
      p_proveedor_msg_id: res.ok ? res.id : null,
    }).catch((e) => console.error('[wa-dispatcher] fn_sms_marcar:', e.message));

    if (res.ok) {
      enviados++;
      console.log(`[wa-dispatcher] id=${msg.id} → ${enmascarar(msg.destinatario)} OK ${res.id}`);
    } else {
      errores++;
      console.error(`[wa-dispatcher] id=${msg.id} → ${enmascarar(msg.destinatario)} ERROR ${res.error}`);
    }

    // Anti-ban: los envíos van en serie y con una pausa corta.
    await new Promise((r) => setTimeout(r, 1200));
  }

  return { procesados: lista.length, enviados, errores };
}

const unaVez = process.argv.includes('--once');
const iLoop = process.argv.indexOf('--loop');

if (unaVez) {
  ciclo()
    .then((r) => { console.log('[wa-dispatcher] fin', JSON.stringify(r)); process.exit(0); })
    .catch((e) => { console.error('[wa-dispatcher] fatal:', e.message); process.exit(1); });
} else {
  const seg = iLoop >= 0 ? Number(process.argv[iLoop + 1] || 20) : 20;
  console.log(`[wa-dispatcher] bucle cada ${seg}s contra ${WAPI_BASE}`);
  for (;;) {
    try {
      const r = await ciclo();
      if (r.procesados) console.log('[wa-dispatcher]', JSON.stringify(r));
    } catch (e) {
      console.error('[wa-dispatcher] ciclo falló:', e.message);
    }
    await new Promise((r) => setTimeout(r, seg * 1000));
  }
}