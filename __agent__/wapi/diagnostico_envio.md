# Diagnóstico de envío WAPI — tienda 177 / sesión 22

**Autor:** `forense-db` (task-1, forense de datos) · **Fecha:** 2026-10-23 ~11:10 (America/Havana)
**Alcance:** análisis **solo lectura** de Supabase (`mcp__supabase__execute_sql`) y logs unificados ClickHouse (`mcp__supabase__query_logs`). Cero escrituras en Supabase. No se tocó código de la edge function.
**Motor analizado:** `ventiq_admin_app/supabase/functions/wapi-send-products/index.ts` + `_shared/wapi_client.ts`.

> ⚠️ **Nota de revisión de código:** otro miembro del equipo estaba editando `index.ts` durante este análisis (pasó de 1898 a 1978 líneas). Las referencias de línea de este informe corresponden a la revisión **que produjo los datos observados**. Al cierre del análisis el fix de la política de reintento ya estaba apareciendo en el archivo (`esIdemEnProgreso()` / `esIdemResultadoDesconocido()`, líneas 192-225). Ver *Preguntas abiertas* §P5.

---

## 0. Contexto mínimo verificado

| Dato | Valor | Fuente |
|---|---|---|
| Tienda / sesión | `id_tienda=177`, `id_sesion=22` (única en toda la tabla) | `app_wapi_envio_log` |
| `wapi_session_id` | `3f394210-aa7e-4279-a330-b5639d3024e7` | `app_wapi_sesion` |
| Host OpenWA | `http://89.40.7.25:2785` | logs `NETWORK_ERROR` |
| Estado de sesión **durante** el incidente | CONNECTED/READY (envíos saliendo) | inferido del éxito de 24 envíos |
| Estado de sesión **ahora** | `FAILED` / `raw_status=FAILED`, `last_error_code=HTTP_400`, `last_error_message="Session is not started. Call POST /sessions/:sessionId/start first."`, `recovery_attempts=1`, `last_status_at=2026-10-23 11:00:29-04` | `app_wapi_sesion` |
| Programación 13 "Difusión diaria" | `activa=false`, `last_run_at=2026-09-07`, 67 productos, 5 destinatarios | `app_wapi_programacion` |
| `id_programacion` en TODAS las filas del 23-oct | `NULL` | `app_wapi_envio_log` |

**Consecuencia:** los envíos del 23-oct fueron **manuales** (dos invocaciones de usuario), **no** del planificador. Dos cadenas distintas corrieron a la vez:

| Cadena | batchId | `destinos` | arranque (UTC-4) | log |
|---|---|---|---|---|
| A | `b_177_1792766659660_696293` | **1** | 10:44:19 | `productos=70 destinos=1` |
| B | `b_177_1792766891001_722542` | **5** | 10:48:11 | `productos=70 destinos=5` |

La cadena A se reencoló por presupuesto (`corte por presupuesto a los 254s: 21 ok, 49 para el worker siguiente`) manteniendo `destinos=1`; la cadena B arrancó **encima** de ella, misma sesión OpenWA.

**Destinos** (`app_wapi_destinatario`, 6 grupos `@g.us`):

| chat_id | etiqueta | en programación 13 |
|---|---|---|
| `120363172271515786@g.us` | CARNAVAL #3 | sí |
| `120363195152592934@g.us` | CARNAVAL #1 | sí |
| `120363409451879219@g.us` | CARNAVAL #4 | sí |
| `120363406746096914@g.us` | CARNAVAL #5 | sí |
| `120363266453891641@g.us` | CARNAVAL #2 | sí |
| `120363423044527374@g.us` | **Inventtia** (id 9, `id_tienda=177`) | **no** |

Orden real de despacho de la cadena B (por `id` de log ascendente): **#3 → #1 → #4 → #5 → #2**.

---

## 1. Taxonomía completa de `estado` / `error_code`

```sql
select estado, error_code, count(*) as n,
       min(created_at) as first_seen, max(created_at) as last_seen,
       count(mensaje_id) as con_mensaje_id, count(sent_at) as con_sent_at
from public.app_wapi_envio_log
group by 1,2 order by n desc;
```

Resultado crudo (316 filas, todas tienda 177 / sesión 22):

| estado | error_code | n | first_seen | last_seen | con `mensaje_id` | con `sent_at` |
|---|---|---|---|---|---|---|
| fallido | `HTTP_500` | **263** | 2026-10-19 15:53:39 | 2026-10-20 11:44:03 | 0 | 0 |
| enviado | `null` | 27 | 2026-10-20 12:37:01 | 2026-10-23 10:48:11 | 27 | 27 |
| fallido | `IDEMPOTENCY_KEY_IN_PROGRESS` | **15** | 2026-10-23 10:48:11 | 2026-10-23 10:55:58 | **0** | 0 |
| fallido | `PRODUCT_TIMEOUT` | **5** | 2026-10-23 10:48:11 | 2026-10-23 10:53:32 | 0 | 0 |
| pendiente | `null` | 5 | 2026-10-23 10:56:13 | 2026-10-23 10:56:57 | 0 | 0 |
| fallido | `IDEMPOTENCY_OUTCOME_UNKNOWN` | 1 | 2026-10-23 10:56:13 | 2026-10-23 10:56:13 | 0 | 0 |

```sql
select id_tienda, id_sesion, count(*), count(*) filter (where estado='enviado') enviado,
       count(*) filter (where estado='fallido') fallido,
       count(*) filter (where estado='pendiente') pendiente
from public.app_wapi_envio_log group by 1,2;
-- 177 | 22 | 316 | 27 | 284 | 5
```

**Interpretación.** Hay **dos incidentes distintos**, no uno:
1. **Ola `HTTP_500`** (263 filas, 19→20-oct): OpenWA devolviendo `Internal server error` de forma sostenida. **Ajeno** al problema de idempotencia.
2. **Cascada de idempotencia del 23-oct** (15 + 1 + 5): el objeto de este informe.

Ninguna fila de la tabla tiene `mensaje_id` salvo las 27 `enviado`. **Nunca** aparece `ACK_ERROR` ni `MESSAGE_FAILED`: el webhook no ha marcado ni corregido una sola fila en toda la historia de la tabla.

---

## 2. Volumen diario (la ventana de 14 días no existe)

```sql
select (created_at at time zone 'America/Havana')::date as dia, count(*) total,
       count(*) filter (where estado='enviado') enviado,
       count(*) filter (where estado='fallido') fallido,
       count(*) filter (where estado='pendiente') pendiente,
       count(distinct chat_id) destinos
from public.app_wapi_envio_log group by 1 order by 1;
```

| día | total | enviado | fallido | pendiente | destinos |
|---|---|---|---|---|---|
| 2026-10-19 | 260 | 0 | 260 | 0 | 5 |
| 2026-10-20 | 6 | 3 | 3 | 0 | 1 |
| 2026-10-23 | 50 | 24 | **21** | 5 | 6 |

**Interpretación.** La tabla **solo contiene 3 días** (19, 20 y 23 de octubre); no hay filas del 21 ni 22. La pregunta "últimos 14 días" **no es respondible** con estos datos: o la tabla se truncó/limpió, o la difusión estuvo caída. Lo que sí se puede afirmar: **el 23-oct falló el 42% de lo intentado** (21 de 50), contra 0% el 20-oct (3 de 6) y 100% el 19-oct.

---

## 3. Latencia real por mensaje — y el truncamiento a 45 s

```sql
with s as (
  select id, chat_id, sent_at, created_at,
         extract(epoch from (sent_at-created_at)) as dur_s,
         extract(epoch from (sent_at - lag(sent_at)
                 over (partition by created_at order by sent_at))) as delta_prev_s,
         count(*) over (partition by created_at) as tam_lote
  from public.app_wapi_envio_log where estado='enviado')
select tam_lote, count(*) n,
       round(min(dur_s)::numeric,1) min_dur,
       round(percentile_cont(0.5) within group (order by dur_s)::numeric,1) p50_dur,
       round(max(dur_s)::numeric,1) max_dur,
       round(avg(delta_prev_s)::numeric,1) avg_delta,
       round(max(delta_prev_s)::numeric,1) max_delta,
       count(*) filter (where delta_prev_s > 30) delta_gt30,
       count(*) filter (where dur_s > 45) dur_gt45
from s group by 1 order by 1;
```

Resultado crudo (las 27 filas `enviado`):

| tam_lote | n | min_dur | p50_dur | max_dur | avg_delta | max_delta | delta>30s | dur>45s |
|---|---|---|---|---|---|---|---|---|
| 1 (cadena A, 1 destino) | 24 | **0.8 s** | **2.5 s** | **31.8 s** | – | – | 0 | 0 |
| 3 (cadena B, 5 destinos) | 3 | 27.2 s | 67.4 s | 95.2 s | **34.0 s** | **40.2 s** | 1 | 2 |

Definiciones: `dur_s` = `sent_at − created_at` (espera en cola, acumulativa dentro del lote); `delta_prev_s` = `sent_at − sent_at` anterior del mismo lote ≈ **duración real del envío** (+ 1.5 s de `FANOUT_PAUSE_MS`).

**Interpretación — el punto clave de este informe:**
- **Ningún envío con éxito registra un `delta_prev` > 40.2 s**, y solo 1 supera 30 s. Esto **no** significa que la latencia máxima sea 40 s: es **truncamiento por censura**. `TIMEOUT_MEDIA_MS = 45_000` aborta el cliente a los 45 s, así que cualquier envío que tarde más de 45 s **no puede producir `sent_at`** y desaparece de la muestra. La distribución está cortada por la derecha exactamente donde está el problema.
- La muestra superviviente se concentra entre **27 y 40 s**: peligrosamente pegada al umbral de 45 s. Un envío normal de 38 s + 1.5 s de pausa + latencia de red entra y sale del timeout según el día.
- En lotes de 1 destino la mediana es **2.5 s** (sanos, 10:44-10:47:35); el primer outlier es **31.8 s** (prod 7319, 10:47:56) — el cambio de régimen.
- `dur_s > 45` = 2 filas, pero son **tiempo en cola** (95.2 s y 67.4 s acumulados del 2.º y 3.er destino), no duración de un envío.

Cronología del cambio de régimen (filas `enviado` de la cadena A a Inventtia):

| id | producto | created | sent | dur | nota |
|---|---|---|---|---|---|
| 24460 | 10605 | 10:44:20.471 | 10:44:25.370 | 4.9 s | |
| 24472 | 5272 | 10:46:31.316 | 10:46:33.852 | 2.5 s | |
| 24479 | 9853 | 10:47:43.803 | 10:47:49.320 | 5.5 s | `NETWORK_ERROR` → recuperado en intento 2 |
| 24480 | **7319** | 10:47:56.319 | 10:48:28.125 | **31.8 s** | **primer outlier** |
| 24481 | 10605 | 10:48:11.562 | 10:48:38.787 | 27.2 s | cadena B, destino 1/5 |
| 24482 | 10605 | 10:48:11.562 | 10:49:18.937 | 67.4 s | destino 2/5 (delta 40.2 s) |
| 24483 | 10605 | 10:48:11.562 | 10:49:46.721 | 95.2 s | destino 3/5 (delta 27.8 s) |

A partir de **10:48:34** ya **no vuelve a registrarse ni un solo `enviado`** (salvo los 3 de este lote). Todo lo demás son timeouts.

---

## 4. **Hallazgo central**: la secuencia exacta TIMEOUT → reintento → 409 IN_PROGRESS

### 4.1 La cadena causal en los logs (evidencia directa)

```sql
select timestamp, event_message
from logs
where source='function_logs' and event_message like '%wapi-send-products%'
order by timestamp limit 200;
```
(ventana 10:30–11:10; la tabla ClickHouse es `logs`, y el campo de tiempo es `timestamp`)

Secuencia cruda reproducida (UTC en ClickHouse = UTC-4 + 4 h; 14:49 UTC = 10:49 -04):

```
14:49:19.469  [wapi-send-products] fallido prod=7318 chat=120363423044527374@g.us
              intento 1/3 (TIMEOUT): WAPI no respondió en 45s — reintentando
14:49:24.298  [wapi-send-products] fallido prod=7318 chat=120363423044527374@g.us
              intento 2/3 (IDEMPOTENCY_KEY_IN_PROGRESS): A request with this
              Idempotency-Key is still running. Retry after it finishes.

14:50:33.290  fallido prod=10605 chat=120363406746096914@g.us intento 1/3 (TIMEOUT): WAPI no respondió en 45s — reintentando
14:50:43.735  fallido prod=10605 chat=120363406746096914@g.us intento 2/3 (IDEMPOTENCY_KEY_IN_PROGRESS): A request with this Idempotency-Key is still running. Retry after it finishes.
14:50:43.820  [wapi-send-products] prod=10605 agotó su ventana: 1 destino(s) sin enviar
14:50:43.820  [wapi-send-products] corte por presupuesto a los 153s: 1 ok, 69 para el worker siguiente

14:53:39.775  fallido prod=9874 chat=120363423044527374@g.us intento 1/3 (NETWORK_ERROR): ... connection reset by peer (os error 104) — reintentando
14:54:29.280  fallido prod=9874 chat=120363423044527374@g.us intento 2/3 (TIMEOUT): WAPI no respondió en 45s — reintentando
14:54:41.906  fallido prod=9874 chat=120363423044527374@g.us intento 3/3 (IDEMPOTENCY_KEY_IN_PROGRESS): A request with this Idempotency-Key is still running. Retry after it finishes.

14:56:56.184  fallido prod=7345 chat=120363172271515786@g.us intento 1/3 (HTTP_500): Internal server error — reintentando
14:57:01.304  fallido prod=7345 chat=120363172271515786@g.us intento 2/3 (IDEMPOTENCY_OUTCOME_UNKNOWN): An earlier request with this Idempotency-Key failed and the message may have been sent. Check the chat; to send again, use a new key.
```

Gaps medidos entre el log de intento 1 y el de intento 2: **4.5 s – 15.0 s** (consistente con `RETRY_BASE_MS = 4_000` ± jitter 25 % + tiempo de conexión).

### 4.2 Reconciliación completa: cada fila de la BD explicada por los logs

```sql
select splitByString('chat=', event_message)[2] as chat_attempt, count(*) as n
from logs where source='function_logs'
  and event_message like '%[wapi-send-products] fallido prod=%'
group by 1 order by n desc;
```

| chat_id | intento 1 | intento 2 | intento 3 | intentos totales |
|---|---|---|---|---|
| `120363423044527374` (Inventtia) | 6×TIMEOUT + 3×NETWORK_ERROR | 6×IN_PROGRESS + 2×TIMEOUT | 2×IN_PROGRESS | **19** |
| `120363172271515786` (#3) | 2×TIMEOUT + 1×HTTP_500 | 2×IN_PROGRESS + 1×OUTCOME_UNKNOWN | 0 | 6 |
| `120363409451879219` (#4) | 2×TIMEOUT | 2×IN_PROGRESS | 0 | 4 |
| `120363195152592934` (#1) | 2×TIMEOUT | 2×IN_PROGRESS | 0 | 4 |
| `120363406746096914` (#5) | 1×TIMEOUT | 1×IN_PROGRESS | 0 | 2 |
| `120363266453891641` (#2) | **0** | **0** | **0** | **0** |

**El cuadre cierra exactamente:**
- 15 filas `IDEMPOTENCY_KEY_IN_PROGRESS` = 13 con 2 intentos + 2 con 3 intentos (`"(tras 3 intento(s))"`).
- 1 fila `IDEMPOTENCY_OUTCOME_UNKNOWN` = el `HTTP_500` de prod 7345 → intento 2.
- 5 filas `PRODUCT_TIMEOUT` = **5 filas con CERO líneas de intento** (`#5`×2 + `#2`×3). Nunca se despacharon.

### 4.3 Por qué el código marca `fallido` (mecanismo)

1. `dispatchOne` llama `wapi.sendImage(..., e.logId ? \`wa-log-${e.logId}\` : undefined)` — **la misma clave en todos los intentos de la fila**, deliberadamente, para obtener el *replay* (comentario del propio código: *"si un TIMEOUT hizo que el mensaje sí saliera, el reintento con la misma clave devuelve el mismo mensajeId"*).
2. Intento 1: el cliente **aborta a los 45 s** (`TIMEOUT_MEDIA_MS`), pero **abortar el cliente no cancela el trabajo en el servidor OpenWA**. Error `TIMEOUT` → `esReintentable()` = `true` → backoff 4 s.
3. Intento 2, misma clave, ~4-15 s después: OpenWA responde `409` con `error.code = IDEMPOTENCY_KEY_IN_PROGRESS`.
4. `esReintentable("IDEMPOTENCY_KEY_IN_PROGRESS")` → `false`. **Dos motivos independientes**: no es `NETWORK_ERROR|SEND_ERROR|TIMEOUT`, y el regex `/^HTTP_(\d{3})$/` no casa con un código simbólico (el `code` viene del body `error.code`, no del status — `wapi_client.ts` línea ~125). Aunque hubiese casado como `HTTP_409`, la función sólo reintenta `408 / 429 / >=500`.
5. `puedeReintentar = intento < 3 && esReintentable(...)` → `false` → `break` → la fila se marca `fallido`.

**Consecuencia de registro:** la fila se guarda con el **código del ÚLTIMO intento**. El `TIMEOUT` real del intento 1 —el hecho físicamente relevante— **nunca se escribe en la BD**; solo queda en los logs de la edge function. Por eso la BD muestra `IDEMPOTENCY_KEY_IN_PROGRESS` y no `TIMEOUT`.

---

## 5. Distribución por chat_id (IDEMPOTENCY* y PRODUCT_TIMEOUT)

```sql
select chat_id,
  count(*) filter (where estado='enviado') enviados,
  count(*) filter (where error_code='IDEMPOTENCY_KEY_IN_PROGRESS') in_progress,
  count(*) filter (where error_code='IDEMPOTENCY_OUTCOME_UNKNOWN') unknown,
  count(*) filter (where error_code='PRODUCT_TIMEOUT') prod_timeout,
  count(*) filter (where estado='pendiente') pendiente
from public.app_wapi_envio_log
where created_at >= now() - interval '7 days'
group by 1 order by 3 desc, 5 desc;
```

| chat_id | etiqueta | enviados | IN_PROGRESS | OUTCOME_UNKNOWN | PRODUCT_TIMEOUT | pendiente | **fallido total** |
|---|---|---|---|---|---|---|---|
| `120363423044527374@g.us` | Inventtia | 21 | **8** | 0 | 0 | 1 | **8** |
| `120363172271515786@g.us` | #3 | 1 | 2 | 1 | 0 | 0 | **3** |
| `120363406746096914@g.us` | #5 | **0** | 1 | 0 | 2 | 1 | **3** |
| `120363266453891641@g.us` | #2 | **0** | 0 | 0 | 3 | 1 | **3** |
| `120363195152592934@g.us` | #1 | 1 | 2 | 0 | 0 | 1 | **2** |
| `120363409451879219@g.us` | #4 | 1 | 2 | 0 | 0 | 1 | **2** |
| | | 24 | 15 | 1 | 5 | 5 | **21** |

**Interpretación.** Inventtia concentra el 53% de los `IDEMPOTENCY_KEY_IN_PROGRESS` (8/15) y el 38% del total de fallidos del día (8/21) — **pero no es "el grupo lento"**: en la misma sesión y la misma hora había entregado 21 mensajes consecutivos en **2-5 s** cada uno (10:44:20→10:47:35). Acumula fallos porque es el **único destino de la cadena A**, que siguió avanzando producto a producto (~60 s por producto) contra una sesión ya saturada por la cadena B.

Los que **nunca recibieron un solo mensaje** son `#5` (`120363406746096914`) y `#2` (`120363266453891641`) — 6 filas fallidas, 0 envíos, y son exactamente las **posiciones 4.ª y 5.ª** del fan-out en serie.

---

## 6. Productos abandonados a mitad

```sql
select id_producto,
       count(*) total,
       count(*) filter (where estado='enviado') ok,
       count(*) filter (where estado='fallido') ko,
       count(*) filter (where estado='pendiente') pend,
       min(created_at) t
from public.app_wapi_envio_log
where created_at >= timestamptz '2026-10-23 10:48:00-04'
group by 1 order by t, 1;
```

| producto | lote | total | ok | ko | pend | desenlace |
|---|---|---|---|---|---|---|
| 10605 | 10:48:11.562 | 5 | 3 | 2 | 0 | destinos 1-3 OK; 4.º IN_PROGRESS; 5.º abandonado |
| 5260 | 10:50:44.703 | 5 | 0 | 5 | 0 | destinos 1-3 IN_PROGRESS; 4.º y 5.º abandonados |
| 11196 | 10:53:32.005 | 5 | 0 | 5 | 0 | ídem |
| 7345 | 10:56:13.840 | 5 | 0 | 1 | 4 | 1.º OUTCOME_UNKNOWN; sesión cayó; 4 quedan pendientes |
| 10418 | 10:56:57.696 | 1 | 0 | 0 | 1 | sesión cayó antes de intentar |

**Sí: el abandono es siempre por la cola del fan-out.** Reproducción aritmética del lote de 10605:
- destino 1 termina a los +27.2 s, destino 2 a +67.4 s, destino 3 a +95.2 s.
- destino 4 arranca a ~+96.7 s, su intento 1 muere a los 45 s → ~+142 s; intento 2 falla a ~+152 s.
- `Date.now() - inicioProducto > PRODUCT_MAX_MS (120_000)` → **abandonar los restantes** (`envios.slice(k+1)`), que quedan `PRODUCT_TIMEOUT` **sin haberse intentado** → "1 destino(s) sin enviar".

Con 3 envíos válidos ya se consumen ~95 s de los 120 s del techo por producto: **en un fan-out de 5 destinos a ~30 s por envío, la 4.ª y 5.ª posición no caben nunca**. `PRODUCT_TIMEOUT` es estructural, no accidental.

---

## 7. Filas `pendiente` — reanudables, pero la sesión está muerta

```sql
select id, id_producto, chat_id, estado, created_at, sent_at, mensaje_id
from public.app_wapi_envio_log where estado='pendiente' order by created_at, id;
```

| id | producto | chat_id | created_at | sent_at | mensaje_id |
|---|---|---|---|---|---|
| 24505 | 7345 | `120363195152592934` (#1) | 10:56:13.840 | null | null |
| 24506 | 7345 | `120363409451879219` (#4) | 10:56:13.840 | null | null |
| 24507 | 7345 | `120363406746096914` (#5) | 10:56:13.840 | null | null |
| 24508 | 7345 | `120363266453891641` (#2) | 10:56:13.840 | null | null |
| 24509 | 10418 | `120363423044527374` (Inventtia) | 10:56:57.696 | null | null |

**Interpretación.** Las 5 son técnicamente reanudables (`estado='pendiente'`, sin `error_code`) y el diseño lo prevé (*"es trabajo por hacer, no un fallo"*). Pero **no se pueden reanudar hoy**: la sesión 22 está `FAILED` (`HTTP_400 Session is not started`). Requieren `POST /sessions/:sessionId/start` (o el botón "reiniciar") antes de reintentar. Son **trabajo perdido de 2 productos**, no falsos negativos.

---

## 8. **El `fallido` es terminal: no existe camino de reconciliación**

### 8.1 El webhook empareja por `mensaje_id`, que es NULL en todas las filas fallidas

`wapi-webhook/index.ts` (handler `message.ack`, ~líneas 254-278):

```ts
} else if (ack >= 2) {
  await admin.from("app_wapi_envio_log")
    .update({ estado: "enviado", mensaje_id: msgId, sent_at: new Date().toISOString() })
    .eq("mensaje_id", msgId);          // ← UPDATE ... WHERE mensaje_id = <msgId>
}
```

Las 21 filas fallidas del 23-oct tienen `mensaje_id IS NULL`. El `UPDATE` **no casa ninguna fila** (`NULL = msgId` nunca es verdadero). Aunque WhatsApp/OpenWA entregue el ack con el `messageId` real de un mensaje que sí salió, **la BD no se entera y la fila se queda `fallido` para siempre**. No hay ninguna otra ruta que las corrija.

Evidencia corroborante — nunca ha llegado un ack negativo ni uno positivo huérfano: `ACK_ERROR` y `MESSAGE_FAILED` **no existen** en las 316 filas (ver §1).

### 8.2 El webhook no registra actividad en la ventana

```sql
select count(*) from logs where source='function_logs'
  and (event_message ilike '%webhook%' or event_message ilike '%message.ack%'
       or event_message ilike '%Evento %');
-- 0   (ventana 24 h)
```

Las 26 llamadas a `function_edge_logs` de la ventana se reparten entre `wapi-send-products` (`6810aeef…`) y 3 funciones de sondeo/recuperación; no hay tráfico identificable del webhook. **Cautela:** el handler solo loguea si vienen `deliveryId`/`idempotencyKey` o si el evento es desconocido, así que "0 líneas" **no prueba** por sí solo que no llegaran acks. Lo que **sí es concluyente** es §8.1: aunque llegaran, no pueden reconciliar filas con `mensaje_id NULL`.

---

## 9. Bug secundario que agrava el corte: `ReferenceError: ses is not defined`

```
14:56:58.566  [wapi-send-products] SESIÓN CAÍDA (HTTP_409: Session is not connected.
              The WhatsApp client is not ready.) estado OpenWA=initializing — intentando
              recuperarla (prod=10418 chat=120363423044527374@g.us)
14:56:58.566  [wapi-send-products] background dispatch falló: ses is not defined
14:57:03.614  [wapi-send-products] SESIÓN CAÍDA (HTTP_409 ...) (prod=7345 chat=120363195152592934@g.us)
14:57:03.614  [wapi-send-products] background dispatch falló: ses is not defined
```

**Causa (verificada en el código):** `dispatchProducts(args: {...})` **no recibe `ses`** — su firma pasa `idSesion`, `idTienda`, `wapiSessionId`, … pero nunca el objeto `ses` (índice 796-826). Sin embargo, la rama de sesión caída dentro de `dispatchOne` usa `ses.last_recovery_at`, `ses.recovery_attempts` y `ses.id` (índice ~1453-1461). `ses` **no existe en ese ámbito** → `ReferenceError`.

**Impacto:** el `.catch()` del `job` (índice ~1851-1855) se lo traga con un `console.error` y **muere todo el worker en segundo plano**. Se pierde exactamente el mecanismo diseñado para este caso: "la fila queda `pendiente` y la reanudación la recoge". Al morir el job, **los 67 productos restantes de la cadena B nunca se despacharon** y no se encoló continuación. El `ReferenceError` se dispara **solo** cuando entra la rama de sesión caída, que es justo cuando más falta hace. Sigue presente en la revisión actual del archivo.

---

## 10. La ola `HTTP_500` del 19-oct (incidente distinto, para dimensionar)

```sql
select id, chat_id, estado, error_code, to_char(created_at,'MM-DD HH24:MI') t,
       left(coalesce(error_message,''),80) msg
from public.app_wapi_envio_log where error_code='HTTP_500'
order by created_at desc limit 8;
```

```
24456 | 120363423044527374@g.us | fallido | HTTP_500 | 10-20 11:44 | Internal server error (tras 3 intento(s))
24455 | 120363423044527374@g.us | fallido | HTTP_500 | 10-20 11:43 | Internal server error (tras 3 intento(s))
24454 | 120363423044527374@g.us | fallido | HTTP_500 | 10-20 11:43 | Internal server error (tras 3 intento(s))
24449 | 120363195152592934@g.us | fallido | HTTP_500 | 10-19 17:07 | Internal server error (tras 3 intento(s))
...
```

260 filas el 19-oct (5 destinos, 0 enviados) + 3 el 20-oct. Todas con 3 intentos agotados: el backoff funcionó, OpenWA estaba caído. **No comparte causa** con el 23-oct: aquí sí hay categoría HTTP y sí es reintentable, y aun así falló todo el día.

---

# Hipótesis de causa raíz

Ordenadas por fuerza de evidencia (de más a menos sostenida por los datos).

### H1 — **Dos cadenas concurrentes sobre UNA sesión OpenWA saturan el envío hasta cruzar los 45 s; el reintento inmediato con la misma clave choca contra la petición original y se marca `fallido` un mensaje que sigue en vuelo.** — *Evidencia: muy fuerte. Causa raíz.*

- Dos lotes coexistentes con el mismo `wapi_session_id`: `destinos=1` (arranque 10:44:19) y `destinos=5` (arranque 10:48:11).
- Cambio de régimen medido: 21 envíos a 1.7-5.5 s → **31.8 s** a las 10:47:56 → timeouts de 45 s desde las 10:48:34.
- 15 de 15 `IDEMPOTENCY_KEY_IN_PROGRESS` van precedidos de un `TIMEOUT` de 45 s del mismo `prod`/`chat` en los logs (concordancia 100%).
- `esReintentable()` no reconoce el código → no reintenta cuando la respuesta correcta es esperar.

### H2 — **El fan-out en serie de 5 destinos a ~30 s/envío agota `PRODUCT_MAX_MS = 120_000` por aritmética: las posiciones 4.ª y 5.ª son estructuralmente inalcanzables (o se abandonan, o se estrellan).** — *Evidencia: muy fuerte.*

- 3 envíos válidos consumen ~95 s de 120 s. El 4.º arranca a +96.7 s y su ciclo TIMEOUT+409 dura ~55 s.
- Las 5 filas `PRODUCT_TIMEOUT` tienen **cero** líneas de intento en los logs: los destinos 4.º/5.º nunca se intentaron.
- Mensaje del propio motor: `prod=10605 agotó su ventana: 1 destino(s) sin enviar`.

### H3 — **El `fallido` es irreversible: el ack se empareja por `mensaje_id`, que es NULL en todas las filas fallidas, así que la BD no puede auto-corregirse.** — *Evidencia: fuerte (estructural, verificada en código + esquema).*

- `.eq("mensaje_id", msgId)` con `mensaje_id IS NULL` en las 21 filas fallidas.
- 0 filas con `ACK_ERROR` / `MESSAGE_FAILED` en toda la tabla.
- Consecuencia directa: cualquier entrega real de un envío marcado `fallido` queda invisible para siempre.

### H4 — **La rama de sesión caída mata el worker con `ReferenceError: ses is not defined`, anulando el diseño de "queda pendiente y se reanuda".** — *Evidencia: fuerte (2 ocurrencias en logs + verificación de ámbito en código).*

- 2 mensajes `background dispatch falló: ses is not defined`, ambos inmediatamente después de un `SESIÓN CAÍDA (HTTP_409)`.
- `dispatchProducts(args)` no recibe `ses`; la rama de recuperación lo usa.
- Efecto medido: los 67 productos restantes de la cadena B quedaron sin despachar.

### H5 — **La degradación de OpenWA (`89.40.7.25:2785`) precede al lanzamiento de la cadena B y pudo ser externa (host compartido / Puppeteer).** — *Evidencia: media-débil.*

- El outlier de 31.8 s es a las **10:47:56**, *antes* del arranque de la cadena B (10:48:11), y hay 2 `NETWORK_ERROR` de socket (`connection closed before message completed`, `Connection reset by peer`) a las 10:47:43 y 10:53:39.
- Sugiere saturación del lado servidor, no solo concurrencia nuestra. No hay telemetría de OpenWA para confirmarlo.

### H6 — **La ola `HTTP_500` del 19-oct es un incidente independiente (OpenWA caído ~20 h).** — *Evidencia: fuerte, pero fuera del alcance del 23-oct.*

---

# Respuestas explícitas a las preguntas del usuario

## P1. ¿Por qué exactamente aparece `IDEMPOTENCY_KEY_IN_PROGRESS` y qué significa que el mensaje quizá SÍ se envió?

**Por qué aparece, paso a paso:**

1. `dispatchOne` envía con la clave de idempotencia derivada **de la fila de log**: `wa-log-<logId>` (una clave por `producto × destino`, reutilizada en todos los reintentos de esa fila).
2. El cliente HTTP aborta a los **45 s** (`TIMEOUT_MEDIA_MS`). Ese aborto es **local**: cierra la conexión desde nuestro lado, **no cancela** el envío en OpenWA.
3. Error `TIMEOUT` → `esReintentable() = true` → espera ~4 s (backoff con jitter).
4. Segundo intento con la **misma** clave. OpenWA ve que la petición original **sigue ejecutándose** y responde `409` con `error.code = IDEMPOTENCY_KEY_IN_PROGRESS`: *"A request with this Idempotency-Key is still running. Retry after it finishes."*
5. `esReintentable("IDEMPOTENCY_KEY_IN_PROGRESS") = false` (no es `TIMEOUT/NETWORK_ERROR/SEND_ERROR` y no casa `HTTP_<status>`; y aun como `HTTP_409` no sería reintentable) → se abandona el bucle y la fila se marca `fallido`.

Verificado en los logs: **15/15** casos siguen el patrón `intento 1/3 (TIMEOUT)` → `intento 2/3 (IDEMPOTENCY_KEY_IN_PROGRESS)`; 2 de ellos llegan a `intento 3/3` tras un segundo `TIMEOUT`.

**Qué significa que el mensaje quizá SÍ se envió:**

El propio texto de OpenWA es la prueba: **"la petición con esta clave sigue en ejecución"** — es decir, `still running`, **no** `failed`. El servidor no canceló nada; sigue trabajando en el envío que nosotros dejamos de esperar. La semántica estándar del patrón `Idempotency-Key` es: mientras una clave está *in flight* → `409`; **cuando termina, un reintento con la misma clave devuelve la respuesta almacenada** (con el mismo `messageId`), sin duplicar el mensaje ([Powerduck, *Idempotency-Key in practice*](https://www.powerduck.com/blog/api-idempotency-key-header-deduplication/)). Esto es exactamente lo que el comentario del propio código dice que esperaba conseguir.

Prueba adicional a favor de "no se canceló": de las 16 claves implicadas, **15 seguían en ejecución** y **solo 1** llegó al estado terminal `IDEMPOTENCY_OUTCOME_UNKNOWN` (cuyo texto es *"una petición anterior con esta clave falló y **el mensaje PUEDE haberse enviado**"*). Si los envíos se hubieran abortado de verdad en el servidor, lo esperable sería `OUTCOME_UNKNOWN` masivo, no `IN_PROGRESS` masivo.

**Implicación práctica (lo importante):** el arreglo correcto no es reintentar con clave nueva (duplicaría), ni marcar `fallido` (miente), sino **esperar y reintentar con la MISMA clave** hasta que la petición original termine: la reproducción devolvería el `messageId` real y la fila pasaría a `enviado` sola.

## P2. ¿Cuántos de los `fallido` de hoy son falsos negativos (el mensaje llegó igual)?

`fallido` del 23-oct = **21** (15 `IDEMPOTENCY_KEY_IN_PROGRESS` + 1 `IDEMPOTENCY_OUTCOME_UNKNOWN` + 5 `PRODUCT_TIMEOUT`).

| categoría | filas | ¿falso negativo? | confianza |
|---|---|---|---|
| `IDEMPOTENCY_KEY_IN_PROGRESS` | **15** | **Sí** — la petición original seguía en ejecución; no fue cancelada | **Alta** |
| `IDEMPOTENCY_OUTCOME_UNKNOWN` | **1** | **Probablemente sí** — OpenWA dice literalmente que "puede haberse enviado" | Media-alta |
| `PRODUCT_TIMEOUT` | 5 | **No** — nunca se intentaron (0 líneas de intento en logs); **no se enviaron** | Alta |
| **TOTAL falsos negativos** | **16 de 21 = 76 %** | | |

**Matiz honesto sobre la confianza:** **no existe confirmación positiva de entrega** en el sistema actual — la tabla no guarda `mensaje_id` en estas filas y el ack no las puede reconciliar (§8). La clasificación se apoya en (a) la semántica *in flight* de OpenWA, (b) la ausencia de cualquier cancelación del lado servidor, y (c) que la única clave que llegó a estado terminal fue `OUTCOME_UNKNOWN` ("puede haberse enviado"). **Verificación definitiva = mirar a mano los 5 grupos** entre 10:48:34 y 10:55:58 (ver §Preguntas abiertas P2).

Los 5 `PRODUCT_TIMEOUT` son lo contrario: **huecos reales** de entrega (nunca se intentaron). Más las 5 `pendiente` (que no son `fallido`): en total, **10 destinos quedaron sin enviar de verdad** y 16 filas mienten.

## P3. ¿Qué chat_id/destino es el cuello de botella y por qué?

**Por conteo absoluto: `120363423044527374@g.us` (Inventtia)** — 8 de 15 `IDEMPOTENCY_KEY_IN_PROGRESS` (**53 %**) y 8 de 21 fallidos del día (**38 %**), más 1 `pendiente`.

**Pero el dato decisivo es que NO es intrínsecamente lento.** En la misma sesión, la misma hora y una ventana de 3 minutos (10:44:20 → 10:47:35) ese mismo grupo recibió **21 mensajes consecutivos con éxito en 1.7-5.5 s cada uno**. Acumula fallos porque es el **único destino de la cadena A**, que siguió avanzando un producto cada ~60 s (un ciclo TIMEOUT+409 completo por producto) contra una sesión ya saturada por la cadena B. Es el **canario**, no la causa.

**El cuello de botella real es posicional, no un grupo concreto:**
- Los destinos con **0 mensajes entregados** son `120363406746096914@g.us` (CARNAVAL #5, 3 fallidos) y `120363266453891641@g.us` (CARNAVAL #2, 3 fallidos): son exactamente las **posiciones 4.ª y 5.ª** del fan-out en serie, y las 5 filas `PRODUCT_TIMEOUT` están todas ahí (`#5`×2 + `#2`×3), **sin un solo intento** registrado.
- La causa material es **una sola sesión OpenWA (`3f394210…`) atendiendo dos cadenas concurrentes** (`destinos=1` y `destinos=5`), lo que elevó la latencia de envío de ~2.5 s a >45 s.

**En una frase:** el cuello de botella es la **sesión**, y se manifiesta siempre en la **cola del fan-out**; `120363423044527374@g.us` solo lo hace visible antes porque es la cadena que no se detiene.

---

# Preguntas abiertas

- **P1.** ¿La cadena `destinos=5` la lanzó el usuario a mano mientras la cadena `destinos=1` seguía viva (`corte por presupuesto a los 254s: 21 ok, 49 para el worker siguiente`)? Los `batchId` son distintos (`b_177_1792766891001_722542` vs `b_177_1792766659660_696293`), lo que apunta a dos intenciones separadas. ¿Debería el backend **rechazar o encolar** un segundo envío sobre una sesión con un batch en curso?
- **P2.** **¿Llegaron los 16 mensajes?** Requiere comprobación manual en los 5 grupos (ventana 10:48:34-10:55:58) o acceso al almacén de mensajes de OpenWA. Es la única forma de cerrar P2 con certeza; la BD no puede.
- **P3.** ¿Cuánto tiempo mantiene OpenWA una clave en estado *in progress* tras el aborto del cliente? Si la petición original se queda colgada indefinidamente, la clave queda envenenada y **todos** los reintentos futuros con esa clave fallarán. Define el TTL y el `Retry-After` que hay que respetar.
- **P4.** ¿Por qué se degradó OpenWA a las 10:47:56, **antes** de la segunda cadena? ¿Host compartido (`89.40.7.25:2785`), pausa de GC de Chromium/Puppeteer, u otro arrendatario? Sin telemetría del lado WAPI no se puede decidir H5.
- **P5.** El `ReferenceError: ses is not defined` (§9) seguía presente en la revisión que leí. ¿Se corrige en el mismo fix que la política de reintento, o queda vivo en producción? Comprobar si `wapi-cron-dispatch` tiene el mismo patrón.
- **P6.** El webhook no da señales de vida en 24 h, pero su handler solo loguea si vienen `deliveryId`/`idempotencyKey`. ¿Está el webhook bien registrado en OpenWA (URL + secret + eventos `message.ack`)? Sin acks, ninguna fila puede reconciliarse nunca.
- **P7.** ¿Por qué la tabla solo tiene 3 días de datos (19, 20 y 23-oct)? Sin retención no se puede medir tendencia ni dimensionar el problema a 14 días.
- **P8.** El handler de `message.ack` empareja solo por `mensaje_id`. ¿Conviene un emparejamiento alternativo (ventana temporal + `chat_id`) para las filas sin `mensaje_id`? Es la única vía de reparar retroactivamente las 16 filas.

---

## Anexo — Referencias de código

| Hecho | Ubicación (revisión analizada) |
|---|---|
| `RETRY_MAX_ATTEMPTS = 3`, `RETRY_BASE_MS = 4_000` | `wapi-send-products/index.ts` ~95-96 |
| `esReintentable()` no conoce `IDEMPOTENCY_*` | ~107-118 |
| Clave de idempotencia `wa-log-${e.logId}` (misma en cada intento) | ~1314 |
| Bucle de reintento, `continue` tras recuperación de sesión | ~1303-1464 |
| `backoffMs = 4s × 2^(intento-1)`, `puedeReintentar` | ~1442-1457 |
| Rama de sesión caída usando `ses.*` fuera de ámbito | ~1349-1414 (líneas 1453-1461 en la revisión nueva) |
| `PRODUCT_MAX_MS = 120_000`, `FANOUT_PAUSE_MS = 1_500`, `WORKER_BUDGET_MS = 270_000` | ~850-859 |
| Abandono del producto → `PRODUCT_TIMEOUT` sin despachar | ~1544-1564 |
| `dispatchProducts(args)` sin `ses` | ~796-826 |
| `.catch()` que traga el `ReferenceError` | ~1851-1855 |
| `TIMEOUT_MEDIA_MS = 45_000` | `_shared/wapi_client.ts` ~56 |
| `code` desde `parsed.error.code` (no del status HTTP) | `_shared/wapi_client.ts` ~125-127 |
| Handler `message.ack` emparejando por `mensaje_id` | `wapi-webhook/index.ts` ~254-278 |
| "Dos envíos simultáneos se pisan y devuelven NETWORK_ERROR" | `index.ts` comentario ~1513-1515 |

> Nota de seguridad observada en el proyecto (fuera del alcance de esta tarea, pero relevante): el asesor de Supabase reporta **RLS deshabilitado en 75 tablas** del esquema `public`. No se aplicó ningún cambio.