# 03 — Almacén: recepción, lotes, costos y stock

Jefe de almacén · Fase 2. Cómo se trabaja hoy en el depósito, qué soporta el sistema y qué falta.
Leyenda: **[HECHO]** verificado con cita · **[PROPUESTA]** decisión a validar con el dueño · **[AUSENTE]** no existe en el repo.

---

## 0. Los cuatro datos que mandan

1. **La compra no existe.** Cero tablas de orden de compra en todo el repo (grep `orden_compra|dat_compra|purchase` en `*.sql`: 0 resultados). Toda recepción de hoy es **externa** por definición. **[AUSENTE]**
2. **El stock no es un número, es un libro.** No hay tabla "stock": hay un ledger de snapshots en `app_dat_inventario_productos`. **[HECHO]**
3. **Recibir ≠ tener.** Registrar la recepción no mueve stock; el stock entra cuando alguien **completa** la operación. Dos pasos, dos personas, dos momentos. **[HECHO]**
4. **El costo se escribe después, fuera de la transacción de stock.** Si el paso de costo falla, el stock ya entró y nadie se entera. **[HECHO]**

---

## 1. Flujo real de la recepción hoy (lo que hace el almacenero)

| # | Qué hace la persona | Qué queda guardado | Cita |
|---|---|---|---|
| 1 | Abre *Recepción de Inventario* y llena la cabecera: **Entregado por**, **Recibido por**, **Motivo** (desplegable), **Observaciones**, **Monto Total** (opcional, se autocalcula). | `app_dat_operacion_recepcion` (entregado_por, recibido_por, motivo, observaciones, monto_total, moneda_factura) | `inventory_reception_screen.dart:625-686` |
| 2 | Elige **una ubicación de destino** para toda la recepción. | Se copia `id_ubicacion` a cada línea (FK `app_dat_layout_almacen`) | `:1100-1130`, `:441-452` |
| 3 | Filtra por proveedor y busca el producto (o usa el asistente IA). | — | `:1132-1204`, `:770-857` |
| 4 | Por producto abre el diálogo de cantidad: cantidad, **precio unitario**, precio referencia, descuento %/monto, bonificación, presentación y variante. | viaja en el jsonb de la línea | `product_quantity_dialog.dart:535-604` |
| 5 | Si el producto es **por lotes**: código de lote + fecha de vencimiento, **obligatorios**. | `app_dat_lote` (se crea o se reutiliza) + `id_lote` en la línea | `product_quantity_dialog.dart:332-363`, `02_lotes_recepcion_rpc.sql:169-209` |
| 6 | Ve los **costos adicionales** activos del producto: checkbox + monto en USD por unidad base. | `app_dat_recepcion_producto_costo` | `product_quantity_dialog.dart:160-229` |
| 7 | Pulsa *Registrar Recepción*. | Se crea la operación y las líneas, **estado = 1 (pendiente)**. El stock NO se toca. | `inventory_service.dart:1336-1411`, `02_...rpc.sql:228-243` |
| 8 | — (opcional) vincula la recepción a una "inversión" del fondo y captura la tasa. | `tasa_cambio_aplicada`, `fecha_tasa_aplicada` | `:688-733`, `fondo_inversion_recepcion_patch.sql:123-133` |
| 9 | Alguien va a *Operaciones* y pulsa **Completar**. | Cada línea entra al ledger como movimiento (cantidad_inicial → cantidad_final); estado = 2 | `inventory_operations_screen.dart:3567-3604`, `inventory_service.dart:3257-3266` |
| 10 | — (automático, después) se recalcula el costo. | `costo_real` efectivo, `app_dat_producto_costo.monto_promedio_usd`, `precio_promedio` de la presentación base | `inventory_service.dart:3443-3446, 4171-4174` |

Notas del paso a paso que importan en el piso:

- **La moneda de la recepción es siempre USD**, fija en el código (`inventory_reception_screen.dart:41-42`); el diálogo convierte con la tasa de la tienda.
- **La cabecera NO captura número ni fecha de factura**, aunque los campos existen en la tabla (`numero_factura`, `fecha_factura`, `monto_factura`, `pdf_factura`: `VentiQ.sql` tabla `app_dat_operacion_recepcion`). Se llenan **a posteriori** desde el diálogo de edición del admin (`reception_edit_dialog.dart:629-743`). El almacenero, en el momento de recibir, no tiene dónde poner el número de factura.
- **Los costos adicionales se guardan best-effort y el error se traga**: `catch { print('⚠️ No se pudieron persistir...') }` (`inventory_service.dart:1394-1402`). Si falla, la recepción queda sin costos y la pantalla dice "éxito".
- **Recepción con compra vs externa: hoy son lo mismo.** El "Motivo" (`app_nom_motivo_recepcion`) distingue compra(1)/transferencia(2)/devolución(3) (`presentaciones_inventario/09_tests_fase1.sql:18`) pero es una **etiqueta**: nada se valida contra ningún documento previo. La única diferencia real es que transferencia y devolución **no** actualizan el costo (`inventory_service.dart:3399-3412`).

---

## 2. Lotes y stock: quién es la fuente de verdad

- **Fuente de verdad: `app_dat_inventario_productos`** (ledger append-only). Cada movimiento inserta una fila con `cantidad_inicial` y `cantidad_final` por clave **(producto, variante, opción, presentación, ubicación, lote)**. No hay UPDATE de un saldo. **[HECHO]** `02_lotes_recepcion_rpc.sql:390-421`
- **Stock agregado** = suma del **último** snapshot de cada `id_lote`, incluidos los NULL (`07_lotes_stock_real_y_listados.sql:23-62`). Antes esa función devolvía `LIMIT 1` y mostraba 400 donde había 5.400 (comentario `:6-7`): el bug clásico de leer un lote y creer que es el total.
- **Stock por lote** = el mismo ledger agrupado por `id_lote`, con estado `ok / expiring / expired / sin_lote` (`07:66-137`). Un producto sin lotes aparece con `codigo_lote = 'Sin lote'` y `estado_caducidad = 'sin_lote'` (`07:118,124`).
- **Convivencia:** los productos sin flag `es_por_lotes` guardan `id_lote = NULL` y se agrupan como una sola partición con `COALESCE(id_lote, 0)`. Nada se rompe (`01_lotes_vencimiento_schema.sql:163-192`).
- **Recepción sin lote o sin vencimiento:** si el producto **no** es por lotes → se guarda NULL, correcto. Si **sí** es por lotes → la RPC devuelve error `V0006` (`02:169-182`) y la UI lo bloquea antes (`product_quantity_dialog.dart:346-363`). **Pero el `RETURN` de plpgsql no deshace lo ya insertado:** la cabecera de operación y las líneas anteriores **quedan guardadas** — el error trae `id_operacion_parcial` justamente porque existen (`02:180`). El almacenero ve "error", reintenta, y ahora hay **dos operaciones pendientes**, una de ellas fantasma con líneas incompletas. Es un hueco de integridad, no solo de mensaje.
- **Lote con código repetido y otra fecha** → error explícito, no se pisa en silencio (`01:291-301`). Bien.
- **Stock viejo sin lote** cuando el flag se activa después: hay una RPC de reclasificación (`09_lotes_asignar_sin_lote.sql:1-7`) pero es de gerente/supervisor, no del almacenero.

### ¿Se puede recepcionar dos veces por error? **[HECHO] sí**

Lo único que existe es:
1. **Idempotencia por línea**: si esa línea de recepción ya tiene movimiento en inventario, la contabilización responde `OMITIDO` (`02:310-322`). Eso evita duplicar el stock de **la misma** recepción al completarla dos veces.
2. El guard `_isLoading` del botón (`inventory_reception_screen.dart:1082`), que evita el doble toque.

Lo que **no** existe: nada compara contra un "pedido". Dos operaciones distintas del mismo camión se registran las dos y **suman stock dos veces**. No hay idempotency key: `app_dat_operaciones.uuid` es el **usuario** que crea (FK a `auth.users`), no una clave de operación (`VentiQ.sql` tabla `app_dat_operaciones`).

---

## 3. Recepción contra compra — cómo debe ser **[PROPUESTA]**

**Por línea de compra, nunca por producto suelto.** El almacenero no "agrega productos a una recepción": abre la compra y ve sus líneas con tres columnas vivas: **pedido / recibido / pendiente**. El buscador de productos desaparece de esa pantalla; si el producto no está en la compra, no se puede recibir por ahí.

- **Pendiente por línea** = `cantidad_pedida − Σ cantidad_recibida` de esa línea, contando solo recepciones completadas. Se calcula **por línea**, no por producto: el mismo producto puede venir en dos líneas con precio distinto y cada una tiene su saldo.
- **Sobre-recepción:** bloqueada por defecto. Tolerancia configurable (sugerido **0 %**; hasta 5 % si el dueño lo autoriza) y, pasado ese margen, **autoriza el dueño o el gerente**, con registro de quién, cuándo, cuánto y por qué. La cantidad excedente **sí entra al stock**, pero el pendiente se topa en 0 — nunca negativo.
- **Producto que no estaba en la compra:** no se agrega a la compra (eso cambiaría lo pactado y su costo). Se recibe como **recepción externa** separada y queda marcada "no prevista" para que el dueño la vea y decida si la suma a la compra o la paga aparte. Si el dueño prefiere, alternativa: línea extra autorizada con motivo.
- **Recepción parcial múltiple: sí, es lo normal** (un camión hoy, otro la semana que viene). Requisitos para que el saldo y el estado queden bien:
  1. Ninguna línea puede tener dos recepciones **abiertas** (pendientes) al mismo tiempo.
  2. El estado de la compra (`pendiente / parcial / recibida / cerrada`) es **derivado** de Σ recibido, no un campo que alguien edite.
  3. Cerrar la compra con pendiente exige motivo ("el proveedor no completa", "se cancela el resto") y libera la reserva del remanente.
- **Sobrante de saldo reservado cuando se recibe menos:** la reserva **no se libera** al recibir menos. Sigue comprometida hasta que el dueño **cierre** la compra o **cancele** el remanente; entonces se libera exactamente lo no recibido. Si se libera en cada recepción parcial, el dueño vuelve a gastar un dinero que ya debe. La regla contable está en [02-contabilidad §4.3](02-contabilidad.md).

---

## 4. Costos adicionales en la recepción

**Lo que hay:** el almacenero los ve **dentro del diálogo de cantidad**, uno por producto, con checkbox y monto en **USD por unidad base**, prellenado con el promedio vigente o el configurado (`product_quantity_dialog.dart:106-142,160-229`). Solo aparecen los conceptos **activos** que el admin ya asoció a ese producto (`CostosAdicionalesService.listarActivosPorProducto`). **Si el producto no tiene conceptos configurados, el almacenero no ve nada y no puede crear uno.** Alcance: por producto, por unidad base, en USD; se guarda por línea y se promedia ponderado (`sql_updates/costos_adicionales_producto.sql:392-436`).

**Lo que falta en la UI (GAP operativo):**

1. **No hay costos a nivel de factura/compra.** Los costos reales del negocio (flete del contenedor, aduana 5 %, transporte interno) son **globales del documento**, y hoy hay que digitarlos producto por producto: con 80 líneas son 80 capturas a mano que nadie hace bien.
2. **No hay reparto por valor.** El sistema solo sabe "monto por unidad de este producto" (reparto por cantidad implícito), que es el peor criterio cuando los artículos tienen precios muy distintos. [02-contabilidad §3.3](02-contabilidad.md) ya decidió que el default debe ser **por valor**.
3. **El almacenero digita a ciegas:** la pantalla no le muestra el costo resultante (`precio + adicionales = costo de esta línea`). No puede detectar que un flete de 300 USD/u sobre un producto de 2 USD es un error de tipeo.
4. **No se pueden revisar ni corregir:** la lista de productos seleccionados (`inventory_reception_screen.dart:859-991`) no muestra costos, y `reception_edit_dialog` edita precio pero **no** costos.
5. **La persistencia es best-effort y silenciosa** (`inventory_service.dart:1394-1402`).

**Cómo debería verse:** en la cabecera de la factura, una lista de los conceptos del nomenclador (`app_cont_tipo_costo`) con monto y criterio de reparto; al registrar, el sistema prorratea **solo sobre lo recibido** ([02-contabilidad §3.5](02-contabilidad.md)) y muestra por línea el costo aterrizado antes de confirmar.

---

## 5. "Pago a la importadora": qué es y qué falta

**Es un proveedor prepago.** El dueño **carga saldo** a la importadora (`imp_dat_saldo`, `imp_dat_recarga_saldo`) y cada **factura** de mercancía **descuenta** de ese saldo al crearse (`imp_dat_factura`: numero, valor, fecha_procesamiento, foto, estado — `importadora_facturas_schema.sql:111-133`). Ciclo del estado: *Procesando por Proveedor → Pagado a Importadora → En Recogida → Finalizado* (`:32-38`). Hay auditoría de saldo y de estados (`:87-155`). Se está migrando a `prv_*` porque la importadora es **un proveedor más** (`migracion_importadora_a_proveedores.sql:1-17`).

**Relación con la recepción hoy: ninguna.** Cero FK entre `imp_dat_factura`/`prv_dat_factura` y `app_dat_recepcion_productos` (verificado también en [02-contabilidad §3.2](02-contabilidad.md)). El almacenero no ve, no elige y no puede asociar una factura de importadora. El pago lo registra el dueño/contador por su lado; el stock entra por otro. Los dos libros nunca se tocan.

**Qué haría falta para que afecte el costo real** — primero decidir **qué es** (son excluyentes):

- **Si es la factura de la mercancía** (trae productos y precios) → **es** el costo de factura. Sumarla como adicional **duplica el costo**. Lo que falta es el vínculo documento → líneas → recepción.
- **Si es el servicio de importación** (fijo o % del valor) → es un **costo adicional prorrateable por valor**, y debe entrar por `app_cont_tipo_costo`, **no** por el saldo prepago.

En ambos casos falta lo mismo: **un documento de compra que una la factura, la recepción y el pago**. Sin eso no hay forma de que el pago afecte el costo sin inventar una regla.

---

## 6. Ubicaciones y almacenes

- **Se elige una sola zona para toda la recepción** (`_selectedLocation`, `inventory_reception_screen.dart:386-389,1100-1130`) y se copia a todas las líneas. **No se elige almacén**: se elige la zona (layout) y el almacén se deduce. Consecuencia práctica: si el camión trae congelados y secos, hay que hacer **dos recepciones**.
- **Multi-almacén:** `listWarehousesOK` filtra por rol vía `AlmacenScopeService` (`warehouse_service.dart:214-250`). Gerente y supervisor ven todo; almacenero, jefe de cocina y cocinero solo lo suyo; el cocinero **no operable** (`almacen_scope_service.dart:67-91`). Ojo: es **acotado de UI, no seguridad** — lo dice el propio archivo (`:13-19`) y la autorización real vive en las RPC.
- **Impacto de elegir almacén en la compra [PROPUESTA]:** la compra debe llevar **almacén destino por línea**. Así la recepción lo precarga (el almacenero no elige a ojo), se puede decidir si el stock en tránsito cuenta como disponible, y el dueño ve *dónde* va a aterrizar cada cosa. Si la compra no lo fija, el stock termina donde no se vende.

---

## 7. Bloquear stock vs reservar vs bloquear catálogo

| | Qué significa en el piso | Qué necesita | Sirve para lo comprado |
|---|---|---|---|
| **(a) Bloquear stock existente** | Marcar unidades **que ya están** en el estante como no vendibles: cuarentena, dañado, apartado para un cliente. | Stock físico. Un campo de estado por unidad/lote. | **No.** Lo comprado todavía no está. |
| **(b) Reservar stock futuro** | Comprometer unidades **que aún no llegaron** a un pedido o cliente. El stock no existe; se reserva la promesa. | Cantidad reservada por línea de compra; `disponible = stock − reservado`; regla de qué pasa si no llega. | **Sí**, es el mecanismo correcto. |
| **(c) Impedir vender hasta que llegue** | El producto no puede entrar en una venta mientras no haya stock / no esté recibido. | Regla de catálogo/visibilidad (`es_vendible`, estado del producto). | **Parcialmente**: es una consecuencia, no un mecanismo. |

**Cuál describió el cliente:** su frase mezcla dos. "Bloquear los productos comprados" suena a (c) —que no se vendan hasta que lleguen—, pero **eso ya pasa solo**: no se puede vender lo que no hay. Lo que realmente quiere evitar es **vender lo que ya está comprometido** y **recibir cualquier cosa**. Ninguna de las tres lo cubre: la que lo cubre es **restringir la recepción a las líneas de la compra** (§3), que es barata y no requiere inventar stock futuro.

**Implicaciones operativas:**
- (a) cuesta poco, no resuelve nada del pedido. Útil solo para merma/cuarentena.
- (b) obliga a decidir qué se hace si la compra no llega (¿se libera? ¿se avisa al cliente?) y a mostrar dos números distintos: *stock* y *disponible*. Sin esa disciplina, el vendedor promete lo mismo dos veces.
- (c) es barato y evita vender humo, pero si el dueño quiere **preventa** (vender antes de que llegue), lo mata.

**Caso "el producto comprado no existe todavía en catálogo" [PROPUESTA]:** la compra debe permitir **crearlo en el momento** (nombre, UM, presentación base, costo) y dejarlo en estado **no vendible / borrador** hasta la primera recepción. Eso es (c) aplicado al producto recién nacido, y es la única forma de que el almacenero pueda recibir algo que el dueño compró por teléfono. La alternativa —línea con descripción libre y "producto pendiente de catalogar"— es peor: después hay que adivinar qué era.

---

## 8. Proceso operativo recomendado (de la decisión al estante)

| # | Paso | Quién | Dinero | Stock |
|---|---|---|---|---|
| 1 | Arma la compra: proveedor, líneas (producto, cantidad, costo pactado, **almacén destino**), condiciones de pago. | Dueño | — | — |
| 2 | Si hay anticipo o pago a importadora, lo registra y lo **vincula a la compra**. | Dueño / contador | **sí** | — |
| 3 | Llega el camión. Abre **la compra**, no una pantalla en blanco. Verifica contra el papel. | Almacenero | — | — |
| 4 | Cuenta lo que **realmente** llegó: cantidad, lote y vencimiento (obligatorios si el producto es por lotes), daño y faltante. **No "cuadra" con lo pedido: registra la diferencia.** | Almacenero | — | — |
| 5 | Captura la factura del proveedor: número, fecha, monto, moneda, foto. Sin factura → marcada "sin factura". | Almacenero | — | — |
| 6 | Captura los costos adicionales **de la factura** una vez, con criterio de reparto. | Almacenero (o contador) | **sí** (es el costo real) | — |
| 7 | **Completa** la recepción. Aquí entra el stock, por lote, en la ubicación. | Almacenero | — | **sí** |
| 8 | El sistema calcula el costo aterrizado de cada producto y actualiza el promedio. | Sistema | **sí** (valorización) | — |
| 9 | Autoriza el cierre de la compra: recibir lo que llegó y cerrar, o dejar pendiente el resto. | Dueño | **sí** (libera reserva) | — |
| 10 | Ubica físicamente y etiqueta con lote y vencimiento. El stock queda vendible (o reservado). | Almacenero | — | **sí** |
| 11 | Cruza factura ↔ recepción ↔ pago. Si no cuadra, no cierra el período. | Contador | **sí** | — |

**Dinero:** pasos 2, 6, 8, 9, 11. **Stock:** pasos 7, 10. **Nunca los dos en el mismo paso** — es la regla que evita que un error de conteo se convierta en un error de costo.

---

## 9. Errores frecuentes y cómo los previene el sistema

| Error real | Estado hoy | Prevención |
|---|---|---|
| **Recepción sin factura** | Se permite: `numero_factura`/`monto_factura` son NULL y nadie lo exige. | Marcar la recepción "sin factura" de forma visible y **no cerrar la compra** ni el período con recepciones sin factura. |
| **Factura que no cuadra con lo recibido** | Nadie compara. `monto_factura` existe en la tabla pero no se valida contra Σ(precio × cantidad). | Mostrar la diferencia antes de completar y exigir motivo si supera una tolerancia. |
| **Mercancía dañada** | Se recibiría como buena y después habría que sacarla con una extracción por "Producto dañado" (`inventory_service.dart:88-128`). | Capturar **cantidad dañada / rechazada** en la misma línea; lo dañado no entra al stock vendible y queda como reclamo al proveedor. |
| **Faltante del transportista** | Se registra la cantidad real, pero como no hay compra **el faltante no queda pendiente de nada**: se pierde. | El faltante queda como **pendiente de la línea**, no como merma. Si no llega nunca, se cierra la compra con motivo. |
| **Recepción retroactiva (fecha pasada)** | **Imposible hoy.** No hay fecha de operación: el stock se fecha con `NOW()` (`02:222`, `07`). Solo la fecha de **factura** es editable, y por el admin. | **[GAP]** Si llega mercancía del viernes y se recibe el lunes, el stock entra el lunes y el reporte de esa semana miente. Hace falta `fecha_operacion` con autorización para fechas pasadas. |
| **Costo distinto al pactado** | El diálogo precarga el **último precio de compra** (`product_quantity_dialog.dart:442-472`) y deja escribir cualquier número sin aviso. | Contra compra, precargar el **precio pactado** y no dejar tocarlo; si difiere, autorización con motivo y registro. |
| **Recepción duplicada** | Nada la impide (§2). | El pendiente de la línea llega a 0 y la línea deja de ser recibible. |

---

## 10. Los tres huecos que más daño hacen

1. **No hay compra.** Sin documento previo no hay pendiente, no hay control de sobre-recepción, no hay detección de doble recepción y no hay forma de saber si lo que llegó es lo que se pidió. Todo lo demás del módulo son parches sobre esta ausencia.
2. **El costo se calcula después y se pierde en silencio.** El stock entra en un paso y el costo en otro, fuera de la misma transacción; los costos adicionales se guardan con el error tragado. Resultado: productos con costo 0 o sin adicionales, margen falso y valorización de inventario falsa, sin que nadie vea un error.
3. **Una sola ubicación por recepción y ninguna fecha de operación.** Mercancía que llega en dos temperaturas obliga a dos recepciones; mercancía que llega tarde se fecha el día que alguien la digita. El stock queda mal ubicado y mal fechado, y corregirlo obliga a operaciones de ajuste que ensucian el kardex.

---

## 11. Preguntas para el dueño

1. **Tolerancia de sobre-recepción:** ¿0 % y autoriza él cada exceso, o un % fijo por proveedor?
2. **¿Quién captura la factura y los costos?** Si es el almacenero, necesita el criterio de reparto en la mano; si es el contador, la recepción se queda "abierta" hasta que él llegue.
3. **¿Se permite preventa?** Si sí, (b) reserva es obligatorio. Si no, basta con (c) y el producto no vendible hasta la primera recepción.
4. **¿El producto comprado se puede crear desde la compra**, o solo desde el catálogo por el admin?
5. **¿Dos almacenes en una misma recepción** (secos y fríos), o se acepta hacer dos operaciones?