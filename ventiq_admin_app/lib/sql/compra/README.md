# Scripts del módulo Compras / Fondo — protocolo

Este directorio entrega el SQL del plan `docs/planes/fondo-inversion/PLAN.md`.

## Entornos

| Alias | Proyecto Supabase | Uso |
|---|---|---|
| **`newa`** | `qhprswhhfasrikhawjoz` (MCP `supabase-debug`) | **Desarrollo. Todo se prueba aquí primero.** |
| **Main** | `vsieeihstajlrdvpuooh` (MCP `supabase`) | Producción. Solo por el pase formal (`tasks/plan_promocion_main.md`). |

## Reglas

1. **`newa` primero, siempre.** Nada se aplica a Main por fuera del pase formal del equipo.
2. **El agente aplica el SQL en `newa`** (decisión del dueño, fase 0 del plan) y lo valida ejecutando el
   script exacto que entrega. **En Main no aplica nunca**: solo entrega scripts para el pase.
3. Cada script es **idempotente** y va envuelto en `BEGIN; … COMMIT;`.
4. Cada script trae un bloque final de verificación que hace `RAISE EXCEPTION` si el esquema no quedó
   como se esperaba.
5. Cada script tiene su `_rollback.sql`, o dice explícitamente por qué no es reversible.
6. La cabecera declara el orden: `-- REQUIERE: 01, 02`.
7. Las verificaciones de solo lectura viven en `verify/` y devuelven `ok` / `falla` por comprobación.
   Algunas **pruebas** de `verify/` son transaccionales y terminan en `ROLLBACK` (p. ej.
   `06c_pruebas_aterrizaje.sql`, que crea compras y recepciones para probar las cifras de dinero): no dejan
   datos y no sustituyen al verify de solo lectura.
8. **Cada verificación es UNA sola sentencia.** Un CTE (`with base as …`) no sobrevive a otra sentencia:
   el resumen va como fila `UNION ALL` (convención: `n = 99`), nunca como `select` aparte. Ya rompió una
   vez con `ERROR: 42P01: relation "base" does not exist`.
9. **El agente valida el script exacto que entrega**, no solo su lógica: ejecutarlo contra `newa` antes de
   darlo por bueno.

## Nomenclatura

- `NN_descripcion.sql` — migración.
- `NN_descripcion_rollback.sql` — reversa.
- `verify/NN_verificacion.sql` — comprobaciones de solo lectura.

## Advertencia de la rama (`multimoneda`)

`multimoneda` va por delante de las bases. Estado real verificado el 2026-11-23:

- **`newa` ya tiene aplicado todo el módulo** (00 a 07), incluida `fn_fdi_registrar_recepcion` con
  **4 args** (`p_id_compra bigint DEFAULT NULL`), el aterrizaje del costo con su columna de vínculo
  (`app_dat_recepcion_producto_costo.id_compra_recepcion`), `fdi_dat_compra_recepcion.tasa_usd_aplicada`,
  el resumen del costo aterrizado, la reversa al cancelar y los ajustes `por_financiar`.
- La fase 7 (`07_aportes_inversores.sql`) añade `fdi_dat_compra_aporte` con **6 triggers** de
  exclusividad, las RPC `fn_fdi_compra_aportes` / `_aporte_registrar` / `_aporte_devolver`, y reescribe
  los cuerpos de `fn_fdi_compra_pagar` / `_liberar` / `_cancelar` / `_anular` con su rama de aportes.
  Deja `fdi_dat_compra_pago.id_cuenta` / `id_medio_pago` **nullable** con el CHECK `fdi_pago_fuente_check`
  (un pago `origen='aporte'` no tiene cuenta ni medio y no lleva movimiento): el pase debe llevar ese
  cambio de restricciones o la rama de aportes no se puede instalar.
- **Main no tiene nada de esto**: le faltan el módulo de costos, `fn_fdi_gasto`, `costo_real` escribible
  y todas las RPC de compras. Ese paquete es la fase 0b y va por el pase del equipo.
- La fase 6 quedó cerrada (E2E del dueño aprobado el 2026-11-23). El pase debe promover el cuerpo de
  `_v2` con el filtro `revertido_at IS NULL` y el de `fn_fdi_compra_recalcular` con el congelamiento de
  `total_financiado`; y, con la fase 7, los cuatro cuerpos de la fase 4 y las restricciones de
  `fdi_dat_compra_pago`.

Corrige la nota anterior, que decía que `fn_fdi_registrar_recepcion` no estaba aplicada: sí lo está en
`newa`.