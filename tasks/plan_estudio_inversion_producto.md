# Implementation Plan: Estudio de inversión del producto

Spec: `tasks/SPEC-estudio-inversion-producto.md` (aprobada).
Tareas: `tasks/todo_estudio_inversion_producto.md`.
`tasks/plan.md` y `tasks/todo.md` son el plan cerrado de Fondo de Caja. Este plan no los toca.

## Overview

Desde el historial de un producto en Tiempo real se abre un estudio histórico de cuánto de cada inversión ya se recuperó. El cálculo parte las recepciones cuando el stock del producto, sumando variantes y ubicaciones, llega a cero, y convierte cada venta a USD con la tasa de esa fecha.

## Architecture Decisions

- La función que parte tramos y calcula el cumplimiento no lee la red ni Flutter. Los tests cubren el ejemplo de 80 % y el corte por agotado sin Supabase.
- La lectura trae la historia completa del `id_producto` en la tienda: recepciones completadas, ventas completadas, movimientos de inventario y filas de `app_dat_precio_venta`. No filtra por `_startDate` / `_endDate`.
- El stock del corte es la suma en unidades base de todas las variantes y ubicaciones. Una variante agotada con otra en existencia no abre tramo.
- `sales_screen.dart` solo añade el botón en la cabecera del diálogo cronológico, y solo si `_canViewGanancias` es verdadero. El diálogo nuevo vive en su propio archivo.
- No hay SQL nuevo. Si la lectura de un producto no cabe en una consulta, se para y se pide antes de crear una RPC.

## Dependency graph

```
función pura (tramos, tasa, cumplimiento)
        │
        ├── tests del ejemplo y del corte
        │
        └── lectura histórica
                │
                └── diálogo + botón en el historial
```

## Risks

- Una línea CUP antigua puede no tener par `precio_venta_cup` / `precio_venta_usd` en esa fecha. El tramo queda incompleto; no se inventa la tasa de hoy.
- `costo_real` en algunos registros puede ser 0. La meta cae a `cantidad × precio_unitario`, que ya está en USD.
- El factor de presentación tiene que ser el mismo criterio que el reporte de productos (`cantidad × factor_rel` hacia la unidad base). Si una recepción no trae factor, esa línea no entra al stock ni a la meta y el tramo se marca incompleto.

## Task List

### Phase 1: Cálculo

1. Modelo y función pura del estudio.
2. Tests del 80 %, de la venta en USD, del corte por stock en cero y del tramo incompleto.

### Checkpoint

- `flutter.bat test --no-pub test/estudio_inversion_test.dart` pasa.

### Phase 2: Lectura y vista

3. Servicio que carga la historia del producto y la entrega a la función pura.
4. Diálogo del estudio y botón en el historial cronológico.

### Checkpoint

- Analyze de los archivos nuevos y de `sales_screen.dart` sin errores nuevos.
- Con costos visibles, el botón abre el estudio. Sin costos, el botón no está. El historial cronológico sigue filtrado por el rango de la pestaña.

## Verification Checkpoints

- Después de las tareas 1 y 2: el ejemplo de 5.000 × 0,30 y 2.000 a 0,60 da 0,80, y una recepción posterior a un stock en cero no modifica ese tramo.
- Después de las tareas 3 y 4: la vista muestra un tramo por inversión, en USD, y no ofrece un total que sume tramos distintos.
