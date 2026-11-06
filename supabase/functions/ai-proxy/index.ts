// Supabase Edge Function: ai-proxy
//
// Proxy transparente hacia el proveedor de IA configurado en la tabla
// `config_asistant_model`.
//
// POR QUE EXISTE ESTA FUNCION (dos problemas reales del acceso directo):
//   1. CORS: las apps Flutter Web llamaban DIRECTO al proveedor
//      (api.xkiro.com, Gemini, Anthropic...). Esos proveedores no permiten el
//      origen https://admin.inventtia.com, asi que el navegador bloqueaba la
//      respuesta. Al pasar por aqui, el navegador solo habla con el dominio de
//      Supabase (que si responde con CORS abierto) y el salto al proveedor lo
//      hace el servidor, donde CORS no aplica.
//   2. SEGURIDAD: la `api_key` vivia en `config_asistant_model`, que estaba
//      SIN RLS: cualquiera con la publishable key podia leerla desde el
//      cliente. Ahora esa tabla ya NO es legible por `anon`/`authenticated`,
//      de modo que la unica forma de obtener la clave es con el cliente
//      `service_role` que se crea aqui dentro. La clave nunca sale al cliente
//      ni se escribe en los logs.
//
// CONTRATO CON LAS APPS (congelado; los clientes ya escriben contra esto):
//   POST {SUPABASE_URL}/functions/v1/ai-proxy
//   Headers: Authorization: Bearer <JWT del usuario>,
//            apikey: <publishable key>,
//            Content-Type: application/json
//   Body:    { "body": <cuerpo especifico del proveedor, tal cual>,
//              "endpoint": "generateContent" }
//   OK:      respuesta del proveedor VERBATIM (mismo status y mismo JSON).
//   Errores propios: { "error": "<mensaje>" } con
//            400 (peticion mal formada) / 500 (sin config) / 502 (proveedor).
//
// La resolucion de URL y de autenticacion replica exactamente la del cliente
// Flutter en `ventiq_admin_app/lib/config/gemini_config.dart` (metodos
// `buildUri`, `buildHeaders`, `applyAuthToBody`, `_resolveParamName` y
// `_resolveParamValue`) para que la peticion que sale de aqui sea identica a
// la que antes salia del navegador.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

// Mismos corsHeaders que la funcion vecina `ai-assistant`.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// El cliente ya reintenta ante fallos transitorios, asi que aqui cortamos a los
// 60 s y devolvemos 502 en lugar de dejar la peticion colgada.
const PROVEEDOR_TIMEOUT_MS = 60_000;

// El `endpoint` viaja en la URL que construimos (`/<model>:<endpoint>`), por eso
// se valida antes: evita que un valor manipulado introduzca rutas, query o
// fragmentos en la URL del proveedor. El cliente solo manda `generateContent`
// (y a futuro variantes tipo `streamGenerateContent`).
const ENDPOINT_PERMITIDO = /^[A-Za-z0-9_]{1,64}$/;

interface ModeloConfig {
  apiKey: string;
  model: string;
  url: string;
  paramType: string; // query | body | header
  paramKey: string; // key | bearer | basic
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// Mensaje corto para los logs. NUNCA se registra la api_key ni el cuerpo de la
// peticion (el cuerpo lleva prompts del negocio; y en `param_type=body` llevaria
// la propia clave).
function mensajeError(e: unknown): string {
  return e instanceof Error ? e.message : String(e);
}

// Lee la fila mas reciente de config_asistant_model.
//
// Esta tabla ya no es legible por `anon`/`authenticated` (era el agujero por el
// que se filtraba la api_key), asi que es imprescindible el cliente
// `service_role` que recibe esta funcion.
async function leerConfigModelo(
  admin: ReturnType<typeof createClient>,
): Promise<ModeloConfig | null> {
  const { data, error } = await admin
    .from('config_asistant_model')
    .select('api_key, model, url, param_type, param_key, updated_at')
    .order('updated_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  if (error || !data) return null;
  return {
    apiKey: String(data.api_key ?? ''),
    model: String(data.model ?? ''),
    url: String(data.url ?? ''),
    paramType: String(data.param_type ?? 'header').toLowerCase(),
    paramKey: String(data.param_key ?? 'bearer').toLowerCase(),
  };
}

// Mismo criterio que `AssistantModelConfig`: el modelo viaja dentro del cuerpo
// en los proveedores OpenAI-compatible (chat/completions), no en la URL.
function incluyeModeloEnCuerpo(url: string): boolean {
  return url.toLowerCase().includes('chat/completions');
}

function esAnthropic(url: string): boolean {
  return url.toLowerCase().includes('/v1/messages');
}

function esMuleRouter(url: string): boolean {
  return url.toLowerCase().includes('mulerouter.ai');
}

// Replica de `_resolveParamName`: para `param_key=key` el parametro se llama
// `key`; en cualquier otro caso (bearer/basic) se llama `Authorization`.
function resolverNombreParametro(paramKey: string): string {
  return paramKey === 'key' ? 'key' : 'Authorization';
}

// Replica de `_resolveParamValue`: bearer/basic se prefijan, el resto va crudo.
function resolverValorParametro(paramKey: string, apiKey: string): string {
  if (paramKey === 'bearer') return `Bearer ${apiKey}`;
  if (paramKey === 'basic') return `Basic ${apiKey}`;
  return apiKey;
}

// Replica de `buildUri`. Se quita la barra final y luego:
//   - Anthropic (/v1/messages), OpenAI (chat/completions) y MuleRouter:
//     la URL tal cual.
//   - Gemini (y cualquier otro): `<url>/<model>:<endpoint>` con el endpoint
//     indicado en el body (por defecto `generateContent`).
function construirUrl(cfg: ModeloConfig, endpoint: string): URL {
  const cleanedUrl = cfg.url.endsWith('/')
    ? cfg.url.substring(0, cfg.url.length - 1)
    : cfg.url;

  const usaUrlTalCual = incluyeModeloEnCuerpo(cleanedUrl) ||
    esMuleRouter(cleanedUrl) ||
    esAnthropic(cleanedUrl);

  const resolvedUrl = usaUrlTalCual
    ? cleanedUrl
    : `${cleanedUrl}/${cfg.model}:${endpoint}`;

  return new URL(resolvedUrl);
}

// Replica de `buildHeaders`: base con Content-Type JSON y, si la autenticacion
// va por cabecera, se inyecta aqui. La clave solo se usa en memoria: no se
// registra ni se devuelve nunca.
function construirHeaders(cfg: ModeloConfig): Record<string, string> {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (cfg.paramType === 'header') {
    if (cfg.paramKey === 'key') {
      // Gemini/Google: `x-goog-api-key`.
      headers['x-goog-api-key'] = cfg.apiKey;
    } else {
      headers['Authorization'] = resolverValorParametro(
        cfg.paramKey,
        cfg.apiKey,
      );
    }
  }

  return headers;
}

// Aplica la autenticacion a la URL (query) o al cuerpo (body).
//
// Replica de `buildUri` (parte query) y de `applyAuthToBody`. Se SOBRESCRIBE
// siempre el valor: el cliente ya no tiene la clave, asi que puede mandar un
// hueco vacio (por ejemplo `key: ''` o `model: null`) que hay que reemplazar por
// el valor real.
function aplicarAutenticacion(
  cfg: ModeloConfig,
  url: URL,
  body: Record<string, unknown>,
): Record<string, unknown> {
  if (cfg.paramType === 'query') {
    const nombre = resolverNombreParametro(cfg.paramKey);
    url.searchParams.set(
      nombre,
      resolverValorParametro(cfg.paramKey, cfg.apiKey),
    );
  }

  // OpenAI-compatible: el modelo va dentro del cuerpo y la clave puede venir en
  // el propio cuerpo segun `param_type`. Se trabaja sobre una copia para no
  // mutar el objeto recibido mas de lo necesario.
  const conModelo = incluyeModeloEnCuerpo(cfg.url)
    ? { ...body, model: cfg.model }
    : { ...body };

  if (cfg.paramType !== 'body') return conModelo;

  const nombre = resolverNombreParametro(cfg.paramKey);
  return {
    ...conModelo,
    [nombre]: resolverValorParametro(cfg.paramKey, cfg.apiKey),
  };
}

// Cabeceras de la respuesta del proveedor que se reenvian. Se filtran a una
// lista blanca porque el cuerpo se entrega YA DESCOMPRIMIDO: reenviar
// `content-encoding`/`content-length` originales corromperia la respuesta, y
// `set-cookie` o las cabeceras CORS del proveedor no tienen por que llegar.
const CABECERAS_RESULTADO = [
  'content-type',
  'content-language',
  'cache-control',
  'expires',
  'pragma',
  'retry-after',
  'x-request-id',
];

Deno.serve(async (req: Request) => {
  // 1) CORS: mismo patron que `ai-assistant`, con 204 en el preflight.
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ error: 'metodo_no_permitido' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json({ error: 'config_servidor' }, 500);
  }

  // 2) Auth: la funcion se despliega con verify_jwt = true, pero ademas se
  // comprueba que hay un usuario real detras del token.
  const authHeader = req.headers.get('Authorization') ?? '';
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    const { data, error } = await userClient.auth.getUser();
    if (error || !data?.user) {
      return json({ error: 'no_autorizado' }, 401);
    }
  } catch {
    return json({ error: 'no_autorizado' }, 401);
  }

  // 3) Cuerpo de la peticion: { body, endpoint }.
  let payload: { body?: unknown; endpoint?: unknown };
  try {
    payload = await req.json();
  } catch {
    return json({ error: 'body_invalido' }, 400);
  }

  const cuerpo = payload?.body;
  if (!cuerpo || typeof cuerpo !== 'object' || Array.isArray(cuerpo)) {
    return json({ error: 'body_requerido' }, 400);
  }

  const endpoint = String(payload?.endpoint ?? 'generateContent').trim() ||
    'generateContent';
  if (!ENDPOINT_PERMITIDO.test(endpoint)) {
    return json({ error: 'endpoint_invalido' }, 400);
  }

  // 4) Config del proveedor con el cliente `service_role` (la tabla no es
  // legible por el usuario).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const cfg = await leerConfigModelo(admin);
  if (!cfg || !cfg.url || !cfg.apiKey) {
    return json({ error: 'modelo_no_configurado' }, 500);
  }

  // 5) URL + autenticacion resueltas igual que en el cliente Flutter.
  let urlProveedor: URL;
  let headersProveedor: Record<string, string>;
  let cuerpoProveedor: Record<string, unknown>;
  try {
    urlProveedor = construirUrl(cfg, endpoint);
    headersProveedor = construirHeaders(cfg);
    cuerpoProveedor = aplicarAutenticacion(
      cfg,
      urlProveedor,
      cuerpo as Record<string, unknown>,
    );
  } catch (e) {
    console.error('[ai-proxy] config invalida:', mensajeError(e));
    return json({ error: 'modelo_no_configurado' }, 500);
  }

  // Se registra el destino y el modo de auth, nunca la clave.
  console.log(
    `[ai-proxy] POST ${urlProveedor.origin}${urlProveedor.pathname} ` +
      `(auth: ${cfg.paramType}/${cfg.paramKey})`,
  );

  // 6) Envio transparente.
  //
  // POR QUE NO SE RE-ARMA EL CUERPO AQUI:
  // el cliente envia el JSON especifico del proveedor ya construido (messages,
  // contents, generationConfig, system...). Si el proxy lo normalizara o
  // filtrara campos, se romperian las capacidades que hoy no se usan pero que
  // los clientes ya pueden mandar y mandaran despues: tool calling
  // (`tools`/`functionDeclarations`/`tool_choice`), `response_format`,
  // imagenes (`inline_data`/`image_url`), `safetySettings`, `thinking`, etc.
  // Reenviando el cuerpo integro y devolviendo la respuesta VERBATIM (mismo
  // status y mismo JSON) el parser del cliente —que ya soporta bloques de
  // `tool_calls`/`functionCall`— sigue funcionando sin ningun cambio, y el
  // proxy no hay que tocarlo cada vez que se anade un campo nuevo. El proxy
  // solo aporta dos cosas: la clave y el salto de CORS.
  const controller = new AbortController();
  const temporizador = setTimeout(
    () => controller.abort(),
    PROVEEDOR_TIMEOUT_MS,
  );

  let respProveedor: Response;
  try {
    respProveedor = await fetch(urlProveedor.toString(), {
      method: 'POST',
      headers: headersProveedor,
      body: JSON.stringify(cuerpoProveedor),
      signal: controller.signal,
    });
  } catch (e) {
    const abortado = e instanceof Error && e.name === 'AbortError';
    console.error(
      '[ai-proxy] proveedor:',
      abortado ? `timeout tras ${PROVEEDOR_TIMEOUT_MS} ms` : mensajeError(e),
    );
    return json(
      {
        error: abortado
          ? 'proveedor_timeout'
          : 'proveedor_no_disponible',
      },
      502,
    );
  } finally {
    clearTimeout(temporizador);
  }

  // 7) Respuesta VERBATIM. NO se fuerza 200 ni se reescribe el JSON: si el
  // proveedor devuelve 429/400/500 con su propio mensaje, el cliente debe verlo
  // igual que lo veia antes, porque su logica de reintentos depende de ello.
  let bytes: ArrayBuffer;
  try {
    bytes = await respProveedor.arrayBuffer();
  } catch (e) {
    console.error('[ai-proxy] lectura de respuesta:', mensajeError(e));
    return json({ error: 'respuesta_invalida' }, 502);
  }

  const headersRespuesta = new Headers();
  for (const nombre of CABECERAS_RESULTADO) {
    const valor = respProveedor.headers.get(nombre);
    if (valor) headersRespuesta.set(nombre, valor);
  }
  for (const [clave, valor] of Object.entries(corsHeaders)) {
    headersRespuesta.set(clave, valor);
  }

  // Un `status: 0` (p. ej. respuesta opaca) no es un status HTTP valido para
  // `Response`; se degrada a 502 en lugar de romper la funcion.
  const status = respProveedor.status >= 200 && respProveedor.status <= 599
    ? respProveedor.status
    : 502;

  return new Response(bytes, {
    status,
    statusText: respProveedor.statusText,
    headers: headersRespuesta,
  });
});

// ---------------------------------------------------------------------------
// Deploy:
//   supabase functions deploy ai-proxy
//
// Se despliega con verify_jwt = true (el cliente envia el JWT del usuario en
// `Authorization` y la publishable key en `apikey`).
// ---------------------------------------------------------------------------
