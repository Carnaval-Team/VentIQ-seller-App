// Supabase Edge Function: contacto-invitacion
//
// Página PÚBLICA de confirmación de un contacto de emergencia de Muévete.
// La abre el contacto desde el navegador del móvil, SIN sesión y SIN instalar
// la app. Es el camino alternativo cuando el gateway de WhatsApp del bot está
// caído: el usuario comparte un enlace (WhatsApp/Telegram/SMS) y el contacto
// lo abre y confirma.
//
// CONTRATO
//   GET /functions/v1/contacto-invitacion?token=<32 bytes en hex (64 chars)>
//     → HTML mobile-first (nunca JSON) con uno de estos estados:
//         · confirmado          (success=true,  ya_confirmado=false)
//         · ya estaba confirmado(success=true,  ya_confirmado=true)
//         · enlace vencido      (success=false, motivo=token_expirado)
//         · enlace no válido    (success=false, motivo=token_invalido)
//         · error temporal      (la RPC no respondió / falta configuración)
//   Cualquier otro método → 405 (Allow: GET).
//   Sin `token`            → 400 con página de error.
//
// CÓMO CONFIRMA
//   La función llama SERVER-SIDE a
//     POST {SUPABASE_URL}/rest/v1/rpc/fn_confirmar_contacto_invitacion
//   con la clave anónima (la RPC tiene GRANT EXECUTE a `anon`,
//   migración 050_sms_outbox.sql) y body { "p_token": "<token>" }.
//   El token NUNCA se escribe en los logs ni se renderiza en el HTML.
//   Como `muevete` no es el esquema por defecto de PostgREST, la petición
//   lleva las cabeceras `Content-Profile`/`Accept-Profile: muevete`.
//
// DESPLIEGUE (PRUEBAS · qhprswhhfasrikhawjoz · NUNCA producción sin decisión)
//   supabase functions deploy contacto-invitacion --no-verify-jwt \
//     --project-ref qhprswhhfasrikhawjoz
//
//   ¿Por qué --no-verify-jwt? La llama un `anon` sin sesión, desde el
//   navegador de una persona que no tiene cuenta. La función no confía en el
//   llamante: sólo actúa por posesión del token (32 bytes aleatorios, hash
//   SHA-256 en BD, un solo uso, 7 días de vigencia). Desactivar verify_jwt no
//   abre nada que no esté ya abierto a `anon` por la propia RPC.
//
// VARIABLES DE ENTORNO
//   SUPABASE_URL        la inyecta Supabase automáticamente.
//   SUPABASE_ANON_KEY   la inyecta Supabase automáticamente.
//   MUEVETE_APP_URL     OPCIONAL. Enlace para el botón "Abrir Muévete" de la
//                       página de error (p. ej. una landing o, cuando exista,
//                       el deep link/Play Store). Si falta, el botón se pinta
//                       sin enlace.
//
// SEGURIDAD
//   · Cache-Control: no-store (el token viaja en la URL; no debe cachearse).
//   · Referrer-Policy: no-referrer (que el token no se filtre por Referer).
//   · CSP cerrada: no se carga ni ejecuta nada externo (la página no usa JS).
//   · Todo texto que venga de la base se escapa antes de pintarse (escapeHtml).
//   · Los logs sólo dicen "fallo al confirmar" + status; nunca el token.

/** Naranja de marca Muévete (ya usada en la app: landing_screen.dart). */
const NARANJA = '#FE6B00';

/**
 * Token válido tal como lo genera `fn_contacto_invitacion`: 32 bytes en hex.
 * Se admite un rango holgado por si algún día cambia el largo, pero se exige
 * sólo hexadecimal para no mandar basura a PostgREST.
 */
const TOKEN_RE = /^[0-9a-fA-F]{16,128}$/;

/** Corte de red: la página se abre en el móvil, no puede quedarse colgada. */
const TIMEOUT_MS = 8_000;

// ── Helpers ────────────────────────────────────────────────────────────────

function escapeHtml(valor: unknown): string {
  return String(valor ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');
}

function recorta(valor: string, max = 80): string {
  const limpio = valor.replace(/\s+/g, ' ').trim();
  return limpio.length > max ? `${limpio.slice(0, max - 1)}…` : limpio;
}

function cabecerasHtml(status: number, extra: Record<string, string> = {}): Headers {
  const headers = new Headers({
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store, max-age=0',
    'Referrer-Policy': 'no-referrer',
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    // La página no usa JavaScript ni recursos externos: CSP mínima.
    'Content-Security-Policy':
      "default-src 'none'; style-src 'unsafe-inline'; img-src data:; " +
      "base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    'Permissions-Policy': 'camera=(), microphone=(), geolocation=()',
  });
  for (const [k, v] of Object.entries(extra)) headers.set(k, v);
  return headers;
}

function paginaHtml(opciones: {
  estado: 'exito' | 'ya' | 'error';
  icono: string;
  titulo: string;
  cuerpo: string;
  nota?: string;
  botonApp?: string;
}): string {
  const { estado, icono, titulo, cuerpo, nota, botonApp } = opciones;

  return `<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<meta name="theme-color" content="${NARANJA}">
<title>${escapeHtml(titulo)} · Muévete</title>
<style>
  :root {
    --naranja: ${NARANJA};
    --naranja-suave: #FFF1E6;
    --tinta: #1A1D27;
    --gris: #5B6270;
    --fondo: #F5F7FA;
    --linea: #E6E8EE;
  }
  * { box-sizing: border-box; }
  html, body { margin: 0; padding: 0; }
  body {
    min-height: 100dvh;
    background: var(--fondo);
    color: var(--tinta);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto,
      "Helvetica Neue", Arial, sans-serif;
    display: flex;
    flex-direction: column;
    align-items: center;
    padding: 0 16px calc(28px + env(safe-area-inset-bottom));
  }
  header {
    width: 100%;
    max-width: 520px;
    padding: calc(18px + env(safe-area-inset-top)) 2px 18px;
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .marca {
    width: 34px; height: 34px; border-radius: 10px;
    background: var(--naranja);
    color: #fff; font-weight: 800; font-size: 19px;
    display: grid; place-items: center;
    box-shadow: 0 4px 12px rgba(254, 107, 0, .28);
  }
  .marca-texto { font-weight: 800; font-size: 18px; letter-spacing: -.2px; }
  .marca-texto span { color: var(--naranja); }
  main {
    width: 100%; max-width: 520px;
    background: #fff;
    border: 1px solid var(--linea);
    border-radius: 22px;
    padding: 30px 22px 26px;
    box-shadow: 0 10px 30px rgba(26, 29, 39, .07);
    text-align: center;
  }
  .icono {
    width: 62px; height: 62px; margin: 0 auto 16px;
    border-radius: 50%;
    display: grid; place-items: center;
    font-size: 30px; line-height: 1;
    background: var(--naranja-suave);
  }
  .icono.ok { background: #E8F9EE; }
  .icono.aviso { background: var(--naranja-suave); }
  h1 {
    margin: 0 0 12px;
    font-size: clamp(22px, 6vw, 26px);
    line-height: 1.2;
    font-weight: 800;
    letter-spacing: -.3px;
  }
  p { margin: 0 0 12px; font-size: 15px; line-height: 1.5; color: var(--gris); }
  p strong { color: var(--tinta); }
  .dato {
    margin-top: 18px;
    padding: 12px 14px;
    border-radius: 14px;
    background: #F7F8FB;
    border: 1px solid var(--linea);
    font-size: 13.5px;
    color: var(--gris);
  }
  .dato strong { color: var(--tinta); letter-spacing: .5px; }
  .boton {
    display: block;
    margin-top: 22px;
    width: 100%;
    padding: 15px 18px;
    border-radius: 14px;
    background: var(--naranja);
    color: #fff !important;
    font-size: 15.5px;
    font-weight: 700;
    text-decoration: none;
    text-align: center;
  }
  .boton-inactivo {
    opacity: .45;
    cursor: default;
  }
  .nota { margin: 14px 0 0; font-size: 12.5px; color: var(--gris); line-height: 1.45; }
  footer {
    width: 100%; max-width: 520px;
    margin-top: 18px;
    text-align: center;
    font-size: 12px;
    color: var(--gris);
    line-height: 1.45;
  }
  @media (prefers-color-scheme: dark) {
    :root { --fondo: #0F1117; --tinta: #FFFFFF; --gris: #B4BAC7; --linea: #2E3347; }
    body { background: var(--fondo); }
    main { background: #1A1D27; box-shadow: none; }
    .dato { background: #222636; }
  }
</style>
</head>
<body>
  <header>
    <div class="marca" aria-hidden="true">M</div>
    <div class="marca-texto">Muéve<span>te</span></div>
  </header>

  <main>
    <div class="icono ${estado === 'exito' ? 'ok' : 'aviso'}" aria-hidden="true">${icono}</div>
    <h1>${escapeHtml(titulo)}</h1>
    ${cuerpo}
    ${nota ? `<p class="nota">${nota}</p>` : ''}
    ${botonApp ?? ''}
  </main>

  <footer>Muévete · Contacto de emergencia</footer>
</body>
</html>`;
}

function paginaError(opciones: {
  titulo: string;
  mensaje: string;
  nota?: string;
  conBotonApp?: boolean;
}): string {
  const appUrl = leerAppUrl();
  const boton =
    opciones.conBotonApp === false
      ? ''
      : appUrl
        ? `<a class="boton" href="${escapeHtml(appUrl)}" rel="noopener noreferrer">Abrir Muévete</a>`
        : `<span class="boton boton-inactivo" role="button" aria-disabled="true">Abrir Muévete</span>
           <p class="nota">Abre la app Muévete en tu teléfono para ver tus contactos.</p>`;

  return paginaHtml({
    estado: 'error',
    icono: '⚠️',
    titulo: opciones.titulo,
    cuerpo: `<p>${escapeHtml(opciones.mensaje)}</p>`,
    nota: opciones.nota,
    botonApp: boton,
  });
}

/** Enlace opcional para el botón "Abrir Muévete" (sin enlace válido, no se pinta). */
function leerAppUrl(): string | null {
  const valor = (Deno.env.get('MUEVETE_APP_URL') ?? '').trim();
  if (!valor) return null;
  if (!/^(https?:\/\/|muevete:\/\/|market:\/\/|itms-apps:\/\/)/i.test(valor)) {
    return null;
  }
  return valor;
}

// ── Llamada a la RPC pública ───────────────────────────────────────────────

interface ResultadoRpc {
  success?: boolean;
  ya_confirmado?: boolean;
  contacto_nombre?: string;
  aceptado_por?: string;
  motivo?: string;
}

type Consulta =
  | { tipo: 'ok'; data: ResultadoRpc }
  | { tipo: 'negocio'; motivo: string; data: ResultadoRpc }
  | { tipo: 'fallo' };

async function confirmarToken(token: string): Promise<Consulta> {
  const base = (Deno.env.get('SUPABASE_URL') ?? '').replace(/\/+$/, '');
  const anon =
    Deno.env.get('SUPABASE_ANON_KEY') ??
    Deno.env.get('SUPABASE_PUBLISHABLE_KEY') ??
    '';

  if (!base || !anon) {
    console.error('[contacto-invitacion] faltan SUPABASE_URL/SUPABASE_ANON_KEY');
    return { tipo: 'fallo' };
  }

  let respuesta: Response;
  try {
    respuesta = await fetch(
      `${base}/rest/v1/rpc/fn_confirmar_contacto_invitacion`,
      {
        method: 'POST',
        headers: {
          apikey: anon,
          Authorization: `Bearer ${anon}`,
          'Content-Type': 'application/json',
          Accept: 'application/json',
          // `muevete` no es el esquema por defecto de PostgREST.
          'Content-Profile': 'muevete',
          'Accept-Profile': 'muevete',
        },
        body: JSON.stringify({ p_token: token }),
        signal: AbortSignal.timeout(TIMEOUT_MS),
      },
    );
  } catch (e) {
    // Nunca se registra el token; sólo el tipo de fallo.
    console.error('[contacto-invitacion] la RPC no respondió:', String(e).slice(0, 120));
    return { tipo: 'fallo' };
  }

  if (!respuesta.ok) {
    // P. ej. `pepper_no_configurado`, 401 de PostgREST o 5xx: no se muestra el
    // detalle del servidor, sólo un mensaje temporal.
    console.error(
      '[contacto-invitacion] RPC status',
      respuesta.status,
    );
    return { tipo: 'fallo' };
  }

  let data: ResultadoRpc;
  try {
    data = (await respuesta.json()) as ResultadoRpc;
  } catch {
    console.error('[contacto-invitacion] respuesta de la RPC no es JSON');
    return { tipo: 'fallo' };
  }

  if (data.success !== true) {
    return {
      tipo: 'negocio',
      motivo: (data.motivo ?? 'token_invalido').toString(),
      data,
    };
  }
  return { tipo: 'ok', data };
}

// ── Páginas por estado ─────────────────────────────────────────────────────

function paginaConfirmado(
  nombre: string,
  aceptadoPor: string,
): string {
  const nombreHtml = escapeHtml(recorta(nombre) || 'Contacto de emergencia');
  const numeroHtml = escapeHtml(recorta(aceptadoPor, 24));

  return paginaHtml({
    estado: 'exito',
    icono: '✅',
    titulo: 'Contacto confirmado',
    cuerpo: `
      <p><strong>${nombreHtml}</strong>, te agregaron como contacto de
      emergencia en Muévete.</p>
      <p>La persona que te agregó ya puede avisarte si tiene una emergencia.
      No necesitas instalar la app ni hacer nada más.</p>
      <div class="dato">Confirmado desde el número
        <strong>${numeroHtml}</strong></div>`,
    nota: 'Guarda este mensaje: el enlace ya se usó y no vuelve a funcionar.',
  });
}

function paginaYaConfirmado(
  nombre: string,
  aceptadoPor: string,
): string {
  const nombreHtml = escapeHtml(recorta(nombre) || 'este contacto');
  const numeroHtml = escapeHtml(recorta(aceptadoPor, 24));

  return paginaHtml({
    estado: 'ya',
    icono: '✅',
    titulo: 'Este contacto ya estaba confirmado',
    cuerpo: `
      <p>No hace falta que hagas nada más:
      <strong>${nombreHtml}</strong> ya aparece como contacto de emergencia
      verificado en Muévete.</p>
      <div class="dato">Confirmado desde el número
        <strong>${numeroHtml}</strong></div>`,
  });
}

function paginaEnlaceInvalido(motivoPage: 'expirado' | 'invalido'): string {
  if (motivoPage === 'expirado') {
    return paginaError({
      titulo: 'Este enlace venció',
      mensaje:
        'Los enlaces de invitación duran 7 días. Pídele a la persona que te ' +
        'agregó que te comparta uno nuevo desde Muévete.',
    });
  }
  return paginaError({
    titulo: 'Enlace no válido',
    mensaje:
      'Este enlace no existe, ya se usó o está incompleto. Pídele a la ' +
      'persona que te agregó que te comparta uno nuevo desde Muévete.',
  });
}

function respuestaHtml(html: string, status: number): Response {
  return new Response(html, { status, headers: cabecerasHtml(status) });
}

// ── Handler ────────────────────────────────────────────────────────────────

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== 'GET') {
    return new Response(
      paginaError({
        titulo: 'Método no permitido',
        mensaje: 'Este enlace se abre directamente en el navegador (GET).',
        conBotonApp: false,
      }),
      {
        status: 405,
        headers: cabecerasHtml(405, { Allow: 'GET' }),
      },
    );
  }

  let token = '';
  try {
    token = (new URL(req.url).searchParams.get('token') ?? '').trim();
  } catch {
    token = '';
  }

  if (!token) {
    return respuestaHtml(
      paginaError({
        titulo: 'Enlace incompleto',
        mensaje:
          'Falta el código de la invitación. Abre el enlace completo que te ' +
          'compartieron, sin quitarle nada.',
        conBotonApp: false,
      }),
      400,
    );
  }

  if (!TOKEN_RE.test(token)) {
    return respuestaHtml(paginaEnlaceInvalido('invalido'), 400);
  }

  const consulta = await confirmarToken(token);

  if (consulta.tipo === 'fallo') {
    return respuestaHtml(
      paginaError({
        titulo: 'No pudimos confirmar el enlace',
        mensaje:
          'Es un problema temporal de Muévete, no tuyo. Inténtalo otra vez en ' +
          'unos minutos con el mismo enlace.',
      }),
      503,
    );
  }

  if (consulta.tipo === 'negocio') {
    return respuestaHtml(
      paginaEnlaceInvalido(
        consulta.motivo === 'token_expirado' ? 'expirado' : 'invalido',
      ),
      200,
    );
  }

  const nombre = (consulta.data.contacto_nombre ?? '').toString();
  const aceptadoPor = (consulta.data.aceptado_por ?? '').toString();

  return respuestaHtml(
    consulta.data.ya_confirmado === true
      ? paginaYaConfirmado(nombre, aceptadoPor)
      : paginaConfirmado(nombre, aceptadoPor),
    200,
  );
});