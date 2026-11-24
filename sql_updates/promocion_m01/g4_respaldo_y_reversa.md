# G4 — Respaldo y reversa (antes de tocar main)

Complementa `tasks/plan_promocion_main.md` §7. Checklist operativo 2026-11-23.

## Antes de la Fase 1

1. **Backup de main** (Supabase / snapshot del proyecto) con etiqueta `pre-m01-fase1-YYYYMMDD`.
2. **Volcado de definiciones** (solo lectura) a un archivo versionado, p. ej.
   `docs/plan-multimoneda/baseline_main_pre_fase1.sql` o un JSON de
   `{firma, md5(prosrc), grants}` de:
   - las 14 funciones que tendrán `_m01`;
   - helpers que se crean (`fn_turno_alinear_*`, `fn_caja_disponible_para_egreso`,
     `fn_config_tienda_puede_*`, `fn_operacion_en_turno`, `fn_operacion_completada`);
   - políticas RLS y grants de tablas tocadas (`app_dat_operacion_offline_idempotencia`,
     `app_dat_configuracion_tienda`, costos, etc.).
3. Confirmar contra el runbook que **ningún script de Fase 1** hace `DROP` / `REVOKE` /
   `ENABLE RLS` sobre tablas en uso, ni `CREATE OR REPLACE` del egreso `_v2` /
   apertura / listar / precio_promedio **sin** sufijo `_m01` (C14 same-name,
   S01 completo, costos completo, R0b… → Fase 3). Checklist: runbook § «NO aplicar».

## Reversa de Fase 1 (aditiva)

Si algo falla tras aplicar solo creación:

```sql
-- Orden inverso aproximado (ajustar a lo realmente aplicado).
DROP FUNCTION IF EXISTS public.fn_listar_ordenes_m01 CASCADE;
DROP FUNCTION IF EXISTS public.fn_actualizar_precio_promedio_recepcion_v2_m01 CASCADE;
-- … resto de *_m01 …
DROP FUNCTION IF EXISTS public.fn_caja_disponible_para_egreso(bigint, text, smallint);
-- Helpers de alineación: solo DROP si NO existían antes del pase.
```

Los nombres de las **14 RPC de venta/turno/egreso** no se modifican (viven en `_m01`).
Sí se tocan cuerpos same-name de **reportes** (C9–C13, C11, turno sin cierre):
si hay que revertir números, restaurar desde el volcado G4.

Columnas/tablas nuevas: no borrar en pánico si ya hay filas piloto; apagar flag
`permitir_moneda_por_producto` y dejar de publicar el cliente nuevo.

## Criterio de parada (producción)

Parar el pase / rollback de clientes si:

- suben de forma sostenida 4xx/5xx en venta, turno o sync;
- hay **un** caso confirmado de escritura perdida o doble cobro;
- el arnés G1 en el espejo newa no cuadra sin diferencia justificada por escrito.

## Tras estabilizar

Conservar el baseline `md5` y el snapshot al menos hasta cerrar la Fase 3 (contrato).
