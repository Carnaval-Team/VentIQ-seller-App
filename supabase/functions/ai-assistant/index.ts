// Supabase Edge Function: ai-assistant
//
// Asistente de ayuda para la app de administracion (Inventtia Gestion).
//
// Que hace:
//   1. Recibe la pregunta del usuario (con su JWT, verify_jwt=true).
//   2. Calcula el embedding de la pregunta con gte-small (integrado).
//   3. Recupera los chunks mas relevantes de la KB (RPC match_ai_kb, solo lectura).
//   4. Arma un prompt con ese contexto + el rol del usuario y llama al LLM
//      (config leida de config_asistant_model; formato Anthropic Messages API).
//   5. Devuelve { message, suggested_route, is_navigable }.
//
// SEGURIDAD (requisito del usuario):
//   - El asistente SOLO explica como hacer cosas y puede leer la KB.
//   - NO ejecuta SQL ni acciones. No escribe nada.
//   - No expone datos de otras tiendas: no consulta datos de negocio en esta
//     version, solo conocimiento de ayuda (KB) + el rol del usuario.
//
// Deploy:
//   supabase functions deploy ai-assistant

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const embedModel = new Supabase.ai.Session('gte-small');

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

interface ChatTurn {
  role: 'user' | 'assistant';
  content: string;
}

interface ModeloConfig {
  apiKey: string;
  model: string;
  url: string;
  paramType: string; // header | body | query
  paramKey: string; // bearer | basic | key
}

// Lee la fila mas reciente de config_asistant_model.
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

// Determina el rol del usuario a partir de sus tablas (respeta RLS via userClient).
async function resolverRolUsuario(
  userClient: ReturnType<typeof createClient>,
): Promise<string> {
  try {
    const { data: userData } = await userClient.auth.getUser();
    const uid = userData?.user?.id;
    if (!uid) return 'usuario';

    // Se comprueba en orden de privilegio. Solo lecturas sencillas.
    const checks: Array<[string, string]> = [
      ['app_dat_gerente', 'gerente'],
      ['app_dat_supervisor', 'supervisor'],
      ['app_dat_almacenero', 'almacenero'],
      ['app_dat_vendedor', 'vendedor'],
    ];
    for (const [tabla, rol] of checks) {
      const { count } = await userClient
        .from(tabla)
        .select('*', { count: 'exact', head: true })
        .eq('uuid', uid);
      if ((count ?? 0) > 0) return rol;
    }
  } catch (_) {
    // Silencioso: el rol es solo contexto.
  }
  return 'usuario';
}

// Construye el bloque de contexto a partir de los chunks recuperados.
function construirContexto(
  matches: Array<{ title?: string; content?: string; similarity?: number }>,
): string {
  if (!matches || matches.length === 0) {
    return '(No se encontro informacion especifica en la base de conocimiento.)';
  }
  return matches
    .map((m, i) => {
      const t = String(m.title ?? '').trim();
      const c = String(m.content ?? '').trim();
      return `[Fragmento ${i + 1}${t ? ` - ${t}` : ''}]\n${c}`;
    })
    .join('\n\n');
}

interface RespuestaAsistente {
  message: string;
  suggested_route: string | null;
  is_navigable: boolean;
}

// Llama al LLM (formato Anthropic Messages API) y parsea la respuesta JSON.
async function invocarLlm(opts: {
  cfg: ModeloConfig;
  question: string;
  history: ChatTurn[];
  contexto: string;
  rol: string;
}): Promise<RespuestaAsistente> {
  const { cfg, question, history, contexto, rol } = opts;

  const systemPrompt =
    `Eres el asistente de ayuda de "Inventtia Gestion", una app de gestion de ` +
    `inventarios, ventas, finanzas y clientes para negocios retail.\n\n` +
    `REGLAS:\n` +
    `1. Responde SIEMPRE en espanol, claro y amigable.\n` +
    `2. Explica COMO hacer las cosas paso a paso, basandote en el CONTEXTO.\n` +
    `3. Solo describes acciones; NUNCA ejecutas ni modificas datos.\n` +
    `4. Adapta la respuesta al rol del usuario (rol actual: ${rol}).\n` +
    `5. Si no sabes algo o no esta en el contexto, dilo con honestidad y ` +
    `sugiere donde podria estar, sin inventar.\n` +
    `6. Se conciso pero completo.\n` +
    `7. Si la respuesta implica ir a una pantalla, incluye su ruta en ` +
    `suggested_route (ej: "/products", "/inventory", "/sales", "/customers", ` +
    `"/financial-dashboard", "/warehouse", "/promotions", "/suppliers").\n\n` +
    `CONTEXTO (base de conocimiento de la app):\n${contexto}\n\n` +
    `Responde EXCLUSIVAMENTE en JSON valido, sin markdown, con este formato:\n` +
    `{"message": "<respuesta>", "suggested_route": "<ruta o null>", "is_navigable": <true|false>}`;

  // Mensajes en formato Anthropic: system aparte, messages = historial + pregunta.
  const messages = [
    ...history.map((t) => ({ role: t.role, content: t.content })),
    { role: 'user', content: question },
  ];

  const isAnthropic = cfg.url.toLowerCase().includes('/v1/messages');
  const isChatCompletions = cfg.url
    .toLowerCase()
    .includes('chat/completions');

  let requestBody: Record<string, unknown>;
  if (isAnthropic) {
    // max_tokens alto: algunos modelos (opus con "thinking") gastan tokens de
    // razonamiento antes del texto final; si es bajo, el JSON se corta.
    requestBody = {
      model: cfg.model,
      max_tokens: 4096,
      system: systemPrompt,
      messages,
    };
  } else if (isChatCompletions) {
    requestBody = {
      model: cfg.model,
      temperature: 0.3,
      max_tokens: 4096,
      messages: [{ role: 'system', content: systemPrompt }, ...messages],
    };
  } else {
    // Gemini generateContent u otros: fallback simple.
    requestBody = {
      contents: [
        {
          role: 'user',
          parts: [{ text: `${systemPrompt}\n\nPregunta: ${question}` }],
        },
      ],
      generationConfig: {
        temperature: 0.3,
        maxOutputTokens: 4096,
      },
    };
  }

  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };
  if (cfg.paramType === 'header') {
    if (cfg.paramKey === 'bearer') {
      headers['Authorization'] = `Bearer ${cfg.apiKey}`;
    } else if (cfg.paramKey === 'basic') {
      headers['Authorization'] = `Basic ${cfg.apiKey}`;
    } else {
      headers['key'] = cfg.apiKey;
    }
    // Anthropic tambien acepta x-api-key; justwoker usa Bearer, ya cubierto.
  }

  const resp = await fetch(cfg.url, {
    method: 'POST',
    headers,
    body: JSON.stringify(requestBody),
  });

  if (!resp.ok) {
    const detalle = await resp.text().catch(() => '');
    throw new Error(`LLM status ${resp.status}: ${detalle.slice(0, 300)}`);
  }

  const data = await resp.json();
  const texto = extraerTexto(data);
  if (!texto) {
    // Ayuda a diagnosticar formatos de respuesta inesperados.
    console.error(
      '[ai-assistant] respuesta LLM sin texto:',
      JSON.stringify(data).slice(0, 800),
    );
  }
  return parsearRespuesta(texto);
}

// Extrae el texto de la respuesta segun el proveedor.
function extraerTexto(data: unknown): string {
  if (!data || typeof data !== 'object') return '';
  const d = data as Record<string, unknown>;

  // Anthropic: { content: [{ type: 'text', text: '...' }, ...] }
  // Puede incluir bloques 'thinking' antes del texto: buscamos el primer
  // bloque de tipo 'text' (o concatenamos todos los text).
  const content = d.content;
  if (Array.isArray(content) && content.length > 0) {
    const textos = content
      .filter(
        (b) =>
          b &&
          typeof b === 'object' &&
          (b as Record<string, unknown>).type === 'text' &&
          typeof (b as Record<string, unknown>).text === 'string',
      )
      .map((b) => String((b as Record<string, unknown>).text));
    if (textos.length > 0) return textos.join('\n');
  }

  // OpenAI/chat.completions: { choices: [{ message: { content } }] }
  const choices = d.choices;
  if (Array.isArray(choices) && choices.length > 0) {
    const msg = (choices[0] as Record<string, unknown>).message as
      | Record<string, unknown>
      | undefined;
    if (msg && typeof msg.content === 'string') return msg.content;
  }

  // Gemini: { candidates: [{ content: { parts: [{ text }] } }] }
  const candidates = d.candidates;
  if (Array.isArray(candidates) && candidates.length > 0) {
    const cont = (candidates[0] as Record<string, unknown>).content as
      | Record<string, unknown>
      | undefined;
    const parts = cont?.parts;
    if (Array.isArray(parts) && parts.length > 0) {
      const t = (parts[0] as Record<string, unknown>).text;
      if (typeof t === 'string') return t;
    }
  }

  return '';
}

// Extrae y valida el JSON de la respuesta del modelo.
function parsearRespuesta(texto: string): RespuestaAsistente {
  const fallback: RespuestaAsistente = {
    message: texto.trim() ||
      'No pude generar una respuesta. Intenta reformular tu pregunta.',
    suggested_route: null,
    is_navigable: false,
  };

  const start = texto.indexOf('{');
  const end = texto.lastIndexOf('}');
  if (start === -1 || end === -1 || end <= start) {
    return fallback;
  }
  try {
    const parsed = JSON.parse(texto.slice(start, end + 1));
    const message = String(parsed.message ?? '').trim();
    if (!message) return fallback;
    let route: string | null = parsed.suggested_route ?? null;
    if (typeof route !== 'string' || !route.startsWith('/')) route = null;
    return {
      message,
      suggested_route: route,
      is_navigable: route != null && parsed.is_navigable === true,
    };
  } catch (_) {
    return fallback;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return json({ ok: false, error: 'metodo_no_permitido' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY');
  if (!supabaseUrl || !serviceKey || !anonKey) {
    return json({ ok: false, error: 'config_servidor' }, 500);
  }

  // JWT del usuario (verify_jwt ya valido que exista y sea correcto).
  const authHeader = req.headers.get('Authorization') ?? '';

  let body: {
    question?: string;
    history?: ChatTurn[];
  };
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: 'body_invalido' }, 400);
  }

  const question = String(body.question ?? '').trim();
  if (question.length < 3) {
    return json({ ok: false, error: 'pregunta_muy_corta' }, 400);
  }
  if (question.length > 2000) {
    return json({ ok: false, error: 'pregunta_muy_larga' }, 400);
  }

  const history = Array.isArray(body.history)
    ? body.history
        .filter(
          (t) =>
            t &&
            (t.role === 'user' || t.role === 'assistant') &&
            typeof t.content === 'string',
        )
        .slice(-8)
    : [];

  // Cliente con el JWT del usuario: para leer su rol respetando RLS.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Cliente admin: solo para leer KB y config (nunca se expone al cliente).
  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // 1) Rol del usuario (contexto, no expone datos de negocio).
  const rol = await resolverRolUsuario(userClient);

  // 2) Embedding de la pregunta.
  let queryEmbedding: number[];
  try {
    queryEmbedding = (await embedModel.run(question, {
      mean_pool: true,
      normalize: true,
    })) as number[];
  } catch (e) {
    console.error('[ai-assistant] embedding:', e);
    return json({ ok: false, error: 'error_embedding' }, 500);
  }

  // 3) Recuperar contexto relevante (solo lectura).
  const { data: matches, error: matchErr } = await admin.rpc('match_ai_kb', {
    query_embedding: queryEmbedding,
    match_count: 6,
    min_similarity: 0.2,
  });
  if (matchErr) {
    console.error('[ai-assistant] match_ai_kb:', matchErr.message);
  }

  const contexto = construirContexto(
    Array.isArray(matches) ? matches : [],
  );

  // 4) Config del modelo LLM.
  const cfg = await leerConfigModelo(admin);
  if (!cfg) {
    return json(
      { ok: false, error: 'modelo_no_configurado' },
      500,
    );
  }

  // 5) Llamar al LLM.
  try {
    const respuesta = await invocarLlm({
      cfg,
      question,
      history,
      contexto,
      rol,
    });
    return json({ ok: true, ...respuesta });
  } catch (e) {
    console.error('[ai-assistant] LLM:', e);
    return json(
      {
        ok: false,
        error: 'error_llm',
        _debug: String(e).slice(0, 500),
        message:
          'Lo siento, no pude generar una respuesta en este momento. Intenta de nuevo.',
      },
      502,
    );
  }
});
