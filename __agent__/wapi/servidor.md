# task-3 — Diagnóstico del servidor OpenWA (`ing-servidor`)

**Servidor:** `5urc.l.time4vps.cloud` / `89.40.7.25:22` (root) · Debian 13, kernel 6.12.57
**Ventana del incidente:** 2026-10-23 **14:44:20 → 14:57:02 UTC** (10:44–10:57 -04)
**Modo:** SOLO LECTURA. No se reinició, paró, borró ni modificó nada del servidor ni de la BD de OpenWA.
Se ejecutaron consultas SQLite con `file:...?mode=ro` (URI read-only) y `docker exec` de solo lectura.
Los dos ficheros temporales de benchmark (`/tmp/_fsync_probe.bin`, `/tmp/_sqlite_probe.db`) se crearon y se **borraron** en el mismo comando.
Salidas crudas guardadas en `__agent__/wapi/logs/` (`01`–`32`).

> ⚠️ **Estado ahora mismo (15:15–15:18 UTC): la sesión está en `qr_ready`. El bot está CAÍDO y necesita re-vincularse con QR.** Ver §9.
>
> ⚠️ **Corrección al enunciado, con evidencia:** el timeout del cliente **no es 45 s**. El envío de media usa
> `WAPI_TIMEOUT_MEDIA_MS ?? 90_000` (`_shared/wapi_client.ts:69`); los **45 s** son `IDEM_ESPERA_MAX_MS`
> (la espera máxima **entre reintentos** de idempotencia). Y el servidor no corta a 45 s: su
> `protocolTimeout` efectivo es **180 s**. Ese 90 s < 180 s es la pieza que convierte un envío lento en el bucle
> `IDEMPOTENCY_KEY_IN_PROGRESS`. Ver §10.

---

## 1. Inventario y versión real

```console
# docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'
openwa-api            openwa-openwa-api      Up 2 days (healthy)   0.0.0.0:2785->2785/tcp
openwa-docker-proxy   tecnativa/docker-socket-proxy:v0.5.0   Up 2 days

# grep '"version"' /root/OpenWA/package.json
  "version": "0.25.0"
```

- **OpenWA 0.25.0** (imagen `openwa-openwa-api:latest`, `f789953dad61`, construida hace 2 días). Nota: existe un tag
  `openwa-openwa-api:pre-media-fix` (6 semanas) → hubo un cambio de media reciente.
- **Cumple el requisito `>= 0.25.0`** para `Idempotency-Key` / `OUTCOME_UNKNOWN` — se confirma porque la tabla
  `send_idempotency_keys` existe y tiene 42 filas.
- **Motor efectivo: `whatsapp-web.js` (Chromium/Puppeteer)**, no Baileys:
  - `src/config/configuration.ts:222` → `process.env.ENGINE_TYPE || 'whatsapp-web.js'`;
  - `ENGINE_TYPE=` llega **vacío** desde compose y `main.ts` trata el vacío como "no definido";
  - `/app/data/.env.generated` **no** define `ENGINE_TYPE` (solo `DATABASE_TYPE=sqlite`, `REDIS_ENABLED=false`,
    `QUEUE_ENABLED=false`, `STORAGE_TYPE=local`);
  - los logs lo confirman: contexto `WhatsAppWebJsAdapter`, `ProtocolError` de `puppeteer-core`, y
    `/usr/local/bin/puppeteer-chrome → /opt/puppeteer/chrome/linux-153.0.8010.36/chrome-linux64/chrome`
    (**Chrome for Testing 153**).
- **WhatsApp Web pineado a un build ALPHA de terceros**: `Pinning WhatsApp Web version 2.3000.1051404344-alpha`
  (`WWEBJS_WEB_VERSION` está vacío → auto-resuelve del registro `wppconnect-team/wa-version` y descarga el HTML
  remoto sin verificación de integridad).

## 2. Entorno efectivo (`docker inspect`, secretos enmascarados)

```console
# docker inspect openwa-api --format '{{range .Config.Env}}{{println .}}{{end}}' | grep -v '=$' | sort
AUTO_START_SESSIONS=true          LOG_LEVEL=info                 PORT=2785
CSP_UPGRADE_INSECURE_REQUESTS=false  NODE_ENV=production         PUPPETEER_EXECUTABLE_PATH=/usr/local/bin/puppeteer-chrome
DATABASE_SYNCHRONIZE=false        PLUGINS_DIR=/app/data/plugins  PUPPETEER_SKIP_DOWNLOAD=true
DOCKER_HOST=tcp://docker-proxy:2375  STATUS_SEED_ON_READY=false  TZ=UTC
HOME=/tmp                         WEBHOOK_DISPATCH_CONCURRENCY=16  WEBHOOK_DISPATCH_MAX_QUEUED=1000
NODE_VERSION=22.23.3              WEBHOOK_RETRY_DELAY=5000       WEBHOOK_TIMEOUT=10000
XDG_CACHE_HOME=/tmp/.cache        XDG_CONFIG_HOME=/tmp/.config
# (DATABASE_PASSWORD, REDIS_PASSWORD y METRICS_TOKEN: ***MASKED***; API_MASTER_KEY/API_KEY_PEPPER llegan VACÍOS)

# docker inspect openwa-api --format 'RestartPolicy={{.HostConfig.RestartPolicy.Name}} Mem={{.HostConfig.Memory}} Net={{...}} Started={{.State.StartedAt}}'
RestartPolicy=unless-stopped  Mem=2147483648  Started=2026-10-20T20:01:27Z
```

**Todas las variables de tuning están presentes pero VACÍAS** (compose usa `${VAR:-}`), es decir se aplican los
defaults de la app. Consecuencias (todas verificadas en el código en `/root/OpenWA/src`):

| Variable | Valor efectivo | Fuente |
|---|---|---|
| `ENGINE_TYPE` | `whatsapp-web.js` | `configuration.ts:222` |
| `PUPPETEER_PROTOCOL_TIMEOUT_MS` | **no definido → 180 000 ms** (default de Puppeteer) | `configuration.ts:247-250` (devuelve `undefined` y el comentario dice "whatever puppeteer-core's `timeout ?? 180_000` says") |
| `SEND_PACING_ENABLED` | **OFF** (`=== 'true'` sobre vacío) | `send-pacing.config.ts:80` |
| `MEDIA_CONVERSION_ENABLED` | **OFF** (`ffmpeg` existe en `/usr/bin/ffmpeg` pero no se usa) | `configuration.ts:521-525` |
| `REDIS_ENABLED` / `QUEUE_ENABLED` | `false` | `/app/data/.env.generated` |
| `DATABASE_TYPE` | **sqlite** (local, sin Postgres) | `/app/data/.env.generated` |
| `WEBHOOK_*` | dispatch 16, timeout 10 s (pero `webhooks` = 0 filas: no hay webhooks) | env |

## 3. Salud de la API (desde dentro del contenedor, `node fetch`; el host no tiene `curl`)

```console
===== /api/health        HTTP 200 in 158 ms  {"status":"ok","timestamp":"2026-10-23T15:07:56.572Z"}
===== /api/health/ready  HTTP 200 in  52 ms  {"status":"ok","details":{"mainDatabase":{"status":"up"},"dataDatabase":{"status":"up"}}}
===== /api/infra/health  HTTP 200 in  65 ms  {"status":"ok", ...}
```

La API responde en **50–160 ms**: el plano de control está sano. El problema está **solo en la ruta de envío**.
`/api/metrics` → **404** (no habilitado), así que no hay histogramas de duración ni event-loop lag.

## 4. Logs del contenedor en la ventana del incidente

```console
# docker logs --since '2026-10-23T14:30:00Z' --until '2026-10-23T15:10:00Z' openwa-api > /tmp/win.log 2>&1
LINES=40  BYTES=23420    level: 12 error / 22 warn / 6 info
```

Contadores dentro de la ventana: `protocolTimeout` **6**, `Runtime.callFunctionOn timed out` **6**,
`Target closed` **16**, `Execution context was destroyed` **4**, `Send failed in the engine (image)` **8**,
`MEDIA_DOWNLOAD_TIMEOUT` **1**, `engine_init_timeout` **1**, `reconnect` **2**.
(`OUTCOME_UNKNOWN`, `IN_PROGRESS`, `idempotency` → **0 apariciones**: el bucle de idempotencia es del lado cliente/Edge Function.)

Líneas clave, literales:

```
14:50:27.644 warn SessionLivenessWatchdog   Liveness probe failed; will treat the session as dead after repeated failures
                                            sessionId=3f394210-…  failures=1
14:55:42.172 warn MessageSend               Send failed in the engine (image) chatId=120363423044527374@g.us
                                            error="ProtocolError: Runtime.callFunctionOn timed out. Increase the
                                            'protocolTimeout' setting in launch/connect calls…" requestId=7bff70f0-…
14:55:44.016 error ExceptionsHandler        ProtocolError: Runtime.callFunctionOn timed out…
                                            at … whatsapp-web.js/src/Client.js:1544  ← Client.sendMessage
                                            at /app/dist/engine/adapters/wwebjs-messaging.js:298 (sendMediaMessage)
                                            at /app/dist/modules/message/message-send.service.js:187 (sendImage)
14:55:52.715 warn WhatsAppWebJsAdapter      Inbound media download timed out (MEDIA_DOWNLOAD_TIMEOUT_MS); emitting message without media
14:56:28.569 warn SessionLivenessWatchdog   Liveness probe failed repeatedly; handling the session as disconnected (failures=2)
14:56:29.492 warn SessionEngineLifecycle    Session disconnected: liveness probe failed (watchdog)
14:56:52.336 error SessionEngineLifecycle   Failed to destroy engine…  "Error: engine.destroy() timed out"  → escalado a force-destroy
14:56:54.019 warn WhatsAppWebJsAdapter      Page transport error during sendMessage — treating the session as dead
                                            error="Protocol error (Runtime.callFunctionOn): Target closed"  (×5 en el mismo ms)
14:57:16.260 warn WhatsAppWebJsAdapter      "Execution context was destroyed… during initialize … check for memory
                                            pressure or a WhatsApp Web reload"
15:01:09.101 error SessionEngineLifecycle   Engine initialization timed out  action=engine_init_timeout
```

**No hay OOM-kill del contenedor** (`memory.events`: `oom 0`, `oom_kill 0`) y **no hay trazas de GC/OOM en los logs**.
El patrón es *stall + timeout*, no *crash por OOM*.

## 5. Cronología reconstruida (reloj del servidor, UTC)

| Hora | Evento | Fuente |
|---|---|---|
| 14:44:20 | primer envío del lote, **4 s** | SQLite + Supabase |
| 14:44:24–14:47:56 | **21 envíos al MISMO grupo `120363423044527374@g.us`, 0–4 s cada uno**, `status=delivered` | SQLite |
| 14:47:43 | primer mensaje "Enviado tras **2 intentos**" | Supabase `app_wapi_envio_log` id 24479 |
| **14:48:11** | primer `IDEMPOTENCY_KEY_IN_PROGRESS` | id 24484 |
| 14:48:13–14:52:30 | envíos con **16/18/26/28/30/36/50 s**; `status` pasa de `delivered` a `sent` | SQLite |
| 14:50:27 | watchdog: liveness probe **fail #1** | docker logs |
| 14:50:44–10:53 | `PRODUCT_TIMEOUT` "Producto abandonado tras **152 s / 166 s / 161 s**" | Supabase 24485/24492/24499 |
| 14:55:42 | `Runtime.callFunctionOn timed out` (protocolTimeout de 180 s superado) | docker logs |
| 14:55:26 / 14:56:29 | fail #2 → **sesión desconectada por el watchdog** | docker logs |
| 14:56:54 | `Target closed` ×5 → la página murió con 5 envíos en vuelo | docker logs |
| 14:56:13 | `IDEMPOTENCY_OUTCOME_UNKNOWN` | Supabase id 24504 |
| 15:00:02 / 15:15:01 / 15:15:11 | `session_stopped` (IPs externas) y `session_started` | `main.sqlite` `audit_logs` |
| 15:16 | **sesión en `qr_ready`** (pide QR) | `GET /api/sessions` |

**Dato clave:** los 21 envíos rápidos fueron **todos al mismo grupo** y los lentos empezaron a las 14:48, también
**contra ese mismo grupo ya "caliente"** (14:49:25 → 26 s; 14:53:47 → 14 s). No es el coste de "primer mensaje a un
grupo nuevo": es una **degradación temporal global** que arranca a las 14:48.

## 6. Latencia real medida (no inferida)

Cruzo `send_idempotency_keys.createdAt` (cuando OpenWA acepta la petición) con `messages.createdAt` de la fila que
`applySendingGate` escribe **antes** de llamar al motor (`message-send.service.ts:203` → `saveOutgoingMessage`,
`buildPending`; luego `:334` `engine.sendImageMessage` y `:338` `persistSentState`). Por tanto mide la **pata
pre-envío + la inserción PENDING**, no el envío al motor (que va después y es justo el que reventó a >180 s).

```
  4 s  wa-log-24460  →  2 s, 2 s, 1 s  … (14:44:20–14:47:56, 21 filas, status=delivered)
 16 s  wa-log-24481
 18 s  wa-log-24482
 26 s  wa-log-24487 / wa-log-24490
 28 s  wa-log-24488
 30 s  wa-log-24494
 36 s  wa-log-24491
 50 s  wa-log-24486   ← máximo medido
n=32  min=0.0  p50=2.0  max=50.0  mean=9.5  (segundos)
```

O sea: **la propia pata previa al envío pasó de 1–2 s a 16–50 s** y luego el envío al motor se quedó colgado hasta el
`protocolTimeout` de 180 s. Y el presupuesto del cliente es **90 s** (`WAPI_TIMEOUT_MEDIA_MS ?? 90_000`,
`_shared/wapi_client.ts:69`), así que el cliente aborta y reintenta con la misma clave mientras OpenWA sigue trabajando.

## 7. Recursos y el número que lo demuestra

```console
# nproc → 2 ;  free -m → total 3921 MB, used 669, available 3252 ;  Swap: 0 (swapon sin salidas)
# df -h → /dev/sda2 50G 19G 29G 39%   (disco NO lleno)
# lsblk -d -o NAME,ROTA,SCHED → sda  ROTA=1  mq-deadline   (disco ROTACIONAL/virtual "Vz HARDDISK0")
# uptime → load average 0.00 0.37 0.93   (CPU al ~0.6 %, no saturada)
# docker stats --no-stream → openwa-api 0.64 % CPU · 550 MiB/2GiB · 12 PIDs   ← sin Chromium (sesión muerta)
#                            openwa-api 12.24 % CPU · 947 MiB/2GiB · 145 PIDs  ← 7 min después, Chromium arriba
```

cgroup del contenedor (`/sys/fs/cgroup/system.slice/docker-f6cdcbe1….scope`):

```console
memory.max      = 2147483648        (2 GiB — viene de `mem_limit: ${OPENWA_MEM_LIMIT:-2g}`, compose:99)
memory.peak     = 2147733504        ← 2 147 733 504 B = 99.99 % del tope
memory.current  = 1090760704        (1.02 GiB con la sesión sólo inicializando)
memory.events   = max 54705 · oom 0 · oom_kill 0
memory.stat     = pgscan_direct 3515428 · pgsteal_direct 3203546 · pgscan_kswapd 0 · pgsteal_kswapd 0
                  pgmajfault 72509 · anon 595 MB · file 462 MB · anon_thp 145 MB
memory.swap.max = 2147483648 pero el HOST no tiene swap → swap.current 0 (no hay a dónde paginar)
cpu.max         = max 100000        ← el contenedor NO está limitado de CPU (usa los 2 vCPU)
```

Procesos Chromium vivos (15:16, sesión esperando QR):

```console
# ps -eo pid,ppid,rss,pcpu,stat,comm --sort=-rss | grep -i chrome
12 procesos "chrome" (incl. 2 chrome_crashpad); suma de RSS = 1375848 KB = 1.31 GiB
# sin crash dumps (*.dmp / *crash*) en el volumen
```

Volumen `openwa_openwa-data`:

```
openwa.sqlite  648 343 552 B (648 MB)  journal_mode=delete  (NO WAL)  ·  messages 28 027 filas + FTS5 (messages_fts*)
main.sqlite        516 096 B (audit_logs 705, api_keys 1, migrations 3)
sessions/          413 MB  → sessions/session-3f394210-…/Default = 403 MB (perfil Chromium/IndexedDB de WhatsApp Web)
media/              77 MB
# node dist/main: leídos 7.89 GB / escritos 24.17 GB desde el 20-oct (io.stat del contenedor: 11.8 GB R / 24.2 GB W)
```

## 8. ¿Es el peso de la imagen o la red? **No.**

Descarga real de imágenes de producto desde el servidor (dentro del contenedor, mismo camino que `loadRemoteMedia`):

```console
   24.3 KB  span  230 ms  image/jpeg  product_1768186016743_product_5277…
   31.3 KB  span  995 ms  image/jpeg  product_1769115753981_product_5508…
   16.7 KB  span  827 ms  image/jpeg  product_1772740880377_product_8689…
 4607.6 KB  span 1139 ms  image/jpeg  product_1772484195942_product_6887…   ← cola gorda
  143.5 KB  span 1006 ms  image/jpeg  product_1771618574764_product_1948…
   37.5 KB  span 1030 ms  image/jpeg  1745537519873178.jpg
median KB: 37.5   max KB: 4607.6
# repetido 3× sobre la primera URL: 24859 B en 0.41 s / 0.07 s / 0.07 s
```

- Las imágenes son **JPEG y pequeñas** (mediana ~37 KB; 4.6 MB solo en la cola). Descarga **< 1.2 s** incluso para 4.6 MB.
- La subida/inyección al page es base64 (`wwebjs-messaging.ts:230` → `new MessageMedia(mimetype, data.toString('base64'))`),
  pero 37 KB → 50 KB de base64: irrelevante.
- **Descartado**: el "cuello de botella por imagen de varios MB" que planteaba la hipótesis de partida.

También descartado con número:
- **Disco/BD**: `fsync` de 64 KB ×40 → p50 0.00 ms, **max 0.43 ms**; commit SQLite+FTS5 ×60 en `/tmp` (mismo `journal_mode=delete`, `synchronous=full`) → **p50 0.1 ms, max 0.4 ms**. El disco escribe rápido (write-back); la presión de IO elevada que vi al principio (`io.pressure some avg10=91 %`) bajó a **6 % → 1 %** al parar mis propias consultas de diagnóstico: **era IO mía**, no de la app.
- **Pacing**: `SEND_PACING_ENABLED` vacío ⇒ `enabled === 'true'` es **false** (`send-pacing.config.ts:80`) ⇒ la puerta `assertSendAllowed` no espera nada. No es un freno anti-ban deliberado.
- **ffmpeg/conversión**: `MEDIA_CONVERSION_ENABLED` vacío ⇒ **OFF**.
- **CPU**: `cpu.max=max`, load 0.37/0.93, contenedor al 0.6 % CPU mientras todo se caía ⇒ **no es saturación de CPU**.
- **API/BD/Redis**: health 52–158 ms, `REDIS_ENABLED=false`, SQLite `mainDatabase/dataDatabase up`.
- **Zombies**: `ps -eo stat | grep -c Z` = **0**.

## 9. Idempotencia: 42 claves, ninguna atascada, 10 envenenadas

```console
# openwa.sqlite, tabla send_idempotency_keys (id, sessionId, idempotencyKey, route, requestHash, state, responseBody, expiresAt, createdAt)
state,route,count →  completed | sendImage | 32
                     failed    | sendImage | 10      (estados distintos: SOLO 'completed' y 'failed')
# las 10 'failed' (createdAt 14:52:38 → 14:57:02), todas con responseBody = NULL:
wa-log-24495 · 24496 · 24501 · 24497 · 24502 · 24498 · 24503 · 24504 · 24509 · 24505
```

- **0 claves atascadas ahora.** El estado sí es en BD: el claim es un `INSERT … state='pending'`
  (`send-idempotency.service.ts`, `createSendIdempotency`/`claim`) contra `UNIQUE(sessionId, idempotencyKey)`, y
  `IDEMPOTENCY_KEY_IN_PROGRESS` se responde cuando esa fila existe en `pending` y es más joven que
  `SEND_IDEMPOTENCY_STALE_PENDING_MS = 10 min` (más vieja ⇒ se responde `outcome_unknown`). Como los estados
  presentes son **solo `completed` y `failed`**, no hay ninguna fila `pending`: nada quedó en vuelo ni zombi.
  El `responseBody` es `NULL` tanto en `pending` como tras un fallo, tal y como documenta la entidad.
- Las **10 `failed` quedan envenenadas 24 h** (`expiresAt` = `createdAt` + 24 h) y **sin `responseBody`**: reintentar
  esas claves no devuelve el `messageId`, devuelve `IDEMPOTENCY_OUTCOME_UNKNOWN` ("may have been sent") — exactamente
  lo que registró el id 24504. Para reanudar hay que resolverlas a mano, no reintentarlas.
- Los 10 `failed` corresponden a los log ids **24495–24509** de `app_wapi_envio_log`.

## 10. Cuello de botella identificado

**El contenedor `openwa-api` vive pegado a su techo de memoria (2 GiB) y sin swap: toda la reclamación es `direct reclaim`
sincrónica, lo que congela la página de Chromium/WhatsApp Web y estira cada envío de 1–2 s a 16–50 s (y al final
>180 s), mientras el cliente sólo espera 90 s.**

Los números que lo demuestran:

1. **`memory.peak = 2 147 733 504 B` contra `memory.max = 2 147 483 648 B` → 99.99 % del tope exacto**, con
   **`memory.events max = 54 705`** (54 705 asignaciones que tuvieron que reclamar para caber).
2. **`pgscan_direct = 3 515 428` / `pgsteal_direct = 3 203 546` con `pgscan_kswapd = 0` / `pgsteal_kswapd = 0`**:
   el 100 % de la reclamación ocurre **en el contexto del proceso que asigna** (bloqueándolo), no en background.
   Con `oom_kill = 0`: el kernel no mata, **hace esperar** — y esa espera es el 27–50 s del envío.
3. **0 swap** en el host (`Swap: 0`) ⇒ no hay válvula de escape; y el contenedor tiene **2 vCPU** con el disco
   **rotacional** (`ROTA=1`), así que cada fallo de page-cache se paga en disco.
4. **La huella viva ya no deja margen**: Chromium = **12 procesos / 1.31 GiB de RSS**, el perfil de WhatsApp Web
   (`Default`) = **403 MB**, el proceso Node = 238 MB y el contenedor sólo *inicializando* ya marca
   **1.02 GiB / 2 GiB** (`memory.current`). Un pico de sincronización de WhatsApp Web basta para llegar al tope.
5. **Curva de degradación medida** (§6): 21 envíos a 0–4 s (14:44–14:47) → 16/18/26/28/30/36/**50 s**
   (14:48–14:52) → `protocolTimeout` **>180 s** (14:55:42) → `Target closed` y sesión muerta (14:56:54), todo
   **sin OOM-kill y con la CPU al 0.6 %**. Ese es el perfil de un *stall* de memoria, no de CPU ni de red.

**Amplificador (por qué acaba en `IDEMPOTENCY_KEY_IN_PROGRESS`):** desajuste de presupuestos.
`WAPI_TIMEOUT_MEDIA_MS` = **90 s** del cliente < `protocolTimeout` de **180 s** del servidor ⇒ **todo** envío que
tarde más de 90 s garantiza un reintento con la misma clave mientras la original sigue viva ⇒ **409
`IDEMPOTENCY_KEY_IN_PROGRESS`**; el Edge Function espera `12/24/…/45 s` × 4 (`IDEM_MAX_ESPERAS=4`) y a los
`MENSAJE_MAX_MS=150 s` abandona el producto ⇒ **`PRODUCT_TIMEOUT` ("Producto abandonado tras 152/166/161 s")**.
O sea: el `PRODUCT_TIMEOUT` **no** es la causa, es el síntoma; y el bucle de idempotencia es correcto pero está
calibrado por debajo del peor caso real del servidor.

## 11. Config recomendada (NO aplicada — requiere autorización del lead)

Por orden de impacto. **Nada de esto está aplicado.**

| # | Cambio | Dónde | Valor propuesto | Por qué |
|---|---|---|---|---|
| 1 | **Sacar Chromium de la ecuación** | `/root/OpenWA/.env` → `ENGINE_TYPE=baileys` y recrear `openwa-api` | `baileys` | Baileys es **built-in** en 0.25.0 (`src/engine/builtin/baileys`) y es un motor WebSocket: elimina los 1.31 GiB de Chromium, el `protocolTimeout` y los stalls de page. `ENGINE_TYPE` vacío en compose hace que `.env` sea el que manda. **Requiere re-vincular** (auth Baileys ≠ perfil Chromium). |
| 2 | **Dar aire a la memoria** | `/root/OpenWA/.env` → `OPENWA_MEM_LIMIT=3584m` (host: 3921 MB) **o** subir el VPS a 8 GB | `3584m` | El tope de 2 GiB es el cuello real (`compose:99`). Con 3.5 GiB el pico medido (2.0 GiB) deja margen. Ojo: el host tiene 3921 MB; hay que dejar ~400 MB al sistema. |
| 3 | **Alinear los presupuestos de timeout** | Edge Function: `WAPI_TIMEOUT_MEDIA_MS` (`_shared/wapi_client.ts:69`) **y** OpenWA: `PUPPETEER_PROTOCOL_TIMEOUT_MS` | cliente `150000`–`180000`; servidor `60000` (o `90000`) | Hoy 90 s < 180 s ⇒ reintento con la clave en vuelo. Con cliente 180 s **o** servidor 60 s el par deja de cruzarse. La opción "servidor 60 s" hace fallar rápido y libera la clave; la opción "cliente 180 s" evita el falso timeout. |
| 4 | **No pinear un build ALPHA de terceros** | `/root/OpenWA/.env` | `WWEBJS_WEB_VERSION=off` (o un build estable concreto) | Hoy: `2.3000.1051404344-alpha` descargado de `wppconnect-team/wa-version` sin verificación de integridad. Es la variable más barata de probar y una fuente conocida de inestabilidad de página. |
| 5 | **Higiene de datos** (no urgente, sin reinicio) | volumen `/app/data` | `VACUUM` de `openwa.sqlite` (648 MB, `journal_mode=delete`) y poda de `media/` (77 MB) | No es el cuello (fsync 0.4 ms), pero 648 MB por 28 027 mensajes indica páginas libres: el `VACUUM` reduce IO y el pico de page-cache. |
| 6 | **Limitación real de recursos** | panel de Time4VPS | ≥4 vCPU / 8 GB RAM / disco SSD-NVMe | El host es HDD virtual con 2 vCPU y sin swap. Todo lo anterior sólo palía, no elimina, la falta de margen. |

**Lo que NO recomiendo tocar:** `SEND_PACING_ENABLED` (está OFF y encenderlo *empeoraría* el timeout),
`MEDIA_CONVERSION_ENABLED` (OFF y no hace falta), `WEBHOOK_*` (no hay webhooks).

## 12. Riesgos / lo que NO pude verificar

- **URGENTE y no es diagnóstico: la sesión está en `qr_ready`** (`GET /api/sessions`, 15:16 UTC) con
  `phone=5363464544` y `engineLoaded=true`. El bot **no está enviando nada ahora mismo** y necesita que alguien
  escanee el QR. Re-vincular es una **acción de escritura** que no puedo hacer en modo solo lectura.
  Si se cambia `ENGINE_TYPE=baileys` (recomendación 1) hay que re-vincular igualmente.
- **`memory.peak` y `memory.events` son acumulados desde el arranque del contenedor (20-oct 20:01)**, no hay
  histórico por intervalos: **no puedo probar que el pico de 2.0 GiB ocurriera exactamente dentro de 14:44–14:57**.
  Lo que sí es duro: el pico = 99.99 % del tope en algún momento de la vida del contenedor, `oom_kill=0`, la
  reclamación es 100 % directa, y la huella *viva* de Chromium (1.31 GiB RSS / 403 MB de perfil) deja poquísimo margen.
  **Experimento discriminante sugerido al lead**: muestrear `docker stats` + `memory.events` cada 5 s durante el
  próximo lote; si `max` sube y los envíos se estiran a la vez, queda cerrado.
- **No pude observar el estado de memoria durante el incidente** (no hay `cAdvisor`, ni `/api/metrics` — 404 —, ni
  historial de `docker stats`, ni `dmesg`/`journalctl -k` con eventos de memoria: vacíos).
- **No distinguí con certeza** si el stall lo provocó el *sistema de memoria* del cgroup o una *operación interna
  concreta de WhatsApp Web* (sincronización con 28 027 mensajes / 403 MB de IndexedDB). Ambos producen la misma
  firma (página sorda, `Runtime.callFunctionOn` lento, `Target closed`). El sub-test de la recomendación 3
  (subir `WAPI_TIMEOUT_MEDIA_MS` a 180 s y ver si los envíos *terminan* aunque tarden) separa las dos.
- **No medí la latencia hacia los servidores de WhatsApp** (`web.whatsapp.com` / `mmg.whatsapp.net`): mi medición fue
  contra Supabase Storage. La red hacia WA no está descartada al 100 %, aunque el patrón (2 grupos, misma
  degradación progresiva, `status=sent` sin `delivered`) apunta a la página, no a la red.
- **No medí el coste exacto de la inyección base64 en el page** (imagen mediana 37 KB ⇒ irrelevante, pero la cola de
  4.6 MB sí multiplica la memoria del renderer en el peor momento).
- **No verifiqué el efecto real de ninguna recomendación**: están propuestas, no probadas, y todas requieren
  recrear el contenedor (`docker compose up -d`), lo que está fuera de mi modo solo lectura.
- El contenedor tiene `read_only` rootfs + `cap_drop ALL` + `no-new-privileges`: el aislamiento está bien puesto;
  el problema no es de seguridad.

## 13. Anexo — comandos exactos y salidas guardadas

Los comandos completos y sus salidas crudas están en `__agent__/wapi/logs/`:

| Fichero | Contenido |
|---|---|
| `01_compose.txt` | `docker ps`, `docker images`, `cat docker-compose.yml` |
| `02_env_compose.txt`, `03_compose_keys.txt` | `.env` del host y envío de variables en compose |
| `07_genenv.txt` | `/app/data/.env.generated` (DATABASE_TYPE=sqlite, REDIS/QUEUE off) |
| `08_health.txt`, `10_health.txt` | `GET /api/health`, `/health/ready`, `/infra/health` con tiempos |
| `11_window_stats.txt`, `12_window_full.txt` | `docker logs --since/--until` + contadores de patrones |
| `13_resources.txt` | `free -m`, `nproc`, `uptime`, `df -h`, `docker stats`, zombies |
| `14_sqlite_tables.txt`, `15_schemas.txt`, `16_latency.txt`, `16b_latency.txt`, `17_timeline.txt` | esquema y consultas SQLite read-only, latencias, timeline |
| `18_memory.txt`, `19_io.txt`, `29_tmpfs.txt` | cgroup: `memory.peak/max/events/stat`, presión de IO, /tmp tmpfs |
| `21_imgtest.txt`, `30_imgsizes.txt` | descarga real de imágenes y su tamaño |
| `22_fsync.txt` | benchmark `fsync` y commit SQLite+FTS5 |
| `23_chrome_mem.txt`, `28_profile.txt` | procesos Chromium, RSS, tamaño del perfil, crash dumps |
| `25_pacing_audit.txt`, `26_pacing_config.txt` | `audit_logs` y defaults de `send-pacing.config.ts` |
| `27_metrics.txt`, `31_idem.txt`, `32_memlimit.txt` | `/api/metrics` (404), claves de idempotencia, `mem_limit` |

Nota de método: el host **no tiene `curl` ni `sqlite3`**; se usó `node` dentro del contenedor para HTTP y `python3`
del host con SQLite en modo `file:...?mode=ro` (URI read-only) para las consultas. Las salidas largas se
redirigieron a `__agent__/wapi/logs/`. La contraseña SSH sólo viajó por variable de entorno, nunca a disco.
