# 02 — Pasarelas y rails de cobro viables para GoReserva

**Fecha de consulta de todas las fuentes: 2026-10-29** (hora de La Habana). Las comisiones y políticas de estas plataformas cambian con frecuencia: **todo número de este documento debe re-verificarse antes de firmar un contrato o codificar una tarifa**.

**Alcance:** app Flutter `inventtia_flow/` (GoReserva: turnos, colas y reservas de servicios) con backend Supabase; mercado primario Cuba (Transfermóvil, CUP/MLC, soporte WhatsApp +53); escenarios de clientes finales, diáspora y expansión LatAm; distribución vía Google Play / App Store.

**Método de búsqueda (declarado):** `web_search` **falló** en esta instalación (`DeepSeek API error (HTTP 402): Insufficient Balance`). Se usó el respaldo acordado: `web_fetch` contra `https://html.duckduckgo.com/html/?q=...` para descubrir URLs, y `web_fetch` directo (con el proxy de lectura `r.jina.ai` cuando la página oficial es JavaScript-only) para leer las fuentes oficiales. Todas las URLs usadas están en el **Anexo A**.

**Leyenda de confianza usada en todo el documento**

| Marca | Significado |
|---|---|
| ✅ **Verificado** | Leído en la página oficial de la empresa/organismo el 2026-10-29. |
| 🟡 **Estimación** | Dato derivado de fuente oficial indirecta (snippet de buscador sobre la web oficial) o de fuente secundaria razonable. No es cita textual. |
| ⚠️ **Dudoso / no verificado** | No pude confirmarlo en fuente oficial en esta sesión. **No lo uses para decidir sin verificar.** |
| 🔁 **Volátil** | Precio/política que cambia con frecuencia incluso dentro del mismo año. |

> **Aviso:** esto es un informe de analista de pagos, **no asesoría legal ni fiscal**. La parte de sanciones y de estructura societaria debe validarla un abogado con licencia en la jurisdicción elegida.

---

## 0. Resumen ejecutivo (léelo aunque no leas el resto)

1. **El fee por reserva / prepago de una cita presencial (salón, médico, turno) NO es una compra digital.** Apple y Google **eximen** ese cobro de su facturación in-app y **prohíben** usar IAP para él (Apple 3.1.3(e); Google Play Payments policy, sección de servicios físicos). Puedes cobrarlo con Transfermóvil, Enzona, TropiPay, USDT o tarjeta, **dentro del mismo binario**.
2. **El "plan premium del consumidor" (features digitales: prioridad en cola, historial, ad-free) SÍ es contenido/funcionalidad digital** y, si se vende **dentro** del binario iOS/Android, exige IAP (Apple 3.1.1; Google Play §1). La salida limpia es **venderlo en la web** y dejar la app móvil en modo "consumo" sin botón de compra.
3. **Ningún PSP global (Stripe, PayPal, MercadoPago) abre cuenta a una entidad cubana.** Stripe ni siquiera lista Cuba entre sus países soportados. Para cobrar a la diáspora/LatAm hay que operar con una **entidad y banco fuera de Cuba** y con **Merchant of Record** o wallet (TropiPay / Paddle / Lemon Squeezy / dLocal dMoRe), asumiendo cumplimiento OFAC (programa Cuba, 31 CFR Part 515).
4. **Para Cuba puro: Transfermóvil es el rail obligatorio y ya está implementado** (deep link + "Ya he pagado" + verificación manual, `inventtia_flow/CHANGELOG.md`). Su gran debilidad es que **no hay callback**: cada confirmación es trabajo humano. La mejora de mayor ROI es migrar a **Pago en Línea por QR / tienda virtual de Bulevar MiTransfer** (que sí expone integración/API de comercio) antes de añadir más pasarelas.
5. **La diaspora la mueve el cripto y TropiPay, no PayPal.** PayPal no opera en Cuba; Zelle exige cuenta bancaria de EE. UU. en ambos extremos. USDT TRC20 vía NOWPayments (1% publicado) es hoy el rail transfronterizo más simple y barato de integrar, con el coste de cumplimiento AML/tributario.

---

## 1. Punto de partida real del repo (solo lectura)

Contexto para no recomendar cosas que contradigan lo ya construido:

- El circuito vigente es **deep link de Transfermóvil → botón "Ya he pagado" → verificación manual**. Ver `inventtia_flow/CHANGELOG.md:18-25` y `inventtia_flow/PLAN_SUSCRIPCIONES.md:176` ("**A.6 Transfermóvil: NO hay callback. Verificado**").
- Tablas/RPC del circuito: `flow.suscripcion_intent`, `flow.suscripcion_pago` (`inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:299-366`).
- El **pago por adelantado del servicio al cliente final ya existe** como circuito separado, con config por entidad: `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql` (número de proveedor del admin, WhatsApp de verificación, moneda, plazo) y UI en `inventtia_flow/lib/widgets/pago_adelantado_sheet.dart`.
- El manifiesto Android ya declara el esquema `transfermovil` y el host `transfermovil.app`: `inventtia_flow/android/app/src/main/AndroidManifest.xml:51-66`.
- Antecedente del sistema "padre" (Carnaval), citado en `inventtia_flow/PLAN_SUSCRIPCIONES.md:445-447`: tenía `stripe_payment`, `numero_zelle_pagos` y `enlace_pago_tropipay`, y **se decidió dejar solo Transfermóvil en v1** con la columna `metodo` preparada para más rails.

**Conclusión de partida:** el esquema ya está preparado para multi-rail (`metodo`, outbox de notificaciones, estados). Cualquier rail nuevo se añade sin migración estructural grande, pero **todos los que no sean Transfermóvil/Enzona exigen una entidad y un banco fuera de Cuba**.

---

## 2. Tabla comparativa por rail

Las comisiones se dan **solo cuando las verifiqué**; cuando no, se dice explícitamente y se marca ⚠️.

### 2.1 Rails Cuba-first

| Rail | Titular cubano (negocio en Cuba) | Cliente final en Cuba | Monedas | Comisión real (%) | Integración | Liquidación | Riesgo / limitaciones |
|---|---|---|---|---|---|---|---|
| **Transfermóvil — deep link** (lo que ya usas) | ✅ **Sí.** Es el estándar para TCP/MIPYME. `transfermovil://tm_compra_en_linea/...` | ✅ Sí, con la app instalada | CUP (y MLC según cuenta) | ⚠️ **No publicada** en las páginas oficiales que pude leer. No la invento. | **Deep link** (no API). **Sin callback**: la app solo dispara y el negocio verifica a mano | Inmediato al confirmar el negocio; **la "liquidación" real es tu conciliación manual** | 🔴 Verificación manual por transacción = coste operativo y fraude interno. El `id_transaccion` viaja como literal `ESTATICO` (bug de la app), así que la referencia única es tuya, no del banco |
| **Transfermóvil — Bulevar MiTransfer (Pago en Línea por QR / tienda virtual)** | ✅ **Sí.** "todos los comercios o establecimientos, ya sean estatales o privados, así como los trabajadores por cuenta propia pueden contratar este servicio" ([ETECSA](https://www.etecsa.cu/es/node/3207)) | ✅ Sí: escanea QR en el comercio o paga desde la web online | CUP / MLC | ⚠️ **No publicada** en la fuente consultada | **QR + portal web de gestión**; existe modalidad "tienda virtual para el cobro online e integración a la API de Transfermóvil" (reportado por prensa, ver nota) | 🟡 No publicado | Trámite: solicitud online → anexo por correo → credenciales → **implementación presencial en el Joven Club municipal** con capacitación. Lead time humano |
| **Enzona (XETID)** | ✅ **Sí.** Plataforma cubana con bancos Metropolitano, BANDEC y BPA; **API pública** | ✅ Sí | CUP y MLC ("USD") | ⚠️ **No publicada** para comercios. La fuente oficial dice **sin comisión por transferencias** entre usuarios | **API REST** documentada ([api.enzona.net/store](https://api.enzona.net/store/)) + **Bulevar** de tiendas virtuales con **plan de suscripción** ([bulevar.enzona.net/tarifas](https://bulevar.enzona.net/tarifas)) | 🟡 No publicado | Es el único rail cubano con API de comercio real. Riesgo: dependencia de un solo proveedor estatal (XETID), madurez de la API, y que **ya tiene un producto competidor de reservas** ("Ticket") |
| **Tarjetas cubanas MLC / "CLÁSICA"** | — | 🟡 Sirven como **destino de fondeo** (recibir), no como medio de cobro internacional | MLC (USD), CUP | — | No aplica: se usan vía los wallets de arriba | 1–5 días cuando el fondeo viene de TropiPay, según fuente secundaria 🟡 | ⚠️ **No pude verificar en esta sesión** la operativa exacta de la tarjeta "CLÁSICA" ni si permite pago internacional card-not-present. **Dato dudoso.** Trátalo como destino de depósito, no como rail de cobro |

**Nota sobre la API de Transfermóvil (pago en línea):** la existencia de contratación de "Pago en Línea por QR" y de una modalidad de "tienda virtual con integración a la API de Transfermóvil" está confirmada por ETECSA (contratación) y por prensa oficial ([OnCubaNews](https://oncubanews.com/cuba/promueven-en-comercios-estatales-y-privados-contratacion-para-pago-electronico/), [Razones de Cuba](https://razonesdecuba.cu/transfermovil-y-enzona-un-camino-seguro-en-la-bancarizacion/)). **El detalle técnico de esa API (endpoints, webhooks, liquidación, comisión) no está publicado** y hay que pedirlo en la contratación: `atencion.usuarios@etecsa.cu`. 🟡/⚠️

### 2.2 Rails diáspora / internacionales

| Rail | Titular cubano | Cliente final en Cuba | Monedas | Comisión real (%) | Integración | Liquidación | Riesgo / limitaciones |
|---|---|---|---|---|---|---|---|
| **TropiPay** | 🟡 Permite operar desde/hacia Cuba en la práctica; es fintech europea PSD2, **no un banco cubano** | 🟡 El cliente cubano suele **recibir** saldo/depósito a tarjeta cubana, no pagar con su tarjeta | Multidivisa (USD/EUR/…), 130+ países (claim del proveedor) | ⚠️ **No pude leer la tabla de tarifas**: su centro de ayuda es JavaScript-only y devolvió vacío. **No invento cifra.** Consultar tarifas vigentes con el proveedor | **API REST v3 "Business Open"** con sandbox, claves API/2FA y SDK TypeScript ([doc.tropipay.com](https://doc.tropipay.com/es/docs/intro)) | 🟡 Depósito a tarjeta cubana en **1–5 días** según banco (fuente secundaria) | 🔴 Es una **billetera**, no una pasarela bancaria: el saldo vive en TropiPay y hay riesgo de contraparte/KYC. Usado por la diáspora para remesas; no lo trates como custodia de tu facturación |
| **Zelle** | ⚠️ No como comercio cubano; requiere entidad/banco de EE. UU. | ❌ El destinatario necesita **cuenta bancaria de EE. UU.** | USD | ✅ **Típicamente sin comisión para consumidor** ([Zelle](https://www.zellepay.com/faq/what-zelle)) | **No hay API de comercio**: transferencia + **conciliación manual** por referencia | ✅ Minutos si el destinatario ya está enrolado | 🔴 **Irreversible** ("payments cannot be reversed") y de persona a persona. Sirve para prepago de la diáspora a una cuenta operadora en EE. UU.; el matching de pagos es 100% manual |
| **PayPal** | ⚠️ **Cuba no figura** entre los mercados donde PayPal opera (fuente secundaria + página de países). Cerrarían la cuenta a un beneficiario cubano | ❌ Sin cuenta/banco cubano no hay cobro | Multidivisa (25 monedas) | ⚠️ No verifiqué precios comerciales en esta sesión | API REST/JS SDK (no probado) | 🟡 Estándar del sector | 🔴 Empresa de EE. UU. sujeta al **programa de sanciones Cuba (OFAC)**. Una operación Cuba-facing sería cerrada y los fondos retenidos. **No lo uso como plan A** |
| **Cripto: USDT TRC20 vía NOWPayments** | ✅ Funciona sin banco cubano; solo dirección de wallet | 🟡 Requiere que el pagador tenga wallet y capacidad de off-ramp (difícil en Cuba) | 350+ criptos; USDT/USDC estables | ✅ **1% de servicio** + comisión de red ([NOWPayments pricing](https://www.nowpayments.io/pricing)). Hay una página propia de [depósito sin fee en USDT TRC20](https://www.nowpayments.io/zero-deposit-fee-usdttrc20) | **API REST + IPN (webhooks)**; también invoices, botón de pago, POS y **suscripciones** | ✅ ~5 minutos de media hasta confirmación; liquidación a tu wallet | 🔴 Sin chargebacks (bueno y malo), pero **AML/KYC, contabilidad y reputación bancaria**. La volatilidad se mitiga usando stablecoins. Tu entidad debe poder justificar el origen de fondos |
| **Cripto: Binance Pay** | 🟡 Muy usado por cubanos, pero ⚠️ **no verifiqué** requisitos de merchant ni tarifa en esta sesión | 🟡 Igual que arriba | Cripto/fiat según región | ⚠️ **No verificado.** Se cita mucho "0% para comercios": **no lo confirmé** | API/recepción de pagos | 🟡 Minutos | 🔴 Dependencia de un exchange con exposición regulatoria; bloqueo de cuenta por KYC/reputación. **No planifiques sobre la tarifa que no verifiqué** |
| **Stripe** | ❌ **Cuba no está** en la lista oficial de países soportados ([Stripe global](https://stripe.com/global)). Sin entidad en país soportado, no hay cuenta | ❌ Un cliente en Cuba no puede pagar con Stripe (no hay adquirencia local) | 135+ monedas de cobro | ✅ **2,9% + 30 ¢** por tarjeta doméstica; **+1,5%** tarjeta internacional; **+1%** si hay conversión de divisa; **1,5%** en stablecoins ([Stripe pricing](https://stripe.com/pricing)) | **API REST/Checkout/Elements + webhooks**; Billing para suscripciones | 🟡 Rolling/weekly/monthly según país de la cuenta | 🟠 Exige **entidad + banco fuera de Cuba**. Si el negocio es "Cuba-facing", Stripe puede cerrar la cuenta por riesgo regulatorio aunque la entidad sea extranjera. Aviso: cobrar a un negocio cubano requiere revisión de cumplimiento |
| **MercadoPago** | ❌ No opera en Cuba | ❌ Sin adquirencia cubana | Monedas locales de cada país | ⚠️ **No publicadas** de forma comparable: cada país tiene tarifas propias y hay que negociarlas. **No invento %** | **API REST + Checkout + suscripciones** | 🟡 Según país (típicamente días) | 🟠 Opera en **AR, BR, MX, CL, CO, PE, UY y EC** (🟡 fuentes secundarias coincidentes; no leí página oficial de cobertura). Cada cuenta está atada a su país: no es una wallet internacional |
| **Wompi (Bancolombia, Colombia)** | ❌ Solo Colombia | ❌ | COP | 🟡 **2,65% + $700 + IVA** por tarjeta en Plan Avanzado (Puntos Colombia 4,43% + $700 + IVA), según el artículo de soporte oficial indexado ([soporte.wompi.co](https://soporte.wompi.co/hc/es-419/articles/360020957133--Cu%C3%A1les-son-los-planes-y-tarifas-que-maneja-la-plataforma-Wompi)) | **API REST, links y QR** | 🟡 Días | 🟠 Requiere entidad/banco colombiano. Volátil |
| **Culqi (Perú)** | ❌ Solo Perú | ❌ | PEN, USD | 🟡 **3,44% tarjetas nacionales y QR; 3,99% internacionales** (snipet de la web oficial de ayuda, [ayuda.culqi.com](https://ayuda.culqi.com/portal/es/kb/articles/cual-es-la-comision-de-culqionline)); hay **mínimo fijo de S/ 3,50** para montos pequeños | **API REST + checkout** | 🟡 Abono el mismo día (claim) | 🟠 Requiere RUC/entidad peruana |
| **dLocal** | ❌ | ❌ | Multi-moneda LatAm/África/Asia | ⚠️ **A cotización**: no publica tarifas. Se negocia por volumen | **API única** para 1000+ métodos locales; tiene **dMoRe = Merchant of Record** | 🟡 Según mercado | 🟠 Está pensado para **empresas globales que venden en mercados emergentes**, no para PYMEs. Onboarding exigente. En LatAm cubre México, Colombia, Perú, Chile, Argentina, Brasil, Uruguay, Ecuador, etc. ([dLocal coverage](https://dlocal.com/)) |
| **Paddle (Merchant of Record)** | ⚠️ No como vendedor cubano; la cuenta es de una entidad no cubana | 🟡 El **comprador** puede estar donde sea, pero las políticas de uso de Paddle excluyen países sancionados (no leí el AUP completo: ⚠️) | Multidivisa | ✅ **5% + 50 ¢** por transacción de Checkout, todo incluido ([Paddle pricing](https://www.paddle.com/pricing)) | **API + checkout alojado/overlay**; Billing para suscripciones | 🟡 Payouts periódicos a tu banco | 🟠 Paddle **es el vendedor legal** ante el cliente (asume IVA/VAT). A cambio: menos control, y **no sirve para cobrar "servicios del mundo real"** — su negocio es software/productos digitales |
| **Lemon Squeezy (MoR)** | ⚠️ Igual que Paddle | 🟡 Igual | 95+ monedas (claim) | ✅ **5% + 50 ¢** por transacción, con **fees adicionales posibles** en casos borde ([Lemon Squeezy pricing](https://www.lemonsqueezy.com/pricing)) | **API REST + checkout/links**; suscripciones y licencias | 🟡 Pagos **dos veces al mes** por transferencia o PayPal | 🟠 Productos digitales únicamente. Misma advertencia de sanciones que Paddle |
| **RevenueCat + Google Play Billing / Apple IAP** | ❌/⚠️ No resuelve el onboarding cubano: el dinero lo cobra la tienda y ella liquida | ✅ Si el usuario tiene cuenta de tienda con medio de pago válido; ⚠️ **Google Play Billing no opera en Cuba** (no verificado formalmente, ver §3.4) | Moneda de la tienda | ✅ **RevenueCat: gratis hasta 2.500 USD de MTR, después 1% de lo trackeado** ([RevenueCat pricing](https://www.revenuecat.com/pricing)). **Apple**: 15% con el Small Business Program si <1 M USD/año ([Apple SBP](https://developer.apple.com/app-store/small-business-program/)), **30% estándar** 🟡. **Google Play**: 15% hasta 1 M USD/año, 30% después; **suscripciones 15%**; nueva estructura 10% + 5% de billing fee en AU/EEE/JP/UK/US ([Google Play service fees](https://support.google.com/googleplay/android-developer/answer/112622?hl=en)) | **SDK nativo + webhooks** | 🟡 Apple/Google pagan según su calendario (mensual, con retenciones) | 🔴 **Solo sirve para contenido digital** (ver §3). Y exige que la entidad pueda darse de alta como developer con cuenta bancaria aceptada por Apple/Google |

**Celdas deliberadamente vacías o con ⚠️:** no puse cifra donde no la verifiqué. Las tres lagunas que más importan son: (a) comisión real de comercio de **Transfermóvil** y **Enzona**, (b) tabla de tarifas de **TropiPay**, (c) tarifas por país de **MercadoPago** y **dLocal**. Las tres se resuelven con una llamada/email comercial, no con web.

---

## 3. Política de las tiendas de apps: cuándo es obligatorio IAP y cuándo NO

Esta sección es la que más dinero puede ahorrar o costar. Está citada textualmente de los documentos oficiales vigentes al 2026-10-29.

### 3.1 Apple — App Store Review Guidelines

**3.1.1 In-App Purchase (lo que SÍ exige IAP)** — cita:

> "If you want to unlock features or functionality within your app, (by way of example: subscriptions, in-game currencies, game levels, access to premium content, or unlocking a full version), you must use in-app purchase. Apps may not use their own mechanisms to unlock content or functionality, such as license keys, augmented reality markers, QR codes, cryptocurrencies and cryptocurrency wallets, etc."

Fuente: [App Review Guidelines 3.1.1](https://developer.apple.com/app-store/review/guidelines/#3.1.1).

**3.1.3(d) Person-to-Person Services (exención para servicios 1:1 en tiempo real)** — cita:

> "If your app enables the purchase of real-time person-to-person services between two individuals (for example tutoring students, medical consultations, real estate tours, or fitness training), you may use purchase methods other than in-app purchase to collect those payments. One-to-few and one-to-many real-time services must use in-app purchase."

**3.1.3(e) Goods and Services Outside of the App (exención + PROHIBICIÓN de IAP)** — cita clave:

> "If your app enables people to purchase physical goods or services that will be consumed outside of the app, **you must use purchase methods other than in-app purchase** to collect those payments, such as Apple Pay or traditional credit card entry."

Fuente: [App Review Guidelines 3.1.3(d) y 3.1.3(e)](https://developer.apple.com/app-store/review/guidelines/#3.1.3).

**3.1.3(b) Multiplatform Services (la trampa para el SaaS del negocio):**

> "Apps that operate across multiple platforms may allow users to access content, subscriptions, or features they have acquired in your app on other platforms or your web site, including consumable items in multi-platform games, provided those items are also available as in-app purchases within the app."

**3.1.3(f) Free Stand-alone Apps** permite una app gratuita de compañía de un servicio web, "provided there is no purchasing inside the app, or calls to action for purchase outside of the app".

**3.1.1(a) Link to Other Purchase Methods:** los entitlements para enlazar fuera solo aplican a regiones específicas y, desde la sentencia/reglas vigentes en EE. UU., en el storefront de EE. UU. no se exigen entitlements para incluir botones/enlaces externos. En el resto de storefronts, "apps and their metadata may not include buttons, external links, or other calls to action that direct customers to purchasing mechanisms other than in-app purchase".

**3.1.5 Cryptocurrencies — corrección importante a la consigna:** en las guías vigentes **no existe un apartado "3.1.5(a)"**. 3.1.5 se titula *Cryptocurrencies* y sus subapartados son **(i) Wallets**, **(ii) Mining**, **(iii) Exchanges**, **(iv) Initial Coin Offerings** y **(v)**. Lo relevante para GoReserva:
- **(i)** permite almacenar cripto solo si el desarrollador está enrolado **como organización**;
- **(iii)** permite facilitar transacciones en un exchange aprobado **solo en países donde la app tenga licencia**;
- y de 3.1.1 se desprende que **una wallet/cripto no puede usarse como mecanismo para desbloquear funcionalidad** dentro de la app. Es decir: **no puedes usar "paga con USDT tu plan premium" como sustituto del IAP en iOS**.

Fuente: [App Review Guidelines §3.1.5](https://developer.apple.com/app-store/review/guidelines/#3.1.5).

### 3.2 Google Play — Payments policy

**Regla general (§1-2 de la política):**

> "Play-distributed apps requiring or accepting payment for access to in-app features or services, including any app functionality, digital content or goods (collectively 'in-app purchases'), must use Google Play's billing system for those transactions unless Section 3, 8, or 9 applies."

**Servicios físicos: NO se usa Play Billing (§4.1):**

> "Google Play's billing system must not be used in cases where: payment is primarily: for the purchase or rental of physical goods (such as groceries, clothing, housewares, electronics); **for the purchase of physical services (such as transportation services, cleaning services, airfare, gym memberships, food delivery, tickets for live events)**; or a remittance in respect of a credit card bill or utility bill."

Fuente: [Payments policy (Play Console Help)](https://support.google.com/googleplay/android-developer/answer/9858738?hl=en).

**FAQ oficial "Understanding Google Play's Payments policy" — exenciones que aplican a GoReserva:**

- **Servicios online 1:1 pagados (educación, salud, asesoría):** no se exige Play Billing si "the paid service is between two individuals" y "the paid service is not available for replay afterwards". Ejemplos citados: *"health coaching (such as personal trainer sessions or counseling services)"* y *"specialist advisory services"*.
- **Servicios clínicos regulados:** "Transactions involving regulated clinical services should not use Google Play's billing system."
- **Bienes/servicios que no se consumen en la app:** "Purchases of digital goods or services that can only be consumed outside of a Play-distributed app and cannot be accessed in a Play-distributed app do not require Google Play's billing system."
- **Si Play Billing no está disponible en un país, la obligación no aplica allí:** "As long as Google Play's billing system isn't available in a particular country, the Payments policy's requirement to use Google Play's billing system does not apply in that country."
- **Nunca puedes dirigir al usuario a otro pago dentro de la app** (salvo programas de país): "Other than the conditions described in Section 3, Section 8, and Section 9, apps may not lead users to a payment method other than Google Play's billing system", incluyendo "in-app webviews, buttons, links, messaging, advertisements, or other calls to action" y flujos de creación de cuenta.
- **App "consumption-only":** permitida; el usuario accede a contenido pagado fuera. Pero "any product(s) or service(s), whether digital or physical, cannot be purchased from within the app".

Fuente: [Understanding Google Play's Payments policy](https://support.google.com/googleplay/android-developer/answer/10281818?hl=en).

### 3.3 Traducción a GoReserva (los 4 casos de producto)

| Producto | Naturaleza | Apple | Google Play | Qué hacer |
|---|---|---|---|---|
| **Fee por reserva / turno / cita presencial** (salón, barbería, consulta, spa) | Servicio del mundo real consumido **fuera** de la app | **Exento y además obligatorio NO usar IAP** (3.1.3(e)) | **Prohibido usar Play Billing** (política §4.1, servicios físicos) | Cobrar con **Transfermóvil / Enzona / TropiPay / USDT / tarjeta**, dentro del binario, sin problema |
| **Prepago de esa misma reserva por la diáspora** (paga un familiar en el exterior) | Igual: servicio real fuera de la app | Exento (3.1.3(e)) | Exento (servicio físico) | Web/checkout externo, link de pago, wallet. **Ojo:** no puede parecer "desbloqueo de funcionalidad digital" |
| **Consulta médica/asistencia 1:1 en vivo por videollamada** | Servicio 1:1 en tiempo real, no reproducible | **Exento** (3.1.3(d)) | **Exento** (FAQ 1:1 online paid services) | Mismo rail que la reserva |
| **"Plan premium del consumidor"** (prioridad en cola, historial, ad-free, más reservas/mes) | **Funcionalidad/contenido digital dentro de la app** | **IAP obligatorio** (3.1.1) si hay compra en el binario | **Play Billing obligatorio** (§1, "app functionality or content") | **Vender solo en la web** (no en la app) y dejar la app como consumo → o asumir el 15/30%. En iOS, la versión de la app **no debe tener botón ni link** de compra hacia la web salvo storefront de EE. UU. con las reglas 3.1.1(a) |
| **Suscripción del negocio (B2B, la que ya cobras)** | Software SaaS de gestión | Zona gris: 3.1.3(b) exige que lo comprado fuera **también** esté como IAP si la app da acceso; 3.1.3(f) lo exime si la app es compañera gratuita **sin compra ni CTA** dentro. Google: "cloud software and services" figura entre lo que **sí** requiere Billing si se compra **dentro** de la app | **No pongas el alta/renovación dentro de la app móvil.** Alta y pago en panel web; la app solo muestra estado y consume. En Android, permitir solo "consumption-only" |

### 3.4 Advertencia específica sobre Cuba y las tiendas

- Apple y Google **cobran y liquidan en su propia moneda** y pagan a una cuenta bancaria que ellos acepten. Un desarrollador cubano sin cuenta bancaria aceptada por Apple/Google **no puede recibir la liquidación** aunque la app esté publicada.
- ⚠️ **No pude verificar formalmente** si Google Play Billing está disponible para usuarios en Cuba (la página oficial "Supported locations" es JavaScript-only y no obtuve la tabla). La FAQ de Google dice que si el billing no está disponible en un país, la obligación de usarlo no aplica allí. **Trátalo como dato no verificado y confírmalo en Play Console antes de diseñar el flujo.** 🔁
- Uso práctico de esta sección: **la versión móvil de GoReserva no debería vender nada digital dentro del binario**. Todo lo digital se vende en la web; todo lo que se vende dentro es servicio del mundo real, que está exento y además está protegido por la política.

---

## 4. Sanciones y limitaciones reales

### 4.1 El marco: OFAC / programa Cuba

✅ **Verificado:** existe un programa de sanciones específico de EE. UU. sobre Cuba, con regulación propia, **31 CFR Part 515 (Cuban Assets Control Regulations)** y 31 CFR Part 516, con licencias generales y específicas, y con la posibilidad de solicitar licencia a OFAC.
Fuente: [OFAC — Cuba Sanctions](https://ofac.treasury.gov/sanctions-programs-and-country-information/cuba-sanctions).

**Consecuencia práctica:** cualquier empresa estadounidense (Stripe, PayPal, Apple, Google, Paddle son de EE. UU. o dependen de bancos de EE. UU.) está sujeta a ese régimen. "No aparece mi país en la lista" no significa "puedo facturar a Cuba"; significa que **la operación requiere análisis y, si aplica, licencia**. Esto es exactamente lo que hunde las cuentas "Cuba-facing" en PSPs globales.

### 4.2 Qué pasa exactamente con cada PSP

| PSP | Estado respecto a Cuba | Evidencia |
|---|---|---|
| **Stripe** | ❌ **Cuba no está en la lista de países soportados.** Se listan AU, AT, BE, BR, BG, CA, CI, HR, CY, CZ, DK, EE, FI, FR, DE, GH, GI, GR, HK, HU, IN, ID, IE, IT, JP, KE, LV, LI, LT, LU, MY, MT, MX, NL, NZ, NG, NO, PL, PT, RO, SG, SK, SI, ZA, ES, SE, CH, TH, AE, GB, US. | ✅ [stripe.com/global](https://stripe.com/global) |
| **PayPal** | ❌ Cuba no figura entre los mercados soportados (fuente secundaria; la lista oficial está en PayPal Global). Empresa de EE. UU. → régimen OFAC. | 🟡 [PayPal: countries and currencies](https://www.paypal.com/va/webapps/mpp/country-worldwide), [PayPal Payouts: countries and supported features](https://developer.paypal.com/payouts/supported-features/) |
| **MercadoPago** | ❌ No opera en Cuba. Cada cuenta está atada a un país (AR/BR/MX/CL/CO/PE/UY/EC). | 🟡 [Wikipedia — Mercado Pago](https://es.wikipedia.org/wiki/Mercado_Pago); la página de cobertura oficial no la pude leer |
| **Zelle** | ❌ "In order to use Zelle®, the sender and recipient's must have U.S bank accounts." Además: **irreversible**. | ✅ [zellepay.com/faq/what-zelle](https://www.zellepay.com/faq/what-zelle) |
| **Apple / Google** | ⚠️ Publican apps de desarrolladores de muchos países, pero la liquidación requiere cuenta bancaria aceptada y cumplimiento; Cuba no es un mercado de pago estándar. | ⚠️ no verificado en detalle |
| **dLocal / Paddle / Lemon Squeezy (MoR)** | ⚠️ Son la vía "legalmente limpia" para vender digital a LatAm/global, pero **sus políticas de uso de producto excluyen países sancionados**. No leí completos sus AUP/ToS en esta sesión: **verifícalo antes de firmar**. | ⚠️ [Paddle pricing](https://www.paddle.com/pricing), [Lemon Squeezy pricing](https://www.lemonsqueezy.com/pricing) |

### 4.3 Las estructuras que se usan habitualmente (y el riesgo de cada una)

> Esta subsección es donde más fácil es hacer algo ilegal sin saberlo. **Requiere abogado.**

| Estructura | Cómo funciona | Coste típico | Riesgos reales |
|---|---|---|---|
| **US LLC / C-Corp en Delaware vía Stripe Atlas** | ✅ Verificado: "Apply online from almost anywhere in the world"; **500 USD una vez** (incluye tasas y primer año de agente) + **100 USD/año** de agente; incluye EIN, equity, 83(b), cuenta con Stripe Treasury | 500 + 100 USD/año | 🔴 **Abrir la empresa no equivale a poder cobrar a Cuba.** El dueño cubano necesita visa/ITIN/EIN y cuenta bancaria; Atlas no garantiza aprobación. Y una entidad de EE. UU. que factura a residentes/empresas cubanas sigue bajo OFAC. Fuente: [stripe.com/atlas](https://stripe.com/atlas) |
| **Entidad en Panamá** | 🟡 Práctica común en la región por apertura societaria y banca internacional | 🟡 Variable (constitución + agente + contabilidad) | ⚠️ **No verifiqué** requisitos 2026 ni disponibilidad de banca/PSP. Hoy muchas fintechs y bancos aplican *enhanced due diligence* a sociedades panameñas → alta tasa de rechazo |
| **Entidad en España** | 🟡 Vía razonable si hay socio/residente UE; Stripe sí opera en España | 🟡 Constitución + notario + alta fiscal | ⚠️ Obligaciones fiscales/contables reales en España; cobrar a Cuba puede chocar con compliance del banco |
| **Entidad en México** | ✅ Stripe y MercadoPago operan en México; ecosistema maduro | 🟡 Constitución + RFC + contabilidad | ⚠️ México mantiene régimen propio de reporte; el banco puede cerrar cuentas con exposición Cuba |
| **Merchant of Record (Paddle, Lemon Squeezy, dLocal dMoRe)** | El MoR **es el vendedor** ante el cliente: factura, cobra, gestiona impuestos. Tú eres "supplier" | ✅ **5% + 50 ¢** (Paddle y Lemon Squeezy) | 🟠 Solo productos **digitales/software**. No sirve para el fee de reserva presencial. Y su AUP es la que decide si aceptan o no la operación: con exposición Cuba, probable rechazo |
| **Cuenta de cobro en el exterior a nombre de un tercero / familiar ("straw")** | ⚠️ Muy frecuente en la diáspora | — | 🔴 **No lo recomiendo.** Es evasión de KYC: el PSP puede congelar fondos, cerrar cuentas y reportar. Deja al negocio sin defensa legal |

**Lo que NO pude verificar y por tanto marco explícitamente como dudoso:**
- Si Stripe Atlas acepta como fundador a un residente/nacional cubano en 2026, y si Stripe acepta después una cuenta con ese perfil (⚠️).
- Si Paddle/Lemon Squeezy/dLocal permiten vender a **clientes** ubicados en Cuba (su AUP, no leído) (⚠️).
- Si TropiPay puede contratarse como **comercio** desde Cuba y con qué tarifa (⚠️).
- Cifras exactas de comisión de comercio de Transfermóvil/Enzona (⚠️ — no publicadas en las fuentes que pude leer).

---

## 5. Recomendación corta por escenario

### Escenario A — "Solo Cuba" (hoy)

- **Fee por reserva / prepago:** **Transfermóvil**. Concretamente: **migrar del deep link + "Ya he pagado" al "Pago en Línea por QR / tienda virtual" de Bulevar MiTransfer** (contratación en [transfermovil.etecsa.cu/contratacion](http://www.transfermovil.etecsa.cu/contratacion)), pidiendo en la contratación el detalle de la **API de tienda virtual** y su comisión. Mientras eso no exista, mantener el circuito actual (que ya funciona y está probado end-to-end) y añadir **Enzona** como segundo rail con su API.
- **Segundo rail:** **Enzona** (API + Bulevar), que es el único rail cubano con API de comercio pública.
- **Suscripción del negocio (recurrente):** mantener Transfermóvil/Enzona con **recordatorio + outbox de WhatsApp** (ya está en el modelo) y conciliación asistida. No hay tokenización posible en Cuba: **el recurrente cubano es, por ahora, un cobro manual asistido**, y hay que diseñarlo como tal (avisos, gracia, degradación de plan).
- **No hacer:** Stripe, PayPal, MercadoPago. No van a abrir la cuenta.

### Escenario B — "Cuba + diáspora"

- **Prepago de reserva pagado por la diáspora:** **TropiPay** (API v3 con sandbox y webhooks; ideal para "el hijo en Miami paga la consulta del padre") **+ Zelle** solo como canal manual de conciliación a una cuenta de EE. UU. **+ USDT TRC20 vía NOWPayments** (1%) como rail sin fricción para el segmento cripto.
- **Regla operativa:** el pago de la diáspora se registra como **prepago de un servicio del mundo real** → exento de IAP en ambas tiendas. La web de pago debe ser una **página web externa**, no un flujo dentro del binario iOS.
- **Suscripción recurrente digital para la diáspora:** **Paddle o Lemon Squeezy como Merchant of Record** (5% + 50 ¢) **solo si** tu entidad y su AUP lo permiten y el producto es software/digital puro. Alternativa: Stripe Billing con entidad en país soportado (2,9% + 30 ¢ + 1,5% internacional).
- **Advertencia clave:** todo esto obliga a tener **entidad y banco fuera de Cuba**. Sin eso, B no existe.

### Escenario C — Expansión LatAm

- **Cobro local:** **MercadoPago** para AR/BR/MX/CL/CO/PE/UY; **Wompi** para Colombia (🟡 2,65% + $700 + IVA); **Culqi** para Perú (🟡 3,44% nacional / 3,99% internacional). Si el volumen justifica una sola integración multi-país y hay recursos de compliance: **dLocal** (+ **dMoRe** como MoR).
- **Suscripciones LatAm:** **Stripe Billing** si hay entidad en un país soportado (MX, BR); si no, **dLocal** para métodos locales recurrentes o un MoR para el digital.
- **Móvil:** la app sigue sin vender digital dentro del binario; el alta y el pago siempre en web.

### Recurrente vs one-shot — la regla de una línea

| Necesidad | Qué usar |
|---|---|
| **One-shot: fee por reserva / prepago de cita** (Cuba) | **Transfermóvil** (QR / deep link) + **Enzona**. Conciliación manual o por API de comercio cuando se contrate. |
| **One-shot: prepago de la diáspora** | **TropiPay** (API/webhooks) + **USDT TRC20 (NOWPayments, 1%)**; Zelle solo como canal manual. |
| **One-shot: ticket digital puro** | MercadoPago / Culqi / Wompi / Stripe según país. |
| **Recurrente dentro de Cuba** | No hay tokenización: Transfermóvil/Enzona + recordatorios y verificación asistida (diseñar como proceso humano). |
| **Recurrente digital fuera de Cuba** | **Stripe Billing** (si hay entidad soportada) o **Paddle / Lemon Squeezy** (5% + 50 ¢, MoR). |
| **Recurrente digital consumido en móvil (iOS/Android)** | **IAP obligatorio** si se vende dentro de la app (Apple 15/30%, Google 15/30%). Recomendado: **no venderlo dentro**, venderlo en web. |
| **Fee por reserva (mundo real) en móvil** | **NUNCA IAP.** Exento y, en Apple, obligatorio usar otro método (3.1.3(e)). |

---

## 6. Anexo A — URLs consultadas (2026-10-29)

**Tiendas de apps / políticas**
- https://support.google.com/googleplay/android-developer/answer/10281818?hl=en — *Understanding Google Play's Payments policy* ✅
- https://support.google.com/googleplay/android-developer/answer/9858738?hl=en — *Payments* (política) ✅
- https://support.google.com/googleplay/android-developer/answer/112622?hl=en — *Service fees* ✅
- https://support.google.com/googleplay/android-developer/answer/12201481?hl=en — *Rest of the world* (categoría de distribución) ✅
- https://support.google.com/googleplay/android-developer/answer/10532353?hl=en — *Supported locations for distribution* (remite a la tabla JS) ✅
- https://developer.apple.com/app-store/review/guidelines/ — *App Review Guidelines* (3.1.1, 3.1.3(d)(e)(f), 3.1.5) ✅
- https://developer.apple.com/app-store/small-business-program/ — comisión reducida 15% ✅

**Rails Cuba**
- https://www.etecsa.cu/es/node/3207 — *Bulevar MiTransfer (Contratación digital)* ✅
- https://www.transfermovil.etecsa.cu/contratacion — contratación del Pago en Línea por QR (timeout al intentar leerlo; citado por ETECSA) ⚠️
- https://www.xetid.cu/es/productos/enzona — ENZONA: plataforma, bancos, API, Bulevar, producto "Ticket" ✅
- https://api.enzona.net/store/ — APIs de ENZONA (referenciada por XETID, no leída) 🟡
- https://bulevar.enzona.net/tarifas — planes de suscripción del Bulevar (referenciada, no leída) 🟡
- https://oncubanews.com/cuba/promueven-en-comercios-estatales-y-privados-contratacion-para-pago-electronico/ — modalidades QR y tienda virtual con API 🟡
- https://razonesdecuba.cu/transfermovil-y-enzona-un-camino-seguro-en-la-bancarizacion/ — contexto de adopción 🟡
- https://eltoque.com/wallets-en-cuba-cual-usar — wallets y su uso en Cuba 🟡

**Rails internacionales**
- https://help.tropipay.com/knowledge-base/tarifas-que-costes-y-comisiones-tiene-tropipay/ — tarifas (página JS, devolvió vacío) ⚠️
- https://doc.tropipay.com/es/docs/intro — API v3, sandbox, 2FA, SDK ✅
- https://www.tropipay.com/developers — integraciones y API ✅
- https://www.nowpayments.io/pricing — 1% de servicio ✅
- https://www.nowpayments.io/zero-deposit-fee-usdttrc20 — USDT TRC20 ✅
- https://stripe.com/global — países soportados (Cuba ausente) ✅
- https://stripe.com/pricing — 2,9% + 30 ¢; +1,5% internacional; +1% conversión; 1,5% stablecoins ✅
- https://stripe.com/atlas — incorporación en Delaware, 500 USD + 100 USD/año ✅
- https://stripe.com/legal/restricted-businesses — negocios prohibidos/restrictos (referenciada, no leída) 🟡
- https://www.paypal.com/va/webapps/mpp/country-worldwide — países y monedas 🟡
- https://developer.paypal.com/payouts/supported-features/ — exclusiones/restricciones por país 🟡
- https://www.zellepay.com/faq/what-zelle — solo cuentas de EE. UU., sin comisión al consumidor, irreversible ✅
- https://www.mercadopago.com/ (no leída) + https://es.wikipedia.org/wiki/Mercado_Pago — 8 países operativos 🟡
- https://soporte.wompi.co/hc/es-419/articles/360020957133--Cu%C3%A1les-son-los-planes-y-tarifas-que-maneja-la-plataforma-Wompi — 2,65% + $700 + IVA (Puntos Colombia 4,43% + $700 + IVA) 🟡
- https://ayuda.culqi.com/portal/es/kb/articles/cual-es-la-comision-de-culqionline — 3,44% nacional / 3,99% internacional, mínimo S/ 3,50 🟡
- https://dlocal.com/ — cobertura, dMoRe (MoR), 1000+ métodos ✅
- https://www.paddle.com/pricing — 5% + 50 ¢ ✅
- https://www.lemonsqueezy.com/pricing — 5% + 50 ¢ (+ fees adicionales posibles) ✅
- https://www.revenuecat.com/pricing — gratis hasta 2.500 USD MTR, luego 1% ✅

**Sanciones**
- https://ofac.treasury.gov/sanctions-programs-and-country-information/cuba-sanctions — programa Cuba, 31 CFR 515/516, licencias ✅
- https://www.ecfr.gov/current/title-31/subtitle-B/chapter-V/part-515 — Cuban Assets Control Regulations (referenciada, no leída) 🟡

**Contexto interno (repo, solo lectura)**
- `inventtia_flow/CHANGELOG.md:18-25`
- `inventtia_flow/PLAN_SUSCRIPCIONES.md:176`, `:445-447`
- `inventtia_flow/docs/flow_schema/migraciones/43_suscripciones_tablas.sql:299-366`
- `inventtia_flow/docs/flow_schema/migraciones/62_pago_adelantado_servicio.sql`
- `inventtia_flow/android/app/src/main/AndroidManifest.xml:51-66`
- `inventtia_flow/lib/widgets/pago_adelantado_sheet.dart`

---

## 7. Anexo B — Lo que queda por verificar (checklist antes de decidir)

1. **Comisión real de comercio de Transfermóvil** (deep link vs. Bulevar/tienda virtual) y si la modalidad de tienda virtual expone API documentada y webhooks. → `atencion.usuarios@etecsa.cu` / Joven Club municipal.
2. **Comisión y API de comercio de Enzona**; leer `bulevar.enzona.net/tarifas` y `api.enzona.net/store/`. ⚠️
3. **Tarifas vigentes de TropiPay** para comercio y para payout a tarjeta cubana (la web de tarifas no es legible por scraping). ⚠️
4. **Disponibilidad real de Google Play Billing en Cuba** (tabla oficial de localizaciones soportadas). ⚠️
5. **AUP/ToS de Paddle, Lemon Squeezy y dLocal** respecto a clientes en países sancionados. ⚠️
6. **Elegibilidad real (no marketing) de Stripe Atlas** para un fundador cubano y para una operación con exposición Cuba; y **disponibilidad de banco** después. ⚠️
7. **Verificar que la tarjeta "CLÁSICA"** hace lo que se cree que hace (no pude confirmarlo). ⚠️
8. **Comisión de MercadoPago por país** (no publicada de forma comparable) y **de dLocal** (a cotización). ⚠️
9. **Revisión legal formal** de la estructura societaria y del encaje OFAC antes de mover un solo dólar. ⚠️
