import { createClient } from "jsr:@supabase/supabase-js@2";

/**
 * flow-tasas — tasa de cambio ("el toque") del día, servida por Supabase.
 *
 * Por qué existe
 * --------------
 * El precio automático de un servicio necesita la tasa del día. Esa consulta no
 * vive en la app: vive aquí. La app solo llama a esta función y recibe la tasa
 * ya normalizada a las monedas que usa (`USD`, `EUR`, `CUP`, `MLC`).
 *
 * Cómo funciona
 * -------------
 *  1. Lee la última fila de `flow.tasa_cambio` (la caché, una fila por fecha).
 *  2. Si esa fila NO se guardó hoy (hora de La Habana), consulta el proveedor,
 *     recalcula las conversiones y hace UPSERT en la tabla.
 *  3. Devuelve la misma forma siempre, venga de caché o de la URL.
 *
 * Conversión
 * ----------
 * El proveedor publica, por moneda de origen, su valor en `CUP`, `MLC` y `USD`
 * (y a veces `null`). Cuando no hay tasa directa se cruza por CUP:
 *
 *     MLC -> EUR  =  (MLC -> CUP) / (EUR -> CUP)
 *
 * Ejemplo real: `697.62 / 925 = 0.7542`.
 *
 * Degradación
 * -----------
 * Si el proveedor falla y hay caché, se devuelve la caché (`origen: "cache"`)
 * con un aviso. Si falla y NO hay caché, se devuelve `ok: false` y la app
 * desactiva el cálculo automático (nunca inventa un factor).
 *
 * Invocación
 * ----------
 *   POST /functions/v1/flow-tasas            -> usa caché si es de hoy
 *   POST /functions/v1/flow-tasas {"forzar": true}  -> refresca siempre
 */

const FUENTE = "directoriocubano";
const URL_TASAS = "https://widgets.directoriocubano.info/api/tasas";
const MONEDAS_APP = ["USD", "EUR", "CUP", "MLC"] as const;

/** Zona horaria del negocio: el "día" de la caché es el de La Habana. */
function hoyHavana(): string {
  // `en-CA` da YYYY-MM-DD.
  return new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Havana",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).format(new Date());
}

function redondear(v: number, decimales: number): number {
  const f = 10 ** decimales;
  return Math.round(v * f) / f;
}

type TasasCrudas = Record<string, Record<string, number | null>>;

/** `tasas[origen][destino]`, positiva o null. */
function tasaCruda(
  tasas: TasasCrudas,
  origen: string,
  destino: string,
): number | null {
  const v = tasas?.[origen]?.[destino];
  return typeof v === "number" && v > 0 ? v : null;
}

/**
 * Matriz normalizada entre las monedas de la app, cruzando por CUP cuando hace
 * falta. El proveedor no publica una fila `CUP`, así que `CUP -> X` sale del
 * inverso de `X -> CUP`.
 */
export function construirConversiones(
  tasas: TasasCrudas,
): Record<string, Record<string, number>> {
  const salida: Record<string, Record<string, number>> = {};

  for (const origen of MONEDAS_APP) {
    salida[origen] = {};
    for (const destino of MONEDAS_APP) {
      if (origen === destino) {
        salida[origen][destino] = 1;
        continue;
      }

      let valor: number | null = null;

      if (origen === "CUP") {
        const inverso = tasaCruda(tasas, destino, "CUP");
        valor = inverso ? 1 / inverso : null;
      } else if (destino === "CUP") {
        valor = tasaCruda(tasas, origen, "CUP");
      } else {
        valor = tasaCruda(tasas, origen, destino);
        if (valor === null) {
          // Cruce por CUP: 1 origen = (origen->CUP) / (destino->CUP) destinos.
          const a = tasaCruda(tasas, origen, "CUP");
          const b = tasaCruda(tasas, destino, "CUP");
          if (a !== null && b !== null && b > 0) valor = a / b;
        }
      }

      if (valor !== null && Number.isFinite(valor) && valor > 0) {
        salida[origen][destino] = redondear(valor, 6);
      }
    }
  }

  return salida;
}

function json(cuerpo: unknown, status = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers":
        "authorization, x-client-info, apikey, content-type",
      "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
    },
  });
}

function filaRespuesta(
  fila: Record<string, unknown>,
  origen: "cache" | "api",
  aviso?: string,
): Record<string, unknown> {
  return {
    ok: true,
    origen,
    fuente: fila.fuente ?? FUENTE,
    fecha: fila.fecha ?? null,
    hora: fila.hora ?? null,
    actualizado: fila.actualizado ?? null,
    guardado_at: fila.updated_at ?? null,
    vigente: fila.fecha === hoyHavana(),
    tasas: fila.tasas ?? {},
    conversiones: fila.conversiones ?? {},
    monedas: MONEDAS_APP,
    ...(aviso ? { aviso } : {}),
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") {
    return json({ ok: true });
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
      Deno.env.get("SB_SECRET_KEY")!,
    { auth: { persistSession: false } },
  );

  let forzar = false;
  try {
    if (req.method === "POST") {
      const cuerpo = await req.json();
      forzar = cuerpo?.forzar === true;
    }
  } catch {
    // Sin cuerpo (o cuerpo no JSON) se usa la caché. No es un error.
  }
  if (new URL(req.url).searchParams.get("forzar") === "1") forzar = true;

  const hoy = hoyHavana();

  // 1. Caché.
  const { data: filas, error: errCache } = await supabase
    .schema("flow")
    .from("tasa_cambio")
    .select("fecha,fuente,hora,actualizado,tasas,conversiones,updated_at")
    .order("fecha", { ascending: false })
    .order("id", { ascending: false })
    .limit(1);

  // Un fallo leyendo la cache NO es fatal: la cache es una optimización. Si el
  // schema no está accesible (p. ej. falta `grant usage on schema flow to
  // service_role`, migración 65), se consulta el proveedor y se devuelven las
  // tasas igualmente, con un aviso. Antes esto devolvía 500 y el admin se
  // quedaba sin precios teniendo la tasa a un `fetch` de distancia.
  const avisoCache = errCache
    ? `No se pudo leer la cache (${errCache.message}); se consulta el proveedor.`
    : undefined;

  const cache = errCache ? null : (filas?.[0] ?? null);
  const cacheDeHoy = cache?.fecha === hoy;

  if (cache && cacheDeHoy && !forzar) {
    return json(filaRespuesta(cache, "cache"));
  }

  // 2. Refresco desde el proveedor.
  let proveedor: Record<string, unknown>;
  try {
    const res = await fetch(URL_TASAS, {
      headers: {
        Accept: "application/json",
        "User-Agent":
          "Mozilla/5.0 (compatible; GoReserva-flow-tasas/1.0; +https://inventtia.com)",
      },
      signal: AbortSignal.timeout(12000),
    });

    if (!res.ok) {
      throw new Error(`HTTP ${res.status} del proveedor de tasas`);
    }

    proveedor = await res.json();

    if (proveedor?.ok !== true || typeof proveedor?.tasas !== "object") {
      throw new Error("El proveedor devolvio una respuesta sin tasas");
    }
  } catch (e) {
    const detalle = e instanceof Error ? e.message : String(e);
    if (cache) {
      // Degradación honesta: se sirve la caché, avisando que no es de hoy.
      return json(
        filaRespuesta(
          cache,
          "cache",
          [avisoCache, `No se pudo refrescar (${detalle}).`]
            .filter(Boolean)
            .join(" "),
        ),
      );
    }
    return json(
      {
        ok: false,
        error: [avisoCache, `Sin tasas disponibles: ${detalle}`]
          .filter(Boolean)
          .join(" "),
      },
      502,
    );
  }

  const tasas = proveedor.tasas as TasasCrudas;
  const conversiones = construirConversiones(tasas);

  // `actualizado` viene como "2026-10-27 07:00:06" en hora local del proveedor.
  const actualizadoTxt =
    typeof proveedor.actualizado === "string" ? proveedor.actualizado : null;
  const fechaProveedor = actualizadoTxt
    ? actualizadoTxt.slice(0, 10)
    : hoy;
  // La caché se indexa por el día del proveedor; si su fecha no es la de hoy
  // (publica con retraso), se guarda igual y `vigente` lo delata.
  const fechaFila = /^\d{4}-\d{2}-\d{2}$/.test(fechaProveedor)
    ? fechaProveedor
    : hoy;

  const fila = {
    fecha: fechaFila,
    fuente: FUENTE,
    hora: typeof proveedor.hora === "string" ? proveedor.hora : null,
    actualizado: actualizadoTxt,
    tasas,
    conversiones,
    updated_at: new Date().toISOString(),
  };

  const { error: errUpsert } = await supabase
    .schema("flow")
    .from("tasa_cambio")
    .upsert(fila, { onConflict: "fecha,fuente" });

  if (errUpsert) {
    // La tasa SI se obtuvo: se devuelve aunque no se haya podido cachear.
    return json({
      ok: true,
      origen: "api",
      fuente: FUENTE,
      fecha: fila.fecha,
      hora: fila.hora,
      actualizado: fila.actualizado,
      guardado_at: fila.updated_at,
      vigente: fila.fecha === hoy,
      tasas,
      conversiones,
      monedas: MONEDAS_APP,
      aviso: [avisoCache, `La tasa no se pudo cachear: ${errUpsert.message}`]
        .filter(Boolean)
        .join(" "),
    });
  }

  return json(
    filaRespuesta({ ...fila, updated_at: fila.updated_at }, "api", avisoCache),
  );
});
