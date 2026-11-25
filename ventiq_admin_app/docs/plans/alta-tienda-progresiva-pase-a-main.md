# Alta progresiva y Go Live: qué aplicar en main

Estado al 2026-11-24. **Todo esto está aplicado en newa
(`qhprswhhfasrikhawjoz`). Nada se ha aplicado en main (`vsieeihstajlrdvpuooh`).**

El plan completo está en `docs/plans/alta-tienda-progresiva-go-live.md`. Este
documento es solo **el orden de despliegue**: qué script, en qué orden, y qué
verificar entre uno y otro.

## Scripts, en este orden

Los cuatro viven en `sql_updates/`. El orden no es negociable: cada uno depende
del anterior.

| # | Script | Qué crea | Depende de |
|---|---|---|---|
| 0 | `grant_update_app_dat_tienda.sql` | `GRANT UPDATE` a `authenticated` en `app_dat_tienda` | — |
| 1 | `tienda_onboarding.sql` | columnas `estado_onboarding`, `tipo_negocio`, `activada_en`, `onboarding_descartado_en` + tabla `app_dat_tarea_onboarding` con RLS | — |
| 2 | `tienda_onboarding_verificar.sql` | nada (solo lectura) | 1 |
| 3 | `fn_m01_activar_tienda.sql` | RPC `fn_m01_activar_tienda` | 1 (lee `estado_onboarding`) |
| 4 | `fn_m01_activar_tienda_verificar.sql` | nada (solo lectura) | 3 |

### El script 0 no es opcional

Sin él, el paso 2 del asistente falla con:

```
{ "code": "42501", "message": "permission denied for table app_dat_tienda",
  "hint": "GRANT UPDATE ON public.app_dat_tienda TO authenticated" }
```

`authenticated` tiene SELECT, INSERT, DELETE, REFERENCES, TRIGGER y TRUNCATE en
`app_dat_tienda`, pero **no UPDATE**: solo `postgres` y `service_role` lo tienen.
La política RLS `m01_tienda_actualizar` existe desde el M01, pero **una política
no concede privilegios**: filtra filas *después* de que el GRANT deje pasar la
sentencia. Sin el GRANT, Postgres responde `42501` antes de evaluar la política.

No lo había notado antes porque el cliente solo insertaba tiendas por RPC
(`SECURITY DEFINER`). El alta progresiva es lo primero que hace `update` directo
desde el cliente. Y no es solo ese `update`: hay tres más que ya existían y
estaban rotos por lo mismo (`catalogo_service.dart:168`,
`carnaval_service.dart:536`, `store_data_service.dart:126`).

`UPDATE` en toda la tabla es el mismo nivel que ya tenían INSERT y DELETE; quien
decide qué filas se tocan sigue siendo la RLS. Verificado con una prueba de
aislamiento: un Dueño actualiza su tienda (1 fila) y no la ajena (0 filas).

### Revisar el mismo hueco en otras tablas

`UPDATE` está igual de ausente en `app_dat_almacen`, `app_dat_tpv`,
`app_dat_trabajadores` y `app_dat_gerente`; y concedido en
`app_dat_configuracion_tienda`, `app_dat_dueno` y `app_dat_producto`. No se
concede aquí porque el cliente admin no hace `update` directo sobre esas cuatro
hoy (verificado por grep: cero coincidencias), pero **si alguna pantalla empieza
a hacerlo, fallará igual**. Comprobación antes de dar el pase por bueno:

```sql
SELECT c.relname,
       has_table_privilege('authenticated', c.oid, 'UPDATE') AS puede_update
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relkind = 'r'
  AND c.relname IN ('app_dat_almacen','app_dat_tpv','app_dat_trabajadores','app_dat_gerente');
```


## Antes de aplicar, en main

1. **`app_dat_tienda.estado` NO es el ciclo de vida.** En main también guarda el
   código de provincia geográfico. La columna nueva es `estado_onboarding`. Si
   algún script dice `SET estado = ...`, está mal y pisaría datos geográficos de
   todas las tiendas. El verificador de la fase 4 lleva un autotest para eso.
2. **Comprobar que no existen ya las columnas** (`information_schema.columns`).
   El script es idempotente, pero conviene saber de qué estado se parte.
3. **Backfill**: `tienda_onboarding.sql` marca como `activa` las tiendas que ya
   existen la primera vez que crea la columna. Sin ese paso, todas las tiendas de
   producción aparecerían en borrador al desplegar el cliente. El script lo hace
   solo una vez; en una reejecución no toca nada.
4. **`fn_config_tienda_puede_leer` y `fn_config_tienda_puede_escribir` deben
   existir en main.** Las políticas de `app_dat_tarea_onboarding` las usan. La
   fase 1 las dio por existentes porque newa las tiene; en main hay que
   confirmarlo antes (`SELECT proname FROM pg_proc WHERE proname LIKE
   'fn_config_tienda_puede%'`). Si faltan, el despliegue del cliente rompería el
   checklist con un error de permiso.

## Después de aplicar, en main

Ejecutar los dos verificadores y comprobar:

- Las 4 columnas existen con sus CHECK.
- `SELECT count(*) FROM app_dat_tienda WHERE estado_onboarding='borrador'` = 0
  recién desplegado (backfill hecho).
- `app_dat_tarea_onboarding` tiene `relrowsecurity = true` y 4 políticas.
- `fn_m01_activar_tienda` es `SECURITY DEFINER`, con `search_path` fijado y sin
  `EXECUTE` para `anon`.
- **`estado` (provincia) sigue teniendo los mismos valores que antes del
  despliegue.** Es la comprobación que más importa.

## El cliente

El cliente que consume esto es `ventiq_admin_app`. **No desplegar el cliente
antes que el SQL**: `onboarding_service.dart` hace `select` de
`estado_onboarding` en el login y en el dashboard, y contra una base sin la
columna el login fallaría con «column does not exist». Orden correcto: SQL → app.

## Pendiente de decisión de proyecto

- **`TRUNCATE` sobre tablas nuevas.** `public` tiene `ALTER DEFAULT PRIVILEGES`
  que concede `arwdDxtm` a `authenticated` sobre toda tabla nueva, `TRUNCATE`
  incluido, y `TRUNCATE` no pasa por RLS. Afecta a `app_dat_tarea_onboarding`
  igual que a `app_dat_trabajadores` o `app_dat_tienda`. No se parchea aquí
  porque revocar solo en la tabla nueva daría falsa seguridad; el arreglo real es
  de proyecto. Documentado en `sql_updates/tienda_onboarding_verificar.sql`.
- **68 tablas de `public` tienen RLS desactivado**, entre ellas `app_dat_mesas`,
  `app_dat_layout_almacen` y `app_dat_produccion_tanda`. Habilitar RLS sin
  políticas bloquearía todo el acceso, así que también es decisión de proyecto.
- **Las 8 tiendas actuales de newa quedaron `activa`.** Para medir el checklist
  con datos reales hay que marcar 1-2 a mano como `borrador`; el plan lo deja
  como decisión diferida.
