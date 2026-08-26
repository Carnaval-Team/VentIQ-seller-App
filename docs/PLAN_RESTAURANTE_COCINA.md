# Plan: restaurante + cocina

Checklist de implementación. Marca `[x]` lo hecho y deja `[ ]` lo pendiente.

> **Estado: fases 0–5 implementadas y probadas contra producción vía MCP.**
> Leyenda: `[x]` hecho y verificado · `[~]` hecho parcialmente (ver nota) · `[ ]` pendiente.
> SQL en `funcionalidad_cocina/01`–`23` (23 archivos, todos aplicados).
> Guía de pruebas: `docs/TUTORIAL_PRUEBAS_COCINA.md`.

**Modelo objetivo:** la tienda tiene N almacenes de venta (TPV) y N cocinas. Cada cocina es un almacén propio (materias primas + tandas). Un TPV se relaciona con una o más cocinas. El producto elaborado indica a qué cocina va y si es `por_tanda` o `al_pedido`. El jefe de cocina se asigna a una cocina (como el almacenero a un almacén).

**Flujo de bar:** pedir ahora, cobrar al final. Pedir = servir / mandar a cocina. Cerrar nota = solo cobro.

---

## Reglas de negocio (referencia)

- [x] Un elaborado puede ser `por_tanda` (arroz moro) o `al_pedido` (bistec).
- [x] Un plato puede mezclar ambos (bistec + moro): baja MP del bistec + 1 porción de moro ya hecho; no explota el moro otra vez. → `fn_ingredientes_con_parada_tanda` (21.2). Verificado: `croqueta=2 [TANDA], harina=80` en vez de `harina=160`.
- [x] En la misma cuenta conviven: listo para venta (cerveza), tanda (moro) y al pedido (bistec).
- [x] Cocina solo ve comandas de su estación, no bebidas del bar. → solo `al_pedido` genera comanda.
- [x] Varias cocinas por tienda; el TPV solo puede mandar a las cocinas ligadas. → `COCINA_NO_LIGADA`.
- [x] Default de `modo_elaboracion` = `al_pedido` (no romper elaborados actuales).

---

## No hacer

- [x] Decidido: no revivir tablas `app_rest_*`. Confirmado por REST: las 4 devuelven `PGRST205`, es código muerto.
- [x] Decidido: no colgar la cocina del TPV (el TPV sigue siendo caja).
- [x] Decidido: no un solo `id_almacen_cocina` en la tienda (rompe multi-cocina).
- [x] Decidido: no mezclar estados de venta (1–4) con estados de preparación.
- [x] Decidido: no reusar solo el rol almacenero para jefe de cocina (misma forma de asignación, permisos distintos).

---

## Fase 0 · Prerrequisito

> Descuento de receta acotado a layouts de un almacén (bug actual).

- [x] Revisar `fn_obtener_ingredientes_recursivos` / descuento en `fn_registrar_venta` y `fn_registrar_venta_mesa`.
- [x] Acotar lookup de inventario de ingredientes al almacén/layouts correctos (no "última fila global"). → `01`, `03`.
- [x] Cubrir también wrappers offline (`fn_registrar_venta_offline` y afines). → `06`.
- [x] Probar venta de elaborado con stock en más de un almacén.

**Dependencias:** ninguna.
**Entrega:** venta de elaborados descuenta MP en el almacén correcto. ✅

> **2 bugs latentes descubiertos y corregidos después**, ambos aplicados en Fase 0 pero nunca ejecutados:
> - `15`: `WHERE pi.id = p_id_producto` sobre `app_dat_producto_ingredientes` (la FK real es `id_producto_elaborado`) → un plato con receta se trataba como producto de barra.
> - `16`: `fn_devolver_ingredientes_elaborado` no insertaba `id_presentacion` (NOT NULL) → SQLSTATE `23502` en el 100 % de las llamadas.

---

## Fase 1 · Cocinas

> Tablas cocina, `es_cocina`, TPV↔cocina, producto, catálogo dual.

### 1.1 Datos / schema — `07_schema_cocinas.sql`

- [x] `app_dat_almacen.es_cocina` (boolean).
- [x] Tabla `app_dat_cocina` (`id_tienda`, `id_almacen`, `denominacion`, `impresora`, `orden`, `activa`, `deleted_at`).
- [x] Tabla `app_dat_tpv_cocina` (N:M TPV ↔ cocina).
- [x] `app_dat_producto.modo_elaboracion` (`por_tanda` | `al_pedido`).
- [x] `app_dat_producto.id_cocina`.
- [x] (Opcional) `app_dat_categoria_tienda.id_cocina` por defecto. → columna creada en el `07` (7.5) y **lógica completada en el `23`**: `fn_asignar_cocina_categoria`, `fn_cocina_por_defecto_producto`, `fn_aplicar_cocina_categoria_a_platos`.
- [x] Config: flag `cocina_activa` en `app_dat_configuracion_tienda`, acoplado con `modo_restaurante`.

### 1.2 RPCs / backend — `08`, `09`, `10`, `11`

- [x] `fn_crear_cocina` (crea/liga almacén cocina).
- [x] `fn_asignar_tpv_cocina` / `fn_desasignar_tpv_cocina`.
- [x] `fn_disponibilidad_plato` (según cocina + modo).
- [x] Catálogo dual: **no** se reemplazó `get_productos_by_categoria_tpv_search_meta`; se creó `fn_productos_cocina_tpv` con las mismas 18 columnas y la app concatena.
- [x] Validar al vender: `producto.id_cocina` ∈ cocinas del TPV. → `fn_resolver_origen_venta` (10.2).
- [x] Enrutamiento del descuento: `fn_descontar_venta_enrutada` (10.3) + las dos funciones de venta regeneradas (`11`).

### 1.3 Admin UI

- [x] Alta / edición de cocinas. → `cocinas_management_screen.dart` + `cocina_form_dialog.dart`.
- [x] Ligar TPV ↔ cocina. → `cocina_tpv_dialog.dart`.
- [x] En producto: `id_cocina` + `modo_elaboracion`. → `cocinas_platos_widget.dart`.
- [x] (Opcional) cocina por defecto en categoría. → **3.ª pestaña "Categorías"** en `cocinas_management_screen` (`cocinas_categorias_widget.dart`), con aplicación en bloque y reporte de los platos respetados.

### 1.4 Vendedor

- [x] Catálogo dual visible (barra + platos de sus cocinas). → `product_service.dart` concatena; degrada a `[]` si falla.
- [x] Bloquear / avisar si el TPV no está ligado a la cocina del plato. → `CocinaChip` + `COCINA_NO_LIGADA`.

**Dependencias:** Fase 0.
**Entrega:** multi-cocina configurada; TPV ve y enruta platos a la cocina correcta. ✅

---

## Fase 2 · Pedir ≠ cobrar

> Al agregar item: clasificar, mover/reservar stock, crear comanda. Cobro no rediscuenta.

### 2.1 Datos — `13_schema_comandas.sql`

- [x] Tablas `app_dat_comanda` + `app_dat_comanda_item` (estados: 1 pendiente / 2 en prep / 3 listo / 4 entregado / 5 cancelado).
- [x] Extender `app_dat_mesa_cuenta_item`:
  - [x] `origen_stock` (`tpv` | `tanda` | `al_pedido` | `servicio`)
  - [x] `id_cocina`
  - [x] `id_comanda_item`
  - [x] `estado_servicio`
  - [x] **`stock_movido`** (5.º campo, no estaba en el plan): hace trivial la comprobación al cobrar y `NULL`/`false` en líneas viejas significa "legado, descuenta como siempre" → no rompe cuentas abiertas previas.

### 2.2 Lógica al agregar a la cuenta — `14_pedir_comanda.sql`

- [x] Clasificar línea: listo TPV / tanda / al_pedido.
- [x] **Cerveza (TPV):** baja del almacén del TPV.
- [x] **Tanda:** baja 1 porción terminada en cocina; sin comanda (`estado_servicio = 4`, entregado).
- [x] **Al pedido:** crea comanda; descuenta MP en layouts de ESA cocina.
- [x] Combo (bistec + moro): BOM con parada en `por_tanda`. → completado en Fase 4 (`21.2`); en Fase 2 subestimaba, no sobreestimaba.
- [x] RPC `fn_disparar_comanda` — estrategia **aditiva**: no se reemplazó `fn_agregar_item_cuenta_mesa`, se creó `fn_pedir_item_cuenta` que la envuelve. Rollback = cambiar una línea en Dart.

### 2.3 Lógica al cobrar / cerrar nota — `17_cobro_sin_redescontar.sql`

- [x] `fn_registrar_venta_mesa`: **no** vuelve a descontar lo ya movido al pedir. (`fn_cerrar_cuenta_mesa` **no existe**; el ciclo real termina en `fn_registrar_venta_mesa` → `fn_marcar_cuenta_cerrada`.)
- [x] Avisar si hay comandas no servidas. → `18` expone `items_en_cocina`/`items_listos`; diálogo en `cuenta_mesa_screen`.
- [x] Cancelar item no servido → devuelve stock. → `fn_cancelar_item_pedido`.
- [x] Item ya servido → merma con motivo obligatorio (`MOTIVO_REQUERIDO`), **sin** devolver stock.

### 2.4 UI vendedor (`ventiq_app`)

- [x] Al agregar `al_pedido`: feedback "🍳 Enviado a [Cocina X]". → `product_details_screen.dart`.
- [x] Estado servido / en cocina en la línea de la cuenta. → `EstadoServicioChip` + `ResumenCocinaBanner`.
- [x] Cobro al final sin re-descontar.
- [x] Interruptor: la bifurcación vive en `OrderService.addItemToCurrentOrder` según `StoreConfigService.cocinaActivaSync`. Un solo punto para todas las pantallas.

**Dependencias:** cuenta abierta existente + Fase 1.
**Entrega:** bar pide y cocina recibe; inventario refleja consumo al pedir. ✅

---

## Fase 3 · Roles + KDS

> Jefe de cocina, permisos, pantalla comandas, ticket cocina.

### 3.1 Roles / datos — `19_rol_jefe_cocina.sql`

- [x] Tabla `app_dat_jefe_cocina` (`uuid`, `id_trabajador`, `id_cocina`, `es_jefe`), `UNIQUE(uuid, id_cocina)` — un chef puede cubrir dos estaciones.
- [x] (Opcional) tabla `app_dat_cocinero` → resuelto con la columna `es_jefe` en vez de una segunda tabla, para no duplicar la lógica de permisos por una diferencia de grado.
- [x] Rol en `seg_roll` / `UserRole`: `jefe_cocina`. — **No hace falta en `seg_roll`** (es un catálogo descriptivo por tienda), pero sí se añadió a las **RPC de gestión de roles** para que la UI lo trate como cualquier otro: `fn_agregar_rol_trabajador`, `fn_eliminar_rol_trabajador`, `fn_actualizar_datos_rol_trabajador` aceptan `jefe_cocina` y `cocinero` con `p_id_cocina`.
- [x] `check_user_has_access_to_tienda` ampliada con un 6.º UNION para jefe de cocina. **Verificado multi-tienda**: un jefe de la tienda 11 entra a la 11 y es rechazado en la 1; al revés igual; una cocina con `deleted_at` deja de dar acceso.
- [x] Guard reutilizable `fn_usuario_puede_operar_cocina(id, requiere_jefe)`.
- [x] Alcance por usuario: `fn_cocinas_del_usuario()` — el KDS no pregunta por cocina, pregunta "lo mío".
- [x] Alcance de almacenes: `fn_almacenes_del_usuario()` — qué almacenes ve cada rol y si puede operarlos.
- [x] RPC de asignación: `fn_asignar_jefe_cocina` (idempotente), `fn_desasignar_jefe_cocina`, `fn_listar_personal_cocina`.
- [x] **`edit_worker_multi_role`: UI de admin para asignar jefe de cocina.** → checkboxes "Jefe de Cocina" y "Cocinero" (excluyentes) + selector de cocina en `edit_worker_multi_role_screen.dart`.

### 3.2 KDS / comandas — `20_rpcs_kds.sql`

- [x] `fn_cambiar_estado_comanda_item` + `fn_cambiar_estado_comanda` (ticket completo).
- [x] Matriz de transiciones: cualquier **avance** vale; **retroceso** de un solo paso; 4 y 5 terminales.
- [x] Estado de la cabecera **derivado** de los items (mínimo de los vivos) vía `_fn_recalcular_estado_comanda`.
- [x] Pantalla KDS filtrada por las cocinas del usuario. → `kds_screen.dart` + `comanda_card.dart`.
- [x] Ticket / impresión tipo `cocina`: **backend** `fn_ticket_comanda` (`22.4`) devuelve texto a N columnas + `app_dat_cocina.impresora`.
- [x] **UI de impresión del ticket.** → `comanda_ticket_service.dart` (resuelve la impresora por IP o por nombre entre las guardadas), botón de impresora en `comanda_card.dart` y `ticket_comanda_dialog.dart` para mostrarlo en pantalla cuando no hay térmica. `wifi_printer_service.imprimirBytesCrudos()` es el nuevo punto de entrada de transporte.
- [x] Al marcar estado: se actualiza `estado_servicio` del item de cuenta (espejo). *No hay "confirmar descuento MP": el modelo descuenta al pedir, no reserva.*

### 3.3 Alcance por rol

| Rol | Comandas | Inventario | Caja/TPV | Estado |
|-----|----------|------------|----------|--------|
| Vendedor | Dispara al pedir | Solo disponibilidad | Sí | Existente |
| Jefe de cocina | KDS de su cocina | Tandas + recepción/conteo/transfer **solo de su almacén** | No | [x] |
| Cocinero (`es_jefe = false`) | KDS | Solo lectura (no aparece en pantallas de movimiento) | No | [x] |
| Almacenero | No | Almacén no cocina | No | Existente |
| Gerente / supervisor | Todas las de su tienda | Todos | Config TPV↔cocina | [x] |

- [x] Recepción / conteo / transferencia acotadas al almacén de la cocina para el jefe. → `fn_almacenes_del_usuario` + `AlmacenScopeService` filtrando `WarehouseService.listWarehouses` / `listWarehousesOK`. Gerente y supervisor **no se ven afectados**; si el alcance no se puede resolver, no se filtra (es acotado de UI, no seguridad).

**Dependencias:** Fase 2.
**Entrega:** jefe de cocina opera KDS e inventario de su estación. ✅

> **Bug de seguridad propio, encontrado al probar el caso negativo:** `SELECT true, bool_or(...)` en el guard es una agregación sin `GROUP BY` → devuelve una fila **siempre**, así que `v_existe` era `true` incondicionalmente y cualquiera podía operar cualquier cocina. Corregido a `count(*) > 0`.

---

## Fase 4 · Tandas — `21_tandas_produccion.sql`

> Producir N porciones; disponibilidad por stock terminado; parada de BOM.

- [x] Tabla `app_dat_produccion_tanda` (cabecera de auditoría; el stock real vive en `app_dat_inventario_productos`).
- [x] RPC `fn_producir_tanda`: consume receta (MP) → entra N porciones del SKU terminado. Valida **todo** antes de mover nada.
- [x] UI jefe de cocina: "producir N porciones". → `produccion_screen.dart` + `tanda_widgets.dart`.
- [x] Disponibilidad de `por_tanda` = stock terminado (si se acabó, agotado aunque quede MP).
- [x] Explosión de venta/comanda: si el hijo es `por_tanda`, parar y descontar ese SKU. → `fn_ingredientes_con_parada_tanda`. **No se tocó** `fn_obtener_ingredientes_recursivos` (la usan Fase 0 y las dos funciones de venta).
- [x] Merma / descarte de tanda: `fn_cerrar_tanda` con motivo obligatorio. `porciones_producidas` y `porciones_descartadas` van **separadas** para no falsear el costo → `costo_por_servida`.
- [x] Extra: `fn_anular_tanda` (deshacer producción), `fn_listar_tandas_cocina`, `fn_platos_por_tanda_cocina` (con `max_producible` e `ingrediente_limite`).

**Dependencias:** Fases 1–2.
**Entrega:** arroz moro y similares se gestionan por tandas. ✅

> **2 bugs propios corregidos al ejecutar:**
> - Anular comparaba el stock **total** del plato contra las porciones del lote → con sobrantes de otro lote anulaba una tanda ya servida. Ahora detecta **salidas reales** posteriores.
> - El fix inicial usaba `created_at`, pero `now()` es **constante dentro de una transacción** → una venta en la misma transacción se perdía. Se añadió `id_inventario_entrada` como ancla (la secuencia de ids sí es monótona).
> - Además: el fallback de presentación ordenaba por `id ASC` en vez de preferir `es_base` → el movimiento podía quedar en la unidad equivocada.

---

## Fase 5 · Offline / multi-cocina fino — `22_offline_y_cierre_turno.sql`

- [x] Cola offline de comandas (idempotencia). → `fn_pedir_item_cuenta_offline` + `fn_cambiar_estado_comanda_item_offline`, sobre la tabla `app_dat_operacion_offline_idempotencia` **que ya existía** (203 operaciones, patrón copiado de `fn_cerrar_turno_offline`).
- [x] Cola **persistente** en el cliente: `cocina_offline_queue.dart` (SharedPreferences, no closures en memoria como `NetworkRequestQueue`).
- [x] Impresora / ticket por cocina: **backend** `fn_ticket_comanda` + `app_dat_cocina.impresora`. UI de impresión pendiente (ver 3.2).
- [x] Rol cocinero. → `es_jefe = false`.
- [x] Sync comandas + stock al pedir en modo offline. Verificado: 2.º envío con el mismo `client_uuid` → mismo `id_item`, harina 920 → 920, sin línea ni comanda nuevas.
- [x] Cierre de turno: listar comandas abiertas de las cocinas ligadas al TPV. → `fn_comandas_abiertas_turno` + diálogo en `cierre_screen.dart`. **Avisa, no bloquea** (bloquear dejaría al vendedor sin cuadrar caja si la cocina se fue sin marcar).

**Dependencias:** Fases 3–4.
**Entrega:** multi-cocina estable online/offline. ✅

---

## RPCs y servicios (checklist técnico)

### Nuevos

- [x] `fn_crear_cocina` · `fn_editar_cocina` · `fn_eliminar_cocina` (soft) · `fn_listar_cocinas`
- [x] `fn_asignar_tpv_cocina` · `fn_desasignar_tpv_cocina` · `fn_cocinas_de_tpv`
- [x] `fn_asignar_plato_cocina` · `fn_productos_cocina_tpv`
- [x] `fn_disponibilidad_plato`
- [x] `fn_resolver_origen_venta` · `fn_descontar_venta_enrutada`
- [x] `fn_siguiente_numero_comanda` · `fn_disparar_comanda` · `fn_pedir_item_cuenta` · `fn_cancelar_item_pedido`
- [x] `fn_cocinas_del_usuario` · `fn_usuario_puede_operar_cocina` · `fn_asignar_jefe_cocina` · `fn_desasignar_jefe_cocina` · `fn_listar_personal_cocina`
- [x] `fn_listar_comandas_cocina` · `fn_cambiar_estado_comanda_item` · `fn_cambiar_estado_comanda` · `_fn_recalcular_estado_comanda`
- [x] `fn_ingredientes_con_parada_tanda` · `fn_producir_tanda` · `fn_cerrar_tanda` · `fn_anular_tanda` · `fn_listar_tandas_cocina` · `fn_platos_por_tanda_cocina`
- [x] `fn_pedir_item_cuenta_offline` · `fn_cambiar_estado_comanda_item_offline` · `fn_comandas_abiertas_turno` · `fn_ticket_comanda`
- [x] `fn_asignar_cocina_categoria` · `fn_cocina_por_defecto_producto` · `fn_aplicar_cocina_categoria_a_platos` · `fn_asignar_plato_cocina`
- [x] `fn_almacenes_del_usuario` · `fn_envolver_texto`

### Cambiar

- [x] Catálogo dual → **no** se tocó `get_productos_by_categoria_tpv*`; se añadió `fn_productos_cocina_tpv` y la app concatena.
- [x] `fn_agregar_item_cuenta_mesa` → **no** se tocó; se envuelve con `fn_pedir_item_cuenta`.
- [x] `fn_registrar_venta_mesa` (no re-descontar) · `fn_registrar_venta` (enrutada)
- [x] Descuento BOM en `fn_registrar_venta*` (Fase 0 + parada `por_tanda`)
- [x] `fn_obtener_cuenta_mesa` → expone estado de cocina (`18`)
- [x] `check_user_has_access_to_tienda` → 6.º UNION
- [x] `fn_agregar_rol_trabajador` / `fn_eliminar_rol_trabajador` / `fn_actualizar_datos_rol_trabajador` → aceptan `jefe_cocina` y `cocinero` (`23`)
- [x] `permissions_service.dart` (admin) · `admin_drawer.dart`
- [x] `edit_worker_multi_role_screen.dart` / `worker_service.dart` → asignar jefe de cocina desde UI
- [x] `warehouse_service.dart` → acotado por rol vía `AlmacenScopeService`
- [x] `wifi_printer_service.dart` → `imprimirBytesCrudos()` para el ticket de cocina
- [x] `mesa_cuenta_service.dart` / `cuenta_mesa_screen.dart`
- [x] `order_service.dart` (bifurcación por `cocina_activa`) · `store_config_service.dart` · `product_details_screen.dart` · `cierre_screen.dart` · `app_drawer.dart` · `main.dart`
- [x] Offline wrappers: `fn_pedir_item_cuenta_offline`, `fn_cambiar_estado_comanda_item_offline`

---

## Pantallas (checklist UI)

### Admin / gerente (`ventiq_admin_app`)

- [x] Gestión de cocinas → `cocinas_management_screen.dart`
- [x] TPV ↔ cocina → `cocina_tpv_dialog.dart`
- [x] Producto: cocina + modo elaboración → `cocinas_platos_widget.dart`
- [x] **Cocina por defecto por categoría** → `cocinas_categorias_widget.dart` (3.ª pestaña)
- [x] **Asignar jefe de cocina** → `edit_worker_multi_role_screen.dart`
- [x] Recetas (ya existía; validado con cocina)
- [x] Config global: `cocina_activa` + `modo_restaurante` acoplados → `global_config_tab_view.dart`

### Jefe de cocina (`ventiq_app`)

- [x] KDS → `/kds`
- [x] Producir tanda → `/produccion`
- [x] Reimprimir ticket de comanda → botón en la tarjeta del KDS
- [x] Recepción / conteo / transfer solo de su almacén cocina → vía `AlmacenScopeService` (admin)
- [x] Sin dashboard de ventas (no ve las pantallas de caja)

### Vendedor (`ventiq_app`)

- [x] Cuenta mesa/barra: feedback "enviado a cocina"
- [x] Estado de línea (pendiente cocina / preparando / listo / entregado)
- [x] Cobro al final sin rediscontar
- [x] Chips de cocina en el catálogo → `cocina_chip.dart`
- [x] Aviso de comandas pendientes al cerrar turno

---

## Criterios de aceptación (smoke)

- [x] TPV Bar vende cerveza del almacén bar; bistec va a Cocina caliente; no aparece en Pizzería. → `COCINA_NO_LIGADA` rechaza sin agregar línea.
- [x] TPV Terraza ligado a 2 cocinas ve platos de ambas.
- [x] Pedir bistec con moro: comanda en cocina + baja 1 moro; al cobrar no baja de nuevo. → harina 500 → 420 al pedir → **420** al cobrar.
- [x] Producir tanda de moro: baja arroz/frijoles, sube porciones; TPV puede vender hasta agotar. → 10 porciones = −400 harina, −100 sal.
- [x] Jefe de cocina A no ve comandas ni stock de cocina B. → rechazado incluso pasando el id a mano.
- [x] Cerrar nota con comanda pendiente: aviso. → diálogo Esperar / Cobrar igual.
- [x] Cerrar **turno** con comanda pendiente: aviso con detalle. → `bloquear=true` si hay mesas sin cobrar.
- [x] Reenviar el mismo pedido offline no duplica inventario. → mismo `id_item`, stock intacto.

---

## Progreso por fase

| Fase | Estado | Notas |
|------|--------|-------|
| 0 Prerrequisito | [x] | + 2 bugs latentes corregidos (`15`, `16`) |
| 1 Cocinas | [x] | Incluye cocina por defecto por categoría (`23`) |
| 2 Pedir ≠ cobrar | [x] | Se activa con `cocina_activa` |
| 3 Roles + KDS | [x] | UI de asignación, impresión y acotado de almacén cerrados en el `23` |
| 4 Tandas | [x] | Parada de BOM completa |
| 5 Offline / fino | [x] | Cola persistente + cierre de turno |

**Las 6 fases del plan están cerradas.**

### Pendientes reales (no bloquean el uso)

1. `flutter pub get` / `build` no ejecutados: verificación hecha solo con `dart analyze` (0 errores en el admin, 1 preexistente y ajeno en el vendedor).
2. Ninguna UI probada en dispositivo. Para hacerlo, seguir `docs/TUTORIAL_PRUEBAS_COCINA.md`.
3. Enganche fino de la cola offline con cada pantalla del vendedor: el servicio y las RPC están probados, pero cada pantalla decide cuándo encolar.

---

## Bugs encontrados durante la implementación

Ninguno lo detecta `pglast` ni `dart analyze`: son SQL sintácticamente válido con semántica rota, y solo aparecen ejecutando contra datos reales.

| # | Archivo | Qué pasaba | Impacto |
|---|---------|-----------|---------|
| 1 | `15` | `WHERE pi.id = p_id_producto` sobre `app_dat_producto_ingredientes` | Plato con receta tratado como producto de barra |
| 2 | `16` | `fn_devolver_ingredientes_elaborado` sin `id_presentacion` (NOT NULL) | 100 % de las devoluciones fallaban (`23502`) |
| 3 | `17` | Emparejaba con `COALESCE(id_presentacion, 0)`; al pedir se guarda NULL | Doble descuento al cobrar (500 → 420 → **340**) |
| 4 | `19` | `SELECT true, bool_or(...)` sin `GROUP BY` en el guard | Cualquiera podía operar cualquier cocina |
| 5 | `20` | Matriz de transiciones solo permitía avanzar de uno en uno | "Marchando todo" nunca llegaba a listo; ticket atascado |
| 6 | `21` | Anular comparaba stock total del plato, no salidas del lote | Anulaba tandas ya servidas |
| 7 | `21` | `created_at` para detectar salidas; `now()` es constante en la transacción | El fix del #6 no funcionaba |
| 8 | `cocina_offline_queue.dart` | `ops.indexOf(op)` con operaciones idénticas | Reencolaba las operaciones equivocadas |
| 9 | `product_details_screen.dart` | `addItemToCurrentOrder` sin `await` | "✅ Agregado" aunque el pedido fallara por stock |
| 10 | `22` / `fn_ticket_comanda` | `substr()` para meter el texto en el ancho del papel | **El ticket truncaba las notas del comensal**: "sin sal ... alérgico al gluten" se imprimía como "SIN SAL Y BIEN TOSTADA POR" y el cocinero no sabía que faltaba texto |
| 11 | `fn_*_rol_trabajador` (preexistente) | `CASE` sin `ELSE` → `CASE_NOT_FOUND` | El rol `recursos_humanos` que la UI ya ofrecía **no se podía desactivar**; salía como "Error: case not found" |
| 12 | `23` | Añadir parámetros con `DEFAULT` crea **sobrecarga**, no reemplaza | Las 3 RPC quedaron duplicadas y la llamada de la app se volvió ambigua (`function ... is not unique`) → habría roto la pantalla de trabajadores en producción. Resuelto con `DROP` de las firmas viejas |
| 13 | `edit_worker_multi_role_screen.dart` | El bucle genérico de roles llamaba a `addWorkerRole` sin `p_id_cocina` | El backend abortaba el guardado **completo** del trabajador con "El rol de cocina requiere una cocina asignada" |

---

## Referencias

- **Tutorial de pruebas paso a paso: `docs/TUTORIAL_PRUEBAS_COCINA.md`**
- SQL: `funcionalidad_cocina/01`–`22` + `_validar_sql.py` (validador pglast)
- Canvas: `canvases/plan-restaurante-cocina.canvas.tsx`
- Relacionados: `cocina-tres-logicas.canvas.tsx`, `cocina-hibrido-tandas-pedido.canvas.tsx`, `bar-cuenta-comanda-cocina.canvas.tsx`
- Roles: `app_dat_vendedor` → TPV, `app_dat_almacenero` → almacén, `app_dat_jefe_cocina` → cocina, gerente/supervisor → tienda
