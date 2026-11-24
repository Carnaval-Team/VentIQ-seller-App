# Referencia de industria — cómo lo hacen los grandes

> Documento de apoyo del plan `PLAN.md`. No es una propuesta: es el estado del arte
> que se usó para decidir. Cada afirmación lleva fuente.

## 1. El ciclo Procure-to-Pay son cinco documentos, no uno

Los ERP grandes (SAP, Oracle, Dynamics, NetSuite, Odoo, ERPNext) modelan la compra como
una cadena de documentos con responsabilidades distintas:

| Documento | Pregunta que responde | Campos de control |
|---|---|---|
| Orden de compra (PO) | Qué se **autorizó** | Cantidad, precio, condiciones |
| Recepción (goods receipt) | Qué se **aceptó** | Recibido, rechazado, pendiente |
| Factura del proveedor | Qué se **factura** | Cantidad, precio, cargos |
| (Pago) | Qué se **desembolsa** | Medio, fecha, tasa |

El control se llama **three-way match**: se comparan PO, recepción y factura antes de pagar.
El objetivo textual: *"confirm that the business is paying for what it approved and
actually received"* ([Procure Utility](https://procureutility.com/blog/three-way-matching-po-receipt-invoice)).

Consecuencias que importan para este proyecto:

- **La recepción registra lo que llegó, no lo que se esperaba.** *"Record the quantity
  actually received, not the quantity expected. Separate accepted, damaged, rejected, and
  back-ordered quantities"* ([Procure Utility](https://procureutility.com/blog/three-way-matching-po-receipt-invoice)).
- **Entregas parciales: se acumulan cantidades.** *"Match each invoice to the applicable
  receipt or receipts. Track cumulative quantities so total invoicing cannot exceed the
  quantity ordered and accepted. Do not close the PO after the first partial invoice"*
  ([Procure Utility](https://procureutility.com/blog/three-way-matching-po-receipt-invoice)).
  → Traducido: una compra **no** se cierra en la primera recepción parcial.
- **No se paga por encima de lo recibido**, salvo tolerancia explícita. *"Most three-way
  match rules block payment above received quantity to prevent overbilling. If you allow
  tolerance, the delta usually posts to PPV or a quantity variance account"*
  ([Cleverence](https://www.cleverence.com/articles/for-business/purchase-order-accounting-entry-4827/)).

## 2. La reserva de dinero se llama *encumbrance* y NO mueve el dinero

Este es el concepto que el dueño describió sin saber el nombre: *"reservar el saldo una vez
se cree la compra para que vea que tiene dinero invertido en una compra"*.

En contabilidad presupuestaria (y en el control de compromisos de cualquier ERP serio), una
orden de compra crea un **compromiso**: reduce la disponibilidad, pero **no** toca el banco.

- *"A purchase order creates only a budgetary commitment"*
  ([CPA Study Notes](https://getoncourse.ai/lessons/cpa/state-and-local-governments/budgetary-accounting-and-encumbrances/encumbrance-accounting-in-governmental-funds/)).
- Al recibir: **se reversa el compromiso por su monto original** y se registra el gasto por
  el **monto real facturado**. La diferencia vuelve sola al disponible.
  > *"April 20 receipt: credit Encumbrances $40,000 — the original budgetary reservation is
  > reversed in full, using the purchase order amount... debit Expenditures $38,500 — the
  > fund recognizes the actual cost of supplies received, not the earlier estimate."*
  > ([CPA Study Notes](https://getoncourse.ai/lessons/cpa/state-and-local-governments/budgetary-accounting-and-encumbrances/encumbrance-accounting-in-governmental-funds/))
- La regla operativa, en una línea:
  > *"Record every purchase order and signed contract as a reservation the day it is issued,
  > not when the invoice shows up. Liquidate each reservation at its original amount the
  > moment goods are received, and book the expenditure at the actual invoiced figure so
  > variances land in the available balance on their own."*
  > ([Beancount](https://beancount.io/blog/2026/10/21/encumbrance-accounting-purchase-orders-reserve-budget-guide))
- Cancelar = **liberar** el compromiso. *"After receipt or cancellation, the related
  encumbrance accounts are cleared"* (CPA Study Notes, ibid).

**Por qué esto es la respuesta al requisito del dueño:** permite mostrar tres cifras
honestas a la vez — disponible, reservado, ejecutado — sin inventar dinero. El código actual
de VentiQ hace lo contrario: `fn_fdi_crear_inversion` **debita** el saldo al crear
(`extraccion_inversion`), es decir, trata la reserva como pago. Ver `02-contabilidad.md`.

## 3. GR/IR: lo recibido y no facturado tiene su propia cuenta

*"The GR/IR (also called receipts accrual or goods received not invoiced) holds the
temporary liability from receiving goods before being invoiced"*
([Cleverence](https://www.cleverence.com/articles/for-business/purchase-order-accounting-entry-4827/)).

Relevante cuando la mercancía llega antes que la factura del proveedor o de la importadora:
el inventario entra con su costo, y la deuda queda pendiente de conciliar. Si el sistema no
tiene este bolsón, esa mercancía aparece como "gratis", que es el error clásico.

## 4. Costo aterrizado (landed cost): se reparte por valor, peso o cantidad

Los costos que no son precio de factura (flete, aduana, seguro, pago a importadora) forman
un **pool** que se reparte entre las líneas de la compra.

- Los tres criterios estándar son **por valor, por peso o por cantidad**, y la elección
  cambia el costo unitario de cada línea — por eso hay que elegir uno y documentarlo
  ([Landed Cost Dashboard](https://github.com/MattNeill1/landed-cost-dashboard): *"see how
  overhead distributes across lines by VALUE, WEIGHT, or QUANTITY... switch the allocation
  basis... to see how the choice changes each line's landed cost"*).
- El costo aterrizado **se capitaliza en el inventario** y actualiza el costo unitario:
  *"purchase price plus allocated freight per unit, updated the moment a shipment cost
  changes"* ([mashreq-supply-chain](https://github.com/amirnsamimi/mashreq-supply-chain-management-system)).
- El caso real de este negocio está descrito casi literalmente en ese mismo proyecto:
  *"Importers buy on one invoice but receive goods across several shipments. A single
  invoice line — say 1,000 units — might leave the supplier in three parts, weeks apart,
  each with its own freight cost. Working out what a unit actually cost you means splitting
  each shipment's freight across the items inside it, then adding that back to the purchase
  price"* (ibid).

→ Es exactamente compra con factura + recepciones parciales + costos adicionales.

## 5. Anticipos: el dinero entregado antes queda "sin asignar" hasta la factura

Aplica directo a dos cosas de este proyecto: el **pago a la importadora** y los **aportes de
inversores**.

- El anticipo se registra contra la contraparte y opcionalmente contra la orden; *"so it
  remains traceable and can be allocated when the invoice is created"*
  ([ERPNext](https://docs.frappe.io/erpnext/advance-payment-entry)).
- Se puede repartir en varias facturas: *"One advance can be used across eligible invoices.
  Allocate part of the available advance to each invoice. ERPNext keeps the unused balance
  available until it is allocated or refunded"* (ibid).
- Si la factura final es menor que el anticipo: *"Allocate only the invoiced amount. The
  remainder stays as supplier credit until it is applied to another invoice or refunded"*
  ([ERPNext](https://docs.frappe.io/erpnext/reconcile-advance-payment-made-to-the-supplier)).
- Hay dos escuelas: factura de anticipo ligada a la OC, o asiento de anticipo con
  conciliación posterior ([Dynamics 365](https://learn.microsoft.com/en-us/dynamics365/finance/accounts-payable/prepayments-invoices-vs-prepayments)).
  La primera da trazabilidad por compra; la segunda, flexibilidad.

→ Modelo recomendado para "inversor X puso X USD en esta compra": **anticipo/asignación con
monto no asignado**, ni gasto ni capital social. Ver decisiones en `PLAN.md`.

## 6. Multimoneda: se guardan tres cosas, no una

El registro correcto por documento guarda **monto en moneda extranjera + tasa + equivalente
en moneda funcional**, y la diferencia de cambio se registra aparte:

- *"The ERP entry should store: Foreign currency amount and currency code; Exchange rate and
  source; Functional currency equivalent at recognition; Bank clearing differences on
  payment"* ([InvoiceQuickly](https://invoicequickly.com/guides/multi-currency-invoicing-guide)).
- *"When payment arrives at a different rate, book the realized gain or loss separately"*
  (ibid).
- La tasa de referencia aceptada para impuestos es la vigente **cuando se recibe, se paga o
  se causa** el hecho, no la del día del contrato
  ([IRS](https://www.irs.gov/individuals/international-taxpayers/foreign-currency-and-currency-exchange-rates)
  vía [InvoiceQuickly](https://invoicequickly.com/guides/multi-currency-invoicing-guide)).

→ Consecuencia de diseño: la compra debe arrastrar la tasa congelada y **cada pago debe
traer la suya**, con la diferencia registrada. No una tasa global mutable.

## 7. Qué de esto ya existe en VentiQ y qué no

| Concepto de industria | Estado en VentiQ | Evidencia |
|---|---|---|
| Orden de compra como entidad | **No existe** | solo hay recepción con `motivo`/`observaciones_compra` |
| Reserva (encumbrance) sin mover dinero | **No existe** — se debita al crear | `fondo_inversion_schema.sql:1317` `extraccion_inversion` |
| Recepción parcial acumulada | **Parcial** — `monto_recibido_ref` + estados `pendiente/parcial/completado` | `fondo_inversion_schema.sql:263` |
| Three-way match | **No existe** | no hay factura vs recepción vs OC |
| Landed cost capitalizado | **No existe** como tal | costos adicionales existen, ver `PLAN_COSTOS_ADICIONALES.md` |
| Anticipo con monto sin asignar | **No existe** | el aporte de inversor es `%` de ganancia, no monto |
| Multimoneda con tasa por pago | **Parcial** — `fdi_dat_inversion_fuente` sí guarda `moneda`+`tasa_a_ref` | `fondo_inversion_schema.sql:284` |
| GR/IR | **No existe** | — |

## 8. Fuentes

- Three-way match y entregas parciales — [Procure Utility](https://procureutility.com/blog/three-way-matching-po-receipt-invoice)
- GR/IR, asientos del ciclo P2P, tolerancias — [Cleverence](https://www.cleverence.com/articles/for-business/purchase-order-accounting-entry-4827/)
- Encumbrance: PO reserva, recepción reversa, cancelación libera — [CPA Study Notes](https://getoncourse.ai/lessons/cpa/state-and-local-governments/budgetary-accounting-and-encumbrances/encumbrance-accounting-in-governmental-funds/)
- Regla operativa de reserva y liquidación — [Beancount](https://beancount.io/blog/2026/10/21/encumbrance-accounting-purchase-orders-reserve-budget-guide)
- Reparto de landed cost por valor/peso/cantidad — [Landed Cost Dashboard](https://github.com/MattNeill1/landed-cost-dashboard)
- Compra única con recepciones parciales y flete por envío — [mashreq-supply-chain](https://github.com/amirnsamimi/mashreq-supply-chain-management-system)
- Anticipos, monto sin asignar, remanente — [ERPNext Advance Payment](https://docs.frappe.io/erpnext/advance-payment-entry) · [Reconcile advance](https://docs.frappe.io/erpnext/reconcile-advance-payment-made-to-the-supplier)
- Anticipo vs factura de anticipo — [Dynamics 365](https://learn.microsoft.com/en-us/dynamics365/finance/accounts-payable/prepayments-invoices-vs-prepayments)
- Multimoneda: tres campos y diferencia de cambio — [InvoiceQuickly](https://invoicequickly.com/guides/multi-currency-invoicing-guide) · [IRS](https://www.irs.gov/individuals/international-taxpayers/foreign-currency-and-currency-exchange-rates)

> Nota de honestidad: estas fuentes describen práctica estándar, no certifican que SAP o
> NetSuite implementen exactamente así cada detalle. Lo que sí está verificado es el
> concepto: **compromiso ≠ pago**, **recepción ≠ factura**, y **el costo real se reparte y
> se capitaliza**.