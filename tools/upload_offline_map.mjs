#!/usr/bin/env node
// Sube un .mbtiles al bucket `muevete` de Supabase Storage sin cargarlo en
// memoria (streaming PUT). Es el plan B de `-Upload` del script de PowerShell,
// que usa curl.exe: en algunos equipos schannel falla con
// `SEC_E_NO_CREDENTIALS` y la subida muere sin explicación.
//
// Uso:
//   $env:SUPABASE_SERVICE_ROLE_KEY = "eyJ..."
//   node tools/upload_offline_map.mjs dist/cuba-detalle.mbtiles
//   node tools/upload_offline_map.mjs dist/cuba-detalle.mbtiles maps/cuba-detalle.mbtiles
//
// Variables:
//   SUPABASE_URL                 (default: producción)
//   SUPABASE_SERVICE_ROLE_KEY    obligatoria
//   SUPABASE_BUCKET              (default: muevete)

import { createReadStream, statSync } from 'node:fs';
import { request } from 'node:https';
import { basename } from 'node:path';

const file = process.argv[2];
const remotePath = process.argv[3] ?? `maps/${basename(file ?? '')}`;
const baseUrl = process.env.SUPABASE_URL ?? 'https://vsieeihstajlrdvpuooh.supabase.co';
const bucket = process.env.SUPABASE_BUCKET ?? 'muevete';
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!file) {
  console.error('Falta la ruta del .mbtiles.');
  process.exit(2);
}
if (!key) {
  console.error('Falta SUPABASE_SERVICE_ROLE_KEY en el entorno.');
  process.exit(2);
}

let size;
try {
  size = statSync(file).size;
} catch {
  console.error(`No existe el archivo: ${file}`);
  process.exit(2);
}
if (size < 1024) {
  console.error(`${file} pesa ${size} bytes: eso no es un .mbtiles.`);
  process.exit(2);
}

const url = new URL(`/storage/v1/object/${bucket}/${remotePath}`, baseUrl);
console.log(`Subiendo ${file}`);
console.log(`  destino : ${baseUrl} · ${bucket}/${remotePath}`);
console.log(`  tamano  : ${(size / 1048576).toFixed(1)} MB`);

const started = Date.now();
let lastPct = -1;
let uploaded = 0;

const req = request(
  url,
  {
    method: 'PUT',
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      'x-upsert': 'true',
      'Content-Type': 'application/octet-stream',
      'Content-Length': size,
      'Cache-Control': 'max-age=3600',
    },
  },
  (res) => {
    let body = '';
    res.setEncoding('utf8');
    res.on('data', (chunk) => {
      if (body.length < 8192) body += chunk;
    });
    res.on('end', () => {
      const secs = ((Date.now() - started) / 1000).toFixed(0);
      if (res.statusCode === 200 || res.statusCode === 201) {
        const avg = (size / 1048576 / Math.max(1, secs)).toFixed(2);
        console.log(`\nSubido en ${secs}s (${avg} MB/s).`);
        console.log(`  objeto  : ${bucket}/${remotePath}`);
        console.log(`  URL     : ${baseUrl}/storage/v1/object/public/${bucket}/${remotePath}`);
        process.exit(0);
      }
      console.error(`\nFallo ${res.statusCode}: ${body || '(sin cuerpo)'}`);
      process.exit(1);
    });
  },
);

req.setTimeout(0);
req.on('error', (err) => {
  console.error(`\nError de red: ${err.message}`);
  process.exit(1);
});

const stream = createReadStream(file);
stream.on('data', (chunk) => {
  uploaded += chunk.length;
  const pct = Math.floor((uploaded / size) * 100);
  if (pct >= lastPct + 10 || pct === 100) {
    lastPct = pct;
    console.log(`  ${String(pct).padStart(3)}%  ${(uploaded / 1048576).toFixed(0)} MB`);
  }
});
stream.on('error', (err) => {
  console.error(`Error leyendo ${file}: ${err.message}`);
  req.destroy();
  process.exit(1);
});
stream.pipe(req);