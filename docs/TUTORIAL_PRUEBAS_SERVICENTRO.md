# Tutorial de pruebas · Modo servicentro

Guía corta para validar un TPV piloto. Configuración: **por TPV** (no por tienda).

## Prep (admin)

1. En Inventtia Admin, marca el producto como **combustible** (`es_combustible`).
2. Gestión de TPVs → menú del TPV → **Servicentro**.
3. Activa **Modo servicentro en este TPV**.
4. Agrega combustibles, ordena, elige color y columnas (1–4).
5. Otro TPV de la misma tienda puede seguir en modo normal / mesas.

## Vendedor (online)

1. Login en el TPV con modo activo → home = grid de combustibles.
2. Tap carta **con stock** → litros ↔ $ + método de pago.
3. Carta **sin stock** → deshabilitada (gris), muestra “Sin stock”; no abre venta.
4. Cobrar → checkout de 1 línea.
5. Tras venta exitosa → `/orders` y se abre el detalle de esa orden.
6. Un solo combustible por ticket (el borrador previo se descarta).
7. Al reabrir la app con sesión válida → debe volver a `/servicentro` (no a categorías).
8. Home (botón inferior) desde órdenes → vuelve al grid servicentro.

## Offline

1. Con sync previo de **productos** (catálogo): apaga red → el grid usa stock del mismo cache que categorías.
2. Si modo ON y cache vacío → mensaje claro (no pantalla rota).
3. Si cambias de TPV de sesión, no debe mostrarse la lista del TPV anterior.

> Métodos de pago: misma fuente que preorden (`PaymentMethodService` + cache
> offline vía `shouldUseLocalData`). La venta pasa por `CheckoutScreen` con
> `isOfflineOrder` cuando aplica.

## Checklist rápido

- [ ] Carta sin stock: gris / “Sin stock”; no abre cantidad.
- [ ] Carta con stock: muestra “Stock: N UM” y permite cobro.
- [ ] Columnas 1–4 se ven bien en teléfono y tablet.
- [ ] Producto sin precio: aviso, no abre cobro.
- [ ] Producto quitado del catálogo / sin `es_combustible`: no aparece tras sync.
- [ ] RLS: vendedor lee vía RPC/acceso tienda; no escribe filas en `app_dat_servicentro_producto` (solo gerente).
- [ ] Tras cobrar vuelve a `/servicentro`.

## SQL de referencia

Aplicar en orden si es instalación nueva:

1. `funcionalidad_servicentro/01_schema.sql`
2. `funcionalidad_servicentro/02_rpcs.sql`
3. `funcionalidad_servicentro/03_migracion_tpv.sql`
4. `funcionalidad_servicentro/04_rpcs_tpv.sql`
5. `funcionalidad_servicentro/05_stock_en_config.sql`
