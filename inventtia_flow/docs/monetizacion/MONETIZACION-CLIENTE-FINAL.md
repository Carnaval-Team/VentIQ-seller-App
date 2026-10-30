# Cómo monetizar GoReserva (`inventtia_flow`) cobrando también al cliente final

**Fecha:** 29-10-2026 · **Ámbito:** app `inventtia_flow/` ("GoReserva": turnos, colas y reservas de servicios), schema `flow` de Supabase, panel `ventiq_superadmin` en su parte Flow.

**Decisiones de partida asumidas** (las indicó el dueño del producto):
mercado de clientes finales = **Cuba + diáspora**; titular para cobrar = **solo entidad/negocio en Cuba** (MIPYME/CNA/TCP); distribución = **APK directo / web** (no tiendas de apps).

**Cómo leer este documento.** Las afirmaciones sobre el código y la base de datos llevan `ruta:línea` y están verificadas (inventario en el [Anexo 1](anexo-01-inventario-cobros.md)). Los **precios y porcentajes son propuestas comerciales mías**, no datos existentes. Las comisiones de las pasarelas cubanas **no están publicadas**: van marcadas y hay un checklist al final ([Anexo 2](anexo-02-pasarelas.md)).

---

## 0. Respuesta corta

1. **El cobro al cliente final ya existe, pero el dinero no llega a la plataforma.** La migración 62 creó el "pago por adelantado del servicio": el cliente paga con el **Transfermóvil del propio negocio** y el admin lo verifica a mano (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52-107`, activo en 2 entidades, 10 intentos reales: 4 verificados). La plataforma no toca ese dinero.
2. **La línea de ingreso principal sigue siendo B2B, y está mal tarifada:** los planes de suscripción valen hoy **1, 2 y 3 CUP** (30/90/365 días) con `modo_prueba = true` en la BD de release. Eso es un placeholder, no un precio. Arreglarlo es el cambio con mejor retorno de todo este documento.
3. Para cobrar **al cliente** hay tres vías que sí suman y no chocan con lo construido:
   - **A. Cargo de servicio GoReserva** (booking fee) cobrado a la **cuenta de la plataforma**, en un intento **separado** del del negocio. Es el único modo limpio: si sumas el fee al intento actual, ese dinero entra en el bolsillo del negocio.
   - **B. Garantía anti-no-show** (depósito/compromiso por reservar): se cobra al cliente y es lo que el negocio está dispuesto a defender porque le reduce las ausencias.
   - **C. Premium del consumidor + packs regalo de la diáspora en USD/EUR**: aquí está el dinero de verdad del lado B2C. En CUP los fees son céntimos de dólar (hoy 1 USD = **845 CUP**), así que el B2C solo compensa en volumen o en divisa.
4. **Rails recomendados.** Cuba: seguir con Transfermóvil y **subir a "Pago en Línea por QR / tienda virtual" de Bulevar MiTransfer** (es lo único que puede quitar la verificación manual), más **Enzona** como segundo rail (única API de comercio cubana pública). Diáspora: **TropiPay** (API v3 + webhooks) y **USDT TRC20 vía NOWPayments** (1 % publicado). **Descartar Stripe, PayPal y MercadoPago** con titular cubano: Cuba no está en sus países soportados y todo cae bajo OFAC (programa Cuba, 31 CFR Part 515). Todo lo que sea en divisa exige **entidad y banco fuera de Cuba**: es una decisión estructural, no una integración.
5. **Tiendas de apps (por si algún día publicas).** El fee de reserva y el prepago son **servicio del mundo real: exentos de IAP** (Apple 3.1.3(e) obliga a usar otro método; Google Play prohíbe Play Billing para servicios físicos). El **Premium del consumidor es digital**: si se vende **dentro** del binario, exige IAP (15-30 %). Con APK/web no aplica; el día que publiques, vende el Premium **en la web** y deja la app en modo "consumo".
6. **Expectativa realista.** El fee en CUP no financia el producto por sí solo (con 100 entidades y 20 reservas/mes son ~70 USD/mes). Lo que sí hace es cambiar el comportamiento (menos ausencias, más reservas online, más datos) y sostener el precio del B2B. El crecimiento de ingreso viene de **subir el precio de la suscripción** y de **cobrar en divisa a la diáspora**.

---

## 1. Diagnóstico: dónde está el dinero hoy

| Quién paga | Por qué concepto | A quién le paga | Rail | Cuánto |
|---|---|---|---|---|
| **Entidad** (negocio) | Días de acceso a la plataforma (`flow.suscripcion`) | **Plataforma** | Deep link Transfermóvil + verificación manual del superadmin | **1 / 2 / 3 CUP** por 30/90/365 días (placeholder, `modo_prueba=true`) |
| **Cliente final** | Pago por adelantado de la reserva (opcional, posterior a reservar) | **Al negocio** (su `transfermovil_numero_proveedor`) | Deep link Transfermóvil + verificación manual del admin | El total de la reserva (`agenda.precio_total`) |
| **Negocio** | Publicidad/patrocinio en el Home | Plataforma | **No existe**: es gratis y lo carga el superadmin a mano | 0 |

Evidencia: `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:128-424`; `inventtia_flow/docs/flow_schema/migraciones/45_suscripciones_pagos.sql:166,282,609`; `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:52,151,354`; `inventtia_flow/docs/flow_schema/migraciones/28_patrocinados.sql:54-92`. El panel del superadmin para suscripciones vive en `ventiq_superadmin/lib/screens/flow_suscripciones_screen.dart` y `ventiq_superadmin/lib/services/suscripcion_admin_service.dart`.

**Los cinco huecos que impiden cobrar al cliente** (todos verificados):

1. **No hay concepto "plataforma" en el flujo de pago.** `flow.reserva_pago` es por reserva y por entidad; no hay tabla de ingresos de la plataforma ni de liquidaciones (`01-inventario`, §4.5).
2. **No hay segundo rail.** Todo cuelga de un deep link sin callback: la única prueba de pago es una persona mirando el banco (`inventtia_flow/lib/services/cobro_service.dart:48-53`).
3. **No hay cron de expiración de pagos de reserva.** `flow.reserva_pago_expirar()` solo corre cuando el admin abre la bandeja (`inventtia_flow/lib/screens/admin/pagos_reserva_screen.dart:58-69`); en `cron.job` solo está el de suscripciones.
4. **Idempotencia asimétrica.** `suscripcion_transaccion.codigo_confirmacion` es UNIQUE; el de `reserva_pago` es **opcional y no único** (`inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql:93`). Cualquier cobro nuevo necesita su propia clave de idempotencia.
5. **Los activos comercializables no tienen negocio detrás.** Patrocinados, colecciones, fidelidad y dashboard existen pero no tienen precio, cupos, métricas ni contrato (`28_patrocinados.sql`, `30_colecciones.sql`, `31_fidelidad.sql`, `41_rpc_admin_dashboard_modo_y_horas.sql`; el dashboard devuelve conteos, **no importes**).

---

## 2. Catálogo de líneas de ingreso

| # | Línea | Quién paga | Precio propuesto (propuesta, no dato) | Rail | Dónde se engancha | Esfuerzo | Riesgo principal |
|---|---|---|---|---|---|---|---|
| L1 | **Precios reales de suscripción** | Negocio | 800 / 2.000 / 5.000 CUP-mes por tramos | Ya existe | `flow.suscripcion_plan` (panel superadmin) | **Muy bajo** | Perder clientes si se sube sin dar valor visible |
| L2 | **Cargo de servicio al cliente** (booking fee) | Cliente final | 5 % del servicio, mín. 20, máx. 150 CUP (o 0,25-0,99 USD diáspora) | Cuenta de la **plataforma** | Nuevo intento enlazado a `id_agenda` | Medio | Fricción y abandono en la reserva |
| L3 | **Garantía anti-no-show** | Cliente final | 10 % del servicio, mín. 100 CUP | Cuenta de la **plataforma** | `flow.cobro_config` + estados nuevos | Medio-alto | Es dinero de terceros: política de devolución obligatoria |
| L4 | **GoReserva Plus** (premium del consumidor) | Cliente final (o su familia) | 500 CUP/mes · 2,99 USD/mes diáspora | Plataforma | `flow.cliente_premium` + provider propio | Medio | Valor percibido; recurrente manual en Cuba |
| L5 | **Saldo/packs y regalo desde el exterior** | Cliente/diáspora | Packs de 5 / 10 / 20 USD | TropiPay / USDT | `flow.cliente_saldo` + webhook | Alto | Exige entidad/banco fuera de Cuba |
| L6 | **Publicidad y posicionamiento** | Negocio | Slot Home 3.000 CUP/semana · colección 2.500 CUP/mes · campaña WA 1.500 CUP/1.000 envíos | Ya existe el rail del negocio | `flow.campana`, `flow.coleccion` (+ métricas) | Bajo-medio | Vender ranking de reseñas sin etiquetar = engaño al usuario |
| L7 | **Comisión por reserva atendida** (take rate) | Negocio | 50-100 CUP por cliente **nuevo** atendido, o 3 % del ticket | Cuenta por cobrar, se factura con la suscripción | `staff_marcar_estado_agenda` → `Completado` | Medio | Requiere atribución y conciliación por reserva |

Orden de prioridad recomendado: **L1 → L2 → L6 → L3 → L7 → L4 → L5.**

### L1. Precios reales de la suscripción (el arreglo más rentable, hoy no hecho)

Los planes estaban en la BD con **1, 2 y 3 CUP** y `modo_prueba = true`: el circuito funcionaba, pero no facturaba. **Esta línea ya está implementada** (ver [PLANES-Y-LIMITES.md](PLANES-Y-LIMITES.md)) con cuatro planes en USD y límites reales que el servidor aplica al crear locales, servicios y usuarios:

| Plan | Precio/mes | Límites | Gancho comercial |
|---|---|---|---|
| Inicio (`starter`) | 20 USD | 1 entidad, 2 locales, 5 servicios por local, 3 usuarios | Entrar sin riesgo |
| Plus (`plus`) | 30 USD | 1 entidad, 3 locales, 10 servicios por local, 8 usuarios | El tramo que debería ser el 70 % de la base; lleva la cinta "Más popular" |
| Profesional (`professional`) | 50 USD | 2 entidades, 5 locales, 10 servicios por local, 15 usuarios | Multi-local y clínicas |
| Empresarial (`enterprise`) | a convenir | Sin límites: se negocia con ventas | El "Contactar con ventas" que pide el negocio grande |

Además, el superadmin puede crear un **plan privado** para un cliente concreto: solo esa entidad lo ve y lo puede pagar. Reglas de acompañamiento: anual con 2 meses gratis (crear el plan anual desde el panel), gracia de 7 días (ya configurada), y **el cargo de servicio al cliente (L2) no cobra a los tramos Profesional y Empresarial** — así el negocio tiene un motivo económico para subir de tramo en lugar de sentir que le añades un peaje.

### L2. Cargo de servicio GoReserva (cobrar al cliente por reservar en línea)

**Mecánica.** Cuando el cliente confirma una reserva, paga un cargo pequeño **a la plataforma** para "confirmar y garantizar" el turno: incluye recordatorio, derecho a cancelar sin penalización dentro de X horas y prioridad si llega tarde. El servicio se sigue pagando al negocio como hoy (en el local o por prepago al Transfermóvil del negocio).

**Por qué así y no sumado al pago del negocio.** El intento actual de prepago paga al **número de proveedor del negocio** (`62_pago_adelantado_servicio.sql:56-57,437-451`). Si le sumas un fee, ese fee acaba en la cuenta del negocio y la plataforma tendría que facturarlo después: dinero cobrado mal y reclamación garantizada. El fee debe ser un **intento separado, con el número de proveedor de la plataforma** (el que ya está en `flow.suscripcion_config.transfermovil_numero_proveedor`), enlazado a `id_agenda`.

**Precio.** 5 % del precio de la reserva, mínimo 20 CUP y máximo 150 CUP (o 0,25-0,99 USD cuando paga la diáspora). Alternativa sin fricción y muy recomendable para el arranque: **fee cero en la primera reserva de cada mes** y fee solo a partir de la segunda; o **fee cero siempre, y el cargo es la vía de entrada al Plus** (L4). Nunca bloquees la reserva por el fee: la reserva nace gratis y el cargo es un paso posterior, igual que hoy.

**Dónde se engancha** (sin tocar el flujo del negocio): nuevo RPC `cliente_crear_cargo_reserva(p_id_agenda)` llamado desde la hoja de pago que ya existe (`inventtia_flow/lib/widgets/pago_adelantado_sheet.dart:34-411`, servicio `inventtia_flow/lib/services/cobro_service.dart:25-294`). El id de la agenda está disponible: `agenda_service.dart` descarta el `data.id_agenda` que devuelve el RPC (`inventtia_flow/lib/services/agenda_service.dart:164-167`) y hoy se resuelve con una consulta extra (`cobro_service.dart:217-243`); conviene arreglar ese wrapper.

**Riesgo.** En Cuba, "pagar por usar una app" es culturalmente duro. Mitigación: importe bajo, contrapartida visible (recordatorio + cancelación flexible + garantía), y que **el negocio lo explique** (a él le interesa: menos ausencias y el tramo de suscripción incluye exención).

### L3. Garantía anti-no-show (la línea que más le sirve al negocio)

**Mecánica.** El cliente deja una garantía (10 % del servicio, mínimo 100 CUP) para reservar un turno con demanda. Si asiste, la garantía se convierte en **saldo GoReserva** (o descuento acordado con el negocio). Si no asiste, se reparte: 50 % al negocio como compensación, 50 % a la plataforma por el coste del hueco. El negocio lo adopta porque **el no-show es su problema económico real**, y es la excusa perfecta para que el cliente pague a la plataforma sin sentirlo como un peaje.

**Dónde se engancha.** `flow.cobro_config` ya tiene activo por entidad, moneda, plazo y `cancelar_si_expira` (`62_pago_adelantado_servicio.sql:52-76`); hay que añadir `porcentaje_garantia`, `minimo_garantia`, `politica_no_show` y `devuelve_saldo`. Estados nuevos en `reserva_pago.estado` y en `agenda.pago_estado` (`garantia_retenida`, `garantia_devuelta`, `reembolsado`): hoy el CHECK no admite ni `anulado` y el trigger lo mapea a `expirado` (`68_anular_pago_al_cancelar.sql:73-88`). La resolución de la garantía se dispara al pasar la reserva a `Completado` o a no-show en `flow.staff_marcar_estado_agenda` (`61_cancelacion_motivo_y_notificacion.sql:100`).

**Riesgo (el más serio de todo el documento).** La plataforma retendría dinero de terceros con obligación de devolución: eso es un pasivo, no un ingreso, y sin personalidad jurídica adecuada ni política escrita es un problema. Recomendación: empezar por la variante **"compromiso no reembolsable de confirmación"** con crédito como gesto comercial (en lugar de "depósito reembolsable"), y **cerrar la política por escrito antes de cobrar el primer peso**. Alternativa aún más conservadora: que la garantía se cobre al **negocio** como módulo del plan (B2B) y que el cliente solo vea el compromiso.

### L4. GoReserva Plus (premium del consumidor)

**Qué vende:** cargo de servicio exento, prioridad en cola, reserva con hasta 7 días de antelación, cancelación flexible, reserva para terceros sin coste, descuento adicional en negocios asociados y sin publicidad. **Precio:** 500 CUP/mes o 2,99 USD/mes (la diáspora lo regala: 4,99 USD/mes).

**Dónde se engancha.** No se puede reutilizar `flow.suscripcion`: su clave es `id_entidad NOT NULL` con FK a `flow.entidad` y su autorización es `_susc_caller_ve_entidad` (`43_suscripciones_tablas.sql:103-121,245-249`). Hace falta un módulo gemelo por `uuid_usuario`: `flow.cliente_premium` (+ intents/transacciones/movimientos) y un provider propio en Flutter (hoy `SuscripcionProvider` es de entidad y vive en el shell del admin: `inventtia_flow/lib/providers/suscripcion_provider.dart:16-18`, `inventtia_flow/lib/screens/home_shell.dart:670`).

**Gates de valor, con nombres concretos:** fee exento → `cliente_cobro_info` (`67_cobro_por_servicio.sql:46`) o `_cobro_disponible` (`69_cobro_disponible_en_agendas.sql:65`); prioridad en cola → `cliente_entrar_sala_espera_reserva` (`38_sala_espera_turno.sql:211`); descuento extra → `cotizar_reserva` (`34_beneficio_bienvenida_precio.sql:158`). **Cuidado con apilar descuentos:** ya hay dos encadenados (promoción → bienvenida) y un tope `greatest(...,0)`; el del Plus debe ir con orden y tope explícitos o el precio caerá a cero (`34_beneficio_bienvenida_precio.sql:474`).

**Recurrente en Cuba = cobro manual asistido.** No hay tokenización posible: se diseña con aviso previo por WhatsApp (el outbox ya existe, `45_suscripciones_pagos.sql:116-157`) y 3 días de gracia. En la diáspora sí puede ser una compra única de 3/6/12 meses.

### L5. Saldo, packs y regalo desde el exterior (la línea en divisa)

**Mecánica.** Tres productos de precio en USD/EUR: (a) **pack regalo** de 5/10/20 USD que un familiar paga desde el exterior y el cliente en Cuba recibe como saldo + reserva garantizada; (b) **recarga de saldo** con bonificación (pagas 500 CUP, recibes 550); (c) **Plus de regalo** por 3/6/12 meses.

**Por qué es la mejor línea B2C:** el que paga es la diáspora, gasta en dólares, y el producto es un regalo, no un peaje. Además el saldo no consumido (breakage) y el diferencial de tasa (el repo ya tiene `flow.tasa_cambio` con USD a 845 CUP y Zelle a 825,19) son margen real.

**Rails:** TropiPay (API v3 con sandbox y webhooks, `https://doc.tropipay.com/es/docs/intro`) y USDT TRC20 vía NOWPayments (1 % publicado, `https://www.nowpayments.io/pricing`); Zelle solo como canal manual de conciliación. **Requiere entidad y banco fuera de Cuba**; sin esa decisión, L5 no existe.

**Diseño mínimo:** `flow.cliente_saldo` + `flow.cliente_saldo_movimiento` (append-only: recarga, consumo, regalo, caducidad, reverso) y una Edge Function de webhook que confirme el pago del PSP contra el intento creado. Regla dura: **el saldo solo paga cosas de la plataforma** (fee, Plus, cursos, prioridad). Si el saldo paga servicios del negocio, vuelves a necesitar liquidación y el problema de pagar a terceros en Cuba — eso es fase 4, no fase 1.

### L6. Publicidad y posicionamiento (dinero rápido con lo ya construido)

`flow.campana` (tarjetas destacadas del Home, con `prioridad`), `flow.coleccion`, `flow.promocion` y el ranking semanal **ya existen** y hoy son gratis: la escritura es solo del superadmin y no hay precio, cupos, métricas ni vencimiento ligado a pago (`28_patrocinados.sql:54-92,116-146`; `30_colecciones.sql:59-77`; `36_ranking_semanal.sql`). Falta el negocio, no la técnica:

- **Slots vendibles** con inventario explícito (posición, categoría, provincia, exclusividad, semanas).
- **Métricas** de impresiones y clics (imprescindible para renovar la venta y para poner precio).
- **Autoservicio de compra** por el negocio, pagado con el rail que ya funciona.
- **Regla de honestidad:** el ranking de reseñas **no se vende** como si fuera calidad; si se destaca algo pagado, se etiqueta como "Patrocinado" (el Home ya tiene el modo `ESPACIO PATROCINADO`, `inventtia_flow/lib/screens/espacio_patrocinado_screen.dart:7-36`).

Precios propuestos: slot Home por categoría 3.000 CUP/semana; colección destacada 2.500 CUP/mes; campaña por WhatsApp 1.500 CUP por 1.000 envíos (las Edge Functions `wapi-*` existen y están desplegadas, pero **no leen el schema `flow`**: hay que cablearlas); inclusión en el tramo Negocio/Pro como gancho de venta.

### L7. Comisión por reserva atendida (alternativa a la suscripción)

Para negocios que se resisten a pagar por adelantado: **gratis publicar, y 50-100 CUP por cliente nuevo que la app le trae y atiende** (o 3 % del ticket), facturado mensualmente con el mismo rail de la suscripción. El ancla correcta es la transición a `Completado` en `flow.staff_marcar_estado_agenda` —no el pago, porque la mayoría de reservas no tienen prepago—, con un asiento por reserva y UNIQUE `(concepto, id_referencia)` para no contar dos veces. Es una **cuenta por cobrar**: un registro contable con recibo, no un cobro automático, salvo que cambies el rail para que la plataforma cobre al cliente y liquide al negocio (fase 4).

Complemento natural: **paquetes de puntos bono** que el negocio compra para regalar a sus clientes (p. ej. 10.000 puntos por 6.000 CUP). La fidelidad ya está construida (`flow.puntos_movimiento`, `fn_saldo_puntos`) pero **no tiene compra ni canje monetario** (`31_fidelidad.sql:107,252`).

---

## 3. Secuencia recomendada

**Fase 0 — Cobrar bien lo que ya cobras (1-2 semanas, sin código de cobro nuevo).**
Poner precios reales L1 y desactivar `modo_prueba`; programar el cron `select flow.reserva_pago_expirar();` cada 10 minutos (hoy no existe); hacer UNIQUE `reserva_pago.codigo_confirmacion`; añadir **importes** al dashboard de entidad (hoy solo conteos) para poder auditar y vender; métricas de patrocinio.
*Métrica de éxito:* ingreso B2B declarado por mes > 0 y conciliación diaria que cuadra.

**Fase 1 — Cargo de servicio al cliente (2-4 semanas).**
`flow.servicio_fee` + `flow.cliente_cargo` + `flow.plataforma_ingreso`, RPC de creación/reporte/verificación y bandeja de conciliación de la plataforma. Arrancar con fee 0 la primera reserva del mes para no matar la adopción.
*Métrica de éxito:* % de reservas con cargo pagado y **tasa de finalización** de la reserva (no debe caer).

**Fase 2 — Garantía anti-no-show (3-4 semanas).**
Ampliar `cobro_config`, estados nuevos, resolución automática al completar/no-show, y **política escrita** publicada en la app.
*Métrica de éxito:* reducción medible de ausencias en los negocios piloto.

**Fase 3 — Plus + saldo + packs USD (4-8 semanas, depende de la entidad en el exterior).**
Módulo `cliente_premium`, wallet, webhook de TropiPay/USDT, y la web de pago (fuera del binario si algún día hay app de tienda).
*Métrica de éxito:* primeras ventas en divisa y recompra mensual.

**Fase 4 — Publicidad empaquetada y take rate (continuo).**
Slots, contratos, métricas, autoservicio; y el modelo de comisión por reserva atendida para negocios que no quieren suscripción.

---

## 4. Pasarelas: qué recomiendo y qué hay que verificar

| Para qué | Rail recomendado | Por qué | Qué falta verificar |
|---|---|---|---|
| Fee/prepago del cliente en Cuba | **Transfermóvil** (ya integrado) → migrar a **Pago en Línea por QR / tienda virtual (Bulevar MiTransfer)** | Es el estándar para MIPYME; la tienda virtual puede dar integración y quitar la verificación manual | **Comisión de comercio (no publicada)** y detalle técnico de la API: pedirlos en la contratación (ETECSA / Joven Club municipal) |
| Segundo rail Cuba | **Enzona (XETID)** | Única plataforma cubana con **API de comercio pública** (`https://api.enzona.net/store/`), bancos Metropolitano/BANDEC/BPA | Comisión de comercio y madurez de la API; ojo: Enzona ya tiene un producto competidor de reservas ("Ticket") |
| Suscripción recurrente del negocio | Transfermóvil/Enzona + avisos y gracia | En Cuba **no hay tokenización**: el recurrente es cobro manual asistido, y hay que diseñarlo como proceso humano | Nada nuevo: el outbox y la gracia ya existen |
| Cliente paga desde el exterior | **TropiPay** (API v3 + webhooks) y **USDT TRC20 (NOWPayments, 1 %)** | Únicos rails viables sin banco cubano; el diáspora paga en divisa | Tarifas de TropiPay (su web no es legible por scraping) y AUP/KYC; cumplimiento AML y contable del cripto |
| Manual de respaldo | **Zelle** (solo conciliación manual) | Sin comisión al consumidor y rápido | Exige cuenta de EE. UU. en ambos extremos y es **irreversible** |
| Venta digital fuera de Cuba | Stripe Billing, o **Paddle / Lemon Squeezy como Merchant of Record** (5 % + 50 ¢) | Cobran impuestos y liquidan | Exige entidad fuera y su AUP puede rechazar exposición Cuba |
| LatAm (si algún día) | MercadoPago (AR/BR/MX/CL/CO/PE/UY), Wompi (CO), Culqi (PE), dLocal (multi-país) | Cobertura local real | Tarifas por país (no comparables públicamente) y entidad local |
| **No usar con titular cubano** | **Stripe** (Cuba no está en `stripe.com/global`), **PayPal** (no opera en Cuba), **MercadoPago** | OFAC (programa Cuba, 31 CFR Part 515): cierran la cuenta y retienen fondos | — |
| Tiendas de apps | IAP solo si se publica y se vende **digital** dentro del binario | Fee de reserva = servicio real, **exento** (Apple 3.1.3(e) / Google Play §4.1); Premium = digital, **IAP obligatorio** | Si Google Play Billing está disponible en Cuba (no verificado) |

**Decisión estructural pendiente (bloquea L5 y todo lo que sea en divisa):** abrir entidad + banco fuera de Cuba (Panamá, España, México, EE. UU.). Es la parte del plan que **requiere abogado**; los detalles y las advertencias están en el [Anexo 2](anexo-02-pasarelas.md), §4. Checklist de datos no verificados: §7 de ese anexo.

---

## 5. Economía honesta (con la tasa real de tu BD)

Tasa del **28-10-2026**, `flow.tasa_cambio` (fuente `directoriocubano`): **1 USD = 845 CUP**, 1 EUR = 930 CUP, 1 MLC = 698,81 CUP, Zelle = 825,19 CUP. Con esa tasa, **1 CUP ≈ 0,00118 USD**: un fee de 50 CUP son **0,06 USD**.

| Escenario | Supuestos | Ingreso mensual estimado |
|---|---|---|
| **A. Base actual, suscripción sin arreglar** | 11 suscripciones a 1-3 CUP + 10 intentos de pago de reserva | Prácticamente **0 USD** (es el estado de prueba) |
| **B. L1 arreglado (100 entidades, tramo medio)** | 100 × 2.000 CUP/mes | **200.000 CUP ≈ 237 USD/mes** |
| **C. L2 cargo de servicio** | 100 entidades × 20 reservas = 2.000 reservas; 40 % con cargo; 75 CUP promedio | **60.000 CUP ≈ 71 USD/mes** |
| **D. L6 publicidad** | 20 negocios × 2.000 CUP/mes | **40.000 CUP ≈ 47 USD/mes** |
| **E. L5 diáspora (USD)** | 300 packs × 8 USD; margen neto ~10 % tras PSP | **≈ 240 USD/mes**, en divisa |

**Lectura:** con el mercado y la tasa actuales, **el fee en CUP no es el motor**: es la palanca que cambia el comportamiento (menos ausencias, más reservas online, más datos) y el argumento para subir el precio del negocio. El motor sigue siendo el **B2B bien tarifado** más **la publicidad**, y el crecimiento en valor viene de **cobrar en divisa a la diáspora**. Cualquier proyección que ignore esto —"cobrar 20 CUP por reserva a 1.000 clientes" = 24 USD/mes— es matemática decorativa.

---

## 6. Diseño técnico propuesto (para cuando decidas implementar)

**Principios.** Un rail, varios beneficiarios; nunca mezclar el dinero del negocio con el de la plataforma en el mismo intento; idempotencia explícita por concepto; libro mayor append-only; RLS en todo; y **degradación elegante** si falta el esquema (`inventtia_flow/lib/utils/esquema_pendiente.dart:21-37`), o la app romperá antes de migrar.

**Tablas nuevas (nombres propuestos, todas en `flow`):**

```sql
-- Concepto de la plataforma: cargo al cliente, garantía, premium, publicidad
flow.servicio_fee            -- por entidad/servicio: tipo (fijo|pct), valor, min, max, moneda,
                             -- exento_con_premium, activo, vigencia
flow.cliente_cargo           -- intento de cobro al cliente A LA PLATAFORMA:
                             -- id_agenda, uuid_usuario, concepto, base, monto, moneda,
                             -- id_transaccion, codigo_confirmacion UNIQUE, url_intent, expira_at, estado
flow.plataforma_ingreso      -- ledger append-only: concepto, id_referencia, id_entidad,
                             -- uuid_usuario, monto, moneda, tasa_cup, estado
flow.cliente_saldo           -- wallet (saldo cacheado)
flow.cliente_saldo_movimiento-- recarga | consumo | regalo | caducidad | reverso (append-only)
flow.cliente_premium         -- uuid_usuario, plan, fecha_inicio/fin, estado, origen (compra|regalo)
flow.publicidad_paquete      -- slot, posición, categoría/provincia, precio, duración
flow.publicidad_contrato     -- entidad, paquete, vigencia, estado, id_pago
flow.publicidad_metrica      -- impresiones, clics (por contrato y día)
```

**Cambios en tablas existentes:** `flow.cobro_config` += `porcentaje_garantia`, `minimo_garantia`, `politica_no_show`, `devuelve_saldo`; CHECK de `flow.agenda.pago_estado` y `flow.reserva_pago.estado` += `garantia_retenida`, `garantia_devuelta`, `reembolsado`; `flow.suscripcion_plan.limites` pasa a usarse de verdad (locales, usuarios, campañas incluidas, exención del cargo).

**RPC nuevos** (mismo contrato `{ok, data|error}` y `security definer` + `set search_path = flow, public` + `auth.uid()` que el resto): `cliente_cotizar_cargo`, `cliente_crear_cargo_reserva`, `cliente_reportar_cargo`, `cliente_mis_cargos`, `admin_verificar_cargo` / `admin_rechazar_cargo` (o bandeja de plataforma si el cobro es al número de la plataforma), `cliente_saldo_movimientos`, `cliente_comprar_premium`, `publicidad_contratar`, `admin_ingresos_resumen`, `premium_expirar`, `cargos_expirar`, `garantia_resolver`.

**Idempotencia y conciliación** (lo que más rompe en producción):
- UNIQUE `(concepto, id_referencia)` en `plataforma_ingreso`: impide cobrar dos veces la misma reserva tras un rechazo o una expiración.
- `codigo_confirmacion` **UNIQUE** en los cargos de plataforma (el error está hoy en `reserva_pago`, donde es opcional y no único).
- Cron: `reserva_pago_expirar()` (falta hoy), `cargos_expirar()`, `premium_expirar()`, y barrido de garantías de reservas que quedaron sin resolver.
- **No confiar en el deep link** como prueba de pago: sigue siendo un "ya pagué" humano hasta que exista tienda virtual/Enzona con callback.
- Conciliación diaria: sumar `plataforma_ingreso` contra el extracto de la cuenta de la plataforma y contra los ingresos verificados por el negocio.

**Puntos de enganche en el código actual** (mínimo cambio, sin reescribir flujos):

| Punto | Archivo |
|---|---|
| Hoja de pago del cliente (añadir el cargo de plataforma) | `inventtia_flow/lib/widgets/pago_adelantado_sheet.dart:34-411` |
| Servicio de cobro del cliente | `inventtia_flow/lib/services/cobro_service.dart:25-294` |
| Bandeja de verificación del negocio | `inventtia_flow/lib/screens/admin/pagos_reserva_screen.dart:10-209` |
| Config de cobro del negocio | `inventtia_flow/lib/screens/admin/cobro_config_screen.dart:8-19` |
| Chip de estado de pago en "Mis reservas" | `inventtia_flow/lib/utils/estado_pago.dart:16-90`, `inventtia_flow/lib/screens/mis_tickets_screen.dart:37-50` |
| Creación de la reserva (recuperar `id_agenda` en el wrapper) | `inventtia_flow/lib/services/agenda_service.dart:129-171` |
| Suscripción y planes (L1) | `inventtia_flow/lib/screens/admin/mi_suscripcion_screen.dart:111-134`; panel en `ventiq_superadmin/lib/screens/flow_planes_screen.dart` |
| Panel global de ingresos (nuevo) | `ventiq_superadmin/lib/screens/flow_*.dart` (junto a `flow_suscripciones_screen.dart`) |

---

## 7. Qué NO hacer

1. **No sumar el fee al intento de pago del negocio**: el dinero acabaría en su cuenta (`62_pago_adelantado_servicio.sql:56-57,437-451`).
2. **No intentar Stripe, PayPal ni MercadoPago con titular cubano**: no abren cuenta, y forzar la operación vía tercero ("straw") es evasión de KYC con fondos congelados como resultado.
3. **No vender el Premium del consumidor dentro del binario** si algún día publicas en tiendas: es contenido digital y exige IAP (Apple 3.1.1 / Google Play §1); Apple además prohíbe usar cripto o wallets para desbloquear funcionalidad.
4. **No cancelar reservas por un fee impago**: rompes el negocio del cliente para cobrar céntimos.
5. **No usar `agenda.pago_monto` como fuente de verdad** del dinero: es denormalizado (`62_pago_adelantado_servicio.sql:141-145`); la base es `reserva_pago.monto` o `agenda.precio_total`.
6. **No vender el ranking de reseñas** como si fuera calidad: destaca y **etiqueta** lo patrocinado.
7. **No montar un wallet que pague servicios del negocio** antes de resolver la liquidación: mientras el saldo solo compre cosas de la plataforma, no hay problema de pagos a terceros.
8. **No dar por buenas las comisiones de Transfermóvil/Enzona**: no están publicadas. Pídelas por escrito antes de fijar el precio del fee.

---

## 8. Quick wins (esta semana)

1. **Subir los precios de los planes** en el panel de superadmin (800 / 2.000 / 5.000 CUP) y **desactivar `modo_prueba`**.
2. **Cron** `select flow.reserva_pago_expirar();` cada 10 minutos (hoy solo barre al abrir la bandeja).
3. **UNIQUE** en `reserva_pago.codigo_confirmacion` (anti doble verificación con el mismo comprobante).
4. **Dashboard con importes**: añadir a `admin_dashboard_entidad` los pagos verificados por día y por servicio (hoy no devuelve dinero, `41_rpc_admin_dashboard_modo_y_horas.sql:155-175`).
5. **Métricas de patrocinio** (impresiones/clics) para poder vender slots con número.
6. **Definir los 3 planes y sus `limites jsonb`** (locales, usuarios, campañas, exención del cargo de servicio).
7. **Contratación**: pedir a ETECSA (Pago en Línea/tienda virtual) y a Enzona comisión, API y requisitos.
8. **Escribir la política de fee y de no-show** (texto visible en la app) **antes** de cobrar el primer peso.

---

## 9. Anexos y fuentes

- **Anexo 1** — [Inventario de cobros actuales y puntos de inserción](anexo-01-inventario-cobros.md) (verificado contra repo + BD de release, 29-10-2026).
- **Anexo 2** — [Pasarelas, políticas de tiendas y sanciones](anexo-02-pasarelas.md) (con URLs citadas y checklist de lo no verificado).
- Documentos vecinos del repo: `inventtia_flow/PLAN_SUSCRIPCIONES.md`, `inventtia_flow/PLAN_PRECIOS_PAGOS_CALENDARIO.md`, `inventtia_flow/docs/flow_schema/BASE_CONOCIMIENTO.md`.

**Advertencia final.** Nada de esto es asesoría legal, fiscal ni contable. Cobrar a clientes finales, retener garantías y operar con la diáspora son decisiones que necesitan revisión profesional de la estructura societaria y del encaje OFAC antes de mover dinero real.
