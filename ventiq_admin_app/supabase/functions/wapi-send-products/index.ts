// POST /functions/v1/wapi-send-products
// Body:
// {
//   id_sesion: number,
//   product_ids: number[],
//   destinations: Array<{ tipo: 'numero'|'grupo', chat_id: string, etiqueta?: string }>,
//   message_template?: string,
//   delay_min_seconds?: number,   // anti-ban (default 5)
//   delay_max_seconds?: number,   // anti-ban (default 10)
//   tipo_envio?: 'manual'|'programado'
// }
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
}

// Trunca caption (WhatsApp permite máx 1024 chars en captions de imagen)
function safeCaption(text: string): string {
  if (text.length <= 1020) return text;
  return text.slice(0, 1017) + "...";
}

// Encabezados rotativos estilo marketing — se elige uno aleatorio por mensaje
// para variar el tono entre productos (no spam-y).
const MARKETING_HEADERS = [
  "✨ *¡NUEVO EN LA TIENDA!* ✨",
  "🔥 *OFERTA DEL DÍA* 🔥",
  "🎁 *SORPRESA PARA TI*",
  "⭐ *RECOMENDADO*",
  "🛍️ *DESCÚBRELO HOY*",
  "💎 *EXCLUSIVO*",
  "🚀 *RECIÉN LLEGADO*",
  "🎉 *NO TE LO PUEDES PERDER*",
];

const MARKETING_CTAS = [
  "👉 *¡Pídelo ahora!* Disponibilidad limitada.",
  "📲 Escríbenos para hacer tu pedido.",
  "🛒 *¡Apártalo antes que se agote!*",
  "💬 Responde a este mensaje para reservarlo.",
  "⚡ Stock limitado — *no esperes más.*",
  "🎯 *Cómpralo hoy* y recíbelo pronto.",
];

function pick<T>(arr: T[], seed: number): T {
  return arr[seed % arr.length];
}

function formatPrice(n: number): string {
  // Formato con separador de miles y sin decimales innecesarios.
  if (!Number.isFinite(n) || n <= 0) return "";
  const fixed = n % 1 === 0 ? n.toFixed(0) : n.toFixed(2);
  return fixed.replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

/**
 * Construye un caption estilo marketing: encabezado llamativo, nombre del
 * producto en negrita, descripción opcional, precio destacado, separadores
 * visuales y CTA al final. Truncado a 1020 chars (límite WhatsApp).
 *
 * Si se pasa un `template`, se respeta y se reemplazan los placeholders
 * `{nombre}`, `{descripcion}`, `{precio}`.
 */
function buildCaption(
  template: string | undefined,
  p: {
    denominacion: string;
    descripcion?: string | null;
    precio?: number | null;
    sku?: string | null;
    categoria?: string | null;
    stock?: number | null;
  },
  seed: number,
): string {
  const stockStr = p.stock != null && p.stock > 0 ? formatPrice(p.stock) : "";
  if (template && template.includes("{nombre}")) {
    return safeCaption(
      template
        .replaceAll("{nombre}", p.denominacion ?? "")
        .replaceAll("{descripcion}", p.descripcion ?? "")
        .replaceAll("{precio}", p.precio != null ? formatPrice(p.precio) : "")
        .replaceAll("{categoria}", p.categoria ?? "")
        .replaceAll("{sku}", p.sku ?? "")
        .replaceAll("{stock}", stockStr),
    );
  }

  const header = pick(MARKETING_HEADERS, seed);
  const cta = pick(MARKETING_CTAS, seed + 1);
  const sep = "━━━━━━━━━━━━━━";

  const parts: string[] = [];
  parts.push(header);
  parts.push("");
  parts.push(`🛍️ *${p.denominacion.trim()}*`);

  if (p.descripcion && p.descripcion.trim()) {
    parts.push("");
    // Descripción en cursiva (WhatsApp: _texto_)
    const desc = p.descripcion.trim().replace(/\s+/g, " ");
    parts.push(`_${desc}_`);
  }

  parts.push("");
  parts.push(sep);

  if (p.precio != null && p.precio > 0) {
    parts.push(`💰 *Precio:* $${formatPrice(p.precio)} CUP`);
  }
  if (p.categoria && p.categoria.trim()) {
    parts.push(`🏷️ ${p.categoria.trim()}`);
  }
  // Stock disponible — solo mostramos cuando hay existencia real.
  // Si quedan pocas unidades añadimos un toque de urgencia.
  if (p.stock != null && p.stock > 0) {
    if (p.stock <= 5) {
      parts.push(`⚠️ *¡Solo ${formatPrice(p.stock)} disponibles!*`);
    } else {
      parts.push(`📦 *Disponibles:* ${formatPrice(p.stock)} unidades`);
    }
  }
  parts.push(sep);
  parts.push("");
  parts.push(cta);

  return safeCaption(parts.join("\n"));
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
}) {
  const {
    admin, idSesion, idTienda, wapiSessionId, productIds,
    destinations, template, delayMin, delayMax, tipoEnvio, idProgramacion,
  } = args;

  if (productIds.length === 0 || destinations.length === 0) {
    return { enviados: 0, fallidos: 0, batch_id: null, skipped: true };
  }

  // Cargar productos (con SKU + categoría via JOIN para captions marketing)
  const { data: productos, error: prodErr } = await admin
    .from("app_dat_producto")
    .select(
      "id, denominacion, descripcion, imagen, sku, app_dat_categoria(denominacion)",
    )
    .in("id", productIds);
  if (prodErr) throw new Error(`Error cargando productos: ${prodErr.message}`);

  // Cargar precio venta (último vigente por producto).
  // `app_dat_precio_venta` es un histórico: cada producto puede tener N filas
  // (una por cada cambio de precio). El precio actual es el de mayor `id`.
  // Traemos todo el histórico ordenado por id desc y nos quedamos con la
  // primera ocurrencia por producto (la más reciente).
  const { data: precios } = await admin
    .from("app_dat_precio_venta")
    .select("id, id_producto, precio_venta_cup, precio_venta_usd")
    .in("id_producto", productIds)
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
  // ───────────────────────────────────────────────────────────────────
  const stockMap = new Map<number, number>();
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
          .in("id_producto", productIds)
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
      }
    }
    console.log(
      `[wapi-send-products] stock calculado para ${stockMap.size}/${productIds.length} productos`,
    );
  } catch (e) {
    // No bloqueamos el envío si falla el cálculo de stock — solo se
    // omite del caption.
    console.warn(
      `[wapi-send-products] error calculando stock: ${(e as Error).message ?? e}`,
    );
  }

  // Construir mensajes: filtrar productos sin imagen
  const messages: Array<{
    chatId: string;
    type: "image";
    content: { image: { url: string; mimetype?: string }; caption: string };
    // metadata propia para mapear al log
    _meta: { id_producto: number; chat_id: string };
  }> = [];

  const skipped: Array<{ id_producto: number; reason: string }> = [];
  let seedCounter = Math.floor(Math.random() * 1000); // rotación de headers/CTAs
  for (const p of productos ?? []) {
    if (!p.imagen || typeof p.imagen !== "string" || !p.imagen.trim()) {
      skipped.push({ id_producto: p.id, reason: "sin imagen" });
      continue;
    }
    const imageUrl = p.imagen.trim();
    // WAPI requiere URL pública http(s). Data URLs y blobs no funcionan.
    if (!/^https?:\/\//i.test(imageUrl)) {
      skipped.push({
        id_producto: p.id,
        reason: `imagen no es URL http(s): ${imageUrl.slice(0, 40)}…`,
      });
      continue;
    }
    const precio = precioMap.get(p.id) ?? 0;
    // Categoría llega como objeto (PostgREST embed) o null.
    const catRaw = (p as any).app_dat_categoria;
    const categoria = Array.isArray(catRaw)
      ? catRaw[0]?.denominacion ?? null
      : catRaw?.denominacion ?? null;
    const stock = stockMap.get(p.id) ?? null;
    const caption = buildCaption(
      template,
      {
        denominacion: p.denominacion,
        descripcion: p.descripcion,
        precio,
        sku: (p as any).sku ?? null,
        categoria,
        stock,
      },
      seedCounter++,
    );
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

    for (const d of destinations) {
      if (!d.chat_id || typeof d.chat_id !== "string") continue;
      // chatId debe acabar en @c.us (números) o @g.us (grupos)
      if (!/@(c|g)\.us$/.test(d.chat_id)) {
        skipped.push({
          id_producto: p.id,
          reason: `chat_id inválido: ${d.chat_id}`,
        });
        continue;
      }
      messages.push({
        chatId: d.chat_id,
        type: "image",
        content: { image: { url: imageUrl, mimetype }, caption },
        _meta: { id_producto: p.id, chat_id: d.chat_id },
      });
    }
  }
  if (skipped.length) {
    console.warn(
      `[wapi-send-products] ${skipped.length} mensajes descartados antes del envío:`,
      JSON.stringify(skipped.slice(0, 10)),
    );
  }

  if (messages.length === 0) {
    return { enviados: 0, fallidos: 0, batch_id: null, skipped: true };
  }

  // Insertar log "pendiente" para todos los mensajes (audit trail)
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

  // Anti-ban: rango de delays aleatorios entre lotes (mínimo 5s).
  // El delay aplica ENTRE productos, no entre destinatarios del mismo producto
  // (esos van en paralelo dentro de MAX_PARALLEL_FANOUT).
  const minMs = Math.max(5_000, delayMin * 1000);
  const maxMs = Math.max(minMs + 1_000, delayMax * 1000);

  // Cuántos destinos del mismo producto se disparan a la vez. Mantenerlo
  // bajo evita ráfagas que crucen el techo de 60 req/min de OpenWA y los
  // 20 msgs/min/sesión recomendados para evitar bans.
  const MAX_PARALLEL_FANOUT = 5;

  // Generamos un batchId único para correlación interna (no se envía al WAPI)
  const batchId = `b_${idTienda}_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
  const logIds = (insertedLogs ?? []).map((l: any) => l.id);

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
  const dispatchOne = async (it: Indexed): Promise<boolean> => {
    const m = it.msg;
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
          })
          .eq("id", it.logId);
      }
      return true;
    }
    console.error(
      `[wapi-send-products] fallido idx=${it.idx} chat=${m.chatId} ` +
        `(${single.error?.code}): ${single.error?.message}`,
    );
    if (it.logId) {
      await admin.from("app_wapi_envio_log")
        .update({
          estado: "fallido",
          error_code: single.error?.code ?? "SEND_ERROR",
          error_message: single.error?.message ?? "Error desconocido",
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

  return {
    enviados,
    fallidos,
    batch_id: batchId,
    mode: "fanout-per-product",
    fanout: MAX_PARALLEL_FANOUT,
  };
}

Deno.serve(async (req) => {
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
  if (!Number.isFinite(idSesion) || productIds.length === 0 || destinations.length === 0) {
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
  const totalMensajes = productIds.length * destinations.length;
  // Con fan-out paralelo por producto, el tiempo de pared depende del
  // número de productos (no del total de mensajes): un delay aleatorio
  // se aplica ENTRE productos. Sub-lotes paralelos añaden ~1s extra.
  const estimadoSeg = Math.round(
    Math.max(0, productIds.length - 1) * ((delayMin + delayMax) / 2),
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
    total_mensajes_estimados: totalMensajes,
    tiempo_estimado_segundos: estimadoSeg,
    delay_segundos: { min: delayMin, max: delayMax },
    message:
      `Envío iniciado en segundo plano. ${totalMensajes} mensajes en cola. ` +
      `Tiempo estimado: ~${Math.ceil(estimadoSeg / 60)} min. ` +
      `Puedes seguir usando la app — revisa el historial para ver el progreso.`,
  });
});
