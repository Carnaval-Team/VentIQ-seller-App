# Mapa de funcionalidades — Inventtia Caja (`ventiq_app`)

Inventario de rutas, pantallas y acciones, **ordenado como el drawer** (`AppDrawer`).

**App:** TPV / caja (venta, turnos, mesas, cocina, servicentro, admin offline).

**Fuentes:** `lib/main.dart`, `lib/widgets/app_drawer.dart`, `lib/widgets/bottom_navigation.dart`, `lib/utils/navigation_helper.dart`, `lib/screens/`

---

## Índice (orden del drawer)

El menú cambia según el tipo de sesión y flags de tienda/TPV:

| Modo | Entradas principales del drawer |
|------|----------------------------------|
| **Solo gestión** (`inventoryOnly`: gerente/supervisor sin venta) | Administración → Egreso → Configuración → [Cierre pendiente] → Salir |
| **Servicentro** | Combustibles → Apertura → Egreso → Venta Total → Cierre → … |
| **Restaurante** | Mesas → [Cocina/Producción] → Venta de Mostrador → Apertura → … |
| **Venta normal** | Venta de Productos → Apertura → Egreso → Venta Total → Cierre → … |

0. [Auth y sesión](#0-auth-y-sesión) *(fuera del drawer)*
1. [Home de venta](#1-home-de-venta) — Combustibles / Mesas / Cocina / Producción / Catálogo
2. [Crear Apertura](#2-crear-apertura)
3. [Crear Egreso](#3-crear-egreso)
4. [Venta Total](#4-venta-total)
5. [Crear Cierre](#5-crear-cierre)
6. [Cierre(s) pendiente(s)](#6-cierres-pendientes) *(condicional)*
7. [Trabajadores de Turno](#7-trabajadores-de-turno)
8. [Administración](#8-administración) *(gerente/supervisor)*
9. [Configuración](#9-configuración)
10. [Datos Offline](#10-datos-offline) *(solo superadmin)*
11. [Cerrar sesión / Cambiar usuario](#11-cerrar-sesión--cambiar-usuario)

Anexos: [Bottom nav](#anexo-a--bottom-navigation) · [Home dinámico](#anexo-b--destino-home) · [Flujo de venta](#anexo-c--flujo-de-venta-pantallas-satélite) · [Deudas](#anexo-d--notas)

---

## 0. Auth y sesión _(detalle fino ✓)_

### SplashScreen (`/`)
- Arranque automático: sesión válida → licencia → `homeRoute`; sin sesión + full offline → `/offline-user-switch`; remember-me → auto-login; si no → `/login`.
- Diálogo de actualización: Descargar / Más tarde. Puede ir a `/subscription-detail`.

### LoginScreen / LoginWebScreen (`/login`, `/login-mobile`, `/login-web`)
- Iniciar sesión (online u offline) → `homeRoute` o `/subscription-detail`.
- Mostrar/ocultar contraseña; Recordarme; Usuarios offline del dispositivo → `/offline-user-switch`.
- Diálogo licencia: Continuar / Ver detalle.

### OfflineUserSwitchScreen (`/offline-user-switch`)
- Lista usuarios locales; contraseña + Entrar → home según rol; Salir del dispositivo → limpia prep → `/login` (conserva inventario).

### SubscriptionDetailScreen (`/subscription-detail`)
- Plan/estado; contactar soporte; historial; ir a categorías si activa; logout → `/login`; reintentar verificación.

---

## 1. Home de venta _(detalle fino ✓)_

Destino home: ver [Anexo B](#anexo-b--destino-home).

### 1.1 Combustibles (Servicentro)

| | |
|--|--|
| **Drawer** | Combustibles → `/servicentro` *(si modo servicentro)* |

#### ServicentroScreen (`/servicentro`)
- Actualizar; tap combustible con stock → ServicentroCantidadScreen; sin stock → diálogo; bottom nav.

#### ServicentroCantidadScreen (push)
- Litros ↔ monto sincronizados; selector pago; **Confirmar** → Checkout (exige turno).

### 1.2 Mesas y Comensales (Restaurante)

| | |
|--|--|
| **Drawer** | Mesas y Comensales → `/mesas` *(si `modo_restaurante`)*; `salirDeMostrador()` |

#### MesasScreen (`/mesas`)
- Refrescar / menú; buscar; chips zona; métricas libres/ocupadas; tap → `/mesa-detail`.
- Long-press: editar / activar-desactivar / eliminar; FAB **Nueva mesa**; bottom nav.

#### MesaDetailScreen (`/mesa-detail`, args: `idMesa`)
- Editar mesa; refrescar; **Nueva Cuenta** → `/cuenta-mesa`; tap cuenta existente; tap orden → `/orders` (auto-open).

#### CuentaMesaScreen (`/cuenta-mesa`, args: `idCuenta`)
- Ítems en BD (sin descontar stock hasta cobro); **+ Agregar productos** → `/categories`.
- +/− / eliminar; **Cancelar** cuenta; **Cerrar Nota** → Preorder/Checkout (aviso si hay platos en cocina).

### 1.3 Cocina (KDS)

| | |
|--|--|
| **Drawer** | Cocina → `/kds` *(si tiene cocinas asignadas)* |

#### KdsScreen (`/kds`)
- Historial ↔ activas; refrescar; filtro cocinas; polling.
- Por tarjeta: avanzar ítem (pendiente→preparando→listo→entregado); cancelar plato; **Empezar todo / Marchando todo / Entregar**; imprimir ticket.

### 1.4 Producción

| | |
|--|--|
| **Drawer** | Produccion → `/produccion` *(si tiene cocinas)* |

#### ProduccionScreen (`/produccion`)
- Tabs Platos / Lotes; historial; selector cocina; **Producir** tanda; **Cerrar** tanda (descartes); **Anular** producción.

### 1.5 Venta de Productos / Venta de Mostrador

| | |
|--|--|
| **Drawer** | “Venta de Productos” o “Venta de Mostrador” → `/categories` (+ `activarMostrador` en restaurante) |

#### CategoriesScreen / CategoriesWebScreen (`/categories`)
- Chip conexión; Buscar (overlay productos); Escanear código → BarcodeScanner; Notificaciones; Menú.
- Tap categoría → FluidMode (si activo) o ProductsScreen; pull-to-refresh; SalesMonitorFAB; chip tasa USD / SyncStatusChip; bottom nav.

#### ProductsScreen (push)
- Subcategorías; buscar; escanear; **Asignar proveedor** → AssignSupplierScreen; tap → ProductDetails (bloquea sin stock salvo elaborado/servicio).

#### ProductDetailsScreen (push)
- Si `esPaquete` → PackageProductScreen; variantes/presentación/cantidad/fracción; personalizar precio (si permiso).
- **Agregar** a OrderService o cuenta mesa activa.

#### PackageProductScreen (push)
- Paso 1: precio, cantidad, nº paquete, fotos, pago → Siguiente; Paso 2: remitente/destinatario → Finalizar.

#### BarcodeScannerScreen (push)
- Cambiar cámara / Flash; escanear → ProductDetails o “no encontrado”.

#### FluidModeScreen (push)
- Pasos Buscar → Producto → Pago → Cliente (switch en settings hoy deshabilitado).

#### PreorderScreen (`/preorder`) — tab carrito (venta normal/mostrador)
- Sin turno → Ir a Apertura; Limpiar/Cancelar orden; +/−/eliminar; método de pago; Contar Billetes; **Enviar Orden** → Checkout.

#### OrdersScreen (`/orders`) — tab Órdenes
- Imprimir todas / Refrescar / Buscar; tap detalle.
- En detalle: Imprimir Factura; PDF cliente; Editar productos; Descuento; Contar Billetes; Cancelar; Confirmar Pago/Orden; Editar cliente.

#### CheckoutScreen (push desde preorder/servicentro/cuenta)
- Promo; desglose pagos; mesa (restaurante) o datos comprador; SMS/foto; **Crear / Confirmar orden**.

---

## 2. Crear Apertura _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Crear Apertura → `/apertura` |

### AperturaScreen (`/apertura`)
- Si ya hay turno: resumen + Volver.
- Formulario: efectivo inicial CUP/USD; observaciones; **Control de inventario** (modal) si aplica; recepción Carnaval posible; **Crear Apertura**.

---

## 3. Crear Egreso _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Crear Egreso → `/egreso` |

### EgresoScreen (`/egreso`)
- Monto, motivo, método de pago; switch **Contabilizar en Fondo de Caja**; **Registrar Egreso**. Sin turno → error + Volver.

---

## 4. Venta Total _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Venta Total → `/venta-total` |

### VentaTotalScreen (`/venta-total`)
- Refrescar; cards filtrables (efectivo/transferencia/…); imprimir ticket por orden; imprimir resumen; tabla productos.

---

## 5. Crear Cierre _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Crear Cierre → `/cierre` |

### CierreScreen (`/cierre`)
- Esperado vs contado; **Contar efectivo**; listar egresos/órdenes; **Controlar/Editar Inventario**; **Crear Cierre** (online o guarda offline → `/cierre-pendiente`); aviso diferencia.

---

## 6. Cierre(s) pendiente(s) _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Solo si hay cierres offline pendientes |
| **Ruta** | `/cierre-pendiente` |

### CierrePendienteDetalleScreen (`/cierre-pendiente`)
- Refrescar; seleccionar turno; ver apertura, cuadre, inventario, ventas, egresos.

---

## 7. Trabajadores de Turno _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Trabajadores de Turno → `/shift-workers` |

### ShiftWorkersScreen (`/shift-workers`)
- Sin turno → Ir a Apertura; FAB **Agregar trabajadores**; seleccionar y **Registrar salida**; refrescar.

---

## 8. Administración _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Administración → `/admin-home` *(si `canManageInventory`)* |
| **Home forzado** | Si `inventoryOnly`, es el destino home |

Hub Admin Lite offline-first (gerente/supervisor). Valida suscripción + permisos.

### AdminHomeScreen (`/admin-home`)
- AppBar: **Cambiar usuario / Salir**; **Actualizar resumen**; Menú drawer.
- Dashboard: Ops admin → `/admin-pending-ops`; Ventas pend. (solo lectura); Turnos → `/admin-turnos-offline`; Stock bajo → `/admin-stock`.
- Tiles (orden UI): Stock · Stock por ubicación · Recepción · Extracción · Venta por acuerdo · Transferencia · Ajuste · Productos · Precios por TPV · TPVs y vendedores · IPV · Proveedores · Clientes · Ops · Cuadres offline · Preparar dispositivo *(solo inventory-only)*.
- Sesión solo gestión: card **Cambiar a vendedor**; AppBar sin atrás.

### AdminStockScreen (`/admin-stock`)
- Buscar producto; lista cache SQLite (nombre, precio, SKU, cantidad). Solo lectura.

### AdminWarehousesScreen (`/admin-warehouses`)
- Refresh; ExpansionTile por ubicación/layout; producto + cantidad; total qty.

### AdminReceptionScreen (`/admin-reception`)
- Entregado/Recibido por; Ubicación destino*; Proveedor opcional; Observaciones.
- Buscar producto (una presentación o varias); Agregar/Eliminar líneas.
- **Registrar recepción** → cola sync; diálogo ticket opcional; `pop`.

### AdminExtractionScreen (`/admin-extraction`)
- Autorizado por; Motivo (dropdown); Observaciones; buscar/agregar líneas.
- **Registrar extracción** → cola; ticket opcional.

### AdminSaleAgreementScreen (`/admin-sale-agreement`)
- Cliente (autocomplete cache); Medio de pago; Observaciones; productos/precios.
- **Registrar venta por acuerdo** (requiere `id_tpv`); ticket; `pop`.

### AdminTransferScreen (`/admin-transfer`)
- Sync layouts (AppBar); Origen/Destino; personas; Observaciones; líneas mixtas.
- **Registrar transferencia** → cola; ticket.

### AdminAdjustmentScreen (`/admin-adjustment`)
- Buscar producto; stock actual; presentación; Cantidad nueva; Motivo; Observaciones.
- **Guardar ajuste** → cola; ticket.

### AdminProductsScreen (`/admin-products`)
- FAB **Alta rápida** (nombre + precio CUP + costo); Buscar; tap → editar precio venta/costo.

### AdminTpvPricesScreen (`/admin-tpv-prices`)
- Sync cache TPVs/precios; filtro TPV; buscar; FAB + nuevo precio; tap fila → editar.

### AdminTpvVendorsScreen (`/admin-tpv-vendors`)
- Tabs TPVs / Vendedores; Sync; FAB + TPV (denominación + almacén); editar TPV.
- Vendedores: Asignar TPV; Permitir/Quitar permiso cambiar precio.

### AdminIpvScreen (`/admin-ipv`)
- Imprimir ticket IPV; Compartir texto; Refresh; Buscar; switch Incluir stock 0; lista solo lectura.

### AdminSuppliersScreen / AdminCustomersScreen
- Sync CRM cache; buscar; lista solo lectura (proveedores / clientes).

### AdminPendingOpsScreen (`/admin-pending-ops`)
- Sincronizar pendientes; Actualizar; banner conteo; Eliminar op no sync (confirma); estados Pendiente/OK/error.

### AdminTurnosOfflineScreen (`/admin-turnos-offline`)
- Sincronizar cola (AppBar + FAB, requiere red); Refresh.
- Tap turno → sheet cuadre; **Ver todo lo guardado** → `/cierre-pendiente`; Diagnosticar/forzar cierre; Imprimir cuadre.

### AdminPrepareOfflineScreen (`/admin-prepare-offline`) *(solo inventory-only)*
1. Contraseña admin → Registrar/Actualizar admin offline.
2. **Sincronizar ahora** (progreso por módulo).
3. Por vendedor: contraseña → Registrar/Actualizar.
4. **Marcar dispositivo listo** (activa modo offline app si procede).

### AssignSupplierScreen (push desde catálogo POS, no tile admin)
- Asignar proveedor a productos de una categoría; seleccionar todos; Asignar.

---

## 9. Configuración _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Configuración → `/settings` |
| **Bottom nav** | Tab Config |

### SettingsScreen (`/settings`)
- **Suscripción** → `/subscription-detail`
- Impresión on/off; USD en tickets; **Impresoras WiFi**; olvidar impresora del turno; texto estático; mostrar SKU
- Modo Fluido (switch hoy deshabilitado); buscar updates; idioma/tema (próximamente)
- **Productos por Defecto** → `/default-order-items`
- **Modo Restaurante** (switch tienda)
- Limitar datos; **Modo Offline**
- Sync manual / por módulos / forzar; Almacenamiento
- Compartir app; Acerca de; **Cerrar sesión**

### WiFiPrintersScreen (`/wifi-printers`)
- Buscar impresoras; seleccionar/guardar; probar; eliminar.

### DefaultOrderItemsScreen (`/default-order-items`)
- Buscar/añadir/quitar; subir local→servidor; limpiar; guardar.

---

## 10. Datos Offline _(detalle fino ✓)_

| | |
|--|--|
| **Drawer** | Datos Offline → `/offline-data-viewer` *(solo superadmin)* |

### OfflineDataViewerScreen (`/offline-data-viewer`)
- Solo lectura diagnóstico. Recargar; tarjeta modo offline ON/OFF; Medir offset reloj vs servidor.
- Secciones expandibles (categories, products, payment_methods, promotions, pending_orders, operations, turnos, egresos, offline_users, caches…): **Copiar** JSON.

### OfflineUserSwitchScreen (`/offline-user-switch`) *(flujo auth, no drawer)*
- Lista usuarios offline de la tienda; contraseña + **Entrar** → ruta según rol.
- **Salir del dispositivo** → limpia full-offline; `/login` (conserva inventario local).

---

## 11. Cerrar sesión / Cambiar usuario

| | |
|--|--|
| **Drawer** | “Cerrar Sesión” o “Cambiar usuario / Salir” |

### Comportamiento (`AppDrawer.promptLogoutOrSwitchUser`)
- **Offline completo / sin red + dispositivo preparado:** selector local → `/offline-user-switch` (conserva inventario de tienda).
- **Online:** signOut Supabase; limpia caché local; → `/login`. Advierte si hay ops sin sincronizar.
- Reconcilia turnos offline stale antes de avisar pendientes.

---

## Anexo A — Bottom navigation

`AppBottomNavigation` — 4 tabs fijos:

| Índice | Label | Destino típico |
|--------|-------|----------------|
| 0 | Home | `NavigationHelper.goHome` → admin / kds / servicentro / mesas / categories |
| 1 | Preorden **o** Cuenta/Mesas | Normal → `/preorder`; flujo mesa → cuenta activa o `/mesas` (`goCarrito`) |
| 2 | Órdenes | `/orders` (args opcionales `autoOpenOrderId`) |
| 3 | Config | `/settings` |

Contador: en venta normal = ítems de preorden; en flujo mesa = punto verde si hay cuenta abierta.

---

## Anexo B — Destino Home

Prioridad (`NavigationHelper.homeRoute`):

```
inventoryOnly → /admin-home
sesión cocina → /kds
modo servicentro TPV → /servicentro
flujo mesa activo → /mesas
default → /categories
```

---

## Anexo C — Flujo de venta resumido

```
Splash → Login / OfflineSwitch / Home
 ├─ Normal: Categories → Products → Details → Preorder → Checkout → Orders
 ├─ Restaurante: Mesas → MesaDetail → CuentaMesa → Categories… → Cerrar Nota → Checkout
 ├─ Mostrador (restaurante): Categories… (preorden local, sin mesa)
 ├─ Servicentro: Combustibles → Cantidad → Checkout
 └─ Cocina: KDS / Producción (paralelo a venta)
Caja: Apertura → (ventas/egresos) → Venta Total / Cierre → [Cierre pendiente]
Admin Lite: /admin-home → ops inventario/CRM/TPV offline
```

---

## Anexo D — Notas

- Flags: `modo_restaurante` (tienda), `modo_servicentro` (TPV), cocinas asignadas, `inventoryOnly`, superadmin, full offline ready.
- Etiqueta tab carrito usa `SalesModeService.flujoMesaActivo` (no solo el flag de tienda): en mostrador vuelve a “Preorden”.
- Comportamiento TPV (pwd maestra, inventario en turnos, CxC, etc.) se configura en **Admin app** → Config Global.

---

## Estado

- [x] Estructura por drawer + rutas
- [x] Detalle fino venta / mesas / cocina / servicentro / caja / settings (§0–§7, §9)
- [x] Detalle fino Administración offline (§8, §10)

*Mapa de `ventiq_app` completo a nivel pantallas/acciones. Actualizar cuando cambien drawer o rutas.*
