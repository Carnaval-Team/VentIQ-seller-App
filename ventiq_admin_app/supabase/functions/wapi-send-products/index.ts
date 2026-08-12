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
//   1. Por producto: se envía la misma imagen a TODOS los destinatarios
//      seleccionados en PARALELO (cap MAX_PARALLEL_FANOUT). Esto explota el
//      hecho de que mandar el mismo contenido a varios chats al mismo tiempo
//      es indistinguible de un broadcast humano; el ban viene de "muchas
//      cosas distintas en poco tiempo".
//   2. Entre productos: delay aleatorio en [delay_min, delay_max].
//   3. Defaults 5–10s alineados con el techo recomendado de 20 msgs/min/sesión
//      (con cap 5 paralelos: ráfaga ≤5, promedio ≤40/min — sólo se acerca al
//      techo si seleccionas muchos grupos).
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

/** ¿El error merece reintento? Los 4xx de validación no (fallarían igual). */
function esReintentable(code: string | undefined): boolean {
  if (!code) return true;
  if (code === "NETWORK_ERROR" || code === "SEND_ERROR") return true;
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
 * Máximo de mensajes de resumen por destino. El resumen se manda al final del
 * último chunk, dentro del mismo worker (techo ~400s): sin tope, un catálogo
 * enorme × muchos destinos se cortaría a media tanda de textos. Con 4 partes
 * caben ~180 productos; el resto se anuncia como "y N más" en vez de
 * desaparecer en silencio.
 */
const SUMMARY_MAX_PARTS = 4;

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
  // Traemos todo el histórico ordenado por id desc y nos quedamos con la
  // primera ocurrencia por producto (la más reciente).
  const { data: precios } = await admin
    .from("app_dat_precio_venta")
    .select("id, id_producto, precio_venta_cup, precio_venta_usd")
    .in("id_producto", ids)
    .order("id", { ascending: false });

  const precioMap = new Map<number, number>();
  (precios ?? []).forEach((p: any) => {
    if (precioMap.has(p.id_producto)) return; // ya tenemos el más reciente
    precioMap.set(
      p.id_producto,
      Number(p.precio_venta_cup ?? p.precio_venta_usd ?? 0),
    );
  });

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
        const { data: invRows } = await admin
          .from("app_dat_inventario_productos")
          .select("id, id_producto, id_ubicacion, cantidad_final, created_at")
          .in("id_producto", ids)
          .in("id_ubicacion", ubicacionIds)
          .order("id", { ascending: false });

        // Mapa intermedio: (idProducto, idUbicacion) → cantidad_final más reciente.
        const latestPerPair = new Map<string, number>();
        for (const row of invRows ?? []) {
          const key = `${row.id_producto}_${row.id_ubicacion}`;
          if (!latestPerPair.has(key)) {
            latestPerPair.set(key, Number(row.cantidad_final ?? 0));
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
}) {
  const {
    admin, idSesion, idTienda, wapiSessionId, productIds,
    destinations, template, delayMin, delayMax, tipoEnvio, idProgramacion,
    resumeLogIds,
  } = args;
  const enviarResumen = args.enviarResumen ?? true;

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

  if (effProductIds.length === 0 || effDestinations.length === 0) {
    return { enviados: 0, fallidos: 0, batch_id: null, skipped: true };
  }

  // Productos que listará el resumen final. En la primera invocación son
  // todos los pedidos; en las continuaciones viene heredado del chunk previo.
  // (Al reanudar sólo conocemos los productos que quedaron sin enviar, así que
  //  el resumen de una reanudación lista ese subconjunto.)
  const summaryIds = args.summaryProductIds?.length
    ? args.summaryProductIds
    : effProductIds;

  // ───────────────────────────────────────────────────────────────────
  //  CHUNKING anti-timeout
  //  Los background tasks de Supabase Edge se matan al llegar al techo de
  //  ~400s de wall-clock. Con delays anti-ban de 5-10s entre productos, un
  //  envío largo (p.ej. una programación con muchos productos) se cortaba a
  //  la mitad y "solo mandaba unos pocos" — el resto quedaba en estado
  //  `pendiente` sin enviarse nunca. Era invisible en el envío manual porque
  //  ahí se seleccionan pocos productos y el total cabía bajo los 400s.
  //
  //  Solución: procesar SÓLO los productos que caben con holgura en un
  //  presupuesto de tiempo, y re-invocar wapi-send-products con el resto.
  //  Cada invocación arranca su propio worker con 400s frescos, así que el
  //  envío completo se reparte en N chunks encadenados. El chunk se decide
  //  AQUÍ (arriba), no a mitad del loop, para que los logs `pendiente` se
  //  inserten sólo para el chunk actual (evita filas duplicadas).
  // ───────────────────────────────────────────────────────────────────
  const MAX_PARALLEL_FANOUT = 5;
  const minMs = Math.max(5_000, delayMin * 1000);
  const maxMs = Math.max(minMs + 1_000, delayMax * 1000);

  // Presupuesto conservador (250s): deja ~150s de margen bajo el techo de
  // 400s para el fan-out del último producto del chunk y la re-invocación.
  const TIME_BUDGET_MS = 250_000;
  const avgDelayMs = (minMs + maxMs) / 2;
  const fanoutBatches = Math.ceil(effDestinations.length / MAX_PARALLEL_FANOUT);
  // Estimado de wall-time por producto: delay entre productos + fan-out
  // (cada sub-lote ~4s por intento; con reintentos el peor caso crece, así
  // que reservamos margen para un reintento medio por sub-lote).
  const perProductMs = avgDelayMs + fanoutBatches * 8_000;
  const maxProductsThisChunk = Math.max(
    1,
    Math.floor(TIME_BUDGET_MS / perProductMs),
  );

  const chunkIds = effProductIds.slice(0, maxProductsThisChunk);
  const remainingIds = effProductIds.slice(maxProductsThisChunk);

  // Re-invoca wapi-send-products con los productos que NO caben en este chunk.
  // Fire-and-forget: el endpoint responde de inmediato (queued) y procesa el
  // siguiente chunk en su propio background task con 400s frescos.
  //
  // IMPORTANTE: idempotencia. `reinvokeRemaining` sólo debe encolar UNA vez por
  // worker; si se llama dos veces (p.ej. en el early-fire y otra vez al final
  // por una ruta de error), duplicaría el chunk restante. Un flag lo evita.
  let reinvoked = false;
  const reinvokeRemaining = async (): Promise<void> => {
    if (remainingIds.length === 0 || reinvoked) return;
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

    // Ruta primaria: admin.functions.invoke. El cliente `admin` ya fue
    // construido con SUPABASE_URL + SERVICE_ROLE_KEY válidos (si faltaran, el
    // serviceClient() habría reventado mucho antes). Esto evita depender de
    // releer el env var crudo dentro del worker en background — que es lo que
    // estaba fallando en silencio y cortaba la cadena tras el primer chunk.
    try {
      const { error } = await admin.functions.invoke("wapi-send-products", {
        body: payload,
      });
      if (!error) {
        console.log(
          `[wapi-send-products] continuación encolada (invoke): ` +
            `${remainingIds.length} productos restantes`,
        );
        return;
      }
      console.error(
        `[wapi-send-products] functions.invoke falló, intento fallback fetch: ` +
          `${error.message ?? error}`,
      );
    } catch (e) {
      console.error(
        `[wapi-send-products] functions.invoke lanzó excepción, fallback fetch: ` +
          `${(e as Error).message ?? e}`,
      );
    }

    // Ruta de respaldo: fetch manual al endpoint público.
    const baseUrl = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!baseUrl || !key) {
      console.error(
        "[wapi-send-products] CADENA ROTA: functions.invoke falló y faltan " +
          "SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY para el fallback. " +
          `${remainingIds.length} productos quedaron SIN enviar.`,
      );
      return;
    }
    const endpoint =
      `${baseUrl.replace(/\/$/, "")}/functions/v1/wapi-send-products`;
    try {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${key}`,
          "apikey": key,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });
      console.log(
        `[wapi-send-products] continuación encolada (fetch): ${remainingIds.length} ` +
          `productos restantes → HTTP ${res.status}`,
      );
    } catch (e) {
      console.error(
        `[wapi-send-products] CADENA ROTA: fallo al encolar continuación (` +
          `${remainingIds.length} productos restantes): ` +
          `${(e as Error).message ?? e}`,
      );
    }
  };

  // Datos de los productos de este chunk: nombre, imagen, categoría, precio
  // vigente, presentación base y stock disponible.
  const infoChunk = await loadProductInfo(admin, idTienda, chunkIds);

  // ── RESUMEN FINAL ───────────────────────────────────────────────────
  // Mensaje de texto con el listado completo (nombre · cantidad ·
  // disponibilidad · precio). Sólo lo dispara el ÚLTIMO chunk de la cadena;
  // si no, saldría un resumen por cada chunk.
  //
  // NO se registra en `app_wapi_envio_log`: esa tabla es por producto y la UI
  // agrupa/reanuda tandas a partir de ella — una fila sin `id_producto` que
  // fallara dejaría la tanda "interrumpida" para siempre, porque el modo
  // reanudar descarta los logs sin producto.
  const enviarResumenFinal = async (): Promise<number> => {
    try {
      // Si el envío entero cupo en un chunk reusamos lo ya cargado; si hubo
      // varios chunks hay que releer los productos de los anteriores.
      const infoResumen = summaryIds.every((id) => infoChunk.has(id))
        ? infoChunk
        : await loadProductInfo(admin, idTienda, summaryIds);

      const items = summaryIds
        .map((id) => infoResumen.get(id))
        .filter((p): p is ProdInfo => !!p);
      const mensajes = buildSummaryMessages(items);
      if (mensajes.length === 0) return 0;

      let ok = 0;
      for (const d of effDestinations) {
        if (!d.chat_id || !/@(c|g)\.us$/.test(d.chat_id)) continue;
        for (const texto of mensajes) {
          if (await sendTextConReintentos(wapiSessionId, d.chat_id, texto)) ok++;
          // Pausa corta entre textos (anti-ban).
          await new Promise((res) => setTimeout(res, 1_500));
        }
      }
      console.log(
        `[wapi-send-products] resumen: ${items.length} producto(s) en ` +
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

  // Construir mensajes: filtrar productos sin imagen
  const messages: Array<{
    chatId: string;
    type: "image";
    content: { image: { url: string; mimetype?: string }; caption: string };
    // metadata propia para mapear al log
    _meta: { id_producto: number; chat_id: string };
  }> = [];

  const skipped: Array<{ id_producto: number; reason: string }> = [];
  let seedCounter = Math.floor(Math.random() * 1000); // rotación de iconos
  // Recorremos en el orden pedido (chunkIds), no en el que devuelva PostgREST.
  for (const idProd of chunkIds) {
    const p = infoChunk.get(idProd);
    if (!p) {
      skipped.push({ id_producto: idProd, reason: "producto no encontrado" });
      continue;
    }
    if (!p.imagen || typeof p.imagen !== "string" || !p.imagen.trim()) {
      skipped.push({ id_producto: idProd, reason: "sin imagen" });
      continue;
    }
    const imageUrl = p.imagen.trim();
    // WAPI requiere URL pública http(s). Data URLs y blobs no funcionan.
    if (!/^https?:\/\//i.test(imageUrl)) {
      skipped.push({
        id_producto: idProd,
        reason: `imagen no es URL http(s): ${imageUrl.slice(0, 40)}…`,
      });
      continue;
    }
    const caption = buildCaption(template, p, seedCounter++);
    // Inferir mimetype desde la extensión (algunas builds de WAPI lo exigen)
    const ext = imageUrl.split("?")[0].split(".").pop()?.toLowerCase() ?? "";
    const mimetype =
      ext === "png"
        ? "image/png"
        : ext === "webp"
        ? "image/webp"
        : ext === "gif"
        ? "image/gif"
        : "image/jpeg";

    for (const d of effDestinations) {
      if (!d.chat_id || typeof d.chat_id !== "string") continue;
      // chatId debe acabar en @c.us (números) o @g.us (grupos)
      if (!/@(c|g)\.us$/.test(d.chat_id)) {
        skipped.push({
          id_producto: idProd,
          reason: `chat_id inválido: ${d.chat_id}`,
        });
        continue;
      }
      // Al reanudar sólo re-despachamos los pares que realmente quedaron
      // sin enviar; el resto del producto ya llegó y no debe repetirse.
      if (esReanudacion && !logIdPorPar.has(`${idProd}|${d.chat_id}`)) continue;
      messages.push({
        chatId: d.chat_id,
        type: "image",
        content: { image: { url: imageUrl, mimetype }, caption },
        _meta: { id_producto: idProd, chat_id: d.chat_id },
      });
    }
  }
  if (skipped.length) {
    console.warn(
      `[wapi-send-products] ${skipped.length} mensajes descartados antes del envío:`,
      JSON.stringify(skipped.slice(0, 10)),
    );
  }

  // En modo reanudar, los productos descartados (sin imagen válida) tienen
  // filas de log que nadie va a tocar. Si las dejáramos en `pendiente` la
  // tanda se quedaría eternamente "interrumpida" y el botón de reanudar
  // reaparecería sin poder avanzar nunca. Las marcamos como fallido con la
  // razón real para que el estado sea honesto y la tanda pueda cerrarse.
  if (esReanudacion) {
    const idsDescartados = new Set(
      skipped
        .filter((s) => chunkIds.includes(s.id_producto))
        .map((s) => s.id_producto),
    );
    const logsDescartados: number[] = [];
    let razon = "Producto sin imagen pública válida";
    for (const [key, logId] of logIdPorPar.entries()) {
      const idProd = Number(key.split("|")[0]);
      if (idsDescartados.has(idProd)) {
        logsDescartados.push(logId);
        const s = skipped.find((x) => x.id_producto === idProd);
        if (s) razon = s.reason;
      }
    }
    if (logsDescartados.length > 0) {
      await admin
        .from("app_wapi_envio_log")
        .update({
          estado: "fallido",
          error_code: "SKIPPED",
          error_message: `No se puede enviar: ${razon}`,
        })
        .in("id", logsDescartados);
      console.warn(
        `[wapi-send-products] REANUDAR: ${logsDescartados.length} log(s) ` +
          `marcados como fallido por producto descartado`,
      );
    }
  }

  if (messages.length === 0) {
    // Ningún producto de este chunk produjo mensajes válidos (todos sin
    // imagen / chat_id inválido). Aún así debemos continuar con los
    // productos restantes — si no, la cadena de chunks se rompería aquí.
    await reinvokeRemaining();
    // Si además éste era el último chunk, el resumen sigue tocando: los
    // chunks anteriores sí enviaron productos.
    const resumen = enviarResumen && remainingIds.length === 0
      ? await enviarResumenFinal()
      : 0;
    return {
      enviados: 0,
      fallidos: 0,
      batch_id: null,
      skipped: true,
      resumen_entregas: resumen,
    };
  }

  // Log del envío. En modo reanudar NO insertamos: reutilizamos las filas
  // existentes (así la tanda original se completa en vez de duplicarse) y
  // las devolvemos a `pendiente` para que la UI muestre el progreso vivo.
  let logIdsOrdenados: Array<number | null>;
  if (esReanudacion) {
    logIdsOrdenados = messages.map(
      (m) => logIdPorPar.get(`${m._meta.id_producto}|${m._meta.chat_id}`) ?? null,
    );
    const aReiniciar = logIdsOrdenados.filter((v): v is number => v != null);
    if (aReiniciar.length > 0) {
      await admin
        .from("app_wapi_envio_log")
        .update({
          estado: "pendiente",
          error_code: null,
          error_message: null,
        })
        .in("id", aReiniciar);
    }
  } else {
    const logRows = messages.map((m) => ({
      id_tienda: idTienda,
      id_sesion: idSesion,
      id_programacion: idProgramacion ?? null,
      id_producto: m._meta.id_producto,
      chat_id: m._meta.chat_id,
      tipo_envio: tipoEnvio,
      estado: "pendiente",
    }));
    const { data: insertedLogs } = await admin
      .from("app_wapi_envio_log")
      .insert(logRows)
      .select("id");
    logIdsOrdenados = messages.map((_, i) => (insertedLogs ?? [])[i]?.id ?? null);
  }

  // minMs / maxMs / MAX_PARALLEL_FANOUT se declararon arriba (necesarios
  // para estimar el presupuesto de tiempo del chunk). Aquí sólo los usamos.

  // Generamos un batchId único para correlación interna (no se envía al WAPI)
  const batchId = `b_${idTienda}_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  const logIds = logIdsOrdenados;

  // Reagrupar mensajes por id_producto. Conservar el índice global para
  // mapear correctamente al logId correspondiente.
  type Indexed = { idx: number; msg: typeof messages[number]; logId: number | null };
  const grouped = new Map<number, Indexed[]>();
  for (let i = 0; i < messages.length; i++) {
    const m = messages[i];
    const arr = grouped.get(m._meta.id_producto) ?? [];
    arr.push({ idx: i, msg: m, logId: logIds[i] ?? null });
    grouped.set(m._meta.id_producto, arr);
  }
  const productOrder = Array.from(grouped.keys());

  if (messages[0]) {
    const m0 = messages[0];
    console.log(
      `[wapi-send-products] batchId=${batchId} session=${wapiSessionId} ` +
        `productos=${productOrder.length} msgs=${messages.length} ` +
        `fanout=${MAX_PARALLEL_FANOUT} delay=[${minMs / 1000}s..${maxMs / 1000}s] ` +
        `sample chatId=${m0.chatId} captionLen=${m0.content.caption.length}`,
    );
  }

  let enviados = 0;
  let fallidos = 0;

  // Helper: dispara UN mensaje y actualiza su log row. Devuelve success bool.
  //
  // Reintenta hasta RETRY_MAX_ATTEMPTS con backoff exponencial + jitter
  // mientras el error sea transitorio. El backoff también funciona como
  // anti-ban: si la sesión WAPI está rechazando conexiones, insistir de
  // inmediato sólo empeora las cosas.
  const dispatchOne = async (it: Indexed): Promise<boolean> => {
    const m = it.msg;
    let ultimoCode = "SEND_ERROR";
    let ultimoMsg = "Error desconocido";

    for (let intento = 1; intento <= RETRY_MAX_ATTEMPTS; intento++) {
      const single = await wapi.sendImage(
        wapiSessionId,
        m.chatId,
        m.content.image.url,
        m.content.caption,
        m.content.image.mimetype,
      );

      if (single.success) {
        if (it.logId) {
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
            .eq("id", it.logId);
        }
        if (intento > 1) {
          console.log(
            `[wapi-send-products] recuperado idx=${it.idx} chat=${m.chatId} ` +
              `en el intento ${intento}`,
          );
        }
        return true;
      }

      ultimoCode = single.error?.code ?? "SEND_ERROR";
      ultimoMsg = single.error?.message ?? "Error desconocido";

      const puedeReintentar = intento < RETRY_MAX_ATTEMPTS &&
        esReintentable(ultimoCode);
      console.error(
        `[wapi-send-products] fallido idx=${it.idx} chat=${m.chatId} ` +
          `intento ${intento}/${RETRY_MAX_ATTEMPTS} (${ultimoCode}): ${ultimoMsg}` +
          (puedeReintentar ? " — reintentando" : ""),
      );
      if (!puedeReintentar) break;

      // Backoff exponencial (4s, 8s…) con jitter ±25% para no sincronizar
      // los reintentos de todo un sub-lote contra el mismo instante.
      const base = RETRY_BASE_MS * Math.pow(2, intento - 1);
      const espera = Math.round(base * (0.75 + Math.random() * 0.5));
      await new Promise((res) => setTimeout(res, espera));
    }

    if (it.logId) {
      await admin.from("app_wapi_envio_log")
        .update({
          estado: "fallido",
          error_code: ultimoCode,
          error_message: `${ultimoMsg} (tras ${RETRY_MAX_ATTEMPTS} intentos)`,
        })
        .eq("id", it.logId);
    }
    return false;
  };

  for (let p = 0; p < productOrder.length; p++) {
    const idProd = productOrder[p];
    const targets = grouped.get(idProd) ?? [];

    // Dentro del mismo producto, lanzar en sub-lotes paralelos.
    for (let off = 0; off < targets.length; off += MAX_PARALLEL_FANOUT) {
      const slice = targets.slice(off, off + MAX_PARALLEL_FANOUT);
      const results = await Promise.allSettled(slice.map(dispatchOne));
      for (const r of results) {
        if (r.status === "fulfilled" && r.value) enviados++;
        else fallidos++;
      }
      // Mini-pausa entre sub-lotes del mismo producto (1s) para no abrir
      // demasiadas conexiones simultáneas al WAPI.
      if (off + MAX_PARALLEL_FANOUT < targets.length) {
        await new Promise((res) => setTimeout(res, 1_000));
      }
    }

    // Delay aleatorio entre productos (no después del último).
    if (p < productOrder.length - 1) {
      const jitter = minMs + Math.floor(Math.random() * (maxMs - minMs));
      await new Promise((res) => setTimeout(res, jitter));
    }
  }

  // Encolar el siguiente chunk (si quedaron productos fuera del presupuesto
  // de tiempo). Cada continuación corre en su propio worker con 400s frescos.
  await reinvokeRemaining();

  // Resumen final: sólo el último chunk de la cadena lo manda.
  let resumenEntregas = 0;
  if (enviarResumen && remainingIds.length === 0) {
    // Pequeña pausa tras el último producto antes del texto (anti-ban).
    await new Promise((res) => setTimeout(res, minMs));
    resumenEntregas = await enviarResumenFinal();
  }

  return {
    enviados,
    fallidos,
    batch_id: batchId,
    mode: "fanout-per-product",
    fanout: MAX_PARALLEL_FANOUT,
    chunk_size: chunkIds.length,
    remaining: remainingIds.length,
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

  // Al reanudar, product_ids/destinations se derivan de los propios logs, así
  // que sólo exigimos id_sesion + la lista de logs a reintentar.
  if (!Number.isFinite(idSesion)) {
    return errorResponse("id_sesion es obligatorio", 400);
  }
  if (!esReanudacion && (productIds.length === 0 || destinations.length === 0)) {
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
  const totalMensajes = esReanudacion
    ? resumeLogIds.length
    : productIds.length * destinations.length;
  // Con fan-out paralelo por producto, el tiempo de pared depende del
  // número de productos (no del total de mensajes): un delay aleatorio
  // se aplica ENTRE productos. Sub-lotes paralelos añaden ~1s extra.
  const productosEstimados = esReanudacion
    ? Math.max(1, Math.ceil(resumeLogIds.length / Math.max(1, destinations.length)))
    : productIds.length;
  const estimadoSeg = Math.round(
    Math.max(0, productosEstimados - 1) * ((delayMin + delayMax) / 2),
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
    enviarResumen: body.send_summary ?? true,
    ...(Array.isArray(body.summary_product_ids) &&
      body.summary_product_ids.length > 0
      ? {
        summaryProductIds: body.summary_product_ids
          .map(Number)
          .filter((n) => Number.isFinite(n)),
      }
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
    total_mensajes_estimados: totalMensajes,
    tiempo_estimado_segundos: estimadoSeg,
    delay_segundos: { min: delayMin, max: delayMax },
    message: esReanudacion
      ? `Reanudando envío: ${totalMensajes} mensaje(s) pendientes. ` +
        `Tiempo estimado: ~${Math.max(1, Math.ceil(estimadoSeg / 60))} min. ` +
        `Revisa el historial para ver el progreso.`
      : `Envío iniciado en segundo plano. ${totalMensajes} mensajes en cola. ` +
        `Tiempo estimado: ~${Math.ceil(estimadoSeg / 60)} min. ` +
        `Puedes seguir usando la app — revisa el historial para ver el progreso.`,
  });
}

// Sólo registrar el listener cuando este archivo es el entry-point real
// de la edge function (i.e. está siendo servido como `/wapi-send-products`).
// Cuando otro módulo lo IMPORTA (p.ej. `wapi-cron-dispatch` para reusar
// `dispatchProducts`), `import.meta.main` es false y NO se registra el
// listener — así evitamos que un Deno.serve fantasma intercepte requests
// destinadas a la otra función.
if (import.meta.main) {
  Deno.serve(handleSendProducts);
}
