# Implementation Plan: Fondo de Caja y preparación offline

## Overview
Implementar validación estricta antes del modo offline manual, una cuenta predeterminada de Fondo de Caja por tienda y la recarga transaccional/idempotente originada por egresos.

## Architecture Decisions
- La base de datos garantiza unicidad de cuenta predeterminada e idempotencia de recarga.
- Un RPC transaccional registra egreso marcado + recarga + saldo + historial; Flutter no encadena escrituras financieras independientes.
- El sincronizador conserva un manifiesto de módulos completados por tienda/sesión; cero filas confirmadas es distinto de fallo.
- El payload offline mantiene compatibilidad: ausencia de `contabilizar_fondo_caja` equivale a `false`.

## Task List

### Phase 1: Base de datos y cuenta predeterminada
1. Extender schema de Fondo de Caja con cuenta predeterminada y vínculo único egreso-recarga.
2. Añadir RPC transaccional e idempotente.
3. Exponer gestión de cuenta predeterminada en admin.

### Checkpoint
- SQL revisado por integridad, Flutter admin analiza sin errores nuevos.

### Phase 2: Preparación offline
4. Descargar/cachear cuenta predeterminada y registrar resultados por módulo.
5. Validar manifiesto completo antes de activar offline y mostrar faltantes.

### Checkpoint
- Tests de readiness pasan; modo offline no se activa ante estado parcial.

### Phase 3: Egreso a Fondo de Caja
6. Añadir check y payload online/offline.
7. Integrar sincronización idempotente y retención de cola ante fallo parcial.

### Checkpoint final
- Tests enfocados, `flutter analyze` de archivos tocados y revisión de diff.

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| Actualización concurrente de saldo | Alto | RPC, bloqueo de fila y transacción |
| Duplicado por reintento | Alto | `client_uuid` + vínculo único de egreso |
| Caché de otra tienda | Alto | manifiesto y cuenta ligados a `idtienda` |
| Tablas reales difieren del artefacto SQL | Medio | cambios aditivos e `IF NOT EXISTS` |
| Registros vacíos confundidos con fallo | Medio | estado de completitud separado del contenido |
