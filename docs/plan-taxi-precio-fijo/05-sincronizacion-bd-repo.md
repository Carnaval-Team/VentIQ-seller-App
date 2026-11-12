# 05 · Sincronización BD real ↔ repositorio

> **Motivo**: los `.sql` del repo y la base de datos de producción no coinciden. Antes de escribir la migración del taxi hay que fijar una línea base fiel, o la migración nueva se apoyaría en objetos que no existen (o duplicaría los que existen con otra firma).
> **Método**: inventario por SQL contra el proyecto de producción `vsieeihstajlrdvpuooh` el **2026-11-12**, comparado con `inventtia_muevete/docs/migrations/*.sql`. Nada se aplicó: solo lectura.
> **Resultado**: se versionó lo que faltaba en `030_baseline_sync_produccion.sql`.

---

## 1. Cómo se verificó

| Consulta | Para qué |
|---|---|
| `pg_proc` + `pg_namespace` (`nspname='muevete'`) | inventario de funciones, firmas, `prosecdef`, `proconfig` |
| `pg_trigger` (`NOT tgisinternal`) | triggers reales (incluidos los de `pg_net`) |
| `pg_views` + `pg_get_viewdef` | vistas y su definición exacta |
| `pg_policies` | 118 políticas en `muevete` |
| `pg_extension` | PostGIS **no** instalado |
| `pg_publication_tables` | tablas publicadas en realtime |
| `information_schema.columns` | columnas reales de las tablas críticas |
| `vault.secrets` | secretos disponibles para reconstruir triggers sin hardcodear |

También se comparó contra el proyecto de desarrollo `qhprswhhfasrikhawjoz`. **Tiene el mismo conjunto en `muevete`**, más copias duplicadas de `complete_ride_payment` en el esquema `public` que producción también arrastra.

---

## 2. Delta encontrado

### 2.1 Existe en producción, NO estaba en el repo

| Objeto | Firma | Estado |
|---|---|---|
| `muevete.get_my_driver_id` | `() → bigint`, `STABLE SECURITY DEFINER` | **faltaba** → añadido en `030` |
| `muevete.complete_ride_payment` | `(text, uuid, bigint, bigint, numeric)` — 5 args | **faltaba** (el repo solo tiene la de 6) → añadida en `030` como wrapper deprecado |
| `notificaciones_push` | trigger `AFTER INSERT` → `supabase_functions.http_request` | **faltaba** → añadido en `030` |
| `solicitudes_push` | ídem sobre `solicitudes_transporte` | **faltaba** → añadido en `030` |
| `ofertas_push` | ídem sobre `ofertas_chofer` | **faltaba** → añadido en `030` (deprecado con el flujo nuevo) |

### 2.2 Existe en producción y SÍ estaba en el repo

`complete_ride_payment` (6 args) · `fn_aprobar_solicitud_plan` · `fn_cambiar_estado_carga` · `fn_crear_suscripcion_gratis` · `fn_crear_suscripcion_trial` · `fn_marcar_carga_tomada` · `fn_proximo_dia_2` · `fn_rechazar_solicitud_plan` · `fn_registrar_perfil_driver` · `is_superadmin` · `set_updated_at` · vistas `v_cargas_estado_actual` y `v_cargas_con_nomencladores`.

### 2.3 Existe en producción, NO se versiona (deuda declarada)

| Objeto | Decisión |
|---|---|
| `public.complete_ride_payment` ×2 | copias legacy fuera de `muevete`; no se recrean; `DROP` documentado para después de verificar que nadie las llama |
| `supabase_functions.http_request` | función de la plataforma Supabase, no del proyecto |

### 2.4 Realtime: producción y desarrollo NO están iguales ⚠️

Medido en `pg_publication` + `pg_publication_tables` en ambos proyectos:

| Proyecto | `supabase_realtime` contiene |
|---|---|
| **Producción** `vsieeihstajlrdvpuooh` | `muevete.notificaciones`, `muevete.ofertas_chofer`, `muevete.place`, `muevete.solicitudes_transporte`, `muevete.vehicle_type`, `muevete.viajes`, `flow.*`, `carnavalapp.*`, `public.app_dat_notificaciones` |
| **Desarrollo** `qhprswhhfasrikhawjoz` | **solo** `flow.agenda`, `flow.notificaciones` — **ninguna tabla de `muevete`** |

Consecuencia: si se prueba H1–H3 en desarrollo, el chofer **no recibirá** el viaje publicado y el cliente no verá la asignación, y parecerá un bug del código cuando es configuración de entorno.

**Acción obligatoria de H0 (entorno de desarrollo):**

```sql
alter publication supabase_realtime add table
  muevete.solicitudes_transporte,
  muevete.viajes,
  muevete.place,
  muevete.notificaciones,
  muevete.vehicle_type,
  muevete.ofertas_chofer;   -- legacy, se retirará en el cutover
```

En producción **no hay que añadir nada**: ya está publicado. Las tablas nuevas (`zonas_tarifa`, `tarifas_municipio`, `configuracion_tarifas`) **no necesitan** realtime: el precio se congela al crear la solicitud y el superadmin refresca al abrir la pantalla. Si más adelante se quiere editar tarifa en vivo, se publican entonces.

---

## 3. Deuda de seguridad detectada en el baseline

Los triggers de push de producción llevan el **JWT de `service_role` escrito literalmente** dentro de la definición del trigger. Cualquiera con acceso al catálogo (`pg_trigger`) puede leerlo: es una credencial con permisos totales sobre la base de datos.

- El baseline `030` reconstruye los triggers leyendo la clave desde **Vault** (`wapi_service_role_key`, `wapi_supabase_url`, que ya existen en el proyecto).
- **No se recrean en producción** (el bloque `DO` solo crea si no existen), así que el token viejo sigue ahí.
- Recomendación: rotar la `service_role` key y recrear los tres triggers desde el baseline con el secreto en Vault. Eso es una tarea aparte de este plan (afecta a todas las apps, no solo a Muevete).

---

## 4. Consecuencias para la migración del taxi

1. La numeración nueva empieza en **031**; `030` es el baseline.
2. `fn_completar_viaje` (H1) **no puede asumir** que `complete_ride_payment` es la única función de cierre: hay dos sobrecargas vivas y apps viejas llamando a ambas. Se mantienen hasta el cutover y se marcan deprecadas.
3. `get_my_driver_id()` ya existe: usarla en las RPC nuevas en lugar de repetir el `SELECT ... FROM drivers WHERE uuid = auth.uid()`.
4. Los triggers de push disparan en INSERT sobre `solicitudes_transporte`: la nueva publicación de viaje los aprovechará sin tocarlos, pero el payload tendrá que ajustarse al nuevo formato ("viaje disponible: $X, te tocan $Y") en la Edge Function `send-push-notification`.

---

## 5. Comandos para re-verificar antes de desplegar

```sql
-- 1. Funciones reales en muevete (esperado 14 filas)
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args, p.prosecdef
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'muevete' ORDER BY 1, 2;

-- 2. Triggers no internos (esperado 4)
SELECT c.relname, t.tgname
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'muevete' AND NOT t.tgisinternal ORDER BY 1, 2;

-- 3. Objetos que la migración del taxi va a crear NO deben existir todavía
SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'muevete'
  AND proname IN ('fn_cotizar_viaje','fn_crear_solicitud','fn_tomar_viaje',
                  'fn_viajes_disponibles','fn_completar_viaje','fn_zona_de_punto',
                  'fn_punto_en_poligono','fn_cancelar_solicitud','fn_recargar_wallet');
-- esperado: 0 filas

-- 4. Tablas nuevas tampoco deben existir
SELECT tablename FROM pg_tables
WHERE schemaname='muevete' AND tablename IN ('zonas_tarifa','tarifas_municipio','configuracion_tarifas');
-- esperado: 0 filas
```