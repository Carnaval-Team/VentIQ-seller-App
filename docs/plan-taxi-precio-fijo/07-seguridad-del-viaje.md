# 07 · Seguridad del viaje (chofer y pasajero)

> **Hito**: H2 del [PLAN-IMPLEMENTACION.md](PLAN-IMPLEMENTACION.md) · **Migración**: `inventtia_muevete/docs/migrations/037_taxi_seguridad.sql` (ver Supuesto S-02 sobre la numeración).
> **Depende de**: H0 (esquema tarifas/RPCs) y H1 (identidad, KYC, `fn_usuario_habilitado()` y pantalla de perfil completo).
> **Bloquea a**: H3 (`fn_tomar_viaje`/`fn_completar_viaje` deben llamar a las piezas de §4.6), H4/H5 (pantallas de viaje) y H6 (bandeja de incidentes en superadmin).
> **Modo**: análisis de sólo lectura sobre el código; el único archivo escrito por este trabajo es este documento.

---

## 0. Resumen para decidir

1. **La app no protege a nadie por sí sola.** Las 6 features aprobadas hacen tres cosas concretas: (a) **acortan el tiempo** hasta que un tercero sepa que algo va mal; (b) hacen al agresor **identificable** (foto, chapa, CI parcial, registro); (c) **sacan de la plataforma** a quien ya agredió y evitan que vuelva a emparejarse con la víctima.
2. **El botón de pánico no llama a nadie de Muevete.** No hay operación 24/7. El pánico: registra el evento en el servidor (o en cola local si no hay red), empuja la alerta a los contactos que tengan la app, deja un SMS **prellenado** listo para enviar desde el propio teléfono, y pone el 106 a un toque. Quien decide llamar a la policía es la persona o su contacto.
3. **El enlace de viaje compartido es la pieza más cara** (necesita una página pública: Edge Function). Es también la que más reduce el riesgo real en un secuestro/traslado, porque le da a un tercero el recorrido en vivo y la chapa. Si no se puede desplegar, el MVP sigue siendo útil pero **no puede prometer "ver en vivo"** (ver §9).
4. **Contacto de emergencia obligatorio**: se valida (responde un código o acepta en la app) y **se exige en el servidor**, no sólo en la UI. Un cliente modificado no puede publicar ni tomar viajes sin él (`fn_crear_solicitud` y `fn_tomar_viaje` lanzan error).
5. **Antes de construir esto hay que cerrar RLS.** Hoy `drivers_see_solicitudes` es `USING (true)` y `place` es legible por cualquier autenticado ([04 §1.2](04-diseno-tecnico.md), [01 §4.3](01-analisis-tecnico.md)). Mientras eso siga abierto, cualquier cuenta puede leer todas las solicitudes con coordenadas y seguir a un chofer: el control de privacidad de §8 **depende** del endurecimiento de RLS, no de la UI.

**Esfuerzo estimado**: 4–5 semanas de un desarrollador full-stack con acceso a Supabase (detalle por feature en §3 y orden recomendado en "Recomendación").

**Fuera de alcance (decidido)**: PIN de abordaje, operador humano 24/7, grabación de audio del viaje, geocercas de riesgo. Están en §9 con su costo de reapertura.

---

## 1. Modelo de amenazas

Escala cualitativa: **Probabilidad** alta/media/baja para un viaje urbano en Santa Clara con viajes nocturnos; **Impacto** crítico (vida/integridad), alto (lesión o pérdida patrimonial grave), medio (pérdida menor, miedo, tiempo), bajo (molestia). No hay datos medidos: hoy la app no registra incidentes, así que estas etiquetas son juicio experto y deben recalibrarse con las métricas de §7 a los 3 meses.

| # | Amenaza | Quién la sufre | Probabilidad | Impacto | Control propuesto (feature) | Qué NO resuelve la app |
|---|---|---|---|---|---|---|
| A-01 | **Robo con violencia al chofer** (arma blanca, varios sujetos, "pásame el carro y el teléfono") | Chofer | Media-alta | Crítico | F1 pánico silencioso + F2 enlace compartido + F6 106 + F5 incidente/bloqueo. Copy anti-resistencia. El pánico **nunca** suena por defecto. | El robo en sí; la integridad física; recuperar el vehículo. Si le quitan el teléfono, la app deja de emitir y el contacto ve "sin actualización". |
| A-02 | **Robo al pasajero** (celular, cadena, efectivo) en el vehículo o al bajarse | Pasajero | Media-alta | Alto | F4 verificación (no subir a un carro que no es), F2 enlace visible por el contacto, F1, F5. Copy "no muestres el teléfono en la calle". | El hurto consumado. Si le roban el teléfono, pierde la app: por eso el registro vive en el servidor y el contacto ya tiene el enlace. |
| A-03 | **Pasajero que no aparece** (deja esperando al chofer de noche en una esquina) | Chofer | Alta | Medio | F5 no-show: temporizador con `gracia_espera_min`, cancelación sin comisión, incidente `no_show_pasajero`, restricción tras 3 en 30 días. | El tiempo perdido y el riesgo de estar parado en la calle. No se obliga al pasajero a estar. |
| A-04 | **Suplantación de identidad** (cuenta ajena, chofer que usa el carro de otro, "soy el que pidió") | Ambos | Media | Alto | F4 foto + nombre + chapa + CI parcial visibles, obligación de coincidir antes de abordar, botón "no coincide", F5 reporte, invalidación de cuenta, F3 contacto para avisar. | Que un conocido del titular use su cuenta y su teléfono; que el chofer preste el vehículo. La identidad se verifica con documentos una vez (H1), no en cada viaje. |
| A-05 | **Montar un vehículo equivocado** (o "taxi pirata" que se hace pasar por el asignado) | Pasajero | Media | Crítico | F4: chapa en tipografía grande + confirmación explícita antes de iniciar + "no es mi chofer" que muestra de nuevo los datos correctos. | Que la persona suba igual por prisa o por presión. No hay forma de impedir físicamente que alguien suba a un carro. |
| A-06 | **Acoso** (verbal, insinuaciones, contacto físico no consentido), sobre todo a pasajeras | Ambos (mayoría pasajeras) | Media | Alto | F1 (discreto), F2 (el contacto ve el recorrido), fin de viaje anticipado sin penalidad, F5 severidad alta + bloqueo preventivo inmediato, F3. | El hecho consumado y la denuncia formal. La app no recoge prueba de audio (rechazado). |
| A-07 | **Agresión en la parada o en la espera** (antes de subir, o el chofer esperando al pasajero) | Ambos | Media | Alto | F1 disponible desde que el viaje se acepta (no sólo "en viaje"), F2, F6, F5, no-show. | La espera en la calle. No hay geocercas de "punto seguro" (rechazado). |
| A-08 | **Uso del viaje para ubicar a una persona** (expareja que pide viaje al domicilio; chofer que vuelve después) | Pasajera o chofer | Media | Crítico | §8: CI parcial, sin teléfono en el enlace, ubicación sólo durante el viaje, tokens con expiración, **bloqueo de emparejamiento** (§4.5) y RLS cerrado. | Que el agresor pida un viaje cerca del domicilio con otra cuenta. Que guarde la dirección a mano. |
| A-09 | **Extorsión / cobro abusivo** ("son 5 000 o te bajas aquí") | Ambos | Media | Alto | Precio **congelado por el servidor** (flujo nuevo): no se negocia en la calle. Recibo con desglose. F5 `extorsion`. Copy "no pagues fuera de la app". | La coerción física: si hay amenaza, manda el 106 y el pánico. |
| A-10 | **Secuestro / traslado fuera de ruta** | Pasajero | Baja | Crítico | F2 (el contacto ve el desvío y la chapa), F1, F6. Alerta al contacto cuando el vehículo se detiene > X min o se aleja del destino (sólo como aviso en la página, no automático). | Nada garantizado. Sin operador no hay nadie que intervenga: el valor es que un tercero sepa. |
| A-11 | **Falso positivo de pánico / broma** | Toda la operación (coste de confianza) | Media | Medio | Ventana de cancelación de 10 s, registro de `cancelado_falso`, 5 falsos en 30 días → revisión manual (no bloqueo automático). Nunca se llama a la policía automáticamente. | El desgaste de los contactos si el usuario abusa. No se puede sancionar sin revisión humana. |
| A-12 | **Fuga de datos personales** (API abierta, enlace filtrado, logs con PII) | Todos | Baja (mientras RLS esté abierto, media) | Alto | RLS por tabla (§4.7), CI parcial, tokens hasheados, `no-store`, `no-referrer`, sin PII en push, retención acotada. | Una brecha de la base completa. La app no puede proteger datos que el servidor entrega mal. |

**Amenazas que la app no cubre y hay que decir en voz alta**: violencia ejercida por alguien que no participa del viaje; robo del vehículo a mano armada con el chofer dentro; agresiones sexuales consumadas; crimen organizado. Para todo eso la única respuesta es **106 + contactos + no resistirse**.

---

## 2. Principio rector

**La app no sustituye a la policía, ni a un operador, ni a un acompañante.** Es una herramienta de **registro, aviso y trazabilidad**. Sirve para que un tercero sepa dónde estabas y con quién, y para que quien agredió no vuelva a usar la plataforma. No sirve para detener una agresión en curso.

### 2.1 Qué garantiza (compromisos verificables)

| Garantía | Cómo se verifica |
|---|---|
| G-01 · Ningún usuario viaja sin al menos un contacto de emergencia validado | `fn_crear_solicitud` y `fn_tomar_viaje` lanzan `sin_contacto_emergencia` si `fn_gate_seguridad()` no devuelve `ok=true` (RS-02) |
| G-02 · Un pánico disparado se registra siempre, con red o sin red | Sin red: queda en cola local persistente (`SharedPreferences`) y se envía al reconectar con el mismo `client_event_id` (idempotente) (RS-07) |
| G-03 · Los contactos con la app reciben la alerta con ubicación | INSERT en `muevete.notificaciones` con `tipo='panico_contacto'` dispara el trigger `notificaciones_push` ya existente ([030 §3](05-sincronizacion-bd-repo.md)) |
| G-04 · El enlace compartido deja de mostrar datos al terminar o cancelar el viaje | Trigger `trg_cierre_seguridad` revoca tokens; la página responde 410 (RS-11) |
| G-05 · Nunca se expone CI completa, teléfono ni dirección exacta a terceros | Whitelist en `fn_ficha_contraparte` y en la Edge Function (§8), verificado con tests de contrato (RS-12) |
| G-06 · Un usuario bloqueado por incidente confirmado no puede pedir ni tomar viajes | Trigger/RPC devuelve `usuario_bloqueado`; además el par víctima-agresor no vuelve a emparejarse (RS-16/RS-18) |
| G-07 · El copy no promete seguridad | Test de copy en CI: ninguna cadena de `lib/screens/seguridad/` contiene "seguro", "protegido", "garantizado", "a salvo" (RS-19) |

### 2.2 Qué NO garantiza (decirlo en la UI, no sólo aquí)

1. **No hay respuesta de emergencia.** Nadie de Muevete va a llamar, ni a ir, ni a mirar la pantalla. No hay operador 24/7.
2. **No impide el delito.** Ni la violencia, ni el robo, ni el traslado forzado.
3. **No verifica identidad en tiempo real.** Verifica documentos una vez (H1); un tercero puede usar la cuenta.
4. **No localiza a la persona si el teléfono se apaga, se queda sin batería o se lo llevan.** Muestra la última posición conocida.
5. **No funciona sin señal.** Sin datos, el SMS y la llamada del propio teléfono son el único canal.
6. **No es un servicio de escolta ni de monitoreo.** El enlace lo mira quien el usuario decida, y sólo si lo mira.

### 2.3 Reglas de copy (obligatorias y testeables)

- Prohibido: "estás seguro", "viaja seguro", "protegemos tu viaje", "garantizado", "respuesta inmediata", "24/7", "monitoreado".
- Obligatorio en la pantalla de pánico y en la de compartir: **"Muevete no sustituye a la policía. Si estás en peligro, llama al 106."**
- El botón del 106 dice **"Llamar al 106"**, nunca "Pedir ayuda" a secas (ambiguo: el usuario creería que alguien de la app responde).
- Los textos de estado usan hechos: "Avisamos a 2 contactos", no "Tus contactos están al tanto".

---

## 3. Especificación de las features aprobadas

### 3.0 Piezas transversales (F0)

Nada de esto es una feature de usuario, pero todo lo demás se apoya en ello.

**Canales de alerta disponibles hoy** (sin contratar nada nuevo):

| Canal | Requiere | Coste | Fiabilidad en Cuba | Uso |
|---|---|---|---|---|
| **Push in-app** (Pushy + trigger `notificaciones_push`) | Contacto con la app instalada y sesión | 0 (infra ya existente) | Media-alta (depende de datos) | Canal automático del pánico |
| **SMS prellenado** (`sms:` vía `url_launcher`) | Cualquier teléfono, sólo señal celular | 0 (lo paga el plan del usuario) | Alta (funciona en 2G) | Contacto sin app; un toque para enviar |
| **WhatsApp prellenado** (`wa.me`, ya usado en `helpers.dart:59-74`) | Contacto con WhatsApp + datos | 0 | Media | Alternativa al SMS |
| **Llamada** (`tel:`, ya usado en `ride_confirmed_screen.dart:697-711`) | Cualquier teléfono | 0 | Alta | Contacto y 106 |
| **Página pública del viaje** (Edge Function nueva) | Datos en el teléfono del contacto | 0 (incluida en el plan) | Media | F2 |

No se asume ningún proveedor de SMS servidor→teléfono: entregar SMS a Cuba de forma programática es caro e inconsistente, y no está en el alcance del MVP (ver §9).

**Archivos nuevos en la app** (respetando el *write scope* de H2 en [PLAN-IMPLEMENTACION.md §7](PLAN-IMPLEMENTACION.md)):

```
lib/services/seguridad_service.dart      # RPCs, outbox, tokens, ficha, incidentes
lib/screens/seguridad/
  contacto_emergencia_screen.dart        # F3 (alta, validación, lista)
  alerta_emergencia_sheet.dart           # F1/F6 (mantener, banner, acciones)
  verificar_contraparte_card.dart        # F4 (widget usado por cliente y chofer)
  compartir_viaje_sheet.dart             # F2
  reportar_incidente_screen.dart         # F5
  mi_seguridad_screen.dart               # hub: contactos, alertas, reportes, bloqueos
lib/widgets/boton_emergencia.dart        # F1 (botón reutilizable)
lib/models/seguridad_models.dart         # ContactoEmergencia, EventoPanico, EnlaceViaje, Incidente, Bloqueo
supabase/functions/seguridad-publica/    # F2 (página y API pública, Deno)
```

**Outbox local** (`seguridad_outbox_v1` en `SharedPreferences`, patrón de `offline_queue_service.dart:7-45`): cola FIFO de 50 eventos como máximo, cada uno con `client_event_id` (UUID v4), `capturado_at`, payload completo. Se vacía con `OfflineQueueService.hasInternetConnection()` (`offline_queue_service.dart:72-90`) al abrir la app, al volver del background y cada 30 s mientras haya pendientes. Si se llena, se descarta el más viejo **sólo si ya tiene más de 7 días**; si no, se bloquea la creación de nuevos eventos y se avisa (no se pierde una alerta por saturación).

**Estados y relojes que usa todo el módulo**: hora del servidor (`now()`), `capturado_at` del cliente y `recibido_at` del servidor se guardan por separado; la diferencia es la métrica `retraso_alerta_s`.

---

### 3.1 F1 · Botón de pánico en viaje

**Objetivo**: que en ≤2 segundos, sin escribir ni explicar nada, quede registrado que la persona está en peligro y que al menos un tercero reciba dónde está y con quién.

**Disparador**
- Viaje `aceptada` (incluye "en camino a recoger"): el chofer ya está expuesto esperando en la calle.
- Viaje `en_curso`.
- Ventana de gracia de 10 minutos después de `completada`/`cancelada` (por si la agresión ocurre al bajarse).

**UX paso a paso (copy exacto)**

1. En las dos pantallas de viaje activo (`active_ride_screen.dart` para el chofer, `ride_confirmed_screen.dart` para el cliente) hay un botón rojo fijo, esquina inferior derecha, por encima de la hoja de ruta:
   > **EMERGENCIA** (ícono de escudo) · debajo, en 11 px: *"Mantén presionado"*

2. Mantener 2 s. Háptica doble a los 1,5 s. Si suelta antes: nada (evita activaciones de bolsillo). Alternativa accesible: 3 toques rápidos sobre el mismo botón (para quien no puede mantener presionado). Ambas vías quedan registradas con `origen='boton'`.

3. Al activarse, **sin que el usuario toque nada más**:
   - se crea el evento (RPC o outbox);
   - se crea un enlace de viaje compartido con permiso completo y 120 min de vida (si no existía);
   - se insertan notificaciones para los contactos con la app;
   - arranca el muestreo reforzado de posición cada 15 s durante 30 min (`eventos_panico_ubicaciones`), usando el foreground service ya existente (`background_service.dart:21-40`, `:577-631`).

4. **Modo discreto por defecto** (`modo='discreto'`): no suena, no vibra fuerte, **la pantalla no cambia**. Aparece una franja fina arriba durante 4 s:
   > *"Alerta enviada · 21:42. Avisamos a tus contactos."*

   Después desaparece. Motivo: en un robo, una pantalla roja o un sonido pueden escalar la violencia. El usuario puede cambiar el default en *Mi seguridad → Cómo se activa*.

5. Si el usuario necesita la pantalla grande (está a salvo para mostrarla), toca la franja o el botón dos veces seguidas:
   > **EMERGENCIA ACTIVADA** · *21:42 · Compartiendo tu ubicación con tus contactos*
   > [ **Llamar al 106** ] (botón grande, primero)
   > [ Enviar mensaje a mamá ] [ Copiar enlace del viaje ] [ Mostrar alerta en pantalla completa ] [ Fue un error ]
   > *Muevete no sustituye a la policía. Si estás en peligro, llama al 106.*
   > *Nadie del equipo de Muevete va a llamarte.*

6. **"Fue un error"** (visible 10 s; después sigue disponible en *Mi viaje → Emergencia*):
   > *"¿Cancelar la alerta? Tus contactos recibirán: «FUE UNA FALSA ALARMA»."* [ Sí, fue un error ] [ No, sigo en peligro ]

7. Si las notificaciones push fallan o el contacto no tiene app, el servidor devuelve la lista de contactos y el sheet ofrece, con un toque:
   > [ **Enviar SMS a mamá** ] → abre el compositor del teléfono con el texto de §3.1.1. *El teléfono no envía solo: pulsa enviar.*

**3.1.1 Texto del SMS de emergencia** (≤320 caracteres, sin acentos raros para teclados viejos; se genera server-side y se rellena en el compositor):

```
MUEVETE EMERGENCIA 21:42. Soy Ana. Viaje 1234 con Carlos P., Lada blanco, chapa 123456.
Ultima ubicacion: 22.4069,-79.9657 https://maps.google.com/?q=22.4069,-79.9657
Estoy en peligro. Llama al 106 y a mi telefono 55512345. Recorrido: https://<host>/f/AbC123
```

**Datos que se envían y a quién**

| Dato | Destino | Notas |
|---|---|---|
| `rol`, `solicitud_id`, `viaje_id`, `lat`, `lon`, `precision_m`, `modo`, `client_event_id`, `capturado_at` | Servidor (`fn_disparar_panico`) | Único dato que sale siempre |
| Nombre del titular, rol, hora, lat/lon, enlace, nombre + chapa del otro implicado | Contactos de emergencia con la app (push) | Sin teléfono, sin CI, sin dirección exacta del domicilio |
| Mismo bloque + enlace + 106 | Contactos sin app (SMS/WhatsApp prellenado) | Sale del teléfono del usuario, no del servidor |
| Evento completo + trazas de posición | Superadmin (`ventiq_superadmin`) | Sólo tras login de administrador |
| **Nada** | La contraparte del viaje | Alertar al agresor sería contraproducente |

**Si no hay red**: el evento se escribe en la outbox y se muestra:
> *"No hay datos. Guardamos la alerta: se envía sola cuando vuelva la conexión. Ahora mismo: envía el SMS o llama al 106. La app no puede llamar por ti."*

La posición que va en el SMS es la última conocida por el GPS (`location_provider`), con la hora en que se tomó (`hace 2 min`), nunca presentada como actual. El enlace en vivo no existe en ese caso (no hay servidor que emita token) y el SMS lo dice: `Recorrido: (sin enlace, no habia datos)`.

**Qué queda registrado**: `eventos_panico` (evento, rol, `modo`, `capturado_at`, `recibido_at`, `origen`), `eventos_panico_ubicaciones` (una fila cada 15 s, 30 min), `viaje_compartidos` (token y accesos), `notificaciones` (una por contacto con app) y el log de acciones (`dial_106`, `sms_abierto`, `enlace_copiado`, `falsa_alarma`) en `eventos_panico.acciones jsonb`. Nada de esto se borra automáticamente antes de 12 meses (§8.4).

**Criterios de aceptación**

- CA-F1-01: con el viaje `aceptada`, mantener 2 s crea **una** fila en `eventos_panico` (doble disparo no duplica: `client_event_id` UNIQUE).
- CA-F1-02: soltar antes de 2 s no crea nada y no muestra error.
- CA-F1-03: activado sin red, la fila existe en la outbox local y se envía al reconectar con el `capturado_at` original (< 60 s de diferencia con el momento real del toque).
- CA-F1-04: con 2 contactos, uno con app y uno sin app, el primero recibe push en < 10 s y el segundo aparece en el selector de SMS.
- CA-F1-05: la pantalla por defecto **no** cambia ni suena; en `modo='visible'` sí cambia y suena.
- CA-F1-06: "Fue un error" dentro de 10 s marca `estado='cancelado_falso'` y notifica "FALSA ALARMA" a los mismos contactos.
- CA-F1-07: la contraparte del viaje no recibe ninguna notificación ni puede leer el evento (RLS §4.7).
- CA-F1-08: la pantalla de pánico contiene literalmente "Muevete no sustituye a la policía".

---

### 3.2 F2 · Compartir viaje en vivo

**Objetivo**: que una persona de confianza vea el recorrido real, la chapa y el estado del viaje hasta que termine, y que ese acceso muera al terminar.

**Disparador**: botón "Compartir viaje" en la pantalla de viaje (cliente y chofer), o automático al disparar F1.

**UX paso a paso (copy exacto)**

1. Sheet:
   > **Compartir este viaje**
   > *Quien tenga el enlace puede ver el recorrido, la chapa y el nombre del chofer hasta que el viaje termine. No ve tu teléfono ni tu carnet. El enlace deja de funcionar al terminar el viaje.*
   > [ Enviar por WhatsApp ] [ Enviar por SMS ] [ Copiar enlace ]
   > ☑ *Avisar si el carro se detiene más de 10 minutos* (opt-in, por defecto activado)
   > *Muevete no sustituye a la policía. Si no contestas, que llamen al 106.*

2. Mensaje prellenado (WhatsApp/SMS):
   > *"Estoy en un viaje de Muevete. Mira el recorrido aquí: <host>/f/<token>. Si no contesto en 15 minutos, llama al 106."*

3. En el viaje queda una fila de estado:
   > *"Compartido con 2 personas · el enlace se apaga al terminar"* [ Dejar de compartir ]

4. Al terminar o cancelar el viaje, la app no tiene que hacer nada: el trigger `trg_cierre_seguridad` revoca el token (§4.6). En el chat del contacto, el enlace ya no abre datos.

5. Si el usuario intenta compartir **sin red**:
   > *"Sin datos no podemos crear el enlace en vivo. Te dejamos un mensaje con tus datos y tu última ubicación para que lo envíes por SMS."*
   > [ Enviar por SMS ] [ Copiar ]

   El texto estático incluye chofer, chapa, hora y un enlace de Google Maps con la última posición, y **no** se actualiza. Se dice explícitamente: *"Esto es una foto del momento, no un seguimiento."*

**Página pública** (Edge Function `seguridad-publica`, `verify_jwt = false`):

`GET https://<ref>.supabase.co/functions/v1/seguridad-publica/f/<token>`

- Token: 32 caracteres base62 (≈190 bits) generados con `gen_random_bytes(24)`; en la base sólo se guarda `sha256(token || pepper)`, nunca el token.
- Devuelve HTML mínimo (sin frameworks, < 20 KB) con mapa de `flutter_map`/Leaflet sobre tiles OSM, marcador del vehículo, línea del recorrido (últimos 200 puntos), estado, ETA y última actualización.
- Encabezados obligatorios: `Cache-Control: no-store`, `Referrer-Policy: no-referrer` (para que el token no se filtre al servidor de tiles), `X-Robots-Tag: noindex, nofollow`, CSP sin `unsafe-inline` salvo estilos propios.
- Campos visibles: nombre público del chofer (`Carlos P.`), chapa, marca/modelo/color, estado del viaje, posición del vehículo, ETA, destino (calle/zona, **no** número de casa), hora de última actualización, botón **"Llamar al 106"**, aviso de §2.2.
- **Nunca** visibles: teléfono, CI (ni parcial), correo, foto, nombre completo, importe, método de pago, historial.
- Actualización: sondeo cada 10 s (realtime no está confirmado en producción, [04 §1.2](04-diseno-tecnico.md)). El mapa dice *"Actualizado hace 12 s"*; si > 90 s → *"Sin actualización desde las 21:47. Esto puede significar que el teléfono se apagó o no tiene señal. Llama al 106."*
- Al terminar/cancelar: HTTP 410 con
  > *"Este viaje ya terminó. El enlace dejó de funcionar. Si no sabes nada de la persona, llama al 106."*
- Rate limit: 60 peticiones/minuto por token y 300/minuto por IP, con contador en `viaje_compartidos.accesos` y ventana en memoria de la función; al excederse, 429. No hay WAF: se documenta como limitación (§Riesgos).

**Permisos**: columna `permisos jsonb NOT NULL` con `{"ubicacion":true,"contraparte":true,"destino":true,"telefono":false,"ci":false}`. El MVP sólo crea enlaces `completo`; `solo_estado` (sin mapa, sólo "en viaje"/"terminado" y última hora) existe para el caso de una persona que no quiere dar su recorrido y queda como opción en fase 2. La función pública **filtra por `permisos`**, no por lo que la UI decida mostrar.

**Datos que se envían y a quién**: el titular crea el token; el portador del enlace (cualquiera) ve el subconjunto anterior; el servidor guarda quién lo creó, cuándo, cuántos accesos y desde qué IP truncada (`/24`), sólo para métricas y abuso.

**Si no hay red**: no se crea enlace (ver paso 5). Si el **contacto** no tiene datos, la página no carga; el SMS igual le llegó.

**Qué queda registrado**: `viaje_compartidos` (token hasheado, creador, permisos, `expira_at`, `revocado_at`, accesos, última IP truncada) y `viaje_ubicaciones` (posiciones del viaje para el mapa: se conservan 30 días). En `solicitudes_transporte.seguridad_snapshot` queda `{"compartido":true,"enlaces":1}` para las métricas de §7.

**Criterios de aceptación**

- CA-F2-01: crear enlace devuelve un token de 32 caracteres; en la base no aparece el token en claro.
- CA-F2-02: la página abre sin autenticación y muestra posición con ≤ 15 s de antigüedad.
- CA-F2-03: al completar o cancelar el viaje, la misma URL devuelve 410 en < 5 s y no se puede forzar con `?t=` prolongado.
- CA-F2-04: el HTML no contiene teléfono, CI ni nombre completo (test de contrato sobre el cuerpo).
- CA-F2-05: `Referrer-Policy: no-referrer` y `Cache-Control: no-store` presentes (test de cabeceras).
- CA-F2-06: dos accesos simultáneos de dos IP distintas no rompen ni invalidan el enlace (es por posesión).
- CA-F2-07: con el token revocado, la página no revela ni el nombre del chofer.

---

### 3.3 F3 · Contacto de emergencia obligatorio

**Objetivo**: que no exista un viaje sin un tercero identificable a quien avisar, y que ese tercero haya confirmado que puede recibir el aviso.

**Disparador**: alta/edición en *Mi seguridad → Contactos de emergencia* y **gate de servidor** en `fn_crear_solicitud` y `fn_tomar_viaje`.

**Reglas**
- Mínimo **1**, máximo **3** contactos por usuario.
- El contacto de prioridad 1 es obligatorio y debe estar `aceptado`.
- Puede ser un usuario de Muevete (canal push) o un teléfono sin app (canal SMS).
- Un contacto **no** puede ser el propio usuario (mismo teléfono normalizado ni misma cuenta).
- No se puede editar/borrar el último contacto validado sin agregar otro antes (si no, el usuario quedaría fuera de la plataforma en el siguiente intento de viaje).

**UX paso a paso (copy exacto)**

1. En "Completa tu perfil" (H1) y en *Mi seguridad*:
   > **Tu contacto de emergencia**
   > *Es a quien avisamos si activas la emergencia. Necesitamos al menos uno que responda para que puedas viajar. No lo usamos para publicidad ni se lo mostramos al chofer ni al pasajero.*

2. Formulario: nombre, parentesco (opcional), teléfono (+53 por defecto), y casilla *"Tiene Muevete"* que se autodetecta por teléfono.
   - Si existe cuenta: **"Enviar invitación en la app"** → el contacto recibe "Ana te quiere agregar como contacto de emergencia" [ Aceptar ] [ Rechazar ]. Queda `aceptado` con `aceptado_at` y `aceptado_ip`.
   - Si no existe: **"Enviar mensaje de confirmación"** → abre el compositor del teléfono con:
     > *"Hola, soy Ana. Me estoy registrando en Muevete y quiero que seas mi contacto de emergencia. Responde con el código 4821 para confirmar."*
     Después la app pide:
     > *"Escribe el código que te respondió"* · 4 dígitos · 3 intentos · el código vence en 24 h.
3. La UI es honesta sobre el alcance de la validación:
   > *"Confirmamos que este número responde. No podemos comprobar que sea de quien dice ser."*
4. Estado en la lista: `Aceptado · responde` (verde) / `Pendiente` (ámbar) / `Rechazado` (rojo, se puede borrar).
5. Intento de viajar sin contacto validado (pantalla bloqueante, antes de cotizar):
   > **Falta tu contacto de emergencia**
   > *Sin un contacto que responda no podemos avisar a nadie si te pasa algo. Por eso no puedes pedir ni tomar viajes todavía.*
   > [ Agregar contacto ] [ Entendido ]
6. Si el contacto rechaza o deja de responder (3 avisos de pánico sin `entregado` en 90 días), la app avisa al titular:
   > *"Mamá no ha recibido tus últimas alertas. Revisa su número o agrega otro contacto."*

**Datos que se envían y a quién**: el titular guarda `nombre`, `telefono` (normalizado E.164), `parentesco`, `prioridad`, `canal`; el contacto (si tiene cuenta) recibe una notificación con el nombre del titular y nada más. **El contacto nunca es visible para la contraparte del viaje, ni en el enlace compartido, ni en incidentes.**

**Si no hay red**: no se puede agregar ni validar (requiere servidor). El gate cachea el resultado `ok=true` por 24 h; publicar o tomar viaje ya requiere red de todos modos (el precio y la asignación son server-side).

**Qué queda registrado**: `contactos_emergencia` con `estado`, `aceptado_at`, `aceptado_ip`, `intentos_validacion`; en cada solicitud, el snapshot `seguridad_snapshot.contacto_ok=true` y `contacto_prioridad1` enmascarado (`••••345`), para poder medir cobertura histórica (§7).

**Criterios de aceptación**

- CA-F3-01: sin contacto `aceptado`, `fn_crear_solicitud` y `fn_tomar_viaje` lanzan `sin_contacto_emergencia` (probado llamando la RPC directo, sin UI).
- CA-F3-02: un contacto no puede ser el mismo usuario (mismo teléfono o misma cuenta) → error `contacto_invalido`.
- CA-F3-03: no se puede borrar el último contacto aceptado si no hay otro aceptado.
- CA-F3-04: código incorrecto 3 veces invalida la validación y hay que reenviar (no bloquea la cuenta).
- CA-F3-05: el contacto nunca aparece en el JSON de `fn_ficha_contraparte` ni en la página pública (test de contrato).
- CA-F3-06: agregar un contacto con la app genera una notificación y el cambio a `aceptado` se refleja en ≤ 10 s.

---

### 3.4 F4 · Verificación mutua visible

**Objetivo**: que antes de subir, cada parte pueda comparar a la persona y el vehículo con los datos que el servidor asignó — y que quede registro de que lo hizo.

**Disparador**: `fn_tomar_viaje` exitoso; se muestra al abrir el viaje activo y se queda visible en la fase "en camino" hasta la confirmación de abordaje.

**UX paso a paso (cliente, `ride_confirmed_screen.dart`)**

1. Tarjeta fija arriba:
   > **Revisa antes de subir**
   > [foto 96×96] **Carlos P.** · ⭐ 4,8 (127 viajes) · *Verificado por Muevete*
   > CI **••••••4821**  (sólo los últimos 4)
   > **Lada 2107 · blanco**
   > **CHAPA 123456**  (tipografía 40 px, el dato más grande de la tarjeta)
   > [ **Estoy en el carro correcto** ]  [ No coincide ]
   > *Si la chapa o la cara no coinciden, no subas. Toca "No coincide".*

2. "Estoy en el carro correcto" → registra `abordaje_pasajero_at` y `chapa_confirmada=true`. No bloquea nada (el pasajero puede no tocar); es evidencia.

3. "No coincide" → sheet:
   > **¿Qué no coincide?** [ La foto ] [ El nombre ] [ La chapa ] [ El carro ] [ Otra cosa ]
   > [ Cancelar el viaje y reportar ] [ Volver ]
   > *Cancelar por esto no tiene penalidad. Si estás en peligro, usa EMERGENCIA o llama al 106.*

   Al confirmar: cancela (si el viaje no empezó), crea un incidente `tipo='suplantacion'` o `'vehiculo_incorrecto'`, severidad media, y activa bloqueo de emparejamiento (§4.5).

**UX paso a paso (chofer, `active_ride_screen.dart` fase `goingToPickup`)**

1. Tarjeta:
   > **Confirma que es tu pasajero**
   > [foto] **Ana L.** · ⭐ 4,9 (43 viajes) · CI **••••••7321**
   > *Compara la cara con la persona que va a subir.*
   > ☐ **La persona coincide con la foto**
   > [ Iniciar viaje ] (deshabilitado hasta marcar la casilla)
   > [ No es esta persona ] (abre el mismo sheet de "no coincide" → no-show o incidente)

2. "Iniciar viaje" llama `fn_confirmar_abordaje(p_viaje_id, p_metodo)` (no un UPDATE directo): pone `viajes.estado=true`, `abordaje_at`, `abordaje_confirmado_por`, `chapa_confirmada`. De ahí en adelante corre el cobro de espera existente (`tiempo_espera_segundos`).

**De dónde salen los datos**: RPC `fn_ficha_contraparte(p_solicitud_id)` (`SECURITY DEFINER`), whitelist estricta:

| Campo | Chofer | Pasajero |
|---|---|---|
| Nombre público | `primer nombre + inicial` desde `drivers.name` | ídem desde `users.name` |
| Foto | `drivers.image` (foto de perfil; **nunca** los documentos KYC) | `users.image` / `users.photo_url` |
| CI parcial | últimos 4 de `drivers.carnet` | últimos 4 de `users.ci` |
| Vehículo | `vehiculos.marca`, `modelo`, `color`, `chapa` | — |
| Reputación | `avg(rating)`, `count(*)` de `valoraciones_viaje` | ídem |
| Verificación | `drivers.kyc AND drivers.revisado` | `users` con documentos aprobados (H1) |
| **Excluido** | teléfono, email, CI completa, documentos, dirección, wallet | ídem |

La RPC sólo responde si `auth.uid()` es participante de esa solicitud y el estado está entre `aceptada` y 72 h después del cierre (ventana para reportar). Devuelve `[]` con `motivo='fuera_de_ventana'` en otro caso.

**Si no hay red**: la ficha se cachea localmente al asignarse el viaje (SharedPreferences, 72 h). Sin caché:
> *"No pudimos verificar los datos del viaje. No subas si la chapa no coincide. Si algo no cuadra, llama al 106."*
El chofer puede iniciar con la confirmación *"No pude verificar los datos"*, que se registra como `abordaje_metodo='sin_verificacion'` y aparece marcada en superadmin. No se bloquea el viaje: bloquearlo obligaría al chofer a cancelar en la calle y empeoraría la situación.

**Qué queda registrado**: `viajes.abordaje_at`, `abordaje_metodo`, `abordaje_confirmado_por`, `chapa_confirmada`; `solicitudes_transporte.seguridad_snapshot` con `{"ficha_servida":true,"ci_parcial":true}`; y cada "No coincide" como incidente con severidad y tipo.

**Criterios de aceptación**

- CA-F4-01: la ficha nunca incluye teléfono, CI completa, correo ni URLs de documentos (test de contrato sobre el JSON).
- CA-F4-02: un tercero autenticado que no participa del viaje recibe `no_autorizado`.
- CA-F4-03: la CI se muestra con exactamente 4 dígitos visibles, aunque el documento tenga más o letras.
- CA-F4-04: el botón "Iniciar viaje" está deshabilitado hasta marcar la casilla de coincidencia; el servidor rechaza `fn_confirmar_abordaje` desde el chofer sin `chapa_confirmada` cuando la ficha se sirvió.
- CA-F4-05: "No coincide" crea incidente y bloqueo de emparejamiento en la misma transacción.
- CA-F4-06: a las 72 h 1 min del cierre, la ficha devuelve `fuera_de_ventana`.

---

### 3.5 F5 · Historial de incidentes y bloqueo

**Objetivo**: registrar lo que pasó, que alguien lo revise, sacar de la plataforma a quien reincide y evitar que víctima y agresor vuelvan a emparejarse.

**Disparador**
- Fin de viaje (pantalla de valoración): *"¿Algo salió mal en este viaje?"*
- *Mi viaje → Reportar un problema* (hasta 7 días después).
- "No coincide" de F4.
- No-show del chofer (1 toque, sin descripción).
- Superadmin puede crear un incidente a mano a partir de un reporte por otro canal.

**UX paso a paso (copy exacto)**

1. > **¿Qué pasó?**
   > [ Me robaron o intentaron robarme ] [ Me agredieron físicamente ] [ Me amenazaron ]
   > [ Me acosaron ] [ El chofer no era quien decía ] [ No era el carro de la chapa ]
   > [ No apareció / no me esperó ] [ Me cobró más de lo que decía la app ] [ Otra cosa ]

2. Severidad automática por tipo (el usuario no la elige): robo con violencia, agresión física, amenaza, acoso sexual, secuestro → `critica`; suplantación, vehículo incorrecto, acoso verbal, extorsión → `alta`; no-show, cobro abusivo → `baja/media`.

3. > **Cuéntanos qué pasó** · mínimo 20 caracteres · *"Lo que escribas lo lee el equipo de Muevete, no la otra persona."*
   > [ Agregar una foto ] (máx. 2; aviso: *"No se puede borrar después de enviar. No incluyas datos de otras personas."*)
   > ☑ **No quiero que me vuelvan a asignar con esta persona** (marcado por defecto si la severidad es alta o crítica)
   > [ Enviar reporte ]

4. Confirmación:
   > *"Recibimos tu reporte #1234. Lo revisa el equipo de Muevete en horario laboral (lunes a viernes, 9:00–17:00). Si estás en peligro ahora, llama al 106. Si es urgente, avísale también a tu contacto de emergencia."*
   > [ Llamar al 106 ] [ Ver mi reporte ]

5. Estado en *Mi seguridad → Mis reportes*: `En revisión` / `Confirmado` / `Descartado`, con la resolución en texto llano si la hay.

6. Chofer, no-show (1 toque, desde el viaje):
   > **El pasajero no apareció**
   > *Si cancelas por esto no te cobramos comisión. Queda registrado. Después de 3 casos en 30 días, el pasajero no puede pedir viajes por 7 días.*
   > [ Cancelar y reportar ] [ Seguir esperando ]

**Ciclo del incidente y bloqueo**

```
reportado ──(48 h hábiles)──> en_revision ──> confirmado ──> bloqueo (automático o manual)
     │                              └──────> descartado
     └──(crítico: 24 h)──> en_revision
```

- **Revisión**: en `ventiq_superadmin` (nueva bandeja, §6.3). El revisor ve: reporte, ficha de ambas partes, viaje, trazas de posición, pánico asociado, enlaces, reportes previos del mismo par y del mismo sujeto. Checklist obligatorio antes de resolver (§6.3.1).
- **Bloqueo automático** (sin esperar al revisor, para cubrir el hueco del fin de semana):
  - 2 incidentes `confirmado` con severidad alta o crítica en 90 días → `bloqueo` 30 días.
  - 1 incidente `confirmado` crítico → bloqueo indefinido con revisión obligatoria.
  - 3 no-show confirmados en 30 días → restricción de 7 días (no es bloqueo de seguridad).
  - **Nunca** se bloquea por un reporte sin confirmar.
- **Bloqueo de emparejamiento** (`emparejamientos_bloqueados`): cuando el reportante marca la casilla o la severidad es alta, el par usuario↔chofer no vuelve a emparejarse nunca, aunque nadie los haya sancionado. Es la medida más rápida, barata y difícil de abusar (sólo afecta a ese par).
- **Lista negra compartida con choferes** (pedido del usuario): se implementa como **señal** en la tarjeta de viaje disponible, no como listado navegable:
  > ⚠ *Pasajero con reportes de seguridad confirmados*
  Sin nombre extra, sin teléfono, sin descripción. Motivo: un listado con datos personales es un arma de acoso y un problema de privacidad; la señal resuelve el 100 % del caso de uso (el chofer decide no tomarlo) sin exponer a nadie.
- **Apelación**: el bloqueado ve en la app
  > *"Tu cuenta no puede pedir viajes hasta el 12/12/2026. Motivo: reportes de seguridad confirmados. Si crees que es un error, escríbenos a <contacto_soporte>."*
  y el superadmin puede revocar el bloqueo con motivo obligatorio.

**Datos que se envían y a quién**: el contenido del reporte, la foto y la identidad del reportante sólo los ve el superadmin. La contraparte **no** ve el reporte ni el nombre de quien reportó (evita represalias); sólo ve su bloqueo y el motivo genérico. La señal del chofer no incluye datos.

**Si no hay red**: el reporte va a la outbox (con las fotos en cola aparte, se suben al reconectar) y se muestra *"Guardamos tu reporte. Se envía cuando vuelva la conexión."* El no-show también se encola.

**Qué queda registrado**: `incidentes` (tipo, severidad, estado, descripción, evidencia, fechas), `bloqueos`, `emparejamientos_bloqueados`, y en superadmin la traza de revisión (`resuelto_por`, `resolucion`, `revisado_at`). Retención: 2 años (§8.4).

**Criterios de aceptación**

- CA-F5-01: reportar en < 7 días funciona; a los 8 días la UI no ofrece reportar y la RPC devuelve `fuera_de_ventana`.
- CA-F5-02: un reporte no confirmado **no** bloquea a nadie.
- CA-F5-03: el segundo incidente confirmado de severidad alta en 90 días crea bloqueo de 30 días en la misma transacción de confirmación.
- CA-F5-04: el bloqueado recibe `usuario_bloqueado` al intentar publicar y al intentar tomar viaje.
- CA-F5-05: el par bloqueado no aparece en `fn_viajes_disponibles` para ese chofer ni el chofer aparece como candidato para esa pasajera.
- CA-F5-06: la contraparte no puede leer el incidente ni la identidad del reportante (RLS).
- CA-F5-07: el motivo mostrado al bloqueado no contiene la descripción del reporte ni datos del reportante.

---

### 3.6 F6 · Marcado directo al 106

**Objetivo**: que llamar a la policía sea lo más rápido posible y no dependa de datos ni de la app.

**Disparador**: botón dentro del sheet de emergencia (F1), en la pantalla de pánico visible, en la página pública de F2 y en el hub *Mi seguridad*.

**UX paso a paso (copy exacto)**

1. Botón grande, primero en la pantalla de emergencia y en el hub:
   > [ **Llamar al 106** ] (rojo, > 56 px de alto)
   > *Se abrirá el marcador de tu teléfono. Pulsa el botón verde para llamar.*
   > *Muevete no puede marcar por ti.*

2. `launchUrl(Uri.parse('tel:106'))` con `url_launcher` (ya usado en la app). Si el dispositivo no tiene marcador (tablet sin SIM, emulador):
   > *"Este teléfono no puede hacer llamadas. Busca un teléfono fijo o pide ayuda a alguien cerca."*

3. También se puede llamar al 106 desde la página pública que ve el contacto.

**Por qué no se marca solo**: Android e iOS exigen confirmación del usuario para una llamada; usar `CALL_PHONE` y marcar automáticamente implica un permiso sensible, riesgo de revisión en Play y, sobre todo, llamadas accidentales. Si el negocio lo quiere, es fase 2 (§9) con decisión explícita de riesgo.

**Datos que se envían y a quién**: ninguno. Se registra sólo el toque (`acciones: [{"tipo":"dial_106","at":"..."}]`) para métricas de uso. La app **no** sabe si la llamada se completó.

**Si no hay red**: funciona igual (llamada de voz).

**Qué queda registrado**: el toque en el evento de pánico o en un evento sintético si se llamó desde el hub sin pánico activo (`eventos_panico.modo='solo_106'`).

**Criterios de aceptación**

- CA-F6-01: el botón del 106 es visible en ≤ 2 toques desde cualquier pantalla de viaje activo.
- CA-F6-02: el número sale de `configuracion_seguridad.numeros_emergencia->>'policia'` (default `106`), no está escrito en el Dart.
- CA-F6-03: en un dispositivo sin marcador, se muestra el mensaje de fallback y no se cierra la app.
- CA-F6-04: el copy incluye "Muevete no puede marcar por ti" (test de copy).

---

## 4. Diseño de datos

> **DDL orientativo**, no ejecutable tal cual sin revisión: va en `inventtia_muevete/docs/migrations/037_taxi_seguridad.sql`, sigue el estilo de [`034_taxi_rls_tarifas.sql`](../../inventtia_muevete/docs/migrations/034_taxi_rls_tarifas.sql) (`BEGIN/COMMIT`, `DROP POLICY IF EXISTS`, `muevete.is_superadmin()`, `muevete.set_updated_at()`), y **no se aplica contra producción desde este entorno** (los MCP de Supabase son de sólo lectura, ver [06](06-aplicar-migraciones.md)).
> Todo es aditivo: tablas nuevas y columnas nuevas con default. Las apps viejas siguen funcionando con el flag `taxi_precio_fijo_activo=false`.

### 4.1 Configuración (una fila)

```sql
CREATE TABLE IF NOT EXISTS muevete.configuracion_seguridad (
  id                          smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  numeros_emergencia          jsonb NOT NULL DEFAULT '{"policia":"106"}'::jsonb,
  contacto_soporte            text  NOT NULL DEFAULT '',
  horario_revision            text  NOT NULL DEFAULT 'L-V 09:00-17:00',
  max_contactos               smallint NOT NULL DEFAULT 3,
  minutos_vida_enlace         integer  NOT NULL DEFAULT 120,
  minutos_tracking_panico     integer  NOT NULL DEFAULT 30,
  segundos_muestreo_panico    integer  NOT NULL DEFAULT 15,
  umbral_bloqueo_incidentes   smallint NOT NULL DEFAULT 2,
  dias_ventana_reincidencia   integer  NOT NULL DEFAULT 90,
  dias_bloqueo_temporal       integer  NOT NULL DEFAULT 30,
  no_show_umbral              smallint NOT NULL DEFAULT 3,
  dias_restriccion_no_show    integer  NOT NULL DEFAULT 7,
  dias_ventana_reporte        integer  NOT NULL DEFAULT 7,
  horas_sla_critico           integer  NOT NULL DEFAULT 24,
  horas_sla_normal            integer  NOT NULL DEFAULT 48,
  dias_retencion_ubicaciones  integer  NOT NULL DEFAULT 30,
  meses_retencion_incidentes  integer  NOT NULL DEFAULT 24,
  modo_panico_default         text NOT NULL DEFAULT 'discreto'
                                CHECK (modo_panico_default IN ('discreto','visible')),
  actualizado_at              timestamptz NOT NULL DEFAULT now()
);

INSERT INTO muevete.configuracion_seguridad (id) VALUES (1) ON CONFLICT (id) DO NOTHING;
```

Todos los umbrales de este documento salen de aquí: cambiarlos no requiere recompilar. El número de policía **no** se escribe en Dart (CA-F6-02).

### 4.2 Contactos de emergencia

```sql
CREATE TABLE IF NOT EXISTS muevete.contactos_emergencia (
  id                   bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid            uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  nombre               text NOT NULL CHECK (char_length(btrim(nombre)) BETWEEN 2 AND 60),
  telefono             text NOT NULL CHECK (telefono ~ '^\+[0-9]{8,15}$'),  -- E.164
  parentesco           text,
  prioridad            smallint NOT NULL DEFAULT 2 CHECK (prioridad BETWEEN 1 AND 3),
  canal                text NOT NULL DEFAULT 'sms' CHECK (canal IN ('push','sms','whatsapp')),
  contacto_uuid        uuid REFERENCES auth.users(id) ON DELETE SET NULL,   -- si tiene cuenta
  estado               text NOT NULL DEFAULT 'pendiente'
                         CHECK (estado IN ('pendiente','aceptado','rechazado','revocado')),
  codigo_hash          text,          -- validación por SMS (código de 4 dígitos)
  codigo_expira_at     timestamptz,
  token_hash           text,          -- invitación por enlace (Edge Function)
  token_expira_at      timestamptz,
  aceptado_at          timestamptz,
  aceptado_ip          inet,
  intentos_validacion  smallint NOT NULL DEFAULT 0,
  avisos_sin_entrega   smallint NOT NULL DEFAULT 0,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);

-- Un teléfono por usuario; un solo "principal" aceptado; no se puede repetir el token
CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_user_tel_uidx
  ON muevete.contactos_emergencia (user_uuid, telefono) WHERE estado <> 'revocado';
CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_principal_uidx
  ON muevete.contactos_emergencia (user_uuid) WHERE prioridad = 1 AND estado = 'aceptado';
CREATE UNIQUE INDEX IF NOT EXISTS contactos_emergencia_token_uidx
  ON muevete.contactos_emergencia (token_hash) WHERE token_hash IS NOT NULL;
CREATE INDEX IF NOT EXISTS contactos_emergencia_contacto_idx
  ON muevete.contactos_emergencia (contacto_uuid) WHERE contacto_uuid IS NOT NULL;
```

El teléfono se guarda normalizado (`+53…`) por un helper en Dart (`seguridad_service.dart`) y se revalida con el `CHECK`: si el usuario escribe `55512345`, el cliente agrega `+53` antes de enviar.

### 4.3 Pánico

```sql
CREATE TABLE IF NOT EXISTS muevete.eventos_panico (
  id                          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  client_event_id             uuid NOT NULL UNIQUE,   -- idempotencia del disparo
  solicitud_id                bigint NOT NULL REFERENCES muevete.solicitudes_transporte(id) ON DELETE RESTRICT,
  viaje_id                    bigint REFERENCES muevete.viajes(id) ON DELETE SET NULL,
  user_uuid                   uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol                         text NOT NULL CHECK (rol IN ('cliente','chofer')),
  modo                        text NOT NULL DEFAULT 'discreto'
                                CHECK (modo IN ('discreto','visible','solo_106')),
  origen                      text NOT NULL DEFAULT 'boton'
                                CHECK (origen IN ('boton','accesibilidad','automatico','solo_106')),
  lat                         double precision CHECK (lat BETWEEN -90 AND 90),
  lon                         double precision CHECK (lon BETWEEN -180 AND 180),
  precision_m                 real,
  capturado_at                timestamptz NOT NULL,   -- reloj del teléfono
  recibido_at                 timestamptz NOT NULL DEFAULT now(),  -- reloj del servidor
  estado                      text NOT NULL DEFAULT 'activo'
                                CHECK (estado IN ('activo','cancelado_falso','gestionado','cerrado')),
  acciones                    jsonb NOT NULL DEFAULT '[]'::jsonb,
  notificados                 jsonb NOT NULL DEFAULT '[]'::jsonb,   -- [{nombre,canal,enlace}]
  contacto_ppal_enmascarado   text,                                  -- '••••345'
  atendido_por                uuid,
  atendido_at                 timestamptz,
  created_at                  timestamptz NOT NULL DEFAULT now(),
  updated_at                  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS eventos_panico_abiertos_idx
  ON muevete.eventos_panico (created_at DESC) WHERE estado = 'activo';
CREATE INDEX IF NOT EXISTS eventos_panico_user_idx ON muevete.eventos_panico (user_uuid, created_at DESC);

CREATE TABLE IF NOT EXISTS muevete.eventos_panico_ubicaciones (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  evento_id      bigint NOT NULL REFERENCES muevete.eventos_panico(id) ON DELETE CASCADE,
  lat            double precision NOT NULL,
  lon            double precision NOT NULL,
  precision_m    real,
  velocidad_mps  real,
  capturado_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS eventos_panico_ubicaciones_evento_idx
  ON muevete.eventos_panico_ubicaciones (evento_id, capturado_at);
```

### 4.4 Enlaces de viaje compartido y posiciones del viaje

```sql
CREATE TABLE IF NOT EXISTS muevete.viaje_compartidos (
  id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  solicitud_id          bigint NOT NULL REFERENCES muevete.solicitudes_transporte(id) ON DELETE CASCADE,
  viaje_id              bigint REFERENCES muevete.viajes(id) ON DELETE SET NULL,
  creado_por_uuid       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol                   text NOT NULL DEFAULT 'cliente' CHECK (rol IN ('cliente','chofer')),
  token_hash            text NOT NULL UNIQUE,      -- sha256(token||pepper); NUNCA el token
  alcance               text NOT NULL DEFAULT 'completo' CHECK (alcance IN ('completo','solo_estado')),
  permisos              jsonb NOT NULL DEFAULT
                          '{"ubicacion":true,"contraparte":true,"destino":true,"telefono":false,"ci":false}'::jsonb,
  expira_at             timestamptz NOT NULL,
  revocado_at           timestamptz,
  motivo_revocacion     text,
  accesos               integer NOT NULL DEFAULT 0,
  ultimo_acceso_at      timestamptz,
  ultima_ip_truncada    inet,          -- /24, sólo para detectar abuso
  created_at            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS viaje_compartidos_vigentes_idx
  ON muevete.viaje_compartidos (token_hash) WHERE revocado_at IS NULL;
CREATE INDEX IF NOT EXISTS viaje_compartidos_solicitud_idx
  ON muevete.viaje_compartidos (solicitud_id);

CREATE TABLE IF NOT EXISTS muevete.viaje_ubicaciones (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  solicitud_id  bigint NOT NULL REFERENCES muevete.solicitudes_transporte(id) ON DELETE CASCADE,
  rol           text NOT NULL CHECK (rol IN ('cliente','chofer')),
  lat           double precision NOT NULL,
  lon           double precision NOT NULL,
  precision_m   real,
  capturado_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS viaje_ubicaciones_sol_idx
  ON muevete.viaje_ubicaciones (solicitud_id, capturado_at DESC);
```

**Por qué `viaje_ubicaciones` y no reusar `place`/`track_place_history`**: `place` y `track_place_history` sólo se escriben si `driverId != null` (`background_service.dart:592-628`). El cliente nunca publica posición. Para que el enlace muestre algo cuando el chofer apaga el teléfono, el pasajero publica cada 20 s **sólo si el viaje está compartido**; el enlace usa la posición del chofer como principal y la del pasajero como respaldo. `track_place_history` (histórico global del chofer) no se expone nunca a un tercero.

### 4.5 Incidentes, bloqueos y emparejamientos

```sql
CREATE TABLE IF NOT EXISTS muevete.incidentes (
  id                     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  solicitud_id           bigint REFERENCES muevete.solicitudes_transporte(id) ON DELETE SET NULL,
  viaje_id               bigint REFERENCES muevete.viajes(id) ON DELETE SET NULL,
  reportado_por_uuid     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  rol_reporta            text NOT NULL CHECK (rol_reporta IN ('cliente','chofer')),
  contraparte_uuid       uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  contraparte_driver_id  bigint REFERENCES muevete.drivers(id) ON DELETE SET NULL,
  tipo                   text NOT NULL CHECK (tipo IN (
                           'robo_con_violencia','robo_sin_violencia','agresion_fisica','amenaza',
                           'acoso_sexual','acoso_verbal','suplantacion','vehiculo_incorrecto',
                           'no_show_pasajero','cobro_abusivo','extorsion','otro')),
  severidad              text NOT NULL CHECK (severidad IN ('baja','media','alta','critica')),
  descripcion            text NOT NULL CHECK (char_length(descripcion) BETWEEN 20 AND 2000),
  evidencia              jsonb NOT NULL DEFAULT '[]'::jsonb,  -- [{tipo:'foto',path,sha256,at}]
  estado                 text NOT NULL DEFAULT 'reportado'
                           CHECK (estado IN ('reportado','en_revision','confirmado','descartado','escalado')),
  solicita_no_emparejar  boolean NOT NULL DEFAULT false,
  posicion_al_reportar   jsonb,          -- {lat,lon,precision_m,at}; nunca se muestra a la contraparte
  revisado_por           uuid,
  revisado_at            timestamptz,
  resolucion             text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  updated_at             timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT incidentes_no_autoreporte
    CHECK (contraparte_uuid IS NULL OR contraparte_uuid <> reportado_por_uuid)
);

CREATE INDEX IF NOT EXISTS incidentes_bandeja_idx
  ON muevete.incidentes (estado, severidad, created_at DESC);
CREATE INDEX IF NOT EXISTS incidentes_sujeto_idx
  ON muevete.incidentes (contraparte_uuid, created_at DESC) WHERE contraparte_uuid IS NOT NULL;
CREATE INDEX IF NOT EXISTS incidentes_driver_idx
  ON muevete.incidentes (contraparte_driver_id, created_at DESC) WHERE contraparte_driver_id IS NOT NULL;
-- Evita reportes duplicados del mismo tipo por el mismo viaje
CREATE UNIQUE INDEX IF NOT EXISTS incidentes_sin_duplicados_uidx
  ON muevete.incidentes (reportado_por_uuid, viaje_id, tipo)
  WHERE viaje_id IS NOT NULL AND estado <> 'descartado';

CREATE TABLE IF NOT EXISTS muevete.bloqueos (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid       uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_id       bigint REFERENCES muevete.drivers(id) ON DELETE CASCADE,
  tipo_bloqueo    text NOT NULL CHECK (tipo_bloqueo IN
                    ('automatico_temporal','administrativo','permanente','restriccion_no_show')),
  motivo          text NOT NULL,
  incidente_id    bigint REFERENCES muevete.incidentes(id) ON DELETE SET NULL,
  vigente_desde   timestamptz NOT NULL DEFAULT now(),
  vigente_hasta   timestamptz,          -- NULL = indefinido
  creado_por      uuid,
  creado_motivo   text,
  revocado_por    uuid,
  revocado_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bloqueos_un_solo_sujeto CHECK (num_nonnulls(user_uuid, driver_id) = 1)
);

CREATE INDEX IF NOT EXISTS bloqueos_user_vigentes_idx
  ON muevete.bloqueos (user_uuid) WHERE revocado_at IS NULL;
CREATE INDEX IF NOT EXISTS bloqueos_driver_vigentes_idx
  ON muevete.bloqueos (driver_id) WHERE revocado_at IS NULL;

CREATE TABLE IF NOT EXISTS muevete.emparejamientos_bloqueados (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_uuid     uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  driver_id     bigint NOT NULL REFERENCES muevete.drivers(id) ON DELETE CASCADE,
  motivo        text NOT NULL,
  incidente_id  bigint REFERENCES muevete.incidentes(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT emparejamientos_bloqueados_uidx UNIQUE (user_uuid, driver_id)
);
```

### 4.6 Columnas, funciones y triggers

**Columnas nuevas en tablas existentes** (aditivas):

```sql
ALTER TABLE muevete.solicitudes_transporte
  ADD COLUMN IF NOT EXISTS seguridad_snapshot jsonb;   -- {contacto_ok, contacto_masked, compartido, enlaces, ficha_servida}

ALTER TABLE muevete.viajes
  ADD COLUMN IF NOT EXISTS abordaje_at           timestamptz,
  ADD COLUMN IF NOT EXISTS abordaje_metodo       text,   -- 'ficha' | 'cache' | 'sin_verificacion'
  ADD COLUMN IF NOT EXISTS abordaje_confirmado_por uuid,
  ADD COLUMN IF NOT EXISTS chapa_confirmada      boolean;
```

**RPCs** (todas `SECURITY DEFINER`, `SET search_path = muevete, public`, `REVOKE ALL FROM anon` y `GRANT EXECUTE TO authenticated`; las de superadmin exigen `muevete.is_superadmin()` dentro):

| RPC | Firma | Devuelve | Quién la llama |
|---|---|---|---|
| `fn_gate_seguridad` | `(p_user_uuid uuid, p_driver_id bigint DEFAULT NULL)` | `jsonb {ok, motivos[]}` | `fn_crear_solicitud`, `fn_tomar_viaje`, la app para pintar el gate |
| `fn_iniciar_validacion_contacto` | `(p_contacto_id bigint)` | `jsonb {codigo, expira_at}` | App del titular (F3) |
| `fn_confirmar_contacto` | `(p_contacto_id bigint, p_codigo text DEFAULT NULL)` | `jsonb {estado}` | Titular (SMS) o contacto (aceptación en app) |
| `fn_disparar_panico` | `(p_solicitud_id bigint, p_client_event_id uuid, p_lat float8, p_lon float8, p_precision_m real DEFAULT NULL, p_modo text DEFAULT 'discreto', p_compartir boolean DEFAULT true, p_capturado_at timestamptz DEFAULT now())` | `jsonb {evento_id, enlace, contactos[]}` | App (cliente o chofer) |
| `fn_registrar_posicion_panico` | `(p_evento_id bigint, p_lat float8, p_lon float8, p_precision_m real DEFAULT NULL, p_velocidad_mps real DEFAULT NULL)` | `void` | App, cada 15 s (F1) |
| `fn_crear_enlace_viaje` | `(p_solicitud_id bigint, p_alcance text DEFAULT 'completo')` | `jsonb {token, url, expira_at, enlace_id}` | App (F2 y F1) |
| `fn_revocar_enlace_viaje` | `(p_enlace_id bigint)` | `void` | App (botón "dejar de compartir") |
| `fn_ficha_contraparte` | `(p_solicitud_id bigint)` | `jsonb` (whitelist §3.4) | App de ambos |
| `fn_confirmar_abordaje` | `(p_viaje_id bigint, p_chapa_confirmada boolean, p_metodo text)` | `jsonb` | Chofer |
| `fn_registrar_posicion_viaje` | `(p_solicitud_id bigint, p_lat float8, p_lon float8, p_precision_m real)` | `void` | App del pasajero si el viaje está compartido |
| `fn_reportar_incidente` | `(p_solicitud_id bigint, p_tipo text, p_descripcion text, p_evidencia jsonb DEFAULT '[]', p_no_emparejar boolean DEFAULT false)` | `jsonb {incidente_id, estado, severidad}` | App de ambos |
| `fn_no_show_pasajero` | `(p_viaje_id bigint)` | `jsonb` | Chofer |
| `fn_estado_contraparte` | `(p_user_uuid uuid, p_driver_id bigint)` | `jsonb {alerta_seguridad bool, bloqueado bool}` | `fn_viajes_disponibles` (H3) y `fn_ficha_contraparte` |
| `fn_resolver_incidente` | `(p_incidente_id bigint, p_estado text, p_resolucion text)` | `jsonb` | Superadmin |
| `fn_revocar_bloqueo` | `(p_bloqueo_id bigint, p_motivo text)` | `void` | Superadmin |

**`fn_disparar_panico` — cuerpo (resumido, es la pieza crítica)**

```sql
CREATE OR REPLACE FUNCTION muevete.fn_disparar_panico(
  p_solicitud_id bigint, p_client_event_id uuid, p_lat double precision,
  p_lon double precision, p_precision_m real DEFAULT NULL, p_modo text DEFAULT 'discreto',
  p_compartir boolean DEFAULT true, p_capturado_at timestamptz DEFAULT now()
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = muevete, public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_sol muevete.solicitudes_transporte%ROWTYPE;
  v_evento bigint;
  v_enlace jsonb;
  v_contactos jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_autenticado' USING ERRCODE = 'P0100'; END IF;

  SELECT * INTO v_sol FROM muevete.solicitudes_transporte WHERE id = p_solicitud_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'solicitud_no_existe' USING ERRCODE = 'P0101'; END IF;

  -- Sólo los dos participantes del viaje
  IF v_sol.user_id <> v_uid
     AND NOT EXISTS (SELECT 1 FROM muevete.drivers d
                     WHERE d.id = v_sol.driver_id AND d.uuid = v_uid) THEN
    RAISE EXCEPTION 'no_participante' USING ERRCODE = 'P0102';
  END IF;

  -- Ventana válida: viaje aceptado, o hasta 10 min después de completado
  IF NOT (v_sol.estado = 'aceptada'
          OR (v_sol.estado = 'completada' AND EXISTS (
                SELECT 1 FROM muevete.viajes v
                WHERE v.solicitud_id = p_solicitud_id
                  AND v.updated_at > now() - interval '10 minutes'))) THEN
    RAISE EXCEPTION 'viaje_no_activo' USING ERRCODE = 'P0103';
  END IF;

  -- Idempotencia: el mismo client_event_id no duplica el evento
  SELECT id INTO v_evento FROM muevete.eventos_panico
   WHERE client_event_id = p_client_event_id;
  IF v_evento IS NOT NULL THEN
    RETURN jsonb_build_object('evento_id', v_evento, 'duplicado', true);
  END IF;

  INSERT INTO muevete.eventos_panico (
    client_event_id, solicitud_id, viaje_id, user_uuid, rol, modo, origen,
    lat, lon, precision_m, capturado_at
  ) VALUES (
    p_client_event_id, p_solicitud_id,
    (SELECT id FROM muevete.viajes WHERE solicitud_id = p_solicitud_id ORDER BY id DESC LIMIT 1),
    v_uid,
    CASE WHEN v_sol.user_id = v_uid THEN 'cliente' ELSE 'chofer' END,
    p_modo, 'boton', p_lat, p_lon, p_precision_m, p_capturado_at
  ) RETURNING id INTO v_evento;

  -- Enlace compartido automático (si el viaje sigue vivo)
  IF p_compartir AND v_sol.estado = 'aceptada' THEN
    v_enlace := muevete.fn_crear_enlace_viaje(p_solicitud_id, 'completo');
  END IF;

  -- Push a contactos que tengan la app (el trigger notificaciones_push hace el envío)
  INSERT INTO muevete.notificaciones (user_uuid, tipo, titulo, mensaje, data)
  SELECT c.contacto_uuid, 'panico_contacto',
         'Alerta de emergencia de ' || left(u.name, 20),
         'Activó la emergencia a las ' ||
           to_char(p_capturado_at AT TIME ZONE 'America/Havana', 'HH24:MI') ||
           '. Abre la app para ver la ubicación.',
         jsonb_build_object('evento_id', v_evento, 'solicitud_id', p_solicitud_id,
                            'lat', p_lat, 'lon', p_lon,
                            'enlace', v_enlace->>'url', 'url', v_enlace->>'url')
    FROM muevete.contactos_emergencia c
    JOIN muevete.users u ON u.uuid = c.user_uuid
   WHERE c.user_uuid = v_uid AND c.estado = 'aceptado' AND c.contacto_uuid IS NOT NULL;

  -- Lista para el SMS prellenado (se devuelve sólo al titular)
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'nombre', c.nombre, 'telefono', c.telefono, 'canal', c.canal,
           'enlace', v_enlace->>'url') ORDER BY c.prioridad), '[]'::jsonb)
    INTO v_contactos
    FROM muevete.contactos_emergencia c
   WHERE c.user_uuid = v_uid AND c.estado = 'aceptado';

  UPDATE muevete.eventos_panico
     SET notificados = v_contactos,
         contacto_ppal_enmascarado = (
           SELECT '••••' || right(regexp_replace(c.telefono, '\D', '', 'g'), 3)
             FROM muevete.contactos_emergencia c
            WHERE c.user_uuid = v_uid AND c.estado = 'aceptado'
            ORDER BY c.prioridad LIMIT 1)
   WHERE id = v_evento;

  RETURN jsonb_build_object('evento_id', v_evento, 'enlace', v_enlace, 'contactos', v_contactos);
END $$;

REVOKE ALL ON FUNCTION muevete.fn_disparar_panico(bigint,uuid,double precision,double precision,real,text,boolean,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION muevete.fn_disparar_panico(bigint,uuid,double precision,double precision,real,text,boolean,timestamptz) TO authenticated;
```

**`fn_crear_enlace_viaje` — token y hash**

```sql
-- 24 bytes aleatorios → 32 caracteres base64 sin relleno (≈190 bits)
v_token  := translate(encode(gen_random_bytes(24), 'base64'), '+/=', 'xyz');
v_pepper := coalesce(
  (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'seguridad_token_pepper'),
  'CAMBIAR-EN-DESPLIEGUE');
v_hash   := encode(extensions.digest(v_token || v_pepper, 'sha256'), 'hex');
INSERT INTO muevete.viaje_compartidos (solicitud_id, creado_por_uuid, rol, token_hash, expira_at)
VALUES (p_solicitud_id, auth.uid(), v_rol, v_hash,
        now() + make_interval(mins => (SELECT minutos_vida_enlace FROM muevete.configuracion_seguridad WHERE id = 1)))
RETURNING id INTO v_enlace_id;
-- El token en claro se devuelve UNA vez y no se guarda nunca.
```

**Gating de servidor** (lo que hace cumplir G-01/G-06):

```sql
CREATE OR REPLACE FUNCTION muevete.fn_gate_seguridad(
  p_user_uuid uuid, p_driver_id bigint DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = muevete, public AS $$
DECLARE v_motivos text[] := '{}';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM muevete.contactos_emergencia
                  WHERE user_uuid = p_user_uuid AND prioridad = 1 AND estado = 'aceptado') THEN
    v_motivos := array_append(v_motivos, 'sin_contacto_emergencia');
  END IF;
  IF EXISTS (SELECT 1 FROM muevete.bloqueos
              WHERE (user_uuid = p_user_uuid OR (p_driver_id IS NOT NULL AND driver_id = p_driver_id))
                AND revocado_at IS NULL
                AND (vigente_hasta IS NULL OR vigente_hasta > now())) THEN
    v_motivos := array_append(v_motivos, 'bloqueado');
  END IF;
  RETURN jsonb_build_object('ok', cardinality(v_motivos) = 0, 'motivos', to_jsonb(v_motivos));
END $$;
```

`fn_crear_solicitud` (H3) debe empezar con:

```sql
IF NOT (muevete.fn_gate_seguridad(auth.uid())->>'ok')::boolean THEN
  RAISE EXCEPTION 'sin_contacto_emergencia' USING ERRCODE = 'P0110';
END IF;
```

y `fn_tomar_viaje` con `fn_gate_seguridad(auth.uid(), v_driver_id)` + `fn_emparejamiento_bloqueado(v_sol.user_id, v_driver_id)`.

**Trigger de cierre** (cumple G-04):

```sql
CREATE OR REPLACE FUNCTION muevete.fn_cierre_seguridad(p_solicitud_id bigint, p_motivo text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = muevete, public AS $$
BEGIN
  UPDATE muevete.viaje_compartidos
     SET revocado_at = now(), motivo_revocacion = p_motivo
   WHERE solicitud_id = p_solicitud_id AND revocado_at IS NULL;
  UPDATE muevete.solicitudes_transporte
     SET seguridad_snapshot = coalesce(seguridad_snapshot, '{}'::jsonb)
                               || jsonb_build_object('cerrado_at', now(), 'motivo_cierre', p_motivo)
   WHERE id = p_solicitud_id;
END $$;

CREATE OR REPLACE FUNCTION muevete.trg_viaje_completado_seguridad()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = muevete, public AS $$
BEGIN
  IF NEW.completado AND NOT coalesce(OLD.completado, false) AND NEW.solicitud_id IS NOT NULL THEN
    PERFORM muevete.fn_cierre_seguridad(NEW.solicitud_id, 'viaje_completado');
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION muevete.trg_solicitud_cerrada_seguridad()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = muevete, public AS $$
BEGIN
  IF NEW.estado IN ('cancelada','completada','expirada')
     AND OLD.estado IS DISTINCT FROM NEW.estado THEN
    PERFORM muevete.fn_cierre_seguridad(NEW.id, 'solicitud_' || NEW.estado);
  END IF;
  RETURN NEW;
END $$;
```

Los triggers `updated_at` de cada tabla nueva usan `muevete.set_updated_at()` (ya existe, 002), igual que en `031`.

### 4.7 RLS: quién puede leer qué

Patrón del proyecto: `ENABLE ROW LEVEL SECURITY` + `REVOKE ALL ... FROM anon` + políticas explícitas + `superadmin_all_*` con `muevete.is_superadmin()` ([034](../../inventtia_muevete/docs/migrations/034_taxi_rls_tarifas.sql)).

| Tabla | `anon` | `authenticated` (política) | `superadmin` |
|---|---|---|---|
| `contactos_emergencia` | nada | `user_uuid = auth.uid()` (SELECT/INSERT/UPDATE/DELETE) + `contacto_uuid = auth.uid()` (sólo SELECT, para aceptar la invitación) | ALL |
| `eventos_panico` | nada | INSERT sólo vía RPC; SELECT sólo `user_uuid = auth.uid()` | ALL |
| `eventos_panico_ubicaciones` | nada | INSERT/SELECT sólo si el evento es propio | ALL |
| `viaje_compartidos` | nada (lee la Edge Function con `service_role`) | SELECT/INSERT/DELETE sólo `creado_por_uuid = auth.uid()`; **nunca** `token_hash` a la app (se sirve por RPC) | ALL |
| `viaje_ubicaciones` | nada | INSERT si es participante del viaje y el viaje está aceptado; SELECT sólo sus propios viajes | ALL |
| `incidentes` | nada | INSERT vía RPC; SELECT sólo `reportado_por_uuid = auth.uid()` (la contraparte **no** ve la acusación) | ALL |
| `bloqueos` | nada | SELECT sólo el propio (`user_uuid = auth.uid()` o `driver_id = muevete.get_my_driver_id()`); sin INSERT/UPDATE | ALL |
| `emparejamientos_bloqueados` | nada | nada (sólo lo consulta el servidor) | ALL |
| `configuracion_seguridad` | nada | SELECT (para copy y umbrales) | ALL |

Además: **`GRANT SELECT (columnas)` por columna** en `eventos_panico` para que la app no pueda leer `atendido_por` ni `notificados` si no debe; y `REVOKE` de `INSERT/UPDATE/DELETE` directo en `viaje_compartidos` para forzar las RPC.

**Regla de oro**: las escrituras sensibles (pánico, incidentes, bloqueos, tokens) pasan por RPC `SECURITY DEFINER`; las tablas quedan en sólo lectura para las apps, igual que el principio rector del flujo de precio fijo ([PLAN §3](PLAN-IMPLEMENTACION.md)).

### 4.8 Evidencia en Storage

Bucket privado `muevete-evidencias`:

- Ruta: `{solicitud_id}/{reportado_por_uuid}/{uuid}.jpg`.
- INSERT: sólo si `auth.uid()` es el primer segmento y existe un incidente propio en los últimos 7 días. Tamaño máximo 5 MB, MIME `image/jpeg|png`. No se permiten videos ni audio.
- SELECT: sólo superadmin (URL firmada de 5 min generada por la consola). La app del reportante puede volver a ver su propia foto durante 7 días.
- Nada de URLs públicas. En `incidentes.evidencia` se guarda `path` + `sha256`, no la URL.

### 4.9 Retención y borrado

| Dato | Retención | Mecanismo |
|---|---|---|
| `eventos_panico` + ubicaciones | 12 meses | Borrado por job; los ubicaciones 90 días |
| `viaje_compartidos` | 6 meses (token ya revocado) | Índice + job |
| `viaje_ubicaciones` | 30 días | Job diario |
| `incidentes` + evidencia | 24 meses | Job; la evidencia se borra a los 12 meses salvo incidente `critico` |
| `contactos_emergencia` | vigencia de la cuenta + 30 días | `ON DELETE CASCADE` |
| Cuenta eliminada | 30 días y se anonimiza (uuid→NULL donde se pueda) | Proceso manual en superadmin |

Los jobs: si `pg_cron` está disponible se programan ahí; si no, una RPC `fn_purgar_seguridad()` llamada por la consola al abrir (idempotente). Se documenta la dependencia (Supuesto S-07).

---

## 5. Flujos integrados con el viaje de precio fijo

### 5.1 Línea de tiempo

| Momento | Estado | Qué hace el sistema | Si falla |
|---|---|---|---|
| **Antes de pedir** | — | `fn_gate_seguridad`: contacto validado + sin bloqueo. La app muestra el gate bloqueante antes de cotizar. | No deja continuar; no es un error silencioso |
| **Publicar** | `pendiente` | `fn_crear_solicitud` valida el gate y guarda `seguridad_snapshot` | RPC lanza `sin_contacto_emergencia` / `usuario_bloqueado` |
| **Tomar** | `aceptada` | `fn_tomar_viaje` valida gate del chofer + emparejamiento bloqueado; devuelve `viaje_id` | El chofer ve "no puedes tomar este viaje"; no se le dice por qué si es por un reporte |
| **Al asignarse** | `aceptada` | La app carga `fn_ficha_contraparte`; pinta la tarjeta de verificación; cachea 72 h | Sin caché → aviso honesto y `abordaje_metodo='sin_verificacion'` |
| **En camino** | `aceptada` | Botón de pánico disponible. Enlace de compartir disponible. | Pánico offline → outbox |
| **Abordar** | `aceptada` | Chofer marca coincidencia → `fn_confirmar_abordaje` → `viajes.estado=true`, `abordaje_at` | Si no hay red: se registra local y se sincroniza; la espera se cobra desde `abordaje_at` (o desde el ingreso manual) |
| **En viaje** | `viajes.estado=true` | Pánico, compartir, 106, posiciones cada 5–10 s (`background_service`) + 20 s del pasajero si hay enlace | — |
| **No-show** | `aceptada` | Tras `gracia_espera_min`, el chofer puede cancelar y reportar: `fn_no_show_pasajero` | Sin red: se encola |
| **Terminar** | `completada` | `fn_completar_viaje` (H3) → trigger `trg_viaje_completado_seguridad` revoca tokens | Si el trigger falla, el token vive hasta `expira_at` (máximo 2 h) |
| **Cancelar** | `cancelada` | `fn_cancelar_solicitud` (H3) → trigger revoca tokens | Ídem |
| **Post-viaje** | — | Ventana de 72 h para ver la ficha y 7 días para reportar. Ventana de pánico de 10 min. | — |

### 5.2 Ciclo de un incidente

```
[ reporte en la app ]  →  incidentes.estado='reportado'
        │                        │
        │                        ├─ severidad crítica → cola prioritaria (SLA 24 h hábiles)
        │                        └─ al confirmar el 2.º reporte alto/crítico en 90 días → bloqueo automático 30 días
        ▼
[ bandeja superadmin ]  →  'en_revision'  →  'confirmado' | 'descartado'
                                                │
                    ┌───────────────────────────┼────────────────────────────┐
                    ▼                           ▼                            ▼
        bloqueo (auto/manual)        emparejamiento bloqueado       sin bloqueo, queda historial
        + notificación al sujeto     (si se pidió o severidad alta)  + métricas
                    │
                    ▼
        apelación → 'revocado' con motivo
```

Reglas duras del ciclo:

1. **Nadie es bloqueado por un reporte sin confirmar.** El bloqueo automático sólo mira incidentes `confirmado`.
2. **La contraparte no ve el reporte.** Sólo el resultado (bloqueo) y el motivo genérico.
3. **El bloqueo de emparejamiento es inmediato** y no requiere revisión: es la protección mínima mientras el revisor mira el caso (crítico en fin de semana).
4. **Una víctima nunca pierde el acceso por reportar.** Reportar no penaliza ni baja el rating.
5. **El revisor no puede ver la identidad del reportante en la cola anónima** si el reporte fue "anónimo"? — no existe reporte anónimo en el MVP: la identidad del reportante es obligatoria para el revisor (y para evitar abuso), pero nunca se le muestra a la contraparte.

---

## 6. Operación sin 24/7

### 6.1 La cadena de respuesta (lo que realmente pasa)

```
Persona en peligro
   │
   ├─(1) Llamada al 106 ......................... funciona sin datos, la hace la persona
   ├─(2) Contacto de emergencia (push + SMS) .... funciona si el contacto mira el teléfono
   ├─(3) Enlace de viaje compartido ............. el contacto ve el recorrido si lo abre
   └─(4) Registro en el servidor ................ existe aunque nadie lo mire en ese momento
                                                       │
                                                       ▼
                                     Se revisa en horario laboral (L–V 9:00–17:00)
```

**No hay nadie mirando en vivo.** Eso no se puede maquillar: el copy de la app lo dice (§2.2) y el equipo lo asume. Lo que se automatiza cubre el hueco entre el incidente y la revisión humana.

### 6.2 Qué se puede automatizar (y qué no)

| Automatizable | No automatizable |
|---|---|
| Push al contacto con ubicación y enlace (trigger existente) | Decidir si una persona está en peligro |
| Registro inmutable del evento con hora y posición | Llamar a la policía por ella |
| Revocación del enlace al cerrar el viaje | Llamar al usuario para preguntar qué pasó |
| Bloqueo automático por umbral de incidentes confirmados | Calibrar la gravedad de un texto libre |
| Bloqueo de emparejamiento por par | Juzgar una apelación |
| Restricción por no-show reiterado | Revisar una foto de evidencia |
| Purga por retención | Negociar con la policía |
| Resumen diario al administrador (08:30) | Cobertura nocturna |

### 6.3 Consola de superadmin (H6, pero con contrato definido aquí)

Pantalla nueva `ventiq_superadmin/lib/screens/muevete/muevete_seguridad_screen.dart` con 3 pestañas, siguiendo el patrón de `muevete_kyc_screen.dart` / `muevete_trips_screen.dart`:

1. **Pánicos**: lista con badge de no revisados, filtro por estado, mapa del recorrido del evento, botón "Marcar como gestionado" (con nota) y "Cerrar".
2. **Incidentes**: bandeja ordenada por severidad y antigüedad, contador de SLA vencido, detalle con ficha de ambos, viaje, trazas, evidencia, reportes previos del par y del sujeto. Acciones: `en_revision`, `confirmado` (elige bloqueo), `descartado`, `escalado`.
3. **Bloqueos**: vigentes, revocados, con motivo y quién los creó; botón "Revocar" con motivo obligatorio.

Además, tarjeta en `muevete_dashboard_screen.dart`: pánicos de las últimas 24 h, incidentes pendientes, SLA vencidos, bloqueos vigentes.

### 6.3.1 Checklist obligatorio del revisor (para que "revisar" no sea un clic)

Antes de marcar `confirmado`:

- [ ] ¿El viaje existe y ambos participantes son quienes dicen? (`solicitud`, `viaje`, `drivers.uuid`, `users.uuid`)
- [ ] ¿Las horas del relato son compatibles con `created_at`, `abordaje_at`, `completado`?
- [ ] ¿Hay trazas de posición (`viaje_ubicaciones`, `track_place_history`) que contradigan o confirmen el desvío/parada?
- [ ] ¿Hay pánico o enlace asociado? ¿La hora del pánico coincide?
- [ ] ¿Hay reportes previos del mismo par o del mismo sujeto? (reincidencia)
- [ ] ¿La evidencia (si hay) es legible y pertinente?
- [ ] ¿La severidad asignada por la app es la correcta tras leer el texto?
- [ ] Decisión escrita en `resolucion` (mínimo 20 caracteres), sin copy interno.

### 6.4 Protocolo operativo mínimo

| Situación | Qué hace el equipo | Plazo |
|---|---|---|
| Pánico `activo` | Se ve en la consola; **no se contacta a nadie** (no hay canal ni personal). Se conserva. | Sin SLA de respuesta; SLA de revisión 24 h hábiles |
| Incidente crítico | Revisar y resolver; si se confirma, bloquear y notificar al sujeto | 24 h hábiles |
| Incidente alto/medio | Revisar, confirmar o descartar | 48 h hábiles |
| Incidente bajo (no-show, cobro) | Revisar por lote | 5 días hábiles |
| Apelación de bloqueo | Revisar con el mismo checklist | 5 días hábiles |
| Resumen diario | Correo/WhatsApp al administrador con: pánicos, incidentes nuevos, SLA vencidos, bloqueos | 08:30 L–V |

Si el equipo crece y quiere 24/7, es fase 2 (§9) y no cambia el diseño de datos: sólo agrega turnos y un SLA.

---

## 7. Métricas de seguridad

Se miden por mes natural y se revisan a los 1, 3 y 6 meses. Todas se pueden calcular con SQL sobre las tablas de §4; no se agrega instrumentación nueva.

```sql
-- M-01 · Tasa de incidentes por 1 000 viajes (30 días)
WITH v AS (SELECT count(*) n FROM muevete.viajes WHERE created_at >= now() - interval '30 days'),
     i AS (SELECT count(*) n FROM muevete.incidentes WHERE created_at >= now() - interval '30 days')
SELECT round(1000.0 * i.n / nullif(v.n, 0), 2) AS incidentes_por_1000 FROM v, i;

-- M-02 · % de viajes con contacto de emergencia validado al publicar
SELECT round(100.0 * count(*) FILTER (WHERE (seguridad_snapshot->>'contacto_ok')::boolean) / count(*), 1)
FROM muevete.solicitudes_transporte
WHERE created_at >= now() - interval '30 days';

-- M-03 · % de viajes compartidos y enlaces accedidos
SELECT round(100.0 * count(DISTINCT c.solicitud_id) / nullif(count(DISTINCT s.id), 0), 1) AS pct_compartidos,
       round(100.0 * count(DISTINCT c.solicitud_id) FILTER (WHERE c.accesos > 0)
             / nullif(count(DISTINCT c.solicitud_id), 0), 1) AS pct_enlace_abierto
FROM muevete.solicitudes_transporte s
LEFT JOIN muevete.viaje_compartidos c ON c.solicitud_id = s.id
WHERE s.created_at >= now() - interval '30 days';

-- M-04 · Tiempo de alerta: del toque a la creación del evento (mediana, segundos)
SELECT percentile_cont(0.5) WITHIN GROUP (
         ORDER BY extract(epoch FROM (recibido_at - capturado_at))) AS mediana_retraso_s,
       count(*) FILTER (WHERE extract(epoch FROM (recibido_at - capturado_at)) > 60) AS con_retraso_gt_60s
FROM muevete.eventos_panico
WHERE created_at >= now() - interval '30 days';

-- M-05 · Reincidencia: sujetos con ≥ 2 incidentes confirmados en 90 días
SELECT count(*) AS sujetos_reincidentes FROM (
  SELECT coalesce(contraparte_uuid::text, 'driver:' || contraparte_driver_id::text) sujeto
  FROM muevete.incidentes
  WHERE estado = 'confirmado' AND created_at >= now() - interval '90 days'
  GROUP BY 1 HAVING count(*) >= 2
) t;

-- M-06 · Cobertura del gate: usuarios activos con contacto principal aceptado
SELECT round(100.0 * count(*) FILTER (WHERE c.id IS NOT NULL) / count(*), 1) AS pct_con_contacto
FROM muevete.users u
LEFT JOIN muevete.contactos_emergencia c
  ON c.user_uuid = u.uuid AND c.prioridad = 1 AND c.estado = 'aceptado';

-- M-07 · Tiempo de reporte: del cierre del viaje al reporte (horas, mediana)
SELECT percentile_cont(0.5) WITHIN GROUP (
         ORDER BY extract(epoch FROM (i.created_at - v.updated_at)) / 3600.0) AS mediana_horas
FROM muevete.incidentes i
JOIN muevete.viajes v ON v.id = i.viaje_id
WHERE i.created_at >= now() - interval '90 days';
```

| Métrica | Objetivo inicial | Para qué sirve |
|---|---|---|
| M-01 incidentes/1 000 viajes | Medir; no fijar meta el primer mes | Si sube, puede ser más reporte (bueno) o más delito (malo): se cruza con M-07 |
| M-02 % con contacto | 100 % (es gate) | Detecta fugas del gate o cuentas viejas |
| M-03 % compartidos | > 25 % | Adopción real de F2 |
| M-04 retraso de alerta | < 10 s mediana | Calidad del offline y de la red |
| M-05 reincidencia | Tendencia a la baja | Efectividad de los bloqueos |
| M-06 cobertura del gate | 100 % | Salud del onboarding |
| M-07 tiempo de reporte | < 12 h mediana | Si es alto, el momento de reportar está mal puesto en la UX |

**Advertencia de interpretación**: estos números no miden seguridad objetiva, miden **uso y registro**. Un mes con 0 incidentes puede significar "nadie reporta". Por eso M-03 y M-07 se leen juntos: si el reporte es fácil y aun así no hay reportes, el problema es de confianza, no de seguridad.

---

## 8. Privacidad

Marco: en Cuba no hay una ley integral de protección de datos personales vigente; se aplica **minimización por diseño**, consentimiento informado (documentos legales de H1) y retención acotada. Este plan debe quedar reflejado en la **política de privacidad** que redacta otro compañero: los puntos de §8.3 son la lista que esa política tiene que cubrir.

### 8.1 Qué dato expone cada feature

| Feature | Dato personal | A quién se expone | Minimización aplicada |
|---|---|---|---|
| F1 pánico | Nombre, rol, ubicación, hora, chapa y nombre del otro | Contactos elegidos por el usuario + servidor + superadmin | Sin teléfono, sin CI, sin dirección de casa; el enlace caduca |
| F2 enlace | Posición del vehículo, chapa, nombre público del chofer, destino aproximado | Cualquiera con el token | Token 190 bits, hash en BD, caduca al cerrar, sin PII, `no-store`/`no-referrer` |
| F3 contacto | Nombre y teléfono de un tercero | Servidor + superadmin | El contacto acepta (consentimiento); nunca se muestra a la contraparte; teléfono enmascarado en métricas |
| F4 verificación | Foto, nombre parcial, CI parcial de ambos | La contraparte del viaje, sólo durante el viaje + 72 h | CI = últimos 4; nombre = nombre + inicial; foto de perfil (nunca documentos) |
| F5 incidentes | Relato, foto, identidad del reportante, posición | Superadmin | La contraparte no ve el reporte; la foto no es pública; se borra a los 12 meses |
| F6 106 | Nada | — | Sólo se registra el toque |

### 8.2 Reglas transversales

1. **CI parcial siempre**: `••••` + últimos 4. La CI completa y los documentos sólo los ve el KYC del superadmin (H1).
2. **Sin teléfono en enlaces ni en terceros**: el número del pasajero/chofer se muestra sólo a la contraparte y sólo durante el viaje activo (+15 min), con la advertencia previa. Es un cambio respecto del comportamiento actual ([`viajes.telefono`](PLAN-IMPLEMENTACION.md)), que hoy se muestra sin límite de tiempo.
3. **Ubicación sólo durante el viaje**: `viaje_ubicaciones` se escribe sólo con viaje aceptado y se borra a los 30 días. `track_place_history` (histórico del chofer) **no** se expone nunca a terceros.
4. **Tokens con expiración y hash**: nunca se guarda el token en claro; se revoca al cerrar el viaje; un token filtrado no sirve después de 2 h como máximo.
5. **Logs sin PII**: no se registran teléfonos, CI ni coordenadas en `debugPrint`/logs de Edge Function; sólo IDs.
6. **Notificaciones push sin datos sensibles**: el cuerpo dice "Alerta de emergencia de Ana"; la ubicación va en `data` y se lee dentro de la app.
7. **Consentimiento del tercero**: el contacto de emergencia acepta explícitamente; si rechaza, se borra. Es el único caso en el que Muevete guarda datos de alguien que no es usuario (o es usuario pero no viaja).
8. **Derecho de supresión**: borrar la cuenta borra contactos y tokens; los incidentes se anonimizan (uuid a NULL) pero se conservan 24 meses por seguridad del resto de usuarios. Se documenta como excepción por interés legítimo de seguridad.

### 8.3 Lo que la política de privacidad debe recoger (para coordinación)

1. Finalidad de cada dato de seguridad (avisar, verificar, sancionar) y base legal/consentimiento.
2. Que el enlace compartido lo puede abrir cualquiera que lo tenga (no hay control de acceso por identidad).
3. Que el contacto de emergencia es un dato de tercero y que se le pide aceptación.
4. Que el pánico se registra aunque el usuario no lo cancele, y por cuánto tiempo.
5. Que el historial de posiciones se conserva 30 días y el de incidentes 24 meses.
6. Que la verificación mutua muestra CI parcial y que la completa queda en KYC.
7. Que el bloqueo se comunica al sujeto con motivo genérico y derecho de apelación.
8. Que no hay operador 24/7 ni respuesta de emergencia.
9. Que el 106 es un servicio externo y Muevete no intermedia la llamada.
10. Cómo ejercer supresión y qué se conserva por seguridad (con el plazo).

---

## 9. Fase 2: lo rechazado y su costo de reapertura

| Rechazado | Por qué ahora no | Coste de reabrirlo | Cuándo tendría sentido |
|---|---|---|---|
| **PIN de abordaje de 4 dígitos** | Duplica F4 (chapa + foto + confirmación) y agrega fricción a un usuario que puede no tener batería/datos; un PIN no impide subir a un carro equivocado, sólo detecta después. | 1–2 semanas: columna `pin_hash`, generación en `fn_tomar_viaje`, pantalla del chofer, validación offline, tests. | Si los datos muestran ≥ 1 caso/mes de "montó el carro equivocado" pese a F4 |
| **Operador humano 24/7** | No hay personal; 24/7 real son ≥ 3 personas en turnos + consola + protocolo + SLA. Es un costo recurrente, no una feature. | 1 mes de implantación + costo mensual de 3 FTE + formación. El diseño de datos ya lo soporta (`eventos_panico.atendido_por/at`). | Si hay ingresos que lo financien y volumen > ~1 000 viajes/día |
| **Grabación de audio del viaje** | Riesgo legal y de consentimiento (grabar sin avisar puede ser delito), costo de almacenamiento, batería, permisos de micrófono y revisión de Play. | 4–6 semanas + criterio legal + consentimiento doble + cifrado en reposo + política de escucha. | Sólo con base legal clara y protocolo de acceso a las grabaciones |
| **Geocercas de riesgo** | No hay datos históricos (0 incidentes registrados hoy); mantener polígonos es trabajo operativo continuo y estigmatiza barrios. | 3–4 semanas + 6 meses de datos + revisión mensual de polígonos + riesgo reputacional. | A los 6–12 meses, con M-01/M-07 por zona |
| **SMS automático servidor→teléfono** | Requiere proveedor (Twilio/MessageBird), costo por mensaje y entregabilidad a Cuba no garantizada; sanciones/limitaciones de proveedores de EE. UU. | 2–3 semanas de integración + costo variable + número internacional. | Si el negocio asume costo por SMS y se valida entrega real a +53 |
| **Auto-llamada al 106** | `CALL_PHONE` + marcado automático: riesgo de revisión de Play y de llamadas accidentales. | 1 semana + decisión de riesgo del negocio. | Sólo si el negocio firma la decisión por escrito |
| **Botón físico/BLE o atajo de hardware** | Requiere hardware y emparejamiento; el atajo de Android (3 toques) ya cubre parte. | 3–4 semanas. | Si se detecta que el botón en pantalla no se alcanza en la práctica |

Ninguna de estas reaperturas cambia el modelo de datos de §4: por eso el diseño deja `permisos`, `estado`, `acciones` y `evidencia` como `jsonb` extensibles.

---

## 10. Requisitos funcionales (RS) con criterios de aceptación

Numeración estable para trazabilidad con H2 y con el QA de H8.

**RS-01 · Contacto de emergencia validado obligatorio**
```gherkin
Dado un usuario autenticado sin contacto de emergencia aceptado
Cuando intenta publicar un viaje o tomar uno
Entonces el servidor responde sin_contacto_emergencia y la app muestra la pantalla "Falta tu contacto de emergencia"
Y el intento no crea filas en solicitudes_transporte ni en viajes
```

**RS-02 · Validación del contacto**
```gherkin
Dado un contacto de prioridad 1 en estado pendiente
Cuando el titular envía el SMS con el código y escribe el código que le respondieron
Entonces el contacto pasa a aceptado con aceptado_at e ip
Y el usuario puede viajar en su siguiente intento
```

**RS-03 · Gate de servidor infranqueable desde el cliente**
```gherkin
Dado un cliente con la app modificada
Cuando llama directamente a fn_crear_solicitud sin contacto de emergencia
Entonces la RPC lanza sin_contacto_emergencia (no hay camino alternativo)
```

**RS-04 · Verificación mutua antes de abordar**
```gherkin
Dado un viaje recién aceptado
Cuando el pasajero abre el viaje
Entonces ve foto, nombre, vehículo, chapa en tamaño destacado y CI parcial del chofer
Y la RPC fn_ficha_contraparte no devuelve teléfono, CI completa ni documentos
Y el chofer no puede iniciar el viaje sin marcar que la persona coincide
```

**RS-05 · Detección de contraparte incorrecta**
```gherkin
Dado un pasajero frente a un vehículo cuya chapa no coincide
Cuando toca "No coincide" y confirma
Entonces se cancela el viaje sin penalidad, se crea un incidente y se bloquea el emparejamiento de ese par
```

**RS-06 · Pánico en ≤ 2 segundos**
```gherkin
Dado un viaje aceptado o en curso
Cuando el usuario mantiene presionado el botón EMERGENCIA 2 segundos
Entonces se crea exactamente un evento de pánico
Y se crea o reutiliza un enlace compartido
Y los contactos con la app reciben una notificación en menos de 10 segundos
```

**RS-07 · Pánico sin red**
```gherkin
Dado un viaje activo sin conexión
Cuando el usuario activa la emergencia
Entonces el evento queda en la outbox local con su hora de captura
Y al volver la conexión se envía con el mismo client_event_id
Y no se duplica el evento aunque el envío se reintente
```

**RS-08 · Falsa alarma**
```gherkin
Dado un pánico activo hace menos de 10 segundos
Cuando el usuario toca "Fue un error"
Entonces el evento pasa a cancelado_falso y los contactos notificados reciben "FUE UNA FALSA ALARMA"
```

**RS-09 · El pánico no alerta al agresor**
```gherkin
Dado un pánico disparado por el pasajero
Cuando la contraparte (chofer) consulta sus notificaciones y el viaje
Entonces no aparece ninguna referencia al evento de pánico
```

**RS-10 · Enlace de viaje compartido**
```gherkin
Dado un viaje aceptado
Cuando el usuario comparte el enlace por WhatsApp o SMS
Entonces el contacto abre una página sin login y ve recorrido, chapa y estado con menos de 15 segundos de antigüedad
Y la página no contiene teléfono, CI ni nombre completo
```

**RS-11 · El enlace muere con el viaje**
```gherkin
Dado un enlace vigente
Cuando el viaje se completa o se cancela
Entonces la misma URL devuelve 410 en menos de 5 segundos y no revela datos del chofer
```

**RS-12 · Privacidad de la página pública**
```gherkin
Dado cualquier token válido
Cuando se inspeccionan las cabeceras y el HTML
Entonces aparecen Cache-Control: no-store, Referrer-Policy: no-referrer y X-Robots-Tag: noindex
Y no hay teléfono, CI, correo ni URL de documentos
```

**RS-13 · Marcado al 106**
```gherkin
Dado cualquier pantalla de viaje activo
Cuando el usuario toca "Llamar al 106"
Entonces se abre el marcador del teléfono con el número configurado
Y se muestra el aviso "Muevete no puede marcar por ti"
```

**RS-14 · Reporte de incidente**
```gherkin
Dado un viaje terminado hace menos de 7 días
Cuando el usuario reporta un tipo de incidente con descripción de al menos 20 caracteres
Entonces se crea un incidente en estado reportado con severidad asignada por el servidor
Y el reportante ve el número de reporte y el plazo de revisión
```

**RS-15 · Ventana de reporte**
```gherkin
Dado un viaje terminado hace más de 7 días
Cuando el usuario intenta reportar
Entonces la RPC responde fuera_de_ventana y la UI no ofrece el botón
```

**RS-16 · Bloqueo por reincidencia**
```gherkin
Dado un usuario con un incidente confirmado de severidad alta hace 10 días
Cuando el supervisor confirma un segundo incidente alto
Entonces se crea un bloqueo vigente 30 días en la misma transacción
Y el bloqueado recibe usuario_bloqueado al intentar viajar
```

**RS-17 · El reporte no se filtra a la contraparte**
```gherkin
Dado un incidente reportado por el pasajero contra el chofer
Cuando el chofer consulta la API o la app
Entonces no puede leer el incidente, la descripción ni la identidad del reportante
```

**RS-18 · Bloqueo de emparejamiento**
```gherkin
Dado un par usuario-chofer con bloqueo de emparejamiento
Cuando el chofer abre la lista de viajes disponibles
Entonces ese viaje no aparece, aunque el chofer cumpla todos los demás requisitos
```

**RS-19 · Copy sin promesas**
```gherkin
Dado el texto de todas las pantallas de seguridad
Cuando corre el test de copy en CI
Entonces no aparece "seguro", "protegido", "garantizado", "a salvo", "24/7" ni "respuesta inmediata"
Y la pantalla de emergencia contiene "Muevete no sustituye a la policía"
```

**RS-20 · Retención**
```gherkin
Dado un viaje con posiciones registradas hace 31 días
Cuando corre fn_purgar_seguridad
Entonces las filas de viaje_ubicaciones de ese viaje ya no existen
Y los incidentes confirmados siguen disponibles
```

---

## Supuestos

- **S-01 · El flujo de precio fijo está implementado como dice el plan.** F1/F2/F4 se enganchan a `solicitudes_transporte` (estados `pendiente|aceptada|completada|cancelada|expirada`) y a `viajes.estado` (`false` = en camino, `true` = en viaje). Si H4/H5 cambian esos nombres, este plan se ajusta en la implementación, no en el diseño.
- **S-02 · Numeración de migración.** Según [PLAN-IMPLEMENTACION.md §7](PLAN-IMPLEMENTACION.md), H2 es dueño de `037_taxi_seguridad.sql`. [04-diseno-tecnico.md](04-diseno-tecnico.md) usa 036/037 para RPCs y 038 para el hardening; hay conflicto de numeración entre documentos. Se asume 037 para seguridad y, si colisiona, se renombra sin cambiar el contenido (Supuesto del Lead a resolver en H0).
- **S-03 · El hardening de RLS llega antes o junto con H2.** Varias garantías (no exponer teléfono/ubicación, que la contraparte no lea el incidente) **dependen** de cerrar `drivers_see_solicitudes USING(true)`, `place` y `solicitudes_select_own_client OR true` ([04 §4.3](04-diseno-tecnico.md)). Sin eso, la app puede cumplir, pero la API filtra.
- **S-04 · El push funciona.** El trigger `notificaciones_push` + Edge Function externa `send-push-notification` existen en producción ([05 §2.4](05-sincronizacion-bd-repo.md)). Si no, el canal automático cae a SMS prellenado y se degrada M-04.
- **S-05 · No hay proveedor de SMS servidor→teléfono** en el MVP. Toda alerta a un contacto sin app es un SMS **prellenado** que el usuario envía con un toque. Se dice en la UI.
- **S-06 · La Edge Function pública se puede desplegar** (Deno + `--no-verify-jwt`). Si no hay permisos de despliegue en este ciclo, F2 queda degradada: enlace no disponible, sólo "ficha por SMS" (§3.2 paso 5) y se recorta la promesa a "compartir datos del viaje".
- **S-07 · `pg_cron` no está confirmado.** La purga se implementa como RPC invocable; si hay cron, se programa.
- **S-08 · H1 puebla CI, documentos y `contactos_emergencia`.** F4 necesita `users.ci` y `drivers.carnet` con datos; si están vacíos, la ficha muestra "CI no registrada" y el revisor no puede identificar. H2 debe añadir un `CHECK`/gate que impida viajar sin carnet (H1 ya lo exige en su pantalla de perfil).
- **S-09 · Los 41 usuarios actuales estarán bloqueados por H1** hasta completar perfil. Este plan no les da periodo de gracia.
- **S-10 · No hay operación 24/7** ni intención de crearla en el MVP. Todo el diseño asume revisión en horario laboral.
- **S-11 · La hora de referencia es `America/Havana`** para los textos al usuario; las tablas guardan `timestamptz` en UTC.
- **S-12 · No se agregan dependencias nuevas a la app** salvo las que ya están (`url_launcher`, `vibration`, `audioplayers`, `supabase_flutter`, `shared_preferences`). Compartir usa `Clipboard` + `wa.me`/`sms:` en vez de `share_plus`.

---

## Riesgos

| # | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| R-S1 | **Falsa sensación de seguridad**: la gente llama menos al 106 porque "la app avisa" | Alta | Crítico | Copy de §2.2 en todas las pantallas; nunca decir "estás protegido"; el botón 106 es el primero, no el último |
| R-S2 | **El contacto no mira el teléfono** y la alerta no sirve de nada | Alta | Alto | Pedir 2 contactos, validar respuesta, avisar al titular cuando un contacto no entrega (F3 paso 6); aceptar la limitación en la UI |
| R-S3 | **Falsos positivos de pánico** saturan a los contactos (y al admin) | Media | Medio | Modo discreto + mantener 2 s + ventana de cancelación + revisión a los 5 falsos, sin bloqueo automático |
| R-S4 | **Abuso de la lista negra / reportes falsos** para vetar a un chofer o a una pasajera | Media | Alto | Bloqueo sólo tras confirmación humana; el reportante es visible al revisor; umbral de 2 confirmados; emparejamiento bloqueado sólo para el par; nunca se bloquea por 1 reporte |
| R-S5 | **Android/iOS matan la app** y el enlace se congela; el contacto cree que está todo bien | Alta | Alto | El enlace muestra "sin actualización desde las HH:MM" en grande y sugiere llamar al 106; foreground service ya existente; posición del pasajero como respaldo |
| R-S6 | **Token filtrado** (reenvío del enlace, historial, captura) | Media | Medio | 190 bits, hash en BD, vida 2 h, revocación al cerrar, sin PII, `no-referrer` |
| R-S7 | **Edge Function pública** se convierte en superficie de ataque (enumeración de tokens, DoS) | Baja | Alto | Token aleatorio (no secuencial), rate limit por token/IP, 429, `no-store`, logs sin PII, sólo lectura |
| R-S8 | **RLS sin endurecer**: cualquier autenticado lee solicitudes y posiciones | Media-alta | Crítico | Es el riesgo #1 del plan global ([01 §4.3](01-analisis-tecnico.md)); H2 no libera sin el hardening o sin aceptar por escrito que la API filtra |
| R-S9 | **Costo de la revisión humana** supera la capacidad del equipo (1 persona) | Media | Medio | Cola priorizada, checklist, digest diario, bloqueo automático para lo crítico; medir minutos por caso |
| R-S10 | **Datos de terceros** (contacto de emergencia) sin base legal clara | Media | Medio | Aceptación explícita del contacto, minimización, retención, inclusión en la política de privacidad (§8.3) |
| R-S11 | **La CI parcial no identifica** (4 dígitos son pocos) | Media | Bajo | Se combina con foto + chapa + nombre, y el carnet físico se muestra al subir; no se promete identificación |
| R-S12 | **El enlace compartido se usa para acosar** (el contacto reenvía a un tercero) | Baja | Medio | Vida corta, revocación, sin PII, sin teléfono; el titular puede dejar de compartir en un toque |

---

## Recomendación

**Orden de implementación (máximo riesgo reducido por semana invertida):**

1. **Semana 1 — F6 + F3.** El 106 es casi gratis (un botón + config) y el contacto validado es el gate que hace posible todo lo demás. Incluye `037` parte 1: `configuracion_seguridad`, `contactos_emergencia`, RPC de validación y `fn_gate_seguridad` enganchado a `fn_crear_solicitud`/`fn_tomar_viaje` de H3.
2. **Semana 2 — F4.** Verificación mutua: `fn_ficha_contraparte`, tarjetas en las dos pantallas y `fn_confirmar_abordaje`. Depende de que H1 haya poblado CI/carnet; sin eso, F4 muestra "no registrada" y pierde valor.
3. **Semana 3 — F1.** Pánico con outbox, modo discreto, notificaciones y 106. Es la feature más delicada en UX; dedicarle tiempo de prueba en calle y en modo avión.
4. **Semanas 4-5 — F5 + consola.** Incidentes, bandeja, bloqueos automáticos, emparejamiento y la señal para choferes. Sin consola, F5 es un formulario que no sirve para nada.
5. **Semanas 5-7 — F2.** Edge Function pública, página, tokens y pruebas de privacidad. Si el despliegue no está disponible, entregar la versión degradada y **no anunciar "seguimiento en vivo"**.

**Decisiones que el Lead debe tomar antes de H2:**

- (D-S1) ¿Se despliega la Edge Function pública? Si no, F2 no es MVP completo y hay que ajustar el copy de lanzamiento.
- (D-S2) ¿Se acepta que la verificación del contacto sea "responde un código" y no una prueba de propiedad? (No hay canal de confianza disponible; la alternativa es no tener contactos.)
- (D-S3) ¿Se mantiene el teléfono visible entre las partes durante el viaje? Recomiendo sí, pero **sólo** mientras el viaje está activo y con aviso previo: sin llamada no se coordina la recogida, y el daño de ocultarlo es mayor.
- (D-S4) ¿Quién revisa los incidentes y en qué horario? El diseño asume una persona en horario laboral; si no hay nadie, los bloqueos automáticos son la única defensa y hay que decirlo en el copy.

**Qué medir antes de reabrir la fase 2** (no antes): M-01, M-05 y M-07 durante 3 meses. Si la tasa de "montó el carro equivocado" o de suplantación es 0, el PIN no se justifica. Si hay ≥ 1 caso/mes, se reabre.

**Lo que no hay que hacer**: lanzar el botón de pánico sin el outbox offline (falla justo cuando más se necesita), lanzar el enlace compartido sin la revocación al cerrar (deja datos colgando), y lanzar la lista negra como listado navegable con nombres y teléfonos (es un vector de acoso y un problema legal).

---

*Documento de diseño. No es código de producción. Las migraciones se entregan revisadas y se aplican manualmente según [06-aplicar-migraciones.md](06-aplicar-migraciones.md).*