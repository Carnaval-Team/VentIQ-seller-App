// Genera `harness.mts` a partir de la revisión CONGELADA del código real.
// Extrae bloques VERBATIM de index.ts y los envuelve en mocks, más el runner
// de escenarios de `runner.js`. Se ejecuta con:
//   node --experimental-strip-types harness.mts
import { createHash } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";

const SRC = new URL("./snapshot/index.ts", import.meta.url);
const EXPECTED = "814A93D14D04D4DE6F4651360E99F679388BE5C0F70B21283D119FEF4EB7F58C";

const src = readFileSync(SRC, "utf8");
const hash = createHash("sha256").update(src).digest("hex").toUpperCase();
if (hash !== EXPECTED) {
  console.error(`HASH INESPERADO: ${hash} != ${EXPECTED}`);
  process.exit(2);
}

const lineOf = (mark) => src.slice(0, src.indexOf(mark)).split("\n").length;
function sliceHasta(inicio, fin) {
  const i = src.indexOf(inicio);
  if (i < 0) throw new Error(`marca no encontrada: ${inicio}`);
  const j = src.indexOf(fin, i);
  if (j < 0) throw new Error(`fin no encontrado: ${fin}`);
  return src.slice(i, j + fin.length);
}

const LOOP_START = "  for (let cursor = 0; cursor < plan.length; cursor++) {";
const loopLine = lineOf(LOOP_START);
const loop = (() => {
  const i = src.indexOf(LOOP_START);
  let depth = 0, started = false;
  for (let k = i; k < src.length; k++) {
    const c = src[k];
    if (c === "{") { depth++; started = true; }
    else if (c === "}") { depth--; if (started && depth === 0) return src.slice(i, k + 1); }
  }
  throw new Error("bucle sin cerrar");
})();

const REG_START = "    if (pares.length === 0 || chatsValidos.length === 0) return [];";
const regLine = lineOf(REG_START);
const regEndMark = "\n    return ids;\n  };";
const regBody = sliceHasta(REG_START, "\n    return ids;\n  };").replace(/\n  \};\s*$/, "");

const CLOSE_START = "  const deDestinoSaltado = remainingPares.filter((p) =>";
const closeLine = lineOf(CLOSE_START);
const closeBlock = sliceHasta(CLOSE_START, "  if (pacingAbort) {").replace(/\s*if \(pacingAbort\) \{$/, "").replace(/\s+$/, "");

const CHATS_START = "  const chatsValidos = Array.from(";
const chatsLine = lineOf(CHATS_START);
const chatsBlock = sliceHasta(CHATS_START, "    ),\n  );");

const PLAN_START = "  const plan: Par[] = [];";
const planLine = lineOf(PLAN_START);
const planBlock = sliceHasta(PLAN_START, "    }\n  }").replace(/\s+$/, "");

const RES_START = "    const ordenProd: number[] = [];";
const resLine = lineOf(RES_START);
const resBlock = sliceHasta(RES_START, "    effDestinations = Array.from(chats.values());");

const runner = readFileSync(new URL("./runner.js", import.meta.url), "utf8");

const out = `// GENERADO por build_harness.mjs — NO EDITAR A MANO.
// Fuente: ventiq_admin_app/supabase/functions/wapi-send-products/index.ts
// SHA256 verificado: ${hash}
// Bloques verbatim: chatsValidos L${chatsLine}, resume L${resLine}, plan L${planLine},
//                  registrarPendientesPares L${regLine}, bucle L${loopLine}, cierre L${closeLine}
/* eslint-disable */

type Par = { idProducto: number; chatId: string };
function clavePar(p: Par): string { return \`\${p.idProducto}|\${p.chatId}\`; }
function chunkArray<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}
const noopConsole = { error: () => {}, warn: () => {}, log: () => {} };

// ─────────────────────────── Mock de Supabase ───────────────────────────
type Fila = { id: number; id_producto: number; chat_id: string; estado: string; error_code?: string | null };
type DB = {
  filas: Fila[];
  inserts: any[][];
  updates: Array<{ patch: any; ids?: number[]; eq?: number }>;
  fallaInsert: boolean;
  nextId: number;
  pendRows: any[];
};
function nuevoDB(): DB {
  return { filas: [], inserts: [], updates: [], fallaInsert: false, nextId: 1000, pendRows: [] };
}
/** Thenable que imita la cadena de PostgREST: se puede await-ear o encadenar. */
function thenable(resultado: any) {
  const o: any = {
    in: () => o, eq: () => o, neq: () => o, order: () => o, limit: () => o,
    single: () => o, maybeSingle: () => o,
    then: (res: any, rej: any) => Promise.resolve(resultado).then(res, rej),
    catch: (rej: any) => Promise.resolve(resultado).catch(rej),
  };
  return o;
}
function mockAdmin(db: DB) {
  const cadena: any = {
    insert: (rows: any[]) => {
      db.inserts.push(rows);
      const creadas: Fila[] = db.fallaInsert ? [] : rows.map((r) => {
        const f: Fila = {
          id: db.nextId++, id_producto: r.id_producto, chat_id: r.chat_id,
          estado: r.estado, error_code: null,
        };
        db.filas.push(f);
        return f;
      });
      return {
        select: () => thenable({
          data: db.fallaInsert ? null : creadas.map((f) => ({ id: f.id, id_producto: f.id_producto, chat_id: f.chat_id })),
          error: db.fallaInsert ? { message: "insert simulado falla" } : null,
        }),
      };
    },
    select: (_cols: string) => thenable({ data: db.pendRows, error: null }),
    update: (patch: any) => ({
      in: async (_col: string, ids: number[]) => {
        db.updates.push({ patch, ids: [...ids] });
        for (const f of db.filas) if (ids.includes(f.id)) Object.assign(f, patch);
        return { error: null };
      },
      eq: async (_col: string, id: number) => {
        db.updates.push({ patch, eq: id });
        for (const f of db.filas) if (f.id === id) Object.assign(f, patch);
        return { error: null };
      },
    }),
  };
  return { from: (_t: string) => cadena };
}

// ── chatsValidos: EXTRAÍDO VERBATIM L${chatsLine} (necesita effDestinations) ──
function construirChatsValidos(effDestinations: any[]) {
${chatsBlock}
  return chatsValidos;
}

// ── plan: EXTRAÍDO VERBATIM L${planLine} ──
function construirPlan(chatsValidos: string[], effProductIds: number[], logIdPorPar: Map<string, number>, esReanudacion: boolean) {
${planBlock}
  return plan;
}

// ── REANUDAR (reconstrucción): EXTRAÍDO VERBATIM L${resLine} ──
function reconstruirDesdeLogs(pend: any[], destinations: any[]) {
  const logIdPorPar = new Map<string, number>();
  const logIdDePar = new Map<string, number>();
  let effProductIds: number[] = [];
  let effDestinations: any[] = [];
  const console = noopConsole;
${resBlock}
  return { effProductIds, effDestinations, logIdPorPar, logIdDePar };
}

// ── registrarPendientesPares: cuerpo EXTRAÍDO VERBATIM L${regLine} ──
function makeRegistrar(env: any) {
  const admin = env.admin;
  const chatsValidos: string[] = env.chatsValidos;
  const logIdDePar: Map<string, number> = env.logIdDePar;
  const idTienda = 1, idSesion = 1, idProgramacion = null, tipoEnvio = "manual";
  const console = noopConsole;
  return async function registrarPendientesPares(pares: Par[], motivo?: { code: string; message: string }): Promise<number[]> {
${regBody}
  };
}

// ── Bucle principal: EXTRAÍDO VERBATIM L${loopLine} ──
async function correrBucle(env: any) {
  const plan: Par[] = env.plan;
  const WORKER_BUDGET_MS: number = env.WORKER_BUDGET_MS;
  const ENTRE_DESTINOS_MS: number = env.ENTRE_DESTINOS_MS ?? 20_000;
  const DESTINO_FALLOS_MAX: number = 3;
  const WINDOW_SIZE: number = 25;
  const minMs: number = env.minMs ?? 0;
  const maxMs: number = env.maxMs ?? 0;
  const effProductIds: number[] = env.effProductIds;
  const posDeProducto: Map<number, number> = env.posDeProducto;
  const descartados: Set<number> = env.descartados;
  const ensureInfo = env.ensureInfo;
  const obtenerProductoListo = env.obtenerProductoListo;
  const dispatchOne = env.dispatchOne;
  const elapsed = env.elapsed;
  const reservaMensajeMs = env.reservaMensajeMs;
  const setTimeout = (fn: any, _ms: number) => globalThis.setTimeout(fn, 0);
  const console = noopConsole;

  let mensajesIntentados = 0;
  let enviados = 0;
  let fallidos = 0;
  let pendientesDeTrabajo = 0;
  let pendientesPorSesion = 0;
  let peorEnvioMs = 0;
  let ventanaFin = 0;
  let remainingPares: Par[] = [];
  let saltadosPares: Par[] = [];
  let pacingAbort: any = env.pacingAbort ?? null;
  let sessionAbort: any = env.sessionAbort ?? null;
  // Declaraciones verbatim L1849-1854 (quedan fuera del bloque del for).
  let destinoActual: string | null = plan.length > 0 ? plan[0].chatId : null;
  let fallosDelDestino = 0;
  const destinosSaltados = new Set<string>();

${loop}

  return { remainingPares, saltadosPares, pacingAbort, sessionAbort, mensajesIntentados, enviados, fallidos, pendientesDeTrabajo, pendientesPorSesion, destinosSaltados, descartados };
}

// ── Cierre: EXTRAÍDO VERBATIM L${closeLine} ──
async function correrCierre(env: any, st: any) {
  let remainingPares: Par[] = st.remainingPares;
  let saltadosPares: Par[] = st.saltadosPares;
  const destinosSaltados: Set<string> = st.destinosSaltados;
  const descartados: Set<number> = st.descartados;
  const registrarPendientesPares = env.registrarPendientesPares;
  const DESTINO_FALLOS_MAX = 3;
  const console = noopConsole;

${closeBlock}

  const continuacion = await registrarPendientesPares(remainingRegistrables);
  return { remainingPares, saltadosPares, remainingRegistrables, deDestinoSaltado, continuacion };
}

${runner}
`;
writeFileSync(new URL("./harness.mts", import.meta.url), out);
console.log(
  `harness.mts generado. hash=${hash}\n` +
  `  chatsValidos=L${chatsLine} resume=L${resLine} plan=L${planLine} registrar=L${regLine} bucle=L${loopLine} cierre=L${closeLine}`,
);