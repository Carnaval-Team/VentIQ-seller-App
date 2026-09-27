// Seed de la base de conocimiento del asistente -> PRODUCCION.
//
// Igual que seed_ai_kb.mjs (rama newa) pero apuntando al proyecto de produccion
// y autenticando con la anon key (publica). La edge function ai-kb-index tiene
// verify_jwt=true: la anon key es un JWT valido y sirve para pasar ese control;
// la insercion en ai_kb_docs la hace la propia funcion con su service_role.
//
// Uso:
//   node scripts/seed_ai_kb_prod.mjs
//   (opcional) SEED_URL=... SEED_KEY=... node scripts/seed_ai_kb_prod.mjs

import fs from 'node:fs';
import path from 'node:path';

const PROD_URL = process.env.SEED_URL ?? 'https://vsieeihstajlrdvpuooh.supabase.co';
// anon key (publica, la misma que usa la app Flutter).
const KEY =
  process.env.SEED_KEY ??
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZzaWVlaWhzdGFqbHJkdnB1b29oIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ1MzIyMDYsImV4cCI6MjA3MDEwODIwNn0.ZQmME9zoNTd77WwblxosRv5nnyMTWN8pKkDA6UMKcO4';

const KB_JSON = path.resolve('ventiq_admin_app/assets/ai_assistant_knowledge.json');

function chunksFromKnowledge(kb) {
  const docs = [];
  const modules = kb.modules ?? {};
  for (const [modKey, mod] of Object.entries(modules)) {
    const modName = mod.name ?? modKey;
    const routes = mod.routes ?? {};
    const routesTxt = Object.entries(routes).map(([k, v]) => `${k}: ${v}`).join(', ');
    docs.push({
      source: 'knowledge_json',
      ref: `modulo:${modKey}`,
      title: `Modulo: ${modName}`,
      content: `${mod.description ?? ''}\nRutas disponibles: ${routesTxt}`.trim(),
      metadata: { modulo: modKey, routes },
    });
    for (const f of mod.features ?? []) {
      const steps = Array.isArray(f.steps)
        ? f.steps.map((s, i) => `${i + 1}. ${s}`).join('\n') : '';
      const tips = Array.isArray(f.tips) ? `\nConsejos:\n- ${f.tips.join('\n- ')}` : '';
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
  for (const [k, item] of Object.entries(kb.glossary ?? {})) {
    docs.push({
      source: 'knowledge_json',
      ref: `glosario:${k}`,
      title: `Glosario: ${item.term ?? k}`,
      content: `${item.term ?? k}: ${item.definition ?? ''}`,
      metadata: { termino: k },
    });
  }
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

function splitLongText(text, maxLen = 1200) {
  const paras = text.split(/\n\s*\n/);
  const chunks = [];
  let buf = '';
  for (const p of paras) {
    if ((buf + '\n\n' + p).length > maxLen && buf) { chunks.push(buf.trim()); buf = p; }
    else { buf = buf ? `${buf}\n\n${p}` : p; }
  }
  if (buf.trim()) chunks.push(buf.trim());
  return chunks;
}

async function fetchProjectDocs() {
  const res = await fetch(`${PROD_URL}/rest/v1/project_docs?select=id,content`, {
    headers: { apikey: KEY, Authorization: `Bearer ${KEY}` },
  });
  if (!res.ok) {
    console.warn('No se pudieron leer project_docs por REST:', res.status, '- se omite esa fuente');
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
  const res = await fetch(`${PROD_URL}/functions/v1/ai-kb-index`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${KEY}`, apikey: KEY },
    body: JSON.stringify({ docs, replaceSource }),
  });
  const txt = await res.text();
  if (!res.ok) throw new Error(`ai-kb-index ${res.status}: ${txt}`);
  return JSON.parse(txt);
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// Indexa 1 doc con reintentos. project_docs tiene chunks grandes (~1000-1200
// chars) y el modelo de embeddings corre en el edge worker; enviarlos de a
// varios dispara WORKER_RESOURCE_LIMIT (546). De 1 en 1 con delay lo evita.
async function indexOneWithRetry(doc, replaceSource, maxRetries = 4) {
  let attempt = 0;
  for (;;) {
    try {
      return await indexBatch([doc], replaceSource);
    } catch (e) {
      attempt++;
      const msg = String(e);
      const recuperable = /546|WORKER_RESOURCE_LIMIT|429|5\d\d/.test(msg);
      if (attempt > maxRetries || !recuperable) throw e;
      const wait = 1500 * attempt;
      console.log(`    reintento ${attempt} tras error (${msg.slice(0, 60)}...), espero ${wait}ms`);
      await sleep(wait);
    }
  }
}

async function main() {
  console.log('Target:', PROD_URL);
  const kb = JSON.parse(fs.readFileSync(KB_JSON, 'utf8'));
  const kbDocs = chunksFromKnowledge(kb);
  console.log(`knowledge_json -> ${kbDocs.length} chunks`);
  const pdDocs = await fetchProjectDocs();
  console.log(`project_docs -> ${pdDocs.length} chunks`);

  const batchSize = 5;
  let total = 0;
  for (let i = 0; i < kbDocs.length; i += batchSize) {
    const batch = kbDocs.slice(i, i + batchSize);
    const r = await indexBatch(batch, i === 0 ? 'knowledge_json' : undefined);
    total += r.inserted ?? 0;
    console.log(`  knowledge_json lote ${i / batchSize + 1}: +${r.inserted}`);
  }
  for (let i = 0; i < pdDocs.length; i++) {
    const replace = i === 0 ? 'project_docs' : undefined;
    const r = await indexOneWithRetry(pdDocs[i], replace);
    total += r.inserted ?? 0;
    console.log(`  project_docs ${i + 1}/${pdDocs.length}: +${r.inserted}`);
    await sleep(1500);
  }
  console.log(`\nTotal indexado: ${total} chunks`);
}

main().catch((e) => { console.error(e); process.exit(1); });
