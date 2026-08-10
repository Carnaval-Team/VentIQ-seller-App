# Plan: Modo Offline Completo con Licencia en `ventiq_app`

> Objetivo: que `ventiq_app` funcione completamente offline si la tienda tiene licencia activa,
> configurable desde `ventiq_admin_app`. La conexión es **obligatoria** solo para revalidar la
> licencia; la sincronización de datos al servidor es **opcional y selectiva por funcionalidad**.
> Incluye venta en caja (vendedores) y, para **gerente/supervisor**, **gestión
> Admin Lite** (stock, recepción, ajuste, precios) sin flujo de venta.

## Base existente (aprovechar, no reescribir)

- `SmartOfflineManager` — activación/desactivación de modo offline, monitoreo de conectividad.
- `AutoSyncService` — sincronización periódica con métodos `_syncXxx()` por módulo.
- `UserPreferencesService` — cache offline (`offline_data`), cola de operaciones/órdenes pendientes, cache de suscripción.
- `SubscriptionGuardService` — verificación de suscripción con caché (refresh cada 5 min).
- Wrappers SQL idempotentes — `ventiq_app/sql_offline/06_idempotencia_extra.sql` (`fn_apertura_turno_offline`, `fn_registrar_cambio_estado_offline`, etc.).
- Patrón de config de tienda — `app_dat_configuracion_tienda` + `StoreConfigService` + `global_config_tab_view.dart` (admin).
- **Tabla `public.app_licencias_offline` ya existe en BD** (sin referencias en código, con 2 filas históricas). Tiene `device_id` (único), `license_key` (UUID, único), `estado`, `fecha_expiracion`, `fecha_ultimo_check` y FK a `app_suscripciones_plan`. Se reutilizará para los tokens offline en lugar de crear una tabla nueva.

---

## Fase 1 — Configuración desde Admin (BD + `ventiq_admin_app`)

**Estado: ✅ Completada (2026-07-30)**

### 1.1 Migración BD
- [x] Columna `permitir_modo_offline_completo boolean NOT NULL DEFAULT false` en `app_dat_configuracion_tienda`.
- [x] Columna `dias_max_sin_validar_licencia integer NOT NULL DEFAULT 7` — ventana máxima sin conectarse antes de bloquear.
  - SQL: `sql_updates/config_modo_offline_completo.sql` (aplicado en producción).

### 1.2 Admin UI
- [x] Método `updatePermitirModoOfflineCompleto` / `updateDiasMaxSinValidarLicencia` en `ventiq_admin_app/lib/services/store_config_service.dart`.
- [x] Card `_buildModoOfflineCompletoCard` en `ventiq_admin_app/lib/widgets/global_config_tab_view.dart` (toggle + días 1–90).

### 1.3 Lectura en `ventiq_app`
- [x] Getters `getPermitirModoOfflineCompleto` / `getDiasMaxSinValidarLicencia` en `ventiq_app/.../store_config_service.dart`.
- [x] `_syncStoreConfig()` ya persiste el JSON completo de config (incluye los 2 flags nuevos).

---

## Fase 2 — Licencia: validación offline + reconexión obligatoria

**Estado: ✅ Completada (2026-07-30)**

Hoy `SubscriptionGuardService.hasActiveSubscription()` falla en offline cuando la caché expira (5 min).

### 2.1 Validación offline de licencia
- [x] Si modo offline completo habilitado y sin conexión: validar contra token firmado local (`OfflineLicenseService`).
- [x] Online: renueva token vía `fn_obtener_licencia_firmada` en cada `forceCheck` / sync de config.

### 2.2 Anti-manipulación de reloj
- [x] Persistir `last_seen_timestamp` (actualizar en validación, arranque vía touch, y cada venta en checkout).
- [x] Si el reloj del dispositivo es anterior al último visto (±2 min) → licencia no verificable → exigir conexión.

### 2.3 Reconexión obligatoria
- [x] Regla de bloqueo: `now - emitido_en > dias_max_sin_validar_licencia` **o** `now > fecha_fin` → bloquear app hasta revalidar online.
- [x] Pantalla de bloqueo: card en `subscription_detail_screen.dart` + botón "Revalidar licencia".
- [x] Banner con cuenta regresiva (`license_reconnect_banner.dart`, visible con ≤ 3 días).
- [x] Al recuperar conexión: revalidación automática y obligatoria en `SmartOfflineManager`.

### 2.4 Token firmado
- [x] RPC `fn_obtener_licencia_firmada` + `OfflineLicenseService` (HMAC-SHA256, secreto compilado).
- [x] Persistencia local de payload + firma en `UserPreferencesService`.

---

## Fase 3 — Cerrar brechas del modo offline actual

**Estado: ✅ Completada (2026-07-30)**

### 3.1 Auditoría de funcionalidades offline
- [x] Login offline: usa `SubscriptionGuardService` (licencia firmada) en lugar de solo caché de 5 min.
- [x] Cambio de estado de órdenes: encolado en `pendingOperations` + `fn_registrar_cambio_estado_offline` (desplegado).
- [x] Apertura/cierre de turno, egresos, ventas: wrappers idempotentes desplegados en producción (`fn_apertura_turno_offline`, `fn_cerrar_turno_offline`, `fn_registrar_egreso_offline`, `fn_registrar_venta_offline`, `fn_registrar_pago_venta_offline`).
- [x] Descuentos/promociones offline: `promo_code` + `promo_discount` se guardan en la orden pendiente y se envían al sincronizar.
- [x] Pagos mixtos offline: `desglose_pagos` por método se persiste y se registra con `fn_registrar_pago_venta_offline`.
- [x] Impresión: local (Bluetooth / web print) — no depende de red.
- [x] Imágenes de operación: se guardan en disco (`operaciones_offline/`) o base64 (web) y se suben al sincronizar la venta.

### 3.2 Activación automática sin diálogo
- [x] Cuando `permitir_modo_offline_completo = true` y licencia local válida, `SmartOfflineManager` activa offline automáticamente sin pedir confirmación.

### 3.3 Almacenamiento SQLite
- [x] Dependencias `sqflite`, `sqflite_common_ffi`, `path`.
- [x] `OfflineDatabaseService`: tablas `offline_sections`, `offline_categories`, `offline_products` (+ índices).
- [x] Migración one-shot SharedPreferences → SQLite al arrancar (`offline_sqlite_migrated_v1`).
- [x] `UserPreferencesService` delega `get/save/merge/clearOfflineData` a SQLite (API compatible).
- [x] Consultas parciales: `searchProducts`, `getProductsByCategory`, `getProductById`.
- [x] Init en `main.dart` (ffi en Windows/Linux).

---

## Fase 4 — Sincronización selectiva por funcionalidad

**Estado: ✅ Completada (2026-07-30)**

El `_SyncDialog` en `settings_screen.dart` ya sincroniza por pasos (`credentials`, `turno`, `egresos`, `store_config`, `promotions`, `payment_methods`, `categories`, `products`, `orders`).

### 4.1 UI "Sincronizar por módulos"
- [x] Diálogo `SelectiveSyncDialog` con checkboxes agrupados:
  - **Subir (upload):** ventas offline, egresos, turno, trabajadores.
  - **Bajar (download):** catálogo, promociones, métodos de pago, config, órdenes, turno/egresos, **licencia (siempre incluida, no des-seleccionable)**.
- [x] Entrada en Settings → Datos → "Sincronizar por módulos".

### 4.2 Refactor de `AutoSyncService`
- [x] `Future<SyncResult> syncModules(Set<SyncModule> modules)` reutilizando los `_syncXxx()` existentes.
- [x] Auto-sync periódico `_performSync` ahora delega en `syncModules` vía `_modulesForAutoSyncPass()` (mismas frecuencias: categorías/3, productos/5, órdenes/2).

### 4.3 Regla de negocio
- [x] Al conectarse: validación de licencia obligatoria y automática; sincronización de datos opcional y selectiva.

---

## Fase 5 — SQL / Supabase

**Estado: ✅ Completada (2026-07-30)**

- [x] Migración: columnas nuevas en `app_dat_configuracion_tienda` (Fase 1.1).
- [x] RPC `fn_obtener_licencia_firmada` + tabla `app_dat_licencia_offline_secreto` (`sql_updates/licencia_offline_firmada.sql`, desplegado).
- [x] Wrappers idempotentes de `sql_offline/` verificados en producción:
  `fn_apertura_turno_offline`, `fn_cerrar_turno_offline`, `fn_registrar_egreso_offline`,
  `fn_registrar_venta_offline`, `fn_registrar_pago_venta_offline`,
  `fn_registrar_cambio_estado_offline`, `fn_listar_promociones_productos_batch`,
  `get_detalles_productos_batch`.

---

## Fase 6 — Admin Lite en Caja (`ventiq_app`)

**Estado: ✅ Completada (2026-07-30)**

Extiende el modo offline completo para que **gerente y supervisor** gestionen inventario y productos desde Caja **sin vender**. Los **vendedores** siguen solo con flujo de venta.

### 6.1 Gate de acceso
- [x] `AdminAccessService`: `app_dat_gerente` / `app_dat_supervisor` → Admin Lite.
- [x] Login prioriza gerente → supervisor → vendedor. Gerente/supervisor **no requieren** `app_dat_vendedor`; TPV por defecto de la tienda.
- [x] Sesión `inventoryOnly`: redirige a `/admin-home`, oculta venta/apertura/cierre/egreso en drawer, bloquea catálogo.
- [x] Cache `caja_entry_role` + rol admin para offline.
- [x] Rutas `/admin-home`, `/admin-stock`, `/admin-reception`, `/admin-adjustment`, `/admin-products`.
- [x] Hub bloqueado si licencia inválida (`SubscriptionGuardService`).

### 6.2 Persistencia y sync
- [x] Tabla SQLite `admin_pending_ops` (migración v1→v2 en `OfflineDatabaseService`).
- [x] `AdminInventoryService`: encola ops offline, aplica cambios locales de stock/precio, sync con RPCs.
- [x] `SyncModule.uploadAdminOps` en auto-sync y diálogo de sync selectiva.

### 6.3 Pantallas MVP (offline-first)
- [x] Stock: lectura desde cache SQLite.
- [x] Recepción: formulario simple → pending op + stock local.
- [x] Ajuste: cantidad nueva → pending op + stock local.
- [x] Productos: editar precio venta/costo + alta rápida.

### 6.4 SQL idempotente
- [x] `ventiq_app/sql_offline/07_admin_caja_ops_offline.sql`:
  `fn_admin_caja_actualizar_precios_offline`,
  `fn_admin_caja_ajuste_inventario_offline`,
  `fn_admin_caja_recepcion_offline`,
  `fn_admin_caja_crear_producto_offline`.
- Cliente con fallback a RPCs/tablas originales si los wrappers aún no están desplegados.
- [ ] **Pendiente:** aplicar `07_admin_caja_ops_offline.sql` en Supabase (el proyecto MCP está en modo read-only).

### 6.5 Inventario compartido en el mismo teléfono
- [x] Offline scoped por **tienda** (`ensureOfflineStoreScope`), no por usuario.
- [x] Vendedor y gerente/supervisor de la misma tienda comparten catálogo/stock SQLite y colas pendientes.
- [x] Cambio de tienda → wipe; cambio de usuario misma tienda → conserva inventario.
- [x] Logout no borra inventario local de la tienda (sí limpia sesión).
- [x] Pendientes etiquetados con `offline_user_id` / `offline_store_id`.

---

## Fase 7 — Dispositivo full offline (admin primero + switch local)

**Estado: ✅ Completada (2026-07-30)**

Cuando la tienda tiene `permitir_modo_offline_completo`, el **administrador prepara el dispositivo** y luego vendedor/admin se turnan **sin login ni logout al servidor**.

### 7.1 Preparación
- [x] Botón en Admin Lite: **Preparar dispositivo offline** (`/admin-prepare-offline`).
- [x] Sync selectiva (licencia, catálogo, etc.) vía `DeviceOfflinePrepService` (mismos módulos que el sync de Caja + categorías/productos/órdenes).
- [x] Garantiza `credentials` en cache offline (requisito de `hasOfflineData`).
- [x] Al marcar listo: activa **modo offline general** (`setOfflineMode` + `SmartOfflineManager.onOfflineModeManuallyEnabled`), igual que Settings.
- [x] Registrar admin + vendedores en `offline_users` con **contraseña local**.
- [x] Flag `device_full_offline_ready` + store id + credenciales admin para reauth.

### 7.2 Cambio de usuario local
- [x] Cerrar sesión con dispositivo preparado → **no** `AuthService.signOut()` → `/offline-user-switch`.
- [x] Selector con contraseña local (`LocalOfflineSessionService`).
- [x] Splash/login redirigen al selector si el dispositivo está preparado.
- [x] “Salir del dispositivo” sí hace signOut y desactiva el flag.

### 7.3 Bloqueo servidor con full offline
- [x] Helper `shouldStayFullyOffline()` = dispositivo preparado + modo offline ON.
- [x] Con red detectada: **no** diálogo “activar online”, **no** revalidación remota de licencia, **no** auto-sync/reauth.
- [x] Login y licencia usan solo datos locales mientras el bloqueo esté activo.
- [x] Solo el **admin** (gerente/supervisor) puede desactivar el modo offline en Settings para volver a usar el servidor.

### Fuera de MVP (fase B futura)
Transferencias, extracción, consignación, IPV, import Excel, dashboard, categorías avanzadas, elaborados/recetas.

> **Nota:** Vendedor = solo venta. Gerente/supervisor = solo inventario/productos (sin venta),
> pueden entrar sin estar en `app_dat_vendedor`. En el **mismo teléfono**, misma tienda =
> **mismo inventario local**. Con **Fase 7**, el admin prepara el dispositivo y el cambio
> admin↔vendedor es local (contraseña cacheada), sin servidor.

---

## Orden de ejecución

1. **Fase 1** — config admin + BD (pequeña, desbloquea el resto).
2. **Fase 2** — licencia offline + bloqueo obligatorio (requisito duro del negocio).
3. **Fase 4** — sync selectiva (refactor de valor inmediato sobre código existente).
4. **Fase 3** — auditoría de brechas + posible migración a sqflite (la más larga; incremental).
5. **Fase 6** — Admin Lite en Caja (inventario/productos offline solo para gerente).

## Decisiones pendientes

| # | Decisión | Opciones | Elegida |
|---|----------|----------|---------|
| 1 | Seguridad de licencia | Caché local + anti-rollback de reloj vs token firmado por servidor | **B — Token firmado por el servidor** |
| 2 | Storage offline | Mantener SharedPreferences vs migrar a SQLite (`sqflite`) | **B — SQLite (`sqflite`)** |
| 3 | Alcance del bloqueo | Bloquear toda la app vs solo nuevas ventas (permitiendo consultas) | **A — Bloquear toda la app** |

> **Nota:** Decisiones tomadas el 2026-07-30. El plan se ajusta para implementar token firmado, SQLite como storage principal y bloqueo completo de la app en vencimiento de licencia o ventana de validación.

### 1. Seguridad de la licencia offline

**Opción A — Caché local + anti-rollback de reloj**
- ✅ Rápida de implementar; reutiliza `SubscriptionGuardService` y `saveSubscriptionData()`.
- ✅ Cero cambios en el backend; solo lógica cliente.
- ✅ No hay claves criptográficas que administrar.
- ⚠️ Un usuario avanzado con root puede editar `SharedPreferences` y `last_seen_timestamp` para extender la licencia.
- ⚠️ El reloj anti-rollback es una barrera débil: cambiar fecha del sistema justo antes del último timestamp vuelve a dejarlo pasar.
- **Mejor para:** MVP rápido o entornos donde el dispositivo no sale del control del negocio (TPV propio).

**Opción B — Token firmado por el servidor (HMAC/JWT)**
- ✅ Muy difícil de falsificar; el cliente no tiene la clave privada.
- ✅ No importa si cambian reloj o ficheros; el token lleva `fecha_fin` firmada y el cliente solo la puede leer, no modificar.
- ✅ Se puede añadir `id_tienda` e incluso `id_dispositivo` al token para ligar la licencia al hardware.
- ⚠️ Requiere nuevo RPC `fn_obtener_licencia_firmada` + secreto en el servidor.
- ⚠️ Si se pierde/regenera el secreto del servidor, todos los dispositivos deben reconectarse para renovar el token.
- ⚠️ Más trabajo en backend y en `SubscriptionGuardService` para parsear/validar la firma.
- **Mejor para:** producción con dispositivos en manos de terceros (vendedores) y requisito de control real.

**Recomendación:** Opción A si se necesita salir en días; Opción B si la prioridad es seguridad.

---

### 2. Almacenamiento del cache offline

**Opción A — Mantener SharedPreferences (actual)**
- ✅ Cero migración; el cache ya funciona (`offline_data`, pending operations, subscription, etc.).
- ✅ Fácil de depurar; JSON plano legible.
- ✅ Tiene límite en iOS/Android pero catálogos pequeños (< ~10 MB) entran sin problemas.
- ⚠️ Límite aproximado: 1–10 MB dependiendo del sistema operativo. Más de eso empieza a fallar silenciosamente o ser lento.
- ⚠️ Toda la carga/descarga se hace en memoria: parsear un JSON de productos grande produce lag y puede crashear.
- ⚠️ Sin consultas parciales: cada vez se lee/escribe TODO el cache.
- **Mejor para:** tiendas con pocos productos (< 1,000) o si se quiere la solución más rápida.

**Opción B — Migrar a SQLite (`sqflite`)**
- ✅ Límite prácticamente solo el espacio del disco; maneja catálogos grandes (miles de productos, imágenes referenciadas, históricos).
- ✅ Consultas parciales: buscar producto por SKU/nombre sin cargar todo el catálogo en memoria.
- ✅ Es el estándar para apps offline en Flutter.
- ⚠️ Es el mayor esfuerzo del plan: crear tablas/entidades/DAO, migrar `AutoSyncService` y todos los servicios que leen `offline_data`.
- ⚠️ Se debe implementar estrategia de inicialización/importación inicial.
- ⚠️ Tiene curva de depuración más alta que SharedPreferences.
- **Mejor para:** catálogos grandes, muchos vendedores o crecimiento futuro.

**Recomendación:** Opción A para validar el MVP offline y luego migrar a B en una fase posterior; o B directamente si el catálogo ya es grande.

---

### 3. Alcance del bloqueo cuando expira la ventana de licencia

**Opción A — Bloquear toda la app**
- ✅ Máximo control del negocio: sin licencia no se puede ni consultar.
- ✅ Más fácil de implementar: una sola pantalla de bloqueo en `main.dart` / `Navigator`.
- ⚠️ Experiencia agresiva para el vendedor: si solo quería consultar una venta anterior, se queda fuera.
- ⚠️ En zonas con mala conectividad puede dejar al negocio ciego hasta que alguien lo reconecte.
- **Mejor para:** negocios con control estricto o donde la consulta también es un servicio de pago.

**Opción B — Bloquear solo nuevas ventas/operaciones**
- ✅ UX amigable: el vendedor puede seguir consultando órdenes, turnos, productos.
- ✅ Reduce el riesgo de perder información histórica en manos del vendedor.
- ✅ Menos presión de soporte: no llaman por "la app se bloqueó".
- ⚠️ Más complejo: hay que inyectar el chequeo en puntos específicos (crear orden, abrir/cerrar turno, registrar egreso), no globalmente.
- ⚠️ Si se deja consultar mucho, el vendedor podría operar de facto offline indefinidamente sin validar.
- **Mejor para:** operaciones típicas de retail donde la consulta histórica debe seguir disponible.

**Recomendación:** Opción B con una advertencia/banner persistente ("nueva venta bloqueada hasta revalidar licencia"); más equilibrada para vendedores.

## Registro de progreso

| Fecha | Fase | Cambio |
|-------|------|--------|
| 2026-07-30 | — | Plan creado |
| 2026-07-30 | 1 | Config admin + columnas BD + getters ventiq_app |
| 2026-07-30 | 5 | RPC licencia firmada desplegada |
| 2026-07-30 | 2 | Token firmado + anti-reloj + bloqueo app + banner + auto-offline |
| 2026-07-30 | 4 | `syncModules` + UI "Sincronizar por módulos" |
| 2026-07-30 | 3.3 | Migración cache offline SharedPreferences → SQLite |
| 2026-07-30 | 3.1/4.2/5 | Auditoría offline + fotos encoladas + auto-sync unificado + RPCs verificados |
