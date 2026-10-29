# Despliegue WAPI — 2026-10-28 (guía consolidada)

**Proyecto:** `vsieeihstajlrdvpuooh` (VentiQ, producción) · **Repo:** `ventiq_admin_app/`

Esta es la guía **única** para aplicar los 3 cambios de esta sesión. Los detalles
largos de cada frente están en `deploy_parte_backend-fix.md` (fix del envío +
`solo_disponibles`) y `deploy_parte_backend-oos.md` (avisos de agotado);
este documento es el camino corto y el orden correcto.

> **Por qué lo aplicas tú:** en esta sesión los MCP de Supabase apuntan a
> producción en **solo lectura** (`supabase_read_only_user`,
> `default_transaction_read_only=on`) y el otro servidor MCP apunta a **otro
> proyecto** (`qhprswhhfasrikhawjoz`). No hay CLI ni token en la máquina, así
> que nada de esto se ha aplicado ni desplegado todavía. Se verificó que
> producción sigue con `wapi-send-products` **v31**, `wapi-cron-dispatch`
> **v24**, sin `wapi-notify-agotado`, sin `solo_disponibles` y sin tablas
> `app_wapi_agotado_*`.

---

## 0. TL;DR (4 pasos, ~15 min)

```powershell
cd C:\Users\cesar\Documents\VentIQ-seller-App\ventiq_admin_app
npx supabase login                     # una vez; abre el navegador
```

1. **SQL 1/2** — pegar `supabase/migrations/20261028_wapi_programacion_solo_disponibles.sql` en el SQL Editor.
2. **SQL 2/2** — pegar `supabase/migrations/20261028_wapi_agotado_notificaciones.sql` en el SQL Editor.
3. **Deploy** de las 3 funciones (ver §3; **respeta el `verify_jwt` de cada una**).
4. **Verificar** (§4) → dry-run y advisors.

Después: **recompilar la app** (§5) y **reintentar la tanda fallida** (§6).

---

## 1. Prerrequisitos

* Node 18+ con `npx` (o `npm i -g supabase`).
* `npx supabase login` (abre el navegador; no hace falta PAT).
* Comprobar: `npx supabase projects list` lista `vsieeihstajlrdvpuooh`.
* Todos los comandos se lanzan **desde `ventiq_admin_app/`** (ahí están
  `supabase/config.toml` y `supabase/functions/`).
* Si `npx` falla con `EPERM` de caché: `$env:npm_config_cache = "$PWD\.npm-cache"`.

> ⚠️ **NO ejecutes `supabase db push`.** El historial remoto de migraciones no
> coincide con los ficheros locales y un push intentaría aplicar ~10 migraciones
> antiguas. Aplica **solo** los dos ficheros nuevos (§2.1 y §2.2).

---

## 2. Aplicar las dos migraciones (SQL)

Las dos son **idempotentes** (`IF NOT EXISTS`, `CREATE OR REPLACE`,
`DROP ... IF EXISTS`): se pueden re-ejecutar sin daño.

### 2.1 `solo_disponibles` (filtro de stock en la difusión programada)

Dashboard → SQL Editor → New query → pegar
`supabase/migrations/20261028_wapi_programacion_solo_disponibles.sql` → Run.

Verificación (debe devolver **1 fila**: `boolean | NO | false`):

```sql
select column_name, data_type, is_nullable, column_default
  from information_schema.columns
 where table_schema = 'public'
   and table_name   = 'app_wapi_programacion'
   and column_name  = 'solo_disponibles';
```

### 2.2 Avisos de "producto agotado"

Igual, con `supabase/migrations/20261028_wapi_agotado_notificaciones.sql`.

Verificación (4 tablas, 4 policies, el trigger nuevo junto a los 3 viejos):

```sql
select table_name from information_schema.tables
 where table_schema='public' and table_name like 'app_wapi_agotado%' order by 1;

select tgname from pg_trigger
 where tgrelid='public.app_dat_inventario_productos'::regclass and not tgisinternal
 order by 1;
-- esperado: trg_notificar_producto_agotado, trg_notificar_producto_disponible,
--           trg_sincronizar_stock_inventario y trg_wapi_agotado_notificar

-- ACL: NO debe aparecer anon / authenticated en las funciones nuevas
select p.proname, coalesce(array_to_string(p.proacl,' | '),'(owner)') as acl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'fn_wapi_agotado%' order by 1;
```

> `REVOKE ... FROM PUBLIC` **no basta** en Supabase: `ALTER DEFAULT PRIVILEGES`
> concede `EXECUTE` a `anon`/`authenticated` al crear cada función. Las
> migraciones ya revocan explícitamente de esos dos roles. Si la consulta
> anterior los muestra, repite el bloque de `REVOKE` del fichero.

### 2.3 Alternativa por CLI (opcional)

Sólo si tu CLI es **≥ 2.79** y tiene el subcomando `db query`. Si no existe, usa
el SQL Editor (§2.1/§2.2) o `psql`; el SQL es el mismo fichero.

```powershell
npx supabase db query --file .\supabase\migrations\20261028_wapi_programacion_solo_disponibles.sql --project-ref vsieeihstajlrdvpuooh
npx supabase db query --file .\supabase\migrations\20261028_wapi_agotado_notificaciones.sql --project-ref vsieeihstajlrdvpuooh
```

---

## 3. Desplegar las 3 edge functions

```powershell
cd C:\Users\cesar\Documents\VentIQ-seller-App\ventiq_admin_app
npx supabase functions deploy wapi-send-products  --project-ref vsieeihstajlrdvpuooh
npx supabase functions deploy wapi-cron-dispatch  --project-ref vsieeihstajlrdvpuooh
npx supabase functions deploy wapi-notify-agotado --project-ref vsieeihstajlrdvpuooh
```

**`verify_jwt` por función — no lo cambies:**

| Función | `verify_jwt` | Por qué |
|---|---|---|
| `wapi-send-products` | **false** | ya estaba así; la invocan los otros workers en segundo plano |
| `wapi-cron-dispatch` | **true** | la llama `fn_wapi_dispatch_diario` (pg_cron + pg_net) con la service key del Vault |
| `wapi-notify-agotado` | **true** | **no puede ir en false**: `_shared/auth.ts:isServiceRoleCall()` acepta `role=service_role` **sin verificar la firma**, así que con `false` cualquier token forjado podría disparar WhatsApps a tus grupos |

Los valores están fijados en `supabase/config.toml`, así que un deploy **por
nombre** los respeta. **Nunca** hagas `npx supabase functions deploy` sin nombre:
reescribe el `verify_jwt` de **todas** las funciones del proyecto y hoy hay
**9** con `false` (`wapi-send-products`, `wapi-webhook`, 4 de Stripe,
`stripe-cancel-order` y las 2 de `auth-recovery`), así que las rompería.

Comprobación:

```powershell
npx supabase functions list --project-ref vsieeihstajlrdvpuooh
```

Debe subir la versión de `wapi-send-products` (v31 → v32), la de
`wapi-cron-dispatch` (v24 → v25) y aparecer `wapi-notify-agotado` **ACTIVE**.

> El orden migración → deploy es el recomendado, pero **ya no es crítico**: si
> desplegaras `wapi-cron-dispatch` antes de la migración, la función detecta que
> la columna no existe, reintenta el `select` sin ella, asume
> `solo_disponibles = false` y **avisa en los logs** en vez de saltarse la
> difusión en silencio.

---

## 4. Verificar

### 4.1 El fix del "producto no encontrado" (dry-run, sin enviar nada)

`wapi-send-products` acepta `dry_run: true`: resuelve productos, stock,
destinos y captions y **no envía ni escribe nada**. Requiere credenciales
reales (service_role o un JWT de gerente/supervisor): la publishable/anon key
devuelve 401 a propósito.

```powershell
$KEY = "<SERVICE_ROLE_KEY>"   # Dashboard → Settings → API. NO lo commitees.
$BODY = @{
  id_sesion = 22
  product_ids = @(5265,5266,5269,11058,11061,11062,6777,7337,7338,7339,7344,9082,9087,9088,9089,9092,10504,10505,10507,10508,10509,11059,5315,7232,7325,7327,8919,9322,9323,9324,9325)
  destinations = @(
    @{chat_id="120363195152592934@g.us"},
    @{chat_id="120363409451879219@g.us"},
    @{chat_id="120363172271515786@g.us"},
    @{chat_id="120363266453891641@g.us"},
    @{chat_id="120363406746096914@g.us"}
  )
  dry_run = $true
} | ConvertTo-Json -Depth 5
Invoke-RestMethod -Method Post `
  -Uri "https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/wapi-send-products" `
  -Headers @{ Authorization = "Bearer $KEY"; apikey = $KEY; "Content-Type" = "application/json" } `
  -Body $BODY | ConvertTo-Json -Depth 4
```

**Criterio de éxito:** `productos_resueltos` == `productos` y
`productos_sin_info` **vacío**. Con 5 destinos, `mensajes` = `productos × 5`.
Ese era exactamente el fallo del 2026-10-28: un worker cargó **6 de 53**
productos y marcó 194 mensajes como `producto no encontrado`.

Logs (Dashboard → Edge Functions → `wapi-send-products` → Logs): debe aparecer
`DRY-RUN: N/N producto(s) resueltos`.

### 4.2 Avisos de agotado

**Pre-flight (hazlo antes de activar nada):** el trigger llama a la función con
la `service_role` key guardada en Vault. Comprueba que ese acoplamiento sigue
vivo — `fn_wapi_dispatch_diario` usa el mismo secreto para `wapi-cron-dispatch`:

```sql
select id, status_code, error_msg, created
  from net._http_response order by created desc limit 10;
-- Esperado: 200 en las llamadas recientes a wapi-cron-dispatch / wapi-session-health.
-- Si ves 401: la clave de Vault ('wapi_service_role_key') está rotada o caducada
-- → actúalizala ANTES de activar los avisos (si no, los avisos quedarían 'omitido'/NO_VAULT
--   o la función devolvería 401 en silencio).
```

```sql
-- Config por tienda (vacío hasta que la actives, ver §7)
select id, id_tienda, activo, cooldown_minutos from public.app_wapi_agotado_config;

-- Historial de avisos
select id, id_tienda, id_producto, chat_id, estado, error_code, created_at, sent_at
  from public.app_wapi_agotado_log order by id desc limit 20;

-- ¿Salió la llamada HTTP del trigger? (200 = la función contestó)
select id, status_code, left(coalesce(content::text,''),200) as contenido, error_msg, created
  from net._http_response order by created desc limit 10;
```

Advisors:

```powershell
npx supabase db advisors --project-ref vsieeihstajlrdvpuooh
# o Dashboard → Advisors
```

Nota: el proyecto ya arrastra cientos de hallazgos
`security_definer_function_executable` **preexistentes**; los de este trabajo
(`fn_wapi_agotado_*`) ya vienen revocados. Lo que no debe aparecer es un
hallazgo nuevo que mencione esas dos funciones o las tablas `app_wapi_agotado_*`.

### 4.3 `solo_disponibles` en una programación

```sql
select id, id_tienda, activa, solo_disponibles from public.app_wapi_programacion order by id;
-- Activar/desactivar (también se hace desde la app):
update public.app_wapi_programacion set solo_disponibles = true  where id = <id_prog>;
update public.app_wapi_programacion set solo_disponibles = false where id = <id_prog>;
```

---

## 5. Recompilar la app

La UI nueva (chip "Solo productos con stock" en la programación, sección de
Avisos de agotado, aviso no bloqueante si la columna/tablas aún no existen)
necesita un build nuevo:

```powershell
cd C:\Users\cesar\Documents\VentIQ-seller-App\ventiq_admin_app
$env:APPDATA = 'C:\Users\cesar\Documents\VentIQ-seller-App\.dsh\dart-tool'   # evita el fallo de telemetría
flutter build apk --release
```

(o el script del repo: `.\build_and_deploy.ps1 -AppFolder "ventiq_admin_app" -ApkName "<nombre>"`).

La app **funciona igual si aplicas primero la app y después el SQL**: si la
columna o las tablas nuevas no existen todavía, lo detecta, guarda la
programación sin el filtro y te avisa con un mensaje no bloqueante.

---

## 6. Recuperar los mensajes perdidos por el bug (importante)

La tanda del 2026-10-28 (53 productos × 5 grupos = 265 mensajes) quedó a medias:
sus filas están en `app_wapi_envio_log` como `fallido` (SKIPPED "producto no
encontrado") o `pendiente`, y las **fallidas cuentan como reintentables**.

1. **Espera a que la cadena actual termine** (mientras haya envíos en curso
   verás actividad en el historial de la app). Lanzar un reintento en paralelo
   vuelve a solapar cadenas, que es lo que ya causó problemas de idempotencia
   en esta misma tanda.
2. **Despliega primero el fix** (§3). Si reintentas con la versión vieja (v31),
   el mismo bug puede volver a marcar productos como "no encontrado".
3. En la app: **Historial de la tanda → "Reintentar N mensajes"**. El backend
   reutiliza las mismas filas (no duplica) y esta vez la precarga de datos de
   producto cubre todos los destinos.
4. Sigue el progreso en el historial (`app_wapi_envio_log`):

```sql
select estado, error_code, count(*), min(created_at), max(sent_at)
  from public.app_wapi_envio_log
 where created_at >= '2026-10-28 11:00:00-04'
 group by estado, error_code order by estado, error_code;
```

> Nota sobre los códigos de error: las filas del incidente son `SKIPPED`
> ("producto no encontrado", antiguo) y **sí** son reintentables. Los códigos
> nuevos `PRODUCTO_NO_ENCONTRADO` y `SKIPPED_AGOTADO` son **terminales** a
> propósito (un producto que no existe, o que la programación pidió no
> anunciar, no debe reintentarse en bucle).

> Contexto de por qué tardaba tanto: OpenWA estaba respondiendo a 15–100 s por
> imagen, así que cada worker de ~4 min despachaba entre 2 y 16 mensajes. Es un
> límite del servidor WAPI, no del fix.

---

## 7. Activar los avisos de "producto agotado"

**Nada está activo por defecto** (`activo = false`). Hasta que lo enciendas, el
trigger sale en la primera comprobación y no manda nada.

Desde la app: *WAPI → Avisos de agotado* → activar, elegir grupos, plantilla y
delays. Equivalentemente por SQL (ejemplo para la tienda 177):

```sql
-- Lista de grupos guardados de la tienda
select id, tipo, chat_id, etiqueta from public.app_wapi_destinatario where id_tienda = 177 order by id;

insert into public.app_wapi_agotado_config (id_tienda, id_sesion, activo)
values (177, null, true)                      -- id_sesion null = la sesión CONNECTED de la tienda
on conflict (id_tienda) do update set activo = excluded.activo, id_sesion = excluded.id_sesion;

insert into public.app_wapi_agotado_destinatario (id_config, id_destinatario)
select c.id, d.id
  from public.app_wapi_agotado_config c
  join public.app_wapi_destinatario d on d.id_tienda = c.id_tienda
 where c.id_tienda = 177
   and d.chat_id in ('<chat_id_1>', '<chat_id_2>')   -- pon aquí los grupos que quieras
on conflict do nothing;
```

**Prueba de humo recomendada:** activa primero **un solo destinatario de
prueba** (un grupo tuyo), provoca un agotado real (una venta que deje stock 0) y
comprueba `app_wapi_agotado_log` + `net._http_response` antes de activar todos
los grupos de clientes.

Apagar: `update public.app_wapi_agotado_config set activo = false;`

> El trigger sólo mira el **stock total del producto** y se dispara en la
> transición a ≤ 0. Aviso: además de las ventas, cualquier movimiento que deje
> el total en 0 (ajustes, consignaciones, extracciones, inicializaciones de
> inventario) puede disparar el aviso; el `cooldown_minutos` (30 por defecto)
> amortigua ráfagas y evita repetir si el stock oscila. Si un producto se
> repone y se vuelve a agotar, **sí vuelve a avisar** (la transición se calcula
> contra el histórico, no con un flag cacheado).

---

## 8. Reversión

```sql
-- Avisos de agotado: apagar y quitar el trigger (los datos quedan)
update public.app_wapi_agotado_config set activo = false;
drop trigger if exists trg_wapi_agotado_notificar on public.app_dat_inventario_productos;

-- Deshacer el esquema completo (opcional)
drop function if exists public.fn_wapi_agotado_check();
drop function if exists public.fn_wapi_agotado_stock_total(bigint, bigint);
drop table if exists public.app_wapi_agotado_destinatario;
drop table if exists public.app_wapi_agotado_log;
drop table if exists public.app_wapi_agotado_config;
drop table if exists public.app_wapi_agotado_estado;

-- solo_disponibles (opcional; las funciones viejas la ignoran)
alter table public.app_wapi_programacion drop column if exists solo_disponibles;
```

Funciones: vuelve a desplegar la versión anterior desde tu control de versiones
(`git log --oneline -- ventiq_admin_app/supabase/functions/wapi-send-products`)
o `npx supabase functions delete wapi-notify-agotado --project-ref vsieeihstajlrdvpuooh`.

---

## 9. Qué cambia exactamente

| Artefacto | Cambio |
|---|---|
| `supabase/functions/wapi-send-products/index.ts` | **fix del bug "producto no encontrado"** (precarga por ventana posicional + reintento puntual antes de descartar + `error_code` `PRODUCTO_NO_ENCONTRADO`), soporte `solo_disponibles` y modo `dry_run` |
| `supabase/functions/wapi-cron-dispatch/index.ts` | lee `app_wapi_programacion.solo_disponibles` y lo reenvía (sólo si `true`), con fallback si la columna aún no existe |
| `supabase/functions/wapi-notify-agotado/index.ts` | **nuevo**: envía el aviso de agotado a los grupos configurados |
| `supabase/migrations/20261028_wapi_programacion_solo_disponibles.sql` | columna `solo_disponibles boolean not null default false` |
| `supabase/migrations/20261028_wapi_agotado_notificaciones.sql` | 4 tablas + RLS + `fn_wapi_agotado_stock_total` + `fn_wapi_agotado_check` + trigger `trg_wapi_agotado_notificar` |
| `supabase/config.toml` | `verify_jwt` explícito de `wapi-cron-dispatch` (true) y `wapi-notify-agotado` (true) |
| `lib/**` de la app | chip "Solo productos con stock", sección de Avisos de agotado y envío del flag al backend |
