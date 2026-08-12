# Publicaciones problema + UI

Copy listo para Facebook / WhatsApp. Cada post indica **qué pantalla capturar** para armar la imagen de referencia.

**CTA:** inventtia.com · WhatsApp +53 63464544  
**Regla:** 1 problema = 1 imagen. El titular habla del dolor; la captura muestra la pantalla que lo resuelve (no logo genérico ni collage).

---

## Guía rápida de captura

| Tema | Qué hacer |
|------|-----------|
| Formato | 1080×1350 (FB feed) o 1080×1080. Stories 1080×1920 con UI en la mitad inferior. |
| Datos | Tienda demo: nombres genéricos, montos creíbles, sin clientes reales ni teléfonos. |
| UI | Ocupa 50–70% del frame. Margen para el titular del problema (no tape botones clave). |
| Marca | Esquina: Inventtia Caja / Gestión / GoReservas / Muévete. CTA abajo: inventtia.com |
| Estilo | Foto real del dispositivo o mockup simple. Evitar collages de muchas pantallas. |

---

## Mapa rápido: problema → pantalla

| ID | App | Problema | Pantalla a mostrar |
|----|-----|----------|-------------------|
| C1 | Caja | No sabes cuánto debería haber en caja al final del día | Cierre de turno |
| C2 | Caja | Se va la luz o el internet y se paran las ventas | Offline + catálogo |
| C3 | Caja | Cobrar con varios métodos de pago es un lío | Checkout / cobro |
| C4 | Caja | Las órdenes se pierden entre mostrador y cocina/almacén | Lista de órdenes |
| C5 | Caja | Vender rápido se vuelve lento si buscas productos a ciegas | Catálogo por categorías |
| C6 | Caja | No hay control de quién abrió la caja ni con cuánto | Apertura de caja |
| G1 | Gestión | No sabes qué se vende ni qué ganas de verdad | Dashboard ejecutivo |
| G2 | Gestión | El inventario vive en la cabeza de alguien | Inventario / stock |
| G3 | Gestión | Cambiar precios es un caos entre papel, WhatsApp y la caja | Gestión de precios |
| G4 | Gestión | Sin trazabilidad de quién movió la mercancía | Operaciones de inventario |
| G5 | Gestión | Las ventas del día se quedan en el TPV sin análisis | Monitoreo de ventas |
| G6 | Gestión | El dinero se mezcla con gastos sin control | Sistema financiero |
| R1 | GoReservas | Agenda en papel → doble reserva | Reserva / panel del día |
| M1 | Muévete | Pedir viaje es incierto (precio, espera, confianza) | Mapa solicitud de viaje |

---

## Orden sugerido de la semana (negocios)

| Día | Post | Tema |
|-----|------|------|
| Lun | C1 | Cierre de caja |
| Mar | G2 | Inventario |
| Mié | C2 | Offline |
| Jue | G3 | Precios |
| Vie | C3 | Cobro |
| Sáb | G1 | Dashboard |
| Dom | Duo | Caja + Gestión (checkout + dashboard en split): “cobra en Caja, controla en Gestión” |

---

## Inventtia Caja (ventiq_app)

En la imagen debe leerse **Inventtia Caja**.

### C1 — Caja que no cuadra

**Problema:** No sabes cuánto debería haber en caja al final del día.

**Gancho:** Si al cerrar el día “calculas de memoria”, ya perdiste dinero.

**Cuerpo:** Muchos negocios cobran todo el día… y al final no saben si faltó efectivo, sobró, o alguien se equivocó. Inventtia Caja abre turno, registra cobros y cierra con totales claros: efectivo, transferencia y egresos.

**CTA:** Prueba Inventtia Caja → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Cierre de turno (totales del día) |
| **Archivo** | `cierre_screen.dart` |
| **Cómo capturar** | Turno real o demo: totales de efectivo/transferencia visibles, sin datos personales. |
| **Composición** | Izquierda: texto del problema. Derecha: screenshot de cierre (~60%). Overlay: “¿Cuadra tu caja hoy?” |

---

### C2 — Sin internet

**Problema:** Se va la luz o el internet y se paran las ventas.

**Gancho:** Tu cliente no espera a que vuelva el WiFi.

**Cuerpo:** Cuando se cae la conexión, el cuaderno vuelve… y después nadie reconcilia bien. Inventtia Caja sigue vendiendo offline y sincroniza cuando vuelve la red.

**CTA:** Sigue cobrando aunque falle internet → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Indicador / datos offline + catálogo o preorden |
| **Archivo** | `offline_data_viewer_screen.dart` + `categories_screen.dart` |
| **Cómo capturar** | Estado “sin conexión” o visor offline junto al catálogo listo para vender. |
| **Composición** | Screenshot del POS con badge offline. Overlay: “Sin internet ≠ sin ventas”. |

---

### C3 — Métodos de pago

**Problema:** Cobrar con varios métodos de pago es un lío.

**Gancho:** Efectivo + transferencia + “pásame por Zelle”… y el cuaderno no aguanta.

**Cuerpo:** En el mostrador el problema no es vender: es registrar bien cómo te pagaron. Inventtia Caja cierra la orden con el método correcto y deja el historial limpio.

**CTA:** Cobra ordenado → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Checkout / finalizar cobro |
| **Archivo** | `checkout_screen.dart` |
| **Cómo capturar** | Métodos de pago visibles (efectivo/transferencia). UI de selección clara. |
| **Composición** | Close-up del checkout. Texto: “Un cobro. Varios métodos. Cero confusión.” |

---

### C4 — Órdenes perdidas

**Problema:** Las órdenes se pierden entre el mostrador y la cocina/almacén.

**Gancho:** “¿Esa orden ya salió?” no debería ser una pelea diaria.

**Cuerpo:** Pedidos a medias, tickets perdidos y “yo pensé que ya se cobró”. Inventtia Caja concentra preórdenes y órdenes en un solo flujo: tomar, cobrar, consultar.

**CTA:** Ordena tu mostrador → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Lista de órdenes (con estados) |
| **Archivo** | `orders_screen.dart` |
| **Cómo capturar** | 4–6 órdenes demo en distintos estados. Productos genéricos. |
| **Composición** | Screenshot a pantalla completa de Órdenes. Badge: “Inventtia Caja”. |

---

### C5 — Catálogo lento

**Problema:** Vender rápido se vuelve lento si buscas productos a ciegas.

**Gancho:** Si tardas 40 segundos en encontrar un producto, la cola se alarga.

**Cuerpo:** El POS tiene que ser más rápido que el papel. Inventtia Caja organiza el catálogo por categorías para armar y cobrar sin fricción.

**CTA:** Vende más rápido → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Catálogo por categorías |
| **Archivo** | `categories_screen.dart` (móvil) o `categories_web_screen.dart` (web) |
| **Cómo capturar** | Grid de categorías con íconos/colores. Preferible tablet/web. |
| **Composición** | UI de categorías + tip: “Del tap al cobro”. |

---

### C6 — Apertura sin control

**Problema:** No hay control de quién abrió la caja ni con cuánto.

**Gancho:** Sin apertura de turno, cualquier diferencia es “misterio”.

**Cuerpo:** Empezar el día sin registrar fondo de caja es invitar al descuadre. Inventtia Caja abre turno con efectivo inicial y responsables claros.

**CTA:** Abre tu turno bien → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Crear apertura de caja |
| **Archivo** | `apertura_screen.dart` |
| **Cómo capturar** | Formulario de apertura con monto inicial visible. Ideal con trabajadores de turno. |
| **Composición** | Screenshot de apertura. Texto: “El control empieza al abrir.” |

---

## Inventtia Gestión (ventiq_admin_app)

Preferible captura **web/desktop** para dashboard y tablas. En la imagen: **Inventtia Gestión**.

### G1 — Sin números reales

**Problema:** No sabes qué se vende ni qué ganas de verdad.

**Gancho:** Vender mucho no significa ganar. Sin números, solo intuición.

**Cuerpo:** Dueños que “sienten” que el mes fue bueno… hasta que faltan pagos. Inventtia Gestión te muestra ventas y panorama del negocio para decidir con datos.

**CTA:** Mira tu negocio completo → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Dashboard ejecutivo |
| **Archivo** | `dashboard_web_screen.dart` |
| **Cómo capturar** | KPIs con datos demo realistas (no ceros). |
| **Composición** | Screenshot web 16:9. Overlay: “Deja de adivinar. Empieza a ver.” |

---

### G2 — Inventario invisible

**Problema:** El inventario vive en la cabeza de alguien.

**Gancho:** Si solo una persona “sabe qué hay”, tu negocio depende de esa persona.

**Cuerpo:** Faltantes, sobrestock y compras a ciegas cuestan caro. Inventtia Gestión centraliza stock, movimientos y salud del almacén.

**CTA:** Controla tu inventario → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Inventario / stock |
| **Archivo** | `inventory_screen.dart` |
| **Cómo capturar** | Lista con cantidades y alertas de bajo stock. |
| **Composición** | UI de inventario. Texto: “Stock visible = compras inteligentes.” |

---

### G3 — Precios desalineados

**Problema:** Cambiar precios es un caos entre papel, WhatsApp y la caja.

**Gancho:** Subiste el precio… pero la caja sigue cobrando el de ayer.

**Cuerpo:** Precios desactualizados = margen perdido o clientes molestos. Inventtia Gestión actualiza costo y precio de venta para que Caja cobre lo correcto.

**CTA:** Alinea precios y caja → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Gestión de precios |
| **Archivo** | `precios_productos_screen.dart` (o `tpv_prices_screen.dart`) |
| **Cómo capturar** | Tabla/lista con precio de venta editable. |
| **Composición** | Screenshot de precios + flecha “Gestión → Caja”. |

---

### G4 — Sin trazabilidad

**Problema:** No hay trazabilidad: “¿quién movió esa mercancía?”

**Gancho:** Sin historial de movimientos, el faltante no tiene culpable ni causa.

**Cuerpo:** Entradas, salidas y transferencias sin registro se vuelven pelea. Inventtia Gestión deja el rastro de operaciones de inventario.

**CTA:** Audita tu almacén → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Operaciones de inventario |
| **Archivo** | `inventory_operations_screen.dart` |
| **Cómo capturar** | Lista de operaciones (recepción/transferencia/salida) con fechas y estados. |
| **Composición** | UI de operaciones. Texto: “Cada movimiento, registrado.” |

---

### G5 — Ventas sin análisis

**Problema:** Las ventas del día se quedan en el TPV y nadie las analiza.

**Gancho:** La caja cobró. ¿Y el dueño qué aprendió?

**Cuerpo:** Sin monitoreo, no sabes qué TPV vende, qué horario peina o qué se frena. Inventtia Gestión concentra el seguimiento de ventas.

**CTA:** Analiza tus ventas → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Monitoreo de ventas |
| **Archivo** | `sales_screen.dart` |
| **Cómo capturar** | Filtros de período/TPV y listado o resumen visible. |
| **Composición** | Screenshot de ventas. Texto: “Lo que se cobra en Caja, se entiende en Gestión.” |

---

### G6 — Finanzas mezcladas

**Problema:** El dinero del negocio se mezcla con gastos sin control.

**Gancho:** Si no separas finanzas, “hubo venta” no te salva a fin de mes.

**Cuerpo:** Gastos, costos y resultados necesitan un lugar. Inventtia Gestión te da el módulo financiero para ver el dinero con orden.

**CTA:** Ordena tus finanzas → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Sistema financiero |
| **Archivo** | `financial_screen.dart` |
| **Cómo capturar** | Resumen financiero claro. Sin datos bancarios reales. |
| **Composición** | UI financiera. Texto: “Ventas ≠ utilidad. Aquí se ve la diferencia.” |

---

## Refuerzo: GoReservas y Muévete

### R1 — GoReservas (inventtia_flow)

**Problema:** La agenda en papel genera doble reserva y clientes enojados.

**Gancho:** Dos personas reservaron el mismo cupo. Tú pierdes la cara.

**Cuerpo:** Clínicas, salones y talleres pierden dinero por choques de horario. Inventtia GoReservas reserva cupos con capacidad real.

**CTA:** Agenda sin choques → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Reserva de servicio / panel del día |
| **Archivo** | Reserva sheet / planificación o reservas del día |
| **Cómo capturar** | Día con turnos ocupados/libres, realista. |
| **Composición** | UI de agenda. Texto: “Cupos claros. Cero doble reserva.” |

---

### M1 — Muévete (inventtia_muevete)

**Problema:** Pedir un viaje es incierto: precio, espera y confianza.

**Gancho:** Necesitas moverte ahora… sin pelear tarifas a ciegas.

**Cuerpo:** Inventtia Muévete conecta pasajero y conductor desde el mapa: origen, destino y oferta clara.

**CTA:** Pide o conduce → inventtia.com · WhatsApp +53 63464544

| Campo | Valor |
|-------|--------|
| **Pantalla** | Mapa de solicitud de viaje (pasajero) |
| **Archivo** | Pantalla de request / mapa |
| **Cómo capturar** | Mapa con origen-destino y precio/oferta. Sin datos personales reales. |
| **Composición** | Mapa fullscreen. Texto: “Del punto A al B, con claridad.” |

---

## Relacionado

- Plan general de nombres, calendario y plantillas WA: [`plan-publicaciones-inventtia.md`](./plan-publicaciones-inventtia.md)
