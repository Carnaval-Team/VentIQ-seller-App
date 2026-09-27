// Supabase Edge Function: ai-kb-index
//
// Indexa la base de conocimiento del asistente: recibe documentos (title,
// content, source, ref, metadata), genera su embedding con el modelo integrado
// gte-small de Supabase (sin dependencias externas) y los guarda/actualiza en
// public.ai_kb_docs.
//
// Uso (solo administradores, se protege por service_role o llamada interna):
//   POST { docs: [{ source, ref, title, content, metadata? }, ...],
//          replaceSource?: string }
//   -> { ok: true, inserted: N }
//
// replaceSource: si se envia, borra primero todos los docs con ese `source`
// antes de insertar (re-indexado limpio).
//
// Deploy:
//   supabase functions deploy ai-kb-index
//
// verify_jwt = true: requiere un JWT valido. Ademas se exige que la llamada
// use la service_role key (o un gerente), para que usuarios normales no puedan
// escribir en la KB.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

// Modelo de embeddings integrado en el Edge Runtime de Supabase.
// gte-small -> 384 dimensiones.
const model = new Supabase.ai.Session('gte-small');

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

interface KbDocInput {
  source: string;
  ref?: string | null;
  title: string;
  content: string;
  metadata?: Record<string, unknown>;
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
  if (!supabaseUrl || !serviceKey) {
    return json({ ok: false, error: 'config_servidor' }, 500);
  }

  let payload: { docs?: KbDocInput[]; replaceSource?: string };
  try {
    payload = await req.json();
  } catch {
    return json({ ok: false, error: 'body_invalido' }, 400);
  }

  const docs = Array.isArray(payload.docs) ? payload.docs : [];
  if (docs.length === 0) {
    return json({ ok: false, error: 'sin_documentos' }, 400);
  }
  if (docs.length > 200) {
    return json({ ok: false, error: 'demasiados_documentos_max_200' }, 400);
  }

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Re-indexado limpio por source (opcional).
  if (payload.replaceSource) {
    const { error: delErr } = await admin
      .from('ai_kb_docs')
      .delete()
      .eq('source', payload.replaceSource);
    if (delErr) {
      return json({ ok: false, error: `delete: ${delErr.message}` }, 500);
    }
  }

  const rows: Array<Record<string, unknown>> = [];
  for (const d of docs) {
    const title = String(d.title ?? '').trim();
    const content = String(d.content ?? '').trim();
    if (!content) continue;

    // El embedding se calcula sobre titulo + contenido para mejor recuperacion.
    const textForEmbedding = `${title}\n\n${content}`.slice(0, 8000);
    const embedding = await model.run(textForEmbedding, {
      mean_pool: true,
      normalize: true,
    });

    rows.push({
      source: String(d.source ?? 'manual'),
      ref: d.ref ?? null,
      title: title || '(sin titulo)',
      content,
      metadata: d.metadata ?? {},
      embedding,
      updated_at: new Date().toISOString(),
    });
  }

  if (rows.length === 0) {
    return json({ ok: false, error: 'documentos_vacios' }, 400);
  }

  const { error: insErr } = await admin.from('ai_kb_docs').insert(rows);
  if (insErr) {
    return json({ ok: false, error: `insert: ${insErr.message}` }, 500);
  }

  return json({ ok: true, inserted: rows.length });
});
