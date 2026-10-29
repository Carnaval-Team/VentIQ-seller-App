# Despliegue — aviso de "producto agotado" a grupos de WhatsApp (WS3)

**Autor:** `backend-oos` · **Fecha:** 2026-10-28 · **Proyecto:** `vsieeihstajlrdvpuooh` (producción)

Esta es **mi parte** del despliegue; el Lead consolida todo en `DEPLOY_WAPI_2026-10-28.md`.

> **NADIE activa avisos automáticos con este despliegue.** La migración crea todo
> con `activo = false`. Sin una fila activa en `app_wapi_agotado_config` y al
> menos un destinatario vinculado, el trigger sale en la primera comprobación y
> no manda nada. El usuario decide desde la app.

---

## 0. Qué se despliega y en qué orden

| # | Artefacto | Ruta en el repo |
|---|---|---|
| 1 | Migración (4 tablas, RLS, helper de stock, trigger) | `ventiq_admin_app/supabase/migrations/20261028_wapi_agotado_notificaciones.sql` |
| 2 | Edge function del envío | `ventiq_admin_app/supabase/functions/wapi-notify-agotado/index.ts` |
| 3 | `verify_jwt = true` de la función | `ventiq_admin_app/supabase/config.toml` → `[functions.wapi-notify-agotado]` |

**Orden obligatorio: 1 → 2.** Si la función se despliega antes que la migración
no pasa nada grave (nadie la invoca todavía), pero el trigger la llamaría a un
endpoint que aún no existe. Primero la migración, después el deploy.

### Requisitos previos

Ya están en producción, **no hay que crear nada**:

* `pg_net` y `pg_cron` (los usa `fn_wapi_dispatch_diario` desde 2026-05).
* `supabase_vault` con los secretos `wapi_supabase_url` y `wapi_service_role_key`
  (comprobado el 2026-10-28: existen desde 2026-05-27 y el cron de producción
  recibe **HTTP 200** cada minuto en `net._http_response`).
* La función `public.fn_user_can_access_tienda(bigint)` (de 20260525) y el
  helper `public.fn_wapi_set_updated_at()`.

---

## 1. Aplicar la migración

Cualquiera de las dos vías (la migración es **idempotente**: `IF NOT EXISTS`,
`CREATE OR REPLACE`, `DROP TRIGGER IF EXISTS`; se puede re-ejecutar sin daño).

### Vía A — SQL Editor del dashboard (la más simple)

1. Abrir <https://supabase.com/dashboard/project/vsieeihstajlrdvpuooh/sql/new>.
2. Pegar **el archivo entero** `20261028_wapi_agotado_notificaciones.sql`.
3. Run. No debe devolver error.

### Vía B — CLI

```bash
cd ventiq_admin_app
npx supabase db query --file supabase/migrations/20261028_wapi_agotado_notificaciones.sql \
  --project-ref vsieeihstajlrdvpuooh
```

### Verificación (debe dar 4 y 4)

```sql
select table_name from information_schema.tables
 where table_schema='public' and table_name like 'app_wapi_agotado%' order by 1;

select policyname from pg_policies
 where schemaname='public' and tablename like 'app_wapi_agotado%' order by 1;

select tgname from pg_trigger
 where tgrelid='public.app_dat_inventario_productos'::regclass and not tgisinternal
 order by 1;   -- debe aparecer trg_wapi_agotado_notificar JUNTO a los 3 preexistentes

-- ACL de las funciones: NO deben aparecer anon ni authenticated
select p.proname, coalesce(array_to_string(p.proacl,' | '),'(default del owner)') as acl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
 where n.nspname='public' and p.proname like 'fn_wapi_agotado%' order by 1;
-- esperado:  fn_wapi_agotado_check        → postgres=X/postgres
--            fn_wapi_agotado_stock_total  → postgres=X/postgres | service_role=X/postgres
```

> ⚠️ `REVOKE ... FROM PUBLIC` **no basta** en Supabase: hay
> `ALTER DEFAULT PRIVILEGES` que conceden `EXECUTE` a `anon`/`authenticated` al
> crear cada función. La migración lo revoca **explícitamente de esos roles**.
> Si el ACL de arriba mostrara `anon=` o `authenticated=`, la migración se
> aplicó mal: repetir el bloque de `REVOKE`. Si no, `get_advisors` (security)
> lo reportaría y el RPC quedaría expuesto vía `/rest/v1/rpc/`.

> Nota: la migración **no toca** los triggers existentes
> (`trg_notificar_producto_agotado`, `trg_notificar_producto_disponible`,
> `trg_sincronizar_stock_inventario`). Añade uno propio y separado. Si en la
> verificación faltara alguno de los tres viejos, algo se rompió: revisar antes
> de seguir.

---

## 2. Desplegar la edge function

```bash
cd ventiq_admin_app
npx supabase functions deploy wapi-notify-agotado --project-ref vsieeihstajlrdvpuooh
```

**`verify_jwt = true`**, fijado explícitamente en `supabase/config.toml`
(`[functions.wapi-notify-agotado]`). El porqué:

* Sus dos llamadores mandan siempre un JWT válido del proyecto: el trigger manda
  la `service_role` key del Vault (`Authorization` + `apikey`, igual que
  `fn_wapi_dispatch_diario` → `wapi-cron-dispatch`, que está con `true` y
  funciona); el botón de la app manda el JWT del usuario.
* **No puede ir en `false`** porque esta función manda WhatsApp a grupos de
  clientes y `_shared/auth.ts:isServiceRoleCall()` acepta `role=service_role`
  **sin comprobar la firma** (asume que el gateway ya la validó). Con
  `verify_jwt=false` un token forjado a mano pasaría ese filtro.

Comprobación:

```bash
npx supabase functions list --project-ref vsieeihstajlrdvpuooh | grep wapi-notify-agotado
```

Debe aparecer `ACTIVE` y con `verify_jwt` en `true`.

---

## 3. Activar el aviso para una tienda (lo hace el usuario desde la app)

Esto es lo único que "enciende" los mensajes. **Para la tienda 177 hay que
hacerlo con permiso explícito del usuario**, porque manda a sus 5 grupos de
CARNAVAL, sus 2 números y el grupo "Inventtia".

### 3.1 Elegir a quién se avisa

Los destinatarios se reutilizan de `app_wapi_destinatario` (los mismos grupos
que ya usa la difusión). Si el grupo no está ahí todavía, primero se guarda ahí
desde la app (o con un insert):

```sql
-- Ejemplo: listar los destinatarios ya guardados de la tienda 177
select id, tipo, chat_id, etiqueta from public.app_wapi_destinatario
 where id_tienda = 177 order by id;
```

### 3.2 Crear la configuración

```sql
-- Tienda 177. `activo` se deja en true SOLO si el usuario lo autoriza.
insert into public.app_wapi_agotado_config (id_tienda, id_sesion, activo)
values (177, null, true)          -- id_sesion null = la sesión CONNECTED de la tienda
on conflict (id_tienda) do update
   set activo = excluded.activo,
       id_sesion = excluded.id_sesion;

-- Vincular los destinatarios que deben recibir el aviso
insert into public.app_wapi_agotado_destinatario (id_config, id_destinatario)
select c.id, d.id
  from public.app_wapi_agotado_config c
  join public.app_wapi_destinatario d on d.id_tienda = c.id_tienda
 where c.id_tienda = 177
   and d.chat_id in ('120363195152592934@g.us', '120363409451879219@g.us')
on conflict do nothing;
```

### 3.3 Ajustes opcionales

```sql
update public.app_wapi_agotado_config
   set plantilla = E'⚠️ *PRODUCTO AGOTADO*\n\n🔴 *{producto}*\n🏷️ {categoria}\n💰 {precio}\n📦 Existencias: {stock}\n\nPronto volverá a estar disponible. — {tienda}',
       delay_min_seconds = 5,
       delay_max_seconds = 10,
       cooldown_minutos  = 30
 where id_tienda = 177;
```

Placeholders soportados: `{producto}`, `{precio}`, `{stock}`, `{categoria}`,
`{tienda}`. Si se deja `plantilla` a `null`, la edge function usa la plantilla
por defecto (la misma del `DEFAULT` de la tabla).

### 3.4 Apagar el aviso

```sql
update public.app_wapi_agotado_config set activo = false where id_tienda = 177;
```

---

## 4. Comprobar que funciona

### 4.0 Antes de confiar en el canal: el token de Vault debe ser válido

El trigger llama a la función con la `service_role` key guardada en
`wapi_service_role_key`. Como la función va con `verify_jwt = true`, **el
gateway valida la firma de ese JWT**: si el secreto del Vault está rotado o es
de otro proyecto, la llamada recibe **401 y el fallo es silencioso** (la venta
sigue bien, el aviso simplemente no llega; sólo queda registrado).

Comprobación (debe devolver **200**, no 401/403):

```sql
select id, status_code, left(coalesce(content::text,''), 300) as contenido,
       error_msg, created
  from net._http_response order by created desc limit 10;
```

Si sale 401: comparar el valor de `wapi_service_role_key` (Vault) con la
`service_role` key actual del dashboard (Project Settings → API) y actualizarlo
con la migración `20260602_wapi_update_service_key.sql`. **El mismo riesgo ya
existe hoy** para `wapi-cron-dispatch` (también `verify_jwt=true` y también
invocada por pg_net con ese secreto): si esa sigue dando 200 cada minuto, el
secreto vale.

```sql
-- ¿Qué avisos se han encolado/enviado?
select id, id_tienda, id_producto, chat_id, estado, error_code,
       left(coalesce(error_message,''), 80) as error, created_at, sent_at
  from public.app_wapi_agotado_log
 order by id desc limit 20;

-- Estado por producto (auditoría/UI; NO decide los avisos)
select * from public.app_wapi_agotado_estado
 where id_tienda = 177 order by updated_at desc limit 20;

-- ¿Salió la llamada HTTP del trigger? (status_code 200 = la función contestó)
select id, status_code, left(coalesce(content::text,''), 200) as contenido,
       error_msg, created
  from net._http_response order by created desc limit 10;

-- Stock total que calcula el trigger para un producto concreto
select public.fn_wapi_agotado_stock_total(<id_producto>);
```

Logs de la función (dashboard → Edge Functions → wapi-notify-agotado → Logs),
o por SQL con el MCP: filtra `function_logs`/`edge_logs` por
`wapi-notify-agotado`.

### Interpretación de `estado` en el log

| estado | significado |
|---|---|
| `pendiente` | el trigger lo encoló; la función aún no lo procesó (o se quedó sin presupuesto) |
| `enviado` | WhatsApp aceptó el mensaje (`mensaje_id` y `sent_at` rellenos) |
| `fallido` | WAPI lo rechazó (ver `error_code`); **re-intentable** re-invocando la función con esos ids |
| `omitido` | no se intentó: `SIN_CONFIG`, `CONFIG_INACTIVA`, `SIN_PRODUCTO` o `NO_VAULT` |

### Comportamiento que conviene tener claro (decidido a propósito)

* **`cooldown_minutos`** es una ventana **anti-ráfaga** para el caso
  "se repone → se vuelve a agotar" (por defecto 30 min). **No es** la
  deduplicación: un mismo agotado genera **un solo** aviso aunque pongas
  `cooldown_minutos = 0`, porque la transición se detecta contra el histórico
  (si dos movimientos de la misma transacción dejan el total en 0, el segundo
  ve que el stock previo ya era 0 y no encola). Con `cooldown = 0` lo único que
  permites es avisar de nuevo si el producto se repone y se agota otra vez, sin
  espera.
* **No sólo las ventas disparan el aviso.** Se dispara con cualquier movimiento
  que deje el total del producto en `<= 0`: ajustes de inventario,
  consignaciones, extracciones totales, inicializaciones... Si el stock llega a
  0, el aviso es correcto; pero si el usuario hace un ajuste a 0 quizá reciba un
  mensaje. El `cooldown` lo amortigua.
* **La rama "desconocido → 0" es inalcanzable** (a propósito). Sin
  ubicaciones/TPV no se puede calcular el stock y **no se avisa**; con
  ubicaciones el stock siempre es un número (0 como mínimo). Un producto que ya
  estaba a 0 en el histórico no produce aviso: sería decir que "se agotó" algo
  que ya estaba agotado antes de activar la feature.
* **`app_wapi_agotado_estado.agotado` es informativo.** El trigger no lo usa
  para decidir (una reposición no lo actualiza y se quedaría obsoleto). La
  fuente de verdad del historial es `app_wapi_agotado_log`.

### Reintentar los fallidos

```bash
curl -X POST "https://vsieeihstajlrdvpuooh.supabase.co/functions/v1/wapi-notify-agotado" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"log_ids":[123,124]}'
```

(Con los ids que aparezcan en `estado='fallido'`. Las filas ya `enviado` se
saltan: re-invocar es idempotente.)

---

## 5. Reversión

```sql
-- 1) Apagar todo (inmediato, sin tocar el esquema)
update public.app_wapi_agotado_config set activo = false;

-- 2) Quitar el trigger (deja de detectar; los datos quedan)
drop trigger if exists trg_wapi_agotado_notificar on public.app_dat_inventario_productos;

-- 3) Deshacer el esquema por completo (opcional)
drop function if exists public.fn_wapi_agotado_check();
drop function if exists public.fn_wapi_agotado_stock_total(bigint, bigint);
drop table if exists public.app_wapi_agotado_destinatario;
drop table if exists public.app_wapi_agotado_log;
drop table if exists public.app_wapi_agotado_config;
drop table if exists public.app_wapi_agotado_estado;
```

Y para la función:
`npx supabase functions delete wapi-notify-agotado --project-ref vsieeihstajlrdvpuooh`

---

## 6. Nota de implementación importante (si alguien revisa el SQL)

El trigger sólo se despierta cuando el movimiento **deja su ubicación en `<=0`**
(cláusula `WHEN`), porque si no cada INSERT del histórico de 412.000 filas
pagaría el coste de comprobar la config. Consecuencia: una **reposición**
(cantidad_final > 0) no lo despierta, así que el flag `agotado` de
`app_wapi_agotado_estado` puede quedar desactualizado.

Por eso la transición **no** se decide con ese flag (hacerlo produciría un falso
negativo silencioso: "producto repuesto y vuelto a agotar" no avisaría nunca),
sino calculando el stock que había **justo antes** del movimiento con
`fn_wapi_agotado_stock_total(producto, id_del_movimiento)`. La tabla de estado
se sigue escribiendo (contrato con la UI / auditoría) pero **no decide**.

Detalle y evidencia en `__agent__/verify/backend-oos/RESUMEN.md`.
