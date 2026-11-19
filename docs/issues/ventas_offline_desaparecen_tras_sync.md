# Ventas offline que desaparecen del vendedor tras sincronizar

Fecha del análisis: 2026-11-18. Base: Supabase **main** (producción). App: `ventiq_app`.

## Síntoma

Las ventas hechas en modo offline **sí llegan al servidor**, pero después de sincronizar
el vendedor deja de verlas (lista de órdenes, resumen y cierre del turno).

## Conclusión corta

Las ventas no se pierden: quedan **fuera de la ventana del turno** al que el servidor las
asocia. Al sincronizar, el turno se crea en el servidor con `fecha_apertura` = **hora del
sync**, no con la hora real de la apertura offline. Las ventas conservan su hora real
(horas antes), así que caen **antes** de la apertura.

La app tiene dos filtros que no coinciden:

1. El pull del servidor usa la apertura **local** (temprana): las ventas entran y la app
   borra sus copias pendientes porque "ya están en el servidor".
2. La lista, el resumen y el cierre usan el turno del **servidor** (apertura tardía): las
   descartan porque `fecha_operacion < fecha_apertura`.

Resultado: ya no quedan como pendiente local, y como orden del servidor se filtran.

---

## 1. Evidencia en el servidor

### 1.1 Tamaño del problema (últimos 10 días)

| Métrica | Valor |
|---|---|
| Ventas offline sincronizadas (`app_dat_operacion_offline_idempotencia`) | 236 |
| Fuera de **cualquier** turno de su vendedor/TPV | **76** |
| Con `created_at` posterior a la hora en que se sincronizaron (reloj adelantado) | 14 |

Las 76 son todas del **TPV 249 "CAJA Capiro"** (tienda 177, Carnaval Escambray),
vendedor **133** (`748b2bc7-dadb-4c76-b327-251c047657fe`, "TURNO CAPIRO 1").

### 1.2 Turnos afectados (hora de Cuba)

| Turno | Apertura en servidor | Cierre | Ventas dentro | Qué pasó |
|---|---|---|---|---|
| 3522 | 16/11 **17:09:00** | 16/11 17:11:00 | **0** | 62 ventas offline de 09:31 a 15:21, sincronizadas a las 17:09 |
| 3524 | 17/11 07:00:14 | 17/11 14:29:51 | 38 | Apertura correcta |
| 3533 | 17/11 **16:07:17** | 17/11 16:16:02 | **0** | 14 ventas de 14:29 a 15:16, sincronizadas a las 16:07 |

En los dos casos la apertura del servidor coincide con el momento del sync (las ventas
se suben un segundo después), no con la apertura real offline.

### 1.3 Dos llamadas de apertura simultáneas

Logs de la API (`edge_logs`):

```
16/11 22:09:00.877Z  POST rpc/fn_apertura_turno_offline_usd  200
16/11 22:09:01.145Z  POST rpc/fn_apertura_turno_offline_usd  200   ← +268 ms
17/11 21:07:17.518Z  POST rpc/fn_apertura_turno_offline_usd  200
17/11 21:07:17.977Z  POST rpc/fn_apertura_turno_offline_usd  200   ← +459 ms
```

- El turno se crea en la **primera** llamada (`fecha_apertura` = `now()` de esa
  transacción: 17:09:00.90 y 16:07:17.55).
- La fila de idempotencia `apertura_turno` es de la **segunda** llamada (17:09:01.16 y
  16:07:17.99). Es otra transacción: `created_at` usa `now()` y no coincide.
- La segunda llamada entra en la rama "turno ya abierto → reutilizar" de
  `fn_apertura_turno_offline`, que **nunca** aplica `p_fecha_apertura`.
- No hay fila de idempotencia de la primera llamada. Puede que usara otro `client_uuid`
  (entrada duplicada en la cola) o que esa fila se borrara después en la rama
  "turno cerrado → DELETE mapping". **Sin confirmar**: hacen falta logs del dispositivo.

### 1.4 La app instalada es más vieja que el repo

El dispositivo llama a `fn_apertura_turno_offline_usd` directamente. El repo actual llama
primero a `fn_apertura_turno_offline_monedas`. Los vendedores corren un build **anterior**
al código analizado, así que hay que validar cada conclusión contra ese build.

### 1.5 Reloj del dispositivo adelantado ~1 h (17/11)

- Turno 3524: `fecha_cierre` = 14:29:51 (la envía el cliente), pero la fila de
  idempotencia del cierre se insertó a las **13:29:52** (hora del servidor).
- Turno 3505 (vendedor 297, mismo TPV): `fecha_cierre` 15:47:13, idempotencia 14:47:14.
- 14 ventas tienen `created_at` **posterior** a la hora en que se sincronizaron.
- En este mismo dispositivo, los logs de `flutter run` muestran
  `ServerTimeService: offset = -3551s (servidor atrás del dispositivo)`.

En el build instalado la corrección de `ServerTimeService` no se aplica (o no en todas las
rutas). Las fechas adelantadas pueden dejar ventas después del cierre real o fuera de la
ventana. Es un riesgo aparte que agrava el problema principal.

---

## 2. Código implicado (repo actual)

### 2.1 Servidor: la apertura reutilizada no corrige la fecha

`fn_apertura_turno_offline` (main):

- Idempotencia por `client_uuid`. Si el turno mapeado está cerrado, borra el mapping.
- Si ya hay turno abierto para `id_tpv`+`id_vendedor`, lo **reutiliza** y devuelve
  `success` **sin** `UPDATE fecha_apertura`.
- Solo cuando crea un turno nuevo (vía `registrar_apertura_turno_v3`) aplica
  `p_fecha_apertura`.

Cadena de llamadas: `_monedas` → `_usd` → `fn_apertura_turno_offline`.

### 2.2 Cliente: la reutilización tampoco corrige la fecha

`AutoSyncService._ensureAperturaForQueueEntry`:

- `ventiq_app/lib/services/auto_sync_service.dart:1336-1362`: si `_getOnlineOpenShift`
  encuentra un turno abierto, lo reutiliza **sin** alinear `fecha_apertura`.
- `:1545-1565`: igual cuando la RPC falla y se reutiliza el turno existente.
- `:1569-1585`: **solo** si `serverId == null` hace `update({'fecha_apertura': ...})`.

### 2.3 Cliente: los dos filtros que no coinciden

**A. Pull del servidor: usa la apertura LOCAL**

- `_resolveTurnoOperacionesWindow` (`auto_sync_service.dart:3348-3412`) toma `from` de
  `getOfflineTurno()['fecha_apertura']`, la apertura offline real (temprana).
- `_syncOrders` / `_filterOrdersByTurnoWindow` (`:3424-3501`): las ventas **entran**.
- `_pullServerOrdersIntoCache` (`:3506-3551`) llama a
  `removeSyncedPendingPresentOnServer(serverOpIds)`
  (`user_preferences_service.dart:1806-1840`), que **borra de `pending_orders`** las
  ventas ya sincronizadas que aparecen en el servidor.

**B. Lista, resumen y cierre: usan el turno del SERVIDOR**

- `TurnoService.getTurnoAbierto()` (`turno_service.dart:302-389`) en modo online
  devuelve la fila de `app_dat_caja_turno`, con la apertura **tardía** (hora del sync).
- `OrderService.loadOrdersForOpenTurnoUnified` (`order_service.dart:2182-2276`) y
  `loadOrdersFromLocalCacheForOpenTurno` (`:2279-2305`) filtran con
  `_filterRawOrdersToOpenTurno` (`:2117-2169`). Las filas de `listar_ordenes` no traen
  `local_turno_id` ni `id_turno`, así que el filtro cae a la fecha:
  `!fo.isBefore(from)` → **descarta** las ventas anteriores a la apertura tardía.
- `getSellerVisiblePendingOrders` (`user_preferences_service.dart:1652-1678`) ya no las
  ve: las borró el paso A.

Además, `saveOfflineTurno` (`user_preferences_service.dart:3162-3195`) sobrescribe la
`fecha_apertura` local con la del servidor
(`'fecha_apertura': turnoData['fecha_apertura'] ?? ...`). Tras cachear el turno online,
incluso la ventana del paso A pasa a ser la tardía.

`orders_screen.dart:785-798` llama a `loadOrdersForOpenTurnoUnified` y, en online, lanza
`pullServerOrdersForCurrentShift` en paralelo. Es la combinación exacta A + B.

### 2.4 Por qué se nota en el cierre

En los dos casos el vendedor sincronizó y cerró minutos después (17:09 → 17:11 y
16:07 → 16:16). Con el turno ya en el servidor, el resumen y el cierre filtran por la
apertura tardía y muestran **0 ventas**. El servidor también ve 0 ventas dentro de 3522
y 3533, así que el cuadre por turno sale mal en las dos puntas.

---

## 3. Otros hallazgos laterales

- **TPV 249 tiene dos vendedores (133 y 297)**. El turno 3505 del vendedor 297 estuvo
  abierto del 14/11 07:29 al 17/11 15:47. No causa este problema (la apertura filtra por
  vendedor), pero es otro turno colgado.
- **`listar_ordenes` con fechas** usa `fecha_desde/fecha_hasta` como `date`
  (`+ 1 day - 1 second`) en la zona del servidor. Si la sesión de Postgres está en UTC,
  las ventas después de ~19:00 de Cuba quedarían fuera del rango del día. No se detectó
  ninguna en los datos actuales (0 ventas después de las 19:00), pero es un riesgo
  latente.
- **Ruta legacy no idempotente en Ajustes**: `settings_screen.dart:4816-4837`
  (`_processAperturaTurno` → `TurnoService.registrarAperturaTurno`) abre turno sin fecha
  si quedara una operación `apertura_turno` en `pending_operations`. Hoy nada encola ese
  tipo; conviene eliminarla.

---

## 4. Correcciones propuestas (resumen)

> El detalle listo para aplicar (SQL completo y cambios en Dart) está en la
> **sección 6**. Esta lista es el resumen.

### Servidor (prioridad alta)

1. En `fn_apertura_turno_offline`, rama "turno ya abierto → reutilizar": si llega
   `p_fecha_apertura` y es **anterior** a la `fecha_apertura` actual (y posterior al
   cierre del turno previo del mismo TPV/vendedor), hacer
   `UPDATE app_dat_caja_turno SET fecha_apertura = p_fecha_apertura`.
2. Serializar la apertura por TPV/vendedor (`pg_advisory_xact_lock(id_tpv, id_vendedor)`
   al inicio) para que dos llamadas simultáneas no creen ni reutilicen a ciegas.
3. Reparar 3522 y 3533: mover `fecha_apertura` al primer `created_at` de sus ventas (o
   reasignar esas ventas). Antes hay que validar el impacto en el cuadre, porque es una
   escritura en producción.

### Cliente (prioridad alta)

4. `_ensureAperturaForQueueEntry`: al reutilizar un turno abierto (las tres ramas),
   alinear `fecha_apertura` con la apertura offline si esta es anterior. Hoy solo lo hace
   cuando `serverId == null`.
5. Evitar dos replays de apertura a la vez: `_turnoQueueInFlight` protege
   `_syncOfflineTurnoQueue`, pero no las rutas `syncModules({uploadTurno})` ni
   `syncSinglePendingOrder` desde el `_SyncDialog` de Ajustes. Revisar si esas rutas
   abren turno por su cuenta y unificarlas en el mismo candado.
6. No borrar pendientes en `removeSyncedPendingPresentOnServer` si después no van a pasar
   el filtro del turno. Opción simple: aplicar el **mismo** `_filterRawOrdersToOpenTurno`
   (con el turno que usa la UI) antes de borrar. Mejor: conservar las synced del turno
   hasta el cierre (como ya promete el comentario de `markOrdersSyncedById`).
7. `saveOfflineTurno`: no pisar la `fecha_apertura` local con una del servidor posterior
   para el mismo turno; quedarse con la menor.
8. Reloj: verificar en el build instalado que todas las fechas offline (venta, apertura,
   cierre, egreso) usan `ServerTimeService().now()`. Ojo: `savePendingOrder` pone
   `created_offline_at = DateTime.now()` (hora del **dispositivo**,
   `user_preferences_service.dart:1576`) y pisa la corregida que manda el checkout. Hoy
   `p_fecha_creacion` usa `fecha_creacion` primero, pero el filtro legacy de
   `getSellerVisiblePendingOrders` usa `created_offline_at` como respaldo.

---

## 5. Cómo verificar

1. Pedir al vendedor de "CAJA Capiro" los logs con prefijo `[TURNO_SYNC]` de un sync,
   para confirmar si hay **dos** entradas en la cola o dos disparadores simultáneos.
2. Reproducir en un dispositivo de prueba:
   - Abrir turno offline a las HH:00, vender a HH:10 y HH:20.
   - Desactivar el modo offline a HH:40 (o sincronizar desde Ajustes).
   - Comprobar `app_dat_caja_turno.fecha_apertura` (¿HH:00 o HH:40?) y la lista de
     órdenes del vendedor antes y después de `pullServerOrdersForCurrentShift`.
3. Probar también con el reloj del dispositivo adelantado 1 h.
4. Comprobar los tres casos que pide la regla del proyecto: online, offline con cache
   fresco y offline con cache vacío.

### SQL de diagnóstico (solo lectura)

```sql
-- Ventas offline fuera de cualquier turno de su vendedor/TPV
with ventas as (
  select o.id, o.created_at, o.uuid, ov.id_tpv, i.created_at as sync_at
  from app_dat_operaciones o
  join app_dat_operacion_venta ov on ov.id_operacion = o.id
  join app_dat_operacion_offline_idempotencia i on i.id_operacion = o.id
  where o.created_at >= now() - interval '10 days'
)
select v.*,
  (select ct.id from app_dat_caja_turno ct
     join app_dat_vendedor vd on vd.id = ct.id_vendedor
    where ct.id_tpv = v.id_tpv and vd.uuid = v.uuid
      and v.created_at >= ct.fecha_apertura
      and v.created_at <= coalesce(ct.fecha_cierre, now())
    limit 1) as turno_que_la_cubre
from ventas v
order by v.created_at;
```

```sql
-- Turnos abiertos por el sync con apertura = hora del sync
select ct.id, ct.id_tpv, ct.id_vendedor, ct.fecha_apertura,
       i.created_at as idem_apertura_at,
       (select min(o.created_at) from app_dat_operaciones o
          join app_dat_operacion_venta ov on ov.id_operacion = o.id
          join app_dat_vendedor vd on vd.uuid = o.uuid
         where ov.id_tpv = ct.id_tpv and vd.id = ct.id_vendedor
           and o.created_at < ct.fecha_apertura
           and o.created_at > ct.fecha_apertura - interval '16 hours') as primera_venta_previa
from app_dat_caja_turno ct
join app_dat_operacion_offline_idempotencia i
  on i.id_operacion = ct.id and i.tipo = 'apertura_turno'
where ct.fecha_apertura >= now() - interval '10 days'
order by ct.fecha_apertura desc;
```

---

## 6. Plan de corrección completo

### 6.0 Causas que hay que corregir

| # | Causa | Dónde | Se corrige en |
|---|---|---|---|
| C1 | Al reutilizar un turno ya abierto no se aplica la apertura real | `fn_apertura_turno_offline` (BD) y `_ensureAperturaForQueueEntryUnlocked` (Dart) | S2, S3, D2 |
| C2 | Dos aperturas simultáneas del mismo TPV/vendedor | BD sin candado; candado del cliente por `local_id` y solo dentro de un isolate | S3, D3 |
| C3 | La app borra la copia local de la venta aunque la UI luego la filtre | `removeSyncedPendingPresentOnServer` | D4 |
| C4 | `saveOfflineTurno` pisa la apertura local con la del servidor (más tardía) | `user_preferences_service.dart` | D5 |
| C5 | Fechas enviadas **sin zona horaria** | `ServerTimeService().now().toIso8601String()` → p. ej. `2026-11-17T14:29:51.000` | D1, S4, S5 |
| C6 | `fn_cerrar_turno_offline` elige el turno abierto del TPV **sin filtrar por usuario** | BD (en el TPV 249 hay dos vendedores) | S4 |
| C7 | El sync de Ajustes abre/cierra turnos por rutas no idempotentes y sube ventas antes de la apertura | `settings_screen.dart` (`_SyncDialog`) | D7 |
| C8 | `created_offline_at` se pisa con la hora del dispositivo | `savePendingOrder` | D6 |

**Detalle de C5.** La sesión de Postgres está en `TimeZone=America/Havana` (configuración
de la base). El cliente manda `DateTime` locales con `toIso8601String()`, que **no lleva
offset**. Postgres interpreta esa hora "de pared" como hora de La Habana.

Si el teléfono tiene una zona distinta (p. ej. UTC-4, por reglas de horario de verano
desactualizadas) y el usuario ajustó el reloj a mano para que "se vea bien", pasa esto:

1. El epoch del teléfono queda adelantado una hora (es el `offset = -3551s` del log).
2. `ServerTimeService` corrige el epoch.
3. Pero al formatear en la zona del teléfono, el texto sale **1 h adelantado** respecto
   a La Habana.

Es justo lo observado el 17/11: cierres 1 h por delante del momento en que se insertaron
y ventas con fecha posterior a su propia subida. La corrección es enviar siempre UTC con
`Z` (D1) y que el servidor no acepte fechas futuras (S4, S5).

### 6.1 Orden de despliegue

1. **SQL S1 a S5** (todas compatibles con el build actual: mismas firmas y mismos
   retornos). Con esto, el build **ya instalado** deja de crear turnos con la apertura
   del sync.
2. **SQL S6**: reparar los turnos 3522 y 3533 (escritura en producción, con vista previa
   y transacción).
3. **App** con D1 a D7 → nuevo build para los vendedores.
4. **S7**: monitoreo diario durante una semana.

Todo el SQL va en un único archivo de migración, p. ej.
`supabase/migrations/20261118120000_fix_apertura_turno_offline.sql`. Es SQL de la app
`ventiq_app` (no de `inventtia_flow`), así que no va en `docs/flow_schema`. No crea
tablas, así que no aplica la regla de RLS. Las funciones nuevas son `SECURITY DEFINER`
con validación de acceso por tienda.

---

### 6.2 SQL

#### S1. Función interna: alinear la apertura hacia atrás con límites

Solo **mueve hacia atrás** la apertura de un turno **abierto**:

- nunca a una fecha futura;
- nunca antes del cierre del turno anterior del mismo TPV y vendedor;
- nunca más de 72 h hacia atrás (protege contra relojes absurdos).

No la puede llamar el cliente directamente.

```sql
create or replace function public.fn_turno_alinear_fecha_apertura(
  p_id_turno       bigint,
  p_fecha_apertura timestamptz
) returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_turno         record;
  v_cierre_previo timestamptz;
  v_fecha         timestamptz;
begin
  if p_id_turno is null or p_fecha_apertura is null then
    return false;
  end if;

  select id, id_tpv, id_vendedor, estado, fecha_apertura
    into v_turno
  from app_dat_caja_turno
  where id = p_id_turno
  for update;

  if not found or v_turno.estado <> 1 then
    return false;
  end if;

  -- Nunca en el futuro (reloj del dispositivo adelantado).
  v_fecha := least(p_fecha_apertura, now());

  -- Solo hacia atrás.
  if v_fecha >= v_turno.fecha_apertura then
    return false;
  end if;

  -- Tope de cordura: un turno offline de más de 3 días se revisa a mano.
  if v_turno.fecha_apertura - v_fecha > interval '72 hours' then
    raise warning 'fn_turno_alinear_fecha_apertura: turno % salto de % rechazado',
      p_id_turno, v_turno.fecha_apertura - v_fecha;
    return false;
  end if;

  -- No solapar con el turno anterior del mismo TPV + vendedor.
  select max(coalesce(ct.fecha_cierre, ct.fecha_apertura))
    into v_cierre_previo
  from app_dat_caja_turno ct
  where ct.id_tpv = v_turno.id_tpv
    and ct.id_vendedor = v_turno.id_vendedor
    and ct.id <> v_turno.id
    and ct.fecha_apertura < v_turno.fecha_apertura;

  if v_cierre_previo is not null and v_fecha <= v_cierre_previo then
    v_fecha := v_cierre_previo + interval '1 millisecond';
  end if;

  if v_fecha >= v_turno.fecha_apertura then
    return false;
  end if;

  update app_dat_caja_turno
     set fecha_apertura = v_fecha
   where id = p_id_turno;

  return true;
end;
$$;

revoke all on function public.fn_turno_alinear_fecha_apertura(bigint, timestamptz)
  from public, anon, authenticated;
```

#### S2. RPC pública: alinear la apertura desde el cliente

La usa el cliente cuando reutiliza un turno abierto **sin** pasar por la RPC de apertura
(D2). Valida el acceso a la tienda y toma el mismo candado que la apertura.

```sql
create or replace function public.fn_alinear_apertura_turno_offline(
  p_id_turno       bigint,
  p_fecha_apertura timestamptz
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_id_tienda   bigint;
  v_id_tpv      bigint;
  v_id_vendedor bigint;
  v_ok          boolean;
begin
  select t.id_tienda, ct.id_tpv, ct.id_vendedor
    into v_id_tienda, v_id_tpv, v_id_vendedor
  from app_dat_caja_turno ct
  join app_dat_tpv t on t.id = ct.id_tpv
  where ct.id = p_id_turno;

  if v_id_tienda is null then
    return jsonb_build_object('status', 'error', 'error_code', 'TURNO_NOT_FOUND');
  end if;

  perform public.check_user_has_access_to_tienda(v_id_tienda);

  perform pg_advisory_xact_lock(
    hashtextextended(format('apertura_turno:%s:%s', v_id_tpv, v_id_vendedor), 0)
  );

  v_ok := public.fn_turno_alinear_fecha_apertura(p_id_turno, p_fecha_apertura);

  return jsonb_build_object(
    'status', 'success',
    'alineado', v_ok,
    'fecha_apertura', (select fecha_apertura from app_dat_caja_turno where id = p_id_turno)
  );
end;
$$;

revoke all on function public.fn_alinear_apertura_turno_offline(bigint, timestamptz)
  from public, anon;
grant execute on function public.fn_alinear_apertura_turno_offline(bigint, timestamptz)
  to authenticated;
```

#### S3. `fn_apertura_turno_offline`: candado, acceso y alineación en todas las ramas

Misma firma y mismo retorno que la actual: `_usd` y `_monedas` la envuelven y no cambian.
Cambios respecto a la versión en main:

1. Valida el acceso a la tienda. Hoy no valida nada y `anon` puede ejecutarla.
2. `pg_advisory_xact_lock` por TPV y vendedor. La segunda llamada simultánea espera a que
   la primera haga commit y entonces ve su idempotencia o su turno abierto. Corrige C2.
3. En las **tres** ramas (idempotente, reutilizar, crear) se aplica la apertura con S1.
   Corrige C1.

```sql
create or replace function public.fn_apertura_turno_offline(
  p_client_uuid       uuid,
  p_efectivo_inicial  numeric,
  p_id_tpv            bigint,
  p_id_vendedor       bigint,
  p_usuario           uuid,
  p_maneja_inventario boolean default false,
  p_productos         jsonb   default '[]'::jsonb,
  p_observaciones     text    default null,
  p_fecha_apertura    timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing      bigint;
  v_turno_abierto bigint;
  v_new_id        bigint;
  v_id_tienda     bigint;
begin
  select t.id_tienda into v_id_tienda from app_dat_tpv t where t.id = p_id_tpv;
  if v_id_tienda is null then
    return jsonb_build_object('status', 'error', 'error_code', 'TPV_NOT_FOUND',
                              'message', 'El TPV no existe');
  end if;
  perform public.check_user_has_access_to_tienda(v_id_tienda);

  -- Serializa aperturas del mismo TPV + vendedor (dos syncs a la vez).
  perform pg_advisory_xact_lock(
    hashtextextended(format('apertura_turno:%s:%s', p_id_tpv, p_id_vendedor), 0)
  );

  select id_operacion into v_existing
  from app_dat_operacion_offline_idempotencia
  where client_uuid = p_client_uuid and tipo = 'apertura_turno';

  if v_existing is not null then
    if exists (select 1 from app_dat_caja_turno where id = v_existing and estado = 1) then
      perform public.fn_turno_alinear_fecha_apertura(v_existing, p_fecha_apertura);
      return jsonb_build_object('status', 'success', 'id_turno', v_existing,
                                'idempotent', true);
    end if;

    delete from app_dat_operacion_offline_idempotencia
    where client_uuid = p_client_uuid and tipo = 'apertura_turno';
  end if;

  select id into v_turno_abierto
  from app_dat_caja_turno
  where id_tpv = p_id_tpv and id_vendedor = p_id_vendedor and estado = 1
  order by fecha_apertura desc nulls last
  limit 1;

  if v_turno_abierto is not null then
    insert into app_dat_operacion_offline_idempotencia
      (client_uuid, id_operacion, tipo, uuid_usuario)
    values (p_client_uuid, v_turno_abierto, 'apertura_turno', p_usuario)
    on conflict (client_uuid) do nothing;

    -- ANTES: se reutilizaba sin tocar la fecha → apertura = hora del sync.
    perform public.fn_turno_alinear_fecha_apertura(v_turno_abierto, p_fecha_apertura);

    return jsonb_build_object('status', 'success', 'id_turno', v_turno_abierto,
                              'idempotent', true,
                              'message', 'Turno ya estaba abierto; reutilizado');
  end if;

  v_new_id := public.registrar_apertura_turno_v3(
    p_efectivo_inicial  := p_efectivo_inicial,
    p_id_tpv            := p_id_tpv,
    p_id_vendedor       := p_id_vendedor,
    p_usuario           := p_usuario,
    p_maneja_inventario := p_maneja_inventario,
    p_productos         := p_productos,
    p_observaciones     := p_observaciones
  );

  if v_new_id is not null then
    insert into app_dat_operacion_offline_idempotencia
      (client_uuid, id_operacion, tipo, uuid_usuario)
    values (p_client_uuid, v_new_id, 'apertura_turno', p_usuario)
    on conflict (client_uuid) do nothing;

    -- Mismos límites que al reutilizar (no futuro, no solapar al anterior).
    perform public.fn_turno_alinear_fecha_apertura(v_new_id, p_fecha_apertura);
  end if;

  return jsonb_build_object('status', 'success', 'id_turno', v_new_id,
                            'idempotent', false);
end;
$$;

revoke execute on function public.fn_apertura_turno_offline(
  uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz) from anon;
revoke execute on function public.fn_apertura_turno_offline_usd(
  uuid, numeric, bigint, bigint, uuid, boolean, jsonb, text, timestamptz, numeric) from anon;
revoke execute on function public.fn_apertura_turno_offline_monedas(
  uuid, bigint, bigint, uuid, boolean, jsonb, jsonb, text, timestamptz) from anon;
```

> Ojo con el `revoke ... from anon`: hoy las tres son ejecutables por `anon`. La app
> siempre llama autenticada (el sync hace `ensureAuthenticated` antes), así que no
> debería romper nada. Si algún flujo llamara sin sesión, fallará con *permission
> denied*: verificar en staging.

#### S4. `fn_cerrar_turno_offline`: turno del usuario y fecha acotada

Cambios:

1. Elige el turno abierto con `creado_por = p_usuario`, igual que `fn_cerrar_turno_tpv`.
   Hoy toma el último turno abierto **del TPV**: con dos vendedores (TPV 249) la
   idempotencia y el `UPDATE fecha_cierre` pueden caer en el turno del otro.
2. `fecha_cierre` acotada a `[fecha_apertura, now()]`: nunca futura (C5) ni anterior a
   la apertura.

`_usd` y `_monedas` la envuelven; misma firma.

```sql
create or replace function public.fn_cerrar_turno_offline(
  p_client_uuid   uuid,
  p_id_tpv        bigint,
  p_efectivo_real numeric,
  p_usuario       uuid,
  p_productos     jsonb default '[]'::jsonb,
  p_observaciones text  default null,
  p_fecha_cierre  timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_existing       bigint;
  v_ok             boolean;
  v_turno_abierto  bigint;
  v_fecha_apertura timestamptz;
begin
  select id_operacion into v_existing
  from app_dat_operacion_offline_idempotencia
  where client_uuid = p_client_uuid and tipo = 'cierre_turno';

  if v_existing is not null then
    return jsonb_build_object('status', 'success', 'idempotent', true,
                              'message', 'Cierre ya procesado');
  end if;

  -- Mismo criterio que fn_cerrar_turno_tpv (creado_por = p_usuario).
  select id, fecha_apertura into v_turno_abierto, v_fecha_apertura
  from app_dat_caja_turno
  where id_tpv = p_id_tpv and estado = 1 and creado_por = p_usuario
  order by fecha_apertura desc nulls last, id desc
  limit 1;

  if v_turno_abierto is null then
    return jsonb_build_object('status', 'success', 'idempotent', true,
                              'message', 'No hay turno abierto; nada que cerrar');
  end if;

  v_ok := public.fn_cerrar_turno_tpv(
    p_id_tpv        := p_id_tpv,
    p_efectivo_real := p_efectivo_real,
    p_usuario       := p_usuario,
    p_productos     := p_productos,
    p_observaciones := p_observaciones
  );

  if v_ok then
    insert into app_dat_operacion_offline_idempotencia
      (client_uuid, id_operacion, tipo, uuid_usuario)
    values (p_client_uuid, v_turno_abierto, 'cierre_turno', p_usuario)
    on conflict (client_uuid) do nothing;

    if p_fecha_cierre is not null then
      update app_dat_caja_turno
         set fecha_cierre = greatest(v_fecha_apertura, least(p_fecha_cierre, now()))
       where id = v_turno_abierto;
    end if;

    return jsonb_build_object('status', 'success', 'idempotent', false);
  end if;

  return jsonb_build_object('status', 'error',
                            'message', 'El servidor rechazó el cierre del turno');
end;
$$;
```

#### S5. `fn_registrar_venta_offline_v4`: no aceptar ventas con fecha futura

Es la RPC que usa el build instalado. Único cambio funcional:
`created_at = least(p_fecha_creacion, now())`. Así una venta no puede quedar después del
cierre real del turno por culpa del reloj (C5).

```sql
create or replace function public.fn_registrar_venta_offline_v4(
  p_client_uuid      uuid,
  p_id_tpv           bigint,
  p_uuid             uuid,
  p_productos        jsonb,
  p_codigo_promocion text     default null,
  p_denominacion     text     default null,
  p_observaciones    text     default null,
  p_estado_inicial   smallint default 1,
  p_id_cliente       bigint   default null,
  p_fecha_creacion   timestamptz default null,
  p_pagos            jsonb    default null
) returns jsonb
language plpgsql
security definer
set search_path to 'public', 'pg_catalog'
as $$
declare
  v_existing_op bigint; v_result jsonb; v_op bigint; v_ok boolean;
  v_id_tienda   bigint;
  v_fecha       timestamptz;
begin
  select t.id_tienda into v_id_tienda from public.app_dat_tpv t where t.id = p_id_tpv;
  if v_id_tienda is null then
    return jsonb_build_object('status','error','error_code','TPV_NOT_FOUND',
                              'message','El TPV no existe');
  end if;
  perform public.check_user_has_access_to_tienda(v_id_tienda);

  select i.id_operacion into v_existing_op
  from public.app_dat_operacion_offline_idempotencia i
  where i.client_uuid = p_client_uuid;

  if v_existing_op is not null then
    v_op := v_existing_op;
    v_result := jsonb_build_object('status','success','id_operacion',v_op,'idempotent',true,
                                   'message','Operación ya registrada previamente (idempotente)');
  else
    v_result := public.fn_registrar_venta_v3(p_id_tpv, p_uuid, p_productos, p_codigo_promocion,
                                             p_denominacion, p_observaciones, p_estado_inicial,
                                             p_id_cliente);
    if v_result is null or v_result->>'status' is distinct from 'success' then
      return v_result;
    end if;
    v_op := nullif(v_result->>'id_operacion','')::bigint;
    if v_op is null then
      raise exception 'fn_registrar_venta_v3 no devolvió id_operacion';
    end if;
    insert into public.app_dat_operacion_offline_idempotencia(client_uuid, id_operacion, tipo, uuid_usuario)
    values (p_client_uuid, v_op, 'venta_v4', p_uuid)
    on conflict (client_uuid) do nothing;

    if p_fecha_creacion is not null then
      -- ANTES: se copiaba tal cual (podía quedar en el futuro).
      v_fecha := least(p_fecha_creacion, now());
      update public.app_dat_operaciones     set created_at = v_fecha where id = v_op;
      update public.app_dat_operacion_venta set created_at = v_fecha where id_operacion = v_op;
    end if;
    v_result := v_result || jsonb_build_object('idempotent', false, 'client_uuid', p_client_uuid);
  end if;

  -- Pagos: fn_registrar_pago_venta_v2 es idempotente (reescribe los no liquidados).
  if p_pagos is not null and jsonb_typeof(p_pagos) = 'array' and jsonb_array_length(p_pagos) > 0 then
    v_ok := public.fn_registrar_pago_venta_v2(v_op, p_pagos);
    if not coalesce(v_ok, false) then
      raise exception 'No se pudieron registrar los pagos de la operación %', v_op;
    end if;
    v_result := v_result || jsonb_build_object('pagos_registrados', true);
  end if;

  return v_result;
end;
$$;
```

> Si `fn_registrar_venta_offline_v3` y `fn_registrar_venta_offline` (con
> `p_fecha_creacion`) siguen en uso por builds viejos, aplicarles el mismo `least(..., now())`.
> Los logs del 16 y 17/11 solo muestran v4.

#### S6. Reparar los turnos 3522 y 3533 (escritura en producción)

Lleva la `fecha_apertura` justo antes de la primera venta huérfana de ese vendedor/TPV,
sin pasar del cierre del turno anterior.

> **No toca** `efectivo_esperado` ni `diferencia`. Hoy valen `0` y `85300` en el 3522
> porque se guardaron con el turno vacío. Los reportes por turno (`fn_reporte_ventas_por_turno`,
> resúmenes) recalculan por ventana, así que al mover la apertura las ventas vuelven a
> contar. Si algún reporte lee esas columnas guardadas, hay que recalcularlas con el
> cuadre vigente antes de dar el caso por cerrado.

**Paso 1: vista previa (solo lectura).**

```sql
with t as (
  select ct.id, ct.id_tpv, ct.id_vendedor, ct.fecha_apertura, ct.fecha_cierre,
         (select max(coalesce(p.fecha_cierre, p.fecha_apertura))
            from app_dat_caja_turno p
           where p.id_tpv = ct.id_tpv and p.id_vendedor = ct.id_vendedor
             and p.id <> ct.id and p.fecha_apertura < ct.fecha_apertura) as cierre_previo
  from app_dat_caja_turno ct
  where ct.id in (3522, 3533)
), h as (
  select t.*,
         (select min(o.created_at)
            from app_dat_operaciones o
            join app_dat_operacion_venta ov on ov.id_operacion = o.id
            join app_dat_vendedor vd on vd.uuid = o.uuid
           where ov.id_tpv = t.id_tpv and vd.id = t.id_vendedor
             and o.created_at < t.fecha_apertura
             and o.created_at > coalesce(t.cierre_previo, t.fecha_apertura - interval '24 hours')
         ) as primera_huerfana
  from t
)
select h.*,
       greatest(coalesce(h.cierre_previo + interval '1 millisecond', '-infinity'),
                h.primera_huerfana - interval '1 second') as nueva_apertura,
       (select count(*)
          from app_dat_operaciones o
          join app_dat_operacion_venta ov on ov.id_operacion = o.id
          join app_dat_vendedor vd on vd.uuid = o.uuid
         where ov.id_tpv = h.id_tpv and vd.id = h.id_vendedor
           and o.created_at >= h.primera_huerfana - interval '1 second'
           and o.created_at <= h.fecha_cierre) as ventas_que_quedan_dentro
from h;
```

Valores esperados: 3522 → nueva apertura ≈ 16/11 09:31:02 con 62 ventas dentro; 3533 →
≈ 17/11 14:36:20 con 14 ventas dentro. Si sale algo distinto, **no seguir**.

**Paso 2: aplicar en una transacción.**

```sql
begin;

with t as (
  select ct.id, ct.id_tpv, ct.id_vendedor, ct.fecha_apertura,
         (select max(coalesce(p.fecha_cierre, p.fecha_apertura))
            from app_dat_caja_turno p
           where p.id_tpv = ct.id_tpv and p.id_vendedor = ct.id_vendedor
             and p.id <> ct.id and p.fecha_apertura < ct.fecha_apertura) as cierre_previo
  from app_dat_caja_turno ct
  where ct.id in (3522, 3533)
), h as (
  select t.*,
         (select min(o.created_at)
            from app_dat_operaciones o
            join app_dat_operacion_venta ov on ov.id_operacion = o.id
            join app_dat_vendedor vd on vd.uuid = o.uuid
           where ov.id_tpv = t.id_tpv and vd.id = t.id_vendedor
             and o.created_at < t.fecha_apertura
             and o.created_at > coalesce(t.cierre_previo, t.fecha_apertura - interval '24 hours')
         ) as primera_huerfana
  from t
)
update app_dat_caja_turno ct
   set fecha_apertura = greatest(coalesce(h.cierre_previo + interval '1 millisecond', '-infinity'),
                                 h.primera_huerfana - interval '1 second')
  from h
 where ct.id = h.id
   and h.primera_huerfana is not null
returning ct.id, ct.fecha_apertura;

-- Repetir aquí la consulta 1 de la sección 5 filtrando id_tpv = 249:
-- "fuera_de_todo_turno" debe bajar de 76 a 0.

commit;   -- o rollback; si algo no cuadra
```

#### S7. Monitoreo (diario, solo lectura)

```sql
-- Debe devolver 0 filas. Si aparecen, hay un caso nuevo.
with ventas as (
  select o.id, o.created_at, o.uuid, ov.id_tpv
  from app_dat_operaciones o
  join app_dat_operacion_venta ov on ov.id_operacion = o.id
  join app_dat_operacion_offline_idempotencia i on i.id_operacion = o.id
  where o.created_at >= now() - interval '2 days'
)
select v.id_tpv, count(*) as ventas_huerfanas, min(v.created_at), max(v.created_at)
from ventas v
where not exists (
  select 1 from app_dat_caja_turno ct
  join app_dat_vendedor vd on vd.id = ct.id_vendedor
  where ct.id_tpv = v.id_tpv and vd.uuid = v.uuid
    and v.created_at >= ct.fecha_apertura
    and v.created_at <= coalesce(ct.fecha_cierre, now())
)
group by v.id_tpv;

-- Ventas o cierres con fecha futura (reloj o zona horaria mal): debe dar 0.
select count(*) from app_dat_operaciones where created_at > now() + interval '1 minute';
select count(*) from app_dat_caja_turno  where fecha_cierre > now() + interval '1 minute';
```

---

### 6.3 Cambios en Dart (`ventiq_app`)

Las líneas son del repo actual (rama `multimoneda`, 18/11).

#### D1. Enviar siempre las fechas en UTC con `Z` (corrige C5)

**Archivo:** `lib/services/auto_sync_service.dart`

**Por qué:** hoy se mandan textos como `2026-11-17T14:29:51.000`, sin offset, y Postgres
los lee como hora de La Habana. Si la zona del teléfono no es la de Cuba, quedan
desplazados. Convirtiendo **al enviar** también se arreglan las entradas que ya están en
cola: se guardaron como hora local del teléfono, `DateTime.tryParse` las vuelve a leer
como locales y `toUtc()` da el instante correcto.

**1. Añadir el helper** (junto a `_parseTurnoId`, ~línea 875):

```dart
  /// Instante para parámetros `timestamptz` de las RPC offline.
  ///
  /// Las fechas de la cola se guardan con `toIso8601String()` de un DateTime
  /// local, que no lleva offset. Postgres (TimeZone=America/Havana) las leía como
  /// hora de La Habana y, con el teléfono en otra zona, quedaban desplazadas.
  /// Se reenvían como UTC con `Z`.
  String? _fechaUtcParaRpc(dynamic raw) {
    if (raw == null) return null;
    final dt = raw is DateTime ? raw : DateTime.tryParse(raw.toString());
    return dt?.toUtc().toIso8601String();
  }
```

**2. Apertura** (líneas 1400-1401):

```dart
    // ANTES
    final fechaApertura =
        entry['fecha_apertura'] ?? aperturaData['fecha_apertura'];
    // DESPUÉS
    final fechaApertura = _fechaUtcParaRpc(
      entry['fecha_apertura'] ?? aperturaData['fecha_apertura'],
    );
```

**3. Cierre** (`tryCierreRpc`, líneas 2394-2397):

```dart
    // ANTES
      final fecha =
          withFecha
              ? (cierreData['fecha_cierre'] ?? latest['fecha_cierre'])
              : null;
    // DESPUÉS
      final fecha =
          withFecha
              ? _fechaUtcParaRpc(
                cierreData['fecha_cierre'] ?? latest['fecha_cierre'],
              )
              : null;
```

**4. Venta** (`_registerSaleInSupabase`, líneas 4265-4266):

```dart
    // ANTES
      'p_fecha_creacion':
          orderData['fecha_creacion'] ?? orderData['created_offline_at'],
    // DESPUÉS
      'p_fecha_creacion': _fechaUtcParaRpc(
        orderData['fecha_creacion'] ?? orderData['created_offline_at'],
      ),
```

*Opcional:* guardar ya en UTC donde se crean (`apertura_screen.dart:2643/2647`,
`checkout_screen.dart:2281/2292`, `preorder_screen*.dart`, `cierre_screen.dart:3548/3552`)
con `nowServerCorrected.toUtc().toIso8601String()`. No es imprescindible si se aplica D1.

#### D2. Alinear la apertura cada vez que se reutiliza un turno abierto (corrige C1 en cliente)

**Archivo:** `lib/services/auto_sync_service.dart`

**Por qué:** `_ensureAperturaForQueueEntryUnlocked` tiene tres salidas que reutilizan un
turno ya abierto **sin llamar a la RPC de apertura**, así que S3 no las cubre:

- `server_id` guardado y sigue abierto (1272-1282);
- `alreadyOpen` (1350-1362);
- reutilizar tras un fallo de la RPC (1554-1561).

Además, 1575-1584 hace un `update` directo de `fecha_apertura` sin límites (puede poner
una fecha futura o pisar el turno anterior).

**1. Añadir el helper** (debajo de `_fechaUtcParaRpc`):

```dart
  /// Lleva `fecha_apertura` del turno del servidor a la apertura offline real
  /// cuando el turno se reutilizó y quedó con la hora del sync. El servidor
  /// valida: solo hacia atrás, nunca futura, sin pisar el turno anterior.
  Future<void> _alinearFechaAperturaEnServidor(
    int serverId,
    Map<String, dynamic> entry,
  ) async {
    final aperturaRaw = entry['apertura'];
    final fecha = _fechaUtcParaRpc(
      entry['fecha_apertura'] ??
          (aperturaRaw is Map ? aperturaRaw['fecha_apertura'] : null),
    );
    if (fecha == null) return;
    try {
      final resp = await Supabase.instance.client.rpc(
        'fn_alinear_apertura_turno_offline',
        params: {'p_id_turno': serverId, 'p_fecha_apertura': fecha},
      );
      print('[TURNO_SYNC] 🕒 alinear apertura $serverId ← $fecha: $resp');
    } catch (e) {
      if (_isRpcUnavailable(
        e,
        functionName: 'fn_alinear_apertura_turno_offline',
      )) {
        print('[TURNO_SYNC] ⚠️ fn_alinear_apertura_turno_offline no desplegada');
        return;
      }
      print('[TURNO_SYNC] ⚠️ No se pudo alinear apertura de $serverId: $e');
    }
  }
```

**2. Llamarlo en las salidas de reutilización:**

```dart
      if (estado == 1) {
        print('[TURNO_SYNC] ✅ reutiliza server_id=$existingId (sigue abierto)');
        // ...
        await _ensureEntryHasUsuario(entry, aperturaDataEarly, localId);
        await _clearStaleFechaCierre(existingId);
        await _alinearFechaAperturaEnServidor(existingId, entry); // NUEVO
        return existingId;
      }
```

```dart
    if (alreadyOpenId != null) {
      // ...
      await _ensureEntryHasUsuario(entry, aperturaData, localId);
      await _clearStaleFechaCierre(alreadyOpenId);
      await _alinearFechaAperturaEnServidor(alreadyOpenId, entry); // NUEVO
      return alreadyOpenId;
    }
```

```dart
        if (existingOpenId != null) {
          // ...
          aperturaOk = true;
          serverId = existingOpenId;
          await _alinearFechaAperturaEnServidor(existingOpenId, entry); // NUEVO
        }
```

**3. Reemplazar el `update` directo** (1575-1584):

```dart
    // ANTES
      if (online != null && fechaApertura != null && serverId != null) {
        try {
          await Supabase.instance.client
              .from('app_dat_caja_turno')
              .update({'fecha_apertura': fechaApertura})
              .eq('id', serverId!);
        } catch (e) {
          print('  ⚠️ No se pudo alinear fecha_apertura: $e');
        }
      }
    // DESPUÉS
      if (online != null && serverId != null) {
        await _alinearFechaAperturaEnServidor(serverId!, entry);
      }
```

#### D3. Serializar las aperturas por TPV + vendedor (corrige C2 en cliente)

**Archivo:** `lib/services/auto_sync_service.dart`, `_ensureAperturaForQueueEntry`
(1227-1247).

**Por qué:** el candado actual (`_aperturaInFlight`) va por `local_id`. Dos entradas de
cola distintas para el mismo turno real (duplicadas, o una hidratada desde
`pending_operations`) abren en paralelo, y eso es lo que se ve en los logs. Se encadenan
por TPV + vendedor: la segunda espera a la primera, que ya habrá dejado el turno abierto
y la idempotencia. Solo protege dentro de un isolate; la garantía real es el candado de
S3.

```dart
  // NUEVO (campo de la clase, junto a _aperturaInFlight)
  final Map<String, Future<void>> _aperturaPorTpv = {};

  Future<T> _encadenarAperturaPorTpv<T>(
    String clave,
    Future<T> Function() tarea,
  ) {
    final previa = _aperturaPorTpv[clave] ?? Future<void>.value();
    final actual = previa.then((_) => tarea());
    final marca = actual.then<void>((_) {}, onError: (_) {});
    _aperturaPorTpv[clave] = marca;
    return actual.whenComplete(() {
      if (identical(_aperturaPorTpv[clave], marca)) {
        _aperturaPorTpv.remove(clave);
      }
    });
  }
```

```dart
    // ANTES (línea 1240)
    final future = _ensureAperturaForQueueEntryUnlocked(entry);
    // DESPUÉS
    final aperturaRaw = entry['apertura'];
    final apertura = aperturaRaw is Map ? aperturaRaw : const {};
    final clave =
        '${entry['id_tpv'] ?? apertura['id_tpv']}:'
        '${entry['id_vendedor'] ?? apertura['id_vendedor']}';
    final future = _encadenarAperturaPorTpv(
      clave,
      () => _ensureAperturaForQueueEntryUnlocked(entry),
    );
```

#### D4. No borrar la copia local mientras el turno siga abierto (corrige C3)

**Archivo:** `lib/services/user_preferences_service.dart`,
`removeSyncedPendingPresentOnServer` (1806-1840).

**Por qué:** es lo que hace que el vendedor "pierda" la venta. La copia local ya
sincronizada se muestra como `ORD-{id_operacion}`, el mismo id que la del servidor, así
que en `loadOrdersForOpenTurnoUnified` no se duplica (el merge es por id y gana el
servidor). Pero si la del servidor queda filtrada, la local es la única que queda. Se
conservan las del turno abierto hasta el cierre, donde ya las purga
`purgeFinalizedSyncedOrdersForTurno`. Esto también cumple lo que promete el comentario
de `markOrdersSyncedById` ("conservadas hasta cierre").

```dart
  Future<int> removeSyncedPendingPresentOnServer(Set<int> serverOpIds) async {
    if (serverOpIds.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_pendingOrdersKey);
    if (json == null) return 0;

    // NUEVO: las del turno que sigue abierto se conservan hasta el cierre.
    final open = await getOpenOfflineTurno();
    final openLocalId = open?['local_id']?.toString();

    final decoded = jsonDecode(json) as List<dynamic>;
    final remaining = <Map<String, dynamic>>[];
    var removed = 0;

    for (final item in decoded) {
      final order = Map<String, dynamic>.from(item as Map);
      final synced = order['synced'] == true;
      final rawOp = order['id_operacion'];
      final opId =
          rawOp is int
              ? rawOp
              : (rawOp is num ? rawOp.toInt() : int.tryParse('$rawOp'));
      final delTurnoAbierto =
          openLocalId != null &&
          order['local_turno_id']?.toString() == openLocalId;

      if (synced &&
          opId != null &&
          serverOpIds.contains(opId) &&
          !delTurnoAbierto) {
        removed++;
        continue;
      }
      remaining.add(order);
    }
    // ... resto igual
  }
```

**Dos ajustes para no duplicar al conservarlas:**

**a.** `order_service.dart`, `loadOrdersFromLocalCacheForOpenTurno` (2300-2304). Esta
ruta suma cache + pendientes sin merge por id:

```dart
    final pending = await userPrefs.getSellerVisiblePendingOrders();
    if (pending.isNotEmpty) {
      // NUEVO: no repetir las que ya vinieron en el cache del servidor.
      final yaListadas = _orders.map((o) => o.id).toSet();
      final nuevas =
          pending.where((p) {
            final op = p['id_operacion'];
            return op is! num || !yaListadas.contains('ORD-${op.toInt()}');
          }).toList();
      addPendingOrdersToList(nuevas);
      print('⏳ Pendientes del turno abierto: ${nuevas.length}');
    }
```

**b.** `user_preferences_service.dart`, `getSellerVisiblePendingOrdersCount` (1690-1692).
El badge de "pendientes" debe contar solo lo que aún no se subió (el FAB ya filtra
`synced != true`):

```dart
  Future<int> getSellerVisiblePendingOrdersCount() async {
    final orders = await getSellerVisiblePendingOrders();
    return orders.where((o) => o['synced'] != true).length;
  }
```

#### D5. No pisar la apertura local con una más tardía del servidor (corrige C4)

**Archivo:** `lib/services/user_preferences_service.dart`, `saveOfflineTurno` (3180-3194).

**Por qué:** si el servidor devuelve el turno con la apertura del sync, la entrada local
pierde la hora real. Con ella se pierde la ventana del pull (A) y la fecha para D2. Para
el **mismo** turno se conserva la más temprana. Si el turno local es otro (`server_id`
distinto), se usa la del servidor, como hoy.

```dart
  // NUEVO helper (privado, en la misma clase)
  static String? _aperturaMasTemprana(dynamic local, dynamic servidor) {
    final l = DateTime.tryParse(local?.toString() ?? '');
    final s = DateTime.tryParse(servidor?.toString() ?? '');
    if (l == null) return servidor?.toString();
    if (s == null) return local?.toString();
    return l.isBefore(s) ? local.toString() : servidor.toString();
  }
```

```dart
    // DENTRO de `if (open != null) { ... }`, antes del upsert:
      final openServerId = open['server_id_turno'];
      final mismoTurno =
          openServerId == null ||
          (incomingId != null && openServerId.toString() == incomingId.toString());

      await upsertOfflineTurno({
        ...open,
        'apertura': mergedApertura,
        // ANTES: 'fecha_apertura': turnoData['fecha_apertura'] ?? open['fecha_apertura'],
        'fecha_apertura':
            mismoTurno
                ? _aperturaMasTemprana(
                  open['fecha_apertura'],
                  turnoData['fecha_apertura'],
                )
                : (turnoData['fecha_apertura'] ?? open['fecha_apertura']),
        // ... resto igual
      });
```

`mergedApertura` también copia `...turnoData` (incluida su `fecha_apertura`) encima de
`open['apertura']`. Añadir después del spread:

```dart
        'fecha_apertura':
            mismoTurno
                ? _aperturaMasTemprana(
                  (open['apertura'] is Map
                      ? (open['apertura'] as Map)['fecha_apertura']
                      : null) ?? open['fecha_apertura'],
                  turnoData['fecha_apertura'],
                )
                : turnoData['fecha_apertura'],
```

(Calcular `mismoTurno` **antes** de construir `mergedApertura`.)

#### D6. No pisar `created_offline_at` (corrige C8)

**Archivo:** `lib/services/user_preferences_service.dart`, `savePendingOrder` (línea 1576).

**Por qué:** el checkout ya manda `created_offline_at` corregido con `ServerTimeService`,
pero aquí se reemplaza con `DateTime.now()` del dispositivo. Ese campo es el respaldo de
`p_fecha_creacion` y del filtro legacy de `getSellerVisiblePendingOrders`.

```dart
    // ANTES
    orderData['created_offline_at'] = DateTime.now().toIso8601String();
    // DESPUÉS
    orderData['created_offline_at'] ??= DateTime.now().toIso8601String();
```

#### D7. Un solo camino de sync en Ajustes (corrige C7)

**Archivo:** `lib/screens/settings_screen.dart`, `_SyncDialog` (tareas en 4014-4027,
switch en 4052-4064).

**Por qué:** los pasos `pending_operations` y `pending_orders` hacen dos cosas mal:

- abren y cierran turnos con `TurnoService.registrarAperturaTurno` /
  `TurnoService.cerrarTurno`, que no son idempotentes y no llevan fecha;
- suben las ventas una a una **antes** de que la cola haya abierto el turno.

El `_ManualSyncDialog` ya hace lo correcto con `forceSyncPendingOrders()`: cola de turnos
en orden, apertura → ventas → egresos → cierre, y después el pull.

```dart
  // ANTES
    {'name': 'Procesando operaciones pendientes', 'key': 'pending_operations'},
    {'name': 'Sincronizando órdenes pendientes', 'key': 'pending_orders'},
  // DESPUÉS
    {'name': 'Sincronizando turnos, ventas y cierres', 'key': 'sync_turno_queue'},
```

```dart
            // ANTES
            case 'pending_operations':
              await _processPendingOperations();
              successfulSteps.add(task['name']!);
              break;
            case 'pending_orders':
              await _processPendingOrders();
              successfulSteps.add(task['name']!);
              break;
            // DESPUÉS
            case 'sync_turno_queue':
              // Cola offline_turnos: hidrata ops legacy de apertura/cierre,
              // abre (idempotente) → ventas → egresos → cierre, y luego baja
              // las órdenes del turno.
              await AutoSyncService().forceSyncPendingOrders();
              successfulSteps.add(task['name']!);
              break;
```

`order_status_change` (que hoy procesa `_processPendingOperations`) ya lo cubre
`forceSyncPendingOrders` → `_syncOrderStatusChanges`. Después de este cambio,
`_processPendingOperations`, `_processAperturaTurno`, `_processCierreTurno`,
`_processPendingOrders`, `_createTurnoFromOffline` y `_processOfflineOrders` quedan sin
uso y se pueden borrar.

---

### 6.4 Pruebas antes de liberar

**Servidor (staging o rama de Supabase):**

1. Dos llamadas simultáneas a `fn_apertura_turno_offline_usd` con distinto
   `client_uuid` y el mismo TPV/vendedor → un solo turno, con `fecha_apertura` =
   `p_fecha_apertura`.
2. Reutilizar un turno abierto a las 10:00 con `p_fecha_apertura` a las 08:00 → queda
   a las 08:00. Con 07:00 y un cierre previo a las 07:30 → queda a las 07:30:00.001.
3. `p_fecha_apertura` / `p_fecha_creacion` / `p_fecha_cierre` 1 h en el futuro → quedan
   en `now()`.
4. TPV con dos vendedores y los dos turnos abiertos: el cierre offline de uno no toca el
   turno del otro.

**App (dispositivo de prueba, zona horaria del teléfono en UTC-4 y reloj ajustado a mano
para mostrar la hora de Cuba):**

1. Abrir turno offline a las HH:00, vender a HH:10 y HH:20, sincronizar a HH:40:
   `fecha_apertura` = HH:00 y las ventas siguen en la lista antes y después del pull.
2. Lo mismo, con el turno ya abierto online antes de pasar a offline: la reutilización
   alinea la apertura.
3. Sync desde Ajustes (`_SyncDialog`) y desde el diálogo manual: mismo resultado y una
   sola llamada de apertura en los logs.
4. Offline con cache fresco y offline con cache vacío (regla del proyecto): las ventas
   del turno abierto siguen visibles; sin turno abierto, la lista está vacía.
5. Cerrar el turno: las copias locales sincronizadas se purgan
   (`purgeFinalizedSyncedOrdersForTurno`) y no quedan duplicadas en el siguiente turno.
6. Monitoreo S7 en 0 durante una semana.

---

## 7. Rama `multimoneda` y proyecto newa

El seguimiento está en `docs/plan-multimoneda/m01_orden_aplicacion.md`, sección
"R33 — ventas offline fuera de su turno":

- **SQL para newa:** `docs/plan-multimoneda/m01_r33_turno_offline_fecha_propuesta.sql`
  (script 56) + `verificar_m01_r33.sql`. En newa ya están vivos los scripts M01 14 y 17,
  que reescriben apertura, cierre y venta offline. S2–S5 de esta sección **no se aplican
  en newa**: el script 56 lleva los mismos cambios sobre esos cuerpos y conserva la huella
  M01.
- **Diferencias del código de `multimoneda` con la sección 6.3** (las líneas citadas
  arriba son del código analizado primero):
  - D2: el `update({'fecha_apertura': ...})` directo ya no existe. Hoy ninguna rama de
    reutilización corrige la fecha. La llamada a `_alinearFechaAperturaEnServidor` va
    también en el bloque `if (serverId == null)` (1619-1625).
  - D7: `pending_operations` ya omite apertura/cierre. Solo falta sustituir el paso
    `pending_orders`.
  - Resto (D1, D3, D4, D5, D6): pendientes, con las líneas actualizadas en la spec.
- **newa está en `TimeZone = UTC`** (main en `America/Havana`). Sin D1, las fechas
  offline enviadas sin offset quedan 5 h antes de la hora real en newa.
