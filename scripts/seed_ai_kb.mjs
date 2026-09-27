// Seed de la base de conocimiento del asistente (rama newa).
// Lee el knowledge JSON de la app + project_docs de la BD y los envia al
// edge function ai-kb-index para generar embeddings e insertarlos en ai_kb_docs.
//
// Uso:
//   node scripts/seed_ai_kb.mjs
//
// Requiere: SERVICE_ROLE_KEY y URL de la rama newa (hardcode abajo, es entorno de test).

import fs from 'node:fs';
import path from 'node:path';

const NEWA_URL = 'https://qhprswhhfasrikhawjoz.supabase.co';
const SERVICE_ROLE =
  process.env.NEWA_SERVICE_ROLE ??
  '__PONER_SERVICE_ROLE__';

const KB_JSON = path.resolve(
  'ventiq_admin_app/assets/ai_assistant_knowledge.json',
);

function chunksFromKnowledge(kb) {
  const docs = [];

  // Modulos y sus features -> un chunk por feature (how-to).
  const modules = kb.modules ?? {};
  for (const [modKey, mod] of Object.entries(modules)) {
    const modName = mod.name ?? modKey;
    const routes = mod.routes ?? {};
    const routesTxt = Object.entries(routes)
      .map(([k, v]) => `${k}: ${v}`)
      .join(', ');

    docs.push({
      source: 'knowledge_json',
      ref: `modulo:${modKey}`,
      title: `Modulo: ${modName}`,
      content:
        `${mod.description ?? ''}\nRutas disponibles: ${routesTxt}`.trim(),
      metadata: { modulo: modKey, routes },
    });

    for (const f of mod.features ?? []) {
      const steps = Array.isArray(f.steps)
        ? f.steps.map((s, i) => `${i + 1}. ${s}`).join('\n')
        : '';
      const tips = Array.isArray(f.tips)
        ? `\nConsejos:\n- ${f.tips.join('\n- ')}`
        : '';
      docs.push({
        source: 'knowledge_json',
        ref: `feature:${modKey}:${f.id ?? f.name}`,
        title: `${modName} - ${f.name ?? ''}`.trim(),
        content: `Como ${f.name ?? ''} (${modName}):\n${steps}${tips}\n` +
          (f.route ? `Pantalla: ${f.route}` : ''),
        metadata: { modulo: modKey, route: f.route ?? null },
      });
    }
  }

  // FAQs.
  for (const faq of kb.faqs ?? []) {
    docs.push({
      source: 'knowledge_json',
      ref: `faq:${faq.question}`,
      title: `FAQ: ${faq.question}`,
      content: `Pregunta: ${faq.question}\nRespuesta: ${faq.answer}` +
        (faq.route ? `\nPantalla: ${faq.route}` : ''),
      metadata: { roles: faq.roles ?? [], route: faq.route ?? null },
    });
  }

  // Glosario.
  for (const [k, item] of Object.entries(kb.glossary ?? {})) {
    docs.push({
      source: 'knowledge_json',
      ref: `glosario:${k}`,
      title: `Glosario: ${item.term ?? k}`,
      content: `${item.term ?? k}: ${item.definition ?? ''}`,
      metadata: { termino: k },
    });
  }

  // Descripciones de rol.
  for (const [k, item] of Object.entries(kb.role_descriptions ?? {})) {
    docs.push({
      source: 'knowledge_json',
      ref: `rol:${k}`,
      title: `Rol: ${k}`,
      content: `${item.description ?? ''}`,
      metadata: { rol: k },
    });
  }

  return docs.filter((d) => (d.content ?? '').trim().length > 0);
}

// Trocea texto largo en chunks de ~1200 chars por parrafos.
function splitLongText(text, maxLen = 1200) {
  const paras = text.split(/\n\s*\n/);
  const chunks = [];
  let buf = '';
  for (const p of paras) {
    if ((buf + '\n\n' + p).length > maxLen && buf) {
      chunks.push(buf.trim());
      buf = p;
    } else {
      buf = buf ? `${buf}\n\n${p}` : p;
    }
  }
  if (buf.trim()) chunks.push(buf.trim());
  return chunks;
}

async function fetchProjectDocs() {
  const res = await fetch(`${NEWA_URL}/rest/v1/project_docs?select=id,content`, {
    headers: {
      apikey: SERVICE_ROLE,
      Authorization: `Bearer ${SERVICE_ROLE}`,
    },
  });
  if (!res.ok) {
    console.warn('No se pudieron leer project_docs:', res.status);
    return [];
  }
  const rows = await res.json();
  const docs = [];
  for (const row of rows) {
    const parts = splitLongText(String(row.content ?? ''));
    parts.forEach((c, i) => {
      docs.push({
        source: 'project_docs',
        ref: `project_docs:${row.id}:${i}`,
        title: `Documentacion del proyecto (parte ${i + 1})`,
        content: c,
        metadata: { doc_id: row.id, chunk: i },
      });
    });
  }
  return docs;
}

async function indexBatch(docs, replaceSource) {
  const res = await fetch(`${NEWA_URL}/functions/v1/ai-kb-index`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${SERVICE_ROLE}`,
    },
    body: JSON.stringify({ docs, replaceSource }),
  });
  const txt = await res.text();
  if (!res.ok) {
    throw new Error(`ai-kb-index ${res.status}: ${txt}`);
  }
  return JSON.parse(txt);
}

async function main() {
  if (SERVICE_ROLE.startsWith('__')) {
    console.error('Falta NEWA_SERVICE_ROLE');
    process.exit(1);
  }

  const kb = JSON.parse(fs.readFileSync(KB_JSON, 'utf8'));
  const kbDocs = chunksFromKnowledge(kb);
  console.log(`knowledge_json -> ${kbDocs.length} chunks`);

  const pdDocs = await fetchProjectDocs();
  console.log(`project_docs -> ${pdDocs.length} chunks`);

  // Indexar por lotes pequeños (el modelo de embeddings corre en el edge y
  // procesar muchos a la vez agota los recursos de compute del worker).
  const batchSize = 5;
  let total = 0;

  // knowledge_json (replace)
  for (let i = 0; i < kbDocs.length; i += batchSize) {
    const batch = kbDocs.slice(i, i + batchSize);
    const r = await indexBatch(batch, i === 0 ? 'knowledge_json' : undefined);
    total += r.inserted ?? 0;
    console.log(`  knowledge_json lote ${i / batchSize + 1}: +${r.inserted}`);
  }

  // project_docs (replace)
  for (let i = 0; i < pdDocs.length; i += batchSize) {
    const batch = pdDocs.slice(i, i + batchSize);
    const r = await indexBatch(batch, i === 0 ? 'project_docs' : undefined);
    total += r.inserted ?? 0;
    console.log(`  project_docs lote ${i / batchSize + 1}: +${r.inserted}`);
  }

  console.log(`\nTotal indexado: ${total} chunks`);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
