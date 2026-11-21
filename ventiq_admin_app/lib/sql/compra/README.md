# Scripts del módulo Compras / Fondo — protocolo

Este directorio entrega el SQL del plan `docs/planes/fondo-inversion/PLAN.md`.

## Entornos

| Alias | Proyecto Supabase | Uso |
|---|---|---|
| **`newa`** | `qhprswhhfasrikhawjoz` (MCP `supabase-debug`) | **Desarrollo. Todo se prueba aquí primero.** |
| **Main** | `vsieeihstajlrdvpuooh` (MCP `supabase`) | Producción. Solo por el pase formal (`tasks/plan_promocion_main.md`). |

## Reglas

1. **`newa` primero, siempre.** Nada se aplica a Main por fuera del pase formal del equipo.
2. **El agente no aplica SQL.** Entrega scripts; los aplica el dueño.
3. Cada script es **idempotente** y va envuelto en `BEGIN; … COMMIT;`.
4. Cada script trae un bloque final de verificación que hace `RAISE EXCEPTION` si el esquema no quedó
   como se esperaba.
5. Cada script tiene su `_rollback.sql`, o dice explícitamente por qué no es reversible.
6. La cabecera declara el orden: `-- REQUIERE: 01, 02`.
7. Las verificaciones de solo lectura viven en `verify/` y devuelven `ok` / `falla` por comprobación.
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

`multimoneda` va por delante de las bases. Estado real verificado el 2026-11-21:

- **`newa` ya tiene aplicado todo el módulo** (00 a 05c), incluida `fn_fdi_registrar_recepcion` con
  **4 args** (`p_id_compra bigint DEFAULT NULL`).
- **Main no tiene nada de esto**: le faltan el módulo de costos, `fn_fdi_gasto`, `costo_real` escribible
  y todas las RPC de compras. Ese paquete es la fase 0b y va por el pase del equipo.

Corrige la nota anterior, que decía que `fn_fdi_registrar_recepcion` no estaba aplicada: sí lo está en
`newa`.