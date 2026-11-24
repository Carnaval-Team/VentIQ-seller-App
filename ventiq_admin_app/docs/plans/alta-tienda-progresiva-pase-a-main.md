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
| 1 | `tienda_onboarding.sql` | columnas `estado_onboarding`, `tipo_negocio`, `activada_en`, `onboarding_descartado_en` + tabla `app_dat_tarea_onboarding` con RLS | — |
| 2 | `tienda_onboarding_verificar.sql` | nada (solo lectura) | 1 |
| 3 | `fn_m01_activar_tienda.sql` | RPC `fn_m01_activar_tienda` | 1 (lee `estado_onboarding`) |
| 4 | `fn_m01_activar_tienda_verificar.sql` | nada (solo lectura) | 3 |

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
