# Edge Functions — WAPI Notifications

Conjunto de Edge Functions que conectan VentIQ con la API WAPI (**OpenWA**)
externa para permitir difusión de productos por WhatsApp.

> **Antes de tocar nada, lee
> [`ventiq_admin_app/docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md`](../../docs/AUDITORIA_WAPI_EDGE_FUNCTIONS.md)**:
> explica por qué el bot se caía de forma aleatoria y qué se cambió.

## Funciones

| Función | Caller | Propósito |
|---|---|---|
| `wapi-session-create`  | Flutter (JWT) | Crea bot en OpenWA (con `config` de reconexión) + registra el webhook **con secret** + persiste en `app_wapi_sesion` |
| `wapi-session-status`  | Flutter (JWT) | Estado actual + QR si está en `SCAN_QR`. Persiste también el status **crudo** |
| `wapi-session-action`  | Flutter (JWT) | `qr` / `restart` / `recover` / `stop` / `force-kill` / `logout` / `delete` / `health` / `register-webhook` |
| `wapi-session-health`  | pg_cron (service_role) o Flutter (JWT) | **Watchdog**: sondea las sesiones, detecta caídas y las recupera (stop→start / force-kill→start) |
| `wapi-list-sessions`   | Flutter (JWT) | Sincroniza estado con OpenWA (en lotes) y devuelve la lista |
| `wapi-list-groups`     | Flutter (JWT) | Lista grupos WhatsApp de la sesión |
| `wapi-send-products`   | Flutter (JWT) | **Envío manual**: despacha productos uno a uno con jitter anti-ban, encadenándose por chunks y **recuperando la sesión si se cae** |
| `wapi-cron-dispatch`   | pg_cron (service_role) | Resuelve la programación diaria, verifica la sesión **en vivo** y **delega** en `wapi-send-products` |
| `wapi-webhook`         | OpenWA (HMAC) | Recibe `session.status` / `authenticated` / `disconnected` / `reconnect_loop` / `restriction` / `qr` / `message.ack` / `message.failed` |

### Módulos compartidos (`_shared/`)

| Módulo | Qué contiene |
|---|---|
| `wapi_client.ts` | Cliente HTTP de OpenWA. Incluye `stopSession`, `forceKill`, `health`/`healthReady`/`healthLive`, `registerWebhook`, `config` de reconexión y `Idempotency-Key` |
| `status.ts` | Mapeo de los estados del cable de OpenWA → los 6 canónicos de la tabla |
| `session_recovery.ts` | Escalera de recuperación: planificador puro (`planRecovery`) + ejecutor (`runRecovery`) |
| `session_store.ts` | Persistencia del estado de sesión, tolerante a que la migración de columnas no esté aplicada |
| `auth.ts` / `cors.ts` / `invoke.ts` | Auth (JWT + service_role), CORS y encadenado entre funciones |

## Anti-ban / Buenas prácticas

Las difusiones (manuales y automáticas) **no** usan el endpoint bulk de OpenWA:
bulk colapsa los `chatId` repetidos, y enviar N productos al mismo grupo son
justamente N mensajes al mismo `chatId`. En su lugar `wapi-send-products`
despacha `send-image` / `send-text` de a uno:

- **En serie por destino** (pausa de 1,5 s entre grupos): la sesión OpenWA es una
  única instancia de Puppeteer/Chromium y se satura si se le paralelizan los
  envíos.
- **Jitter aleatorio entre productos** en el rango `delay_min_seconds` –
  `delay_max_seconds` (5–10 s por defecto).
- **Reintentos** con backoff exponencial + jitter, respetando el
  `retryAfterSeconds` que pide el server en sus 429 (`SEND_PACING_LIMITED`).
- **Idempotencia**: cada envío viaja con `Idempotency-Key` derivada de su fila de
  log, así un reintento tras un `TIMEOUT` no duplica el mensaje (OpenWA ≥ 0.25.0;
  en builds anteriores el header se ignora sin daño).
- El envío ocurre en el **servidor remoto** de OpenWA → el teléfono del usuario
  **no necesita estar encendido**: la sesión vive en el servidor.

Los rangos `delay_min_seconds` y `delay_max_seconds` se pueden personalizar por
programación (tabla `app_wapi_programacion`).

## Sesiones: caídas y recuperación automática

OpenWA pierde la sesión de forma aleatoria (OOM de Chromium, bucle de
reconexión, modal *"What's new"* sin confirmar, watchdog interno). Cuando eso
pasa, **todo envío falla** con `HTTP_409 Session is not connected` o
`HTTP_400 Session '…' is not active` y hace falta reiniciar a mano. Para que no
haga falta:

1. **Watchdog** — `fn_wapi_session_watchdog()` (pg_cron, cada 5 min) llama a
   `wapi-session-health`, que sondea `GET /api/sessions/:id`, persiste el estado
   y, si la sesión está caída, aplica la escalera:
   - `disconnected` → `POST /stop` → `POST /start`
   - `action_required` → lo mismo **+ hay que confirmar el modal "What's new"
     en el teléfono una vez** (la sesión no se recupera sola de esto)
   - `failed` (terminal en OpenWA) → `POST /force-kill` → `POST /start`
   - Luego **verifica** leyendo el estado real, no se fía del 2xx.
   - Límites: `watchdog_enabled = true`, cooldown de 10 min, 3 intentos, y
     **no toca sesiones sin vincular que esperan QR** (reiniciarlas invalidaría
     el QR).
2. **Sender** — si `wapi-send-products` recibe un error de "sesión no
   conectada", recupera la sesión y reintenta el mismo mensaje. Si no lo
   consigue, **no** marca la fila como `fallido`: la deja `pendiente` y corta el
   chunk para poder reanudar.
3. **Cron** — `wapi-cron-dispatch` ya no se salta la difusión en silencio:
   verifica la sesión en vivo, intenta recuperarla y, si no puede, deja
   constancia en `app_wapi_sesion.last_error_code` y en los logs.

> `restart` **no** es una ruta de OpenWA: su runbook dice *"there is no /restart
> route"*. Aquí está implementado como `stop` → `start`.

## Chunks y presupuesto de worker

Un worker de Edge Functions muere al llegar al techo de wall-clock (~400 s), y
un envío de 70 productos a 4 grupos son 280 mensajes: no cabe. `dispatchProducts`
lleva su propio reloj (`WORKER_BUDGET_MS = 270_000`) y, antes de arrancar cada
producto, comprueba si aún cabe usando el peor producto observado hasta el
momento. Cuando no cabe, corta y **re-invoca `wapi-send-products`** con los
productos que faltan, que estrena un worker con 400 s frescos.

Reglas que conviene no romper al tocar esto:

- La continuación se encola **antes** de mandar el resumen. Si se hiciera al
  revés, un worker que muera mientras escribe el resumen se lleva por delante
  toda la cola pendiente.
- Si no se pudo encolar la continuación, los productos restantes se registran
  como `pendiente` en `app_wapi_envio_log` para que la UI pueda ofrecer
  "reanudar" (`resume_log_ids`).
- El resumen final se manda con `summary_product_ids` = catálogo **completo**,
  no el subconjunto del último chunk; si al último chunk no le queda worker,
  se delega con `summary_only: true`.
- `wapi-cron-dispatch` **no** debe volver a ejecutar el envío dentro de su
  propio worker: al ser invocado por pg_cron ya arrastra tiempo consumido y el
  envío quedaría atado a un worker reciclable.
- El conteo de intentos que se escribe en `error_message` es el **real**, no
  `RETRY_MAX_ATTEMPTS`: mentir ahí entorpece el diagnóstico.

## Secrets a configurar

```bash
npx supabase secrets set \
  WAPI_BASE_URL=<http://IP:PUERTO_DEL_SERVIDOR_WAPI> \
  WAPI_API_KEY=<API_KEY> \
  WAPI_WEBHOOK_SECRET=<secret_compartido_con_la_api>
```

Opcionales:

| Secret | Default | Para qué |
|---|---|---|
| `WAPI_RECONNECT_BASE_DELAY_MS` | `5000` | `config.reconnectBaseDelay` de cada sesión nueva |
| `WAPI_MAX_RECONNECT_ATTEMPTS` | `10` | `config.maxReconnectAttempts` (`unset` = ilimitado con tope de 5 min) |
| `WAPI_WEBHOOK_ALLOW_UNSIGNED` | `false` | Aceptar webhooks sin firma (sólo para diagnóstico) |

> Nunca escribas estos valores en el código ni los commitees: viven sólo como
> secrets del proyecto. Si el servidor OpenWA cambia de IP/puerto o rotas la
> API key, basta con volver a lanzar `secrets set` y **redesplegar** las
> funciones que llaman a OpenWA (`wapi-*`) — el módulo `_shared/wapi_client.ts`
> lee las env vars al cargar.

`SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` ya están
inyectados automáticamente por la plataforma.

### Webhook: registrar con secret

OpenWA sólo firma (`X-OpenWA-Signature`) los webhooks que tienen `secret`. El
secret es *write-only*: la API nunca lo devuelve. Las sesiones creadas antes de
este cambio se registraron **sin** secret, así que sus entregas se rechazaban
con 401 y la BD nunca se enteraba de las caídas. Para arreglar una sesión ya
existente:

```bash
curl -X POST "$SUPABASE_URL/functions/v1/wapi-session-action" \
  -H "Authorization: Bearer <JWT_DEL_GERENTE>" \
  -H "Content-Type: application/json" \
  -d '{"id_sesion": 22, "action": "register-webhook"}'
```

## Migraciones relacionadas

```bash
npx supabase db push      # o aplicar a mano en el SQL Editor
```

| Migración | Qué hace |
|---|---|
| `20260525_wapi_notifications.sql` | Tablas + RLS + cron del dispatcher |
| `20260527_wapi_dispatch_vault.sql` | Secretos del dispatcher en Vault |
| `20260602_wapi_dispatch_debug.sql` | `fn_wapi_dispatch_debug` / `fn_wapi_force_dispatch` |
| `20261017_wapi_session_recovery.sql` | Columnas de recuperación + `fn_wapi_session_watchdog` + cron cada 5 min |
| `sql/wapi_cleanup.sql` | `fn_wapi_backlog_report` / `fn_wapi_purge_envio_log` / `fn_wapi_purge_infra_logs` |

## GUCs Postgres (para el cron)

Ya no hacen falta si usas la ruta de Vault (que es lo que está en producción).
Se documentan por si algún entorno nuevo arranca del SQL original:

```sql
ALTER DATABASE postgres SET app.supabase_url     = 'https://<proj>.supabase.co';
ALTER DATABASE postgres SET app.service_role_key = '<service_role_key>';
SELECT pg_reload_conf();
```

## Deploy

```bash
cd ventiq_admin_app
npx supabase functions deploy wapi-session-create
npx supabase functions deploy wapi-session-status
npx supabase functions deploy wapi-session-action
npx supabase functions deploy wapi-session-health
npx supabase functions deploy wapi-list-sessions
npx supabase functions deploy wapi-list-groups
npx supabase functions deploy wapi-send-products
npx supabase functions deploy wapi-cron-dispatch
npx supabase functions deploy wapi-webhook
```

## Pruebas

Las partes puras (mapeo de estados, escalera de recuperación, persistencia
tolerante a migraciones) se prueban sin Deno ni red:

```bash
node --experimental-strip-types ventiq_admin_app/scripts/tests/wapi_shared.test.mjs
```

## Mantenimiento de la bitácora

```bash
# Informe (no borra nada)
node ventiq_admin_app/scripts/wapi_cleanup.mjs

# Borrar las tareas pendientes (lo que la app muestra como "interrumpida")
node ventiq_admin_app/scripts/wapi_cleanup.mjs --pendientes --apply

# Vaciar toda la bitácora + los QR guardados
node ventiq_admin_app/scripts/wapi_cleanup.mjs --all --apply
```