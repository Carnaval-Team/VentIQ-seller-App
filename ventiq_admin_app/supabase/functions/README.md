# Edge Functions — WAPI Notifications

Conjunto de Edge Functions que conectan VentIQ con la API WAPI (OpenWA) externa
para permitir difusión de productos por WhatsApp.

## Funciones

| Función | Caller | Propósito |
|---|---|---|
| `wapi-session-create`  | Flutter (JWT) | Crea bot en API WAPI + persiste en `app_wapi_sesion` |
| `wapi-session-status`  | Flutter (JWT) | Estado actual + QR si está en SCAN_QR |
| `wapi-session-action`  | Flutter (JWT) | `logout` / `restart` / `delete` |
| `wapi-list-sessions`   | Flutter (JWT) | Sincroniza estado con API WAPI y devuelve lista |
| `wapi-list-groups`     | Flutter (JWT) | Lista grupos WhatsApp de la sesión |
| `wapi-send-products`   | Flutter (JWT) | **Envío manual**: despacha productos uno a uno con jitter anti-ban, encadenándose por chunks |
| `wapi-cron-dispatch`   | pg_cron (service_role) | Resuelve la programación diaria y **delega** en `wapi-send-products` |
| `wapi-webhook`         | API WAPI (HMAC) | Recibe eventos `session.status`, `session.qr`, `message.ack` |

## Anti-ban / Buenas prácticas

Las difusiones (manuales y automáticas) **no** usan el endpoint bulk de WAPI:
bulk colapsa los `chatId` repetidos, y enviar N productos al mismo grupo son
justamente N mensajes al mismo `chatId`. En su lugar `wapi-send-products`
despacha `send-image` / `send-text` de a uno:

- **En serie por destino** (pausa de 1,5 s entre grupos): la sesión WAPI es una
  única instancia de Puppeteer y se satura si se le paralelizan los envíos.
- **Jitter aleatorio entre productos** en el rango `delay_min_seconds` –
  `delay_max_seconds` (5–10 s por defecto).
- **Reintentos** con backoff exponencial + jitter, respetando el
  `retryAfterSeconds` que pide el server en sus 429 (`SEND_PACING_LIMITED`).
- El envío ocurre en el **servidor remoto** de WAPI → el teléfono del usuario
  **no necesita estar encendido**: la sesión vive en el servidor.

Los rangos `delay_min_seconds` y `delay_max_seconds` se pueden personalizar por
programación (tabla `app_wapi_programacion`).

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

## Secrets a configurar

```bash
npx supabase secrets set \
  WAPI_BASE_URL=<http://IP:PUERTO_DEL_SERVIDOR_WAPI> \
  WAPI_API_KEY=<API_KEY> \
  WAPI_WEBHOOK_SECRET=<secret_compartido_con_la_api>
```

> Nunca escribas estos valores en el código ni los commitees: viven sólo como
> secrets del proyecto. Si el servidor WAPI cambia de IP/puerto o rotas la
> API key, basta con volver a lanzar `secrets set` y **redesplegar** las
> funciones que llaman a WAPI (`wapi-*`) — el módulo `_shared/wapi_client.ts`
> lee las env vars al cargar.

`SUPABASE_URL`, `SUPABASE_ANON_KEY` y `SUPABASE_SERVICE_ROLE_KEY` ya están
inyectados automáticamente por la plataforma.

## GUCs Postgres (para el cron)

Una sola vez por proyecto (substituir valores):

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
npx supabase functions deploy wapi-list-sessions
npx supabase functions deploy wapi-list-groups
npx supabase functions deploy wapi-send-products
npx supabase functions deploy wapi-cron-dispatch
npx supabase functions deploy wapi-webhook
```
