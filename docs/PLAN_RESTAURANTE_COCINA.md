# Plan: restaurante + cocina

Checklist de implementación. Marca `[x]` lo hecho y deja `[ ]` lo pendiente.

**Modelo objetivo:** la tienda tiene N almacenes de venta (TPV) y N cocinas. Cada cocina es un almacén propio (materias primas + tandas). Un TPV se relaciona con una o más cocinas. El producto elaborado indica a qué cocina va y si es `por_tanda` o `al_pedido`. El jefe de cocina se asigna a una cocina (como el almacenero a un almacén).

**Flujo de bar:** pedir ahora, cobrar al final. Pedir = servir / mandar a cocina. Cerrar nota = solo cobro.

---

## Reglas de negocio (referencia)

- [ ] Un elaborado puede ser `por_tanda` (arroz moro) o `al_pedido` (bistec).
- [ ] Un plato puede mezclar ambos (bistec + moro): baja MP del bistec + 1 porción de moro ya hecho; no explota el moro otra vez.
- [ ] En la misma cuenta conviven: listo para venta (cerveza), tanda (moro) y al pedido (bistec).
- [ ] Cocina solo ve comandas de su estación, no bebidas del bar.
- [ ] Varias cocinas por tienda; el TPV solo puede mandar a las cocinas ligadas.
- [ ] Default de `modo_elaboracion` = `al_pedido` (no romper elaborados actuales).

---

## No hacer

- [x] Decidido: no revivir tablas `app_rest_*`.
- [x] Decidido: no colgar la cocina del TPV (el TPV sigue siendo caja).
- [x] Decidido: no un solo `id_almacen_cocina` en la tienda (rompe multi-cocina).
- [x] Decidido: no mezclar estados de venta (1–4) con estados de preparación.
- [x] Decidido: no reusar solo el rol almacenero para jefe de cocina (misma forma de asignación, permisos distintos).

---

## Fase 0 · Prerrequisito

> Descuento de receta acotado a layouts de un almacén (bug actual).

- [ ] Revisar `fn_obtener_ingredientes_recursivos` / descuento en `fn_registrar_venta` y `fn_registrar_venta_mesa`.
- [ ] Acotar lookup de inventario de ingredientes al almacén/layouts correctos (no “última fila global”).
- [ ] Cubrir también wrappers offline (`fn_registrar_venta_offline` y afines).
- [ ] Probar venta de elaborado con stock en más de un almacén.

**Dependencias:** ninguna.  
**Entrega:** venta de elaborados descuenta MP en el almacén correcto.

---

## Fase 1 · Cocinas

> Tablas cocina, `es_cocina`, TPV↔cocina, producto, catálogo dual.

### 1.1 Datos / schema

- [ ] `app_dat_almacen.es_cocina` (boolean).
- [ ] Tabla `app_dat_cocina` (`id_tienda`, `id_almacen`, `denominacion`, …).
- [ ] Tabla `app_dat_tpv_cocina` (N:M TPV ↔ cocina).
- [ ] `app_dat_producto.modo_elaboracion` (`por_tanda` | `al_pedido`).
- [ ] `app_dat_producto.id_cocina`.
- [ ] (Opcional) `app_dat_categoria_tienda.id_cocina` por defecto.
- [ ] Config: `tickets_a_imprimir` admite `cocina`; flag `cocina_activa` si hace falta.

### 1.2 RPCs / backend

- [ ] `fn_crear_cocina` (crea/liga almacén cocina).
- [ ] `fn_asignar_tpv_cocina` / desasignar.
- [ ] `fn_disponibilidad_plato` (según cocina + modo).
- [ ] Cambiar catálogo TPV (`get_productos_by_categoria_tpv*`) → unión: almacén TPV + elaborados de cocinas ligadas.
- [ ] Validar al vender: producto.`id_cocina` ∈ cocinas del TPV.

### 1.3 Admin UI

- [ ] Alta / edición de cocinas.
- [ ] Ligar TPV ↔ cocina.
- [ ] En producto: `id_cocina` + `modo_elaboracion` (+ receta existente).
- [ ] (Opcional) cocina por defecto en categoría.

### 1.4 Vendedor

- [ ] Catálogo dual visible (barra + platos de sus cocinas).
- [ ] Bloquear / avisar si el TPV no está ligado a la cocina del plato.

**Dependencias:** Fase 0.  
**Entrega:** multi-cocina configurada; TPV ve y enruta platos a la cocina correcta.

---

## Fase 2 · Pedir ≠ cobrar

> Al agregar item: clasificar, mover/reservar stock, crear comanda. Cobro no rediscuenta.

### 2.1 Datos

- [ ] Tablas `app_dat_comanda` + `app_dat_comanda_item` (estados cocina: pendiente / en prep / listo / entregado / cancelado).
- [ ] Extender `app_dat_mesa_cuenta_item`:
  - [ ] `origen_stock` (`tpv` | `tanda` | `al_pedido`)
  - [ ] `id_cocina`
  - [ ] `id_comanda_item`
  - [ ] `estado_servicio`

### 2.2 Lógica al agregar a la cuenta

- [ ] Clasificar línea: listo TPV / tanda / al_pedido.
- [ ] **Cerveza (TPV):** baja (o reserva) del almacén del TPV.
- [ ] **Tanda:** baja 1 porción terminada en cocina; sin comanda de cocción (pase opcional).
- [ ] **Al pedido:** crea comanda; reserva/descuenta MP en layouts de ESA cocina.
- [ ] Combo (bistec + moro): MP del al_pedido + porción de tanda; BOM con parada en `por_tanda`.
- [ ] RPC `fn_disparar_comanda` (desde `fn_agregar_item_cuenta_mesa` o post-hook).

### 2.3 Lógica al cobrar / cerrar nota

- [ ] `fn_cerrar_cuenta_mesa` / `fn_registrar_venta_mesa`: **no** volver a descontar lo ya movido al pedir.
- [ ] Avisar o bloquear si hay comandas no servidas.
- [ ] Cancelar item no servido → devolver reserva.
- [ ] Item ya servido → merma / anulación con motivo.

### 2.4 UI vendedor (`ventiq_app`)

- [ ] Al agregar `al_pedido`: feedback “enviado a [Cocina X]”.
- [ ] Estado servido / en cocina en la línea de la cuenta.
- [ ] Cobro al final sin re-descontar.

**Dependencias:** cuenta abierta existente + Fase 1.  
**Entrega:** bar pide y cocina recibe; inventario refleja consumo al pedir.

---

## Fase 3 · Roles + KDS

> Jefe de cocina, permisos, pantalla comandas, ticket cocina.

### 3.1 Roles / datos

- [ ] Tabla `app_dat_jefe_cocina` (`uuid`, `id_trabajador`, `id_cocina`).
- [ ] (Opcional) tabla `app_dat_cocinero` (solo KDS).
- [ ] Rol en `seg_roll` / `UserRole`: `jefe_cocina` (+ `cocinero`).
- [ ] `permissions_service`: pantallas KDS + inventario de su almacén cocina.
- [ ] `edit_worker_multi_role`: asignar jefe de cocina eligiendo cocina (como almacenero).

### 3.2 KDS / comandas

- [ ] `fn_cambiar_estado_comanda` (pendiente → en prep → listo → entregado / cancelado).
- [ ] Pantalla KDS filtrada por `id_cocina` del usuario.
- [ ] Ticket / impresión tipo `cocina` (impresora de esa cocina).
- [ ] Al marcar listo/entregado: confirmar descuento MP si había reserva; actualizar `estado_servicio` del item de cuenta.

### 3.3 Alcance por rol

| Rol | Comandas | Inventario | Caja/TPV | Estado |
|-----|----------|------------|----------|--------|
| Vendedor | Dispara al pedir | Solo disponibilidad | Sí | Existente |
| Jefe de cocina | KDS de su cocina | Recepción, tandas, conteo, transfer de ESA cocina | No | [ ] |
| Cocinero (opc.) | KDS | No | No | [ ] |
| Almacenero | No | Almacén no cocina | No | Existente |
| Gerente / supervisor | Todas | Todos | Config TPV↔cocina | Existente + [ ] config cocina |

**Dependencias:** Fase 2.  
**Entrega:** jefe de cocina opera KDS e inventario de su estación.

---

## Fase 4 · Tandas

> Producir N porciones; disponibilidad por stock terminado; parada de BOM.

- [ ] Tabla `app_dat_produccion_tanda` (o equivalente).
- [ ] RPC `fn_producir_tanda`: consume receta (MP) → entra N porciones del SKU terminado.
- [ ] UI jefe de cocina: “producir N porciones”.
- [ ] Disponibilidad de `por_tanda` = stock terminado (si se acabó, agotado aunque quede MP).
- [ ] Explosión de venta/comanda: si el hijo es `por_tanda`, parar y descontar ese SKU.
- [ ] Merma / descarte de tanda (opcional en esta fase).

**Dependencias:** Fases 1–2.  
**Entrega:** arroz moro y similares se gestionan por tandas.

---

## Fase 5 · Offline / multi-cocina fino

- [ ] Cola offline de comandas (idempotencia).
- [ ] Impresora / ticket por cocina.
- [ ] Rol cocinero (si no se hizo en fase 3).
- [ ] Sync comandas + stock al pedir en full-offline / modo offline.
- [ ] Cierre de turno: listar o bloquear comandas abiertas de las cocinas ligadas al almacén/TPV.

**Dependencias:** Fases 3–4.  
**Entrega:** multi-cocina estable online/offline.

---

## RPCs y servicios (checklist técnico)

### Nuevos

- [ ] `fn_crear_cocina`
- [ ] `fn_asignar_tpv_cocina`
- [ ] `fn_disparar_comanda`
- [ ] `fn_cambiar_estado_comanda`
- [ ] `fn_producir_tanda`
- [ ] `fn_disponibilidad_plato`

### Cambiar

- [ ] `get_productos_by_categoria_tpv*` (catálogo dual)
- [ ] `fn_agregar_item_cuenta_mesa`
- [ ] `fn_cerrar_cuenta_mesa` / `fn_registrar_venta_mesa`
- [ ] Descuento BOM en `fn_registrar_venta*` (Fase 0 + parada `por_tanda`)
- [ ] `permissions_service.dart`
- [ ] `edit_worker_multi_role_screen.dart` / `worker_service`
- [ ] `admin_drawer.dart`
- [ ] `mesa_cuenta_service.dart` / `cuenta_mesa_screen.dart`
- [ ] Offline sale wrappers si aplica

---

## Pantallas (checklist UI)

### Admin / gerente

- [ ] Gestión de cocinas
- [ ] TPV ↔ cocina
- [ ] Producto: cocina + modo elaboración
- [ ] Asignar jefe de cocina
- [ ] Recetas (ya existe; validar con cocina)

### Jefe de cocina

- [ ] KDS
- [ ] Producir tanda
- [ ] Recepción / conteo / transfer solo de su almacén cocina
- [ ] Sin dashboard de ventas ni otros almacenes

### Vendedor (`ventiq_app`)

- [ ] Cuenta mesa/barra: feedback “enviado a cocina”
- [ ] Estado de línea (pendiente cocina / listo / servido)
- [ ] Cobro al final sin rediscontar

---

## Criterios de aceptación (smoke)

- [ ] TPV Bar vende cerveza del almacén bar; bistec va a Cocina caliente; no aparece en Pizzería.
- [ ] TPV Terraza ligado a 2 cocinas ve platos de ambas.
- [ ] Pedir bistec con moro: comanda en cocina + baja 1 moro; al cobrar no baja de nuevo.
- [ ] Producir tanda de moro: baja arroz/frijoles, sube porciones; TPV puede vender hasta agotar.
- [ ] Jefe de cocina A no ve comandas ni stock de cocina B.
- [ ] Cerrar nota con comanda pendiente: aviso o bloqueo según regla definida.

---

## Progreso por fase

| Fase | Estado | Notas |
|------|--------|-------|
| 0 Prerrequisito | [ ] | |
| 1 Cocinas | [ ] | |
| 2 Pedir ≠ cobrar | [ ] | |
| 3 Roles + KDS | [ ] | |
| 4 Tandas | [ ] | |
| 5 Offline / fino | [ ] | |

---

## Referencias

- Canvas: `canvases/plan-restaurante-cocina.canvas.tsx`
- Relacionados: `cocina-tres-logicas.canvas.tsx`, `cocina-hibrido-tandas-pedido.canvas.tsx`, `bar-cuenta-comanda-cocina.canvas.tsx`
- Schema actual: `VentiQ.sql`, `mesa_cuenta_abierta.sql`, `mesas_schema.sql`
- Roles actuales: `app_dat_vendedor` → TPV, `app_dat_almacenero` → almacén, gerente/supervisor → tienda
