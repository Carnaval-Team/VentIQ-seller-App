# Plan: Costos adicionales por producto

Estado: **implementación en curso** (SQL listo en `sql_updates/costos_adicionales_producto.sql` — aplicar en Newa/Main; UI admin cableada). Decisiones extra: inyección en **v2** (no v3); `costo_real` pasó de GENERATED a columna normal.

## Objetivo

Cada producto puede tener "costos adicionales" (flete, aduana, transporte…)
asociados a un **concepto de costo** del nomenclador, con un monto por
**unidad base**, guardado siempre en **USD** (editable en USD o CUP con la
tasa de la tienda). En la recepción se elige qué costos aplican y con qué
monto; se promedian ponderado por cantidad recibida; y el costo efectivo
(puro + adicionales) alimenta `precio_promedio`, las vistas de producto y
la gestión de precios.

## Decisiones acordadas

| Pregunta | Decisión |
|---|---|
| ¿Base del monto? | Por **unidad base** del producto (no monto total prorrateado) |
| ¿Ponderación? | Por **cantidad recibida** (misma fórmula que el costo puro) |
| ¿Nivel? | Por **producto** (unidad base); las presentaciones heredan por equivalencia |
| ¿Catálogo? | Nomenclador global gestionado por **superadmin** |

## Estructura existente que se reutiliza

- `app_cont_tipo_costo` (id, denominacion, descripcion, naturaleza → `app_nom_naturaleza_costo`, afecta_margen): **el nomenclador de conceptos** — global (sin id_tienda). No crear tabla nueva de conceptos.
- `app_cont_gastos.id_tipo_costo`: los gastos financieros ya usan el mismo catálogo (coherencia).
- `app_cont_asignacion_costos`: existe pero es para prorrateo contable por centro de costo (%), NO para costo unitario — no reutilizar para esto.
- `app_dat_precio_costo` (historial por presentación), `app_dat_producto_presentacion.precio_promedio`, `app_dat_recepcion_productos.costo_real`, `app_dat_operacion_recepcion.tasa_cambio_aplicada / moneda_factura`: el pipeline de costo vigente.
- `fn_actualizar_precio_promedio_recepcion_v3`: pondera `precio_promedio` con la recepción — punto de inyección.
- `CurrencyService` (admin): tasa USD→CUP efectiva e histórica de la tienda para capturar montos en CUP.

## 1. Base de datos (`sql_updates/costos_adicionales_producto.sql`)

### Tablas nuevas (RLS inmediato, misma transacción)

```sql
-- Relación producto ↔ concepto (monto inicial y promedio, por unidad base)
CREATE TABLE public.app_dat_producto_costo (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_producto bigint NOT NULL REFERENCES public.app_dat_producto(id),
  id_tipo_costo bigint NOT NULL REFERENCES public.app_cont_tipo_costo(id),
  monto_usd numeric NOT NULL DEFAULT 0,          -- monto inicial/configurado
  monto_promedio_usd numeric NOT NULL DEFAULT 0, -- promedio ponderado vigente
  activo boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (id_producto, id_tipo_costo)
);
ALTER TABLE public.app_dat_producto_costo ENABLE ROW LEVEL SECURITY;
-- SELECT: quien tenga acceso a la tienda del producto (via app_dat_producto)
-- INSERT/UPDATE/DELETE: solo gerente/superadmin

-- Costo aplicado por línea de recepción (auditoría)
CREATE TABLE public.app_dat_recepcion_producto_costo (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  id_recepcion_producto bigint NOT NULL REFERENCES public.app_dat_recepcion_productos(id),
  id_tipo_costo bigint NOT NULL REFERENCES public.app_cont_tipo_costo(id),
  monto_usd numeric NOT NULL,                 -- valor aplicado en ESTA recepción (editable)
  monto_promedio_anterior numeric NOT NULL,   -- promedio previo para trazabilidad
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.app_dat_recepcion_producto_costo ENABLE ROW LEVEL SECURITY;
-- Misma política que la línea padre (acceso por tienda de la operación)
```

### Función / integración con el pipeline de costo

Punto de inyección: donde hoy se calcula `costo_real` y se pondera
`precio_promedio` en la cadena de recepción
(`fn_insertar_recepcion_completa*` → `fn_actualizar_precio_promedio_recepcion_v3`
→ `fn_contabilizar_recepcion_inventario`).

- La RPC de recepción acepta en el jsonb de cada producto:
  `costos: [{"id_tipo_costo": N, "monto_usd": X}, …]` (opcional; ausente = sin cambios).
- Por línea recibida:
  - `costo_efectivo_unidad = costo_puro + Σ monto_usd de costos aplicados`.
  - `precio_promedio` se pondera con `costo_efectivo` (no con el puro).
  - `costo_real` guarda el efectivo (histórico verdadero de esa línea).
  - Por cada concepto aplicado → INSERT en `app_dat_recepcion_producto_costo`
    con `monto_promedio_anterior` = el valor previo.
  - Actualiza `monto_promedio_usd` de `app_dat_producto_costo` con la misma
    ponderación por cantidad en unidad base:
    `nuevo_avg = (prev_avg × stock_prev + monto_aplicado × cant_recibida_base) / (stock_prev + cant_recibida_base)`
    (si `stock_prev + cant = 0` → `monto_aplicado`).
- Las presentaciones del producto lo heredan por equivalencia
  (precio_promedio por presentación × `cantidad`).

## 2. Nomenclador superadmin (app admin) — YA EXISTE

- `cost_types_management_screen.dart` + `FinancialService`
  (`getCostTypes`/`createCostType`/`updateCostType`/`deleteCostType`):
  CRUD completo de `app_cont_tipo_costo`.
- Verificar que el acceso esté restringido a superadmin (hoy cuelga del
  módulo financiero); si no, agregar el gate.
- Catálogo global compartido por todas las tiendas (sin id_tienda).

## 3. Detalle de producto (app admin)

- Sección **"Costos adicionales"** en `product_detail_screen.dart`:
  - Lista de conceptos asociados: concepto, monto configurado, `monto_promedio_usd` vigente (y su equivalente CUP con tasa actual).
  - Agregar: selector del nomenclador + monto en USD o CUP (conversión con `CurrencyService` de la tienda; se persiste en USD).
  - Editar monto inicial, activar/desactivar (`activo`), eliminar.
- Servicio nuevo `CostosAdicionalesService` (admin): CRUD de `app_dat_producto_costo` + lectura de promedios.

## 4. Recepción (app admin)

En la pantalla de recepción de compra, por cada línea de producto con
costos configurados (y `activo`):

- Lista de conceptos: nombre, `monto_promedio_usd` vigente (sugerido como valor por defecto), checkbox **"aplica a esta recepción"** y campo de monto **editable** (USD/CUP con la tasa de la recepción).
- Al registrar: los conceptos marcados viajan en `costos[]` del jsonb de la línea → la RPC aplica la lógica de §1.
- Solo lectura/edición del monto para ESA recepción: editar aquí NO cambia el `monto_usd` configurado en el producto, solo el valor aplicado (y alimenta el promedio ponderado del concepto).

## 5. Vistas de costo (app admin)

- **Vista/detalle de producto**: desglose `precio_costo` =
  costo puro + línea por cada concepto con su monto_promedio.
- **Gestión de precios** (`precios_productos_screen.dart`): para productos
  con costos adicionales, mostrar el desglose junto al precio_costo
  (columna o expandible por fila).
- **Reportes**: sin cambios — al sumar los adicionales dentro de
  `precio_promedio`/`costo_real`, ventas/ganancia/márgenes quedan
  correctos automáticamente.

## 6. Alcance

- **TODOS los productos** pueden tener costos adicionales (incluye
  elaborados y servicios): el adicional se suma al costo efectivo igual
  que en productos normales — para elaborados va encima del costo de
  receta si el flujo lo permite.
- **Consignaciones NO manejan costos adicionales** (excluidas
  explícitamente).
- App vendedora: los costos solo afectan promedios en servidor; nada que
  mostrar en TPV.

## 7. Orden de despliegue

1. SQL en **Newa** → validar recepción con costos → luego **Main**.
2. `CostosAdicionalesService` + nomenclador superadmin.
3. Detalle de producto (asociación + montos).
4. Recepción (checkbox + monto editable + envío en jsonb).
5. Vistas de costo y gestión de precios.
6. Verificación: recepción con y sin costos, edición de monto por recepción,
   ponderación correcta del promedio por concepto y del `precio_promedio`,
   equivalencia en presentaciones, reportes de ventas/ganancia.

## Dudas — todas resueltas

- ✅ Por unidad base; ponderado por cantidad; por producto; nomenclador superadmin.
- ✅ UI del nomenclador **ya existe**: `cost_types_management_screen.dart`
  (verificar gate superadmin al implementar).
- ✅ **Todos** los productos pueden tener costos adicionales.
- ✅ Consignaciones **no** manejan costos adicionales.
