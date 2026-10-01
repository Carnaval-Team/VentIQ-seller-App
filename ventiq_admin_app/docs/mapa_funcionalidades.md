# Mapa de funcionalidades — VentIQ Admin (`ventiq_admin_app`)

Inventario de rutas, pantallas y acciones, **ordenado como el drawer** (`AdminDrawer`).

**Roles:** Gerente · Supervisor · Auditor · Almacenero · RRHH · Dependiente (vendedor)

**Fuentes:** `lib/main.dart`, `lib/widgets/admin_drawer.dart`, `lib/widgets/admin_bottom_navigation.dart`, `lib/services/permissions_service.dart`, `lib/screens/`

---

## Índice (orden del drawer)

0. [Auth y selección de tienda](#0-auth-y-selección-de-tienda) *(fuera del drawer)*
1. [Dashboard](#1-dashboard)
2. [Productos](#2-productos)
3. [Inventario](#3-inventario)
4. [Almacenes](#4-almacenes)
5. [TPVs](#5-tpvs)
6. [Cocinas](#6-cocinas) *(solo modo restaurante)*
7. [Servicentro](#7-servicentro) *(solo gerente; atajo a TPVs)*
8. [Marketing](#8-marketing)
9. [Ventas](#9-ventas)
10. [Finanzas](#10-finanzas)
11. [CRM Empresarial](#11-crm-empresarial)
12. [Consignaciones](#12-consignaciones)
13. [Cuentas por Cobrar](#13-cuentas-por-cobrar)
14. [Notificación a Clientes](#14-notificación-a-clientes)
15. [Órdenes Carnaval](#15-órdenes-carnaval) *(si `admin_carnaval`)*
16. [Trabajadores](#16-trabajadores)
17. [Recursos Humanos](#17-recursos-humanos)
18. [Pago a proveedores](#18-pago-a-proveedores)
19. [Fondo de Caja](#19-fondo-de-caja)
20. [Configuración](#20-configuración)
21. [Widgets de inicio](#21-widgets-de-inicio) *(solo Android)*
22. [Cerrar sesión](#22-cerrar-sesión)

Anexos: [Bottom nav](#anexo-a--bottom-navigation) · [Permisos](#anexo-b--matriz-de-permisos) · [Deudas](#anexo-c--deudas-conocidas)

---

## 0. Auth y selección de tienda

No aparecen en el drawer; son el flujo de entrada.

### SplashScreen (`/`)
- Arranque ~2 s. Sesión + RRHH → `/hr-dashboard`; sesión → `/dashboard`; sin sesión → `/login`.
- Rutas desconocidas caen aquí (fallback `onGenerateRoute`).

### LoginScreen (`/login`)
- **Iniciar Sesión** (email/password); **Recordarme**; **¿Olvidaste tu contraseña?** (“próximamente”); **Registrar Nueva Tienda** → `/store-registration`; **Contactar Soporte**.
- Tras login: multi-tienda → `/store-selection`; RRHH → `/hr-dashboard`; con suscripción → `/dashboard`; sin → `/subscription-detail`.

### StoreSelectionScreen (`/store-selection`)
- Elegir tienda activa; Continuar → dashboard o HR según rol.

### StoreRegistrationScreen (`/store-registration`)
- Wizard: Usuario → Info tienda (mapa/IA) → Opcionales (almacenes, TPVs, personal) → Confirmar → vuelve a login.

### SubscriptionDetailScreen (`/subscription-detail`)
- Detalle del plan / suscripción.

---

## 1. Dashboard

| | |
|--|--|
| **Drawer** | Dashboard → `/dashboard` |
| **Quién** | Todos con acceso admin |
| **Rutas** | `/dashboard`, `/dashboard-mobile`, `/dashboard-web` |

### PlatformAwareDashboardScreen / DashboardScreen / DashboardWebScreen
- **Propósito:** KPIs del negocio, atajos y selector de tienda.
- **Acciones:** Abrir drawer; cambiar tienda; atajos a Ventas / Productos / Categorías / Inventario / Config; bottom nav; (web) tarjetas y gráficos.

---

## 2. Productos

| | |
|--|--|
| **Drawer** | Productos → `/products-dashboard` |
| **Quién** | Gerente, Supervisor, Auditor, Almacenero (lectura) |
| **Permisos acción** | create/edit: Gerente+Supervisor · delete: Gerente · view: + Almacenero |

### ProductsDashboardScreen (`/products-dashboard`)
- Tabs: Resumen | Análisis | Alertas | Estrategia.
- AppBar Actualizar / Menú; FAB Nuevo → `/add-product`; atajos Agregar / Ver Todos → `/products`; Generar/Regenerar análisis IA.

### ProductsScreen (`/products`)
- Gestión de Precios → `/precios-productos`; Generar con IA; Agregar; Importar Excel → `/excel-import`; FAB +; buscar; filtrar categoría; ordenar; tap → `/product-detail`.
- Por ítem: Ver / Editar / Código de barras / Descargar imagen / Gestionar imagen / Eliminar.

### ProductDetailScreen (`/product-detail`)
- Descargar imagen; Editar; popup Duplicar / Importar códigos / Eliminar; editar precios; historiales; Cambiar proveedor; Tarjeta de Estiba → ProductMovementsScreen.

### AddProductScreen (`/add-product`)
- Crear/editar: categoría, presentaciones, ingredientes, variantes, multimedia, flags (combustible, elaborado…); Escanear código; Guardar.

### PreciosProductosScreen (`/precios-productos`)
- Edición masiva precios venta/costo; filtros sin precio / stock / margen.

### CategoriesScreen (`/categories`)
- CRUD categorías (también accesible desde Config).

---

## 3. Inventario

| | |
|--|--|
| **Drawer** | Inventario → `/inventory` |
| **Quién** | Gerente, Supervisor, Auditor, Almacenero (hub restringido para almacenero según matriz) |

### InventoryScreen (`/inventory`)
- Tabs: Dashboard | Stock | Movimientos | Almacenes.
- FAB + (según permiso) → bottom sheet:
  1. Recepción → InventoryReceptionScreen
  2. Transferencia → InventoryTransferScreen
  3. Ajuste por Exceso
  4. Ajuste por Faltante
  5. Extracción
  6. Extracción elaborados
  7. Venta por Acuerdo → `/sale-by-agreement`
  8. Asignar consignación → ConsignacionScreen
  9. Consultar IPV
  10. Filtro de búsqueda (“próximamente”)

### Tabs embebidos
- **Dashboard:** salud / rotación / alertas → StockHealthDetail, RotationDetail, StockAlertsDetail.
- **Stock:** exportar; listado por almacén; sheet Transferir / Ver Detalles.
- **Movimientos:** filtros; Completar/Cancelar operación; Auditar; Corregir faltantes.
- **Almacenes (tab):** stock por zona con valoración.

### Operaciones (push)
| Pantalla | Qué hace |
|----------|----------|
| InventoryReceptionScreen | Entrada; Asistente IA; Registrar recepción |
| InventoryTransferScreen | Origen/destino; Crear transferencia |
| InventoryAdjustmentScreen | Ajuste exceso o faltante |
| InventoryExtractionScreen | Extracción de productos |
| ElaboratedProductsExtractionScreen | Extracción elaborados (descuenta ingredientes) |
| InventoryExtractionBySaleScreen | Venta por acuerdo + PDF/acta |
| InventoryIPVReportScreen | Reporte IPV; PDF/Excel; filtros moneda/fecha |

---

## 4. Almacenes

| | |
|--|--|
| **Drawer** | Almacenes → `/warehouse` |
| **Quién** | Todos (almacenero: solo el suyo) |

### WarehouseScreen (`/warehouse`)
- Listado paginado; buscar; Agregar → `/add-warehouse`; Ver detalle / Editar.

### AddWarehouseScreen (`/add-warehouse`)
- Datos básicos; layouts; condiciones; límites de stock; Guardar.

### WarehouseDetailScreen (push)
- Editar info; Inicializar Inventario Faltante; layouts (ordenar, agregar); zona: Editar / Duplicar / Eliminar; Gestionar límites.

---

## 5. TPVs

| | |
|--|--|
| **Drawer** | TPVs → `/tpv-management` |
| **Quién** | No almacenero (Gerente, Supervisor, Auditor) |

### TpvManagementScreen (`/tpv-management`)
- Tabs: **TPVs** | **Vendedores** | **Cambios** | **Turnos Tpv**; FAB + Crear TPV.

#### Tab TPVs — menú por ítem
- Editar · Gestionar Precios → TpvPricesScreen · Servicentro → ServicentroManagementScreen · Estadísticas · Eliminar.

#### Tab Vendedores
- Asignar / Reasignar / Desasignar TPV; Eliminar; switch Cambio de precio.

#### Tab Cambios
- Auditoría de cambios de precio; filtro fechas.

#### Tab Turnos Tpv
- Filtro fechas; Con discrepancias; Imprimir; detalle; Acta.

### TpvPricesScreen (`/tpv-prices`)
- FAB + precio; Importar; Editar / Duplicar / Eliminar / Restaurar / Ver Detalles.

---

## 6. Cocinas

| | |
|--|--|
| **Drawer** | Cocinas → `/cocinas-management` |
| **Quién** | Visible solo si **modo restaurante** ON; no almacenero |

### CocinasManagementScreen (`/cocinas-management`)
- Switch Cocina habilitada/deshabilitada.
- Tabs: **Cocinas** | **Platos** | **Categorias**.
- FAB Nueva cocina.
- Cocinas: CRUD; Ligar TPVs; Activar/Desactivar.
- Platos: asignar cocina + modo (al pedido / por tanda).
- Categorias: aplicar modo en bloque a platos.

---

## 7. Servicentro

| | |
|--|--|
| **Drawer** | Servicentro → atajo a `/tpv-management` |
| **Quién** | Solo gerente |
| **Nota** | La config real es por TPV (menú del TPV → Servicentro) |

### ServicentroManagementScreen (`/servicentro-management`, args `idTpv`)
- Switch Modo servicentro; columnas 1–4; FAB Agregar combustible; color / Subir / Bajar / Quitar; vista previa grid.

---

## 8. Marketing

| | |
|--|--|
| **Drawer** | Marketing → `/marketing-dashboard` |
| **Quién** | Gerente (+ Auditor en submódulos según matriz) |

### MarketingDashboardScreen (`/marketing-dashboard`)
- Cards: Promociones · Campañas · Comunicaciones · Segmentos · Fidelización · Análisis.
- Card Análisis → `/marketing-analytics` (**ruta ausente**); el menú popup usa `/analytics`.

### Submódulos
| Pantalla | Ruta | Acciones |
|----------|------|----------|
| PromotionsScreen | `/promotions` | FAB crear/filtros; detalle/editar/eliminar |
| CampaignsScreen | `/campaigns` | FAB nueva; editar; activar/desactivar |
| CommunicationsScreen | `/communications` | FAB crear; detalle; analíticas (editar “en desarrollo”) |
| SegmentsScreen | `/segments` | FAB crear; activar/desactivar; eliminar |
| LoyaltyScreen | `/loyalty` | Nuevo evento; Agregar recompensa |
| AnalyticsScreen | `/analytics` | Métricas; período 7d/30d/90d/1y |

---

## 9. Ventas

| | |
|--|--|
| **Drawer** | Ventas → `/sales` |
| **Quién** | Gerente, Supervisor, Auditor |

### SalesScreen (`/sales`)
- Tabs: Tiempo Real · TPVs · Proveedores · Desglose · Análisis · Paquetería · Analista (IA).
- Actualizar; selector período; FAB exportar PDF/Excel según tab; atajos `/tpv-management` y `/tpv-prices`; Reinyectar inventario; detalle proveedor/órdenes.

---

## 10. Finanzas

| | |
|--|--|
| **Drawer** | Finanzas → `/financial` |
| **Quién** | Gerente, Auditor |

### FinancialScreen (`/financial`)
- Cards: Dashboard · Reportes · Gastos · Costos.
- Configurar Sistema; Procesar pendientes; historial de actividad; menú financiero.

### Submódulos
| Pantalla | Ruta | Acciones |
|----------|------|----------|
| FinancialSetupScreen | `/financial-setup` | Inicializar; CRUDs catálogos |
| FinancialDashboardScreen | `/financial-dashboard` | KPIs, P&L, alertas; período |
| FinancialReportsScreen | `/financial-reports` | Tabs Rentabilidad / Proyecciones / Presupuestos / Aprobaciones |
| FinancialExpensesScreen | `/financial-expenses` | Agregar gasto; pendientes Registrar/Omitir |
| ProductionCostsScreen | `/restaurant-costs` | Calcular/Historial/Actualizar costo; convertidor |
| CostAssignmentsScreen | push | FAB + asignación tipo→centro |
| FinancialConfigurationScreen | push | Stats + acceso a catálogos |
| FinancialActivityHistoryScreen | push | Timeline filtrable |

---

## 11. CRM Empresarial

| | |
|--|--|
| **Drawer** | CRM Empresarial → `/crm-dashboard` |
| **Quién** | Gerente, Auditor |

### CRMDashboardScreen (`/crm-dashboard`)
- Cards: Interacciones · Clientes · Proveedores · Analytics · Relaciones.

### Submódulos
| Pantalla | Ruta | Acciones |
|----------|------|----------|
| InteraccionesClientesScreen | `/interacciones-clientes` | Ratings/comentarios → listados |
| CustomersScreen | `/customers` | Tabs Clientes / Fidelización / Segmentación; Agregar |
| SuppliersListScreen | `/suppliers` | FAB agregar; detalle/editar/eliminar; Reportes |
| SupplierDetailScreen | `/supplier-detail` | Ficha; Editar |
| AddEditSupplierScreen | `/add-supplier`, `/edit-supplier` | Formulario CRUD |
| SupplierReportsScreen | `/supplier-reports` | Overview / Performance / Alertas |
| CRMAnalyticsScreen | `/crm-analytics` | Charts e insights |
| CRMRelationshipsScreen | `/relationships` | Tabs Relaciones / Interacciones / Oportunidades |

### Menú CRM — rutas rotas (caen a Splash)
| Ítem | Ruta | Alternativa |
|------|------|-------------|
| Historial de Interacciones | `/crm-interactions` | `/interacciones-clientes` o tab Relaciones |
| Oportunidades | `/crm-opportunities` | Tab en `/relationships` |
| Reportes Avanzados | `/crm-reports` | — |
| Configuración CRM | `/crm-settings` | — |

---

## 12. Consignaciones

| | |
|--|--|
| **Drawer** | Consignaciones → `/consignacion` |
| **Quién** | Visible en drawer; permiso fino Gerente/Supervisor/Auditor |

### ConsignacionScreen (`/consignacion`)
- Tabs Resumen / Contratos; FAB Nuevo Contrato; Ver Detalle; Confirmar/Cancelar/Rescindir; Ver Envíos.

### Flujo satélite (push)
| Pantalla | Acciones |
|----------|----------|
| CrearContratoConsignacionScreen | Crear (plan Avanzado) |
| DetalleContratoConsignacionScreen | Liquidaciones; Stock destino; Ops venta; Rescindir |
| ConsignacionEnviosListadoScreen | Filtros; FAB ENVÍO / DEVOLUCIÓN |
| AsignarProductosConsignacionScreen | Productos/precios; CONFIRMAR ENVÍO |
| ConfirmarRecepcionConsignacionScreen | Aceptar/Rechazar |
| ConsignacionEnvioDetallesScreen | PDF; rechazar; aprobar devolución |
| OperacionesVentaConsignacionScreen | Ventas del contrato |
| LiquidacionesListScreen | Nueva; Confirmar/Rechazar |
| ProductosZonaDestinoScreen | Stock destino; ajuste |
| MapeoCategoriasConsignacionScreen | Mapear categoría local |
| ContratosPendientes / ListaProductosPendientes | Confirmación consignataria |
| ConsignacionesConsignatariaScreen | Vista recibidas |

---

## 13. Cuentas por Cobrar

| | |
|--|--|
| **Drawer** | Cuentas por Cobrar → `/cuentas-por-cobrar` |
| **Quién** | Gerente, Supervisor |

### CuentasPorCobrarScreen (`/cuentas-por-cobrar`)
- Buscar; Actualizar; tap cliente → detalle.

### ClienteCxcDetailScreen (push)
- Órdenes pendientes; Bloquear/Desbloquear; FAB Liquidar / Registrar cobro.

---

## 14. Notificación a Clientes

| | |
|--|--|
| **Drawer** | Notificación a Clientes → `/wapi-notifications` |
| **Quién** | Visible; licencia WAPI se valida en pantalla |

### WapiNotificationsScreen (`/wapi-notifications`)
- Licencia; Añadir bot (QR); conectar/desconectar/eliminar; Enviar productos ahora; Configurar envío automático; logs/reintentar.

### WapiScheduleConfigScreen / WapiProductSelectorScreen (push)
- Programación diaria (bot, hora, productos, destinatarios, delay); selección de productos.

---

## 15. Órdenes Carnaval

| | |
|--|--|
| **Drawer** | Órdenes Carnaval → `/carnaval-orders` |
| **Quién** | Solo si la tienda tiene `admin_carnaval = true` |

### CarnavalOrdersScreen (`/carnaval-orders`)
- Filtros estado/contabilización/fechas; reasignar repartidor; productos por recoger; dashboard/auditoría/bitácora; PDF/Excel; WhatsApp/mapa; marcar contabilizada.

### Relacionadas
| Pantalla | Ruta / acceso |
|----------|---------------|
| CarnavalProviderDashboardScreen | `/carnaval-provider-dashboard` |
| CarnavalOrdersDashboardScreen | push |
| CarnavalAuditScreen | push |
| CarnavalBitacoraScreen | push |
| CarnavalTabView | tab en Configuración |

---

## 16. Trabajadores

| | |
|--|--|
| **Drawer** | Trabajadores → `/workers` |
| **Quién** | Gerente, Supervisor, Auditor, RRHH |

### WorkersScreen (`/workers`)
- Tabs: Personal | Roles | Rec. Hum.
- Agregar Trabajador; sync UUID; ir a `/hr-dashboard`; buscar; ver/editar/eliminar; crear usuario login; Nuevo Rol; export PDF HR.

---

## 17. Recursos Humanos

| | |
|--|--|
| **Drawer** | Recursos Humanos → `/hr-dashboard` |
| **Quién** | Gerente, Supervisor, RRHH + plan Pro/Avanzado |
| **Drawer propio** | `HRDrawer` (navegación aislada) |

### HRDrawer
Dashboard · Firmar Entrada · Firmar Salida · Reporte Salarios · Historial Asistencia · Configurar Trabajador · Cambiar Tienda · Ir a Administración (si gerente) · Cerrar Sesión.

### Pantallas
| Pantalla | Ruta | Acciones |
|----------|------|----------|
| HRDashboardScreen | `/hr-dashboard` | Selector mes; KPIs; gráficos; top trabajadores |
| HRCheckinScreen | `/hr-checkin` | Seleccionar; Registrar entrada(s) |
| HRCheckoutScreen | `/hr-checkout` | Time picker; Registrar salida(s) |
| HRSalaryReportScreen | `/hr-salary-report` | Tabla; FAB export PDF |
| HRAttendanceHistoryScreen | `/hr-attendance-history` | Filtros; Eliminar día |
| HRWorkerConfigScreen | `/hr-worker-config` | Agregar; salario hora/día y PPR |

---

## 18. Pago a proveedores

| | |
|--|--|
| **Drawer** | Pago a proveedores → `/pago-proveedores` |

### PagoProveedoresScreen (`/pago-proveedores`)
- Selector proveedor; tabs Saldo / Facturas; menú Estados / Monedas / Asignar moneda; FAB Recargar Saldo o Nueva Factura; editar/estado/fotos/historial/eliminar.

### Catálogos
- `/pago-proveedores-estados` — CRUD + Inicializar estándar.
- `/pago-proveedores-monedas` — CRUD monedas.

---

## 19. Fondo de Caja

| | |
|--|--|
| **Drawer** | Fondo de Caja → `/depositos-bancarios` |

### DepositosBancariosScreen (`/depositos-bancarios`)
- Selector banco; tabs Saldo / Extracciones; menú Estados / Tipos / Bancos / Monedas; FAB Recargar Fondo o Nueva extracción.

### Catálogos
| Ruta | Propósito |
|------|-----------|
| `/depositos-estados` | Estados de extracción |
| `/depositos-tipos-extraccion` | Tipos de extracción |
| `/depositos-bancos` | Bancos/cuentas |
| `/depositos-monedas` | Monedas |

---

## 20. Configuración

| | |
|--|--|
| **Drawer** | Configuración → `/settings` |
| **Quién** | Gerente, Supervisor (tabs reducidos) |

### SettingsScreen (`/settings`)
- **Gerente:** Tienda · Global · Categorías · Variantes · Presentaciones · Unidades · Tasas pers. · Carnaval App · Márgenes.
- **Supervisor:** Tienda · Global · Carnaval App.
- AppBar: Compartir APK admin; Menú. FAB + en Categorías/Variantes/Presentaciones.

### Tab Tienda
- Info, mapa, horario; Publicar en Catálogo; Gestionar Productos en Catálogo; Editar Información.

### Tab Global — toggles (afectan Inventtia Caja)
| Setting | Efecto |
|---------|--------|
| Contraseña Maestra para Cancelar | Exige pwd al cancelar órdenes |
| Completar Todas las Órdenes | Cerrar pendientes antes de crear otra |
| Control de Inventario en Turnos | Conteo al abrir/cerrar turno |
| → Mostrar “Debe haber” | Cantidad esperada en conteo |
| → Copiar cantidad esperada como real | Autocompletar conteo |
| Venta de Productos Sin Disponibilidad | Elaborados sin stock de ingredientes |
| Mostrar Descripción en Selectores | Preferencia local del dispositivo |
| No Pedir Datos en Venta | Cliente automático |
| Permitir Descuentos Manuales | Descuentos en TPV |
| Vendedores Pueden Crear CxC | Fiado desde TPV |
| Modo Restaurante | Mesas/cuentas abiertas |
| Módulo de Cocina | Enruta platos a estaciones |
| Método de redondeo | No / normal / exceso / múltiplo de 5 |
| Imprimir Órdenes Pendientes | Tickets de no pagadas |
| Permitir Modificar Orden Abierta | Editar ítems de orden abierta |
| Cambiar fecha de creación al cierre | Ajusta created_at ~20 min antes |
| Solicitar imagen en la operación | Foto obligatoria |
| Modo Offline Completo | Offline + días máx. sin validar |
| Precio regido por USD | CUP sigue tasa USD |
| Guardar Impresora por Defecto | Recuerda impresora del turno |
| Mostrar método de pago en ticket | Forma de pago en ticket cliente |
| Tickets Cliente/Almacén + copias | Qué imprimir y cuántas |
| Configurar impresoras WiFi | → `/wifi-printers` |

### Otras tabs
- Categorías / Variantes / Presentaciones / Unidades — CRUD maestros.
- Tasas pers. — tasas personalizadas (+ ElToque).
- Carnaval App — sync, TPV, productos, precios, desvincular.
- Márgenes — % o monto fijo con vigencia.

### WiFiPrintersScreen (`/wifi-printers`)
- Agregar por IP; Probar conexión; Eliminar. (También desde Global.)

---

## 21. Widgets de inicio

| | |
|--|--|
| **Drawer** | Widgets de inicio → tutorial sheet |
| **Quién** | Solo Android nativo (no web) |

### WidgetTutorialSheet
- Onboarding; **Añadir ahora** por tipo.

### WidgetConfigScreen
- Configurar instancia: tienda + parámetros.
- Tipos: **Mini Dashboard** · **Ventas / TPV** · **Seguimiento de Producto** (→ WidgetProductPickerScreen).

---

## 22. Cerrar sesión

| | |
|--|--|
| **Drawer** | Cerrar Sesión → diálogo de confirmación |

- Confirmar → limpia sesión/prefs y vuelve a `/` (login/splash).

---

## Anexo A — Bottom navigation

Ítems dinámicos según rol (`AdminBottomNavigation`):

| Ítem | Ruta | Quién |
|------|------|-------|
| Dashboard | `/dashboard` | Todos |
| Productos | `/products-dashboard` | Gerente, Supervisor, Auditor, Almacenero |
| Inventario | `/inventory` | Gerente, Supervisor, Auditor, Almacenero |
| Almacenes | `/warehouse` | Todos |
| Config | `/settings` | Gerente, Supervisor |

---

## Anexo B — Matriz de permisos

Detalle en `permissions_service.dart`. Resumen:

| Área | Gerente | Supervisor | Auditor | Almacenero | RRHH |
|------|:-------:|:----------:|:-------:|:----------:|:----:|
| Dashboard | ✓ | ✓ | ✓ | ✓ | —* |
| Productos (ver) | ✓ | ✓ | ✓ | ✓ | — |
| Productos (crear/editar) | ✓ | ✓ | — | — | — |
| Inventario hub | ✓ | ✓ | ✓ | —** | — |
| Recepción/transfer | ✓ | ✓ | — | ✓ | — |
| Extracción | ✓ | — | — | — | — |
| Almacenes | ✓ | ✓ | ✓ | ✓ | — |
| TPVs / Cocinas | ✓ | ✓ | ✓ | — | — |
| Servicentro | ✓ | — | — | — | — |
| Ventas | ✓ | ✓ | ✓ | — | — |
| Finanzas | ✓ | — | ✓ | — | — |
| Marketing | ✓ | — | parcial | — | — |
| CRM | ✓ | — | ✓ | — | — |
| Trabajadores | ✓ | ✓ | ✓ | — | ✓ |
| RRHH | ✓ | ✓ | — | — | ✓ |
| Settings | ✓ | ✓ | — | — | — |
| CxC | ✓ | ✓ | — | — | — |
| Consignación | ✓ | ✓ | ✓ | — | — |

\* RRHH usa `/hr-*`. · \*\* Almacenero: operaciones específicas, no hub según matriz.

---

## Anexo C — Deudas conocidas

- Rutas CRM rotas → Splash: `/crm-interactions`, `/crm-opportunities`, `/crm-reports`, `/crm-settings`
- Card Marketing “Análisis” → `/marketing-analytics` ausente (menú sí usa `/analytics`)
- “En desarrollo”: editar gasto, editar comunicación/segmento, Performance proveedores, gráfico analytics marketing
- FAB filtro inventario y “Olvidé contraseña” → “próximamente”

---

## Siguiente

- [ ] Mapear `ventiq_app` (TPV) con el mismo formato markdown

*Actualizar este archivo cuando cambien ítems del drawer o rutas.*
