# Implementation Plan: Dashboard de proveedor Carnaval

## Overview
Crear una pantalla en `ventiq_admin_app` para que el dueño/gerente de una tienda Inventtia sincronizada con Carnaval consulte un dashboard de estadísticas de las órdenes que contienen productos de su catálogo. El monto de ventas se recalcula con el **precio histórico** del producto local en Inventtia.

## Architecture Decisions
- El dashboard es específico del proveedor autenticado (tienda dueña); no es un dashboard general desglosado por proveedor.
- Se crea una función SQL/RPC `fn_dashboard_carnaval_proveedor` que recibe `p_id_tienda` (Inventtia) y rango de fechas; hace el join de `carnavalapp.Orders` + `OrderDetails` con `app_dat_producto`, `app_dat_precio_venta` y `relation_products_carnaval`, y devuelve datos agregados.
- El cálculo del precio histórico usa `app_dat_precio_venta` filtrando por `fecha_desde <= created_at < COALESCE(fecha_hasta, '9999-12-31')` y tomando el más reciente.
- El dashboard se reusa en la medida de lo posible: `fl_chart` ya está en `pubspec.yaml` y se usan widgets tipo `Card` estilo admin app.

## Task List

### Phase 1: Backend SQL/RPC
- [x] Definir `fn_dashboard_carnaval_proveedor` con los parámetros y campos devueltos.
- [x] Añadir el script manual para Supabase SQL Editor en `ventiq_admin_app/lib/sql/carnaval_provider_dashboard.sql`.
- [x] Añadir llamada RPC en `CarnavalService` del admin app.

### Phase 2: Modelo y datos
- [x] Crear `CarnavalProviderDashboardData` y helpers (`DateValue`, `NameCount`, etc.).

### Phase 3: UI
- [x] Crear `CarnavalProviderDashboardScreen` con filtro de fechas, resumen, gráfico y listados.
- [x] Agregar botón de acceso en `CarnavalTabView`.
- [x] Registrar la ruta en `main.dart`.

### Checkpoint
- [x] `flutter analyze` limpio para el modelo, la pantalla y sus pruebas.
- [ ] Navegación y carga funcionan (verificación visual mínima con la RPC instalada).

## Risks and Mitigations
| Risk | Impact | Mitigation |
|---|---|---|
| Precio histórico ausente para una fecha | Medio | Usar 0 con log para no romper agregados. |
| Múltiples monedas en órdenes | Medio | Sumar todo en CUP usando precio de Inventtia; documentar que es en moneda local. |
| Datos maestros cruzados (producto en otra tienda) | Medio | Forzar join por `app_dat_producto.id_tienda = p_id_tienda`. |

## Open Questions
- Ninguna. El script manual se guarda en `ventiq_admin_app/lib/sql/carnaval_provider_dashboard.sql` para ejecutarlo mediante Supabase SQL Editor.
