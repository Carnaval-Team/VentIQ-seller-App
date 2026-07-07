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
| `wapi-send-products`   | Flutter (JWT) | **Envío manual**: encola productos en bulk con jitter anti-ban |
| `wapi-cron-dispatch`   | pg_cron (service_role) | Procesa programación diaria pendiente |
| `wapi-webhook`         | API WAPI (HMAC) | Recibe eventos `session.status`, `session.qr`, `message.ack` |

## Anti-ban / Buenas prácticas

Todas las difusiones (manuales y automáticas) usan el endpoint **bulk** de WAPI
con `delayBetweenMessages: 30s–90s` por defecto y `randomizeDelay: true`. Esto:

- Inserta jitter aleatorio (±30%) entre mensajes.
- Distribuye los envíos para evitar patrones detectables.
- Procesa el batch en el **servidor remoto** de WAPI → el teléfono del usuario
  **no necesita estar encendido**: la sesión vive en el servidor.

Los rangos `delay_min_seconds` y `delay_max_seconds` se pueden personalizar por
programación (tabla `app_wapi_programacion`).

## Secrets a configurar

```bash
supabase secrets set \
  WAPI_BASE_URL=http://3.238.37.3:2786 \
  WAPI_API_KEY=<API_KEY> \
  WAPI_WEBHOOK_SECRET=<secret_compartido_con_la_api>
```

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
supabase functions deploy wapi-session-create
supabase functions deploy wapi-session-status
supabase functions deploy wapi-session-action
supabase functions deploy wapi-list-sessions
supabase functions deploy wapi-list-groups
supabase functions deploy wapi-send-products
supabase functions deploy wapi-cron-dispatch
supabase functions deploy wapi-webhook
```
