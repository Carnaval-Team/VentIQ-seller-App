# Referencia de industria: inventario con multiples presentaciones

Investigacion de documentacion publica de Odoo, SAP (B1 / ERP / S4HANA / EWM),
NetSuite, Dynamics 365 (Business Central y Supply Chain Management) y Zoho
Inventory, hecha el 2026-08-26 para respaldar
`docs/PLAN_PRESENTACIONES_INVENTARIO.md`.

Sin evidencia: Fishbowl y Cin7 (portales tras login). No se afirma nada de ellos.
"Bill of Packaging" NO existe en la doc publica de SAP Business One; el
equivalente ahi es UoM Group + Items per Sales/Purchasing UoM.


## 1. Terminologia

| Concepto | Ingles | Espanol | Producto |
|---|---|---|---|
| Abrir / desempacar | Unpack, break bulk, split | **Desempaquetar** | Odoo (boton `Unpack` en la ficha de Paquete). "Desempaquetar" es la traduccion **oficial** de Odoo (`addons/stock/i18n/es.po`) |
| Empaquetar | Pack, Put in Pack, Assemble | **Empaquetar / Poner en paquete** | Odoo `Put in Pack`; NetSuite Assembly Build; Zoho Assembly |
| Conversion en el kardex | Repack / Pack / Unpack | Reembalar / embalar / desembalar | SAP ERP-EWM transaccion HU02: "Packing involves transferring unpacked material quantities to packed material quantities... Unpacking involves transferring packed material quantities to unpacked" |
| Desarmar a componentes | Assembly Unbuild | Desmontaje | NetSuite: baja el ensamble y sube los componentes |
| Reempaque en almacen | Warehouse Internal Repacking | Reembalaje interno | SAP S/4HANA BP 3BW: pack / repack / **unpack stock from one HU onto the bin** |

Dato relevante: **ningun producto revisado tiene un tipo de movimiento llamado
"apertura de caja" a nivel de unidad de medida.** La conversion siempre se modela
como repack/unbuild entre *contenedores o items*, nunca entre unidades de medida.

URLs:
- https://www.odoo.com/documentation/18.0/applications/inventory_and_mrp/inventory/product_management/configure/package.html
- https://github.com/odoo/odoo/blob/18.0/addons/stock/i18n/es.po
- https://help.sap.com/docs/SAP_ERP/248c3cdd7e6548999a7f5b95118f4522/258dbf53f106b44ce10000000a174cb4.html
- https://help.sap.com/docs/SAP_S4HANA_CLOUD_BEST_PRACTICES/68f9e85c72f876ec92ad076c6b417d26/826537e63e7243c48680f3bdfaf69ebf.html
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N3191993.html


## 2. LA DECISION CENTRAL: base unica vs saldos por empaque

**Todos los ERP revisados guardan el stock en UNA unidad base y solo convierten
para mostrar. Ninguno guarda saldos fisicos separados por presentacion.**

- **Odoo**: "The specified unit is also the unit used to keep track of the
  product's inventory and internal transfers". El packaging es solo etiqueta de
  venta/compra con `Contained Quantity`; `stock.quant` tiene un unico
  `product_uom_id`. Los **Packages** (con boton `Unpack`) si son entidades
  reales, pero son *contenedores identificados*, no presentaciones de catalogo.
- **Business Central**: "The base unit of measure **defines how you store it in
  inventory**". El Item Ledger Entry lleva `Quantity`, `Unit of Measure Code` y
  `Qty. per Unit of Measure`: guarda base + memoria de la UoM del documento.
- **NetSuite**: base unit + conversion rate. Stock / Purchase / Sale Units son
  presentacion, no saldo: "The stock unit you choose here is the default for
  calculating and **displaying** ... Quantity on Hand".
- **SAP Business One**: el conteo por UoM se **suma y convierte**: "counted 3
  boxes of item I001 (18 bottles) and an extra 5 bottles... the counted quantity
  is 18 + 5 = 23 (bottles)".
- **D365 SCM (WMS)**: unit sequence groups pallet->caja->pieza, pero "The
  smallest unit in a sequence group... must match the inventory unit".
- **Zoho Inventory**: un solo `Unit` por item; para vender empaques hay que crear
  **Assembly** (stock propio, consume componentes) o **Kit** (sin stock propio).

### Que significa esto para VentIQ

El modelo de saldos fisicos separados por presentacion es **deliberadamente
distinto al del mainstream**. El unico analogo real en la industria es
"producto separado + assembly/unbuild" (Zoho; y es la recomendacion de los foros
de Odoo: "you'd have to track water-bottle and water-6-packs separately. And make
inventory adjustments when opening water-6-pack").

Esto NO invalida la decision del plan: la operacion real del usuario es contar
"4 cajas y 4 unidades" en el estante, y el mainstream obliga a workarounds
(productos duplicados + ajustes manuales) precisamente para lograr eso. Pero
implica dos obligaciones de diseno, ambas ya cubiertas por la Fase 0:

1. El equivalente base tiene que estar SIEMPRE disponible y ser la base del
   dinero (`fn_equivalente_base`). Es lo que todo el resto de la industria usa
   como fuente de verdad, y sin el no hay valoracion ni rotacion comparable.
2. La conversion tiene que ser un movimiento trazable y distinguible, no un
   ajuste (`id_conversion` + `origen_cambio = 20`). En la industria el analogo
   (repack / unbuild) siempre es una transaccion con nombre propio.

URLs:
- https://www.odoo.com/documentation/18.0/applications/inventory_and_mrp/inventory/product_management/configure/uom.html
- https://learn.microsoft.com/en-us/dynamics365/business-central/inventory-how-setup-units-of-measure
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2212390.html
- https://help.sap.com/docs/SAP_BUSINESS_ONE/68a2e87fb29941b5bf959a184d9c6727/45221d4973c80108e10000000a114a6b.html
- https://learn.microsoft.com/en-us/dynamics365/supply-chain/warehousing/unit-measure-stocking-policies
- https://www.zoho.com/inventory/help/items/composite-items.html
- https://www.odoo.com/forum/help-1/how-can-i-sell-in-different-units-of-measurement-within-the-point-of-sale-287081


## 3. Conversion automatica vs explicita

Los tres comportamientos existen, en niveles distintos:

- **Automatica y sin movimiento** (solo aritmetica): Odoo convierte UoM de
  compra->inventario y venta->entrega. NetSuite y BC igual. No hay asiento de
  conversion porque el saldo nunca fue por empaque.
- **Explicita, con movimiento real**, cuando el contenedor es fisico: SAP HU02
  Repack/Pack/Unpack; la app *Pack Handling Units - Advanced* con drag&drop y
  "Partial Quantity"; Odoo `Unpack`; NetSuite Assembly Unbuild (o su alternativa
  documentada: ajuste de inventario -1 del ensamble, +componentes).
- **Bloqueo en vez de apertura automatica**: Odoo `Reserve Only Full Packagings`
  vs `Reserve Partial Packagings` (pedido de 2 packs de 12 con 22 en stock:
  reserva 12 vs 22). D365 `Restrict to sales unit`: si la reserva deja unidades
  de venta incompletas, **bloquea la liberacion al almacen con error**.
- Business Central **no tiene** transaccion de conversion de UoM. Confirmado: el
  Item Reclassification Journal solo cambia ubicacion, bin, lote/serie,
  caducidad y dimensiones.

URLs:
- https://help.sap.com/docs/SAP_S4HANA_CLOUD/87f9b54f9c4f4e75aff0061860a6589a/86ad0462af4c4fc592d2525d71bf974b.html
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/bridgehead_161520846793.html
- https://learn.microsoft.com/en-us/dynamics365/supply-chain/warehousing/restrict-to-sales-unit
- https://learn.microsoft.com/en-us/dynamics365/business-central/inventory-how-transfer-between-locations


## 4. Patrones de UI reproducibles

- **Entrada mixta en una sub-ventana, no en la fila.** SAP B1 tiene "Inventory
  Counting by UoM" / "Inventory Posting by UoM": se abre desde la flecha del
  campo `Counted Qty` de la linea y se capturan cantidades por cada UoM, que el
  sistema suma y convierte. Es el patron mas directamente aplicable al
  formulario de entrada mixta de la Fase 2.
- **Selector de unidades multi-linea en movil.** NetSuite WMS: "A units selector
  appears on picking and receiving screens... You can add one line item for each
  unit configured on the item record" (ej. 7 eaches = 1 each + 1 case de 6).
  Ademas un **icono junto a Quantity Remaining que abre un popup "Conversion
  Units and Rates"**.
- **Limite de presentaciones visibles en movil.** D365 permite hasta 4 unidades
  del sequence group en conteo ciclico movil: "If you select more than four
  units, the additional units don't appear on the mobile device". Senal fuerte:
  maximo 3-4 presentaciones por pantalla.
- **Unidad por defecto segun el proceso.** D365 `Default unit for purchase and
  transfer` (recibir en Pallet, stock en Pcs). NetSuite: PO en purchase units,
  factura en sale units, ajuste en stock units.
- **La cantidad NUNCA va desnuda en reportes.** NetSuite: "reports you generate
  show units of measure based on the units used in transactions". BC guarda
  `Unit of Measure Code` + `Qty. per Unit of Measure` en cada movimiento.
- **Redondeo visible.** BC tiene `Quantity Rounding Precision` justamente porque
  5/6 de caja da 4,99998 piezas.

URLs:
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_156382534438.html
- https://help.sap.com/docs/SAP_BUSINESS_ONE/68a2e87fb29941b5bf959a184d9c6727/45221d4973c80108e10000000a114a6b.html


## 5. Quejas y errores conocidos (a evitar)

- **Odoo eCommerce/POS no soportan packaging bien, cinco versiones seguidas**:
  "the ecommerce app always sticks to the base unit (pcs)... they can put in 205
  pcs which's not a whole number of cartons".
- **Un usuario real rechaza el saldo por empaque por ilegible**: "Selecting
  different base unit is not feasible as it'd make awkward recordkeeping (e.g.
  on hand quantity of 100 cartons of 10 pcs or variations thereof, instead of
  directly showing 1000 pcs)". **Es el riesgo directo del modelo de VentIQ**: por
  eso el equivalente base tiene que estar siempre visible al lado del mixto.
- **Productos duplicados como workaround -> ajustes manuales al abrir cajas**,
  reconocido como friccion en los foros.
- **POS con una sola UoM**: "In Odoo POS, you can set only one Unit of Measure...
  you need customization".
- **Redondeo y desbordes**: BC 4,99998 piezas; NetSuite tope de 9.999.999.999
  unidades base por linea, que "can arise unexpectedly when you use small base
  units together with big conversion rates".
- **Cambios de configuracion irreversibles a proposito**: NetSuite "After you
  assign a units type to an item, the units type can't be edited except to add
  more units"; SAP B1 no permite cambiar la Base UoM. **Los factores deben ser
  inmutables una vez que el producto tiene movimientos.**
- **Series/lotes**: NetSuite exige nº de series = cantidad en unidades base.

URLs:
- https://www.odoo.com/forum/help-1/ecommerce-still-cannot-sell-by-multiples-of-packaging-even-in-v19-where-units-and-packages-have-been-combined-286826
- https://www.odoo.com/forum/help-1/sale-of-multiple-unit-of-measure-in-pos-287906
- https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_N2212143.html


## 6. Recomendaciones de UI para VentIQ (cajero primero)

1. Mostrar siempre **mixto + equivalente base en la misma linea**:
   `4 Cajas + 4 u  ·  = 52 u` (el equivalente en gris, secundario). Nunca solo
   "52 u" ni solo "4 + 4".
2. Maximo **3-4 presentaciones visibles** por producto en movil (regla D365); el
   resto tras "Ver mas".
3. Entrada mixta con **una fila por presentacion dentro de un bottom-sheet**
   abierto desde la linea del producto (patron SAP B1 "...by UoM"), con el total
   base calculado en vivo en el pie.
4. Preseleccionar la presentacion **segun el proceso**: entrada -> la mayor
   (Pallet/Caja), venta -> la menor (Unidad). Guardar el default por producto.
5. Un **chip toggle** de presentacion junto al campo cantidad en el TPV
   (Unidad | Caja | Pallet), no un dropdown: menos taps para el cajero.
6. Icono de info junto a la cantidad que abra **"Factores de conversion"**
   (1 Pallet = 12 Cajas = 144 u), copiando el "Conversion Units and Rates" de
   NetSuite WMS.
7. La conversion debe ser **una transaccion explicita y nombrada**, no un efecto
   lateral silencioso. Usar `Desempaquetar` / `Empaquetar` (terminos oficiales de
   Odoo en espanol) y registrarla en el kardex como tipo propio. **Ya cubierto
   por la Fase 0** (`app_dat_conversion_presentacion`, `origen_cambio = 20`).
8. En egreso con saldo insuficiente, **proponer la apertura en un dialogo de
   confirmacion de un toque** ("Faltan 4 u. Abrir 1 Caja (12 u)?"), con opcion
   "recordar y no preguntar". Es el punto medio entre la conversion silenciosa y
   el bloqueo tipo `Restrict to sales unit`. **Esto matiza la decision cerrada
   "abrir automatico" del plan: ver nota abajo.**
9. Mostrar el **remanente resultante** en ese mismo dialogo ("quedaran 8 u
   sueltas"): el sobrante suelto es el efecto que el cajero no anticipa.
10. En reportes y kardex, etiquetar la columna **"Cantidad (presentacion)"** con
    la presentacion en cada fila, y anadir una columna separada **"Equiv. base"**.
    No mezclar unidades en una sola columna sumable.
11. Precio y costo siempre **derivados y de solo lectura**, con la formula visible
    (`$12.00 x 12 = $144.00`), para que el cajero no dude ni intente editar.
12. **Congelar los factores** de una presentacion cuando el producto ya tiene
    movimientos (como NetSuite y SAP B1); los cambios solo via presentacion
    nueva. Y declarar la precision de redondeo para evitar el caso "4,99998".


## Notas para las fases siguientes

**Fase 2 (UI):** los puntos 1, 2, 3, 5, 6, 9, 10 y 11 son directamente
aplicables. El patron de bottom-sheet con una fila por presentacion (punto 3)
sustituye al "dropdown + una cantidad" que tiene hoy
`product_quantity_dialog.dart`.

**Decision pendiente del usuario (punto 8).** El plan tiene cerrada la decision
"abrir automatico" en todos los egresos, y la Fase 0 la implementa asi:
`fn_descontar_con_rebalanceo` abre sin preguntar. La industria no hace eso en
ningun caso: o convierte solo aritmeticamente sin movimiento, o exige una
transaccion explicita, o bloquea. La recomendacion del punto 8 es un tercer
camino: el SQL sigue igual (el rebalanceo automatico se queda), pero la **UI del
TPV pregunta antes** cuando va a abrir un empaque, mostrando el remanente. No
requiere ningun cambio en la Fase 0: `fn_rebalancear_presentaciones` ya devuelve
`estrategia`, `conversiones` y `maximo_convertible`, que es exactamente lo que
ese dialogo necesita para armarse. Queda a decision del usuario si se implementa
en la Fase 4.

**Candidato a Fase 0.4 (punto 12), no implementado.** Congelar
`app_dat_producto_presentacion.cantidad` una vez que el producto tiene
movimientos requiere un trigger BEFORE UPDATE que rechace el cambio de `cantidad`
si existe alguna fila en `app_dat_inventario_productos` de ese producto. Hoy
nada lo impide y cambiar un factor reinterpreta retroactivamente todo el
historico de saldos. No se implemento porque no estaba en el plan; conviene
decidirlo antes de la Fase 2, que es cuando empezaran a existir saldos no-base
de verdad.
