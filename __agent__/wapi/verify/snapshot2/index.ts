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
// Estrategia de envío actual (ORDEN POR DESTINO):
//   1. Los destinatarios se atienden UNO DETRÁS DE OTRO: primero se manda a un
//      grupo TODOS los productos de la tanda, en el mismo orden, y sólo cuando
//      ese grupo está completo se pasa al siguiente. Antes el bucle era por
//      producto (todos los grupos veían el producto k, luego el k+1): con un
//      grupo lento, el guarda-raíl por producto abandonaba a los demás a
//      medias, así que unos grupos recibían el catálogo y otros no. Eso era el
//      "caos entre grupos".
//   2. Dentro de un destino: delay aleatorio en [delay_min, delay_max] entre
//      mensaje y mensaje. Entre destinos: una pausa fija más larga.
//   3. Todo EN SERIE: la sesión de WAPI es UNA sola instancia de Puppeteer;
//      dos envíos simultáneos se pisan y devuelven NETWORK_ERROR.
//   4. Defaults 5–10s: el ritmo real queda holgadamente por debajo del techo
//      recomendado de 20 msgs/min/sesión.
//
// IDEMPOTENCIA (OpenWA 0.25.0+): cada mensaje viaja con `Idempotency-Key`
// derivada de su fila de log (`wa-log-<id>`), estable entre reintentos y entre
// reanudaciones. Eso hace que reintentar NUNCA duplique el mensaje, y permite
// tratar `IDEMPOTENCY_KEY_IN_PROGRESS` / `IDEMPOTENCY_OUTCOME_UNKNOWN` como
// "todavía no sé el resultado" (se espera y se reintenta con la MISMA clave;
// OpenWA devuelve la respuesta guardada) en vez de marcarlos `fallido` cuando
// el mensaje probablemente SÍ salió.
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
import { isSessionSendable, normalizeWapiStatus } from "../_shared/status.ts";
import { runRecovery } from "../_shared/session_recovery.ts";
import { updateSessionState } from "../_shared/session_store.ts";

interface Destino {
  tipo: "numero" | "grupo";
  chat_id: string;
  etiqueta?: string;
}

/** Un mensaje concreto del plan: un producto para un destino. */
interface Par {
  idProducto: number;
  chatId: string;
}

/** Clave de `Par` para los mapas en memoria (`producto|chat`). */
function clavePar(p: Par): string {
  return `${p.idProducto}|${p.chatId}`;
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
 * Esperas extra cuando OpenWA responde "la petición con esta clave sigue en
 * vuelo" (`IDEMPOTENCY_KEY_IN_PROGRESS`). NO es un fallo: el mensaje puede
 * estar saliendo en este momento. Hay que darle tiempo a terminar y volver a
 * preguntar con la MISMA clave — cuando acabe, OpenWA reproduce la respuesta
 * guardada y nos da el `messageId` real. Marcarlo `fallido` (lo que se hacía
 * antes al 2º intento) producía falsos negativos: el mensaje llegaba al grupo
 * y en el historial aparecía como fallido.
 */
const IDEM_MAX_ESPERAS = 4;
const IDEM_ESPERA_BASE_MS = 12_000;
const IDEM_ESPERA_MAX_MS = 45_000;

/**
 * Techo de reloj para UN mensaje contando todos sus reintentos y esperas. Si
 * un destino se atasca (Puppeteer colgado) no se abandona el envío entero: se
 * deja ESE mensaje en `pendiente` —reanudable, y sin riesgo de duplicado
 * gracias a la clave de idempotencia— y se sigue con el resto del grupo.
 */
const MENSAJE_MAX_MS = 150_000;

/**
 * Fallos consecutivos contra un mismo destino antes de saltárselo. Un grupo
 * caído (o que ya no existe) no puede consumir el presupuesto de los demás.
 * Sus mensajes quedan `pendiente` con el motivo, para reanudar cuando se
 * arregle.
 */
const DESTINO_FALLOS_MAX = 3;

/** Pausa al cambiar de grupo: no se encadenan grupos uno tras otro en seco. */
const ENTRE_DESTINOS_MS = 20_000;

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

/**
 * ¿El error significa "la sesión de OpenWA se cayó / está caída"?
 *
 * Dos familias observadas en producción (4,995 filas `fallido`):
 *   · HTTP_409 "Session is not connected. The WhatsApp client is not ready."
 *     y el 409 "WhatsApp Web is reloading its page and the session is
 *     re-injecting. Retry in a few seconds."
 *   · HTTP_400 "Session '<uuid>' is not active. Start the session first."
 *
 * Antes esto se trataba como un fallo transitorio cualquiera: 3 reintentos con
 * backoff, fila `fallido`, y a la siguiente. Así se llenaba el historial de
 * fallos y nadie reiniciaba la sesión. Ahora dispara la escalera de
 * recuperación (ver `dispatchOne`).
 */
function esErrorDeSesion(code: string | undefined, message: string | undefined): boolean {
  const m = (message ?? "").toLowerCase();
  const sesion =
    m.includes("not connected") || m.includes("not ready") ||
    m.includes("is not active") || m.includes("start the session") ||
    m.includes("session is not") || m.includes("session not found") ||
    m.includes("is re-injecting") || m.includes("reloading its page");
  if (!sesion) return false;
  if (code === "HTTP_400" || code === "HTTP_409" || code === "HTTP_404") return true;
  // Algunas builds envuelven el 409 en un 500.
  return code === "HTTP_500";
}

/**
 * ¿El error dice "tu clave de idempotencia sigue en vuelo"?
 *
 * OpenWA responde `409 IDEMPOTENCY_KEY_IN_PROGRESS` cuando llega una petición
 * con una clave cuya primera petición todavía se está ejecutando. Suele pasar
 * porque NUESTRO cliente abortó por timeout mientras el servidor seguía
 * trabajando: el reintento inmediato con la misma clave choca con la original.
 *
 * Correcto: esperar y reintentar con la MISMA clave. La primera petición acaba
 * guardando su resultado y la siguiente reproducción de la clave devuelve el
 * `messageId` real (o el error real), sin mandar el mensaje dos veces.
 */
function esIdemEnProgreso(code: string | undefined, message: string | undefined): boolean {
  if (code === "IDEMPOTENCY_KEY_IN_PROGRESS") return true;
  const m = (message ?? "").toLowerCase();
  return m.includes("is still running") ||
    (m.includes("idempotency-key") && m.includes("retry after"));
}

/**
 * ¿El error dice "una petición anterior con esta clave falló y el mensaje
 * PUEDE haberse enviado"? (`IDEMPOTENCY_OUTCOME_UNKNOWN`.)
 *
 * Tampoco es un `fallido` honesto: no sabemos si salió. Reintentar con la
 * misma clave es la única forma de averiguarlo sin arriesgar un duplicado.
 */
function esIdemResultadoDesconocido(
  code: string | undefined,
  message: string | undefined,
): boolean {
  if (code === "IDEMPOTENCY_OUTCOME_UNKNOWN") return true;
  const m = (message ?? "").toLowerCase();
  return m.includes("may have been sent");
}

/** Hash estable (FNV-1a) para construir claves de idempotencia. */
function fnv1a(texto: string): string {
  let h = 0x811c9dc5;
  for (let i = 0; i < texto.length; i++) {
    h ^= texto.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h.toString(36);
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
  // Clave de idempotencia estable por (destino, contenido): si un TIMEOUT
  // provocó un reintento y el mensaje ya había salido, OpenWA devuelve el mismo
  // mensaje en vez de mandar el resumen dos veces. Como la clave incluye el
  // texto, un resumen con precios/stock distintos SÍ se vuelve a mandar.
  const idemKey = `wa-sum-${chatId}-${fnv1a(text)}`;
  for (let intento = 1; intento <= RETRY_MAX_ATTEMPTS; intento++) {
    const r = await wapi.sendText(wapiSessionId, chatId, text, idemKey);
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
  /**
   * Fila de `app_wapi_sesion`. La necesita la rama de recuperación de
   * `dispatchOne` (`last_recovery_at`, `recovery_attempts`, `id`).
   *
   * Antes NO se pasaba y esa rama lanzaba `ReferenceError: ses is not defined`,
   * matando el worker justo cuando la sesión se caía: los mensajes que quedaban
   * en la tanda nunca se despachaban ni se registraban (se veía como tanda
   * "interrumpida" sin motivo).
   */
  ses: {
    id: number;
    last_recovery_at?: string | null;
    recovery_attempts?: number | null;
  };
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
    resumeLogIds, ses,
  } = args;
  const enviarResumen = args.enviarResumen ?? true;
  const summaryOnly = args.summaryOnly === true;

  // ── MODO REANUDAR ───────────────────────────────────────────────────
  // Reconstruimos productos y destinos a partir de las filas de log que
  // quedaron sin enviar, y guardamos el mapa (producto, chat) → logId para
  // reutilizar esas filas en vez de insertar duplicados.
  const esReanudacion = Array.isArray(resumeLogIds) && resumeLogIds.length > 0;
  const logIdPorPar = new Map<string, number>();
  /**
   * `producto|chat` → id de su fila en `app_wapi_envio_log`, para TODO par que
   * ya tenga fila (reanudada o creada por `prepararProducto`). Evita insertar
   * duplicados cuando hay que registrar como pendientes los mensajes que un
   * corte dejó fuera.
   */
  const logIdDePar = new Map<string, number>();
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
      if (!logIdPorPar.has(key)) {
        logIdPorPar.set(key, Number((row as any).id));
        logIdDePar.set(key, Number((row as any).id));
      }
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

    // ── ORDEN CANÓNICO AL REANUDAR ──────────────────────────────────────
    // El orden de los pares se reconstruye desde los logs, pero el `id` de las
    // filas NO refleja el orden destino-mayor: durante el envío las filas se
    // insertan por producto. Sin corregirlo, el grupo que se estaba sirviendo
    // cuando se cortó el chunk pasaba al FINAL de la cadena, y el "un grupo
    // detrás de otro" se degradaba en cada corte.
    //
    // La petición sí trae el orden bueno:
    //   · `destinations` — la continuación hereda `effDestinations` del worker
    //     anterior (la reanudación manual desde la app manda `[]`).
    //   · `summary_product_ids` — la cadena lo hereda COMPLETO desde el primer
    //     chunk, así que sirve de orden canónico de productos.
    // Si no llegan (reanudación manual sin ellos) se cae al orden de los logs,
    // que es el comportamiento anterior.
    const ordenDestinos = destinations
      .map((d) => String(d.chat_id ?? "").trim())
      .filter((c) => c.length > 0);
    if (ordenDestinos.length > 0) {
      const posDestino = new Map<string, number>();
      ordenDestinos.forEach((c, i) => {
        if (!posDestino.has(c)) posDestino.set(c, i);
      });
      const ultimo = Number.MAX_SAFE_INTEGER;
      effDestinations = Array.from(chats.values()).sort(
        (a, b) =>
          (posDestino.get(a.chat_id) ?? ultimo) -
          (posDestino.get(b.chat_id) ?? ultimo),
      );
    } else {
      effDestinations = Array.from(chats.values());
    }

    const ordenProductos = (args.summaryProductIds ?? [])
      .map((n) => Number(n))
      .filter((n) => Number.isFinite(n));
    if (ordenProductos.length > 0) {
      const posProducto = new Map<number, number>();
      ordenProductos.forEach((id, i) => {
        if (!posProducto.has(id)) posProducto.set(id, i);
      });
      const ultimo = Number.MAX_SAFE_INTEGER;
      effProductIds = [...ordenProd].sort(
        (a, b) =>
          (posProducto.get(a) ?? ultimo) - (posProducto.get(b) ?? ultimo),
      );
    } else {
      effProductIds = ordenProd;
    }
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
  /** Pausa entre mensajes del MISMO destino. El grueso del ritmo anti-ban lo
   *  pone el delay aleatorio [delay_min, delay_max]; esta pausa es el suelo
   *  mínimo para que la sesión de Puppeteer libere el envío anterior. */
  const FANOUT_PAUSE_MS = 1_500;
  /** Techo por MENSAJE (ya no por producto): si un destino se atasca, se deja
   *  ESE mensaje en `pendiente` —reanudable y sin riesgo de duplicado— y se
   *  sigue con el resto del grupo. Antes se abandonaban a mitad los demás
   *  destinos del producto y quedaban `fallido` SIN haberse intentado. */
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
  /** Estimación inicial del coste de UN mensaje, sin el delay anti-ban: ~5s de
   *  envío. Con la latencia real observada (hasta 40s por imagen) se queda
   *  corta, pero se corrige en cuanto se mide el primer envío (`peorEnvioMs`),
   *  y la decisión de cortar se toma con el reloj, no con esta estimación. */
  const envioEstimadoMs = 5_000;
  let peorEnvioMs = 0;
  /** Hueco que debe quedar libre para arrancar otro MENSAJE: lo peor visto
   *  (+20%) más el delay anti-ban. Se topa a medio presupuesto para que un
   *  único mensaje lentísimo no reduzca los chunks a un mensaje cada uno. */
  const reservaMensajeMs = () =>
    Math.min(
      WORKER_BUDGET_MS / 2,
      Math.max(envioEstimadoMs, peorEnvioMs * 1.2) + avgDelayMs,
    );

  // ── PLAN DE ENVÍO: ORDEN POR DESTINO ────────────────────────────────
  //
  // `plan` es la lista ORDENADA de mensajes a despachar: primero TODOS los
  // productos del primer destino, después todos los del segundo, y así. Cada
  // grupo recibe su catálogo completo y en el mismo orden; un grupo lento ya
  // no deja a los demás a medias. Ese era el "caos entre grupos": el bucle
  // anterior era por producto, y el guarda-raíl por producto abandonaba a
  // mitad los destinos que faltaban.
  //
  // Al reanudar sólo entran los pares que quedaron sin enviar, así que el plan
  // es siempre exactamente "lo que falta".
  const plan: Par[] = [];
  for (const chatId of chatsValidos) {
    for (const idProd of effProductIds) {
      const par: Par = { idProducto: idProd, chatId };
      if (esReanudacion && !logIdPorPar.has(clavePar(par))) continue;
      plan.push(par);
    }
  }

  /** Mensajes que este worker no alcanzará (corte por presupuesto). Los lee
   *  `reinvokeRemaining` justo antes de encolar la continuación. */
  let remainingPares: Par[] = [];
  /** Mensajes de un destino que se saltó por fallos consecutivos: quedan
   *  `pendiente` para reanudar a mano, pero NO se encadenan — volverían a
   *  fallar y sólo gastarían workers. */
  let saltadosPares: Par[] = [];
  /** Si WAPI pidió frenar, aquí queda la espera que exigió. */
  let pacingAbort: { retryAfterSeconds: number } | null = null;

  // Re-invoca wapi-send-products con los mensajes que NO caben en este chunk.
  // Fire-and-forget: el endpoint responde de inmediato (queued) y procesa el
  // siguiente chunk en su propio background task con 400s frescos.
  //
  // Se encola por `resume_log_ids` (no por `product_ids`): así la continuación
  // retoma EXACTAMENTE donde se cortó, conservando el orden por destino, en vez
  // de reconstruir el trozo desde la lista de productos.
  //
  // IMPORTANTE: idempotencia. `reinvokeRemaining` sólo debe encolar UNA vez por
  // worker; si se llama dos veces (p.ej. en el early-fire y otra vez al final
  // por una ruta de error), duplicaría el chunk restante. Un flag lo evita.
  let reinvoked = false;
  const reinvokeRemaining = async (logIds: number[]): Promise<boolean> => {
    if (logIds.length === 0 || reinvoked) return false;
    reinvoked = true;

    const payload = {
      id_sesion: idSesion,
      product_ids: Array.from(new Set(remainingPares.map((p) => p.idProducto))),
      destinations: effDestinations,
      resume_log_ids: logIds,
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
          `${logIds.length} mensaje(s) restantes`,
      );
    } else {
      console.error(
        `[wapi-send-products] CADENA ROTA: ${logIds.length} mensaje(s) ` +
          `quedan sin despachar (${res.error ?? "motivo desconocido"})`,
      );
    }
    return res.ok;
  };

  /**
   * Asegura que cada mensaje del plan tenga su fila en `app_wapi_envio_log`.
   * Dos usos:
   *
   *   · corte por presupuesto → hay que registrar los mensajes que ni siquiera
   *     se prepararon, porque la continuación se guía por logIds.
   *   · destino saltado o mensaje atascado → la fila queda `pendiente` con el
   *     motivo, lista para el botón "reanudar" de la app.
   *
   * Es idempotente: reutiliza las filas ya existentes (de una reanudación o de
   * `prepararProducto`) y sólo inserta las que falten, así que nunca duplica la
   * tanda. Devuelve los ids de las filas implicadas.
   */
  const registrarPendientesPares = async (
    pares: Par[],
    motivo?: { code: string; message: string },
  ): Promise<{ ids: number[]; ok: boolean }> => {
    if (pares.length === 0 || chatsValidos.length === 0) {
      return { ids: [], ok: true };
    }

    const implicados = new Set<number>();
    // Deduplicado por par: si la petición repitiera un producto, sin esto se
    // insertarían DOS filas del mismo (producto, chat) y la segunda quedaría
    // `pendiente` para siempre — la reanudación conserva el primer log y la
    // tanda se vería "interrumpida" sin poder avanzar nunca.
    const faltantes = new Map<string, Par>();
    for (const par of pares) {
      const clave = clavePar(par);
      const id = logIdDePar.get(clave);
      if (id != null) implicados.add(id);
      else faltantes.set(clave, par);
    }

    let ok = true;
    if (faltantes.size > 0) {
      const filas = Array.from(faltantes.values()).map((p) => ({
        id_tienda: idTienda,
        id_sesion: idSesion,
        id_programacion: idProgramacion ?? null,
        id_producto: p.idProducto,
        chat_id: p.chatId,
        tipo_envio: tipoEnvio,
        estado: "pendiente",
      }));
      try {
        for (const lote of chunkArray(filas, 500)) {
          const { data, error } = await admin
            .from("app_wapi_envio_log")
            .insert(lote)
            .select("id, id_producto, chat_id");
          if (error) throw new Error(error.message);
          for (const row of data ?? []) {
            const par: Par = {
              idProducto: Number((row as any).id_producto),
              chatId: String((row as any).chat_id),
            };
            const id = Number((row as any).id);
            logIdDePar.set(clavePar(par), id);
            implicados.add(id);
          }
        }
      } catch (e) {
        // CRÍTICO: si el insert falla, estos mensajes se despacharán SIN fila
        // de log y SIN `Idempotency-Key` (`logId` null) → invisibles en el
        // historial y no reanudables. Además la continuación, que se guía por
        // logIds, se quedaría sin ellos. Hay que decirlo ALTO.
        ok = false;
        console.error(
          `[wapi-send-products] FALLO al registrar ${faltantes.size} ` +
            `mensaje(s) pendientes: ${(e as Error).message ?? e}. Se ` +
            `despacharían SIN fila ni clave de idempotencia.`,
        );
      }
      // Si algún par se ha quedado sin fila, la operación no está completa.
      for (const clave of faltantes.keys()) {
        if (!logIdDePar.has(clave)) {
          ok = false;
          break;
        }
      }
    }

    const ids = Array.from(implicados);
    if (motivo && ids.length > 0) {
      for (const lote of chunkArray(ids, 500)) {
        await admin.from("app_wapi_envio_log")
          .update({
            estado: "pendiente",
            error_code: motivo.code,
            error_message: motivo.message,
          })
          .in("id", lote);
      }
    }
    return { ids, ok };
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

  /** Producto validado y listo, con sus destinos y sus filas de log. */
  type ProductoListo = {
    idProducto: number;
    url: string;
    caption: string;
    mimetype: string;
    /** Destinos a los que hay que mandarlo (al reanudar, sólo los que faltan). */
    chats: string[];
    /** chat_id → id de su fila en `app_wapi_envio_log`. */
    logIdPorChat: Map<string, number>;
  };

  const skipped: Array<{ id_producto: number; reason: string }> = [];
  let enviados = 0;
  let fallidos = 0;
  /** Mensajes en `pendiente` que NO son fallos: hay que reanudarlos. */
  let pendientesDeTrabajo = 0;
  let mensajesIntentados = 0;
  /** Mensajes que quedaron `pendiente` por caída de sesión (NO son fallos:
   *  son trabajo por hacer en cuanto la sesión vuelva). */
  let pendientesPorSesion = 0;
  // batchId para correlación interna (no se envía al WAPI).
  const batchId = `b_${idTienda}_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;

  /** Posición del producto en la tanda: fija el icono del caption. Así el
   *  MISMO producto sale con el MISMO texto en todos los grupos (antes el
   *  contador rotaba en cada destino y cada grupo veía un icono distinto). */
  const posDeProducto = new Map<number, number>();
  effProductIds.forEach((id, i) => {
    if (!posDeProducto.has(id)) posDeProducto.set(id, i);
  });

  // Descarta un producto (sin imagen, imagen no pública…). Al reanudar hay
  // que marcar sus filas como fallido: si quedaran en `pendiente` la tanda se
  // vería "interrumpida" para siempre y el botón de reanudar reaparecería sin
  // poder avanzar nunca.
  const descartados = new Set<number>();

  const descartar = async (idProd: number, razon: string): Promise<void> => {
    if (descartados.has(idProd)) return;
    descartados.add(idProd);
    skipped.push({ id_producto: idProd, reason: razon });
    // Al reanudar sólo existen filas para los pares que quedaron sin enviar.
    const chatsObjetivo = esReanudacion
      ? chatsValidos.filter((c) => logIdPorPar.has(`${idProd}|${c}`))
      : chatsValidos;
    const { ids, ok } = await registrarPendientesPares(
      chatsObjetivo.map((c) => ({ idProducto: idProd, chatId: c })),
    );
    if (!ok) {
      console.error(
        `[wapi-send-products] el producto ${idProd} se descarta (${razon}) ` +
          `pero no se pudieron registrar sus filas: no quedará constancia ` +
          `en el historial`,
      );
    }
    if (ids.length === 0) return;
    for (const lote of chunkArray(ids, 500)) {
      await admin.from("app_wapi_envio_log").update({
        estado: "fallido",
        error_code: "SKIPPED",
        error_message: `No se puede enviar: ${razon}`,
      }).in("id", lote);
    }
  };
  // Valida un producto, compone el caption y asegura sus filas de log.
  // Devuelve el producto listo con sus destinos, o `null` si no se puede
  // mandar (ya quedó anotado en `skipped` y sus filas marcadas `fallido`).
  const prepararProducto = async (
    idProd: number,
  ): Promise<ProductoListo | null> => {
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
    const caption = buildCaption(template, p, posDeProducto.get(idProd) ?? 0);
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

    const logIdPorChat = new Map<string, number>();

    if (esReanudacion) {
      // Se reutilizan las filas existentes: la tanda original se completa en
      // vez de duplicarse. Vuelven a `pendiente` para que la UI muestre el
      // progreso vivo mientras se re-despachan.
      const aReiniciar: number[] = [];
      for (const c of chats) {
        const id = logIdPorPar.get(`${idProd}|${c}`);
        if (id == null) continue;
        logIdPorChat.set(c, id);
        logIdDePar.set(`${idProd}|${c}`, id);
        aReiniciar.push(id);
      }
      for (const lote of chunkArray(aReiniciar, 500)) {
        await admin.from("app_wapi_envio_log")
          .update({ estado: "pendiente", error_code: null, error_message: null })
          .in("id", lote);
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
        .select("id, chat_id");
      if (logErr) {
        // Sin log el envío seguiría funcionando, pero la UI no vería nada:
        // preferimos avisar y continuar sin logId antes que abortar el chunk.
        console.error(
          `[wapi-send-products] no se pudo registrar el log del producto ` +
            `${idProd}: ${logErr.message}`,
        );
      }
      // Se mapea por `chat_id`, nunca por posición: si el insert devolviera las
      // filas en otro orden, emparejar por índice daría logIds cruzados.
      for (const row of insertados ?? []) {
        const c = String((row as any).chat_id);
        const id = Number((row as any).id);
        logIdPorChat.set(c, id);
        logIdDePar.set(`${idProd}|${c}`, id);
      }
    }

    return {
      idProducto: idProd,
      url: imageUrl,
      caption,
      mimetype,
      chats,
      logIdPorChat,
    };
  };

  /**
   * Caché de preparación. El plan recorre cada producto una vez POR DESTINO,
   * así que sin caché se recalcularía el caption y se reinsertarían filas N
   * veces. `null` también se cachea: un producto descartado no debe volver a
   * intentarse (ni volver a insertar sus filas) en cada destino.
   */
  const cacheProductos = new Map<number, ProductoListo | null>();
  const obtenerProductoListo = async (
    idProd: number,
  ): Promise<ProductoListo | null> => {
    if (cacheProductos.has(idProd)) return cacheProductos.get(idProd) ?? null;
    const listo = await prepararProducto(idProd);
    cacheProductos.set(idProd, listo);
    return listo;
  };

  console.log(
    `[wapi-send-products] batchId=${batchId} session=${wapiSessionId} ` +
      `productos=${effProductIds.length} destinos=${chatsValidos.length} ` +
      `delay=[${minMs / 1000}s..${maxMs / 1000}s] fanout=serie ` +
      `presupuesto=${Math.round(WORKER_BUDGET_MS / 1000)}s` +
      (esReanudacion ? " modo=reanudar" : ""),
  );
  /** Resultado de un envío. `pacing` significa "WAPI pide una pausa que no
   *  cabe en este worker": el chunk se corta y lo pendiente se reanuda.
   *  `sessionDown` significa "la sesión de OpenWA se cayó": se intentó
   *  recuperar (una vez por worker) y, si no se pudo, se corta el chunk
   *  dejando los mensajes en `pendiente` para poder reanudar. */
  type EnvioResultado = {
    ok: boolean;
    pacing?: { retryAfterSeconds: number };
    sessionDown?: { rawStatus: string | null; recuperada: boolean; action: string };
    /** El mensaje NO se envió pero NO es un fallo: quedó `pendiente` y hay que
     *  reanudarlo. Se usa cuando el resultado es indeterminado (la clave de
     *  idempotencia seguía en vuelo, o "puede que se haya enviado") o cuando el
     *  mensaje agotó su ventana. Marcarlo `fallido` daría falsos negativos: el
     *  mensaje puede haber llegado y el `fallido` es irreversible. */
    pendiente?: boolean;
  };

  /** La escalera de recuperación se intenta UNA vez por worker: si la sesión
   *  no vuelve con stop→start, insistir desde dentro del bucle sólo gasta
   *  presupuesto y llena la BD de intentos. */
  let recuperacionIntentada = false;
  let sessionAbort: EnvioResultado["sessionDown"] | null = null;

  // Dispara UN mensaje y actualiza su fila de log.
  //
  // Reintenta hasta RETRY_MAX_ATTEMPTS con backoff exponencial + jitter
  // mientras el error sea transitorio. El backoff también funciona como
  // anti-ban: si la sesión WAPI está rechazando conexiones, insistir de
  // inmediato sólo empeora las cosas.
  //
  // Si el error es "la sesión se cayó", NO se gasta un reintento a ciegas:
  // primero se intenta recuperar la sesión y, si vuelve, se reintenta el
  // mensaje. Eso es lo que antes hacía una persona a mano.
  const dispatchOne = async (e: Envio): Promise<EnvioResultado> => {
    let ultimoCode = "SEND_ERROR";
    let ultimoMsg = "Error desconocido";
    let intentosHechos = 0;
    /** Cuántas veces hemos esperado porque la clave de idempotencia seguía en
     *  vuelo. Estas esperas NO consumen el presupuesto de reintentos: no son
     *  fallos, son "todavía no sé el resultado". */
    let esperasIdem = 0;
    /** Cuándo empezó ESTE mensaje: alimenta el guarda-raíl MENSAJE_MAX_MS. */
    const inicioMensaje = Date.now();

    /**
     * Deja la fila en `pendiente` (trabajo por hacer, NO fallo) y sale.
     *
     * Se usa cuando el resultado es indeterminado. `fallido` sería mentira y
     * además es irreversible: el webhook empareja por `mensaje_id`, y estas
     * filas lo tienen `NULL`, así que ningún ack podría corregirlas después.
     */
    const dejarPendiente = async (
      code: string,
      message: string,
    ): Promise<EnvioResultado> => {
      if (e.logId) {
        await admin.from("app_wapi_envio_log").update({
          estado: "pendiente",
          error_code: code,
          error_message: message,
        }).eq("id", e.logId);
      }
      console.warn(
        `[wapi-send-products] prod=${e.idProducto} chat=${e.chatId} ` +
          `queda PENDIENTE (${code}): ${message}`,
      );
      return { ok: false, pendiente: true };
    };

    for (let intento = 1; intento <= RETRY_MAX_ATTEMPTS; intento++) {
      intentosHechos = intento;
      const single = await wapi.sendImage(
        wapiSessionId,
        e.chatId,
        e.url,
        e.caption,
        e.mimetype,
        // Idempotencia (OpenWA 0.25.0+): si un TIMEOUT hizo que el mensaje sí
        // saliera, el reintento con la misma clave devuelve el mismo mensajeId
        // en vez de mandar un duplicado. En builds viejas el header se ignora.
        e.logId ? `wa-log-${e.logId}` : undefined,
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

      // ── Clave de idempotencia EN VUELO ─────────────────────────────────
      // NO es un fallo. Casi siempre significa que nuestro cliente abortó por
      // timeout mientras OpenWA seguía enviando: la petición original sigue
      // viva. Se espera y se vuelve a preguntar con la MISMA clave; cuando la
      // original acabe, OpenWA reproduce su respuesta guardada y sabremos si
      // el mensaje salió (y con qué messageId) sin arriesgar un duplicado.
      //
      // Antes esto se marcaba `fallido` al 2º intento: 15 de los 21 `fallido`
      // de una sola tanda real eran mensajes que SÍ habían llegado.
      if (esIdemEnProgreso(ultimoCode, ultimoMsg)) {
        const sinMargen = esperasIdem >= IDEM_MAX_ESPERAS ||
          Date.now() - inicioMensaje > MENSAJE_MAX_MS ||
          elapsed() + IDEM_ESPERA_MAX_MS + 20_000 >= WORKER_BUDGET_MS;
        if (sinMargen) {
          return await dejarPendiente(
            "IDEMPOTENCY_KEY_IN_PROGRESS",
            `${ultimoMsg} — se deja pendiente para reanudar con la misma ` +
              `clave (el mensaje puede haberse enviado)`,
          );
        }
        esperasIdem++;
        const esperaMs = Math.min(
          IDEM_ESPERA_MAX_MS,
          IDEM_ESPERA_BASE_MS * esperasIdem,
        );
        console.warn(
          `[wapi-send-products] prod=${e.idProducto} chat=${e.chatId} ` +
            `IDEMPOTENCY_KEY_IN_PROGRESS: la petición original sigue en vuelo ` +
            `— esperando ${Math.round(esperaMs / 1000)}s y reintentando la ` +
            `misma clave (espera ${esperasIdem}/${IDEM_MAX_ESPERAS})`,
        );
        await new Promise((res) => setTimeout(res, esperaMs));
        intento--; // la espera no consume presupuesto de reintentos
        continue;
      }

      // ── Resultado indeterminado: "puede que se haya enviado" ───────────
      // Tampoco es un `fallido` honesto. Reintentar con la misma clave es la
      // única forma de averiguarlo sin arriesgar un duplicado.
      if (esIdemResultadoDesconocido(ultimoCode, ultimoMsg)) {
        const sinMargen = esperasIdem >= IDEM_MAX_ESPERAS ||
          Date.now() - inicioMensaje > MENSAJE_MAX_MS ||
          elapsed() + IDEM_ESPERA_BASE_MS + 20_000 >= WORKER_BUDGET_MS;
        if (sinMargen) {
          return await dejarPendiente(
            "IDEMPOTENCY_OUTCOME_UNKNOWN",
            `${ultimoMsg} — resultado indeterminado: se deja pendiente para ` +
              `reanudar con la misma clave`,
          );
        }
        esperasIdem++;
        await new Promise((res) => setTimeout(res, IDEM_ESPERA_BASE_MS));
        intento--; // la espera no consume presupuesto de reintentos
        continue;
      }

      // ── Sesión caída: recuperar y reintentar ───────────────────────────
      // 4,995 de las filas `fallido` en producción son HTTP_409 "Session is
      // not connected" / HTTP_400 "is not active" repetidos contra una sesión
      // muerta. Aquí se intenta la escalera UNA vez por worker.
      if (esErrorDeSesion(ultimoCode, ultimoMsg)) {
        if (recuperacionIntentada) {
          // Ya se intentó en este worker y sigue caída: no se marca `fallido`
          // (es trabajo por hacer, no un fallo): la fila queda `pendiente`.
          sessionAbort = {
            rawStatus: sessionAbort?.rawStatus ?? null,
            recuperada: false,
            action: "ya-intentada",
          };
          return { ok: false, sessionDown: sessionAbort };
        }
        recuperacionIntentada = true;

        const live = await wapi.getSession(wapiSessionId);
        const rawActual = live.success
          ? ((live.data?.status as string | undefined) ?? null)
          : null;
        console.error(
          `[wapi-send-products] SESIÓN CAÍDA (${ultimoCode}: ${ultimoMsg}) ` +
            `estado OpenWA=${rawActual ?? "?"} — intentando recuperarla ` +
            `(prod=${e.idProducto} chat=${e.chatId})`,
        );

        const outcome = await runRecovery(wapi, wapiSessionId, rawActual, {
          lastRecoveryAt: (ses.last_recovery_at as string | null) ?? null,
          recoveryAttempts: Number(ses.recovery_attempts ?? 0),
          // Si llegamos hasta aquí es porque la sesión estaba enviando: está
          // vinculada. Marcarlo evita que el planificador la trate como
          // "esperando QR" y no haga nada.
          linked: true,
        });

        await updateSessionState(admin, ses.id, {
          status: normalizeWapiStatus(
            outcome.finalRawStatus ?? rawActual,
            "DISCONNECTED",
          ),
          rawStatus: outcome.finalRawStatus ?? rawActual,
          recoveryAttempt: outcome.action !== "none" && outcome.action !== "cooldown",
          errorCode: outcome.ok ? null : "SESSION_DOWN",
          errorMessage: outcome.ok
            ? null
            : `recuperación falló (${outcome.action}) tras ${ultimoCode}`,
        });

        if (outcome.ok) {
          console.warn(
            `[wapi-send-products] sesión recuperada (${outcome.action} → ` +
              `${outcome.finalRawStatus}): reintentando el mensaje`,
          );
          // Se consume una vuelta del bucle para reintentar el MISMO mensaje.
          continue;
        }

        sessionAbort = {
          rawStatus: outcome.finalRawStatus ?? rawActual,
          recuperada: false,
          action: outcome.action,
        };
        console.error(
          `[wapi-send-products] no se pudo recuperar la sesión ` +
            `(${outcome.action}, estado final ${outcome.finalRawStatus}). ` +
            `Se corta el chunk; los mensajes quedan pendientes de reanudar.`,
        );
        return { ok: false, sessionDown: sessionAbort };
      }

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
      // marcar el fallo ya y dejar que el resto del chunk siga. Se aplica el
      // mismo criterio al techo POR MENSAJE: un destino atascado no puede
      // consumir el presupuesto de los demás mensajes del grupo.
      const sinTiempo = elapsed() + backoffMs + 15_000 >= WORKER_BUDGET_MS ||
        Date.now() - inicioMensaje + backoffMs > MENSAJE_MAX_MS;
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

    // El mensaje no llegó a `enviado`. ¿Es un fallo o trabajo por hacer?
    //
    //   · TIMEOUT / NETWORK_ERROR / SEND_ERROR / idempotencia indeterminada:
    //     se agotaron los reintentos y NO sabemos si salió. Como todas las
    //     tentativas viajan con la MISMA `Idempotency-Key`, reanudar es seguro
    //     y no duplica nada → `pendiente`. Marcarlo `fallido` era el falso
    //     negativo: 15 de 21 filas de una tanda real eran mensajes entregados.
    //   · 4xx de validación (imagen rechazada, chat inexistente...): reintentar
    //     daría lo mismo → `fallido`, para no prometer una reanudación inútil.
    const indeterminado = !ultimoCode ||
      ultimoCode === "TIMEOUT" ||
      ultimoCode === "NETWORK_ERROR" ||
      ultimoCode === "SEND_ERROR" ||
      esIdemEnProgreso(ultimoCode, ultimoMsg) ||
      esIdemResultadoDesconocido(ultimoCode, ultimoMsg);

    if (e.logId) {
      await admin.from("app_wapi_envio_log")
        .update(
          indeterminado
            ? {
              estado: "pendiente",
              error_code: ultimoCode,
              error_message:
                `${ultimoMsg} (tras ${intentosHechos} intento(s)) — ` +
                `reanudable sin duplicar (misma clave)`,
            }
            : {
              estado: "fallido",
              error_code: ultimoCode,
              // El conteo es el REAL, no RETRY_MAX_ATTEMPTS: cuando el bucle sale
              // antes por falta de presupuesto o por error no reintentable, decir
              // "tras 3 intentos" era simplemente falso (y entorpecía el
              // diagnóstico: las 1,599 filas HTTP_500 lo decían todas).
              error_message: `${ultimoMsg} (tras ${intentosHechos} intento(s))`,
            },
        )
        .eq("id", e.logId);
    }
    return indeterminado ? { ok: false, pendiente: true } : { ok: false };
  };

  // ── BUCLE PRINCIPAL: UN DESTINO DETRÁS DE OTRO ───────────────────────
  // `plan` ya viene ordenado destino-mayor: primero TODOS los productos del
  // primer grupo, luego todos los del segundo. Aquí sólo se recorre con un
  // cursor y, antes de cada mensaje, se comprueba si CABE en lo que queda de
  // worker; si no cabe, el resto se encola en un worker nuevo por
  // `resume_log_ids`. Si un destino falla varias veces seguidas se SALTA (sus
  // mensajes quedan `pendiente`) para que no se coma el presupuesto de los
  // demás grupos.
  let ventanaFin = 0;
  let destinoActual: string | null = plan.length > 0 ? plan[0].chatId : null;
  let fallosDelDestino = 0;
  /** Destinos ya marcados como problemáticos. Sirve para que un grupo caído no
   *  vuelva a encolarse cuando el corte por presupuesto parte el plan. */
  const destinosSaltados = new Set<string>();

  for (let cursor = 0; cursor < plan.length; cursor++) {
    const par = plan[cursor];

    // Cambio de grupo: pausa larga y contador de fallos a cero.
    if (par.chatId !== destinoActual) {
      destinoActual = par.chatId;
      fallosDelDestino = 0;
      const pausa = ENTRE_DESTINOS_MS +
        Math.floor(Math.random() * Math.min(minMs, 10_000));
      console.log(
        `[wapi-send-products] siguiente destino a los ` +
          `${Math.round(elapsed() / 1000)}s (pausa ${Math.round(pausa / 1000)}s)`,
      );
      if (elapsed() + pausa + reservaMensajeMs() < WORKER_BUDGET_MS) {
        await new Promise((res) => setTimeout(res, pausa));
      }
    }

    const sinPresupuesto = mensajesIntentados > 0
      ? elapsed() + reservaMensajeMs() > WORKER_BUDGET_MS
      : elapsed() > WORKER_BUDGET_MS; // el primero siempre se intenta
    if (sinPresupuesto) {
      remainingPares = plan.slice(cursor);
      console.log(
        `[wapi-send-products] corte por presupuesto a los ` +
          `${Math.round(elapsed() / 1000)}s: ${mensajesIntentados} mensaje(s) ` +
          `despachados, ${remainingPares.length} para el worker siguiente`,
      );
      break;
    }

    // Destino problemático: no se insiste contra él. Sus mensajes quedan
    // `pendiente` (reanudables a mano) y se pasa al grupo siguiente.
    if (fallosDelDestino >= DESTINO_FALLOS_MAX) {
      destinosSaltados.add(par.chatId);
      saltadosPares.push(par);
      continue;
    }
    // Producto descartado: ni se prepara ni cuenta como trabajo pendiente.
    if (descartados.has(par.idProducto)) continue;

    // Precarga por ventanas: una consulta cada WINDOW_SIZE productos, en vez
    // de una por producto (lento) o una sola gigante (se trunca).
    const posProd = posDeProducto.get(par.idProducto) ?? 0;
    if (posProd >= ventanaFin) {
      const fin = Math.min(effProductIds.length, posProd + WINDOW_SIZE);
      await ensureInfo(effProductIds.slice(posProd, fin));
      ventanaFin = fin;
    }

    const listo = await obtenerProductoListo(par.idProducto);
    if (!listo) {
      // Producto descartado: `descartar` ya marcó sus filas como `fallido`
      // (SKIPPED) y dejó constancia en `skipped`. Por eso NO va a ningún cubo
      // de pendientes: no hay nada que reanudar.
      continue;
    }
    if (!listo.chats.includes(par.chatId)) {
      // No debería ocurrir nunca: el `plan` y `prepararProducto` usan el mismo
      // filtro (`logIdPorPar`). Si pasara, el par quedaría fuera de todos los
      // cubos, así que se avisa en vez de perderlo en silencio.
      console.error(
        `[wapi-send-products] par sin destino preparado: ` +
          `prod=${par.idProducto} chat=${par.chatId} — se omite`,
      );
      continue;
    }

    const inicioMensaje = Date.now();
    const r = await dispatchOne({
      idProducto: par.idProducto,
      chatId: par.chatId,
      url: listo.url,
      caption: listo.caption,
      mimetype: listo.mimetype,
      logId: listo.logIdPorChat.get(par.chatId) ?? null,
    });
    mensajesIntentados++;
    // Coste real del mensaje: alimenta `reservaMensajeMs()` para que la
    // decisión de cortar use medidas de ESTE envío, no una estimación fija.
    peorEnvioMs = Math.max(peorEnvioMs, Date.now() - inicioMensaje);

    if (r.ok) {
      enviados++;
      fallosDelDestino = 0;
    } else if (r.sessionDown) {
      // La sesión de OpenWA se cayó y la escalera no la levantó: se corta el
      // chunk. Todo lo que queda queda `pendiente` (no `fallido`): es trabajo
      // por hacer cuando la sesión vuelva.
      pendientesPorSesion++;
      sessionAbort = r.sessionDown;
      remainingPares = plan.slice(cursor + 1);
      break;
    } else if (r.pacing) {
      // WAPI pide una pausa que no cabe en este worker: se corta y se reanuda.
      pacingAbort = r.pacing;
      remainingPares = plan.slice(cursor + 1);
      break;
    } else if (r.pendiente) {
      // Resultado indeterminado. La fila ya quedó `pendiente` y es reanudable
      // sin duplicar (misma clave). Cuenta como fallo del destino para poder
      // saltárselo si se atasca, pero NO se marca como fallo de la tanda.
      pendientesDeTrabajo++;
      fallosDelDestino++;
    } else {
      fallidos++;
      fallosDelDestino++;
    }

    // Delay anti-ban entre mensajes DEL MISMO destino. Mantiene el mismo ritmo
    // efectivo por sesión que el fan-out anterior (donde el hueco lo ponían
    // los otros destinos) pero concentrado en el grupo que se está sirviendo.
    if (cursor < plan.length - 1 && plan[cursor + 1].chatId === par.chatId) {
      const jitter = minMs +
        Math.floor(Math.random() * Math.max(1, maxMs - minMs));
      if (elapsed() + jitter + 20_000 < WORKER_BUDGET_MS) {
        await new Promise((res) => setTimeout(res, jitter));
      }
    }
  }

  // ── CIERRE ───────────────────────────────────────────────────────────
  // ORDEN CRÍTICO: primero la continuación, después el resumen. Al revés,
  // si el resumen se come lo que queda de worker la cadena muere y los
  // mensajes restantes no se envían nunca (era el bug de los 4 grupos).
  let continuacionOk = false;

  // Si el corte por presupuesto dejó dentro del `remaining` mensajes de un
  // destino que YA se marcó como caído, no se encolan: volverían a fallar en el
  // worker siguiente y gastarían su presupuesto. Pasan a `saltadosPares`.
  const deDestinoSaltado = remainingPares.filter((p) =>
    destinosSaltados.has(p.chatId)
  );
  if (deDestinoSaltado.length > 0) {
    saltadosPares.push(...deDestinoSaltado);
    remainingPares = remainingPares.filter((p) =>
      !destinosSaltados.has(p.chatId)
    );
  }

  // Los mensajes de un destino saltado NO se encadenan: volverían a fallar y
  // sólo gastarían workers. Quedan `pendiente` con el motivo para que el botón
  // "reanudar" de la app los recoja cuando el grupo se arregle.
  const saltadosRegistrables = saltadosPares
    .filter((p) => !descartados.has(p.idProducto));
  if (saltadosRegistrables.length > 0) {
    const { ids, ok } = await registrarPendientesPares(saltadosRegistrables, {
      code: "DESTINO_CAIDO",
      message:
        `El destino acumuló ${DESTINO_FALLOS_MAX} fallos seguidos; sus ` +
        `mensajes quedan pendientes de reanudar`,
    });
    console.warn(
      `[wapi-send-products] ${saltadosRegistrables.length} mensaje(s) de ` +
        `destino(s) saltado(s) quedan pendientes (${ids.length} fila(s)` +
        `${ok ? "" : ", REGISTRO INCOMPLETO"})`,
    );
  }

  const remainingRegistrables = remainingPares
    .filter((p) => !descartados.has(p.idProducto));

  if (pacingAbort) {
    // WAPI está en cooldown: encadenar sería chocar con el mismo 429 desde
    // un worker nuevo. Se registran los pendientes para reanudar después.
    console.warn(
      `[wapi-send-products] cortado por pacing ` +
        `(${pacingAbort.retryAfterSeconds}s): ${remainingRegistrables.length} ` +
        `mensaje(s) quedan pendientes de reanudar`,
    );
    await registrarPendientesPares(remainingRegistrables);
  } else if (sessionAbort) {
    // La sesión se cayó y la escalera de recuperación falló. Encadenar un
    // worker nuevo sería inútil (haría lo mismo contra una sesión muerta) y
    // gastaría una invocación: se registran los pendientes y se avisa.
    console.error(
      `[wapi-send-products] cortado por SESIÓN CAÍDA ` +
        `(acción=${sessionAbort.action}, estado final=${sessionAbort.rawStatus ?? "?"}): ` +
        `${remainingRegistrables.length} mensaje(s) quedan pendientes de reanudar. ` +
        `El watchdog (wapi-session-health) y el cron revisan la sesión.`,
    );
    await registrarPendientesPares(remainingRegistrables);
  } else if (remainingRegistrables.length > 0) {
    // Primero se aseguran las filas (la continuación se guía por logIds) y
    // después se encola. Al revés, la continuación iría sin ids.
    const { ids, ok } = await registrarPendientesPares(remainingRegistrables);
    if (!ok || ids.length === 0) {
      // Sin filas no hay continuación posible: hay que gritarlo, porque si no
      // la tanda se queda "a medias" sin ninguna señal (era el fallo silencioso
      // que rompía la cadena de chunks).
      console.error(
        `[wapi-send-products] CADENA ROTA: no se pudieron registrar ` +
          `${remainingRegistrables.length} mensaje(s) que faltaban ` +
          `(ids=${ids.length}, ok=${ok}). Esos mensajes NO se despacharán ` +
          `hasta que se reanude la tanda a mano.`,
      );
      continuacionOk = false;
    } else {
      continuacionOk = await reinvokeRemaining(ids);
    }
  }

  // El resumen sólo lo manda el ÚLTIMO chunk de la cadena. `cerrarConResumen`
  // decide por sí mismo si le cabe aquí o lo delega a un worker nuevo.
  const esUltimoChunk = remainingPares.length === 0 && !pacingAbort &&
    !sessionAbort;
  const resumenEntregas = esUltimoChunk ? await cerrarConResumen() : 0;

  console.log(
    `[wapi-send-products] chunk cerrado en ${Math.round(elapsed() / 1000)}s: ` +
      `${mensajesIntentados} mensaje(s) (${enviados} ok / ${fallidos} fallidos / ` +
      `${pendientesDeTrabajo} pendientes / ${pendientesPorSesion} por sesión ` +
      `caída), ${skipped.length} descartado(s), ` +
      `${remainingPares.length} para el worker siguiente, ` +
      `${saltadosPares.length} de destino saltado`,
  );

  return {
    enviados,
    fallidos,
    pendientes: pendientesDeTrabajo,
    pendientes_por_sesion: pendientesPorSesion,
    batch_id: batchId,
    mode: "serie-por-destino",
    destinos: chatsValidos.length,
    chunk_size: mensajesIntentados,
    mensajes: mensajesIntentados,
    skipped,
    remaining: remainingPares.length,
    saltados: saltadosPares.length,
    continuacion_encolada: continuacionOk,
    ...(pacingAbort
      ? { pacing_retry_after_seconds: pacingAbort.retryAfterSeconds }
      : {}),
    ...(sessionAbort
      ? {
        sesion_caida: {
          accion: sessionAbort.action,
          estado_final: sessionAbort.rawStatus,
          recuperada: sessionAbort.recuperada,
        },
      }
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
    ? Array.from(
      new Set(body.product_ids.map(Number).filter((n) => Number.isFinite(n))),
    )
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
    ? Array.from(
      new Set(
        body.summary_product_ids.map(Number).filter((n) => Number.isFinite(n)),
      ),
    )
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
  // ── Puerta de entrada: ¿está la sesión realmente conectada? ──────────
  // La columna `status` de la BD puede estar OBSOLETA: sólo se refresca
  // cuando la app llama a wapi-session-status o cuando llega un webhook, y el
  // webhook se registró mal durante meses (sin secret ni eventos session.*).
  // Consecuencia real: o se rechazaba con 409 una sesión sana, o se creía
  // CONNECTED una sesión muerta y todos los envíos fallaban.
  // Ahora: se pregunta a OpenWA y, si hace falta, se intenta recuperar.
  let sesionLista = ses.status === "CONNECTED";
  let statusCrudo: string | null = null;

  if (!sesionLista) {
    const live = await wapi.getSession(ses.wapi_session_id);
    statusCrudo = live.success
      ? ((live.data?.status as string | undefined) ?? null)
      : null;

    if (live.success && isSessionSendable(statusCrudo)) {
      // La BD mentía: la sesión está viva. Se corrige y se sigue.
      sesionLista = true;
      await updateSessionState(admin, ses.id, {
        status: normalizeWapiStatus(statusCrudo, "CONNECTED"),
        rawStatus: statusCrudo,
        ...(live.data?.phoneNumber ? { phoneNumber: live.data.phoneNumber } : {}),
        resetRecovery: true,
      });
      console.warn(
        `[wapi-send-products] la BD decía status="${ses.status}" pero OpenWA ` +
          `responde "${statusCrudo}": se corrige y se continúa`,
      );
    } else {
      // Caída de verdad: intentar la escalera antes de rendirse. Antes esto
      // devolvía 409 seco y el usuario tenía que pulsar "reiniciar".
      const outcome = await runRecovery(
        wapi,
        ses.wapi_session_id,
        statusCrudo ?? (ses.status as string),
        {
          lastRecoveryAt: (ses.last_recovery_at as string | null) ?? null,
          recoveryAttempts: Number(ses.recovery_attempts ?? 0),
          linked: Boolean(live.data?.phoneNumber ?? ses.phone_number),
        },
      );

      await updateSessionState(admin, ses.id, {
        status: normalizeWapiStatus(
          outcome.finalRawStatus ?? statusCrudo,
          "DISCONNECTED",
        ),
        rawStatus: outcome.finalRawStatus ?? statusCrudo,
        recoveryAttempt: outcome.action !== "none" && outcome.action !== "cooldown",
        errorCode: outcome.ok ? null : "NOT_CONNECTED",
        errorMessage: outcome.ok
          ? null
          : `recuperación ${outcome.action} sin éxito`,
      });

      if (!outcome.ok) {
        return errorResponse(
          `La sesión no está conectada a WhatsApp (estado OpenWA: ` +
            `${statusCrudo ?? "desconocido"}). Se intentó recuperarla ` +
            `automáticamente (${outcome.action}) sin éxito. ` +
            (outcome.needsHumanAck
              ? "Hay que confirmar el modal \"What's new\" de WhatsApp en el " +
                "teléfono una vez, y volver a intentarlo."
              : outcome.terminal
              ? "La sesión está en FAILED, que es terminal en OpenWA: puede " +
                "hacer falta borrarla y volver a vincularla."
              : "Revisa el servidor OpenWA (health / logs del contenedor)."),
          409,
          "NOT_CONNECTED",
        );
      }
      console.warn(
        `[wapi-send-products] sesión recuperada automáticamente ` +
          `(${outcome.action} → ${outcome.finalRawStatus}): se continúa con el envío`,
      );
      sesionLista = true;
    }
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
  // Mensajes que va a despachar el plan/chunk. El envío es EN SERIE y el
  // Orden POR DESTINO y en serie: cada mensaje cuesta su envío + el delay anti-ban.
  const mensajesDelPlan = esReanudacion
    ? resumeLogIds.length
    : productIds.length * Math.max(1, destinations.length);
  /** Estimación: cada mensaje cuesta su envío (≈8s de base, pero se han medido
   *  16-50s por imagen cuando OpenWA está justo de memoria) más el delay
   *  anti-ban. Es un suelo optimista para que el usuario sepa que puede seguir
   *  usando la app, no una promesa. */
  const estimadoSeg = soloResumen ? 30 : Math.round(
    mensajesDelPlan * (8 + (delayMin + delayMax) / 2),
  );

  const job = dispatchProducts({
    admin,
    idSesion: ses.id,
    idTienda: ses.id_tienda,
    wapiSessionId: ses.wapi_session_id,
    // La rama de recuperación de `dispatchOne` necesita la fila de sesión
    // (`last_recovery_at`, `recovery_attempts`, `id`). Sin esto lanzaba
    // `ReferenceError: ses is not defined` justo cuando la sesión se caía.
    ses: {
      id: ses.id,
      last_recovery_at: (ses.last_recovery_at as string | null) ?? null,
      recovery_attempts: Number(ses.recovery_attempts ?? 0),
    },
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
    sesion_lista: sesionLista,
    sesion_estado_openwa: statusCrudo,
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
