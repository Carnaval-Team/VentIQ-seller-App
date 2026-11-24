# Fondo de Inversión → Compras → Recepción → Consumo

Índice del módulo. El plan vivo es [`PLAN.md`](PLAN.md); todo lo demás es contexto que se escribió
antes o en paralelo y que sigue mandando donde no lo contradiga el plan.

## Estado (2026-11-23)

| Fase | Estado |
|---|---|
| 0. Cimientos y desbloqueo de la rama | **done** |
| 0b. Integrar el delta de esquema al pase formal | pendiente (va con el pase) |
| 1. Motor de dinero I | **done** |
| 2. Motor de dinero II | **done** |
| 3. Compra como documento | **done** |
| 4. Reserva y liquidación | **done** |
| 5. Recepción: carril A y carril B | **done** |
| 6. Costo aterrizado | **done** |
| 7. Inversores aportantes (100 %) | **done** |
| 8. Reportes, conciliación y cierre | **done** |
| 9. Pendientes, recordatorios y faltantes | **en curso** — construida y verificada; pendiente el E2E del dueño |
| 10. Responsive real de las vistas nuevas | **done** |

## Documentos

| Archivo | Para qué sirve |
|---|---|
| [`PLAN.md`](PLAN.md) | **La verdad operativa**: fases, checklist, criterios de salida, E2E por fase, decisiones cerradas (PD1-PD8), bitácora de desviaciones y riesgos. |
| [`PASE-MAIN.md`](PASE-MAIN.md) | **Orden de aplicación en producción** (main): estado de partida, los 16 pasos con su verificación, lo que no se puede saltar y cómo revertir. |
| [`00-auditoria-programador.md`](00-auditoria-programador.md) | Auditoría técnica inicial: qué había, qué estaba roto, qué se podía reutilizar. |
| [`01-analisis-funcional.md`](01-analisis-funcional.md) | Qué necesita el negocio: compra, recepción, consumo, aportes, devoluciones. |
| [`02-contabilidad.md`](02-contabilidad.md) | **Contabilidad del dinero**: grano del saldo, partida doble, conciliación R1-R7 (§6.3), riesgos X1-Xn. Es la referencia cuando hay duda de si un número está bien. |
| [`03-almacen.md`](03-almacen.md) | Almacén, ubicaciones, FEFO y cómo entra el inventario. |
| [`04-diseno-ux.md`](04-diseno-ux.md) | Decisiones de UX del módulo. |
| [`05-referencia-industria.md`](05-referencia-industria.md) | Cómo lo resuelven otros ERPs. |
| [`06-revision-adversarial.md`](06-revision-adversarial.md) | Revisión que buscó cómo se pierde dinero. Sus hallazgos son los riesgos del plan. |
| [`07-deriva-newa-vs-main.md`](07-deriva-newa-vs-main.md) | Qué hay en `newa` que no está en main (y al revés). |
| [`08-costos-newa.md`](08-costos-newa.md) | Estado del costo aterrizado antes de la fase 6. |
| [`09-financiacion-recepcion-existente.md`](09-financiacion-recepcion-existente.md) | La recepción financiada que ya existía y que el módulo no debía romper. |
| [`10-estado-equipo-y-contradicciones.md`](10-estado-equipo-y-contradicciones.md) | Contradicciones detectadas entre documentos y decisiones del equipo. |
| [`11-diff-v4-v6.md`](11-diff-v4-v6.md) | Qué cambió entre la v4 y la v6 del plan. |
| [`12-inventario-migraciones.md`](12-inventario-migraciones.md) | Inventario de migraciones necesarias. |
| [`13-ui-compras.md`](13-ui-compras.md) / [`14-ui-liquidacion.md`](14-ui-liquidacion.md) | Pantallas y flujos de compras y liquidación. |

## SQL

Vive en `ventiq_admin_app/lib/sql/compra/`, con su propio
[protocolo y estado](../../../ventiq_admin_app/lib/sql/compra/README.md). Regla corta: **se aplica y se
prueba en `newa` (qhprswhhfasrikhawjoz); a main solo por el pase formal**
([`tasks/plan_promocion_main.md`](../../../tasks/plan_promocion_main.md)).

Cada script tiene su `_rollback.sql` y cada verificación su archivo en `verify/`:

| Archivo | Qué instala | Verificación |
|---|---|---|
| `01_motor_dinero.sql` | Ledger, saldos, conciliación R1 | `verify/01_*` |
| `02a` / `02b` | Idempotencia y `transferir_v2` | `verify/02_*` |
| `03a` / `03b` | Esquema de compra y sus RPC | `verify/03_*` |
| `04_compra_liquidacion.sql` | Reserva, pago, anulación | `verify/04_liquidacion.sql` |
| `05a` / `05c` | Recepción contra compra y carril B | `verify/05_*` |
| `06a`-`06d` | Costo aterrizado, aterrizaje, reversa, ajustes `por_financiar` | `verify/06_costos.sql` (27) + pruebas con dinero |
| `07_aportes_inversores.sql` | Aportes de inversores al 100 % | `verify/07_aportes.sql` (32) + `verify/07_pruebas_aportes.sql` (42) |
| `08_reportes.sql` | R2-R7 | `verify/08_reportes.sql` (14) |
| `08b_conciliacion_job.sql` | R1 programada en `pg_cron` | `verify/08b_job.sql` (9) |
| `09_pendientes.sql` | Panel de pendientes, detalle por línea, histórico de recepciones y facturas | `verify/09_pendientes.sql` (14) |

**Prerrequisito del pase**: `sql_updates/costos_adicionales_producto.sql` (tabla de costos por recepción,
`costo_real` como columna normal y `_v2` leyendo la tabla de costos). Sin él, `06c` no puede parchear `_v2`
y la reversa del costo falla en main. Se comprueba con `verify/00_prerrequisito_costos.sql`.

Las «pruebas con dinero» son scripts transaccionales que crean sus datos y terminan en `ROLLBACK`: no
dejan filas y son la única prueba de que las cifras cuadran de verdad.

## Diseño

Capturas de Stitch en [`docs/design/`](../../design/), proyecto `4232822798385486487`, design system
`assets/c6b06057a9464b0d89f5593a1f4a8a3b`:

- `compras-recepcion-aterrizaje.png` — recepción con importadora y adicionales (fase 6).
- `compras-costos-adicionales.png` — catálogo de costos (fase 6).
- `compras-aportes-inversores.png` — aportes de inversores (fase 7).
- `reportes-conciliacion-caja.png`, `reportes-compras-costo-cambiario.png`,
  `reportes-movimientos-inversores.png` — reportes y conciliación (fase 8).

## Cómo se prueba

1. `newa` es el único entorno de desarrollo. Cada script se aplica con el runner de la Management API y
   se valida con su `verify/`.
2. Los scripts de `verify/*_pruebas_*.sql` son los que prueban dinero: se ejecutan y deben dar **0
   fallos**, terminan en `ROLLBACK`.
3. El E2E del dueño de cada fase está en `PLAN.md`; una fase no se marca `done` sin él.
4. Al promover a main, `tasks/hallazgos_pruebas_newa.md` no puede tener filas «pendiente».