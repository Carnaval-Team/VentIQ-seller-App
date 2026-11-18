# 06 · Cómo aplicar las migraciones

> 🛑 **NO EJECUTAR TODAVÍA.** Este documento es la guía *para cuando el plan se apruebe*. Nada se ha aplicado: ni en `newa` ni en producción. Los `.sql` son borradores y están en [`propuesta-migraciones/`](propuesta-migraciones/), no en la carpeta real de migraciones.
>
> 🔴 **Cuando llegue el momento**, antes de aplicar en producción: existe un incidente P0 abierto (clave `service_role` de producción embebida en 6 apps y repositorio público). Ver [`10-incidente-credenciales.md`](10-incidente-credenciales.md). **H0-A va antes que todo.**
>
> **Por qué este documento**: los servidores MCP de Supabase están configurados en **solo lectura** (`.mcp.json` → `read_only=true`), tanto para `supabase-newa` (dev) como para `supabase-main` (prod). El agente **no puede ejecutar DDL**. La aplicación es manual, en el SQL Editor del proyecto o con el CLI.
>
> **Proyecto de pruebas**: `newa` = `qhprswhhfasrikhawjoz` (desarrollo). Producción `vsieeihstajlrdvpuooh` no se toca sin autorización explícita.

---

## 0. Orden completo (no solo H0)

| Fase | Archivos | Estado | Dónde se aplica |
|---|---|---|---|
| **H0-A** credenciales | rotación de clave + `lib/config/supabase_config.dart` de 6 apps + repo privado | ⛔ bloqueado por decisión del usuario (corte inmediato vs 72 h) | dashboard + código |
| **H0** datos y tarifas | `030` → `031` → `032` → `033` → `034` | ✅ escritos y verificados | `newa` primero |
| **H1** identidad y vehículos | `035` → `036` | ✅ escritos (255 + 1 088 líneas) | `newa` |
| **H2** seguridad | `037` | ⏳ pendiente | `newa` |
| **H3** RPCs de precio | `038` → `039` → `040` | ⏳ pendiente | `newa` |
| Cutover | `041` hardening de RLS | ⏳ pendiente | **solo producción, en la ventana de corte** |

> `041` **nunca** se aplica antes de que las apps nuevas estén publicadas: revoca las políticas que las apps actuales necesitan.

---

## 1. Precondiciones

1. Tener acceso al SQL Editor del proyecto `newa`.
2. Confirmar el punto de partida (todo debe dar 0 filas):

```sql
select tablename from pg_tables
where schemaname='muevete'
  and tablename in ('zonas_tarifa','tarifas_municipio','configuracion_tarifas');

select proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='muevete'
  and proname in ('fn_cotizar_viaje','fn_zona_de_punto','fn_punto_en_poligono',
                  'fn_crear_solicitud','fn_tomar_viaje','fn_viajes_disponibles',
                  'fn_completar_viaje','fn_cancelar_solicitud','fn_recargar_wallet');
```

3. Opcional pero recomendado: anotar el `count(*)` de `solicitudes_transporte` (55) y `viajes` (44) antes de empezar, para comparar después.

---

## 2. Orden de aplicación (obligatorio)

Ejecutar **archivo por archivo**, esperando el `Success` de cada uno. No pegar los cinco de golpe.

| # | Archivo | Qué hace | Efecto esperado |
|---|---|---|---|
| 1 | `030_baseline_sync_produccion.sql` | Versiona lo que ya existía en prod y faltaba en el repo | En `newa` debe ser **no-op** (los objetos ya existen). Si crea algo, es que faltaba |
| 2 | `031_taxi_zonas_tarifas.sql` | 3 tablas nuevas, `multiplicador_tarifa`, 13 columnas snapshot, triggers, índices | Crea 3 tablas y añade columnas. No borra nada |
| 3 | `032_taxi_geo_y_cotizacion.sql` | `fn_punto_en_anillo`, `fn_haversine_km`, `fn_punto_en_poligono`, `fn_zona_de_punto`, `fn_cotizar_viaje` | 5 funciones nuevas |
| 4 | `033_taxi_seed_santa_clara.sql` | Config global, tarifas municipales, 7 multiplicadores, zonas MUN/FB/Z1–Z9 | Inserta/actualiza datos de tarifa |
| 5 | `034_taxi_rls_tarifas.sql` | RLS y grants de las 3 tablas nuevas | Políticas nuevas |
| 6 | `035_taxi_vehiculos_catalogo.sql` | `orden`, `nombre_ui`, `pasajeros_max`; ocultar bicicleta/camioneta; `solicitudes.pasajeros`; `fn_capacidad_vehiculo`; vista `v_catalogo_vehiculos` | 3 columnas nuevas y 1 vista; `tuktuk` pasa a mostrarse como "Triciclo Eléctrico" |
| 7 | `036_taxi_identidad_consentimiento.sql` | `poblado`/`ci`/`direccion`/`kyc_estado`; `documentos_legales`; `consentimientos`; `configuracion_identidad`; `fn_usuario_habilitado` y compañía | 3 tablas nuevas y el gate de identidad |

> Los pasos 6 y 7 son de **H1**. No los ejecutes en producción hasta que la app nueva esté lista: cambian el gate de operación y dejan a los 41 usuarios actuales en "perfil incompleto" (pueden entrar, no operar).

> Atajo: `docs/plan-taxi-precio-fijo/sql/APPLY_dev_030_034.sql` contiene los cinco concatenados en orden (1 820 líneas). Útil solo si tu cliente SQL maneja bien scripts largos; si uno falla, es más difícil saber cuál.

---

## 3. Verificación después de cada paso

### Tras 031

```sql
select tablename from pg_tables
where schemaname='muevete' and tablename in ('zonas_tarifa','tarifas_municipio','configuracion_tarifas');
-- esperado: 3 filas

select column_name, data_type from information_schema.columns
where table_schema='muevete' and table_name='solicitudes_transporte'
  and column_name in ('driver_id','zona_id','precio_plataforma','comision_pct',
                      'precio_chofer','tarifa_detalle','tarifa_modo','moneda','aceptada_at');
-- esperado: 9 (o 13 si se aceptaron los timestamps del desvío D-02)

select column_name, data_type from information_schema.columns
where table_schema='muevete' and table_name='viajes' and column_name in ('solicitud_id','driver_id');
-- driver_id debe ser bigint

select trigger_name from information_schema.triggers
where trigger_schema='muevete' and event_object_table='solicitudes_transporte';
-- esperado: incluye trg_solicitud_guarda
```

### Tras 032

```sql
select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='muevete'
  and proname in ('fn_punto_en_anillo','fn_haversine_km','fn_punto_en_poligono','fn_zona_de_punto','fn_cotizar_viaje')
order by 1;
-- esperado: 5 filas
```

Prueba funcional del cálculo (debe dar 1 500 para auto en el centro de Santa Clara):

```sql
select muevete.fn_cotizar_viaje(
  22.40689, -79.96450,   -- origen: Parque Vidal
  22.40900, -79.96000,   -- destino: ~0,5 km en línea recta
  (select id from muevete.vehicle_type where lower(tipo) = 'auto'),
  now(),
  3.3,                   -- km de ruta declarados (la función los acota)
  'Villa Clara', 'Santa Clara'
) ->> 'precio_plataforma';
-- esperado: 1500 (tarifa municipal fija; km_total queda en ~2,04 por el tope
--           anti-inflación, así que NO entra la válvula de precio corto)
```

> Ojo con acortar demasiado el trayecto: con un destino a ~200 m el `km_total`
> baja de 1,5 km y entra `precio_corto_auto`, que devuelve **1 000** en lugar de
> 1 500. No es un fallo, es la tarifa corta; usa el trayecto de arriba para la
> comprobación de humo.

### Tras 033

```sql
select comision_pct, permite_deuda, limite_deuda_efectivo,
       monto_fijo_fallback_municipio, precio_km_fallback, precio_minimo_auto, redondeo_cup
from muevete.configuracion_tarifas;
-- esperado: 15.00 | true | 1000 | 1500 | 400 | 1500 | 50

select tipo, multiplicador_tarifa, precio_espera_min
from muevete.vehicle_type where categoria='pasajero' order by tipo;
-- esperado: moto 0.60/100 · auto 1.00/40 · microbus 1.50/60 · camioneta 1.20 ·
--           minivan 1.30 · tuktuk 0.50 · bicicleta 0.30

select codigo, modo, monto_fijo, precio_km, activo
from muevete.zonas_tarifa order by codigo;
-- esperado: MUN activa (fijo 1500/400), FB y Z1..Z9 inactivas
```

### Tras 034

```sql
select tablename, policyname, cmd from pg_policies
where schemaname='muevete' and tablename in ('zonas_tarifa','tarifas_municipio','configuracion_tarifas')
order by 1,2;
-- esperado: SELECT para authenticated + ALL para superadmin en las 3
```

---

## 4. Arreglar realtime en `newa` (obligatorio antes de probar H2/H3)

`newa` **no tiene ninguna tabla de `muevete` publicada**. Sin esto, el chofer no recibe el viaje y el cliente no ve la asignación: parecerá un bug del código.

```sql
alter publication supabase_realtime add table
  muevete.solicitudes_transporte,
  muevete.viajes,
  muevete.place,
  muevete.notificaciones,
  muevete.vehicle_type,
  muevete.ofertas_chofer;   -- legacy, se retirará en el cutover

-- verificar
select schemaname, tablename from pg_publication_tables
where pubname='supabase_realtime' and schemaname='muevete' order by 2;
-- esperado: 6 filas
```

> En producción **no hay que ejecutar esto**: ya están publicadas las 6.

---

## 5. Rollback

Cada archivo lleva su bloque `DOWN` documentado al final (comentado). Orden inverso: `034 → 033 → 032 → 031`, y `030` no requiere rollback salvo que hayas creado objetos que faltaban.

Antes de revertir en serio, comprobar que no haya datos nuevos dependiendo de las tablas:

```sql
select count(*) from muevete.solicitudes_transporte where driver_id is not null;
select count(*) from muevete.zonas_tarifa;
```

---

## 6. Qué NO se aplica todavía

- `035`–`038` (RPCs de toma/cierre y endurecimiento de RLS) son **H1**. No existen aún como archivos.
- El endurecimiento de RLS (`038`) va **en el cutover**, después de publicar las apps nuevas. Si se aplica antes, las apps actuales dejan de poder crear solicitudes y viajes.
- `ofertas_chofer` no se borra: queda en solo lectura hasta después del periodo de gracia.

---

## 7. Si algo falla

1. Copiar el mensaje de error completo.
2. Identificar el archivo y la línea (el error de Postgres trae `LINE n`).
3. Cada archivo está envuelto en `BEGIN/COMMIT`, así que un error deja ese archivo **sin aplicar** (no a medias).
4. Reportar el error con el número de archivo y línea para corregir el `.sql` y reintentar.