// Invocación de una Edge Function DESDE otra Edge Function.
//
// Se usa para "encadenar" workers: un envío largo no cabe en el techo de
// wall-clock (~400s) de un solo worker, así que cada invocación procesa un
// trozo y encola el siguiente con un worker nuevo y 400s frescos.
//
// La llamada tiene dos rutas porque `functions.invoke` falla en silencio en
// algunos escenarios de background task:
//   1. `admin.functions.invoke` — ruta normal.
//   2. `fetch` manual al endpoint público con la service_role key.
//
// Regla anti-duplicados: si la ruta 1 devolvió un HTTP 4xx, la función
// destino RECHAZÓ la request de forma determinista (validación, sesión
// desconectada, sin permisos) — reintentar por fetch daría el mismo 4xx, así
// que no se reintenta. Sólo se cae al fallback cuando no hubo respuesta o
// cuando fue 5xx / límite de workers, casos en los que el trabajo casi con
// seguridad no arrancó.
import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

export interface InvokeOutcome {
  /** ¿Quedó encolado? */
  ok: boolean;
  via: "invoke" | "fetch" | "none";
  status?: number;
  error?: string;
}

/** Timeout de la propia llamada de encolado (la función destino responde
 *  enseguida con `queued`; si tarda más, algo va mal en el gateway). */
const ENQUEUE_TIMEOUT_MS = 25_000;

export async function invokeEdgeFunction(
  admin: SupabaseClient,
  fnName: string,
  // Objeto JSON: `functions.invoke` no acepta `unknown` como body y todos los
  // encolados de la cadena mandan un objeto plano.
  payload: Record<string, unknown>,
  logTag = fnName,
): Promise<InvokeOutcome> {
  // ── Ruta 1: functions.invoke ──────────────────────────────────────────
  let statusInvoke: number | undefined;
  let errorInvoke: string | undefined;
  try {
    const { error } = await admin.functions.invoke(fnName, { body: payload });
    if (!error) {
      console.log(`[${logTag}] → ${fnName} encolado (invoke)`);
      return { ok: true, via: "invoke" };
    }
    statusInvoke = (error as any)?.context?.status;
    errorInvoke = error.message ?? String(error);
  } catch (e) {
    errorInvoke = (e as Error).message ?? String(e);
  }

  // Un 4xx (salvo 429) es un rechazo determinista: el fallback daría igual.
  if (
    typeof statusInvoke === "number" && statusInvoke >= 400 &&
    statusInvoke < 500 && statusInvoke !== 429
  ) {
    console.error(
      `[${logTag}] → ${fnName} RECHAZADO con HTTP ${statusInvoke}: ` +
        `${errorInvoke}. No se reintenta (fallo determinista).`,
    );
    return { ok: false, via: "invoke", status: statusInvoke, error: errorInvoke };
  }

  console.error(
    `[${logTag}] → ${fnName} invoke falló (status=${statusInvoke ?? "n/a"}): ` +
      `${errorInvoke} — probando fallback fetch`,
  );

  // ── Ruta 2: fetch manual ──────────────────────────────────────────────
  const baseUrl = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!baseUrl || !key) {
    console.error(
      `[${logTag}] CADENA ROTA: invoke falló y faltan SUPABASE_URL / ` +
        `SUPABASE_SERVICE_ROLE_KEY para el fallback.`,
    );
    return { ok: false, via: "none", error: errorInvoke ?? "sin credenciales" };
  }

  const endpoint = `${baseUrl.replace(/\/$/, "")}/functions/v1/${fnName}`;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), ENQUEUE_TIMEOUT_MS);
  try {
    const res = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${key}`,
        "apikey": key,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
      signal: ctrl.signal,
    });
    if (!res.ok) {
      const detalle = await res.text().catch(() => "");
      console.error(
        `[${logTag}] CADENA ROTA: ${fnName} devolvió HTTP ${res.status}: ` +
          detalle.slice(0, 300),
      );
      return { ok: false, via: "fetch", status: res.status, error: detalle.slice(0, 300) };
    }
    console.log(`[${logTag}] → ${fnName} encolado (fetch, HTTP ${res.status})`);
    return { ok: true, via: "fetch", status: res.status };
  } catch (e) {
    console.error(
      `[${logTag}] CADENA ROTA: fallo al encolar ${fnName}: ` +
        `${(e as Error).message ?? e}`,
    );
    return { ok: false, via: "fetch", error: (e as Error).message ?? String(e) };
  } finally {
    clearTimeout(timer);
  }
}
