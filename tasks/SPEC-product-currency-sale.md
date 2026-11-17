# Spec: Venta con moneda por producto

- Module id: `product-currency-sale`.
- Estado: CONTRATO CONSOLIDADO APROBADO por el usuario, incluidas secciones 0.1–0.3 y secuencia de sección 14. La aprobación autoriza preparar el plan técnico detallado, no implementar ni ejecutar DDL.
- Depende de: `store-product-currency-policy`.
- Consumidor: `product-currency-report-contracts`.
- Referencia funcional: `tasks/plan_admin_multimoneda.md`, intención confirmada y reglas 1–19.
- Entorno de diseño y pruebas: newa. El usuario ejecuta SQL desde SQL Editor; el agente solo inspecciona.
- Main no define las versiones de desarrollo; la promoción posterior exige comparación y migración específicas.

## 0. Contratos consolidados propuestos para aprobación

Esta sección fija la recomendación técnica tras la revisión adicional. No convierte propuestas operativas en decisiones ya aprobadas. Las reglas funcionales de moneda, precio propio, descuentos por unidad/detalle y redondeo nativo mantienen sus confirmaciones previas.

### 0.1 Totales y compatibilidad

Recomendación: nativos explícitos como fuente comercial; campos legacy conservados como proyección contable CUP para producto-v1, con ramas de lectura/escritura por versión. No sumar CUP y USD ni cambiar globalmente el significado de registros históricos.

| Magnitud | Contrato propuesto para producto-v1 |
|---|---|
| Bruto comercial | Precio propio seleccionado antes de descuentos, por moneda y detalle. |
| Subtotal previo al manual | Resultado tras promociones/recargos automáticos, antes del descuento manual unitario. Magnitud distinta del bruto de catálogo. |
| Neto comercial | Resultado tras automático y manual, redondeado por línea con la regla confirmada. |
| precio_unitario legacy | Proyección CUP del unitario previo al manual; no precio nativo ni fuente para reconstruirlo. |
| importe / importe_real legacy | Proyección CUP del subtotal previo al manual, para mantener la compatibilidad con alta legacy observada; nuevos consumidores deben usar campos explícitos para conocer neto. |
| importe_total legacy | Suma de subtotales contables CUP previos al manual, no suma de importes nativos ni bruto de catálogo. |
| precio_con_descuento_total legacy | Neto contable CUP tras manual cuando exista; null si no existe, conservando el patrón actual observado. |
| Totales nuevos | Bruto, automático, manual, neto y sus equivalentes explícitos, más mapas nativos por moneda/medio. No inferirlos de alias legacy. |
| es_pagada | Cumplimiento de obligaciones nativas por moneda/medio, excluyendo pendientes como cobros reales. No comparación exclusiva de equivalentes CUP. |

Propuesta de precisión contable: guardar la tasa decimal publicada sin redondearla a centavos; calcular equivalentes de bruto/subtotal/neto con decimal exacto y fijarlos a 2 decimales CUP por línea, half-up. Los totales contables suman líneas fijadas. Conservar insumos y residual que expliquen diferencias entre componentes redondeados. No alterar el nativo para cuadrar diferencias contables ni exigir coincidencia con precio CUP de catálogo. Esta precisión contable se somete a revisión junto con la spec; no está incluida automáticamente en la aprobación previa del cobro nativo.

Para pagos agrupados, el equivalente procede de la atribución a detalles y snapshots; si hay tasas distintas o diferencias por redondeo, no recalcular todo con una sola tasa y sobrescribir el equivalente. El diseño SQL debe preservar los segmentos contables o su atribución verificable. UI puede agrupar moneda/medio sin exigir una única fila física de pago.

Todos los mutadores de cantidad, edición, anulación y descuentos deben tener rama producto-v1 antes de habilitar ventas. Los reportes y métricas críticas deben leer los nuevos netos sin volver a restar descuentos. Un consumidor no adaptado es un gate de activación, no motivo para reutilizar una suma nativa escalar.

### 0.2 Política, precio y tasa offline

Recomendación a aprobar: registrar revisiones inmutables de política por tienda y constancias de entrega al usuario/dispositivo, emitidas por servidor durante el sync/preparación existentes. La revisión identifica flag, forzado y monedas habilitadas en una lectura consistente; no combinar configuraciones descargadas en momentos distintos.

- La constancia referencia una revisión real y el ámbito de usuario/tienda/dispositivo; no se acepta una revisión histórica arbitraria por venir en un JSON del cliente.
- Si hace falta almacenamiento nuevo, usar tablas pequeñas de revisiones/entregas, no otro catálogo de productos ni un pipeline paralelo. RLS y policies explícitas inmediatamente después de CREATE TABLE; revisiones inmutables y emisión protegida. Es propuesta, todavía no DDL aprobado.
- Online: nueva orden obtiene la revisión actual autorizada. Offline: propuesta de permitir nuevas órdenes bajo la última revisión entregada mientras la licencia/ventana offline existente autorice operar. No crear un TTL monetario arbitrario adicional.
- Los cambios posteriores no reinterpretan órdenes ya iniciadas. Al reconectar se validan acceso actual, procedencia de revisión, precio/tasa, cantidades, descuentos y coherencia de la venta, sin sustituir sus snapshots por los actuales.
- Para primer envío fuera de la autorización offline o sin evidencia suficiente: propuesta de retener la orden para revisión autorizada, sin borrarla, cobrar otra vez ni convertirla. Un replay de una operación ya aceptada devuelve su resultado original. La regla de revisión de envíos tardíos requiere aceptación operativa del usuario.
- Límite explícito: una revisión/constancia auténtica no demuestra la hora exacta de creación en un dispositivo desconectado. No presentar el reloj local como prueba irrefutable ni prometer revocación instantánea sin red.

Precio: reutilizar las vistas vigentes y el sync de productos/precios específicos, preservando referencias y valores descargados. Tasa: reutilizar CurrencyService y sus timelines, extendiendo la información descargada con identidad y procedencia necesarias para validación; no aceptar solo un mapa USD=valor como evidencia histórica.

La lectura de CurrencyService confirmó fuentes de tienda/globales, resolución as-of y caché de timelines. No modificar silenciosamente su precedencia durante esta feature. Una edición explícita de moneda/medio reevalúa los datos que deba cambiar y exige confirmación; reintentar/sincronizar no lo hace.

### 0.3 Cobertura obligatoria, sin exclusiones silenciosas

| Ruta | Adaptación requerida antes de activar |
|---|---|
| Mostrador, detalle, búsqueda y escáner | Misma política y detalle monetario; identidad estable y resolución por moneda. |
| Preorden online/offline | Eliminar CUP implícito y agrupación solo por medio en producto-v1; persistir exactamente los snapshots y netos del carrito. Legacy no cambia. |
| Mesa sin cocina | Ampliar app_dat_mesa_cuenta_item con moneda/snapshots y conservarlos al convertir la cuenta en Order y venta. No perderlos entre pantallas. |
| Mesa con cocina | Validar moneda/precio/tasa antes de pedir; mantener referencia de cuenta/item y stock_movido/origen/comanda. Cobrar no vuelve a consumir ni crea otra comanda. |
| Editar/cancelar pedido | Operar por id de línea, revertir solo sus efectos y conservar auditoría. Sin unión automática por producto que ignore selección. |
| Crédito/CxC y parcial | Ampliar deuda/liquidación a moneda nativa y atribución por línea. El sentinel pendiente no cuenta como ingreso cobrado. No conectar venta mixta al saldo escalar actual. |
| Cambio de medio después del cobro/devolución | No reescribir la venta/cobro histórico como si nunca hubiese ocurrido. Requiere ajuste autorizado, moneda original y referencia a línea/pago. |

Evidencia de newa: mesa_cuenta_item tiene medio/promoción/inventario y stock_movido, pero carece de moneda/tasa explícitas. fn_agregar_item_cuenta_mesa une por identidad que incluye medio, no moneda; fn_pedir_item_cuenta_v2 mueve inventario y conserva stock_movido. fn_marcar_cuenta_cerrada enlaza operación posterior. La finalización debe cerrar la cuenta de forma idempotente y recuperable, sin duplicar el alta comercial ni inventario.

Evidencia CxC: app_dat_liquidacion_cxc tiene monto_total sin moneda; fn_cxc_saldo_cliente resta SUM(pagos.monto) del total escalar, y fn_cxc_registrar_liquidacion inserta pagos sin moneda explícita. Deben extenderse antes de aceptar deudas nuevas producto-v1. No reconstruir moneda de liquidaciones históricas por suposición.

Propuesta operativa para crédito: registrar deuda en moneda de cada línea; liquidar en esa moneda, sin conversión de deuda. Si el detalle fue creado como pendiente, elegir su medio real al comenzar a liquidarlo y mantener un único medio real por línea; parciales posteriores deben respetarlo. Esta excepción acotada de elección diferida requiere aprobación junto con la spec; no equivale a permitir redistribución libre en checkout ni combina medios en una misma línea.

Si alguna ruta no supera sus pruebas, no activar el flag de tienda. No declarar listas las ventas multimoneda excluyendo crédito, mesas o preorden sin autorización explícita.

## 1. Resultado e invariantes confirmados

Con el flag apagado, conservar exactamente el comportamiento legacy, incluidos precios, editor de distribución, payloads y órdenes antiguas.

Con el flag encendido:

1. Cada línea tiene una moneda y un medio de pago para toda su cantidad. Se utiliza el selector de medio ya existente.
2. CUP usa precio CUP propio y USD usa precio USD propio; no se convierten para sustituirse.
3. La tienda forzada limita la selección. Sin forzado, seleccionar entre monedas habilitadas con precio válido.
4. Si falta precio, bloquear esa moneda. Si falta tasa USD→CUP válida online y en caché, bloquear nuevas líneas USD. No ofrecer CUP como fallback si la tienda fuerza USD.
5. Guardar importe nativo, tasa histórica y equivalente CUP separados. El equivalente no determina si el precio USD coincide con el precio CUP del catálogo.
6. Checkout deriva cobros agrupados por moneda y medio de los detalles y no los redistribuye. Editar una selección exige volver al detalle.
7. Repetido con distinta moneda/medio: informar, permitir separar o unir; al unir, elegir explícitamente combinación final y confirmar importe nativo. No convertir ni seleccionar automáticamente.
8. Órdenes ya iniciadas o pendientes conservan modalidad y condiciones seleccionadas ante cambios posteriores del flag/forzado. No reinterpretarlas al sincronizar.
9. Solo datos nuevos. Históricos sin atribución demostrable siguen sin ella.
10. Los pagos de la orden siguen representando cobros reales; los detalles representan su origen comercial. No contar ambos como dos ingresos.

## 2. Evidencia local y de newa

### Código local inspeccionado

- `models/order.dart`: OrderItem tiene precioUnitario/precioBase, paymentMethod y promotionData, sin moneda. displayPrice/subtotal ejecutan reglas por efectivo y promoción; no son un simple precio de catálogo. toJson/fromJson/copyWith requieren extenderse coherentemente.
- El mismo modelo conserva presentación y factor histórico. La cantidad está en la presentación seleccionada; inventario usa equivalenteBase.
- `models/product.dart`: Product y ProductVariant conservan un único precio. No basta añadir moneda como etiqueta; hay que transportar los precios propios por el pipeline existente.
- `screens/product_details_screen.dart`: calcula precios y multiplica por factor de presentación antes de añadir a la orden. Evitar aplicar el factor dos veces.
- `services/order_service.dart`, addItemToCurrentOrder: une por producto, variante y presentación, sin moneda/medio. Antes del carrito deriva a MesaCuentaService si hay cuenta activa; con cocina activa llama pedirItem, sin ella agregarItem.
- El payload de registro construye productos con precio_unitario=item.displayPrice, cantidad y referencias de inventario, pero no moneda/medio por extracción.
- `screens/checkout_screen.dart`: _currencyPaymentLines alimenta tanto pagos online como desglose_pagos offline; el editor «Distribuir pagos» debe quedar exclusivamente en la rama legacy.
- `services/auto_sync_service.dart`: consume desglose_pagos y también tiene reconstrucciones por ítems. El modo nuevo debe evitar fallbacks que reconstruyan pagos perdiendo moneda o snapshots.
- `screens/preorder_screen_styled.dart`: tiene una ruta que declara moneda CUP explícitamente. No asumir cobertura del modo nuevo por cambiar solo product_details_screen.

### Esquema inspeccionado en newa, solo lectura

- app_dat_extraccion_productos: cantidad numeric; precio_unitario, importe, importe_real, precio_oficial_venta; presentación, variante, ubicación, lote. Sin moneda, medio, tasa ni equivalente por detalle.
- app_dat_operacion_venta: importe_total y precio_con_descuento_total numeric; es_pagada boolean; no modalidad monetaria explícita actualmente.
- app_dat_pago_venta: monto nativo, moneda, id_medio_pago, tasa_cambio, tasa_usd, monto_cup_equivalente. Sin vínculo directo con extracción.
- app_dat_precio_venta y vistas app_v_precio_venta_vigente/base_vigente contienen precio_venta_cup y precio_venta_usd.
- app_dat_precio_tpv contiene precio_venta_cup; no apareció una columna USD en la inspección de columnas. La prioridad entre precio TPV CUP y precio USD de catálogo necesita definición, no conversión implícita.

### RPC actuales de newa

| Función y argumentos | Huella de definición inspeccionada |
|---|---|
| fn_registrar_venta_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint) | 97c58841e8a4ce7912fb6b6477b13723 |
| fn_registrar_venta_v3_impl(mismos tipos) | 2fa23774819d7accd358dc31ea8d3c6f |
| fn_registrar_venta_mesa_v3(bigint,uuid,jsonb,text,text,text,smallint,bigint,bigint) | bb620c6f983e4b34f656dcc6fe4c38cb |
| fn_registrar_venta_mesa_v3_impl(mismos tipos) | f8aa6a1bf87631f6592407e4495de72b |
| fn_agregar_producto_orden_pendiente_v2(bigint,jsonb,uuid) | 6bb4d98aae8b304d76a43aaf3fa489d1 |
| fn_editar_orden_pendiente_v2(bigint,jsonb,uuid) | d9e4821bdf72b863c5d359993d0d615b |
| fn_registrar_pago_venta_v3(bigint,jsonb) | ea2778fb3b7bc312db00489b391affab |

Las huellas identifican lo observado, no sustituyen pruebas. Se inspeccionaron firmas y fragmentos monetarios relevantes; no se afirma una auditoría completa de todos los cuerpos y consumidores.

Hallazgos:

- Registrar venta acumula cantidad × precio_unitario en un solo total; no admite sumar nativos CUP y USD sin cambiar el contrato.
- Agregar pendiente busca coincidencia por operación/producto/variante/ubicación, fusiona cantidad y redirige a fn_actualizar_cantidad_producto_orden_v2. No incluye moneda/medio ni presentación en esa búsqueda.
- Agregar pendiente también actualiza pagos por medio sin distinguir moneda y recalcula importe_total sumando todos los detalles.
- Registrar pago v3 verifica moneda/medio y calcula equivalente; decide pago completo por equivalentes contra importe_total. Esa condición no es la validación nativa requerida por el modo nuevo.

## 3. Contrato de orden propuesto

La modalidad debe persistirse en la orden y no consultarse de nuevo para interpretar cada reintento.

Campos conceptuales, nombres finales a fijar en el plan:

- Versión del contrato monetario: legacy o producto-v1.
- Identificador estable de orden cliente, tienda y TPV.
- Snapshot de la política de moneda al iniciar la orden y procedencia/fecha de carga para diagnóstico.
- Lista de detalles con identificadores estables.
- Totales nativos por moneda y obligaciones por moneda/medio.
- Total contable CUP independiente, nunca rotulado como total nativo.

Una orden antigua sin versión es legacy. Un payload nuevo incompleto o con versión desconocida debe fallar explícitamente: no degradarlo a legacy para lograr sincronización.

La política histórica debe ser verificable por el servidor. No confiar en un booleano aportado por el cliente para eludir restricciones de tienda. El mecanismo de evidencia/revisión de política para órdenes creadas offline queda pendiente del plan técnico; no fingir que guardar un JSON local resuelve autorización.

## 4. Detalle monetario propuesto

Preferencia de diseño: ampliar app_dat_extraccion_productos, condicionando los campos a líneas comerciales del contrato producto-v1; no exigirlos a todas las extracciones ni backfillear históricos.

| Dato conceptual | Propuesta de tipo/validación |
|---|---|
| id de línea cliente | UUID estable; identidad independiente del producto y clave para reintentos. |
| versión monetaria | Identificador de contrato; permite diferenciar ausencia histórica de línea nueva inválida. |
| moneda | Código CUP/USD validado, no una etiqueta libre. |
| medio seleccionado | FK al catálogo existente, compatible con permisos y reglas del medio. |
| precio de catálogo nativo histórico | numeric, con origen de precio/vigencia identificables. |
| precio unitario nativo efectivo | numeric, después de las reglas aplicables de precio/promoción. |
| cantidad y presentación | Reutilizar cantidad/id_presentacion; conservar factor histórico requerido por offline. |
| importe nativo final | numeric, base del cobro de la línea, sin suma entre monedas. |
| descuento/recargo nativo | Snapshot suficiente para explicar el precio final; no recalcular promociones históricas. |
| tasa hacia CUP | numeric positiva; CUP=1. |
| equivalente CUP | numeric separado, calculado con el importe final y tasa histórica. |
| fecha/origen de tasa | Permite verificar la tasa usada; no consultar la tasa actual al reintentar. |

### Nombres y contrato de detalle para revisión técnica

Propuesta concreta, todavía sin DDL aprobado. Campos nuevos aditivos en la extracción comercial; nullable para históricos y operaciones no comerciales, con validación condicional para producto-v1:

| Campo propuesto | Responsabilidad |
|---|---|
| version_monetaria | Identificar contrato de la línea. Ausencia histórica no se convierte en una atribución nueva. |
| id_linea_cliente | UUID estable, independiente del id_producto. Unicidad por operación y línea no nula. |
| moneda_venta | CUP o USD; aplica a todos los importes nativos de esta línea. |
| id_medio_pago_seleccionado | Selección comercial, no prueba por sí sola de cobro. |
| precio_unitario_nativo | Precio histórico resuelto para la presentación vendida antes de descuentos/recargos. |
| descuento_manual_unitario_nativo | Monto manual por unidad confirmado por el usuario. Nunca importe global repartido. |
| precio_unitario_neto_nativo | Resultado unitario después de reglas aplicables; puede conservar precisión intermedia, sin redondeo prematuro a entero. |
| importe_bruto_nativo | Bruto de la línea en su moneda, antes de descuentos/recargos. |
| importe_neto_nativo | Total exigible de la línea después de descuentos/recargos y regla de redondeo aprobada. |
| tasa_cambio_cup | Snapshot positivo hacia CUP; CUP=1. No tasa para formar el precio propio USD. |
| importe_bruto_cup_equivalente | Equivalente contable bruto, independiente del precio CUP del catálogo. |
| importe_neto_cup_equivalente | Equivalente contable neto, independiente del cobro nativo. |
| snapshot_precio | Origen general/TPV, id del registro, variante/presentación y vigencia que explican el precio utilizado. |
| snapshot_descuentos | Promoción/recargo aplicado, tipo, base, valor unitario nativo/porcentaje y motivo/autorización del manual. |
| snapshot_tasa | Fuente/registro, fecha de vigencia y momento de selección. |

Propuesta de tipos: uuid para identidad, FK smallint compatible con el catálogo de medios, numeric para cantidad/importes/tasa y jsonb para snapshots explicativos. Los snapshots no sustituyen columnas financieras consultables ni validaciones del servidor. No guardar datos sensibles innecesarios en ellos.

Magnitudes que deben reconstruirse sin consultar catálogo/promociones actuales:

- Descuento manual nominal de línea = descuento manual unitario × cantidad vendida.
- Neto ideal = cantidad × precio unitario neto nativo; aplicar la regla de precisión una sola vez en el punto aprobado.
- Descuento/recargo realmente reconocido debe reconciliar bruto y neto. Si se muestran componentes redondeados, definir explícitamente el residual para que no aparezca ni desaparezca dinero.
- Obligación por moneda/medio = suma de netos nativos de las líneas correspondientes, no de brutos ni de equivalentes.
- Equivalente contable = cálculo sobre snapshots con la regla de precisión pactada; nunca valida que un precio USD propio sea igual al precio CUP propio.

No reutilizar precio_unitario/importe/importe_real para nativos mixtos sin adaptar consumidores. No almacenar dinero usando float en PostgreSQL; definir serialización y redondeo reproducibles entre Dart y SQL antes de implementar. La precisión exacta y los nombres finales se revisan junto con el DDL, no se consideran migración autorizada por aparecer aquí.

Recomendación consolidada para revisión: mantener aliases legacy como proyección contable CUP del flujo previo al descuento manual, según sección 0.1, y campos explícitos para bruto comercial y neto después de todos los descuentos. La versión determina cómo leer/escribir cada registro; no aplicar reglas nuevas a históricos ni habilitar mutadores/reportes sin adaptar. Esta elección técnica se somete a aprobación de la spec; el DDL aún no está autorizado.

### Inventario adicional de consumidores de totales

Verificado por lectura local y fragmentos de funciones de newa; no representa cobertura completa:

| Consumidor | Cálculo observado | Riesgo para producto-v1 |
|---|---|---|
| newa fn_actualizar_cantidad_producto_orden_v2 | Multiplica cantidad por precio_unitario y recompone importe_total por suma de todas las líneas. | Requiere rama monetaria explícita; no sumar nativos mixtos ni perder descuentos del snapshot. |
| newa fn_editar_orden_pendiente_v2 | Recalcula total bruto y descuento de vendedor; modifica pagos, incluye ajustes por equivalentes/tasa_usd. | No reutilizar su redistribución para sobrescribir obligaciones por moneda/medio. |
| newa reporte_ordenes_json | Expone importe_total, SUM(ep.importe), precio_unitario y pagos con moneda. | Contrato versionado: los valores escalares no pueden significar unas veces CUP y otras suma nativa sin identificador. |
| admin CustomerService | Suma importe_total para métricas de cliente. | Mantener lectura contable tipada o adaptar consumidor antes de habilitar modo nuevo. |
| vendedor checkout offline | Acumula un subtotal escalar y transforma importes por medio/tasa al armar pagos. | Nueva rama debe partir de importes nativos por línea; no dividir el precio propio USD por tasa otra vez. |
| SQL local fn_eliminar_order_detail_con_devolucion_v2 | Recalcula venta por SUM(importe_real) y asigna ese resultado a monto de pagos. | Ruta de devolución con riesgo de destruir desglose; archivo local no demuestra que esta función esté desplegada en newa. Auditar integración Carnaval antes de permitirla sobre ventas nuevas. |

Contrato técnico recomendado para revisión:

- Totales nativos como mapa por moneda; equivalentes contables con unidad CUP explícita; bruto y neto diferenciados.
- Mantener total/payloads legacy para órdenes legacy. El contrato nuevo requiere getters/serialización identificados, no cambiar silenciosamente la unidad de Order.total.
- No resolver todos los consumidores rellenando cualquier total escalar con una suma equivalente sin revisar si espera bruto, neto, cobrado o deuda.
- Centralizar la agregación de snapshots para registro, edición, checkout, sync y contrato de reporte. El servidor recalcula y valida importes; no acepta un total del cliente como autoridad.
- Incluir promoción y descuento final en cada detalle o atribución explícita por detalle, para que totales y cobros se reconstruyan de forma reproducible sin consultar reglas actuales.
- La elección final de los campos legacy sigue abierta (PCS-D02); no introducir nativos en esos campos para avanzar parcialmente.

## 5. Selección de precios y descuentos

### Ampliación de precios específicos TPV aprobada funcionalmente

- Extender la tabla actual con precio_venta_usd opcional y permitir precio_venta_cup opcional. Exigir al menos un precio específico y valores positivos cuando se informen. El DDL concreto requiere revisar consumidores y clientes legacy antes de permitir registros solo USD.
- Cada moneda se resuelve por separado: específico TPV vigente → general vigente de esa moneda → sin precio, bloquear. No convertir entre importes propios.
- Vacío significa heredar. La última configuración vigente con una moneda vacía hereda del general, no busca un específico anterior de esa moneda. Para heredar ambas, desactivar la configuración específica.
- Conservar registros CUP existentes sin fabricar USD. Extender formularios, modelos, importaciones, RPC de edición offline y sync para transportar ambos precios y su procedencia.
- newa: la tabla actual exige CUP no nulo, restringe CUP > 0 y tiene unicidad por producto/TPV/fecha_desde. Se comprobó RLS off y ausencia de policies; cerrar esta exposición dentro de la ampliación antes de habilitar clientes nuevos.
- Lectura por acceso a tienda; escritura administrativa autorizada y validación cruzada de tienda de producto/TPV. No reutilizar un helper que excluya vendedores como única policy de lectura.
- Compartir contrato de resolución entre servidor/admin/vendedor y caché existente. Mostrar precio efectivo y origen antes de guardar o vender; conservar snapshots de órdenes iniciadas.
- Casos de prueba obligatorios: específico en ambas monedas, solo CUP, solo USD, herencia por moneda, ausencia total de precio, cambios de vigencia, regla de tienda forzada, caché vacía y permisos.

### Reglas generales

- Fuente vigente por fecha del servidor e ID mayor; variantes NULL/0 representan base. Usar las vistas existentes, no created_at.
- Extender el sync de productos para conservar ambos precios y sus metadatos. No crear segundo catálogo offline.
- Precio faltante y precio numérico cero no se deben confundir automáticamente con promociones gratuitas. La regla para gratuidad requiere confirmar los casos existentes.
- Al elegir moneda, resolver primero su precio propio; aplicar luego reglas compatibles con medio, promoción, variante y presentación.
- Evitar convertir un descuento monetario CUP en un número USD por cambiar la etiqueta.
- Promociones porcentuales pueden evaluarse sobre precio nativo si su contrato lo permite. Descuentos/importes fijos, mínimos monetarios y descuentos globales de orden necesitan reglas explícitas antes de habilitarlos en órdenes mixtas.
- El precio ya seleccionado se congela con la línea. Cambiar moneda/medio exige mostrar y confirmar el nuevo precio, no una recalculación invisible al volver del checkout.

### Promociones y descuentos: evidencia adicional y propuesta pendiente

Lectura confirmada:

- newa app_mkt_promociones tiene valor_descuento y min_compra, pero no moneda ni valores separados CUP/USD. app_dat_descuentos_vendedor tampoco identifica moneda de sus importes.
- PromotionRules clasifica descuentos/recargos porcentuales y fijos. La compatibilidad por medio se verifica antes de elegir el precio final.
- isMinimumPurchaseMet compara min_compra con cantidad. No reinterpretar ese campo como umbral de dinero; comprobar las demás rutas antes de modificarlo.
- PriceUtils.roundDiscountPrice redondea a entero. Su uso en calculatePromotionPrices perdería centavos USD; no reutilizarlo sin una política de precisión explícita para la rama nueva. El comportamiento legacy no se cambia incidentalmente.
- Checkout tiene además un descuento de código promocional escalar; no basta corregir la promoción por producto para cubrir descuentos globales.

Reglas confirmadas: descuentos asociados al detalle del producto en modalidad nueva. Esta decisión sustituye la propuesta anterior de descuento manual global por moneda; no se aprobó reparto proporcional ni registrar descuentos como gastos operativos.

1. Porcentajes: mismo porcentaje sobre el precio propio de cada moneda, respetando reglas de medio, cantidad y compatibilidad.
2. Descuento/recargo fijo automático: valor explícito por moneda; no heredar un valor CUP como USD ni convertirlo. Si falta valor aplicable, esa promoción no se aplica a esa moneda y el UI lo informa, sin bloquear por ello una venta con precio válido.
3. Ausencia de descuento no equivale a precio faltante. Son validaciones distintas; precio y tasa siguen sujetos a las restricciones confirmadas.
4. Descuento manual asociado a una línea concreta: su moneda es la de esa línea y conserva su medio. No hay un importe global sin atribución que luego se distribuya entre productos. Identificar por id de línea cliente/extracción, no solo por producto, pues el mismo producto puede estar en líneas con monedas/medios diferentes. Confirmado por el usuario: el monto fijo manual se aplica por unidad de la línea, no una sola vez sobre su subtotal. Ejemplo: 3 unidades a 100 CUP menos 10 CUP por unidad dejan 90 CUP unitarios, descuento total de 30 CUP y neto de 270 CUP. Conservar descuento unitario y total derivado de cantidad; no confundir unidad vendida/presentación con unidades base de inventario.
5. Mantener por detalle bruto, promoción/descuento aplicado, importe nativo neto y equivalente contable neto. Los pagos se derivan de los netos agrupados por moneda/medio; no registrar bruto como dinero cobrado ni restar el descuento dos veces. No reevaluar snapshots con promociones actuales al sincronizar.
6. El descuento global legacy y sus registros históricos permanecen intactos cuando corresponda a esa modalidad. Los códigos/promociones globales que sigan disponibles en la nueva deberán producir descuentos efectivos y explicables por detalle; su adaptación debe verificarse antes de habilitarlos.
7. Redondeo nativo confirmado: conservar precisión intermedia y fijar neto final de línea CUP/USD a 2 decimales al más cercano, con empate half-up. Sumar esos netos por moneda/medio; mantener regla reproducible en Dart y SQL, sin reutilizar redondeo legacy a enteros.

Pruebas adicionales propuestas: porcentaje sobre CUP y USD propios, fijo solo CUP que no se aplique a USD, fijo USD independiente, recargo por medio correcto, mínimo por cantidad, ausencia de valores con aviso, preservación de centavos, asociación a la línea correcta en productos repetidos y sumas de netos por moneda/medio que coincidan con cobros sin doble descuento.

### Precisión del cobro confirmada y propuestas técnicas asociadas

- Regla funcional confirmada por el usuario para producto-v1: conservar precisión durante el cálculo unitario y multiplicación por cantidad; redondear el neto final de cada línea CUP/USD a dos decimales, al más cercano, con empate half-up para magnitudes positivas. No redondear primero cada unidad ni aplicar alza para cubrir un total convertido.
- Ejemplo confirmado: 3 unidades a 1,05 USD menos 10% producen 0,945 USD unitarios y 2,835 USD ideales de línea → cobrar 2,84 USD, no 2,85.
- Los grupos por moneda/medio suman netos de línea ya fijados; no vuelven a convertir ni recalcular precios. Total de ticket, payload y obligación del servidor debe coincidir.
- Propuesta técnica: si se almacenan/brindan componentes bruto/descuento/recargo redondeados, conservar precisión suficiente y residual explícito para reconciliar con el neto. No esconder un céntimo en un descuento manual distinto del elegido.
- Equivalentes contables: sigue por concretar el redondeo reproducible por línea y agregación por suma, sin usar sus diferencias para alterar el importe nativo cobrado. La reconciliación de pagos debe respetar snapshots, incluidos grupos con tasas distintas. La aprobación del cobro nativo no fija por sí sola la escala de tasas ni de contabilidad.
- Transporte decimal canónico y operaciones exactas en ambos extremos; no basar comparación de pagos en tolerancias float arbitrarias. No añadir dependencias sin revisar primero las disponibles y el plan técnico.
- Legacy mantiene sus reglas y tests actuales. test/moneda_venta_redondeo_test.dart verifica redondeo al alza de conversiones legacy; no cambiar esas expectativas para hacer pasar la modalidad nueva.
- Regla documentada, todavía no implementada. Antigüedad de caché/tasa y validación de gratuidad siguen siendo decisiones separadas.

## 6. Duplicados y edición

Identidad logística: producto, variante/opción, ubicación, presentación y lote cuando corresponda. Identidad monetaria: moneda, medio, precio y promoción/snapshot aplicables.

- Detectar el mismo producto con combinaciones distintas y mostrar diferencias antes de escribir en servidor o descontar stock.
- Separar: crear otro id de línea, sin que la RPC lo vuelva a fusionar.
- Unir: elegir combinación final explícita y volver a validar precio/tasa; mostrar cantidad, presentación e importe final; confirmar o cancelar sin efectos parciales.
- No unir cantidades de presentaciones diferentes como si fueran la misma unidad. Si una unión requiere conversión de unidades, no implementarla implícitamente; mantener líneas distintas o pedir especificación adicional.
- Editar/eliminar por id de línea, no por id de producto. Revisar ajuste de cantidades, edición pendiente, pagos y stock juntos.
- La modificación de una venta con cobros reales ya registrados necesita conciliación explícita; nunca sobrescribir cobros históricos para hacerlos coincidir con una nueva selección.

## 7. Checkout y pagos

Para modo producto, la obligación es el mapa (moneda, medio) → importe nativo. El cliente y servidor calculan ese mapa desde detalles, no desde un total convertido editable.

- No mostrar el editor de redistribución legacy en modo producto.
- Para cambiar selección, volver al detalle específico.
- El servidor compara cada obligación y pago en su moneda/medio. Rechaza moneda/medio inesperados y faltantes según las reglas de cobro de la operación.
- Un único excedente convertido en CUP no completa una obligación USD.
- El importe contable del pago debe reconciliarse con los snapshots de las líneas que lo originan. Si un grupo incluye tasas históricas distintas, no multiplicar todo por la tasa del último detalle: separar segmentos contables o conservar atribución por detalle y tasa efectiva reproducible.
- Mantener pagos reales de orden, sin duplicar ingresos al unir con detalles en reportes.
- Si venta y cobro se envían separados, el protocolo debe reanudar sin duplicar ni marcar pagada una venta incompleta. Preferencia a evaluar: finalización atómica e idempotente para ventas cobradas, conservando el flujo de pendientes que corresponda.
- Pago pendiente/crédito, sentinel 998, pagos parciales, devoluciones y cambio posterior de medio requieren trazar sus rutas antes de aprobar compatibilidad. No declarar dinero cobrado por el mero hecho de existir un medio seleccionado en un producto.

## 8. Online, offline y reintentos

- Snapshot de modalidad/política al iniciar la orden; snapshot monetario al seleccionar/confirmar la línea. Definir cuándo una modificación explícita renueva tasa/precio sin alterar líneas no editadas.
- Serializar todos los campos de Order/OrderItem en carrito, cola, JSON de pendientes y payload de sync.
- Sin precio propio cacheado: bloquear esa selección. Sin tasa válida: bloquear USD. Sin configuración utilizable: no inventar autorización ni activar modo nuevo.
- Configuración cambiada después no reinterpreta órdenes ya iniciadas. Snapshot no equivale a permiso irrestricto: validar usuario, tienda, TPV y operación en cada RPC.
- Cada orden y línea conserva identidad de cliente para recuperación tras timeout, reinicio y respuesta perdida. Índices/contratos de idempotencia deben impedir duplicación de operación, extracción, pagos y stock.
- No usar fallback a RPC legacy si rechaza campos nuevos o falla la autorización. Retener pendiente con diagnóstico accionable, sin borrarlo ni cobrar otra vez.
- No recalcular precios/tasas históricas desde catálogo actual durante sincronización.
- Offline con caché fresca, vacía y stale tiene pruebas separadas; no inventar un TTL. La validez de tasas/cache debe apoyarse en reglas aprobadas.

### Infraestructura de reintento ya existente en newa

Verificado por lectura de cliente, esquema y fragmentos de RPC:

- AutoSyncService persiste client_uuid y client_uuid_pago mediante _persistPendingOrderSyncKeys antes de solicitar venta/pagos. Reutilizar esas identidades; no generar otra en cada intento.
- La ruta preferida es fn_registrar_venta_offline_v4, con p_client_uuid, productos y p_pagos. La función valida acceso a tienda, usa el registro de idempotencia y llama a fn_registrar_venta_v3 y fn_registrar_pago_venta_v2.
- El cliente tiene fallbacks v4 → v3 → otras variantes, incluso retirando p_pagos/fecha. Con producto-v1 no se permite degradar el contrato ni separar atómicamente lo que se envió junto; los fallbacks legacy siguen solo para órdenes legacy.
- La ruta online actual registra venta y después pagos en llamadas separadas, con una comprobación cliente de coincidencia de pagos. Esa comprobación no sustituye exclusión de concurrencia ni validación autoritativa de la base.
- app_dat_operacion_offline_idempotencia ya existe: client_uuid UUID como PK, id_operacion, tipo, uuid_usuario y created_at. En la inspección de newa tiene RLS off y ninguna policy. No usarla como frontera de seguridad sin endurecer sus accesos y revisar todos los tipos de operación que la comparten.
- Los fragmentos offline v4 muestran consulta previa del UUID, creación y luego INSERT ... ON CONFLICT DO NOTHING. La unicidad del registro evita dos claves iguales, pero no demuestra que dos creaciones previas a ese insert no puedan producir efectos duplicados. Hace falta validar concurrencia con dos sesiones.

### Protocolo de producto-v1 propuesto para revisión

1. Persistir UUID estable y snapshot completo antes del primer envío, también en checkout online, para recuperar tras cierre/reinicio o respuesta perdida.
2. En cada solicitud autenticar usuario y validar tienda/TPV antes de devolver un resultado previo. Un UUID conocido no autoriza acceder a una venta ajena.
3. Adquirir exclusión transaccional por identidad de solicitud antes de consultar/crear operación (por ejemplo, advisory transaction lock sobre clave estable); no confiar únicamente en un SELECT seguido de INSERT.
4. Vincular la identidad al tipo de operación, usuario y operación/tienda. Proponer una huella de payload canónico para distinguir reenvío exacto de reutilización de clave con contenido diferente. Revisar su extensión aditiva en la infraestructura existente; no crear una segunda tabla de deduplicación por defecto.
5. UUID existente + mismo contenido autorizado: devolver mismos ids y resultado, sin repetir stock, pagos ni comanda. Misma clave + contenido financiero distinto: conflicto explícito, no sobrescribir ni inventar otro UUID para evitarlo.
6. Venta cobrada de mostrador: crear operación, detalles, descuentos, inventario, pagos y registro de idempotencia en una transacción; cualquier error revierte ese intento completo.
7. Mesas/cocina: reconocer los efectos ya ejecutados al pedir. El cobro no vuelve a descontar stock ni emite la misma comanda; requiere contrato específico con ids de cuenta/línea, no aplicar ciegamente el alta de mostrador.
8. Respuesta perdida: reenviar misma identidad y contenido. Fallo real de validación: retener cola y explicar motivo. Una edición intencional es otra revisión autorizada con control de concurrencia, no un replay distinto bajo la misma clave.
9. RLS/policies y permisos de la infraestructura compartida se proponen en SQL separado revisado, con pruebas de los usos existentes. No se cambió esa tabla ni sus RPC durante esta exploración.

### Tasas cacheadas y evidencia offline

UserPreferencesService ya almacena tasas de tienda y timelines USD→CUP de tienda/globales con savedAt. Reutilizar el pipeline existente; el mapa simple de valores no basta para explicar fecha/origen de un snapshot histórico.

El backend debe poder comprobar origen/alcance de precio, tasa y política sin aceptar un JSON arbitrario como autorización. Un snapshot firmado o revisión emitida por el servidor es una opción técnica a evaluar; no demostraría por sí solo la hora exacta de creación de una orden en un dispositivo offline. Separar autenticidad de la política descargada, autorización actual del usuario y aceptación de su uso offline. La regla de antigüedad admisible sigue pendiente: no inventar un TTL ni presentar el reloj local como prueba irrefutable.

## 9. Cobertura de rutas y reportes

Debe inventariarse detalle, escáner, búsqueda, carrito, preorden, mesa/cuenta, cocina, edición de pendientes, cambio de cantidad, cobro parcial y anulación. Ninguna ruta puede activar modo producto y enviar un payload legacy a espaldas del usuario.

Mesas/cocina usan servicios y RPC propios, con efectos de stock/comanda al pedir. Antes de cualquier efecto hay que validar selección monetaria. No decidir que esas rutas quedan fuera sin aprobación del usuario.

Tickets, resumen de orden y caja no deben sumar nativos de distintas monedas ni imprimir una etiqueta general falsa. Conservar formatos legacy para órdenes legacy. No añadir desglose visual nuevo a reportes admin; sí ajustar contratos mínimos antes de habilitar ventas nuevas.

Los reportes futuros deben distinguir detalle comercial y pago cobrado, consolidar solo equivalentes y marcar históricos sin atribución. El módulo de reportes depende de este contrato; la activación de tiendas debe esperar a que consumidores críticos interpreten los nuevos campos correctamente.

## 10. Seguridad y despliegue

- RLS existente de extracciones/operaciones/pagos debe revisarse al diseñar la migración; las RPC SECURITY DEFINER no sustituyen aislamiento por tienda.
- Cualquier tabla nueva: ENABLE RLS y policies inmediatamente después de CREATE TABLE en el mismo script. No usar USING(true) como atajo.
- SQL versionado bajo docs/plan-multimoneda; no aplica inventtia_flow salvo que aparezca una dependencia real.
- Migraciones aditivas, sin reconstrucción histórica. Backend compatible antes de cliente/activación; flag false hasta terminar el recorrido.
- Usuario ejecuta primero en newa desde SQL Editor. Agente inspecciona y verifica en lectura. Promoción a main separada y autorizada.
- No iniciar APIs, servidores ni despliegues automáticamente.

## 11. Criterios de aceptación y pruebas

| ID | Verificación requerida |
|---|---|
| PCS-01 | Flag false conserva precios, editor, pagos online/offline y JSON legacy. |
| PCS-02 | CUP/USD usan precios propios; precio o tasa ausente bloquean la selección correspondiente. |
| PCS-03 | Forzado se respeta sin fallback; snapshot de orden iniciada sobrevive a cambios posteriores. |
| PCS-04 | Una línea tiene una combinación para toda su cantidad; presentaciones/factores no se pierden ni duplican. |
| PCS-05 | Separar/unir duplicados funciona en UI, carrito, persistencia y RPC sin fusión silenciosa. |
| PCS-06 | Checkout y servidor validan obligaciones nativas por moneda/medio, nunca solo equivalente CUP. |
| PCS-07 | Snapshot de precio, descuento y tasa roundtrip en JSON/copyWith/offline/reinicio sin pérdida. |
| PCS-08 | Reintento tras respuesta perdida no duplica venta, detalle, pago, descuento de stock ni comanda. |
| PCS-09 | Registros históricos/no comerciales siguen válidos, sin atribución inventada. |
| PCS-10 | Roles/tiendas ajenas no pueden escribir/leer ventas mediante manipulación del snapshot. |
| PCS-11 | Todas las rutas habilitadas soportan contrato nuevo antes de activar el flag en tienda. |
| PCS-12 | Reportes no duplican ingresos, tickets no mezclan nativos y cobros reales siguen independientes. |

Pruebas nuevas a planificar: modelo/roundtrip, resolver de precio nativo, identidad de líneas, agrupación de obligaciones, validación de pagos, integración SQL/idempotencia y offline. Nombres de archivos no fijados todavía.

Regresiones existentes del vendedor a conservar, desde ventiq_app:

```powershell
flutter.bat test --no-pub test/checkout_payment_lines_test.dart test/multimoneda_core_test.dart test/descuento_multimoneda_test.dart test/order_usd_payments_test.dart test/payment_currency_amounts_test.dart test/home/app_compile_test.dart
flutter.bat test --no-pub test/home/product_detail_price_cache_test.dart test/home/product_detail_phase5_test.dart test/venta_ingredient_consumo_test.dart
```

La existencia y adecuación de cada test se verificará al crear el plan. Contratos estáticos SQL no sustituyen ejecutar en newa; tests Flutter no sustituyen venta, sync ni impresión física. No se ejecutaron tests al redactar este borrador.

## 12. Registro de decisiones del contrato aprobado

Estado vigente: PCS-D01–PCS-D06 aprobados con el contrato consolidado. Las formulaciones propositivas de las filas siguientes describen el diseño presentado y quedan ratificadas por la aprobación de sección 13; solo quedan plan, tareas, implementación y verificación, no otra aprobación de las mismas reglas.

| ID | Tema | Estado |
|---|---|---|
| PCS-D01 | Precios específicos TPV multimoneda con herencia por moneda. | Confirmado por el usuario: ampliar configuración existente para CUP/USD independientes; vacío hereda general de la misma moneda. Sin precio en ninguna fuente, bloquear esa selección. Diseño SQL/RLS/sync pendiente de plan y revisión. |
| PCS-D02 | Totales y aliases legacy. | Recomendación concretada en 0.1: nativos explícitos y proyección CUP compatible previa al manual, con neto explícito y adapters por versión. Pendiente aprobación del contrato consolidado y pruebas de consumidores, no una elección de nombres por el usuario. |
| PCS-D03 | Promociones/descuentos y mínimos en órdenes mixtas. | Automáticas confirmadas: porcentaje sobre precio nativo, fijo por moneda sin conversión; si falta fijo, no aplicar esa promoción y avisar sin bloquear venta válida. Decisión posterior: descuento manual por línea concreta, en su moneda y sin cambiar medio; reemplaza global sin atribución. No aprobado reparto proporcional. Fijo manual por unidad confirmado; total descontado = descuento unitario × cantidad de la línea. Redondeo del neto nativo de línea confirmado a 2 decimales half-up tras multiplicar por cantidad, sin redondeo intermedio. min_compra por cantidad según evaluador actual, no reinterpretar como dinero. |
| PCS-D04 | Política histórica offline y reintentos. | Recomendación en 0.2: revisión inmutable y constancia emitida al usuario/dispositivo, integrada al sync existente; exclusión transaccional, pertenencia de UUID y huella de contenido. RLS de idempotencia debe endurecerse. Aceptación offline bajo ventana existente y revisión de envíos tardíos requieren aprobación operativa junto con la spec. |
| PCS-D05 | Mesas/cocina, preorden, crédito/parciales y ajustes. | Cobertura obligatoria fijada en 0.3, sin exclusiones silenciosas. Propuesta de deuda nativa y medio real diferido para pendientes requiere aprobación; después se detalla SQL y pruebas de cada transición. |
| PCS-D06 | Tasas/cache y precisión. | Redondeo nativo ya confirmado. Contabilidad propuesta a 2 decimales CUP por línea, tasa publicada sin redondear a centavos, y aceptación offline ligada a licencia existente; sometidos a aprobación de la spec. Sin TTL monetario arbitrario nuevo. |

## 13. Estado y puerta siguiente

El usuario aprobó explícitamente el contrato consolidado de secciones 0.1–0.3 y la secuencia de sección 14, incluidas precisión contable, política offline y crédito. La aprobación reemplaza el estado pendiente de aprobación de las propuestas descritas en esas secciones y PCS-D02/D04/D05/D06; no demuestra que estén implementadas o probadas. Sin cambios de aplicación, DDL ni ejecución de pruebas. El plan técnico y el desglose MC-xxx también fueron aprobados; el usuario autorizó el primer lote MC-001–MC-003, cuyo estado/evidencia está en el plan. Las tareas posteriores respetan dependencias y puertas específicas. Ninguna aprobación documental autoriza escrituras remotas del agente, activación piloto ni cambios en main.

## 14. Secuencia orientativa para revisar junto con la spec

No es todavía un plan de tareas aprobado ni permiso de ejecución:

1. Backend y seguridad: revisiones/constancias de política, protección de infraestructura compartida y contratos monetarios aditivos; precios específicos CUP/USD y resolver común con herencia por moneda. Pruebas SQL en newa ejecutadas por el usuario.
2. Proveedor de configuración: flag apagado, permisos admin, snapshot consistente y caché/constancia por tienda/dispositivo. No activar tiendas aún.
3. Detalle comercial: ambos precios propios, descuento manual unitario, cálculo decimal, identidad estable, duplicados confirmados y persistencia de snapshots.
4. Registro y cobro: checkout restringido, obligaciones nativas y transacciones idempotentes online/offline. Añadir pruebas de concurrencia y respuesta perdida.
5. Cobertura: preorden, mesa/cocina sin doble stock/comanda, edición/cancelación y CxC/liquidaciones nativas con trazabilidad por línea.
6. Consumidores críticos: contratos mínimos de reportes/caja/ticket/métricas por versión; la spec de product-currency-report-contracts se completa antes de habilitar ventas nuevas. Sin nuevos desgloses visuales de reportes.
7. Verificación integral: flag off/on, online/offline fresco/vacío/stale, permisos, tasas históricas, promociones, crédito, impresora y recuperación. Solo después habilitar una tienda de pruebas; promoción a main separada y autorizada.

## 15. Contrato canónico y fixtures — MC-003

Esta sección fija el contrato de intercambio, no implementa modelos ni RPC productivos. Único discriminador de transporte: version_monetaria = producto-v1. La expresión product-v1 usada en prosa identifica el mismo diseño, no un alias aceptado en la API. Payload nuevo sin versión o con versión inválida no se degrada a legacy; las órdenes legacy se despachan mediante su contrato capturado y la reanudación autorizada del plan.

### Representación y autoridad

- IDs bigint: cadenas de enteros positivos sin signo ni ceros iniciales, en rango PostgreSQL bigint. UUID de orden/línea/pago/revisión/constancia estables; normalizar su representación en el borde. id_medio_pago es entero smallint validado contra el catálogo, nunca un monto.
- Dinero, cantidad, factor, porcentaje y tasa: cadenas decimales finitas, sin exponente ni separadores regionales. Normalizar ceros fraccionarios redundantes para identidad/huella. No aceptar JSON number para valores financieros v1 ni obtener su cadena después de haber perdido precisión en double.
- Cantidad/precio publicado/tasa/factor positivos; manual no negativo y sujeto a permisos/coherencia. Neto cero solo por ajuste autorizado, no por precio faltante. Importes finales nativos y equivalentes CUP se serializan con dos decimales; precio unitario intermedio y residual conservan precisión.
- Instantes nuevos UTC explícito terminado en Z; fechas de vigencia son fechas del servidor. creada_en offline es una declaración, no prueba irrefutable de la hora física.
- El servidor deriva actor de autenticación. id_vendedor/origen se validan contra tienda, asignación, constancia y delegación autorizada; ningún booleano del DTO concede permisos.

### Solicitud de creación

| Campo/grupo | Contrato |
|---|---|
| version_monetaria, client_uuid | Versión exacta e identidad estable del intento comercial, persistidos antes de red. |
| id_tienda, id_tpv, id_vendedor, id_dispositivo | Ámbito declarado que debe coincidir con autorización/constancia. No sustituye identidad autenticada. |
| creada_en, origen | Instante declarado y tipo mostrador/preorden/mesa. Mesa requiere referencia válida de cuenta; no confiar en stock_movido del cliente para omitir inventario. |
| politica | id_revision e id_constancia emitidos por servidor, flag activo, forzado y monedas habilitadas del snapshot. El servidor valida coincidencia; copiar esos campos no autoriza una política vieja arbitraria. |
| lineas | Lista no vacía con id_linea_cliente único. No usar id_producto como identidad de extracción. |
| Logística de línea | id_producto, variante/opción/ubicación/presentación cuando correspondan, factor y cantidad de unidad vendida. El servidor valida relación y fuente del factor, no acepta inventario calculado arbitrariamente. |
| Moneda y selección | moneda_venta CUP/USD y seleccion_cobro discriminada como medio_pago o pendiente. Medio real lleva id_medio_pago; pendiente lleva null, no un pago ficticio. |
| Precio y manual | precio_unitario_nativo antes de automáticos; descuento_manual_unitario_nativo por unidad, motivo y permisos cuando se aplique. No descuento global repartido. |
| Snapshots | snapshot_precio, snapshot_tasa y snapshot_ajustes_automaticos preservan fuente/identidad/valor/regla publicados y evidencia del servidor. Un ajuste fijo pertenece a la moneda de línea; ausencia no significa convertir otra moneda. |
| pagos | Solo cobros reales con id_pago_cliente estable, moneda, medio, monto_nativo y aplicaciones por id_linea_cliente. Sumas por pago/línea no exceden obligaciones ni cruzan monedas. |

Pendiente no se almacena como FK de un medio real inexistente: mapear el sentinel legacy a estado explícito. La persistencia exige FK cuando hay medio real y estado/procedencia cuando está pendiente. El primer cobro fija su medio real; siguientes parciales respetan esa elección y moneda original, conservando selección inicial/auditoría.

Bruto, previo al manual, neto y equivalentes se derivan en el servidor con la secuencia aprobada. Totales suministrados por cliente, si se incluyen como assertions, nunca son autoridad. Aplicaciones conservan atribución de equivalente por detalle/tasa; no usar una única tasa reciente para todo un grupo.

### Evidencia de publicación y fuentes mutables

MC-001 confirmó que la tasa global puede cambiar bajo el mismo id; tampoco se presume inmutable todo acceso a precio TPV. Cada snapshot verificable debe contener referencia de origen, identidad del registro, valor/regla y momento publicado, más evidencia_publicacion opaca emitida por servidor y vinculada a ese contenido/ámbito. La constancia de política sola no demuestra el precio o tasa.

La evidencia puede referenciar una publicación inmutable o una prueba verificable de emisión; el detalle de almacenamiento/criptografía y gestión de claves pertenece a MC-007/MC-024 y requiere revisión antes del SQL. Un hash que calcule libremente el cliente no es evidencia. No publicar secretos en cliente ni reconstruir el pasado consultando solo la fila actual. Para CUP la tasa identidad 1 es intrínseca; USD necesita fuente y evidencia válida. Modo nuevo falla cerrado si el servidor no puede verificar snapshots; no altera pendientes para lograr sincronizarlos.

### Resultado, errores y reintento

Éxito: status success, versión, client_uuid, id_operacion, revisión de orden, correspondencias línea cliente/extracción, netos/obligaciones/pagos y estado financiero pagada/parcial/pendiente. IDs y dinero financiero se mantienen iguales en replay; idempotent puede cambiar como dato diagnóstico.

Error: status error, error_code estable, message segura y retryable. Sin detalles internos/secretos/stack traces. Casos de contrato: DECIMAL_STRING_REQUIRED, INVALID_DECIMAL, INVALID_QUANTITY, UNSUPPORTED_CURRENCY, CONTRACT_VERSION_UNSUPPORTED, NATIVE_PRICE_UNAVAILABLE, SNAPSHOT_EVIDENCE_REQUIRED, SNAPSHOT_INVALID, PAYMENT_SELECTION_MISMATCH, IDEMPOTENCY_CONFLICT y OFFLINE_REVIEW_REQUIRED. Son códigos del contrato a implementar, no resultados de RPC ya existentes.

La huella se calcula en servidor sobre contenido financiero/de efectos normalizado, incluyendo ámbito, selección, cantidades, referencias y aplicaciones, con orden determinista de claves/líneas. Misma clave con contenido financiero distinto produce conflicto; editar o liquidar después es otra intención autorizada con su propia clave y revisión esperada, no un replay modificado. Un error de contrato o autorización no provoca fallback a legacy ni regeneración automática de UUID.

### Artefactos compartidos y límite de verificación

- docs/plan-multimoneda/product_currency_v1_fixtures.json: fuente ficticia de vectores monetarios, agrupaciones, resolución de precios, inválidos esperados y ejemplo DTO. Todos los IDs/pruebas de publicación son ficticios; fixture-only nunca acredita una publicación real ni se envía a RPC de negocio.
- docs/plan-multimoneda/product_currency_v1_fixture_checks.sql: SELECT aritmético numeric sobre los mismos vectores; no toca tablas ni llama RPC. No es migración ni prueba de autorización.
- ventiq_app/test/product_currency_v1_fixtures_test.dart: integridad de fixtures y equivalencia del dataset SQL/JSON, decimales de texto y agregación de netos fijados. No implementa ni certifica el futuro núcleo monetario/DTO productivo.

Los casos inválidos y de precio describen expectativas para MC-011/MC-020/MC-024; conservarlos no significa que los validadores/resolver ya existan. La paridad con la calculadora productiva se verificará al implementarla, no solo con este oráculo independiente.
