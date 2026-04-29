# Push Notifications — Muevete

## Architecture

Two parallel notification channels ensure delivery even when the app is suspended:

1. **Supabase Realtime (WebSocket)** — in-app + background service notifications. Works when the app is in foreground or the background service is alive.
2. **Pushy.me (Push)** — server-side push via Supabase Edge Function. Works even when the app is fully killed.

Duplicate notifications may occur; this is acceptable and expected.

## Pushy.me Setup

- **App ID:** `69a5cf6e17a786c0470bc2d1`
- **App Name:** `inventtia_muevete`
- **Dashboard:** https://dashboard.pushy.me/

### API Key

The Pushy Secret API Key is used in the Supabase Edge Function to send pushes. It is stored directly in `docs/edge-functions/send-push-notification.ts`.

## Database: `muevete.push_tokens`

Run `docs/migrations/push_tokens.sql` in Supabase SQL Editor to create the table.

| Column | Type | Description |
|--------|------|-------------|
| id | bigint | Auto-increment PK |
| user_uuid | uuid | FK to auth.users |
| device_token | text | Pushy device token |
| platform | text | 'android' or 'ios' |
| created_at | timestamptz | Auto |
| updated_at | timestamptz | Auto |

Unique constraint on `(user_uuid, device_token)`.

## Supabase Edge Function

File: `docs/edge-functions/send-push-notification.ts`

### Deploy

```bash
supabase functions deploy send-push-notification
```

### Database Webhooks

Create 3 database webhooks in Supabase Dashboard → Database → Webhooks:

1. **notificaciones_push** — Table: `muevete.notificaciones`, Event: INSERT
2. **solicitudes_push** — Table: `muevete.solicitudes_transporte`, Event: INSERT
3. **ofertas_push** — Table: `muevete.ofertas_chofer`, Event: INSERT

All 3 should call the `send-push-notification` edge function with payload:
```json
{
  "type": "INSERT",
  "table": "<table_name>",
  "record": { ...new_row... }
}
```

## Background Service Improvements

- **Heartbeat** (every 5 min): re-subscribes Supabase Realtime channels if they dropped
- **Polling fallback** (every 60s): queries for new solicitudes/ofertas since last poll as a safety net

## Testing

1. Login on a device → check `push_tokens` table for the device token
2. Minimize the app, wait 30s for WebSocket to close
3. From another account, create a solicitud → driver should receive a push notification
4. From a driver, create an oferta → client should receive a push notification
5. Check `supabase functions logs send-push-notification` for edge function output
