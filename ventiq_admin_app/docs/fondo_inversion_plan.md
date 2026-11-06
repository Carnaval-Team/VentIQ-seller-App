# Plan de implementación — Fondo de Inversión

Estado: **diseño cerrado**, pendiente de implementación.
Fecha: 2026-10-31.

## 1. Objetivo

Nueva sección **Fondo de Inversión**, gestionada de forma parecida a Pago a proveedores y Fondo de caja (Depósitos bancarios):

- Cada tienda define **conceptos** de almacenamiento de dinero y, dentro de cada concepto, **cuentas**.
- El dinero se lleva por **concepto + cuenta + medio de pago + moneda**, sin convertir entre monedas.
- El dinero entra al fondo mediante **liquidaciones** de ventas por periodo (desde Ventas → tab Proveedores), **ingresos manuales** y **ajustes positivos**.
- Se mueve entre conceptos/cuentas con **transferencias** (con % de costo opcional y conversión de moneda).
- Sale del fondo mediante **extracciones para inversión**, que se completan con **recepciones de productos**.
- Las inversiones que no se completan con recepciones quedan **marcadas para revisión**.

## 2. Decisiones de diseño (respuestas del cliente)

| # | Tema | Decisión |
|---|------|----------|
| 1 | Conceptos | Cantidad libre por tienda (CRUD). Campos: denominación, descripción. |
| 2 | Cuentas | Tabla nueva propia del Fondo. Campos: nombre, descripción. |
| 3 | Cuenta ↔ concepto | Cada cuenta pertenece a **un solo** concepto. |
| 4 | Unidad de saldo | **Concepto + cuenta + medio de pago + moneda**. |
| 5 | Medios de pago y monedas | Los **globales**: `app_nom_medio_pago` y `monedas`. |
| 6 | Total general | **Un total por moneda**, sin convertir. |
| 7 | Alcance de la liquidación | **Global**: todas las ventas del periodo filtrado, de todos los productos (con o sin proveedor). Los pagos se toman por orden completa; no hay reparto por proveedor. |
| 8 | Doble liquidación | **Bloqueada**: cada orden solo puede liquidarse una vez. Las órdenes ya liquidadas se excluyen y los totales se recalculan sin ellas. |
| 9 | Ganancia | **Sale del sistema**. Queda registrada en el historial de liquidaciones, consultable por periodo. |
| 10 | Destino de la inversión | Un solo concepto + cuenta por liquidación; cada medio/moneda conserva su origen (no se convierte). |
| 11 | Validación de ganancia | Se pide una **tasa solo para validar** que la ganancia retirada (en sus monedas) equivale a la del reporte (CUP). Si no coincide: **aviso + confirmación**, y la diferencia queda guardada. |
| 12 | Costo de transferencia | El % **siempre se suma** a lo que sale del origen. 1000 con 5 % → salen 1050, llegan 1000. |
| 13 | Transferencia entre monedas/medios | **Permitida**. Se pide la tasa y se muestra cuánto sale y cuánto llega antes de confirmar. |
| 14 | Fuentes de una inversión | **Varias fuentes** (cuenta + medio + moneda) por inversión. |
| 15 | Moneda de la inversión | La inversión tiene **moneda de referencia**. Cada fuente en otra moneda pide su tasa al crearla. |
| 16 | Recepción ↔ inversión | Una recepción se asocia a **una sola** inversión. Una inversión puede tener **varias** recepciones (llegadas parciales). |
| 17 | Moneda de la recepción | Si difiere de la de la inversión, se **pide la tasa** al asociar y se muestra el equivalente. |
| 18 | Momento en que cuenta | La recepción cuenta **al registrarse**. |
| 19 | Recepción cancelada | **Se revierte**: se quita el vínculo y la inversión recalcula su estado. |
| 20 | Estados | Pendiente / Parcial / Completado. **Automáticos** según lo recibido, y además **cambio manual** con historial. |
| 21 | Exceso recibido | **Aviso + confirmación**. Solo se registra; no mueve dinero. |
| 22 | Faltante (sobrante sin gastar) | **No se devuelve dinero**. La inversión se marca **"En revisión"** para investigar qué pasó con el dinero. |
| 23 | Cuándo se marca revisión | (a) Al pasar a Completado a mano con monto recibido menor al invertido, **o** (b) cuando pasan **N días** sin completarse. **N lo configura el cliente** por tienda. |
| 24 | Inversión en revisión | **Sigue aceptando recepciones**. Si llega a cubrir el monto, la marca de revisión se quita sola. |
| 25 | Dónde se opera | **Admin (gerente/dueño)**: estructura (conceptos y cuentas) + operación diaria en una **vista nueva**; la liquidación en Ventas y la asociación en Recepción. **Superadmin**: solo paneles de lectura (saldos, inversiones en revisión). |
| 26 | Ingresos manuales | **Sí**, con motivo y fecha. |
| 27 | Ajustes | Solo **positivos** (aumentan la base de inversión). |
| 28 | Anulaciones | **No se anula** ninguna operación. Correcciones: una transferencia mal hecha se corrige con **otra transferencia en sentido contrario al 0 %**; una liquidación que metió de más se corrige con un **ajuste de corrección negativo**, solo gerente, con motivo obligatorio y ligado a la liquidación. |
| 29 | Roles en admin | Solo **gerente** (y superadmin). |

## 3. Contexto técnico existente (referencia)

- **Pagos de venta**: `app_dat_pago_venta` tiene `id_medio_pago`, `monto`, `moneda`, `tasa_usd`, `monto_cup_equivalente`, `id_operacion_venta`.
- **Medios de pago**: `app_nom_medio_pago` (global; hoy: efectivo oferta, transferencia regular, efectivo regular).
- **Tab Proveedores** (`sales_screen.dart`, `_buildSuppliersTab` / `_loadSupplierReports`): agrega filas de `fn_reporte_ventas_con_proveedor5` o `fn_reporte_ventas_con_proveedor_por_turno_v2` (según `_productDateFilterMode`). Solo CUP, sin desglose por medio ni moneda.
- **Recepción**: `inventory_reception_screen.dart` → `InventoryService.insertInventoryReception` → RPC `fn_registrar_recepcion_con_inventario`. Escribe `app_dat_operaciones`, `app_dat_operacion_recepcion` (`monto_total`, `moneda_factura`, `tasa_cambio_aplicada` sin usar), `app_dat_recepcion_productos`. Moneda fija en USD en la UI.
- **Cambio de estado de operaciones**: `fn_registrar_cambio_estado_operacion_mejorado`.
- **Helpers de acceso**: `fn_user_can_access_tienda(id_tienda)`, `fn_user_is_gerente_or_superadmin(id_tienda)`, `fn_is_superadmin_full_access()`.
- **Patrón de módulo**: `prv_*` (Pago a proveedores) y `dep_*` (Depósitos bancarios) en `ventiq_admin_app/lib/sql/*_schema.sql`.

## 4. Base de datos (Supabase)

Archivo: `ventiq_admin_app/lib/sql/fondo_inversion_schema.sql`. Prefijo de tablas: `fdi_`.

Reglas para **todas** las tablas (regla del proyecto):

- `ENABLE ROW LEVEL SECURITY` inmediatamente después de cada `CREATE TABLE`, con sus policies en las líneas siguientes.
- **SELECT**: `fn_user_can_access_tienda(id_tienda)`.
- **INSERT/UPDATE/DELETE** directos: solo en tablas de estructura y configuración, con `fn_user_is_gerente_or_superadmin(id_tienda)`.
- Tablas de dinero (saldos, movimientos, liquidaciones, transferencias, inversiones): **sin policies de escritura directa**; solo se escriben mediante RPCs `SECURITY DEFINER` que validan rol y tienda.

### 4.1 Estructura y configuración

**`fdi_dat_concepto`**
- `id`, `id_tienda`, `denominacion` (único por tienda), `descripcion`, `activo`, `created_at`, `updated_at`.

**`fdi_dat_cuenta`**
- `id`, `id_concepto` (FK), `nombre` (único por concepto), `descripcion`, `activo`, `created_at`, `updated_at`.
- `id_tienda` desnormalizado para RLS.

**`fdi_dat_config`**
- `id_tienda` (PK), `dias_alerta_revision` (entero > 0, configurable por el cliente), `updated_at`, `updated_by`.

### 4.2 Saldos y movimientos

**`fdi_dat_saldo`**
- `id`, `id_tienda`, `id_cuenta`, `id_medio_pago`, `moneda`, `saldo` (`CHECK saldo >= 0`), `updated_at`.
- `UNIQUE (id_cuenta, id_medio_pago, moneda)`.

**`fdi_dat_movimiento`** (libro de todos los movimientos)
- `id`, `id_tienda`, `id_cuenta`, `id_medio_pago`, `moneda`.
- `monto` (con signo), `saldo_anterior`, `saldo_nuevo`.
- `tipo`: `liquidacion`, `transferencia_salida`, `transferencia_entrada`, `comision_transferencia`, `extraccion_inversion`, `ingreso_manual`, `ajuste`, `ajuste_correccion`.
- Referencias opcionales: `id_liquidacion`, `id_transferencia`, `id_inversion`.
- `observacion`, `created_by`, `created_at`.

### 4.3 Liquidaciones

**`fdi_dat_liquidacion`**
- `id`, `id_tienda`, `idempotency_key` (único).
- Periodo: `fecha_desde`, `fecha_hasta`, `modo_filtro` (`fechas` / `turnos_abiertos`).
- Totales del reporte (CUP): `venta_total`, `costo_total`, `ganancia_reporte`.
- Validación: `tasa_validacion`, `ganancia_retirada_equivalente`, `diferencia_ganancia`, `confirmada_con_diferencia` (bool).
- Destino: `id_cuenta_destino`.
- `cantidad_ordenes`, `observacion`, `created_by`, `created_at`.

**`fdi_dat_liquidacion_detalle`**
- `id`, `id_liquidacion`, `id_medio_pago`, `moneda`.
- `monto_vendido`, `monto_ganancia_retirada`, `monto_inversion` (= vendido − ganancia retirada; `CHECK >= 0`).

**`fdi_dat_liquidacion_orden`**
- `id`, `id_liquidacion`, `id_operacion_venta` **UNIQUE** (impide doble liquidación).

### 4.4 Transferencias

**`fdi_dat_transferencia`**
- `id`, `id_tienda`, `idempotency_key` (único).
- Origen: `id_cuenta_origen`, `id_medio_pago_origen`, `moneda_origen`.
- Destino: `id_cuenta_destino`, `id_medio_pago_destino`, `moneda_destino`.
- `monto_destino` (lo que llega), `tasa` (1 si misma moneda), `monto_base_origen` (= monto_destino convertido a moneda origen), `porcentaje_costo`, `monto_comision`, `monto_total_origen` (= base + comisión).
- `id_transferencia_corregida` (opcional, para transferencias de corrección al 0 %).
- `observacion`, `created_by`, `created_at`.
- `CHECK` origen ≠ destino (la combinación cuenta + medio + moneda).

### 4.5 Inversiones

**`fdi_dat_inversion`**
- `id`, `id_tienda`, `idempotency_key` (único).
- `identificador` (**UNIQUE por tienda**), `detalles`, `descripcion`.
- `moneda_referencia`, `monto_total_ref`, `monto_recibido_ref`.
- `estado`: `pendiente` / `parcial` / `completado`.
- `estado_manual` (bool: el último cambio fue manual).
- Revisión: `requiere_revision` (bool), `motivo_revision` (`completado_con_faltante` / `vencida`), `monto_faltante_ref`, `revision_resuelta_por`, `revision_resuelta_at`, `revision_nota`.
- `created_by`, `created_at`, `updated_at`.

**`fdi_dat_inversion_fuente`**
- `id`, `id_inversion`, `id_cuenta`, `id_medio_pago`, `moneda`, `monto`, `tasa_a_ref`, `monto_ref`.

**`fdi_hist_estado_inversion`**
- `id`, `id_inversion`, `estado_anterior`, `estado_nuevo`, `origen` (`automatico` / `manual`), `motivo`, `created_by`, `created_at`.

**`fdi_dat_inversion_recepcion`**
- `id`, `id_inversion`, `id_operacion` **UNIQUE** (una recepción → una inversión).
- `monto_recepcion`, `moneda_recepcion`, `tasa_a_ref`, `monto_ref`.
- `confirmada_con_exceso` (bool), `created_by`, `created_at`.

### 4.6 RPCs

Reglas comunes:
- `SECURITY DEFINER`, `SET search_path = public`.
- Validan `fn_user_is_gerente_or_superadmin(p_id_tienda)` en escrituras y `fn_user_can_access_tienda` en lecturas.
- Bloquean las filas de saldo afectadas con `SELECT ... FOR UPDATE` (ordenadas por id para evitar deadlocks).
- Reciben `p_idempotency_key uuid` generado por la app. Si ya existe, devuelven la operación existente en lugar de crear otra (evita duplicados por doble click o reintento).
- Validan saldo suficiente antes de descontar.

| RPC | Descripción |
|-----|-------------|
| `fn_fdi_ventas_por_medio_moneda(p_id_tienda, p_desde, p_hasta, p_modo)` | Toma las órdenes de venta del periodo (mismo criterio que el reporte del tab Proveedores según `p_modo`), **excluye** las ya presentes en `fdi_dat_liquidacion_orden`, agrupa `app_dat_pago_venta` por medio de pago y moneda, y calcula venta, costo y ganancia (CUP) solo de esas órdenes. Devuelve también la cantidad de órdenes excluidas. |
| `fn_fdi_crear_liquidacion(p_id_tienda, p_desde, p_hasta, p_modo, p_id_cuenta_destino, p_detalle jsonb, p_tasa_validacion, p_confirmar_diferencia, p_observacion, p_idempotency_key)` | Recalcula en servidor las órdenes elegibles (no confía en el cliente), valida que cada `monto_ganancia_retirada <= monto_vendido`, calcula la diferencia de ganancia y, si es distinta de cero sin confirmación, rechaza con un código que la app usa para pedir confirmación. Inserta liquidación, detalle y órdenes; suma `monto_inversion` a cada saldo (cuenta destino + medio + moneda) y registra movimientos `liquidacion`. |
| `fn_fdi_transferir(p_id_tienda, origen..., destino..., p_monto_destino, p_tasa, p_porcentaje_costo, p_id_transferencia_corregida, p_observacion, p_idempotency_key)` | Calcula base en moneda origen, comisión y total; descuenta el total del origen y suma el monto al destino. Movimientos: `transferencia_salida`, `comision_transferencia` (si > 0) y `transferencia_entrada`. Si es corrección, exige `porcentaje_costo = 0`. |
| `fn_fdi_ingreso_manual(p_id_tienda, p_id_cuenta, p_id_medio_pago, p_moneda, p_monto, p_fecha, p_motivo, p_idempotency_key)` | `p_monto > 0`. Movimiento `ingreso_manual`. |
| `fn_fdi_ajuste(...)` | `p_monto > 0`, motivo obligatorio. Movimiento `ajuste`. |
| `fn_fdi_ajuste_correccion_liquidacion(p_id_tienda, p_id_liquidacion, p_id_medio_pago, p_moneda, p_monto, p_motivo, p_idempotency_key)` | Solo gerente/superadmin. `p_monto > 0` se **descuenta** de la cuenta destino de esa liquidación, en el medio y moneda indicados; no puede superar lo que esa liquidación ingresó en ese medio/moneda menos correcciones previas. Movimiento `ajuste_correccion` ligado a la liquidación. |
| `fn_fdi_crear_inversion(p_id_tienda, p_identificador, p_detalles, p_descripcion, p_moneda_referencia, p_fuentes jsonb, p_idempotency_key)` | Cada fuente: cuenta, medio, moneda, monto, tasa (1 si es la moneda de referencia). Descuenta cada fuente, calcula `monto_total_ref`, crea la inversión en `pendiente` y registra movimientos `extraccion_inversion` e historial de estado. |
| `fn_fdi_cambiar_estado_inversion(p_id_inversion, p_estado, p_motivo)` | Cambio manual con historial. Si pasa a `completado` con `monto_recibido_ref < monto_total_ref` → `requiere_revision = true`, `motivo_revision = 'completado_con_faltante'`, guarda el faltante. |
| `fn_fdi_recalcular_inversion(p_id_inversion)` | Interna. Suma `monto_ref` de sus recepciones; estado automático: 0 → `pendiente`, entre 0 y total → `parcial`, ≥ total → `completado`. Si llega a cubrir el total, limpia `requiere_revision`. Registra historial si el estado cambia. |
| `fn_fdi_vincular_recepcion(p_id_operacion, p_id_inversion, p_monto, p_moneda, p_tasa_a_ref, p_confirmar_exceso)` | Valida que la inversión sea de la misma tienda; si el total recibido superaría el invertido sin confirmación, rechaza con código para pedir confirmación. Inserta el vínculo y recalcula. |
| `fn_fdi_desvincular_recepcion(p_id_operacion)` | Interna, llamada al cancelar la recepción. Borra el vínculo y recalcula. |
| `fn_fdi_resolver_revision(p_id_inversion, p_nota)` | Registra qué pasó con el dinero, quién y cuándo. **No mueve saldo**. |
| `fn_fdi_saldos(p_id_tienda)` | Saldos por concepto → cuenta → medio → moneda y totales por moneda. |
| `fn_fdi_movimientos(p_id_tienda, filtros...)` | Movimientos con filtros de fecha, concepto, cuenta, medio, moneda y tipo. |
| `fn_fdi_liquidaciones(p_id_tienda, p_desde, p_hasta)` | Historial de liquidaciones del periodo con su detalle. |
| `fn_fdi_inversiones(p_id_tienda, filtros...)` | Lista con estado y bandera de revisión. La revisión por vencimiento se **calcula al consultar**: estado distinto de `completado` y `created_at` más antiguo que `dias_alerta_revision`. |
| `fn_fdi_detalle_inversion(p_id_inversion)` | Fuentes, recepciones asociadas (con enlace a la operación), historial de estados y revisión. |

### 4.7 Cambios en funciones existentes

- **`fn_registrar_recepcion_con_inventario`**: nuevos parámetros opcionales `p_id_inversion`, `p_tasa_inversion`, `p_confirmar_exceso_inversion`. Si viene `p_id_inversion`, llama a `fn_fdi_vincular_recepcion` dentro de la misma transacción usando `p_monto_total` y `p_moneda_factura`. Guardar también `tasa_cambio_aplicada` y `fecha_tasa_aplicada` en `app_dat_operacion_recepcion`.
  - Mantener la firma anterior funcionando (parámetros con `DEFAULT NULL`) para no romper builds viejas.
- **`fn_registrar_cambio_estado_operacion_mejorado`**: cuando una operación de recepción pasa a **cancelada**, llamar a `fn_fdi_desvincular_recepcion`.
- Verificar si existe otra ruta de eliminación/cancelación de recepciones y aplicar lo mismo.

## 5. ventiq_superadmin

> **Actualizado**: la estructura (conceptos y cuentas) la gestiona el **gerente/dueño desde ventiq_admin_app** (ver 6.3, tab Configuración). El superadmin queda como panel de consulta/auditoría; su CRUD de estructura se mantiene solo como soporte excepcional.

1. **Servicio**: `lib/services/fondo_inversion_service.dart` — CRUD de conceptos y cuentas (soporte excepcional), lectura de saldos (`fn_fdi_saldos`), movimientos (`fn_fdi_movimientos`) y de inversiones en revisión (`fn_fdi_inversiones p_solo_revision`).
2. **Pantalla**: `lib/screens/fondo_inversion_screen.dart`.
   - Selector de tienda.
   - Gestión de conceptos y cuentas (crear, editar, activar/desactivar, eliminar solo si no tienen saldos/movimientos) — uso excepcional; la gestión cotidiana es en admin.
   - Panel de solo lectura: saldos por cuenta, medio y moneda con totales por moneda.
   - Panel de solo lectura: movimientos recientes.
   - Panel de solo lectura: inversiones en revisión de la tienda.
3. **Navegación**: ruta `/fondo-inversion` con `RouteGuard` en `lib/main.dart`, entrada en `lib/widgets/app_drawer.dart` (sección Tiendas).

## 6. ventiq_admin_app

### 6.1 Servicio y modelos

- `lib/models/fondo_inversion.dart`: concepto, cuenta, saldo, movimiento, liquidación (+ detalle), transferencia, inversión (+ fuente, recepción, historial), config.
- `lib/services/fondo_inversion_service.dart`: llamadas a todas las RPCs de la sección 4.6. Genera el `idempotency_key` **una vez por apertura de diálogo** y lo reutiliza en reintentos.

### 6.2 Liquidación en Ventas → tab Proveedores (`sales_screen.dart`)

- Botón **"Crear liquidación"** en `_buildSuppliersTab`, visible solo para gerente.
- Diálogo:
  1. Encabezado con el periodo y el modo de filtro activos.
  2. Llama `fn_fdi_ventas_por_medio_moneda`. Si hay órdenes ya liquidadas excluidas, muestra el aviso con la cantidad.
  3. Referencia: venta, costo y ganancia del reporte (CUP) de las órdenes elegibles.
  4. Tabla por medio de pago + moneda: vendido, campo **ganancia a retirar**, **inversión** calculada.
  5. Campo **tasa de validación**: muestra la ganancia retirada convertida frente a la ganancia del reporte y la diferencia.
  6. Selección de **concepto** y **cuenta** destino.
  7. Resumen final y botón **Confirmar** con loading y bloqueo de doble click (estado fuera del `builder` del `StatefulBuilder`, `barrierDismissible: false`).
  8. Si el servidor responde "diferencia sin confirmar", segundo diálogo de confirmación y reintento con `p_confirmar_diferencia = true` y la misma clave.
- Si no hay órdenes elegibles, el botón de confirmar queda deshabilitado con mensaje.

### 6.3 Vista nueva "Fondo de Inversión"

`lib/screens/fondo_inversion/fondo_inversion_screen.dart`, ruta `/fondo-inversion`, entrada en `admin_drawer.dart` (solo gerente). Pestañas:

1. **Saldos**: árbol concepto → cuenta → medio + moneda; totales por moneda. Acciones: ingreso manual, ajuste positivo.
2. **Movimientos**: lista con filtros (fecha, concepto, cuenta, medio, moneda, tipo).
3. **Liquidaciones**: historial por periodo; detalle con montos por medio/moneda, validación de ganancia, órdenes incluidas y correcciones aplicadas. Acción: **ajuste de corrección** (motivo obligatorio).
4. **Transferencias**: lista y diálogo de nueva transferencia.
   - Origen y destino (concepto, cuenta, medio, moneda), monto que llega, % de costo, tasa si cambia la moneda.
   - Vista previa: **sale X (base + comisión) / llega Y** antes de confirmar.
   - Acción "Corregir" sobre una transferencia: abre el diálogo invertido al 0 %.
5. **Inversiones**:
   - Lista con filtros por estado y **"En revisión"**; insignia de aviso en las marcadas.
   - Crear: identificador, detalles, descripción, moneda de referencia, varias fuentes (cada una con su tasa si aplica), vista previa del total en la moneda de referencia.
   - Detalle: fuentes, recepciones asociadas (enlace a la operación), avance (recibido / total), historial de estados, faltante y revisión.
   - Acciones: cambio manual de estado (con motivo), **resolver revisión** (nota).
6. **Configuración**: `dias_alerta_revision` + **gestión de la estructura** (conceptos y cuentas: crear, editar, activar/desactivar, eliminar solo sin saldos/movimientos) — la estructura la administra el gerente/dueño en esta app, no en superadmin.

Todos los diálogos de escritura con loading y bloqueo de doble click.

### 6.4 Recepción de productos (`inventory_reception_screen.dart`)

- Selector opcional **"Inversión asociada"**: lista inversiones de la tienda en `pendiente` o `parcial`, incluidas las que están en revisión.
- Al elegir una, muestra moneda de referencia, total, recibido y faltante.
- Si la moneda de la recepción difiere de la de la inversión: campo **tasa** obligatorio y equivalente calculado.
- Si con esta recepción se supera el monto invertido: aviso con confirmación (`p_confirmar_exceso_inversion`).
- `InventoryService.insertInventoryReception` pasa los nuevos parámetros a la RPC.

### 6.5 Detalle de operación

- En la vista de detalle de una operación de recepción, mostrar la inversión vinculada (identificador, monto aplicado, tasa) con enlace al detalle de la inversión.

### 6.6 Changelog

- Nueva entrada en `assets/changelog.json` describiendo la sección.

## 7. ventiq_app (TPV)

Sin cambios. El Fondo de Inversión solo se opera en admin y siempre en línea; **no entra** en el pipeline de sincronización offline. Las ventas y pagos que alimentan la liquidación ya se sincronizan con el flujo existente.

## 8. Orden de implementación

1. Script SQL completo (tablas + RLS + RPCs) y prueba en un entorno de pruebas.
2. Cambios en `fn_registrar_recepcion_con_inventario` y en el cambio de estado de operaciones.
3. Admin: gestión de conceptos y cuentas en la vista del fondo (necesarios antes de operar).
4. Admin: servicio y modelos.
5. Admin: vista Fondo de Inversión (saldos, ingresos manuales, ajustes, configuración + estructura).
6. Admin: liquidación desde Ventas.
7. Admin: transferencias.
8. Admin: inversiones.
9. Admin: asociación en recepción y detalle de operación.
10. Changelog y pruebas finales.

## 9. Pruebas de aceptación

**Liquidación**
- Periodo con pagos mixtos (CUP efectivo, CUP transferencia, USD efectivo): el detalle por medio/moneda cuadra con los pagos.
- Ganancia retirada que no coincide con el reporte: pide confirmación y guarda la diferencia.
- Liquidar dos veces el mismo periodo: la segunda no incluye órdenes ya liquidadas.
- Periodo parcialmente solapado: solo entran las órdenes nuevas y los totales se recalculan.
- Doble click en confirmar: una sola liquidación.
- Ajuste de corrección: no permite descontar más de lo que la liquidación ingresó.

**Transferencias**
- 1000 con 5 %: salen 1050, llegan 1000, comisión registrada.
- Cambio de moneda con tasa: montos de origen y destino correctos en la vista previa y en los saldos.
- Saldo insuficiente en origen: rechazada.
- Corrección al 0 %: restaura los saldos.

**Inversiones y recepciones**
- Inversión con dos fuentes en monedas distintas: total en moneda de referencia correcto; saldos descontados.
- Dos recepciones parciales: Pendiente → Parcial → Completado.
- Recepción con exceso: pide confirmación.
- Cancelar una recepción: la inversión vuelve al estado que corresponde.
- Completar a mano con faltante: queda en revisión con el faltante.
- Inversión que supera `dias_alerta_revision` sin completarse: aparece en revisión.
- Inversión en revisión que recibe lo que faltaba: la marca se quita sola.
- Resolver revisión: queda la nota, el saldo no cambia.

**Seguridad**
- Vendedor: no puede escribir en ninguna tabla ni RPC del fondo.
- Gerente de otra tienda: no puede leer ni escribir el fondo ajeno.
- Gerente: gestiona conceptos y cuentas **de su tienda** desde admin (es el flujo principal).
- Superadmin: puede gestionar conceptos y cuentas de cualquier tienda (uso excepcional).
- Escritura directa por PostgREST en tablas de dinero: rechazada por RLS.

## 10. Riesgos y puntos a vigilar

- **Criterio de órdenes del periodo**: `fn_fdi_ventas_por_medio_moneda` debe usar exactamente el mismo criterio (fechas o turnos abiertos, estados de orden válidos) que el reporte del tab Proveedores; si no, la ganancia de referencia no coincidirá con la pantalla.
- **Órdenes con devoluciones o cancelaciones posteriores a la liquidación**: hoy no se contempla; quedan liquidadas con el monto original. Revisar con el cliente si aparece el caso.
- **Moneda de recepción fija en USD** en la UI: si se habilita elegir moneda, la asociación con la inversión ya la soporta.
- **Compatibilidad**: la firma vieja de `fn_registrar_recepcion_con_inventario` debe seguir funcionando para builds anteriores.
