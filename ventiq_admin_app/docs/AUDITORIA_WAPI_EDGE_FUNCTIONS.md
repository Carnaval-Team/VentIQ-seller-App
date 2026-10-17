# Auditoría técnica — Edge Functions WAPI (OpenWA) de `ventiq_admin_app`

**Fecha de la auditoría:** 2026-10-17
**Proyecto Supabase auditado:** `vsieeihstajlrdvpuooh`
**Alcance:** las Edge Functions WAPI de `ventiq_admin_app` y su `_shared/`, que integran con **OpenWA** (gateway WhatsApp self-hosted, repo `rmyndharis/OpenWA`).
**Objetivo:** explicar por qué el bot "se muere" de forma aparentemente aleatoria, por qué hay que reiniciar la sesión a mano, y qué cambios hacer en las edge functions.

Todas las rutas de archivo de este informe son **relativas al workspace** (`C:\Users\cesar\Documents\VentIQ-seller-App`).

---

## 1. Resumen ejecutivo

Ordenado por impacto sobre el síntoma *"el bot se muere y hay que reiniciar la sesión a mano"*:

1. **No hay webhook funcional, y sin él nadie se entera de que la sesión se cayó.** El webhook se registra en el body de `POST /api/sessions` (ruta no documentada) y **sin `secret`**; sólo declara `message.received`/`message.sent`, así que los eventos `session.*` **nunca llegan**. La BD conserva un `CONNECTED` obsoleto y el bot queda muerto sin señal visible.
2. **Ninguna edge function intenta recuperar la sesión.** Ante un 409/400 de "sesión no conectada" el código reintenta 3 veces, marca `fallido` y termina. La recuperación sólo existe como botón humano en la app. De ahí las **4.995 filas `fallido`**.
3. **`/restart` no existe en OpenWA.** `_shared/wapi_client.ts:230` llama a una ruta inexistente; el reinicio manual sólo funciona por el fallback a `POST /start`, que sobre una sesión ya arrancada puede devolver 400/502. El "reinicio soportado" es **stop → start** (y, en escalada, `force-kill → start`), y el cliente no tiene ni `stopSession` ni `forceKill`.
4. **`action_required` no está en el mapa de estados y se pinta como "Inicializando".** Es el estado del modal *"What's new"* de WhatsApp: si el modal no está en inglés y su etiqueta no está en `WWEBJS_ONBOARDING_CONTINUE_LABELS`, la sesión enlaza y **se cae a `disconnected` con reason `LOGOUT` a los pocos minutos**. En Cuba la UI está en español: escenario muy plausible para el "se muere solo".
5. **El bug upstream que describe exactamente el síntoma está arreglado en OpenWA `v0.25.0`**, pero la documentación local (`ventiq_admin_app/docs_wapi/`) es de la era **v0.11.1** (14 versiones menores por detrás). **La versión que corre en el servidor no se ha podido verificar.**
6. **El estado de la sesión se lee de la copia en BD**, no de OpenWA, justo antes de enviar (`wapi-send-products/index.ts:1550`). Con el webhook roto, eso significa o rechazar una sesión sana con 409, o creer que está viva cuando está muerta y hacer fracasar **todos** los envíos con 409/400.
7. **La difusión diaria se salta en silencio.** `wapi-cron-dispatch/index.ts:63` devuelve `200 {skipped: "session_not_connected"}` sin alerta. Coherente con lo observado: la programación 13 quedó `activa=false`, `last_run_at` 2026-09-07, `next_run_at` null.
8. **No se usa la única palanca oficial de reconexión por sesión.** `createSession()` nunca envía el `config` documentado (`reconnectBaseDelay`, `maxReconnectAttempts`); si no se fija, OpenWA reintenta sin límite con el delay estacionado en **5 minutos**.
9. **El diagnóstico está envenenado por el propio log.** `wapi-send-products/index.ts:1328` escribe siempre `"(tras 3 intentos)"` aunque el bucle saliera por falta de presupuesto o por error no reintentable; y `PRODUCT_TIMEOUT` (1.356 filas) marca como *fallido* trabajo que en realidad sólo se abandonó por reloj.
10. **Seguridad (crítico, fuera de las edge functions):** el JWT de `service_role` del proyecto, con `exp` en 2035, está **commiteado en claro** en `ventiq_admin_app/supabase/migrations/20260527_wapi_dispatch_vault.sql:35`. Hay que rotarlo. No causa el síntoma, pero es el hallazgo más grave del repo.

---

## 2. Cómo se diagnosticó

| Vía | Qué se miró | Resultado |
|---|---|---|
| **BD en vivo** (MCP Supabase, proyecto `vsieeihstajlrdvpuooh`, medido 2026-10-17) | `app_wapi_envio_log`, `app_wapi_sesion`, `app_wapi_programacion`, `cron.job` | 11.739 filas / 4.776 kB; 4.995 `fallido`; sesión 22 en `SCAN_QR` sin teléfono; programación 13 inactiva desde 2026-09-07; `wapi_dispatch_diario` corre cada minuto con `succeeded` |
| **Código** | 13 archivos de `ventiq_admin_app/supabase/functions/` (`_shared/` + 10 funciones) | 17 hallazgos, detallados en §4 |
| **Docs upstream** | repo público `rmyndharis/OpenWA` (rama `main`, verificado 2026-10-17), CHANGELOG y runbooks | Última release **v0.25.0 del 2026-10-15**; el fix de reconexión está dentro; `/restart` no existe |
| **Docs locales** | `ventiq_admin_app/docs_wapi/` | Decía "Last updated: 2026-07-28" = era **v0.11.1**: 14 versiones menores por detrás. **Ya resincronizada** a `main` (0.25.0) con `scripts/sync_wapi_docs.mjs`; ver §6 y `docs_wapi/UPSTREAM.md` |
| **Lo que NO se pudo medir** | versión real del servidor OpenWA, su `ENGINE_TYPE`, su `config` de reconexión, y si honra las doce rutas con `Idempotency-Key` | Requiere URL + API key del gateway (`GET /api/health` sólo devuelve `version` con key válida). Ver §9 |
| **Lo que NO se pudo ejecutar** | `deno check` sobre las funciones desplegables | En este entorno no hay `deno` ni `supabase` CLI (tampoco se pudo instalar: `npx` falla con `EPERM` en el sandbox). Sí se validó la **sintaxis** de los 13 archivos con el *type stripping* de Node 22 y se escribieron **pruebas unitarias** de la lógica pura (29 aserciones en verde). La verificación de **tipos** queda pendiente (§9.4) |

---

## 3. Evidencia de producción

### 3.1 Tabla `app_wapi_envio_log` (proyecto `vsieeihstajlrdvpuooh`, 2026-10-17)

**11.739 filas · 4.776 kB · rango 2026-07-30 → 2026-10-14**

| `estado` | Filas |
|---|---:|
| `enviado` | 6.179 |
| `fallido` | 4.995 |
| `pendiente` | 565 |

**42,6 % de los envíos terminaron en `fallido`.**

### 3.2 Distribución de `error_code` en `fallido`

| `error_code` | Filas | Mensaje observado | Qué significa | De quién es la culpa |
|---|---:|---|---|---|
| `HTTP_500` | **1.599** | `"Internal server error"` (1.598) + `"Internal server error (tras 3 intentos)"` (1) | Fallo interno del servidor OpenWA / su Chromium (whatsapp-web.js). El engine se rompió o el worker se quedó sin recursos | **OpenWA** (infra) |
| `HTTP_409` | **1.567** | `"Session is not connected. The WhatsApp client is not ready."` (1.538) y `"WhatsApp Web is reloading its page and the session is re-injecting. Retry in a few seconds."` (29) | La sesión **ya estaba caída** (o reinyectándose) y el código siguió intentando enviar. El 409 no es la causa: es el aviso de que la causa ocurrió antes | **Nosotros** (no reaccionamos al 409) |
| `PRODUCT_TIMEOUT` | **1.356** | Generado por nuestro propio código (`wapi-send-products/index.ts:1396`) | El producto agotó su ventana de reloj y se abandonaron sus destinos restantes. Están marcados `fallido`, pero **no hubo fallo de WhatsApp** | **Nosotros** (etiquetado) |
| `TIMEOUT` | **308** | Timeout de nuestro `wapi_client` (20 s / 45 s con media) | OpenWA abrió conexión y nunca respondió (Puppeteer atascado). Nuestro lado lo cortó | **Nosotros** (detección) / OpenWA (causa) |
| `HTTP_400` | **165** | `"Session '<uuid>' is not active. Start the session first."` | El **engine está detenido**: la sesión existe en el gateway pero no hay proceso vivo. Es el estado previo a "escanea el QR otra vez" | **OpenWA + nosotros** |

**Detalle clave del `HTTP_400`:** aparecen **tres UUID distintos** — `3f394210-…`, `616617fb-…`, `f0f93a15-…`. Es decir, la sesión se **recreó al menos tres veces**, y cada recreación invalidó la anterior dejando envíos apuntando a un engine muerto.

### 3.3 Estado de la sesión y de la programación

| Tabla | Registro | Valores |
|---|---|---|
| `app_wapi_sesion` | id **22** | `id_tienda` 177 · `wapi_session_id` `3f394210-aa7e-4279-a330-b5639d3024e7` · `status` **`SCAN_QR`** · `phone_number` **null** · `last_status_at` 2026-10-17 11:12 |
| `app_wapi_programacion` | id **13** | tienda 177 · sesión 22 · **`activa` = false** · `hora_envio` 19:30 · `timezone` `America/New_York` · delays 5/10 s · `last_run_at` **2026-09-07** · `next_run_at` **null** |
| `cron.job` | `wapi_dispatch_diario` | cada minuto, activo, `succeeded` en **cada** corrida |

**Lectura:** la sesión está pidiendo QR (nunca enlazó, `phone_number` null) desde al menos 2026-09-07, y la programación diaria está apagada desde esa fecha. El cron "tiene éxito" todos los minutos porque `wapi-cron-dispatch` se sale con **200** cuando el estado en BD no es `CONNECTED` (hallazgo 14). **Un fallo total del negocio se ve como un cron sano.**

### 3.4 Tareas pendientes

Las **565 filas `pendiente`** son **todas de la tienda 177** y **todas de la sesión 22**; **330** de ellas tienen `tipo_envio='programado'`. Son trabajo real que nunca se envió y que la UI presenta como tandas "interrumpidas" con botón *Reanudar* — indistinguibles del ruido de `PRODUCT_TIMEOUT`.

---

## 4. Hallazgos por archivo

Severidades: **Crítico** = causa directa del síntoma o riesgo de seguridad · **Alto** = agrava o perpetúa el síntoma · **Medio** = dificulta el diagnóstico / degrada · **Bajo** = higiene.

### 4.1 `ventiq_admin_app/supabase/functions/_shared/wapi_client.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 1 | **Crítico** | `:230` | `restart()` hace `POST /api/sessions/:id/restart`. **Esa ruta no existe en OpenWA**: su runbook dice literalmente *"Try session restart (stop then start — there is no /restart route)"*. | Todo "reinicio" del sistema arranca con una llamada condenada a 404/400. Sólo el fallback a `/start` (`wapi-session-action/index.ts:108-114`) lo salva por accidente, y sobre una sesión ya arrancada `/start` puede devolver 400 (se tolera con `looksAlreadyStarted`) o **502**. |
| 2 | **Alto** | `:187` | `createSession()` **nunca envía el `config` por sesión** documentado: `{"config": {"reconnectBaseDelay": 5000, "maxReconnectAttempts": 10}}`. | Se ignora la **única palanca oficial de reconexión por sesión**. Sin ella, OpenWA reintenta sin límite con el delay estacionado en **5 minutos**: la sesión tarda muchísimo en volver, y si se cae antes de los 5 minutos de estabilidad el contador no se reinicia. |
| 3 | **Crítico** | archivo completo | **No existen** `stopSession`, `forceKill` ni los endpoints de health (`/api/health`, `/api/health/live`, `/api/health/ready`). | Sin ellos es imposible hacer el reinicio soportado (stop→start), la escalada a `force-kill` ni comprobar la **versión** del servidor OpenWA. La mitad de la superficie de diagnóstico y recuperación simplemente no está implementada. |
| — | 👍 | `:42-44`, `:56-59` | Timeouts por operación (20 s / 45 s con media) con `AbortController` manual y limpieza del timer. | **Bien hecho.** El comentario del archivo documenta el bug real que esto arregló: una request que nunca respondía congelaba el worker hasta el techo de ~400 s y se llevaba por delante toda la cadena de chunks. |
| — | 👍 | `:84-107`, `:116-135` | `retryAfterSeconds` leído del body **o** del header `Retry-After`; distinción `TIMEOUT` vs `NETWORK_ERROR`. | **Bien hecho.** Es la base para respetar el `SEND_PACING` y para no confundir un timeout propio con un fallo de red. |

### 4.2 `ventiq_admin_app/supabase/functions/_shared/status.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 4 | **Crítico** | `:38` (mapa `MAP`) | El mapa **no contempla `action_required`**, estado documentado de OpenWA (`created \| initializing \| qr_ready \| authenticating \| ready \| disconnected \| action_required \| failed`). `normalizeWapiStatus("action_required")` cae al `fallback`, normalmente `INITIALIZING`. | Una sesión que **requiere acción humana** se pinta en la app como **"Inicializando" (ámbar)**, no como "Desconectado" (rojo). El operador no tiene ninguna señal de que hay que intervenir, y la sesión muere a los pocos minutos. La causa documentada de `action_required` es el modal *"What's new"*: si no está en inglés y su etiqueta no está en `WWEBJS_ONBOARDING_CONTINUE_LABELS`, *"it links normally, then drops to `disconnected` with reason `LOGOUT` a few minutes later"*. **En Cuba la UI está en español → escenario muy plausible del "se muere solo".** |
| — | 👍 | `:23-26` | El comentario explica por qué se colapsan las dos formas (internal y API) a 6 canónicas. | **Bien hecho.** |

### 4.3 `ventiq_admin_app/supabase/functions/_shared/auth.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 5 | **Medio** (Crítico si `--no-verify-jwt`) | `:92` | `isServiceRoleCall()` **decodifica el JWT sin verificar la firma**. | Aceptable **sólo** si el gateway de Edge Functions verifica JWT. Si el proyecto corre con `--no-verify-jwt`, cualquiera puede fabricar un token con `role: "service_role"` y entrar por las funciones que sólo protegen con esta comprobación (`wapi-cron-dispatch:25`). |
| — | 👍 | `:85-90`, `:109-118` | El propio comentario documenta la limitación y sugiere `iss === "supabase"` + `ref`; el código comprueba `iss` y `exp`. | **Bien hecho.** La mitigación ya está a medias; falta fijar la verificación en el gateway o validar la firma de verdad. |

### 4.4 `ventiq_admin_app/supabase/functions/_shared/invoke.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 6 | **Medio** | `:40-113` | El encolado de cada chunk se hace por HTTP (**dos** rutas: `functions.invoke` y fallback `fetch`) **sin clave de idempotencia**. El flag `reinvoked` (`wapi-send-products/index.ts:868`) protege dentro de **un** worker, pero no entre las dos rutas de `invoke.ts`. | Un fallback reintentado puede **duplicar el chunk restante**: mensajes repetidos a los mismos destinatarios (riesgo de spam y de baneo). El riesgo es acotado porque la regla anti-duplicados descarta los 4xx deterministas, pero no es cero ante 5xx/timeout. |
| — | 👍 | `:12-17`, `:55-65` | Regla explícita: un 4xx (salvo 429) es rechazo determinista y **no** se reintenta por `fetch`. | **Bien hecho**, y bien documentado. |

### 4.5 `ventiq_admin_app/supabase/functions/wapi-session-create/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 7 | **Crítico** | `:58` | Registra el webhook **en el body de `POST /api/sessions`** (`{ name, webhook: { url, events } }`), que **no es la ruta documentada** (`POST /api/sessions/:sessionId/webhooks`) y **no manda `secret`**. | Dos consecuencias graves: **(a)** sólo puede declarar `message.received`/`message.sent`, así que **nunca llegan los eventos `session.*`** y el estado en BD no se actualiza cuando la sesión se cae; **(b)** si OpenWA genera su propio secret para el webhook, `wapi-webhook` compara el HMAC contra `WAPI_WEBHOOK_SECRET` y **rechaza con 401 todas las entregas**. |
| 8 | **Alto** | `:62-67` | El fallback reintenta crear la sesión **sin webhook** si el intento con webhook falla. | Deja sesiones **sin ningún evento**: el bot queda ciego por diseño. El comentario dice que el webhook "puede registrarse después vía `/api/sessions/:id/webhooks`", pero **hasta esta sesión nada lo hacía**. |

### 4.6 `ventiq_admin_app/supabase/functions/wapi-session-status/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 9 | **Medio** | `:78-84` | Persiste sólo el status **normalizado**; el status **crudo** de OpenWA no se guarda en ningún sitio. | Diagnosticar a posteriori un `action_required`, un `failed` con reason, un `reconnect_loop` o un `restriction` es **imposible sin mirar logs, que caducan**. Es una de las razones por las que este incidente tardó meses en entenderse. |
| — | 👍 | `:54-61` | Acepta `image`, `qrCode` y `qr` como fuentes del data-URL del QR. | **Bien hecho:** ya cubre la variante `qrCode` de las builds actuales. |

### 4.7 `ventiq_admin_app/supabase/functions/wapi-session-action/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 10 | **Crítico** | `:106` | Llama **primero** a `wapi.restart()` (ruta inexistente) y sólo cae a `/start` en `:108-114`. | El "reiniciar" que el operador pulsa a mano empieza siempre con una llamada inválida. Funciona **por accidente**, y el fallback tiene sus propios modos de fallo (400 "already started" tolerado, 502 propagado al usuario). |
| — | 👍 | `:18-25`, `:120-128` | `looksAlreadyStarted()` traduce el 400 de `/start` a "ya estaba arrancada" y relee el estado en vez de devolver 502. | **Bien hecho:** es exactamente la clase de tolerancia que hacía falta. |

### 4.8 `ventiq_admin_app/supabase/functions/wapi-list-sessions/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 11 | **Medio** | `:30` | Sincroniza con `Promise.all` **sin límite**: N sesiones = N peticiones **paralelas** a OpenWA. | Con una sola sesión es inocuo; con varias, se golpea a la vez un gateway que mantiene **un Chromium por sesión** y es sensible a la concurrencia. Además, si `getSession` falla, **deja el estado viejo en silencio** (no hay rama `else`): otra fuente de estado obsoleto. |

### 4.9 `ventiq_admin_app/supabase/functions/wapi-list-groups/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 12 | **Medio** | `:22` | Rechaza con `409 NOT_CONNECTED` si `ses.status !== "CONNECTED"`, leyendo **la copia en BD**. | Mismo problema que el hallazgo 15, en modo lectura: con el webhook roto y el estado obsoleto, la app puede negarse a listar grupos de una sesión **sana** (409 espurio) o intentarlo contra una sesión **muerta**. El usuario ve "sesión no conectada" sin que eso corresponda a la realidad. |

### 4.10 `ventiq_admin_app/supabase/functions/wapi-webhook/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 13 | **Crítico** | `:82-141` | El `switch` maneja sólo `session.status`, `session.authenticated`, `session.disconnected`, `session.qr` y `message.ack`. **Ignora `session.reconnect_loop`** (la señal oficial de *"la sesión está muriendo"*: se emite cada 5.º intento consecutivo), **`session.restriction`** y **`message.failed`**. | Se descarta precisamente la telemetría que existe para este síntoma. Aunque el webhook llegara bien, el sistema seguiría sin ver el aviso más temprano de caída. |
| 14 | **Alto** | `:46-54` | **No deduplica** por `X-OpenWA-Idempotency-Key` / `X-OpenWA-Delivery-Id`. | OpenWA documenta explícitamente que los re-runs de la cola y los barridos del outbox **reentregan la misma clave** y que las entregas pueden llegar **desordenadas**. Sin deduplicar, un `message.ack` viejo puede reescribir `mensaje_id`/`estado` de un log ya resuelto, y un `session.status` retrasado puede pisar un estado más nuevo. |
| 15 | **Alto** | `:107` | En `session.qr` lee `data.image`, pero OpenWA devuelve el campo **`qrCode`**. | El QR no se guarda en `last_qr_image` por webhook. (Mitigado: `wapi-session-status:57-61` sí acepta `qrCode`.) |
| 16 | **Crítico** | `:13-19` | Si `WAPI_WEBHOOK_SECRET` no está configurado, `verifySignature()` **devuelve `true`** tras un `console.warn`. | El webhook no tiene **ninguna** otra autenticación: cualquiera que conozca la URL puede hacer POST y **cambiar el `status` de una sesión o reescribir `mensaje_id`** en los logs de envío. La URL se construye como `${SUPABASE_URL}/functions/v1/wapi-webhook?tienda=<id>`: es adivinable. |

### 4.11 `ventiq_admin_app/supabase/functions/wapi-send-products/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 17 | **Crítico** | `:1550` | Antes de enviar comprueba `ses.status !== "CONNECTED"` contra **la copia en BD**, que sólo se actualiza cuando la app llama a `wapi-session-status` o cuando llega un webhook. | Con el webhook roto (hallazgo 7), la BD queda desactualizada: **o rechaza con 409 una sesión sana, o cree que está CONNECTED cuando está muerta y entonces *todos* los envíos fallan con 409/400.** Es el mecanismo central del síntoma. |
| 18 | **Crítico** | `:1237-1332` | El camino del 409 (*"Session is not connected"*) reintenta 3 veces con backoff y marca **`fallido`**. **Nunca intenta recuperar la sesión.** | Explica directamente las **4.995 filas `fallido`** con `HTTP_409`/`HTTP_400`: el código convierte una sesión caída —recuperable con stop→start— en miles de fallos permanentes, y hace falta que **una persona** pulse "reiniciar". |
| 19 | **Medio** | `:1328` | Escribe `error_message: \`${ultimoMsg} (tras ${RETRY_MAX_ATTEMPTS} intentos)\`` **siempre**, incluso cuando el bucle salió antes por falta de presupuesto (`sinTiempo`, `:1302`) o por error **no** reintentable (`:1303-1314`). | **El mensaje miente.** Las 1.599 filas `HTTP_500` dicen "tras 3 intentos" aunque muchas fueron el **primer** mensaje de un chunk contra una sesión ya muerta. Eso desvió el diagnóstico hacia "OpenWA falla mucho" cuando la causa era "había un solo intento contra una sesión caída". |
| 20 | **Medio** | `:1385-1401` | Marca como **`fallido`** con `PRODUCT_TIMEOUT` los destinos que abandona por reloj (1.356 filas). | Es **ruido**: la UI lo convierte en tareas pendientes reanudables y son **indistinguibles de un fallo real**. Contamina cualquier métrica de salud del bot y multiplica las "tandas interrumpidas" fantasma. |
| 21 | **Bajo** | `:868-871` | `reinvoked` protege la re-invocación **dentro** de un worker, no entre las dos rutas de `_shared/invoke.ts`. | Ver hallazgo 6. La mitigación existe y está razonada; el hueco es entre funciones. |
| — | 👍 | `:1335-1359` | **Chunking por reloj**: antes de cada producto se comprueba si «cabe» en lo que queda de worker; si no, se corta y se encola con 400 s frescos. Precarga **por ventanas** (`WINDOW_SIZE`) en vez de una consulta por producto o una gigante que se trunca. | **Muy bien hecho.** Es la razón por la que los envíos largos llegaban a completarse antes de que la sesión empezara a caerse. |
| — | 👍 | `:1273-1296` | Respeta `retryAfterSeconds` del 429 (`SEND_PACING_LIMITED`); si la pausa no cabe en el presupuesto, **corta el chunk y deja las filas en `pendiente`** — "es trabajo por hacer, no un fallo". | **Muy bien hecho**, y la decisión está documentada en el propio código. |
| — | 👍 | `:1366-1368` | Envío **EN SERIE** con el comentario de por qué: la sesión es **una** instancia de Puppeteer y dos envíos simultáneos devuelven `NETWORK_ERROR`. | **Muy bien hecho.** Explica el fenómeno "a un grupo iba perfecto y a cuatro se caía la mitad". |
| — | 👍 | `:1299-1320` | Backoff exponencial con jitter ±25 % para no sincronizar reintentos. | **Bien hecho** (el problema es el *etiquetado* del resultado, no el backoff). |

### 4.12 `ventiq_admin_app/supabase/functions/wapi-cron-dispatch/index.ts`

| # | Sev. | Línea | Qué pasa | Por qué importa |
|---|---|---|---|---|
| 22 | **Crítico** | `:63` | Devuelve **200** con `{skipped: true, reason: "session_not_connected"}` cuando el estado **en BD** no es `CONNECTED`. | Mismo estado obsoleto que el hallazgo 17, pero aquí el efecto es el peor posible: **la difusión diaria se salta en silencio, sin alerta y con el cron marcando `succeeded`.** Coherente con lo observado: la programación 13 quedó `activa=false` con `last_run_at` del 2026-09-07 y la sesión lleva desde entonces en `SCAN_QR`. **El negocio dejó de enviar y nadie recibió un error.** |
| — | 👍 | `:8-16` | El comentario explica **por qué** se delega en `wapi-send-products` en vez de despachar aquí: un worker limpio con 400 s frescos, no atado al worker del cron que Supabase puede reciclar. | **Excelente decisión de diseño, y documentada.** Es lo que permite que la cadena de chunks sobreviva. |
| — | 👍 | `:130-138` | Si el encolado falla, devuelve **502** en vez de 200 ("devolver 200 haría que pg_cron registrara un éxito para un envío que nunca arrancó"). | **Bien hecho.** El contraste con la línea 63 es justamente el problema: ahí sí se enmascara. |
| — | 👍 | `:122-124` | Comentario sobre el bug de precedencia de operadores que producía un estimado erróneo. | **Bien hecho** (higiene y memoria del bug). |

---

## 5. Cadena causal completa

El ciclo, paso a paso, tal como ocurre hoy:

1. **La sesión se cae dentro de OpenWA.** Causa upstream (bug de reconexión corregido en `v0.25.0`, OOM de Chromium, límite de PIDs, o el modal *"What's new"* en español → `action_required` → `disconnected` con reason `LOGOUT`). El gateway emite `session.disconnected` y, si insiste, `session.reconnect_loop`.
2. **Esos eventos no llegan.** El webhook se registró en la ruta equivocada y sin `secret`, y sólo declara `message.received`/`message.sent` (hallazgo 7). Nunca se declararon los eventos `session.*`. Y si el gateway sí los mandara, `wapi-webhook` los rechazaría con **401** (secret distinto) o los ignoraría (`reconnect_loop` no está en el `switch`, hallazgo 13).
3. **La BD queda con `CONNECTED` obsoleto.** Nadie actualiza `app_wapi_sesion.status`; `last_status_at` envejece. Si la app abriera la pantalla de sesión, `wapi-session-status` lo corregiría — pero eso **sólo pasa si un humano mira**.
4. **Los envíos siguen saliendo contra una sesión muerta.** `wapi-send-products:1550` lee la BD, ve `CONNECTED`, y despacha. OpenWA responde **409** (*"Session is not connected…"*) o **400** (*"Session '…' is not active"*).
5. **Se reintenta 3 veces y se marca `fallido`.** `:1237-1332`. No hay recuperación: **nadie hace stop→start** (hallazgo 18). El estado en BD **sigue** en `CONNECTED`, así que el siguiente chunk repite el ciclo.
6. **Se acumula el desastre.** 4.995 `fallido` (1.567 con 409, 165 con 400, 1.599 con 500 del engine roto) + 565 `pendiente` (330 programados) + 1.356 `PRODUCT_TIMEOUT` de ruido.
7. **Nadie reinicia.** El botón "reiniciar" de la app existe, pero depende de que una persona se dé cuenta — y la UI no ayuda: `action_required` se pinta como **"Inicializando" ámbar** (hallazgo 4), es decir, como si estuviera arrancando normalmente.
8. **La difusión diaria se apaga sola y en silencio.** `wapi-cron-dispatch:63` se sale con **200 `skipped: session_not_connected`** cada minuto; `cron.job_run_details` registra `succeeded`; nadie recibe alerta. La programación 13 lleva desde 2026-09-07 sin correr y `next_run_at` quedó en `null`.

```
  OpenWA (sesión se cae)
    │  emite session.disconnected / session.reconnect_loop
    │
    ├──────────► webhook registrado MAL (ruta no documentada, sin secret,
    │            sólo message.*)  ⇒  los eventos NO llegan
    │                                   │
    │                                   └─► si llegaran: 401 (secret) o ignorados
    │
    ▼
  app_wapi_sesion.status  =  "CONNECTED"   ← OBSOLETO, nadie lo corrige
    │
    ├──► wapi-cron-dispatch:63  → 200 {skipped: session_not_connected}
    │                            SIN ALERTA · cron = "succeeded"
    │                            ⇒ difusión diaria muerta desde 2026-09-07
    │
    └──► wapi-send-products:1550  ve CONNECTED ⇒ despacha
            │
            ├─ 409 "Session is not connected"      1.567
            ├─ 400 "Session '…' is not active"       165
            ├─ 500 "Internal server error"         1.599   (engine roto)
            └─ TIMEOUT / NETWORK_ERROR               308
                    │
                    ▼  reintento ×3 (backoff+jitter) → NO recupera sesión
                 estado = "fallido"      (4.995 filas)
                 + PRODUCT_TIMEOUT       (1.356 filas de ruido)
                 + 565 "pendiente" (330 programadas)
                    │
                    ▼
          Una PERSONA pulsa "reiniciar"   ← único camino de recuperación existente
                    │
                    └─ wapi-session-action:106  →  POST /restart  ⇒ NO EXISTE
                                                     (sólo salva el fallback /start)
```

---

## 6. Qué cambia en OpenWA desde la documentación local (v0.11.1 → v0.25.0)

**Aviso central:** el snapshot local `ventiq_admin_app/docs_wapi/` decía *"Last updated: 2026-07-28"*, que corresponde a la release **v0.11.1**. La última release upstream es **v0.25.0 (2026-10-15)**: **14 versiones menores por detrás**. **La versión que corre en el servidor NO se ha podido comprobar** (no se tiene URL ni API key de OpenWA desde este entorno). Se mide con `GET /api/health`, que devuelve `version` **sólo si se manda una key válida** (ver §8, paso 6).

> **Actualización posterior a esta auditoría:** la copia local se **resincronizó** con la doc de `main` (`0.25.0`) con
> `node ventiq_admin_app/scripts/sync_wapi_docs.mjs`. Ahora `docs_wapi/` contiene 41 archivos de la doc oficial
> (incluido el nuevo `31-session-lifecycle-design.md`) y un índice `docs_wapi/UPSTREAM.md` con el ref y la versión
> sincronizados. Las afirmaciones de esta tabla están ya **verificadas contra esos archivos locales**: p. ej.
> `docs_wapi/11-operational-runbooks.md:130` (*"there is no /restart route"*),
> `docs_wapi/06-api-specification.md:4606` (lista de eventos de webhook) y
> `docs_wapi/12-troubleshooting-faq.md:583-616` (modal *"What's new"* / `action_required`).
> Para volver a actualizarla: `node ventiq_admin_app/scripts/sync_wapi_docs.mjs`.

| Tema | Qué dice la doc local (v0.11.1) | Qué hay en v0.25.0 | Relevancia para el síntoma |
|---|---|---|---|
| **Bug de reconexión** | No existe | **Arreglado en 0.25.0.** Cita literal del CHANGELOG: *"A failed reconnect attempt no longer arms another attempt that tears down the next attempt's engine, which repeated until the session ended `failed`"*. Y además: *"Handle an engine disconnect again when the session row read fails, so the session reconnects instead of staying registered with no reconnect armed"* | **Es la descripción exacta del síntoma**: la sesión termina `failed` tras una cadena de reintentos que se sabotean entre sí. Si el servidor corre < 0.25.0, **este bug está activo y ninguna edge function puede arreglarlo del todo** |
| **Reconexión por sesión** | No documentada | `reconnectBaseDelay` (1000–300000 ms, default 5000) y `maxReconnectAttempts` (0–20; 0 lo desactiva; **si no se pone, reintentos ilimitados con el delay estacionado en 5 minutos**) | El conteo de intentos **se reinicia sólo si la sesión se mantuvo READY 5 minutos**; una sesión que se cae antes **gasta un tope finito y termina FAILED**. Nuestro cliente nunca manda este `config` (hallazgo 2) |
| **Watchdog oficial** | No documentado | *"probes every 60 s with a 15 s timeout and treats two consecutive failures as a disconnect, so a wedge is picked up in roughly 75 to 135 s"*. En `action_required` **sólo observa, no recupera** | Da la referencia de latencia esperada: un atasco debería detectarse en **75–135 s**. Hoy nadie detecta nada. Y confirma que `action_required` **exige mano humana**, coherente con el hallazgo 4 |
| **Idempotencia de envío** | No existe | **Nueva en 0.25.0**: header `Idempotency-Key` (1–255 ASCII) en **doce rutas** de envío a un destinatario, retención 24 h. Códigos `IDEMPOTENCY_KEY_INVALID` (400), `IDEMPOTENCY_KEY_REUSED` (422), `IDEMPOTENCY_KEY_IN_PROGRESS` (409), `IDEMPOTENCY_OUTCOME_UNKNOWN` (409: *"a failure may have sent the message"*) | Permite eliminar los duplicados del hallazgo 6 y saber si un envío "desconocido" se mandó o no |
| **Pacing de envío** | No existe | Apagado por defecto. Rechazos **429** con `code: "SEND_PACING_LIMITED"` + `retryAfterSeconds`. Variables `SEND_PACING_ENABLED`, `SEND_PACING_WARMUP_SCHEDULE`, `SEND_PACING_COLD_DAILY_CAP`, `SEND_PACING_BREAKER_THRESHOLD`, `SEND_PACING_BREAKER_COOLDOWN_MS` | Nuestro cliente **ya respeta** `retryAfterSeconds`; sólo falta activarlo en el gateway (ver §10) |
| **Ciclo de vida** | No listado | `POST /api/sessions/:id/start`, `/stop`, `/logout`, **`/force-kill`**, `DELETE /api/sessions/:id` (204), `/pairing-code`. **No hay `/restart`.** El runbook dice: *"Try session restart (stop then start — there is no /restart route)"* | Confirma el hallazgo 1 y define la escalera real de recuperación |
| **Health** | No listado | `GET /api/health`, `/api/health/live` (siempre ok, **incluso en teardown**), `/api/health/ready` (proba ambas BD, **503 mientras drena**), `GET /api/infra/health` | Es el termómetro que hoy no podemos leer (hallazgo 3) |
| **Webhooks** | Registro sólo implícito en el body de `POST /api/sessions` | Registro documentado: **`POST /api/sessions/:sessionId/webhooks`** con `url`, `events[]`, **`secret`**, `retryCount` (0–5; default **3**). Headers `X-OpenWA-Signature` (HMAC-SHA256 sobre el **cuerpo crudo**, formato `sha256=<hex>`, sólo si el webhook tiene secret), `X-OpenWA-Event`, `X-OpenWA-Idempotency-Key`, `X-OpenWA-Delivery-Id`, `X-OpenWA-Retry-Count`. Envelope `{event, timestamp, sessionId, idempotencyKey, deliveryId, data}`. Eventos útiles: `session.status`, `session.disconnected`, **`session.reconnect_loop`**, **`session.restriction`**, `message.ack`, **`message.failed`**. **Reentregas:** los workers de cola re-ejecutan jobs al reiniciar y los barridos del outbox reenvían el mismo evento **con la misma `Idempotency-Key`** → el receptor debe deduplicar | Es la corrección de los hallazgos 7, 13 y 14. También valida que el HMAC va sobre el **cuerpo crudo** (`wapi-webhook:50` ya usa `req.text()`, correcto) |
| **QR** | `image` + `code` | `GET /api/sessions/:id/qr` → `{"qrCode":"data:image/png;base64,…","status":"qr_ready"}`, válido **~60 s** | Valida el ajuste de `wapi-session-status:57-61` y señala el bug del hallazgo 15 |
| **Motores** | No documentado | `ENGINE_TYPE` = `whatsapp-web.js` (**default**) o `baileys`. Se elige **una vez por despliegue** y cambiar requiere reinicio. `baileys` usa mucha menos RAM por sesión; `whatsapp-web.js` lleva **un Chromium por sesión** (≈300–500 MB) y **es el único cuyo reconnect gobierna el gateway**. No hay ranking oficial de estabilidad | Explica el OOM como causa upstream y da una palanca (con matices: cambiar de motor cambia quién gobierna la reconexión) |
| **Despliegue** | No documentado | **`replicas: 1` obligatorio:** *"Run exactly one API instance per session-data volume"* | Dos instancias sobre el mismo volumen corrompen el estado de sesión |
| **Límites y fragilidad** | No documentado | `OPENWA_MEM_LIMIT` default **2g**, `OPENWA_PIDS_LIMIT` default **2048**; corrupción del perfil al hacer **rollback de una versión mayor de Chrome** (borra el IndexedDB del perfil y **todas las sesiones vuelven a QR**); modal *"What's new"* no reconocido → `disconnected` con reason `LOGOUT` a los pocos minutos | OOM/PIDs = causa upstream de los `HTTP_500` y del engine muerto; el rollback de Chrome explica los **tres UUID distintos** de `HTTP_400` (sesiones recreadas) |
| **Estado `action_required`** | No existe en la doc local | Estado de sesión documentado: `created \| initializing \| qr_ready \| authenticating \| ready \| disconnected \| action_required \| failed`. Requiere confirmar el modal; la etiqueta debe estar en `WWEBJS_ONBOARDING_CONTINUE_LABELS` | Cierra el hallazgo 4 con la causa concreta y la variable a tocar (§10) |

---

## 7. Cambios aplicados en esta sesión (pendientes de despliegue)

> **Estado: aplicados en el árbol de trabajo y PENDIENTES DE DESPLIEGUE.** Nada de esto está en producción. Se publica con `npx supabase functions deploy …` (comandos en §8). Ver §9 antes de desplegar.

| Archivo | Qué hace ahora |
|---|---|
| `ventiq_admin_app/scripts/wapi_cleanup.mjs` | Script CLI de limpieza de la bitácora y las "tareas pendientes". **Dry-run por defecto**; los borrados se hacen **en lotes por ventanas de `id`** para no abrir una transacción gigante. Modos `--pendientes`, `--fallidos`, `--enviados`, `--logs`, `--all`, `--qr`; filtros `--tienda`, `--sesion`, `--older-than DAYS`; credenciales por `--url`/`--key`, variables de entorno o `--env-file`. **No toca** sesiones de OpenWA, programaciones ni destinatarios |
| `ventiq_admin_app/sql/wapi_cleanup.sql` | Tres funciones SQL: `fn_wapi_backlog_report()` (conteos de bitácora + **tandas que la app pintará como "interrumpida"**, con el mismo umbral de 10 min que `WapiEnvioTanda._umbralInactividad` en Flutter), `fn_wapi_purge_envio_log(...)` (purga en lotes, con dry-run) y `fn_wapi_purge_infra_logs(...)` (**pg_net** `net._http_response` + `cron.job_run_details`). `SECURITY DEFINER`, concedidas sólo a `service_role`. Incluye un **job de retención de pg_cron comentado** (descomentarlo es una decisión explícita: borra historia automáticamente) |
| `ventiq_admin_app/supabase/functions/_shared/status.ts` | Ampliado con los estados nuevos de OpenWA: **`action_required` → `DISCONNECTED`** (rojo / "Desconectado" / botón reiniciar), más `attention_required`, `restricted`, `restriction`, `suspended`, `banned`, `unlinked`, `deleted`, `terminated`, `reconnecting`, `reinjecting`, `engine_loading`, `restoring`. Añade `rawStatusKey()`, aviso en logs de status **desconocido** (una vez por isolate), y los predicados `isSessionDown()`, `isSessionSendable()`, `isSessionTerminal()` (este último codifica que **`failed` es terminal en OpenWA**) |
| `ventiq_admin_app/supabase/functions/_shared/wapi_client.ts` | Ampliado con `stopSession()`, `forceKill()`, `health()` / `healthReady()` / `healthLive()`, `registerWebhook()`, el **`config` de reconexión** (`reconnectBaseDelay`, `maxReconnectAttempts`) en `createSession()`, y soporte del header **`Idempotency-Key`** en los envíos |
| `ventiq_admin_app/supabase/functions/_shared/session_recovery.ts` | **Nuevo.** Escalera de recuperación con planificador **puro** (`planRecovery`) y ejecutor (`runRecovery`) con el cliente **inyectado** (testeable sin red y sin Deno; no conoce Supabase). Mapea estado crudo → acción: `ready`→nada; intermedios→`start`; `disconnected`→`stop→start`; `action_required`→`stop→start` **+ aviso de que hay que confirmar el modal a mano**; `failed`→`force-kill→start`; reintento agotado→`cooldown` y revisión manual. **Cooldown de 10 min y máximo 3 intentos** por sesión para no martillear la API; respeta `retryAfterSeconds`; tolera los 400 de "no había engine" en `/stop` y `/force-kill`; **verifica leyendo el estado real** en vez de fiarse del 2xx |
| `ventiq_admin_app/supabase/functions/_shared/session_store.ts` | **Nuevo.** Persistencia del estado de una sesión (`status`, `raw_status`, teléfono, QR, contabilidad de recuperación). Intenta el update completo y, si falla porque las columnas de la migración no existen todavía, **reintenta sólo con las columnas base**: el código se puede desplegar antes o después de la migración, sin ventana de caída |
| `ventiq_admin_app/supabase/functions/wapi-session-action/index.ts` | Reescrito para usar el **reinicio soportado** (stop→start) y añadir las acciones **`stop`**, **`force-kill`**, **`health`** y **`register-webhook`**. Persiste el status crudo y apaga/enciende `watchdog_enabled` según la acción |
| `ventiq_admin_app/supabase/functions/wapi-session-create/index.ts` | Registra el webhook por la **ruta documentada** (`POST /api/sessions/:sessionId/webhooks`) y **con `secret`**, en vez de dentro del body de creación; persiste el status crudo; envía el `config` de reconexión |
| `ventiq_admin_app/supabase/functions/wapi-session-status/index.ts` | Persiste el status **crudo** y devuelve `requiere_confirmacion_manual` cuando OpenWA reporta `action_required` |
| `ventiq_admin_app/supabase/functions/wapi-webhook/index.ts` | Maneja **`session.reconnect_loop`**, **`session.restriction`** y **`message.failed`**; corrige la lectura del campo **`qrCode`**; persiste el status crudo; y cuando llega un evento **sin firma** con `WAPI_WEBHOOK_SECRET` configurado responde 401 con un mensaje accionable (o lo acepta si `WAPI_WEBHOOK_ALLOW_UNSIGNED=true`). **La deduplicación por `X-OpenWA-Idempotency-Key` NO se implementó** (los handlers son idempotentes; las claves se registran en los logs) — ver §9.13 |
| `ventiq_admin_app/supabase/functions/wapi-send-products/index.ts` | **Verificación en vivo de la sesión** (en vez de la copia en BD), **recuperación acotada** ante 409/400 de "sesión no conectada" (recupera y reintenta el mismo mensaje; si no puede, deja la fila `pendiente` y corta el chunk), **conteo real de intentos** en `error_message` (fin del "tras 3 intentos" mentiroso) y **`Idempotency-Key`** en los envíos |
| `ventiq_admin_app/supabase/functions/wapi-cron-dispatch/index.ts` | Ya **no** se salta la difusión en silencio: verifica la sesión en vivo, intenta recuperarla y, si no puede, lo deja en `last_error_code` + log de error |
| `ventiq_admin_app/supabase/functions/wapi-list-sessions/index.ts` | Sincroniza en **lotes de 4** (antes: N `getSession` en paralelo contra una sola instancia de Chromium) y persiste el status crudo; si el sondeo falla no inventa estado |
| `ventiq_admin_app/supabase/functions/wapi-list-groups/index.ts` | Comprueba el estado **en vivo** antes de rechazar con 409 en vez de fiarse de la BD |
| `ventiq_admin_app/supabase/functions/wapi-session-health/index.ts` | **Nueva edge function watchdog**: revisa las sesiones, ejecuta la escalera de `session_recovery.ts` cuando hace falta y deja constancia del resultado. Invocable por pg_cron (service_role) o por la app (JWT, con `id_sesion`/`id_tienda`) |
| `ventiq_admin_app/supabase/migrations/20261017_wapi_session_recovery.sql` | **Nueva migración** con las columnas de recuperación (status crudo, última recuperación, intentos, último error, `watchdog_enabled`), `fn_wapi_session_watchdog()` (con advisory lock anti-solape), el **job de pg_cron cada 5 min** y `fn_wapi_session_recovery_report()` |
| `ventiq_admin_app/scripts/tests/wapi_shared.test.mjs` | **Nuevo.** 29 pruebas de la lógica pura (`normalizeWapiStatus`, predicados, `planRecovery`, `runRecovery` con cliente falso, `updateSessionState` con degradación) ejecutables **sin Deno ni red**: `node --experimental-strip-types ventiq_admin_app/scripts/tests/wapi_shared.test.mjs` |
| `ventiq_admin_app/scripts/sync_wapi_docs.mjs` | **Nuevo.** Sincroniza `docs_wapi/` con la doc oficial de OpenWA (`main` o un `--ref`) y escribe `docs_wapi/UPSTREAM.md` con la versión y la fecha. Re-ejecutable cuando salga una release. **Ya se ejecutó**: 41 archivos actualizados/añadidos, versión upstream detectada `0.25.0` |
| `ventiq_admin_app/docs_wapi/` (41 archivos) | **Resincronizada** con la doc de OpenWA `0.25.0` (antes: era `v0.11.1`). Incluye `31-session-lifecycle-design.md` y `examples/` |

**Inventario final:** los 16 archivos de la tabla están aplicados en el árbol de trabajo. Verifícalo con `git status` antes de desplegar y despliega el conjunto **completo**: `session_recovery.ts` depende de que `wapi_client.ts` exponga `stopSession`/`forceKill`, y `wapi-session-health` depende de `session_store.ts`.

---

## 8. Plan de despliegue y verificación

Ejecutar desde `ventiq_admin_app/`.

**Paso 0 — prerrequisito de seguridad.** Rotar la `service_role` key (ver §10.1) **antes** de desplegar; si no, se despliega con una credencial pública en el repo.

**Paso 1 — Aplicar la migración.**

```
npx supabase link --project-ref vsieeihstajlrdvpuooh
npx supabase db push
```

Alternativa sin CLI: pegar el contenido de `ventiq_admin_app/supabase/migrations/20261017_wapi_session_recovery.sql` en el SQL Editor del proyecto. Verificar después que las columnas de recuperación existen y que el job de watchdog quedó registrado en `cron.job`.

**Paso 2 — Configurar el secret del webhook.**

```
npx supabase secrets set WAPI_WEBHOOK_SECRET=<secreto-largo-aleatorio>
```

Debe ser **el mismo** que se registre en OpenWA en el paso 4. Sin él, `wapi-webhook` acepta cualquier POST (hallazgo 16).

**Paso 3 — Desplegar las edge functions.**

```
npx supabase functions deploy wapi-session-action
npx supabase functions deploy wapi-session-create
npx supabase functions deploy wapi-session-status
npx supabase functions deploy wapi-session-health
npx supabase functions deploy wapi-webhook
npx supabase functions deploy wapi-send-products
npx supabase functions deploy wapi-list-sessions
npx supabase functions deploy wapi-list-groups
npx supabase functions deploy wapi-cron-dispatch
```

`_shared/` se empaqueta automáticamente en cada despliegue: **no** se despliega como función. **No** usar `--no-verify-jwt`: la verificación de JWT en el gateway es parte de la mitigación del hallazgo 5.

**Paso 4 — Volver a registrar el webhook de la sesión 22.**

Llamar a `wapi-session-action` con `{"id_sesion": 22, "action": "register-webhook"}` para que registre `POST /api/sessions/3f394210-…/webhooks` con:

- `url`: `https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/wapi-webhook?tienda=177`
- `events`: `session.status`, `session.authenticated`, `session.disconnected`, **`session.reconnect_loop`**, **`session.restriction`**, `message.ack`, **`message.failed`**
- `secret`: el del paso 2
- `retryCount`: 3 (default)

Comprobar en los logs de `wapi-webhook` que llegan eventos reales (no 401).

**Paso 5 — Re-escanear el QR.**

La sesión 22 está en `SCAN_QR` con `phone_number` null: **nunca enlazó**. Abrir la pantalla de sesión en la app (o la acción `qr`) y escanear. Confirmar que `app_wapi_sesion.status` pasa a `CONNECTED` y que `phone_number` deja de ser null.

**Paso 6 — Medir la versión real de OpenWA.**

Invocar `wapi-session-action` con `{"id_sesion": 22, "action": "health"}`, que consulta `GET /api/health`. **Registrar la `version` devuelta.** Si es `< 0.25.0`, el bug de reconexión sigue activo en el servidor y hay que actualizarlo (§10.2). Si no devuelve `version`, la key no se está enviando o no es válida.

**Paso 7 — Vigilar el watchdog.**

Con `wapi-session-health` desplegada y su job de pg_cron activo, comprobar en los primeros ciclos que: (a) no recupera sesiones sanas; (b) respeta el cooldown de 10 min; (c) registra el status **crudo** en la BD (el diagnóstico que hoy no existe, hallazgo 9). Prueba sugerida: `{"action": "stop"}` sobre la sesión 22 y confirmar que el watchdog la devuelve a `CONNECTED` sin intervención humana, en el orden de magnitud del watchdog oficial (75–135 s) más el cooldown.

**Paso 8 — Reactivar la programación.**

Poner `app_wapi_programacion.activa = true` en la fila 13 y confirmar que `next_run_at` se recalcula (trigger, +1 día). Verificar la primera corrida de 19:30 `America/New_York` **de punta a punta**, no sólo que el cron devuelva 200: revisar que aparezcan filas `enviado` nuevas en `app_wapi_envio_log`, y que si el estado no es CONNECTED el resultado ya **no** sea un `skipped` silencioso.

**Paso 9 — Limpiar el backlog.**

Primero el informe (no borra nada):

```
node scripts/wapi_cleanup.mjs
```

Después, sólo las tareas pendientes de la tienda 177 y la retención:

```
node scripts/wapi_cleanup.mjs --pendientes --tienda 177 --apply
node scripts/wapi_cleanup.mjs --logs --older-than 30 --apply
```

La service_role key **por variable de entorno**, nunca en el repo.

**Paso 10 — Criterios de éxito.**

- `app_wapi_sesion.status = CONNECTED` con `phone_number` no nulo y `last_status_at` fresco.
- Los eventos `session.*` llegan al webhook (sin 401) y el estado en BD se actualiza **sin** que nadie abra la app.
- Un `stop` forzado de prueba se recupera **automáticamente**.
- No aparecen nuevos `HTTP_409`/`HTTP_400` de "sesión no conectada" en envíos masivos.
- La corrida diaria produce filas `enviado`, no `skipped`.
- Ningún `error_message` vuelve a decir "tras 3 intentos" cuando hubo menos.

---

## 9. Riesgos y cosas NO verificadas

1. **Versión del servidor OpenWA: DESCONOCIDA.** No se tiene URL ni API key desde este entorno. Es la incógnita más importante: si corre `< 0.25.0`, el bug de reconexión sigue activo y **ninguna edge function lo arregla del todo**. Se mide en §8 paso 6.
2. **Si su build honra el `config` de reconexión por sesión: NO VERIFICADO.** Es la palanca que ahora se envía en `createSession()`, pero no se ha comprobado contra un servidor real. Además, **las sesiones ya creadas no lo tendrán** (el `config` sólo viaja en la creación), así que la sesión 22 podría necesitar recrearse.
3. **Los nombres exactos de las doce rutas con `Idempotency-Key`: NO VERIFICADOS.** La documentación dice "doce rutas de envío a un destinatario", pero no se ha confirmado la lista exacta ni que `send-image` esté entre ellas. Si no lo está, la `Idempotency-Key` que mandamos en esa ruta puede ser ignorada (sin efecto) o rechazada.
4. **El código Deno NO se ha verificado con `deno check`** (no hay `deno` ni `supabase` CLI, y `npx` falla con `EPERM` en el sandbox). Mitigación aplicada: los **13 archivos** pasan el *type stripping* de Node 22 (`node --experimental-strip-types --check`) y las **29 pruebas** de la lógica pura están en verde (`ventiq_admin_app/scripts/tests/wapi_shared.test.mjs`). Lo que sigue sin validar son los **tipos** y el comportamiento en el runtime de Deno (imports `https://esm.sh/...`, `EdgeRuntime.waitUntil`, `Deno.env`). Es el riesgo más alto del despliegue: hazlo en una ventana con margen y revisa los logs de las primeras invocaciones.
5. **El servicio OpenWA puede estar detrás de una IP/puerto que cambió.** `WAPI_BASE_URL` (ejemplo en el código: `http://3.238.37.3:2786`) no se ha podido comprobar; puede apuntar a un host muerto o a una versión distinta de la documentada.
6. **Periodicidad exacta de `session.reconnect_loop`: NO VERIFICADA en código.** La documentación habla de "cada 5.º intento consecutivo"; el intervalo temporal resultante depende del `reconnectBaseDelay` efectivo.
7. **Modo del gateway de Edge Functions: NO VERIFICADO.** Si el proyecto corre con `--no-verify-jwt`, el hallazgo 5 pasa de **Medio** a **Crítico** y `isServiceRoleCall()` es un bypass de autorización real.
8. **Comportamiento del gateway al re-registrar el webhook: NO VERIFICADO.** No se sabe si `POST /api/sessions/:id/webhooks` reemplaza el webhook del body de creación o **añade uno segundo** (lo que produciría entregas duplicadas). Hay que comprobarlo en el servidor tras §8 paso 4; si se duplica, hay que borrar el viejo por la API.
9. **El fix de 0.25.0 no se ha leído en el código fuente**, sólo en el CHANGELOG: se asume que la cita describe el bug, pero no se ha rastreado el commit.
10. **No se ha probado con tráfico real** ningún flujo nuevo: recuperación, watchdog, idempotencia de webhook, ni el conteo real de intentos.
11. **Dependencia de la rotación de clave:** si se rota la `service_role` key antes de actualizar el secreto `wapi_service_role_key` en **vault** (`20260527_wapi_dispatch_vault.sql`), `fn_wapi_dispatch_diario` dejará de poder invocar `wapi-cron-dispatch` y la difusión diaria se romperá por otra vía. El orden importa.
12. **El informe se redactó mientras el conjunto de cambios se consolidaba** en el árbol de trabajo; el inventario final está en §7. Verifica con `git status` antes de desplegar.
13. **Deduplicación de webhooks: NO implementada.** OpenWA documenta que los workers de su cola re-ejecutan jobs al reiniciar y que los barridos del *outbox* pueden **reentregar el mismo evento con la misma `X-OpenWA-Idempotency-Key`**. Los handlers actuales escriben estado absoluto (no incrementan contadores), así que una reentrega no corrompe datos; las claves `X-OpenWA-Idempotency-Key` y `X-OpenWA-Delivery-Id` quedan en los logs para poder rastrearla. Si en el futuro se añade un efecto acumulativo (contadores, cargos, avisos), habrá que añadir una tabla de deduplicación con índice único.
14. **La escalera de recuperación podría pelear con el watchdog interno de OpenWA.** El gateway ya sondea cada 60 s y trata dos fallos consecutivos como desconexión; nuestro cooldown de 10 min es deliberadamente más lento para no reiniciar una sesión que el gateway está a punto de recuperar solo. Si en producción se observa que una sesión tarda en volver, revisar el orden de los tiempos antes de bajar el cooldown.

---

## 10. Recomendaciones fuera de las edge functions

### 10.1 Rotar la `service_role` key commiteada (prioridad máxima)

El JWT de `service_role` del proyecto `vsieeihstajlrdvpuooh`, **con `exp` en 2035**, está **en claro** en `ventiq_admin_app/supabase/migrations/20260527_wapi_dispatch_vault.sql:35`. Cualquiera con acceso al repo tiene control total sobre la base de datos (bypassa RLS).

1. Rotar la clave en el dashboard del proyecto (Settings → API).
2. Actualizar el secreto `wapi_service_role_key` en **vault** y el `Authorization` del job `wapi_dispatch_diario`.
3. Actualizar `SUPABASE_SERVICE_ROLE_KEY` en los secrets de las edge functions y en los entornos locales.
4. **Purgar el secreto del historial de git** (p. ej. `git filter-repo` o BFG): borrar la línea del archivo **no** es suficiente, el valor sigue en los commits.
5. Revisar si hubo uso anómalo de esa clave desde que se commiteó.

### 10.2 Actualizar OpenWA a v0.25.0

Es el cambio con más probabilidad de eliminar el síntoma de raíz (contiene el fix de reconexión y la idempotencia de envío).

- **Backup previo obligatorio** de `data/sessions` **y** `main.sqlite`.
- No hacer **rollback de una versión mayor de Chrome**: borra el IndexedDB del perfil y **todas las sesiones vuelven a QR**.
- Tras actualizar, volver a medir `GET /api/health` (§8 paso 6) y **verificar que las sesiones siguen `CONNECTED`**; si volvieron a QR, hay que re-escanear (es el motivo del backup).

### 10.3 Recursos del host

- `OPENWA_MEM_LIMIT`: subir de **2g** a **4g** (whatsapp-web.js usa ≈300–500 MB por sesión en Chromium).
- `OPENWA_PIDS_LIMIT`: subir de **2048** a **4096**.
- **`replicas: 1` obligatorio**: *"Run exactly one API instance per session-data volume"*. Dos instancias sobre el mismo volumen corrompen el estado.

### 10.4 El modal "What's new"

Añadir la **etiqueta en español** del modal a `WWEBJS_ONBOARDING_CONTINUE_LABELS` (junto a las variantes en inglés ya soportadas). Sin esto, `action_required` reaparecerá: la sesión enlaza y se cae a `disconnected` con reason `LOGOUT` a los pocos minutos. Es el candidato número uno a "se muere solo y hay que reiniciar" en un despliegue con UI en español.

### 10.5 Motor

Valorar **`ENGINE_TYPE=baileys`** si la RAM es el cuello de botella: usa mucha menos memoria por sesión que `whatsapp-web.js` (un Chromium por sesión). **Matiz importante:** `whatsapp-web.js` es el único cuyo *reconnect* gobierna el gateway; con `baileys` la dinámica de reconexión cambia, así que la escalera de `session_recovery.ts` habría que revalidarla. El motor se elige **una vez por despliegue** y cambiarlo exige reiniciar el servicio.

### 10.6 Pacing de envío

Activar **`SEND_PACING_ENABLED`** con `SEND_PACING_WARMUP_SCHEDULE`, `SEND_PACING_COLD_DAILY_CAP`, `SEND_PACING_BREAKER_THRESHOLD` y `SEND_PACING_BREAKER_COOLDOWN_MS`. Beneficio doble: reduce el riesgo de restricción/baneo de la cuenta y convierte los `HTTP_500`/`HTTP_409` en **429 con `retryAfterSeconds`**, que nuestro cliente **ya sabe respetar** (`wapi-send-products:1273-1296`).

### 10.7 Arranque automático de sesiones

Activar **`AUTO_START_SESSIONS`** para que las sesiones registradas se levanten solas tras un reinicio del gateway, en vez de quedarse inertes esperando un toque humano.

### 10.8 Observabilidad y alertas

- El watchdog **debe alertar** cuando agota los 3 intentos de recuperación (`planRecovery` → `cooldown`): hoy el modo de fallo del sistema es el **silencio** (cron `succeeded`, difusión muerta durante semanas).
- Persistir el **status crudo** de OpenWA (ya contemplado en la migración nueva) y revisarlo antes de culpar al código.
- Vigilar que `app_wapi_programacion.next_run_at` no quede en `null` ni `last_run_at` se estanque.

---

## Fuentes

- Repo OpenWA: <https://github.com/rmyndharis/OpenWA>
- Troubleshooting / FAQ: <https://raw.githubusercontent.com/rmyndharis/OpenWA/main/docs/12-troubleshooting-faq.md>
- Runbooks operacionales: <https://raw.githubusercontent.com/rmyndharis/OpenWA/main/docs/11-operational-runbooks.md>
- Diseño del ciclo de vida de sesión: <https://raw.githubusercontent.com/rmyndharis/OpenWA/main/docs/31-session-lifecycle-design.md>
- CHANGELOG: <https://raw.githubusercontent.com/rmyndharis/OpenWA/main/CHANGELOG.md>

Documentación **local** (desactualizada, era v0.11.1): `ventiq_admin_app/docs_wapi/`.