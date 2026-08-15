// POST /functions/v1/wapi-send-products
// Body:
// {
//   id_sesion: number,
//   product_ids: number[],
//   destinations: Array<{ tipo: 'numero'|'grupo', chat_id: string, etiqueta?: string }>,
//   message_template?: string,
//   delay_min_seconds?: number,   // anti-ban (default 5)
//   delay_max_seconds?: number,   // anti-ban (default 10)
//   tipo_envio?: 'manual'|'programado',
//   send_summary?: boolean        // resumen final (default true)
// }
//
// Formato del mensaje (ver buildCaption): una imagen por producto con un
// caption de 5 líneas — nombre + icono, disponibilidad con semáforo
// 🟢/🟡/🔴, precio, presentación y hashtag de categoría. Al terminar TODA la
// tanda se manda además un mensaje de texto con el listado resumido de
// productos (ver buildSummaryMessages).
//
// Estrategia anti-ban actual:
//   1. Por producto: la misma imagen se manda a los destinatarios EN SERIE,
//      con una pausa corta entre uno y otro. Antes iban en paralelo (cap 5) y
//      eso saturaba la sesión de WAPI —que es UNA sola instancia de
//      Puppeteer— devolviendo NETWORK_ERROR: con 1 grupo iba fino y con 4 se
//      caía a la mitad.
//   2. Entre productos: delay aleatorio en [delay_min, delay_max].
//   3. Defaults 5–10s: enviando en serie el ritmo real queda holgadamente por
//      debajo del techo recomendado de 20 msgs/min/sesión.
//
// El envío se reparte en chunks encadenados: cada invocación despacha los
// productos que le caben en su presupuesto de wall-clock (los workers de Edge
// mueren a los ~400s) y re-invoca esta misma función con el resto. El corte se
// decide MIDIENDO el reloj, no estimándolo.
//
import { handleOptions, okResponse, errorResponse } from "../_shared/cors.ts";
import {
  getAuthContext,
  assertStoreAccess,
  isServiceRoleCall,
  serviceClient,
  AuthContext,
} from "../_shared/auth.ts";
import { wapi } from "../_shared/wapi_client.ts";
import { invokeEdgeFunction } from "../_shared/invoke.ts";

interface Destino {
  tipo: "numero" | "grupo";
  chat_id: string;
  etiqueta?: string;
}

interface SendBody {
  id_sesion: number;
  product_ids: number[];
  destinations: Destino[];
  message_template?: string;
  delay_min_seconds?: number;
  delay_max_seconds?: number;
  tipo_envio?: "manual" | "programado";
  id_programacion?: number; // solo si tipo_envio = programado

  // MODO REANUDAR: ids de `app_wapi_envio_log` que quedaron `pendiente` o
  // `fallido` en una tanda anterior. Cuando viene, NO se insertan filas
  // nuevas: se re-despachan exactamente esos mensajes reutilizando su fila
  // de log (así el historial no se duplica y la tanda se "completa" en vez
  // de aparecer dos veces). `product_ids` y `destinations` se ignoran: los
  // pares (producto, chat) salen de los propios logs.
  resume_log_ids?: number[];

  // Uso INTERNO (cadena de chunks): lista completa de productos del envío
  // lógico, para que el resumen final del último chunk liste todo y no sólo
  // su propio trozo. Si no viene, se asume `product_ids`.
  summary_product_ids?: number[];

  // Uso INTERNO: esta invocación NO despacha productos, sólo manda el mensaje
  // resumen. La usa el último chunk cuando se queda sin presupuesto de tiempo
  // para el texto: así el resumen sale en un worker nuevo en vez de perderse.
  // Requiere `summary_product_ids` + `destinations`.
  summary_only?: boolean;

  /** ¿Mandar el mensaje resumen al final del envío? Default true. */
  send_summary?: boolean;
}

// ───────────────────────────────────────────────────────────────────────
//  Reintentos
//  Los fallos observados en producción son casi todos transitorios
//  (NETWORK_ERROR: la sesión WAPI rechaza la conexión cuando está saturada
//  con varios envíos en paralelo). Antes un único fallo marcaba el mensaje
//  como `fallido` para siempre; ahora se reintenta con backoff.
// ───────────────────────────────────────────────────────────────────────
const RETRY_MAX_ATTEMPTS = 3;
const RETRY_BASE_MS = 4_000;

/**
 * ¿El error merece reintento? Los 4xx de validación no (fallarían igual).
 *
 * `TIMEOUT` lo emite nuestro propio wapi_client cuando WAPI abre la conexión y
 * no contesta dentro del plazo; casi siempre es la sesión atascada un momento,
 * así que se reintenta. Los 429 NO se resuelven aquí: llevan
 * `retryAfterSeconds` y los gestiona `dispatchOne`, que respeta la espera
 * pedida en vez de insistir con backoff propio.
 */
function esReintentable(code: string | undefined): boolean {
  if (!code) return true;
  if (code === "NETWORK_ERROR" || code === "SEND_ERROR" || code === "TIMEOUT") {
    return true;
  }
  const m = /^HTTP_(\d{3})$/.exec(code);
  if (m) {
    const status = Number(m[1]);
    return status === 408 || status === 429 || status >= 500;
  }
  return false;
}

// Trunca caption (WhatsApp permite máx 1024 chars en captions de imagen)
function safeCaption(text: string): string {
  if (text.length <= 1020) return text;
  return text.slice(0, 1017) + "...";
}

// ───────────────────────────────────────────────────────────────────────
//  Formato del mensaje
//  Política actual (deliberadamente austera): el caption lleva SÓLO 5 datos
//  — nombre, disponibilidad, precio, presentación y hashtag de categoría.
//  Sin encabezados de marketing, sin líneas separadoras y sin CTA: además de
//  leerse más limpio, los captions cortos no inflan la cola de Puppeteer de
//  la sesión WAPI.
// ───────────────────────────────────────────────────────────────────────

/** Iconos "elegantes" que acompañan al nombre. Se rotan entre productos. */
const PRODUCT_ICONS = [
  "✨", "💫", "🌟", "⭐", "💎", "🔹", "🔸", "🏷️",
  "🛍️", "🎁", "🌸", "🍀", "💠", "🎯", "🪄", "🔖",
];

/** Con este stock o menos, la disponibilidad se marca 🟡 en vez de 🟢. */
const STOCK_BAJO = 5;

/** Tope conservador por mensaje de texto (WhatsApp corta sobre los 4096). */
const SUMMARY_MAX_CHARS = 3_500;

/**
 * Máximo de mensajes de resumen por destino. Con 6 partes caben ~270
 * productos; el resto se anuncia como "y N más" en vez de desaparecer en
 * silencio. El tope existe por tiempo, no por WhatsApp: cada texto tarda
 * ~3s × destinos. Si no cupiera en el worker, el resumen se delega a una
 * invocación nueva (`summary_only`) en vez de recortarse.
 */
const SUMMARY_MAX_PARTS = 6;

function pick<T>(arr: T[], seed: number): T {
  return arr[seed % arr.length];
}

/** Separador de miles respetando la parte decimal. */
function withThousands(s: string): string {
  const [ent, dec] = s.split(".");
  return ent.replace(/\B(?=(\d{3})+(?!\d))/g, ",") + (dec ? `.${dec}` : "");
}

function formatPrice(n: number): string {
  // Formato con separador de miles y sin decimales innecesarios.
  if (!Number.isFinite(n) || n <= 0) return "";
  return withThousands(n % 1 === 0 ? n.toFixed(0) : n.toFixed(2));
}

/** Cantidades: a diferencia del precio admite el 0 y decimales (fraccionables). */
function formatQty(n: number): string {
  if (!Number.isFinite(n)) return "";
  // 2.50 → "2.5" · 2.00 → "2"
  const s = Number.isInteger(n)
    ? n.toFixed(0)
    : n.toFixed(2).replace(/0+$/, "").replace(/\.$/, "");
  return withThousands(s);
}

/**
 * Semáforo de disponibilidad: 🟢 holgado · 🟡 quedan pocas · 🔴 agotado.
 * `null` significa "no se pudo calcular el stock" → sin semáforo, para no
 * anunciar un agotado que no sabemos si es real.
 */
function stockEmoji(stock: number | null): string {
  if (stock == null) return "";
  if (stock <= 0) return "🔴";
  if (stock <= STOCK_BAJO) return "🟡";
  return "🟢";
}

/** Texto de cantidad: "24 disponibles" · "Agotado" · "" si no se sabe. */
function stockTexto(stock: number | null): string {
  if (stock == null) return "";
  if (stock <= 0) return "Agotado";
  return `${formatQty(stock)} disponibles`;
}

/**
 * Recorta nombres largos para el listado del resumen. Además de leerse mejor,
 * acota la longitud de cada línea: sin esto un nombre kilométrico podría
 * empujar un bloque del resumen por encima del límite de WhatsApp (el troceo
 * nunca parte una línea por la mitad).
 */
function shortName(s: string, max = 60): string {
  const t = s.trim();
  return t.length <= max ? t : `${t.slice(0, max - 1)}…`;
}

/**
 * Convierte el nombre de una categoría en hashtag estilo `#alimentos` o
 * `#aseo_personal`:
 *   - todo a minúsculas
 *   - acentos/diacríticos eliminados
 *   - espacios y separadores → `_`
 *   - todo lo que no sea [a-z0-9_] se descarta
 *   - `_` duplicados se colapsan y se recortan extremos
 * Devuelve cadena vacía si no queda nada útil.
 */
function categoriaToHashtag(cat: string | null | undefined): string {
  if (!cat) return "";
  const slug = cat
    .normalize("NFD")
    .replace(/[̀-ͯ]/g, "") // quitar acentos (combining diacritics)
    .toLowerCase()
    .replace(/[\s\-\/]+/g, "_") // separadores → _
    .replace(/[^a-z0-9_]/g, "") // descartar resto
    .replace(/_+/g, "_") // colapsar __ → _
    .replace(/^_+|_+$/g, ""); // trim _
  return slug ? `#${slug}` : "";
}

/** Datos de un producto ya resueltos y listos para pintar en el mensaje. */
interface ProdInfo {
  id: number;
  denominacion: string;
  descripcion: string | null;
  imagen: string | null;
  sku: string | null;
  categoria: string | null;
  /** Nombre de la presentación base ("Unidad", "Caja", "Paquete"…) o null. */
  presentacion: string | null;
  precio: number;
  /** Existencias sumadas. `null` = no se pudo calcular (≠ agotado). */
  stock: number | null;
}

/**
 * Caption del producto. Cinco líneas como máximo, sin adornos:
 *
 *   ✨ *Coca Cola 1L*
 *   🟢 24 disponibles
 *   💰 $250 CUP
 *   📦 Presentación: Caja
 *   #refrescos
 *
 * De la presentación se muestra SÓLO el nombre — nunca la cantidad por
 * empaque ("12 x Caja"): al cliente le importa en qué formato lo compra,
 * no cómo se contabiliza en el almacén.
 *
 * Si se pasa un `template`, se respeta y se reemplazan los placeholders
 * `{nombre}`, `{precio}`, `{categoria}`, `{sku}`, `{stock}`,
 * `{disponibilidad}` y `{presentacion}`.
 */
function buildCaption(
  template: string | undefined,
  p: ProdInfo,
  seed: number,
): string {
  const cantidad = stockTexto(p.stock);
  const emoji = stockEmoji(p.stock);
  const precioStr = formatPrice(p.precio);
  const tag = categoriaToHashtag(p.categoria);

  if (template && template.includes("{nombre}")) {
    return safeCaption(
      template
        .replaceAll("{nombre}", p.denominacion ?? "")
        // {descripcion} se rellena vacío: la política actual oculta la
        // descripción del producto en los envíos por WhatsApp (ver el
        // formato por defecto). Si el template la pide, queda en blanco.
        .replaceAll("{descripcion}", "")
        .replaceAll("{precio}", precioStr)
        // {categoria} → hashtag (#alimentos, #aseo_personal, …)
        .replaceAll("{categoria}", tag)
        .replaceAll("{sku}", p.sku ?? "")
        .replaceAll("{stock}", p.stock != null ? formatQty(p.stock) : "")
        .replaceAll("{disponibilidad}", cantidad ? `${emoji} ${cantidad}` : "")
        .replaceAll("{presentacion}", p.presentacion ?? ""),
    );
  }

  const parts: string[] = [];
  parts.push(`${pick(PRODUCT_ICONS, seed)} *${p.denominacion.trim()}*`);
  if (cantidad) parts.push(`${emoji} ${cantidad}`);
  if (precioStr) parts.push(`💰 $${precioStr} CUP`);
  if (p.presentacion) parts.push(`📦 Presentación: ${p.presentacion}`);
  if (tag) parts.push(tag);

  return safeCaption(parts.join("\n"));
}

/**
 * Mensaje(s) de resumen que se manda al final de la tanda: un listado
 * compacto de nombre · cantidad/disponibilidad · precio.
 *
 *   📋 *RESUMEN DE PRODUCTOS*
 *   _12 productos · precios en CUP_
 *
 *   🟢 *Coca Cola 1L* · 24 disponibles · 💰 $250
 *   🟡 *Pan Suave* · 3 disponibles · 💰 $80
 *   🔴 *Cerveza Cristal* · Agotado · 💰 $200
 *
 * Devuelve varios mensajes si el listado no cabe en uno solo (WhatsApp corta
 * los textos largos, así que troceamos por debajo de SUMMARY_MAX_CHARS).
 */
function buildSummaryMessages(items: ProdInfo[]): string[] {
  if (items.length === 0) return [];

  const lineas = items.map((p) => {
    // "▪️" cuando no hay dato de stock: mantiene la columna alineada sin
    // afirmar una disponibilidad que no conocemos.
    const campos = [`${stockEmoji(p.stock) || "▪️"} *${shortName(p.denominacion)}*`];
    const cantidad = stockTexto(p.stock);
    if (cantidad) campos.push(cantidad);
    const precioStr = formatPrice(p.precio);
    if (precioStr) campos.push(`💰 $${precioStr}`);
    return campos.join(" · ");
  });

  const bloques: string[] = [];
  let buf: string[] = [];
  let len = 0;
  for (const linea of lineas) {
    if (buf.length > 0 && len + linea.length + 1 > SUMMARY_MAX_CHARS) {
      bloques.push(buf.join("\n"));
      buf = [];
      len = 0;
    }
    buf.push(linea);
    len += linea.length + 1;
  }
  if (buf.length > 0) bloques.push(buf.join("\n"));

  // Tope de partes: preferimos un resumen recortado y honesto a uno completo
  // que el worker no alcance a mandar entero.
  let omitidos = 0;
  if (bloques.length > SUMMARY_MAX_PARTS) {
    omitidos = bloques
      .slice(SUMMARY_MAX_PARTS)
      .reduce((acc, b) => acc + b.split("\n").length, 0);
    bloques.length = SUMMARY_MAX_PARTS;
    console.warn(
      `[wapi-send-products] resumen recortado a ${SUMMARY_MAX_PARTS} mensaje(s): ` +
        `${omitidos} de ${items.length} producto(s) no se listan`,
    );
  }

  return bloques.map((cuerpo, i) => {
    const titulo = bloques.length > 1
      ? `📋 *RESUMEN DE PRODUCTOS* (${i + 1}/${bloques.length})`
      : "📋 *RESUMEN DE PRODUCTOS*";
    const pie = omitidos > 0 && i === bloques.length - 1
      ? `\n\n_… y ${omitidos} producto(s) más disponibles en tienda._`
      : "";
    return `${titulo}\n_${items.length} producto(s) · precios en CUP_\n\n${cuerpo}${pie}`;
  });
}

/** Parte una lista en trozos de tamaño fijo. */
function chunkArray<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/**
 * Lee TODAS las filas de una consulta paginando con `.range()`.
 *
 * PostgREST corta las respuestas en `max-rows` (1000 por defecto en Supabase)
 * SIN avisar. Las tablas `app_dat_precio_venta` e
 * `app_dat_inventario_productos` son históricos con muchas filas por
 * producto, así que una consulta con 70 productos se truncaba: los productos
 * cuyo último movimiento quedaba fuera del corte salían con precio 0 y
 * "🔴 Agotado" en el mensaje aunque tuvieran stock. Paginando desaparece.
 */
async function fetchAllPages<T>(
  makeQuery: (from: number, to: number) => PromiseLike<
    { data: T[] | null; error: { message: string } | null }
  >,
  opts: { pageSize?: number; maxPages?: number; label?: string } = {},
): Promise<T[]> {
  const pageSize = opts.pageSize ?? 1000;
  const maxPages = opts.maxPages ?? 20;
  const label = opts.label ?? "query";
  const out: T[] = [];
  for (let page = 0; page < maxPages; page++) {
    const from = page * pageSize;
    const { data, error } = await makeQuery(from, from + pageSize - 1);
    if (error) {
      console.warn(`[wapi-send-products] ${label}: error paginando: ${error.message}`);
      break;
    }
    const filas = data ?? [];
    out.push(...filas);
    if (filas.length < pageSize) return out; // última página
    if (page === maxPages - 1) {
      console.warn(
        `[wapi-send-products] ${label}: tope de ${maxPages} páginas ` +
          `(${out.length} filas) — puede faltar histórico`,
      );
    }
  }
  return out;
}

/**
 * Carga todo lo que el mensaje necesita de cada producto: nombre, imagen,
 * categoría, precio vigente, presentación base y stock disponible.
 *
 * Se usa dos veces por tanda: para los productos del chunk que se está
 * despachando y (en el último chunk) para el listado completo del resumen.
 */
async function loadProductInfo(
  admin: ReturnType<typeof serviceClient>,
  idTienda: number,
  ids: number[],
): Promise<Map<number, ProdInfo>> {
  const out = new Map<number, ProdInfo>();
  if (ids.length === 0) return out;

  const { data: productos, error: prodErr } = await admin
    .from("app_dat_producto")
    .select(
      "id, denominacion, descripcion, imagen, sku, app_dat_categoria(denominacion)",
    )
    .in("id", ids);
  if (prodErr) throw new Error(`Error cargando productos: ${prodErr.message}`);

  // Precio venta (último vigente por producto).
  // `app_dat_precio_venta` es un histórico: cada producto puede tener N filas
  // (una por cada cambio de precio). El precio actual es el de mayor `id`.
  // Traemos el histórico ordenado por id desc y nos quedamos con la primera
  // ocurrencia por producto (la más reciente).
  //
  // Se consulta en lotes de productos + paginado: con muchos productos, una
  // sola consulta superaba el `max-rows` de PostgREST y los productos cuyo
  // precio quedaba fuera del corte se anunciaban a $0.
  const precioMap = new Map<number, number>();
  for (const lote of chunkArray(ids, 25)) {
    const precios = await fetchAllPages<any>(
      (from, to) =>
        admin
          .from("app_dat_precio_venta")
          .select("id, id_producto, precio_venta_cup, precio_venta_usd")
          .in("id_producto", lote)
          .order("id", { ascending: false })
          .range(from, to),
      { label: "precio_venta" },
    );
    for (const p of precios) {
      if (precioMap.has(p.id_producto)) continue; // ya tenemos el más reciente
      precioMap.set(
        p.id_producto,
        Number(p.precio_venta_cup ?? p.precio_venta_usd ?? 0),
      );
    }
  }
  if (precioMap.size < ids.length) {
    console.warn(
      `[wapi-send-products] precio resuelto para ${precioMap.size}/${ids.length} ` +
        `producto(s) — el resto irá sin precio`,
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // Stock disponible por producto (suma sobre todas las ubicaciones de
  // todos los almacenes vinculados a algún TPV de la tienda).
  //
  // 1. tpvs.id_almacen ─→ 2. layout_almacen.id (ubicaciones) ─→
  // 3. inventario_productos (histórico: última fila por
  //    (id_producto, id_ubicacion) manda) ─→ sumar cantidad_final.
  //
  // `stockOk` sólo se pone a true si la cadena llegó hasta el final. Si la
  // tienda no tiene almacenes/ubicaciones o algo falla, el stock queda
  // DESCONOCIDO (null) en vez de 0 — anunciar "🔴 Agotado" por un fallo de
  // lectura sería peor que no decir nada.
  // ───────────────────────────────────────────────────────────────────
  const stockMap = new Map<number, number>();
  let stockOk = false;
  try {
    const { data: tpvs } = await admin
      .from("app_dat_tpv")
      .select("id_almacen")
      .eq("id_tienda", idTienda);
    const almacenIds = Array.from(
      new Set((tpvs ?? []).map((t: any) => Number(t.id_almacen)).filter(Boolean)),
    );

    if (almacenIds.length > 0) {
      const { data: ubicaciones } = await admin
        .from("app_dat_layout_almacen")
        .select("id")
        .in("id_almacen", almacenIds)
        .is("deleted_at", null);
      const ubicacionIds = (ubicaciones ?? []).map((u: any) => Number(u.id));

      if (ubicacionIds.length > 0) {
        // Traemos todos los movimientos de inventario (histórico) para
        // los productos y ubicaciones relevantes. Después, en memoria,
        // nos quedamos con la última fila por (producto, ubicación).
        //
        // Esta es la consulta que más sufría el corte de `max-rows`: es un
        // histórico de movimientos, así que 70 productos × N ubicaciones ×
        // M movimientos pasa de 1000 filas con facilidad. Cuando se cortaba,
        // los productos que quedaban fuera se anunciaban como "🔴 Agotado"
        // teniendo stock. Lotes pequeños de productos + paginado lo evitan.
        // Mapa intermedio: (idProducto, idUbicacion) → cantidad_final más reciente.
        const latestPerPair = new Map<string, number>();
        for (const lote of chunkArray(ids, 10)) {
          const invRows = await fetchAllPages<any>(
            (from, to) =>
              admin
                .from("app_dat_inventario_productos")
                .select("id, id_producto, id_ubicacion, cantidad_final, created_at")
                .in("id_producto", lote)
                .in("id_ubicacion", ubicacionIds)
                .order("id", { ascending: false })
                .range(from, to),
            { label: "inventario_productos" },
          );
          for (const row of invRows) {
            const key = `${row.id_producto}_${row.id_ubicacion}`;
            if (!latestPerPair.has(key)) {
              latestPerPair.set(key, Number(row.cantidad_final ?? 0));
            }
          }
        }
        // Acumulamos por producto.
        for (const [key, qty] of latestPerPair.entries()) {
          const idProd = Number(key.split("_")[0]);
          stockMap.set(idProd, (stockMap.get(idProd) ?? 0) + qty);
        }
        stockOk = true;
      }
    }
    console.log(
      `[wapi-send-products] stock calculado para ${stockMap.size}/${ids.length} ` +
        `productos (ok=${stockOk})`,
    );
  } catch (e) {
    // No bloqueamos el envío si falla el cálculo de stock — solo se
    // omite del mensaje.
    console.warn(
      `[wapi-send-products] error calculando stock: ${(e as Error).message ?? e}`,
    );
  }

  // ───────────────────────────────────────────────────────────────────
  // Presentación base de cada producto.
  // `app_dat_producto_presentacion` NO tiene FK declarada hacia
  // `app_nom_presentacion`, así que PostgREST no puede resolver el embed:
  // hay que traer los nombres en una segunda consulta.
  // ───────────────────────────────────────────────────────────────────
  const presentacionMap = new Map<number, string>();
  try {
    const { data: pres } = await admin
      .from("app_dat_producto_presentacion")
      .select("id, id_producto, id_presentacion, es_base")
      .in("id_producto", ids)
      // es_base primero: es la presentación en la que se vende el producto.
      .order("es_base", { ascending: false, nullsFirst: false })
      .order("id", { ascending: true });

    const idsPres = Array.from(
      new Set(
        (pres ?? []).map((r: any) => Number(r.id_presentacion)).filter(Boolean),
      ),
    );
    if (idsPres.length > 0) {
      const { data: noms } = await admin
        .from("app_nom_presentacion")
        .select("id, denominacion")
        .in("id", idsPres);
      const nombrePres = new Map<number, string>(
        (noms ?? []).map((n: any) => [Number(n.id), String(n.denominacion ?? "")]),
      );
      for (const r of pres ?? []) {
        const idProd = Number((r as any).id_producto);
        if (presentacionMap.has(idProd)) continue; // ya tenemos la base
        const nombre = nombrePres.get(Number((r as any).id_presentacion));
        if (nombre && nombre.trim()) presentacionMap.set(idProd, nombre.trim());
      }
    }
  } catch (e) {
    console.warn(
      `[wapi-send-products] error cargando presentaciones: ${(e as Error).message ?? e}`,
    );
  }

  for (const p of productos ?? []) {
    const id = Number((p as any).id);
    // Categoría llega como objeto (PostgREST embed) o null.
    const catRaw = (p as any).app_dat_categoria;
    const categoria = Array.isArray(catRaw)
      ? catRaw[0]?.denominacion ?? null
      : catRaw?.denominacion ?? null;

    out.set(id, {
      id,
      denominacion: String((p as any).denominacion ?? ""),
      descripcion: (p as any).descripcion ?? null,
      imagen: (p as any).imagen ?? null,
      sku: (p as any).sku ?? null,
      categoria,
      presentacion: presentacionMap.get(id) ?? null,
      precio: precioMap.get(id) ?? 0,
      stock: stockOk ? stockMap.get(id) ?? 0 : null,
    });
  }
  return out;
}

/**
 * Manda un mensaje de texto con la misma política de reintentos que las
 * imágenes (los fallos de WAPI son casi siempre transitorios).
 */
async function sendTextConReintentos(
  wapiSessionId: string,
  chatId: string,
  text: string,
): Promise<boolean> {
  for (let intento = 1; intento <= RETRY_MAX_ATTEMPTS; intento++) {
    const r = await wapi.sendText(wapiSessionId, chatId, text);
    if (r.success) return true;

    const code = r.error?.code ?? "SEND_ERROR";
    // Si el server pide frenar (rate limiter o SEND_PACING) hay que respetar
    // su plazo: reintentar antes sólo alarga el cooldown.
    const pausaSeg = r.error?.retryAfterSeconds ??
      (code === "SEND_PACING_LIMITED" ? 60 : undefined);
    if (pausaSeg && pausaSeg > 0 && pausaSeg <= 60 && intento < RETRY_MAX_ATTEMPTS) {
      console.error(
        `[wapi-send-products] resumen chat=${chatId} ${code}: ` +
          `el server pide ${pausaSeg}s — esperando`,
      );
      await new Promise((res) => setTimeout(res, pausaSeg * 1000));
      continue;
    }

    const puedeReintentar = intento < RETRY_MAX_ATTEMPTS && esReintentable(code);
    console.error(
      `[wapi-send-products] resumen fallido chat=${chatId} ` +
        `intento ${intento}/${RETRY_MAX_ATTEMPTS} (${code}): ` +
        `${r.error?.message ?? "Error desconocido"}` +
        (puedeReintentar ? " — reintentando" : ""),
    );
    if (!puedeReintentar) break;

    const base = RETRY_BASE_MS * Math.pow(2, intento - 1);
    await new Promise((res) =>
      setTimeout(res, Math.round(base * (0.75 + Math.random() * 0.5)))
    );
  }
  return false;
}

/**
 * Lógica core reutilizable por wapi-cron-dispatch.
 * Recibe un admin client (service_role) y los datos resueltos.
 */
export async function dispatchProducts(args: {
  admin: ReturnType<typeof serviceClient>;
  idSesion: number;
  idTienda: number;
  wapiSessionId: string;
  productIds: number[];
  destinations: Destino[];
  template?: string;
  delayMin: number;
  delayMax: number;
  tipoEnvio: "manual" | "programado";
  idProgramacion?: number;
  /** Ver `SendBody.resume_log_ids`. Cuando viene, se reusan esas filas de log. */
  resumeLogIds?: number[];
  /**
   * Lista COMPLETA de productos del envío lógico, para el mensaje resumen.
   * La primera invocación no la trae (son todos los pedidos); las
   * continuaciones por chunk sí, para que el resumen del último chunk liste
   * todo lo enviado y no sólo su trozo.
   */
  summaryProductIds?: number[];
  /** ¿Mandar el mensaje resumen al terminar? Default true. */
  enviarResumen?: boolean;
  /** Ver `SendBody.summary_only`: no despacha productos, sólo el resumen. */
  summaryOnly?: boolean;
}) {
  const {
    admin, idSesion, idTienda, wapiSessionId, productIds,
    destinations, template, delayMin, delayMax, tipoEnvio, idProgramacion,
    resumeLogIds,
  } = args;
  const enviarResumen = args.enviarResumen ?? true;
  const summaryOnly = args.summaryOnly === true;

  // ── MODO REANUDAR ───────────────────────────────────────────────────
  // Reconstruimos productos y destinos a partir de las filas de log que
  // quedaron sin enviar, y guardamos el mapa (producto, chat) → logId para
  // reutilizar esas filas en vez de insertar duplicados.
  const esReanudacion = Array.isArray(resumeLogIds) && resumeLogIds.length > 0;
  const logIdPorPar = new Map<string, number>();
  let effProductIds = productIds;
  let effDestinations = destinations;

  if (esReanudacion) {
    const { data: pend, error: pendErr } = await admin
      .from("app_wapi_envio_log")
      .select("id, id_producto, chat_id, estado")
      .in("id", resumeLogIds!)
      .eq("id_tienda", idTienda)
      .neq("estado", "enviado")
      .order("id", { ascending: true });
    if (pendErr) {
      throw new Error(`Error cargando logs a reanudar: ${pendErr.message}`);
    }

    const ordenProd: number[] = [];
    const vistosProd = new Set<number>();
    const chats = new Map<string, Destino>();
    // Los destinos originales traen `etiqueta`/`tipo`; los reaprovechamos.
    const metaPorChat = new Map(destinations.map((d) => [d.chat_id, d]));

    for (const row of pend ?? []) {
      const idProd = Number((row as any).id_producto);
      const chatId = String((row as any).chat_id ?? "");
      if (!Number.isFinite(idProd) || !chatId) continue;
      const key = `${idProd}|${chatId}`;
      // Si el mismo par apareciera dos veces nos quedamos con el primer log.
      if (!logIdPorPar.has(key)) logIdPorPar.set(key, Number((row as any).id));
      if (!vistosProd.has(idProd)) {
        vistosProd.add(idProd);
        ordenProd.push(idProd);
      }
      if (!chats.has(chatId)) {
        chats.set(
          chatId,
          metaPorChat.get(chatId) ?? {
            tipo: chatId.endsWith("@g.us") ? "grupo" : "numero",
            chat_id: chatId,
          },
        );
      }
    }

    effProductIds = ordenProd;
    effDestinations = Array.from(chats.values());
    console.log(
      `[wapi-send-products] REANUDAR: ${logIdPorPar.size} mensaje(s) ` +
        `sin enviar → ${effProductIds.length} producto(s), ` +
        `${effDestinations.length} destino(s)`,
    );
  }

  // En modo sólo-resumen no hay productos que despachar: lo único
  // imprescindible son los destinos y la lista para el texto.
  if (effDestinations.length === 0) {
    return { enviados: 0, fallidos: 0, batch_id: null, skipped: true };
  }
  if (!summaryOnly && effProductIds.length === 0) {
    return { enviados: 0, fallidos: 0, batch_id: null, skipped: true };
  }

  // Productos que listará el resumen final. En la primera invocación son
  // todos los pedidos; en las continuaciones viene heredado del chunk previo.
  // (Al reanudar, la app manda la lista completa de la tanda en
  //  `summary_product_ids`; si no llegara, el resumen listaría sólo los
  //  productos que quedaron sin enviar.)
  const summaryIds = args.summaryProductIds?.length
    ? args.summaryProductIds
    : effProductIds;

  // ───────────────────────────────────────────────────────────────────
  //  CHUNKING anti-timeout — guiado por el RELOJ, no por una estimación
  //
  //  Los workers de Supabase Edge mueren al llegar al techo de ~400s de
  //  wall-clock. La versión anterior decidía antes del loop cuántos productos
  //  caben con una fórmula que ignoraba el número de destinos
  //  (`ceil(destinos/5)` valía 1 tanto con 1 destino como con 4), así que con
  //  varios grupos el chunk se pasaba del presupuesto, el worker moría a
  //  mitad y la continuación —que se encolaba DESPUÉS del loop— no llegaba a
  //  encolarse: la cadena se rompía y de 70 productos llegaban 20 o 30.
  //
  //  Ahora:
  //   · Se mide el tiempo transcurrido y se corta cuando el siguiente
  //     producto ya no cabe con holgura, usando el peor producto observado.
  //   · Las filas de log se insertan producto a producto, justo antes de
  //     despacharlo: un corte no deja `pendiente` de productos no intentados.
  //   · La continuación se encola SIEMPRE al salir del loop y ANTES del
  //     resumen, así un resumen que se coma el worker no rompe la cadena.
  // ───────────────────────────────────────────────────────────────────
  const startedAt = Date.now();
  const elapsed = () => Date.now() - startedAt;

  /** Presupuesto de este worker. El techo real ronda los 400s; cortamos en
   *  270s para que quepan el último envío en curso y el encolado. */
  const WORKER_BUDGET_MS = 270_000;
  /** Pausa entre destinos del MISMO producto (fan-out en serie). */
  const FANOUT_PAUSE_MS = 1_500;
  /** Techo por producto: si su fan-out se eterniza (WAPI lento, reintentos),
   *  se abandonan los destinos que falten de ESE producto en vez de
   *  arrastrar el chunk entero al matadero. */
  const PRODUCT_MAX_MS = 120_000;
  /** Espera máxima que aceptamos cuando WAPI pide frenar. Más que esto no
   *  cabe en un worker: se corta el chunk y queda reanudable. */
  const PACING_WAIT_MAX_MS = 60_000;
  /** Productos por ventana de precarga de datos (nombre, precio, stock…). */
  const WINDOW_SIZE = 25;

  const minMs = Math.max(5_000, delayMin * 1000);
  const maxMs = Math.max(minMs + 1_000, delayMax * 1000);
  const avgDelayMs = (minMs + maxMs) / 2;

  /** Destinos con chat_id válido: WhatsApp exige `@c.us` (números) o `@g.us`
   *  (grupos). Se deduplican — el mismo grupo repetido en la programación
   *  duplicaría cada mensaje. Son los únicos que cuentan para los tiempos. */
  const chatsValidos = Array.from(
    new Set(
      effDestinations
        .map((d) => (typeof d.chat_id === "string" ? d.chat_id.trim() : ""))
        .filter((c) => /@(c|g)\.us$/.test(c)),
    ),
  );
  const chatsInvalidos = effDestinations
    .map((d) => String(d.chat_id ?? "").trim())
    .filter((c) => !/@(c|g)\.us$/.test(c));
  if (chatsInvalidos.length > 0) {
    console.warn(
      `[wapi-send-products] ${chatsInvalidos.length} destino(s) con chat_id ` +
        `inválido, ignorados: ${JSON.stringify(chatsInvalidos.slice(0, 5))}`,
    );
  }
  const nDestinos = Math.max(1, chatsValidos.length);
  /** Estimación inicial del fan-out de un producto, sin el delay anti-ban:
   *  ~5s de envío + la pausa, por destino. Se corrige con lo medido. */
  const envioEstimadoMs = nDestinos * (5_000 + FANOUT_PAUSE_MS);
  let peorEnvioMs = 0;
  /** Hueco que debe quedar libre para arrancar otro producto: lo peor visto
   *  (+20%) más el delay anti-ban. Se topa a medio presupuesto para que un
   *  único producto lentísimo no reduzca los chunks a un producto cada uno. */
  const reservaProductoMs = () =>
    Math.min(
      WORKER_BUDGET_MS / 2,
      Math.max(envioEstimadoMs, peorEnvioMs * 1.2) + avgDelayMs,
    );

  /** Productos que este worker no alcanzará. Se rellena cuando el reloj
   *  manda; `reinvokeRemaining` lo lee en el momento de encolar. */
  let remainingIds: number[] = [];
  /** Si WAPI pidió frenar, aquí queda la espera que exigió. */
  let pacingAbort: { retryAfterSeconds: number } | null = null;

  // Re-invoca wapi-send-products con los productos que NO caben en este chunk.
  // Fire-and-forget: el endpoint responde de inmediato (queued) y procesa el
  // siguiente chunk en su propio background task con 400s frescos.
  //
  // IMPORTANTE: idempotencia. `reinvokeRemaining` sólo debe encolar UNA vez por
  // worker; si se llama dos veces (p.ej. en el early-fire y otra vez al final
  // por una ruta de error), duplicaría el chunk restante. Un flag lo evita.
  let reinvoked = false;
  const reinvokeRemaining = async (): Promise<boolean> => {
    if (remainingIds.length === 0 || reinvoked) return false;
    reinvoked = true;

    // En modo reanudar, la continuación también debe reanudar: si mandara
    // sólo product_ids insertaría filas de log nuevas y duplicaría la tanda.
    // Filtramos los logIds que corresponden a los productos que faltan.
    const remainingSet = new Set(remainingIds);
    const remainingLogIds = esReanudacion
      ? Array.from(logIdPorPar.entries())
          .filter(([k]) => remainingSet.has(Number(k.split("|")[0])))
          .map(([, v]) => v)
      : [];

    const payload = {
      id_sesion: idSesion,
      product_ids: remainingIds,
      destinations: effDestinations,
      ...(esReanudacion ? { resume_log_ids: remainingLogIds } : {}),
      ...(template ? { message_template: template } : {}),
      delay_min_seconds: delayMin,
      delay_max_seconds: delayMax,
      tipo_envio: tipoEnvio,
      ...(idProgramacion ? { id_programacion: idProgramacion } : {}),
      // El resumen lo manda el ÚLTIMO chunk de la cadena, y necesita conocer
      // la lista completa del envío — no sólo su propio trozo.
      summary_product_ids: summaryIds,
      send_summary: enviarResumen,
    };

    const res = await invokeEdgeFunction(
      admin,
      "wapi-send-products",
      payload,
      "wapi-send-products/chunk",
    );
    if (res.ok) {
      console.log(
        `[wapi-send-products] continuación encolada (${res.via}): ` +
          `${remainingIds.length} producto(s) restantes`,
      );
    } else {
      console.error(
        `[wapi-send-products] CADENA ROTA: ${remainingIds.length} producto(s) ` +
          `quedan sin despachar (${res.error ?? "motivo desconocido"})`,
      );
    }
    return res.ok;
  };

  // Cuando la cadena se rompe (no se pudo encolar la continuación) o WAPI pide
  // una pausa que no cabe en este worker, los productos que quedan fuera no
  // tienen fila de log: se insertan producto a producto justo antes de
  // despacharlos. Sin fila, la UI no sabe que existen y no ofrece reanudar.
  // Las creamos en `pendiente` para que la tanda quede recuperable con un clic.
  const registrarPendientes = async (ids: number[]): Promise<void> => {
    // Al reanudar las filas ya existen y siguen en `pendiente`: nada que hacer.
    if (ids.length === 0 || esReanudacion || chatsValidos.length === 0) return;
    const filas: Array<Record<string, unknown>> = [];
    for (const idProd of ids) {
      for (const chatId of chatsValidos) {
        filas.push({
          id_tienda: idTienda,
          id_sesion: idSesion,
          id_programacion: idProgramacion ?? null,
          id_producto: idProd,
          chat_id: chatId,
          tipo_envio: tipoEnvio,
          estado: "pendiente",
        });
      }
    }
    try {
      for (const lote of chunkArray(filas, 500)) {
        const { error } = await admin.from("app_wapi_envio_log").insert(lote);
        if (error) throw new Error(error.message);
      }
      console.warn(
        `[wapi-send-products] ${ids.length} producto(s) registrados como ` +
          `pendiente (${filas.length} fila(s)) para poder reanudar`,
      );
    } catch (e) {
      console.error(
        `[wapi-send-products] no se pudieron registrar los pendientes: ` +
          `${(e as Error).message ?? e}`,
      );
    }
  };

  // ── Datos de producto, con caché ────────────────────────────────────
  // Se cargan por ventanas en vez de todos de golpe: así un chunk que se
  // corta pronto no paga las consultas de históricos de productos que nunca
  // va a tocar, y lo ya cargado se reutiliza para el resumen final.
  const infoCache = new Map<number, ProdInfo>();
  const infoIntentados = new Set<number>();
  const ensureInfo = async (ids: number[]): Promise<void> => {
    const faltan = ids.filter((id) => !infoIntentados.has(id));
    if (faltan.length === 0) return;
    for (const id of faltan) infoIntentados.add(id);
    const cargado = await loadProductInfo(admin, idTienda, faltan);
    for (const [id, info] of cargado.entries()) infoCache.set(id, info);
  };

  // ── RESUMEN FINAL ───────────────────────────────────────────────────
  // Mensaje de texto con el listado completo (nombre · cantidad ·
  // disponibilidad · precio). Sólo lo dispara el ÚLTIMO chunk de la cadena;
  // si no, saldría un resumen por cada chunk.
  //
  // NO se registra en `app_wapi_envio_log`: esa tabla es por producto y la UI
  // agrupa/reanuda tandas a partir de ella — una fila sin `id_producto` que
  // fallara dejaría la tanda "interrumpida" para siempre, porque el modo
  // reanudar descarta los logs sin producto.
  const prepararResumen = async (): Promise<string[]> => {
    await ensureInfo(summaryIds);
    const items = summaryIds
      .map((id) => infoCache.get(id))
      .filter((p): p is ProdInfo => !!p);
    if (items.length < summaryIds.length) {
      console.warn(
        `[wapi-send-products] resumen: ${items.length}/${summaryIds.length} ` +
          `producto(s) resueltos`,
      );
    }
    return buildSummaryMessages(items);
  };

  const entregarResumen = async (mensajes: string[]): Promise<number> => {
    let ok = 0;
    for (const chatId of chatsValidos) {
      for (const texto of mensajes) {
        if (await sendTextConReintentos(wapiSessionId, chatId, texto)) ok++;
        // Pausa corta entre textos (anti-ban).
        await new Promise((res) => setTimeout(res, FANOUT_PAUSE_MS));
      }
    }
    return ok;
  };

  // Delega el resumen en un worker nuevo (`summary_only`). Se usa cuando el
  // chunk llega al final con el reloj agotado: mandarlo aquí sería perderlo a
  // mitad, que es justo lo que hacía que el resumen listara 10 productos.
  const encolarResumen = async (): Promise<boolean> => {
    const res = await invokeEdgeFunction(
      admin,
      "wapi-send-products",
      {
        id_sesion: idSesion,
        summary_only: true,
        product_ids: [],
        destinations: effDestinations,
        summary_product_ids: summaryIds,
        ...(template ? { message_template: template } : {}),
        delay_min_seconds: delayMin,
        delay_max_seconds: delayMax,
        tipo_envio: tipoEnvio,
        ...(idProgramacion ? { id_programacion: idProgramacion } : {}),
        send_summary: true,
      },
      "wapi-send-products/resumen",
    );
    if (res.ok) {
      console.log(
        `[wapi-send-products] resumen delegado a un worker nuevo (${res.via})`,
      );
    }
    return res.ok;
  };

  const cerrarConResumen = async (): Promise<number> => {
    if (!enviarResumen) return 0;
    try {
      // Sin margen ni para preparar el texto: delegar directamente.
      const sinMargen = !summaryOnly &&
        elapsed() + 30_000 >= WORKER_BUDGET_MS;
      if (sinMargen && await encolarResumen()) return 0;

      const mensajes = await prepararResumen();
      if (mensajes.length === 0) return 0;

      // ¿Cabe entregarlo aquí? Cada texto tarda ~6s por destino.
      const costeMs = mensajes.length * nDestinos * (6_000 + FANOUT_PAUSE_MS) +
        5_000;
      if (
        !summaryOnly && !sinMargen &&
        elapsed() + costeMs >= WORKER_BUDGET_MS &&
        await encolarResumen()
      ) {
        return 0;
      }

      // Pausa tras el último producto antes del texto (anti-ban).
      await new Promise((res) => setTimeout(res, Math.min(minMs, 5_000)));
      const ok = await entregarResumen(mensajes);
      console.log(
        `[wapi-send-products] resumen: ${summaryIds.length} producto(s) en ` +
          `${mensajes.length} mensaje(s) → ${ok} entrega(s) ok`,
      );
      return ok;
    } catch (e) {
      // El resumen es un extra: si falla, el envío de productos ya está hecho.
      console.error(
        `[wapi-send-products] error enviando resumen: ${(e as Error).message ?? e}`,
      );
      return 0;
    }
  };

  // Modo sólo-resumen: esta invocación existe únicamente para entregar el
  // texto final que el chunk anterior no alcanzó a mandar.
  if (summaryOnly) {
    const entregas = await cerrarConResumen();
    return {
      enviados: 0,
      fallidos: 0,
      batch_id: null,
      mode: "summary-only",
      resumen_entregas: entregas,
    };
  }

  // ── Preparación por producto ────────────────────────────────────────
  // Antes se construía la lista COMPLETA de mensajes y se insertaban todas
  // las filas de log de golpe, antes de mandar nada. Si el worker moría a
  // mitad, las filas de los productos que nunca se intentaron quedaban en
  // `pendiente` para siempre. Ahora cada producto se prepara —y se
  // registra— justo antes de despacharlo.
  type Envio = {
    idProducto: number;
    chatId: string;
    url: string;
    caption: string;
    mimetype: string;
    logId: number | null;
  };

  const skipped: Array<{ id_producto: number; reason: string }> = [];
  let seedCounter = Math.floor(Math.random() * 1000); // rotación de iconos
  let enviados = 0;
  let fallidos = 0;
  let productosDespachados = 0;
  let mensajesIntentados = 0;
  // batchId para correlación interna (no se envía al WAPI).
  const batchId = `b_${idTienda}_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;

  // Descarta un producto (sin imagen, imagen no pública…). Al reanudar hay
  // que marcar sus filas como fallido: si quedaran en `pendiente` la tanda se
  // vería "interrumpida" para siempre y el botón de reanudar reaparecería sin
  // poder avanzar nunca.
  const descartar = async (idProd: number, razon: string): Promise<void> => {
    skipped.push({ id_producto: idProd, reason: razon });
    if (!esReanudacion) return;
    const logs = chatsValidos
      .map((c) => logIdPorPar.get(`${idProd}|${c}`))
      .filter((v): v is number => v != null);
    if (logs.length === 0) return;
    await admin.from("app_wapi_envio_log").update({
      estado: "fallido",
      error_code: "SKIPPED",
      error_message: `No se puede enviar: ${razon}`,
    }).in("id", logs);
  };
  // Valida un producto, compone el caption y registra sus filas de log.
  // Devuelve los envíos a ejecutar, o `null` si el producto no se puede
  // mandar (ya quedó anotado en `skipped`).
  const prepararProducto = async (idProd: number): Promise<Envio[] | null> => {
    const p = infoCache.get(idProd);
    if (!p) {
      await descartar(idProd, "producto no encontrado");
      return null;
    }
    if (!p.imagen || typeof p.imagen !== "string" || !p.imagen.trim()) {
      await descartar(idProd, "sin imagen");
      return null;
    }
    const imageUrl = p.imagen.trim();
    // WAPI requiere URL pública http(s). Data URLs y blobs no funcionan.
    if (!/^https?:\/\//i.test(imageUrl)) {
      await descartar(
        idProd,
        `imagen no es URL http(s): ${imageUrl.slice(0, 40)}…`,
      );
      return null;
    }
    const caption = buildCaption(template, p, seedCounter++);
    // Inferir mimetype desde la extensión (algunas builds de WAPI lo exigen).
    const ext = imageUrl.split("?")[0].split(".").pop()?.toLowerCase() ?? "";
    const mimetype = ext === "png"
      ? "image/png"
      : ext === "webp"
      ? "image/webp"
      : ext === "gif"
      ? "image/gif"
      : "image/jpeg";

    // Al reanudar sólo se re-despachan los pares que quedaron sin enviar; el
    // resto del producto ya llegó a destino y no debe repetirse.
    const chats = esReanudacion
      ? chatsValidos.filter((c) => logIdPorPar.has(`${idProd}|${c}`))
      : chatsValidos;
    if (chats.length === 0) return null;
    // Filas de log. Al reanudar se reutilizan las existentes (así la tanda
    // original se completa en vez de duplicarse) y se devuelven a
    // `pendiente` para que la UI muestre el progreso vivo.
    let logIds: Array<number | null>;
    if (esReanudacion) {
      logIds = chats.map((c) => logIdPorPar.get(`${idProd}|${c}`) ?? null);
      const aReiniciar = logIds.filter((v): v is number => v != null);
      if (aReiniciar.length > 0) {
        await admin.from("app_wapi_envio_log")
          .update({ estado: "pendiente", error_code: null, error_message: null })
          .in("id", aReiniciar);
      }
    } else {
      const filas = chats.map((c) => ({
        id_tienda: idTienda,
        id_sesion: idSesion,
        id_programacion: idProgramacion ?? null,
        id_producto: idProd,
        chat_id: c,
        tipo_envio: tipoEnvio,
        estado: "pendiente",
      }));
      const { data: insertados, error: logErr } = await admin
        .from("app_wapi_envio_log")
        .insert(filas)
        .select("id");
      if (logErr) {
        // Sin log el envío seguiría funcionando, pero la UI no vería nada:
        // preferimos avisar y continuar sin logId antes que abortar el chunk.
        console.error(
          `[wapi-send-products] no se pudo registrar el log del producto ` +
            `${idProd}: ${logErr.message}`,
        );
      }
      logIds = chats.map((_, i) => (insertados ?? [])[i]?.id ?? null);
    }

    return chats.map((c, i) => ({
      idProducto: idProd,
      chatId: c,
      url: imageUrl,
      caption,
      mimetype,
      logId: logIds[i] ?? null,
    }));
  };

  console.log(
    `[wapi-send-products] batchId=${batchId} session=${wapiSessionId} ` +
      `productos=${effProductIds.length} destinos=${chatsValidos.length} ` +
      `delay=[${minMs / 1000}s..${maxMs / 1000}s] fanout=serie ` +
      `presupuesto=${Math.round(WORKER_BUDGET_MS / 1000)}s` +
      (esReanudacion ? " modo=reanudar" : ""),
  );
  /** Resultado de un envío. `pacing` significa "WAPI pide una pausa que no
   *  cabe en este worker": el chunk se corta y lo pendiente se reanuda. */
  type EnvioResultado = { ok: boolean; pacing?: { retryAfterSeconds: number } };

  // Dispara UN mensaje y actualiza su fila de log.
  //
  // Reintenta hasta RETRY_MAX_ATTEMPTS con backoff exponencial + jitter
  // mientras el error sea transitorio. El backoff también funciona como
  // anti-ban: si la sesión WAPI está rechazando conexiones, insistir de
  // inmediato sólo empeora las cosas.
  const dispatchOne = async (e: Envio): Promise<EnvioResultado> => {
    let ultimoCode = "SEND_ERROR";
    let ultimoMsg = "Error desconocido";

    for (let intento = 1; intento <= RETRY_MAX_ATTEMPTS; intento++) {
      const single = await wapi.sendImage(
        wapiSessionId,
        e.chatId,
        e.url,
        e.caption,
        e.mimetype,
      );

      if (single.success) {
        if (e.logId) {
          await admin.from("app_wapi_envio_log")
            .update({
              estado: "enviado",
              sent_at: new Date().toISOString(),
              mensaje_id: single.data?.messageId ?? null,
              // Limpiamos rastros de intentos previos: si acabó enviándose,
              // el error anterior ya no describe el estado de la fila.
              error_code: null,
              error_message: intento > 1
                ? `Enviado tras ${intento} intentos`
                : null,
            })
            .eq("id", e.logId);
        }
        if (intento > 1) {
          console.log(
            `[wapi-send-products] recuperado prod=${e.idProducto} ` +
              `chat=${e.chatId} en el intento ${intento}`,
          );
        }
        return { ok: true };
      }

      ultimoCode = single.error?.code ?? "SEND_ERROR";
      ultimoMsg = single.error?.message ?? "Error desconocido";
      // ── 429 con pausa pedida por el server ─────────────────────────────
      // Dos casos, ambos con `retryAfterSeconds`: el rate limiter genérico
      // y el SEND_PACING (breaker por fallos consecutivos). Insistir antes
      // del plazo sólo alarga el cooldown, así que se respeta o se corta.
      const pidePausaSeg = single.error?.retryAfterSeconds ??
        (ultimoCode === "SEND_PACING_LIMITED" ? 60 : undefined);
      if (pidePausaSeg && pidePausaSeg > 0) {
        const esperaMs = pidePausaSeg * 1000;
        const cabe = intento < RETRY_MAX_ATTEMPTS &&
          esperaMs <= PACING_WAIT_MAX_MS &&
          elapsed() + esperaMs + 20_000 < WORKER_BUDGET_MS;
        console.error(
          `[wapi-send-products] prod=${e.idProducto} chat=${e.chatId} ` +
            `${ultimoCode}: el server pide ${pidePausaSeg}s` +
            (cabe ? " — esperando" : " — se corta el chunk y se reanuda luego"),
        );
        if (!cabe) {
          // El log queda en `pendiente` a propósito: es trabajo por hacer,
          // no un fallo. La reanudación lo recogerá.
          return { ok: false, pacing: { retryAfterSeconds: pidePausaSeg } };
        }
        await new Promise((res) => setTimeout(res, esperaMs));
        continue;
      }

      // ── Backoff normal ────────────────────────────────────────────────
      const backoffMs = RETRY_BASE_MS * Math.pow(2, intento - 1);
      // No arrancar una espera que nos va a dejar sin worker: más vale
      // marcar el fallo ya y dejar que el resto del chunk siga.
      const sinTiempo = elapsed() + backoffMs + 15_000 >= WORKER_BUDGET_MS;
      const puedeReintentar = intento < RETRY_MAX_ATTEMPTS &&
        esReintentable(ultimoCode) && !sinTiempo;
      console.error(
        `[wapi-send-products] fallido prod=${e.idProducto} chat=${e.chatId} ` +
          `intento ${intento}/${RETRY_MAX_ATTEMPTS} (${ultimoCode}): ${ultimoMsg}` +
          (puedeReintentar
            ? " — reintentando"
            : sinTiempo
            ? " — sin presupuesto para reintentar"
            : ""),
      );
      if (!puedeReintentar) break;

      // Backoff exponencial (4s, 8s…) con jitter ±25% para no sincronizar
      // los reintentos contra el mismo instante.
      await new Promise((res) =>
        setTimeout(res, Math.round(backoffMs * (0.75 + Math.random() * 0.5)))
      );
    }

    if (e.logId) {
      await admin.from("app_wapi_envio_log")
        .update({
          estado: "fallido",
          error_code: ultimoCode,
          error_message: `${ultimoMsg} (tras ${RETRY_MAX_ATTEMPTS} intentos)`,
        })
        .eq("id", e.logId);
    }
    return { ok: false };
  };

  // ── BUCLE PRINCIPAL ──────────────────────────────────────────────────
  // Un producto a la vez y, dentro de cada producto, un destino a la vez.
  // Antes de cada producto se comprueba si CABE en lo que queda de worker;
  // si no cabe, el resto se corta y se encola en un worker nuevo.
  let ventanaFin = 0;
  for (let i = 0; i < effProductIds.length; i++) {
    const sinPresupuesto = productosDespachados > 0
      ? elapsed() + reservaProductoMs() > WORKER_BUDGET_MS
      : elapsed() > WORKER_BUDGET_MS; // el primero siempre se intenta
    if (sinPresupuesto) {
      remainingIds = effProductIds.slice(i);
      console.log(
        `[wapi-send-products] corte por presupuesto a los ` +
          `${Math.round(elapsed() / 1000)}s: ${productosDespachados} ok, ` +
          `${remainingIds.length} para el worker siguiente`,
      );
      break;
    }
    // Precarga por ventanas: una consulta cada WINDOW_SIZE productos, en vez
    // de una por producto (lento) o una sola gigante (se trunca).
    if (i >= ventanaFin) {
      const fin = Math.min(effProductIds.length, i + WINDOW_SIZE);
      await ensureInfo(effProductIds.slice(i, fin));
      ventanaFin = fin;
    }
    const idProd = effProductIds[i];
    const envios = await prepararProducto(idProd);
    if (!envios || envios.length === 0) continue;

    const inicioProducto = Date.now();
    let corteDeProducto = false;
    // EN SERIE: la sesión WAPI es UNA instancia de Puppeteer. Dos envíos
    // simultáneos se pisan y devuelven NETWORK_ERROR — por eso a un solo
    // grupo iba perfecto y a cuatro se caía la mitad.
    for (let k = 0; k < envios.length; k++) {
      const r = await dispatchOne(envios[k]);
      mensajesIntentados++;
      if (r.ok) enviados++;
      else if (!r.pacing) fallidos++;
      if (r.pacing) {
        // WAPI pide una pausa larga: cortar aquí y reanudar más tarde.
        pacingAbort = r.pacing;
        remainingIds = effProductIds.slice(i + 1);
        corteDeProducto = true;
        break;
      }
      // Guarda-raíl por producto: si UN producto se está comiendo el worker
      // (imagen enorme, sesión pesada), se abandonan sus destinos restantes
      // en vez de arrastrar toda la cadena. Quedan como `fallido`, así que
      // el botón "reanudar" de la app los recoge.
      const excedido = Date.now() - inicioProducto > PRODUCT_MAX_MS ||
        elapsed() > WORKER_BUDGET_MS;
      if (excedido && k < envios.length - 1) {
        const restantes = envios.slice(k + 1);
        const logs = restantes
          .map((x) => x.logId)
          .filter((v): v is number => v != null);
        if (logs.length > 0) {
          await admin.from("app_wapi_envio_log")
            .update({
              estado: "fallido",
              error_code: "PRODUCT_TIMEOUT",
              error_message:
                `Producto abandonado tras ${Math.round((Date.now() - inicioProducto) / 1000)}s`,
            })
            .in("id", logs);
        }
        fallidos += restantes.length;
        console.warn(
          `[wapi-send-products] prod=${idProd} agotó su ventana: ` +
            `${restantes.length} destino(s) sin enviar`,
        );
        corteDeProducto = true;
        break;
      }
      // Pausa corta entre destinos del mismo producto: da margen a que la
      // sesión libere el envío anterior y evita ráfagas contra el limiter.
      if (k < envios.length - 1) {
        await new Promise((res) => setTimeout(res, FANOUT_PAUSE_MS));
      }
    }

    // Coste real del producto: alimenta `reservaProductoMs()` para que la
    // decisión de cortar use medidas de ESTE envío, no una estimación fija.
    peorEnvioMs = Math.max(peorEnvioMs, Date.now() - inicioProducto);
    productosDespachados++;
    if (pacingAbort) break;

    // Delay aleatorio entre productos (anti-ban). No tras el último, ni si
    // no cabe: mejor guardar el tiempo para encolar la continuación.
    if (i < effProductIds.length - 1 && !corteDeProducto) {
      const jitter = minMs + Math.floor(Math.random() * (maxMs - minMs));
      if (elapsed() + jitter < WORKER_BUDGET_MS) {
        await new Promise((res) => setTimeout(res, jitter));
      }
    }
  }

  // ── CIERRE ───────────────────────────────────────────────────────────
  // ORDEN CRÍTICO: primero la continuación, después el resumen. Al revés,
  // si el resumen se come lo que queda de worker la cadena muere y los
  // productos restantes no se envían nunca (era el bug de los 4 grupos).
  let continuacionOk = false;
  if (pacingAbort) {
    // WAPI está en cooldown: encadenar sería chocar con el mismo 429 desde
    // un worker nuevo. Se registran los pendientes para reanudar después.
    console.warn(
      `[wapi-send-products] cortado por pacing ` +
        `(${pacingAbort.retryAfterSeconds}s): ${remainingIds.length} ` +
        `producto(s) quedan pendientes de reanudar`,
    );
    await registrarPendientes(remainingIds);
  } else if (remainingIds.length > 0) {
    continuacionOk = await reinvokeRemaining();
    if (!continuacionOk) await registrarPendientes(remainingIds);
  }

  // El resumen sólo lo manda el ÚLTIMO chunk de la cadena. `cerrarConResumen`
  // decide por sí mismo si le cabe aquí o lo delega a un worker nuevo.
  const esUltimoChunk = remainingIds.length === 0 && !pacingAbort;
  const resumenEntregas = esUltimoChunk ? await cerrarConResumen() : 0;

  console.log(
    `[wapi-send-products] chunk cerrado en ${Math.round(elapsed() / 1000)}s: ` +
      `${productosDespachados} producto(s), ${mensajesIntentados} mensaje(s) ` +
      `(${enviados} ok / ${fallidos} fallidos), ${skipped.length} descartado(s), ` +
      `restan ${remainingIds.length}`,
  );

  return {
    enviados,
    fallidos,
    batch_id: batchId,
    mode: "serie-por-producto",
    destinos: chatsValidos.length,
    chunk_size: productosDespachados,
    mensajes: mensajesIntentados,
    skipped,
    remaining: remainingIds.length,
    continuacion_encolada: continuacionOk,
    ...(pacingAbort
      ? { pacing_retry_after_seconds: pacingAbort.retryAfterSeconds }
      : {}),
    resumen_entregas: resumenEntregas,
  };
}

// El handler está extraído como función nombrada para que otros módulos
// puedan importarlo SIN que se registre un Deno.serve secundario en el
// mismo proceso. Sólo el bloque `if (import.meta.main)` al final del
// archivo registra el listener — y eso sólo ocurre cuando este archivo
// es el entry-point de la edge function, no cuando lo importa otro.
export async function handleSendProducts(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return handleOptions();
  if (req.method !== "POST") return errorResponse("Method not allowed", 405);

  // Service-role bypass (usado por wapi-cron-dispatch internamente)
  const fromService = isServiceRoleCall(req);
  let ctx: AuthContext | null = null;
  if (!fromService) {
    ctx = await getAuthContext(req);
    if (!ctx) return errorResponse("No autenticado", 401);
  }

  let body: SendBody;
  try { body = await req.json(); } catch {
    return errorResponse("JSON inválido", 400);
  }

  const idSesion = Number(body.id_sesion);
  const productIds = Array.isArray(body.product_ids)
    ? body.product_ids.map(Number).filter((n) => Number.isFinite(n))
    : [];
  const destinations = Array.isArray(body.destinations) ? body.destinations : [];
  const resumeLogIds = Array.isArray(body.resume_log_ids)
    ? body.resume_log_ids.map(Number).filter((n) => Number.isFinite(n))
    : [];
  const esReanudacion = resumeLogIds.length > 0;
  // Invocación interna que sólo manda el resumen (la lanza el último chunk
  // cuando no le queda worker para el texto). Ver `SendBody.summary_only`.
  const soloResumen = body.summary_only === true;
  const summaryProductIds = Array.isArray(body.summary_product_ids)
    ? body.summary_product_ids.map(Number).filter((n) => Number.isFinite(n))
    : [];

  // Al reanudar, product_ids/destinations se derivan de los propios logs, así
  // que sólo exigimos id_sesion + la lista de logs a reintentar.
  if (!Number.isFinite(idSesion)) {
    return errorResponse("id_sesion es obligatorio", 400);
  }
  if (soloResumen) {
    if (destinations.length === 0 || summaryProductIds.length === 0) {
      return errorResponse(
        "summary_only requiere destinations[] y summary_product_ids[]",
        400,
      );
    }
  } else if (
    !esReanudacion && (productIds.length === 0 || destinations.length === 0)
  ) {
    return errorResponse(
      "id_sesion, product_ids[] y destinations[] son obligatorios",
      400,
    );
  }

  const admin = serviceClient();

  const { data: ses, error } = await admin
    .from("app_wapi_sesion").select("*").eq("id", idSesion).maybeSingle();
  if (error || !ses) return errorResponse("Sesión no encontrada", 404);

  if (ctx && !(await assertStoreAccess(ctx, ses.id_tienda))) {
    return errorResponse("Sin acceso a la tienda", 403);
  }
  if (ses.status !== "CONNECTED") {
    return errorResponse("La sesión no está conectada a WhatsApp", 409, "NOT_CONNECTED");
  }

  const delayMin = Math.max(5, Number(body.delay_min_seconds ?? 5));
  const delayMax = Math.max(delayMin + 1, Number(body.delay_max_seconds ?? 10));

  // Fire-and-forget: el envío puede tardar varios minutos (delays anti-ban
  // entre mensajes). Respondemos inmediatamente al cliente y procesamos el
  // batch en segundo plano vía EdgeRuntime.waitUntil(). El usuario podrá
  // seguir trabajando en la app y revisar el progreso en el historial.
  const totalMensajes = soloResumen
    ? summaryProductIds.length
    : esReanudacion
    ? resumeLogIds.length
    : productIds.length * destinations.length;
  // El envío es EN SERIE por destino, con un delay aleatorio entre productos.
  // Estimado ≈ (nº productos - 1) × delay medio + el tiempo de los envíos.
  const productosEstimados = esReanudacion
    ? Math.max(1, Math.ceil(resumeLogIds.length / Math.max(1, destinations.length)))
    : productIds.length;
  const estimadoSeg = soloResumen ? 30 : Math.round(
    Math.max(0, productosEstimados - 1) * ((delayMin + delayMax) / 2) +
      productosEstimados * Math.max(1, destinations.length) * 7,
  );

  const job = dispatchProducts({
    admin,
    idSesion: ses.id,
    idTienda: ses.id_tienda,
    wapiSessionId: ses.wapi_session_id,
    productIds,
    destinations,
    template: body.message_template,
    delayMin,
    delayMax,
    tipoEnvio: body.tipo_envio ?? "manual",
    idProgramacion: body.id_programacion,
    enviarResumen: soloResumen ? true : (body.send_summary ?? true),
    ...(soloResumen ? { summaryOnly: true } : {}),
    ...(summaryProductIds.length > 0
      ? { summaryProductIds }
      : {}),
    ...(esReanudacion ? { resumeLogIds } : {}),
  }).catch((err) => {
    console.error(
      `[wapi-send-products] background dispatch falló: ${(err as Error).message ?? err}`,
    );
  });

  // EdgeRuntime es propio de Supabase Edge Functions / Deno Deploy.
  // @ts-ignore — no está en los typings de Deno pero existe en runtime.
  if (typeof EdgeRuntime !== "undefined") {
    // @ts-ignore
    EdgeRuntime.waitUntil(job);
  } else {
    // Fallback (entorno local sin EdgeRuntime): no esperamos, dejamos correr.
    // Nota: en `deno run` plano la promise se interrumpe al terminar el handler.
    void job;
  }

  return okResponse({
    queued: true,
    resumed: esReanudacion,
    summary_only: soloResumen,
    total_mensajes_estimados: totalMensajes,
    tiempo_estimado_segundos: estimadoSeg,
    delay_segundos: { min: delayMin, max: delayMax },
    message: soloResumen
      ? `Resumen en cola (${summaryProductIds.length} producto(s)).`
      : esReanudacion
      ? `Reanudando envío: ${totalMensajes} mensaje(s) pendientes. ` +
        `Tiempo estimado: ~${Math.max(1, Math.ceil(estimadoSeg / 60))} min. ` +
        `Revisa el historial para ver el progreso.`
      : `Envío iniciado en segundo plano. ${totalMensajes} mensajes en cola. ` +
        `Tiempo estimado: ~${Math.max(1, Math.ceil(estimadoSeg / 60))} min. ` +
        `Puedes seguir usando la app — revisa el historial para ver el progreso.`,
  });
}

// Sólo registrar el listener cuando este archivo es el entry-point real
// de la edge function (i.e. está siendo servido como `/wapi-send-products`).
// Si algún otro módulo llegara a importar `dispatchProducts` o
// `handleSendProducts`, `import.meta.main` es false y NO se registra el
// listener — así evitamos que un Deno.serve fantasma intercepte requests
// destinadas a la otra función. (Hoy nadie lo importa: `wapi-cron-dispatch`
// delega por HTTP para conseguir un worker con presupuesto fresco.)
if (import.meta.main) {
  Deno.serve(handleSendProducts);
}
