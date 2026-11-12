# 08 · Privacidad, términos y consentimiento obligatorio — Taxi Muévete

> **Rol:** especialista legal / privacidad del equipo.
> **Alcance:** textos legales listos para publicar (Política de Privacidad, Términos y Condiciones, cuatro consentimientos informados) + mecanismo técnico de consentimiento **ineludible** (versión, hash, fecha, IP, dispositivo, auditoría) para el módulo de taxi de `inventtia_muevete` y la consola `ventiq_superadmin`.
> **Depende de:** [`PLAN-IMPLEMENTACION.md`](PLAN-IMPLEMENTACION.md) §2.5, §4, §5; [`04-diseno-tecnico.md`](04-diseno-tecnico.md) §2, §5, §6.
> **Modo:** redacción legal + diseño técnico. **No se tocó código ni migraciones**: el único archivo escrito es este. Las migraciones y pantallas descritas son propuestas para que las implementen los especialistas de BD y Flutter.
> **Fecha:** 2026-11-12 (America/Havana).
> **Advertencia:** este documento es un **borrador profesional de trabajo**, no asesoría jurídica firmada. Cada afirmación marcada `[VALIDAR]` debe ser confirmada por un abogado cubano con la Gaceta Oficial en mano. Las cifras, artículos y plazos citados se verificaron contra el texto publicado (ver §1), pero su **aplicación al caso concreto** (plataforma privada de intermediación, sin licencia de transportista) requiere criterio jurídico.
> **Revisión 1.1 (2026-11-12, decisiones del usuario):** se retiró por completo el análisis de alojamiento/ubicación de los servidores (no se afirma obligación de alojamiento nacional ni se incluye en riesgos o recomendaciones) y se añadieron las **cuentas de empresa** (representante legal con CI + documento acreditativo de la persona jurídica + datos fiscales) en Términos, Política, consentimiento de identidad, matriz, modelo técnico, pruebas y auditoría. Los textos legales siguen en versión `1.0.0`; los cambios de esta revisión son de alcance y redacción, no de versión publicada.

---

## Índice

1. [Resumen ejecutivo y hallazgos que cambian el plan](#1-resumen-ejecutivo-y-hallazgos-que-cambian-el-plan)
2. [Marco jurídico cubano aplicable](#2-marco-jurídico-cubano-aplicable)
3. [Texto A1 — Política de Privacidad (v1.0.0)](#3-texto-a1--política-de-privacidad-v100)
4. [Texto A2 — Términos y Condiciones de Uso (v1.0.0)](#4-texto-a2--términos-y-condiciones-de-uso-v100)
5. [Textos A3 — Consentimientos informados específicos](#5-textos-a3--consentimientos-informados-específicos)
6. [B — Mecanismo técnico de consentimiento ineludible](#6-b--mecanismo-técnico-de-consentimiento-ineludible)
7. [C — Matriz dato → finalidad → base legal → conservación → quién accede](#7-c--matriz-dato--finalidad--base-legal--conservación--quién-accede)
8. [D — Riesgos y recomendaciones](#8-d--riesgos-y-recomendaciones)
9. [Supuestos](#9-supuestos)
10. [Riesgos](#10-riesgos)
11. [Recomendación](#11-recomendación)
12. [Anexo — Checklist de validación legal](#12-anexo--checklist-de-validación-legal)

---

## 1. Resumen ejecutivo y hallazgos que cambian el plan

### 1.1 Qué se entrega

| Bloque | Contenido |
|---|---|
| **Textos legales** | Política de Privacidad completa (§3), Términos y Condiciones completos (§4), y cuatro consentimientos informados: datos personales, geolocalización en segundo plano, verificación de identidad con fotos del carnet, y contactos de emergencia (§5). Todos en español, versionados `1.0.0`. |
| **Mecanismo técnico** | Tablas `muevete.documentos_legales` y `muevete.consentimientos` (append-only, con hash del texto, IP y user-agent del servidor), RLS, RPCs `SECURITY DEFINER`, y **gates en servidor** que impiden publicar o tomar viajes sin consentimiento vigente (§6). |
| **Reglas de negocio** | Menores, cuentas existentes (41 usuarios), cuentas de empresa (representante legal con CI + documento de la empresa), rechazo, retirada, cambio de versión con aviso de 3 meses, conservación de la evidencia (§6.9). |
| **Matriz de tratamiento** | 18 filas dato → finalidad → base → conservación → acceso (§7). |
| **Riesgos** | Ubicación en segundo plano, histórico de 387 351 posiciones, exposición de la CI en la verificación mutua, cuentas de empresa, y dos riesgos de seguridad y cumplimiento que exceden la privacidad (§8, §10). |

### 1.2 Los cuatro hallazgos que condicionan el plan

1. **La Ley 149/2022 está vigente y es exigente.** Cuba aprobó la **Ley No. 149 «De Protección de Datos Personales»** el 14 de mayo de 2022 (Gaceta Oficial No. 90 Ordinaria de 25 de agosto de 2022, GOC-2022-832-O90). Entró en vigor a los 180 días de su publicación, esto es, el **21 de febrero de 2023**. No es un marco «blando»: exige consentimiento informado, aviso de privacidad previo a la recogida, plazos de respuesta, registro nacional de bases de datos y notificación de incidentes, con sanciones de hasta 20 000 pesos, suspensión y clausura (art. 56).
2. **Hay una resolución sectorial (MINCOM) que regula exactamente nuestros términos y condiciones.** La **Resolución 58/2022 del Ministerio de Comunicaciones** (19 de agosto de 2022, GOC-2022-833-O90, en vigor desde el 21 de febrero de 2023) exige que los responsables definan los términos y condiciones de uso de los datos personales, que el usuario **confirme su aprobación** (art. 6), y que los cambios de esos términos se comuniquen **con al menos 3 meses de antelación** (art. 8, inciso d). Esto es el corazón del §6.
3. **El registro de bases de datos personales es una obligación propia.** Ley 149 arts. 40–42: las bases de datos que tratan datos personales se **declaran** ante el control nacional que crea el Ministerio de Justicia (Disposiciones Especiales Primera y Segunda), y se notifican sus cambios. Además, el art. 48 obliga a **notificar incidentes de ciberseguridad** a la autoridad competente. `[VALIDAR]` si el control nacional está operativo en 2026 y cuál es el procedimiento.
4. **Hoy la app embarca una clave `service_role` de Supabase.** En `inventtia_muevete/lib/config/supabase_config.dart:12`, la constante `_releaseAnonKey` es un JWT con `"role":"service_role"`. Cualquiera que extraiga el APK puede leer y escribir **toda** la base (CI, fotos del carnet, wallet, histórico de ubicaciones) y saltarse RLS. Esto convierte cualquier promesa de la Política de Privacidad en incumplimiento de la obligación de seguridad (Ley 149 arts. 10.f y 44; Res. 58/2022 art. 4). **Es un bloqueante de seguridad y de privacidad, no una mejora.** `[VALIDAR]` con el responsable técnico. **Decisión del proyecto (2026-11-12)**: **no se rota** la clave mientras haya app en producción; las **versiones nuevas** deben usar la clave `anon` y el riesgo residual queda aceptado y documentado por escrito (ver [`10-incidente-credenciales.md`](10-incidente-credenciales.md) §7).

### 1.3 Cómo se garantiza que el consentimiento **no se pueda evadir** (resumen)

1. Los textos y sus versiones viven en la **base de datos**, no en el APK. La app pide el texto al servidor y registra el **hash SHA-256** de lo que mostró; el servidor rechaza cualquier aceptación cuyo hash no coincida con el texto canónico.
2. La aceptación se registra por RPC `SECURITY DEFINER` con **hora, IP y user-agent del servidor** (no del cliente), y las tablas son **append-only**: no hay política de `UPDATE` ni `DELETE`; un trigger lo impide incluso para el rol autenticado.
3. Las operaciones críticas (`fn_crear_solicitud`, `fn_viajes_disponibles`, `fn_tomar_viaje`, escritura de ubicación, botón de pánico, enlace compartido) llaman a `muevete.fn_exigir_operacion()` y **fallan** si falta cualquier consentimiento obligatorio o si el perfil está incompleto. La UI solo refleja ese estado; **no es la que decide**.
4. Al publicar una nueva versión de un documento, la anterior se cierra y la aceptación antigua pasa a `desactualizado`: la app bloquea hasta la re-aceptación. Los cambios se publican con **≥ 90 días de antelación** y se notifican (push/email/aviso en la app), cumpliendo Res. 58/2022 art. 8.d.
5. La evidencia no se fabrica ni se borra: no se hace *backfill* de consentimientos para los 41 usuarios existentes; cada uno debe aceptar realmente en su siguiente sesión. La evidencia se conserva hasta 5 años (Ley 149 art. 39.4) y se puede verificar por hash desde superadmin (§6.11).

---

## 2. Marco jurídico cubano aplicable

### 2.1 Normas y estado (verificado contra texto publicado)

| Norma | Identificación | Vigencia | Qué aporta a este módulo | Certeza |
|---|---|---|---|---|
| **Constitución de la República de Cuba (2019)** | Arts. 40, 48 y 97 (citados expresamente por la Ley 149/2022) | Vigente | Art. 40: dignidad humana como valor supremo. Art. 48: derecho al respeto de la intimidad personal y familiar, la propia imagen y voz, el honor y la identidad personal. Art. 97: derecho a acceder a los datos personales, a interesar su no divulgación y a obtener corrección, rectificación, modificación, actualización o cancelación. | Alta (los tres artículos aparecen citados en los «POR CUANTO» de la Ley 149/2022) |
| **Ley No. 149/2022 «De Protección de Datos Personales»** | 14 de mayo de 2022 · GOC-2022-832-O90 · GO No. 90 Ordinaria de 25/08/2022 | Vigente desde el **21/02/2023** (180 días tras publicación, Disposición Final Quinta) | Marco general: principios (art. 10), consentimiento (arts. 11–17), derechos del titular y plazos (arts. 19–38), conservación (art. 39), registro nacional de bases de datos (arts. 40–43), obligaciones (arts. 44–48), datos de imagen y voz (arts. 49–55), sanciones (art. 56). | Alta (texto completo publicado) |
| **Resolución 58/2022 del MINCOM** | 19 de agosto de 2022 · GOC-2022-833-O90 · GO No. 90 Ordinaria de 25/08/2022 | Vigente desde el **21/02/2023** (Disposición Final Segunda) | Reglamento para la seguridad y protección de los datos personales en soporte electrónico. Aplica expresamente a «los de aplicaciones» (art. 2). Art. 4: seguridad, medidas técnicas/administrativas y notificación de incidentes. Art. 6: vías de acceso/modificación/cancelación, **términos y condiciones y forma de confirmar la aprobación**, confidencialidad e integridad, respaldos. Art. 8: contenido obligatorio de los términos y condiciones, aviso de modificaciones **con 3 meses de antelación**, plazo de cancelación. Art. 10: derechos del usuario. | Alta (texto completo publicado) |
| **Decreto-Ley No. 35/2021** | «De las Telecomunicaciones, las Tecnologías de la Información y la Comunicación y el uso del Espectro Radioeléctrico» · GO No. 92 Ordinaria de 17/08/2021 | Vigente | Marco de las telecomunicaciones/TIC y de la prestación de servicios; su art. 16 remite al marco de protección al consumidor. `[VALIDAR]` obligaciones concretas aplicables a una app de intermediación. | Media (norma localizada y vigente; articulado aplicable a validar) |
| **Decreto-Ley No. 321/2014 «De Protección al Consumidor»** (MINCIN como organismo rector) y **Resolución 54/2018 del MINCIN** | 23/05/2014 y 2018 respectivamente | Vigente | Derechos del consumidor, reclamaciones y atención. `[VALIDAR]` articulado exacto aplicable a servicios digitales y a la relación pasajero–plataforma–chofer. | Media (referencia sectorial; validar artículos) |
| **Resoluciones del MITRANS 364/2020, 367/2020 y 368/2020** | Ministerio del Transporte, 2020 | Vigentes | Regulan agencias de taxi, clasificación de la demanda y precios/tarifas del servicio de taxi (empresa estatal). `[VALIDAR]` cómo encaja un intermediario privado y si la operación requiere autorización provincial; la licencia operativa del chofer es condición de la plataforma (§4.6). | Media |
| **Código Civil (Ley No. 59/1987)** | 1987 | `[VALIDAR]` vigencia y articulado | Obligaciones y responsabilidad civil contractual y extracontractual; soporte de los Términos y Condiciones. | Baja-media (no verificado en esta sesión) |
| **Normativa fiscal y contable** (retención de comprobantes, wallet, comisión) | — | — | Base de licitud para conservar datos económicos/financieros por obligación legal (Ley 149 art. 17.a). `[VALIDAR]` norma y plazo exactos. | Baja (no verificada) |

> **Nota de método:** las tres primeras filas se verificaron leyendo el texto publicado en fuentes abiertas (vLex/Informática Jurídica y referencias de la Gaceta). El resto se marca como `[VALIDAR]` porque no se consultó el texto articulado en esta sesión. No se cita ningún número de ley que no se haya podido contrastar.

### 2.2 Advertencia sobre la naturaleza del consentimiento en Cuba

La Ley 149/2022 es **consentimentalista**: el art. 11.1 exige consentimiento del titular «salvo en los casos de excepción previstos en esta Ley», y el art. 17 enumera taxativamente las excepciones (disposición de la ley, resolución judicial/fiscal, hecho que pueda dañar a una persona, asistencia sanitaria urgente, fuentes públicas, disociación, persona desaparecida, bienestar general/orden público/seguridad nacional). **No existe una base autónoma de «ejecución de contrato»** como en el RGPD europeo. `[VALIDAR]`

Consecuencia de diseño: **no basta con la aceptación de los Términos y Condiciones**. Hay que recabar consentimiento expreso, granular e informado para cada finalidad (arts. 10.l, 11 y 12), y apoyarse en el art. 17 solo para lo que la ley permite (p. ej., conservación contable por disposición legal, o uso en una emergencia real). Por eso el mecanismo del §6 registra **seis documentos**: dos aceptaciones (Términos y Política) y cuatro consentimientos.

### 2.3 Cómo leer las marcas de este documento

- `[VALIDAR]` → afirmación jurídica que **debe** confirmar un abogado antes de publicar.
- `[HUECO: …]` → dato del responsable (razón social, domicilio, correo) que el usuario debe aportar; no se inventa.
- `[FECHA]` → fecha de entrada en vigor que se fija al publicar (propuesta: ≥ 2026-12-15).
- Los artículos citados son de la Ley 149/2022 salvo que se indique otra norma.

---

## 3. Texto A1 — Política de Privacidad (v1.0.0)

> **Ficha del documento.** Código: `politica_privacidad` · Versión: `1.0.0` · Vigente desde: `[FECHA]` · Hash: lo calcula el servidor al publicar (§6.3). Este es el texto canónico: se publica sin las marcas de esta ficha y sin los corchetes ya completados.

### POLÍTICA DE PRIVACIDAD DE MUÉVETE

**Versión 1.0.0 · Vigente desde [FECHA]**

#### 1. Quién es el responsable del tratamiento

El responsable del tratamiento de tus datos personales es **[RAZÓN SOCIAL DEL RESPONSABLE]**, que opera la aplicación y la plataforma «Muévete» (en adelante, «la Plataforma»), con domicilio legal en **[DOMICILIO LEGAL]**, municipio **[MUNICIPIO]**, provincia **[PROVINCIA]**, República de Cuba, inscrita en **[REGISTRO QUE CORRESPONDA]** con el número **[NIT/RUC]**, correo electrónico **[CORREO DE PRIVACIDAD]** y teléfono **[TELÉFONO DE CONTACTO]**.

Esta condición de responsable se corresponde con el artículo 7.1 de la Ley No. 149/2022, de 14 de mayo, «De Protección de Datos Personales» (en adelante, «la Ley 149»). `[VALIDAR]` la forma jurídica concreta del responsable (persona natural, MIPYME u otra) y los datos registrales exactos.

#### 2. Alcance

Esta Política se aplica a los datos personales que tratamos cuando:

- te registras como pasajero o como chofer;
- abres o administras una cuenta en nombre de una **empresa (persona jurídica)** a través de su representante legal;
- usas la aplicación para solicitar, tomar, realizar o pagar viajes;
- activas funciones de seguridad (botón de pánico, viaje compartido, contactos de emergencia);
- contactas a nuestro equipo de soporte o presentas una reclamación.

No se aplica a los datos que un chofer o un pasajero trate por su cuenta fuera de la Plataforma. Cuando el chofer presta el servicio de transporte, actúa como prestador independiente y responsable de sus propios tratamientos; la Plataforma le facilita los datos estrictamente necesarios para el viaje (ver punto 12).

#### 3. Qué datos tratamos

Los datos marcados como **obligatorios** son necesarios para prestarte el servicio. Si no los aportas, no podemos crear la cuenta o no podemos asignarte viajes, y te lo explicamos en el momento de la recogida (artículo 12 de la Ley 149). Los datos marcados como **opcionales** solo se tratan si los aportas o si activas la función correspondiente.

| Categoría | Datos | Carácter | Para qué |
|---|---|---|---|
| **Identificación y contacto** | Nombre y apellidos, correo electrónico, teléfono, foto de perfil, provincia, municipio, dirección, país | Obligatorios los de cuenta; la dirección puede ser opcional | Crear y administrar tu cuenta, contactarte por el viaje, mostrarte tu perfil |
| **Identidad** | Número de carnet de identidad (CI), tipo de documento, fotografía del frente y del dorso del documento; en choferes, además, licencia de conducción y licencia de circulación (frente y dorso) y, si aplica, licencia operativa | **Obligatorios** | Verificar tu identidad, evitar suplantaciones y fraude, habilitar al chofer para operar |
| **Cuenta de empresa (persona jurídica)** | Razón social, NIT/RUC, domicilio de la empresa, **documento acreditativo de la empresa** y los datos de su **representante legal** (nombre, CI y fotos del carnet) | **Obligatorios** si la cuenta es de empresa | Verificar que quien contrata representa válidamente a la empresa, habilitar la cuenta y facturar |
| **Ubicación** | Posición del dispositivo en tiempo real mientras estás conectado o durante un viaje; histórico de posiciones del chofer; origen, destino y recorrido del viaje | **Obligatorios** para operar | Asignar viajes, mostrar el trayecto, calcular distancia y precio, atender emergencias y disputas |
| **Viajes** | Origen y destino (coordenadas y direcciones), distancia, duración, precio, método de pago, estado, cancelaciones | Obligatorios | Ejecutar y documentar el servicio, facturar y atender reclamaciones |
| **Pagos y wallet** | Saldo, transacciones, comisión, recargas y su evidencia; no almacenamos números de tarjetas bancarias | Obligatorios cuando usas wallet | Cobrar la comisión, liquidar saldos, contabilidad y prevención de fraude |
| **Valoraciones** | Puntuación y comentario sobre el viaje | Opcionales | Confianza y calidad del servicio |
| **Seguridad** | Contactos de emergencia que tú registres (nombre, teléfono, relación), eventos de pánico, enlaces de viaje compartido, reportes de incidentes | Voluntarios, pero necesarios si quieres usar esas funciones | Protegerte y avisar a quien tú elijas |
| **Comunicaciones** | Token del dispositivo, plataforma, versión de la app, notificaciones enviadas y leídas | Obligatorios para notificaciones | Enviarte avisos operativos del viaje |
| **Técnicos** | Dirección IP, agente de usuario (user-agent), registros de consentimiento, fecha y hora de aceptación | Obligatorios al aceptar | Probar que aceptaste los documentos y proteger la Plataforma |

No tratamos datos de salud, creencias religiosas, filiación política, orientación sexual ni otros datos sensibles en el sentido del artículo 15 de la Ley 149. Si en el futuro una función los requiriera, se te pediría consentimiento expreso y separado. `[VALIDAR]` el inventario definitivo cuando se implementen las nuevas funciones del plan (contactos, pánico, viaje compartido, incidentes).

#### 4. Para qué usamos tus datos y con qué base de licitud

| Finalidad | Datos | Base de licitud |
|---|---|---|
| Crear y administrar tu cuenta; prestarte el servicio | Identificación, contacto, perfil | Tu consentimiento expreso (arts. 11.1 y 10.l) y la aceptación de los Términos y Condiciones |
| Verificar tu identidad y habilitarte como chofer | CI, fotos del carnet, licencias | Consentimiento específico de verificación de identidad (punto 6 y §5.3) |
| Verificar la representación de una cuenta de empresa y habilitarla | Documento acreditativo de la empresa, datos fiscales y CI del representante legal | Consentimiento específico de verificación de identidad (punto 6 y §5.3) |
| Geolocalizar el dispositivo, incluso en segundo plano | Ubicación en vivo e histórica | Consentimiento específico de geolocalización (punto 5 y §5.2) |
| Asignar, ejecutar y documentar viajes; calcular precio | Ubicación, viajes, valoraciones | Consentimiento (arts. 11.1 y 10.l) y aceptación de los Términos |
| Cobrar comisión, liquidar wallet y llevar contabilidad | Pagos, wallet, transacciones | Consentimiento y, para la conservación contable, disposición legal (art. 17.a) `[VALIDAR]` |
| Notificarte avisos operativos del viaje | Token, plataforma, versión | Consentimiento (art. 11.1) |
| Atender emergencias y proteger tu seguridad | Contactos, ubicación, eventos de pánico | Consentimiento y excepción del art. 17.c (hecho que potencialmente pueda dañar a una persona) `[VALIDAR]` |
| Atender reclamaciones, disputas y defensa jurídica | Viajes, mensajes, evidencia | Consentimiento y, en su caso, art. 17.a `[VALIDAR]` |
| Prevenir fraude y usos indebidos | Identidad, dispositivos, patrones de viaje | Consentimiento y medidas de seguridad (arts. 10.f y 44) `[VALIDAR]` |
| Estadísticas y mejora del servicio | Datos **anonimizados o disociados** | Art. 17.f y art. 9 de la Resolución 58/2022 |
| Cumplir requerimientos de autoridades | Los estrictamente solicitados | Art. 17.a y 17.b; se registra cada entrega |

**No vendemos tus datos personales, no los cedemos para publicidad y no los usamos para elaborar perfiles comerciales.**

#### 5. Geolocalización, incluida la ubicación en segundo plano

**Qué recogemos.** Mientras un chofer está conectado, la aplicación envía periódicamente su posición al servidor para que pueda recibir viajes. Mientras un pasajero tiene un viaje activo, se envía su posición para mostrar el recorrido y calcular distancia, precio y tiempos. En ambos casos la recogida continúa **con la aplicación en segundo plano o cerrada**, porque el servicio no funciona si la ubicación se interrumpe al apagar la pantalla. `[VALIDAR]` la redacción exacta con el asesor, porque es el tratamiento de mayor riesgo.

**Para qué.** Asignar viajes compatibles con la zona; mostrar al pasajero dónde está su chofer; calcular el precio y la distancia; detectar desvíos; atender emergencias, incidentes y disputas; prevenir el fraude.

**Qué no hacemos.** No mostramos tu ubicación a otros usuarios fuera del viaje; no la publicamos; no la vendemos; no la usamos para publicidad. El histórico de posiciones se conserva conforme al punto 13 y solo lo consulta personal autorizado.

**Cómo desactivarla.** Puedes retirar el permiso de ubicación desde los ajustes del sistema operativo o retirar el consentimiento desde la app (Perfil → Privacidad). Si la retiras, **no podrás solicitar ni tomar viajes ni mantenerte conectado como chofer**, porque la ubicación es imprescindible para el servicio. Si retiras el consentimiento durante un viaje en curso, el viaje se completa por seguridad y la retirada se aplica al finalizar.

#### 6. Fotos del carnet de identidad y verificación de identidad

**Qué recogemos.** Número de CI, tipo de documento y fotografías del frente y del dorso del carnet. En el caso de choferes, también las fotografías de la licencia de conducción, de la licencia de circulación del vehículo y, si corresponde, de la licencia operativa.

**Para qué.** Verificar que eres quien dices ser; evitar suplantaciones, cuentas falsas y fraude; cumplir los requisitos para que un chofer pueda transportar pasajeros; resolver disputas de identidad.

**Cuentas de empresa.** Si la cuenta se abre en nombre de una **persona jurídica**, además del carnet y las fotos del **representante legal**, recogemos el **documento acreditativo de la empresa** y sus **datos fiscales** (razón social, NIT/RUC y domicilio). La verificación de identidad se hace sobre la persona del representante legal, que es quien acepta los documentos y opera la cuenta; la empresa responde por el uso que hagan sus usuarios. Cualquier cambio de representante legal debe comunicarse y verificarse de nuevo.

**Quién las revisa.** Personal autorizado de la Plataforma, a través de la consola de administración. No se muestran a otros usuarios: el pasajero no ve el carnet del chofer y el chofer no ve el carnet del pasajero. `[VALIDAR]` si por exigencia operativa debe mostrarse algún dato parcial (ver §8.3).

**Cuánto tiempo.** Las imágenes se conservan el tiempo estrictamente necesario para la verificación y, después, se eliminan; se conserva únicamente el resultado de la verificación (verificado/no verificado), la fecha y un resumen técnico. Los plazos concretos están en el punto 13. Si hay una investigación de fraude en curso, se conservan hasta su conclusión con acceso restringido. `[VALIDAR]` el plazo de conservación de las imágenes.

**Seguridad.** Las imágenes se guardan en almacenamiento privado, con acceso mediante enlaces temporales firmados y registro de accesos. No se incluyen en notificaciones ni en registros de errores.

#### 7. Contactos de emergencia

Puedes registrar personas a las que avisar si activas el botón de pánico o compartes un viaje. De ellas tratamos **nombre, teléfono y relación contigo**. Se usan **solo** para esa finalidad; no les enviamos publicidad ni los incluimos en ninguna otra comunicación.

Al registrar un contacto declaras que **le informaste** de que podríamos contactarle en una emergencia. Puedes revocar este consentimiento en cualquier momento y eliminar los contactos; si lo revocas, no podrás usar el botón de pánico ni compartir viajes. La persona contactada puede ejercer sus derechos escribiendo a **[CORREO DE PRIVACIDAD]**. `[VALIDAR]` la base jurídica del tratamiento de datos de terceros que no han dado su consentimiento; ver §8.4 y la recomendación de guardarlos solo en el dispositivo.

#### 8. Pagos y wallet

Registramos saldos, comisiones, transacciones, recargas y la evidencia que aportes (por ejemplo, captura o número de operación). No almacenamos números de tarjetas bancarias ni códigos de seguridad. Los datos económicos y financieros están protegidos por la Ley 149 (art. 4) y solo los consulta el personal autorizado para liquidaciones, contabilidad y atención de reclamaciones.

#### 9. Viajes, direcciones y valoraciones

Registramos el origen y destino del viaje, las coordenadas, las direcciones, la distancia, el precio y el método de pago para ejecutar el servicio, emitir el recibo, atender reclamaciones y defendernos ante una reclamación o un proceso. Las valoraciones se publican de forma agregada y sin exponer datos de contacto.

#### 10. Notificaciones y token del dispositivo

Para enviarte avisos del viaje usamos un identificador técnico del dispositivo (token) y la plataforma (Android/iOS). No incluimos direcciones, nombres ni datos del carnet en el contenido de las notificaciones; las notificaciones te avisan y los detalles se consultan dentro de la app. Puedes desactivar las notificaciones del sistema, pero algunas son necesarias para operar.

#### 11. Menores de edad

La Plataforma es solo para personas **mayores de 18 años**. No recogemos conscientemente datos de menores. Si detectamos que una cuenta pertenece a un menor, la bloqueamos y eliminamos sus datos personales, salvo la evidencia mínima de la incidencia. Si eres padre, madre o representante y crees que un menor nos facilitó datos, escríbenos a **[CORREO DE PRIVACIDAD]**.

`[VALIDAR]` la regla de edad (el art. 13 de la Ley 149 permite consentimiento de menores según su autonomía progresiva o de sus representantes; la Plataforma opta por 18+ por razones contractuales y de seguridad).

#### 12. Destinatarios de tus datos

| Destinatario | Qué recibe | Cuándo |
|---|---|---|
| **El chofer o el pasajero del viaje** | Nombre, foto, valoración, teléfono; origen, destino y recorrido. **Nunca el carnet ni las fotos del documento** | Solo cuando el viaje está asignado, y durante su ejecución |
| **Personal autorizado de la Plataforma** | Los datos estrictamente necesarios según su función (verificación, soporte, liquidaciones, seguridad) | Con acceso registrado y bajo confidencialidad |
| **La empresa titular de la cuenta** (si la cuenta es de empresa) | Datos de la cuenta, de sus usuarios y de los viajes que gestione | Cuando la cuenta es de empresa y la empresa administra usuarios |
| **Proveedor de infraestructura (encargado)** | Aloja la base de datos, autenticación y almacenamiento: **Supabase** | Siempre |
| **Proveedor de notificaciones push (encargado)** | Token del dispositivo y el texto genérico de la notificación: **Pushy** | Cuando se envía una notificación |
| **Servicios de mapas y rutas** | Coordenadas del origen y destino o zona consultada: **OSRM** (rutas), **Nominatim** (búsqueda de direcciones) y servidores de teselas (OpenStreetMap/Carto) | Cuando usas el mapa o pides una ruta |
| **Autoridades** | Lo estrictamente requerido por ley, resolución judicial o fiscal, o en una emergencia real | Con registro de la entrega |
| **Otros** | Ninguno. No vendemos ni cedemos datos a terceros con fines publicitarios | — |

Los proveedores que actúan como encargados están obligados contractualmente a tratar los datos solo según nuestras instrucciones y a aplicar medidas de seguridad. `[VALIDAR]` la calificación de encargado/responsable de cada proveedor y la existencia de contratos de encargo (art. 7.2 de la Ley 149).

#### 13. Plazo de conservación

| Dato | Plazo | Fundamento |
|---|---|---|
| Datos de cuenta y perfil | Mientras la cuenta esté activa y hasta **5 años** desde la última actividad o la baja | Art. 39.4 de la Ley 149 |
| CI y fotos del carnet / licencias | Durante la verificación y **90 días después**; luego se eliminan las imágenes y se conserva el resultado, la fecha y un resumen técnico | Arts. 10.a y 39.2 |
| CI y fotos del **representante legal** de una cuenta de empresa | Durante la verificación y **90 días después**; luego se eliminan las imágenes | Arts. 10.a y 39.2 |
| **Documento acreditativo de la empresa y datos fiscales** | Mientras la cuenta esté activa y **5 años** después de la baja | Art. 17.a `[VALIDAR]` y art. 39.4 |
| Ubicación en vivo | Mientras estás conectado o en viaje; la última posición se conserva **24 horas** para soporte | Minimización (art. 10.a) |
| Histórico de posiciones | **90 días** en bruto; después se agrega y anonimiza para estadísticas y se elimina el dato individual | Arts. 10.a, 17.f y 39 |
| Viajes, precios, recibos y reclamaciones | **5 años** | Art. 39.4 y defensa jurídica |
| Wallet y transacciones | **5 años** | Art. 17.a `[VALIDAR]` y contabilidad |
| Contactos de emergencia | Mientras la cuenta esté activa; se borran al revocar o al cerrar la cuenta | Art. 22 |
| Eventos de pánico e incidentes | **5 años** o hasta la prescripción de la acción | Art. 39.4 y defensa `[VALIDAR]` |
| Registros de consentimiento (fecha, IP, user-agent, hash) | **5 años** desde la última aceptación o la baja | Arts. 17.a y 39.4 `[VALIDAR]` |
| Notificaciones y token | Mientras el dispositivo esté activo; **180 días** de inactividad | Minimización |
| Registros de seguridad y accesos | **2 años** | Seguridad (art. 10.f) |

Cuando termina el plazo, los datos se suprimen de oficio o a tu solicitud (arts. 39.3 y 46). La evidencia de consentimiento puede conservarse seudonimizada para demostrar el cumplimiento. `[VALIDAR]` si procede conservarla tras la baja y en qué forma.

#### 14. Seguridad

Adoptamos medidas técnicas y organizativas para proteger tus datos: control de acceso por roles, cifrado en tránsito, almacenamiento privado de documentos con enlaces temporales, registro de accesos, copias de seguridad, revisión de permisos y formación del personal. Ningún sistema es infalible; si ocurre un incidente, actuamos según el punto 17.

#### 15. Tus derechos y cómo ejercerlos

Puedes ejercer en cualquier momento, sin orden de prelación y sin coste (arts. 19 a 28 de la Ley 149):

- **Acceso**: saber qué datos tenemos y cómo los tratamos (art. 20).
- **No divulgación / intimidad** (art. 19).
- **Rectificación, corrección, modificación y actualización** (art. 21).
- **Cancelación** cuando el fin se cumplió o el tratamiento es inadecuado (art. 22).
- **Oposición** al tratamiento que te cause daño o afecte tus derechos (art. 23).

**Cómo.** Escribe a **[CORREO DE PRIVACIDAD]** desde el correo de tu cuenta, o usa Perfil → Privacidad. Indica tu nombre, el derecho que ejerces y, si rectificas, el documento que lo acredita. Responderemos en **5 días hábiles** sobre la procedencia y lo haremos efectivo en **10 días hábiles** (art. 25), prorrogables una sola vez por igual plazo. Si no somos competentes, te lo diremos en 5 días hábiles y te orientaremos (art. 26).

Si no atendemos tu solicitud o no estás conforme, puedes interponer la **acción de protección de datos personales** en el plazo de 10 días hábiles (arts. 29 a 38), ante la autoridad o el tribunal competente según el art. 30. `[VALIDAR]` la autoridad concreta competente en Villa Clara.

#### 16. Cookies y tecnologías de seguimiento

La aplicación móvil no usa cookies de publicidad. Usamos identificadores técnicos del dispositivo (token push, versión de la app, plataforma) y registros de seguridad. No usamos SDK de publicidad ni de analítica de terceros. Los servicios de mapas y las fuentes tipográficas pueden recibir tu IP al cargar recursos; lo informamos aquí conforme al art. 8.c de la Resolución 58/2022. `[VALIDAR]` el inventario técnico definitivo con el equipo de desarrollo.

#### 17. Incidentes de seguridad

Si se produce un incidente que afecte tus datos, lo contendremos, evaluaremos su alcance y lo notificaremos a la autoridad competente conforme al art. 48 de la Ley 149 y al art. 4.c de la Resolución 58/2022. Si el incidente puede afectar significativamente tus derechos, te lo comunicaremos por los canales de contacto de tu cuenta. Conservamos un registro interno de incidentes. `[VALIDAR]` el plazo y la autoridad exacta de notificación (la ley no fija un plazo expreso).

#### 18. Cambios a esta Política

Podemos actualizar esta Política. Los cambios se comunicarán **con al menos 3 meses de antelación** por correo electrónico, SMS, notificación en la app o aviso en el sitio, conforme al art. 8.d de la Resolución 58/2022, y la nueva versión se publicará con su número de versión, fecha y hash. Si el cambio afecta tu consentimiento, deberás aceptar la nueva versión para seguir operando. `[VALIDAR]` si la primera publicación de estos documentos exige también el aviso de 3 meses (no hay versión anterior que «modificar»).

#### 19. Autoridad de control y reclamaciones

Puedes reclamar ante el **Ministerio de Comunicaciones (MINCOM)**, que controla el cumplimiento de la Resolución 58/2022, y ante el **Ministerio de Justicia**, a cuyo cargo está el control nacional de registros, ficheros, archivos y bases de datos personales (Ley 149, arts. 40 a 43 y Disposiciones Especiales). También puedes acudir a los tribunales. `[VALIDAR]` los canales y procedimientos vigentes en 2026.

#### 20. Contacto

**[CORREO DE PRIVACIDAD]** · **[TELÉFONO]** · **[DOMICILIO LEGAL]** · **[SITIO WEB]**

**Versión 1.0.0 · Vigente desde [FECHA] · Hash [HASH] · Responsable: [RAZÓN SOCIAL]**

---

## 4. Texto A2 — Términos y Condiciones de Uso (v1.0.0)

> **Ficha del documento.** Código: `terminos_uso` · Versión: `1.0.0` · Vigente desde: `[FECHA]` · Hash: calculado al publicar.

### TÉRMINOS Y CONDICIONES DE USO DE MUÉVETE

**Versión 1.0.0 · Vigentes desde [FECHA]**

#### 1. Identificación del prestador

Estos Términos regulan el uso de la aplicación y la plataforma «Muévete», operada por **[RAZÓN SOCIAL]**, con domicilio en **[DOMICILIO LEGAL]**, **[MUNICIPIO]**, **[PROVINCIA]**, Cuba, **[NIT/RUC]**, correo **[CORREO DE CONTACTO]**. `[VALIDAR]` datos registrales.

#### 2. Naturaleza del servicio: somos un intermediario tecnológico

Muévete es una **plataforma tecnológica de intermediación** que conecta a pasajeros con choferes independientes. **No somos una empresa de transporte, no prestamos el servicio de transporte, no somos titulares de los vehículos ni empleamos a los choferes.** El contrato de transporte se celebra entre el pasajero y el chofer; la Plataforma solo facilita el encuentro, la fijación del precio, el registro del viaje y el cobro de su comisión.

El chofer actúa como prestador independiente y es responsable de contar con la **licencia operativa** y demás autorizaciones que exija la autoridad provincial o municipal, así como del estado técnico del vehículo, del seguro y de la legalidad de su servicio. `[VALIDAR]` el encuadre exacto conforme al Decreto-Ley 35/2021 y a las resoluciones del MITRANS y la normativa provincial; es un punto central que el abogado debe confirmar, porque de él depende la responsabilidad de la Plataforma.

#### 3. Capacidad y requisitos de los usuarios

Para usar Muévete debes:

- ser **mayor de 18 años** y tener capacidad legal para contratar;
- registrarte con datos veraces y completos, incluido un **carnet de identidad válido** y las fotografías que se te soliciten;
- superar la **verificación de identidad**;
- tener una cuenta única y no compartirla;
- contar con un dispositivo compatible y conexión a internet;
- si eres chofer, además: licencia de conducción vigente, licencia de circulación del vehículo, licencia operativa cuando corresponda, vehículo en condiciones y el resto de requisitos que la Plataforma verifique.

El incumplimiento de estos requisitos impide operar y puede provocar la suspensión o el bloqueo de la cuenta.

#### 3.1 Cuentas de empresa (persona jurídica)

Una persona jurídica puede abrir una cuenta a través de su **representante legal**. En ese caso:

- el representante legal debe aportar su **carnet de identidad válido** y las **fotografías** que se le soliciten, y superar la verificación de identidad **a título personal**;
- debe aportar el **documento acreditativo de la empresa** (el que acredite su constitución y la representación que ejerce) y los **datos fiscales** de la empresa (razón social, NIT/RUC y domicilio);
- la empresa es la titular de la cuenta y **responde por el uso que hagan sus usuarios** y por la veracidad de los datos que aporte;
- cualquier cambio de representante legal, de razón social o de datos fiscales debe comunicarse y verificarse de nuevo; la cuenta puede suspenderse mientras no se acredite;
- la verificación de identidad se conserva sobre la persona del representante legal; los documentos de la empresa se conservan mientras la cuenta esté activa y por el plazo fiscal aplicable.

`[VALIDAR]` el documento exacto que acredita la constitución y la representación de una persona jurídica cubana (escritura notarial, inscripción registral u otro) y si la Plataforma debe conservar copia o solo la constancia de su verificación.

#### 4. Registro, identidad y veracidad

El registro implica la aceptación de estos Términos, de la Política de Privacidad y de los consentimientos que se te presentan. **Sin esas aceptaciones no es posible crear el perfil ni operar.** Los datos deben ser exactos y actualizarse cuando cambien. La Plataforma puede solicitar documentación adicional razonable para verificar identidad, titularidad del vehículo o habilitación.

Una cuenta es personal e intransferible. El uso de una cuenta por otra persona, la suplantación de identidad o la aportación de documentos falsos o ajenos son incumplimientos graves.

#### 5. Obligaciones del pasajero

- Proporcionar datos veraces y mantener actualizado el teléfono.
- Estar en el punto de recogida a la hora indicada y facilitar el contacto.
- Pagar el precio mostrado por la aplicación y no pactar cobros fuera de ella.
- Tratar con respeto al chofer y al vehículo; no comer, fumar, consumir alcohol ni sustancias ilícitas dentro del vehículo.
- No transportar mercancías ilícitas, peligrosas o prohibidas.
- No usar la Plataforma para acosar, amenazar, discriminar o cometer delitos.
- Aportar información veraz en una reclamación o incidente.

#### 6. Obligaciones del chofer

- Mantener vigente su **licencia operativa**, la licencia de conducción y la circulación del vehículo, y acreditarlas cuando se le soliciten.
- Mantener el vehículo en condiciones técnicas, de limpieza y de seguridad, con seguro vigente.
- Conducir sin haber consumido alcohol, drogas o medicamentos que afecten la conducción; respetar las normas de tránsito.
- Aceptar solo los viajes que pueda cumplir; no ceder el viaje a un tercero ni usar el vehículo de otro sin autorización.
- No cobrar un precio distinto del que muestra la aplicación, ni exigir pagos adicionales fuera de la app, ni negarse a usar el método de pago elegido.
- Tratar con respeto y sin discriminación a los pasajeros; prestar ayuda razonable a personas con movilidad reducida.
- **No solicitar, fotografiar ni conservar el carnet del pasajero** ni otros documentos; la verificación de identidad la hace la Plataforma.
- Mantener la confidencialidad de los datos del pasajero a los que acceda por el viaje.
- No usar la aplicación mientras conduce; el teléfono debe manejarse con el vehículo detenido o mediante soporte y voz.
- Reportar de inmediato accidentes, incidentes de seguridad o sospechas de fraude.

#### 7. Prohibiciones generales

Se prohíbe: usar la Plataforma para fines ilícitos; suplantar identidad; manipular el GPS, el precio o los registros del viaje; crear cuentas falsas o múltiples para eludir bloqueos; extraer, copiar o automatizar datos de la Plataforma; interferir en su funcionamiento; acosar, amenazar o difamar a otros usuarios; discriminación por cualquier motivo; y cualquier conducta que ponga en riesgo la seguridad de las personas.

#### 8. Precio, comisión y forma de pago

El precio del viaje lo calcula **la Plataforma en el servidor** conforme a la zona, la distancia y el tipo de vehículo, y se muestra antes de confirmar. **El precio no se negocia** y no puede ser modificado por el pasajero ni por el chofer. Puede incluir recargos informados (nocturno, espera, distancia) y se redondea según la configuración vigente.

La Plataforma cobra una **comisión** sobre el precio del viaje (actualmente 15 %, configurable) y el resto corresponde al chofer. En efectivo, el chofer retiene el importe y acumula la deuda de comisión; en wallet, la comisión se descuenta automáticamente. Las condiciones de deuda, su tope y los días máximos se muestran en la app y pueden cambiar según la configuración de la Plataforma.

El pago con wallet y las recargas se rigen por las condiciones mostradas en la app; el comprobante del viaje estará disponible en el historial. La Plataforma no almacena datos de tarjetas bancarias.

#### 9. Cancelaciones y no presentación

El pasajero puede cancelar antes de que el chofer llegue; si el viaje ya está en curso o el chofer se encuentra en el punto, podrán aplicarse condiciones informadas en la app. El chofer puede cancelar por causas justificadas (seguridad, accidente, fuerza mayor) y debe informarlo. Las cancelaciones reiteradas o abusivas pueden afectar la valoración y el acceso al servicio. `[VALIDAR]` la política de cargos por cancelación, si se implementa, conforme al marco de protección al consumidor.

#### 10. Valoraciones

Pasajero y chofer pueden valorarse. Las valoraciones deben ser honestas y respetuosas; se prohíbe su uso para amenazar, extorsionar o condicionar servicios. La Plataforma puede moderar o eliminar contenidos ilícitos y usar las valoraciones para mejorar la calidad.

#### 11. Seguridad y botón de pánico

La Plataforma ofrece funciones de seguridad: botón de pánico, contactos de emergencia y enlace de viaje compartido. **Estas funciones son una ayuda y no sustituyen a los servicios de emergencia.** En una emergencia debes llamar de inmediato a los servicios públicos: **Policía 106, Bomberos 105, Ambulancia 104, Salvamento y rescate 107**. `[VALIDAR]` los números vigentes y si la Plataforma puede integrarse con algún servicio de emergencia.

El botón de pánico puede: compartir tu ubicación y los datos del viaje con los contactos que elegiste; alertar al equipo de seguridad de la Plataforma; registrar el evento. **No garantiza** que una persona acuda a tu auxilio, ni que la policía o una ambulancia lleguen, ni tiempos de respuesta; depende de la cobertura, la batería, la red y de terceros. **No graba audio ni video** salvo que se te informe y consientas expresamente de forma separada. El enlace de viaje compartido muestra tu ubicación a quien tenga el enlace; eres responsable de a quién se lo envías.

#### 12. Responsabilidad

La Plataforma responde por el funcionamiento del servicio tecnológico que presta y por el tratamiento de datos conforme a la ley y a la Política de Privacidad. **No responde** por el servicio de transporte en sí, por la conducta de choferes o pasajeros, por accidentes, daños o pérdidas ocurridos durante el viaje, ni por incumplimientos de obligaciones legales propias del chofer, sin perjuicio de las responsabilidades que la ley imponga y de la colaboración que prestemos a las autoridades. `[VALIDAR]` los límites de responsabilidad admisibles conforme al Código Civil y al Decreto-Ley 321/2014; algunas limitaciones podrían ser nulas frente a consumidores.

La Plataforma no garantiza disponibilidad ininterrumpida: puede haber mantenimientos, fallos de red, fuerza mayor o causas ajenas. Tampoco garantiza que siempre haya choferes disponibles.

#### 13. Reclamaciones y atención al cliente

Puedes reclamar por **[CORREO DE CONTACTO]**, por el formulario de la app o por el teléfono **[TELÉFONO]**. Responderemos en un plazo razonable y, cuando la ley lo exija, en los plazos legales. Conservamos la evidencia del viaje y de la reclamación. Como consumidor puedes acudir además a las vías del Decreto-Ley 321/2014 y a la autoridad de protección al consumidor. `[VALIDAR]` plazos y vías exactas.

#### 14. Propiedad intelectual

La app, su código, marcas, textos y diseño son de titularidad de **[RAZÓN SOCIAL]** o de sus licenciantes. No puedes copiar, modificar, distribuir ni explotar la Plataforma sin autorización. Los mapas y datos geográficos pertenecen a sus proveedores y se usan conforme a sus licencias.

#### 15. Suspensión, bloqueo y baja

La Plataforma puede suspender o bloquear una cuenta, temporal o definitivamente, por incumplimiento de estos Términos, por fraude, por riesgo para la seguridad, por requerimiento de autoridad o por inactividad prolongada. Se informará el motivo cuando sea posible y se permitirá la reclamación. El usuario puede solicitar la baja en cualquier momento; la baja no elimina las obligaciones pendientes (por ejemplo, deuda de comisión) ni la evidencia que deba conservarse por ley.

#### 16. Modificaciones

La Plataforma puede modificar estos Términos y la Política de Privacidad. Los cambios se comunicarán **con al menos 3 meses de antelación** por correo, SMS, notificación o aviso en la app (Res. 58/2022, art. 8.d) y se publicarán con su versión, fecha y hash. Si el cambio afecta tu consentimiento, deberás aceptar la nueva versión para seguir operando; si no aceptas, podrás dejar de usar el servicio y solicitar la baja. `[VALIDAR]` el régimen exacto de la primera versión.

#### 17. Nulidad parcial, ley aplicable y jurisdicción

Si alguna cláusula es nula, las demás siguen vigentes. Estos Términos se rigen por la **ley cubana**. Las partes se someten a los tribunales competentes de **[MUNICIPIO/PROVINCIA]**, sin perjuicio de los derechos del consumidor. `[VALIDAR]` la jurisdicción y el fuero aplicable.

#### 18. Aceptación electrónica

La aceptación de estos Términos se realiza electrónicamente mediante la marca de la casilla correspondiente y el registro en el servidor de la versión, el hash del texto, la fecha, la hora, la IP y el dispositivo. Conforme al art. 11.2 de la Ley 149, el consentimiento puede manifestarse por cualquier medio que se pueda equiparar al escrito; la Plataforma exige manifestación **expresa** (no tácita). La aceptación tiene valor probatorio.

#### 19. Contacto

**[RAZÓN SOCIAL]** · **[DOMICILIO LEGAL]** · **[CORREO DE CONTACTO]** · **[TELÉFONO]**

**Versión 1.0.0 · Vigentes desde [FECHA] · Hash [HASH]**

---

## 5. Textos A3 — Consentimientos informados específicos

> **Regla común.** Los cuatro consentimientos se presentan **por separado**, con casilla propia **no premarcada**, enlace al texto completo y la información del art. 12 de la Ley 149: finalidad, datos, destinatarios, carácter obligatorio o facultativo, dónde se almacenan, consecuencias de no otorgarlo y régimen de conservación. El texto que se muestra al usuario es el que se registra por hash (§6.3).

### 5.1 `consentimiento_datos` — Tratamiento de datos personales

> Autorizo a **[RAZÓN SOCIAL]** a tratar mis datos personales (nombre, teléfono, correo, foto de perfil, provincia, municipio, dirección, país y los datos del viaje, valoraciones y wallet) para: crear y administrar mi cuenta; asignarme y documentar viajes; calcular el precio; cobrar la comisión y liquidar saldos; notificarme avisos operativos; atender reclamaciones; prevenir el fraude; y cumplir obligaciones legales.
>
> **Datos:** los descritos en la Política de Privacidad. **Destinatarios:** el chofer o pasajero del viaje (solo lo necesario), personal autorizado de la Plataforma, los proveedores de infraestructura que actúan como encargados del tratamiento (ver Política, punto 12) y las autoridades cuando la ley lo exija. **Almacenamiento:** servidores de los encargados del tratamiento (ver Política, punto 12). **Conservación:** según la Política, punto 13.
>
> **Es obligatorio:** sin este consentimiento no puedo registrarme ni operar. **Puedo retirarlo** en cualquier momento desde Perfil → Privacidad o escribiendo a **[CORREO DE PRIVACIDAD]**; la retirada no afecta los tratamientos ya realizados y me impide seguir operando.
>
> Declaro que leí la Política de Privacidad (versión 1.0.0) y que se me informó de lo anterior.

### 5.2 `consentimiento_geolocalizacion` — Ubicación, incluida en segundo plano

> Autorizo a **[RAZÓN SOCIAL]** a recoger y tratar mi ubicación (coordenadas, precisión aproximada, origen y destino del viaje y, si soy chofer, mi posición mientras estoy conectado) **incluso con la aplicación en segundo plano o cerrada**, para: asignarme viajes compatibles con mi zona; mostrar mi posición al pasajero o al chofer del viaje; calcular distancia, tiempo y precio; detectar desvíos; atender emergencias y disputas; prevenir el fraude.
>
> **Destinatarios:** la contraparte del viaje (solo durante el viaje), personal autorizado de la Plataforma, proveedores de mapas y rutas (coordenadas del origen y destino), Supabase como encargado y las autoridades cuando la ley lo exija.
>
> **Es obligatorio para operar:** sin la ubicación no puedo solicitar ni tomar viajes, porque el servicio depende de ella. Se me explicó que puedo desactivar el permiso en los ajustes del sistema operativo y que, si lo hago, dejaré de poder operar. **Conservación:** mientras estoy conectado o en viaje; el histórico, 90 días en bruto y después agregado y anonimizado.
>
> **Puedo retirarlo** en Perfil → Privacidad o en los ajustes del sistema; la retirada se aplica al terminar el viaje en curso, por seguridad.

### 5.3 `consentimiento_identidad` — Verificación de identidad con fotos del carnet

> Autorizo a **[RAZÓN SOCIAL]** a tratar mi número de carnet de identidad, tipo de documento y las **fotografías del frente y del dorso** de mi carnet; si soy chofer, también las fotografías de mi licencia de conducción, de la licencia de circulación del vehículo y, en su caso, de la licencia operativa. La finalidad es **verificar mi identidad**, evitar suplantaciones y fraude y habilitarme para operar.
>
> Si actúo como **representante legal de una persona jurídica**, autorizo además el tratamiento del **documento acreditativo de la empresa** y de sus **datos fiscales** (razón social, NIT/RUC y domicilio), con la finalidad de verificar que represento válidamente a la empresa y habilitar su cuenta. La verificación de identidad se hace sobre mi persona; la empresa responde por el uso que hagan sus usuarios.
>
> **Quién las ve:** únicamente personal autorizado de la Plataforma a través de la consola de verificación; **no se muestran al pasajero ni al chofer** de mis viajes. **Almacenamiento:** almacenamiento privado con enlaces temporales y registro de accesos. **Conservación:** durante la verificación y 90 días después; luego se eliminan las imágenes y se conserva solo el resultado de la verificación y la fecha. El documento de la empresa se conserva mientras la cuenta esté activa y **5 años** después de la baja. `[VALIDAR]` el plazo de las imágenes y el documento que acredita la representación.
>
> **Es obligatorio para operar.** **Puedo retirarlo** escribiendo a **[CORREO DE PRIVACIDAD]**; la retirada bloquea mi cuenta hasta que se verifique de nuevo o solicite la baja. Declaro que los documentos son míos, auténticos y están vigentes.

### 5.4 `consentimiento_contactos_emergencia` — Contactos de emergencia

> Autorizo a **[RAZÓN SOCIAL]** a tratar el **nombre, teléfono y relación** de las personas que yo registre como contactos de emergencia, con la única finalidad de avisarles si activo el botón de pánico o comparto un viaje. No se usarán para publicidad ni para otras comunicaciones.
>
> **Declaro que informé a esas personas** de que podrían ser contactadas en una emergencia y que son mayores de edad. **Destinatarios:** el contacto elegido (solo cuando se activa la función), el equipo de seguridad de la Plataforma y, si corresponde, las autoridades.
>
> **Es voluntario:** puedo operar sin contactos de emergencia, pero no podré usar el botón de pánico ni el enlace de viaje compartido. **Puedo retirarlo y eliminar los contactos** en cualquier momento desde Perfil → Seguridad; la retirada se hace efectiva de inmediato.
>
> `[VALIDAR]` la base jurídica del tratamiento de datos de terceros y la alternativa de guardar los contactos **solo en el dispositivo** (recomendada en §8.4).

---

## 6. B — Mecanismo técnico de consentimiento ineludible

### 6.1 Principios de diseño

1. **El servidor es la única autoridad.** La app puede mostrar, pero no decidir. Toda operación se valida en una RPC `SECURITY DEFINER`; las tablas no admiten escritura directa del cliente.
2. **Evidencia atada al texto.** Se registra el hash SHA-256 del texto canónico publicado; si la app mostrara otro texto u otro hash, la RPC rechaza la aceptación.
3. **Evidencia inmutable.** Tabla *append-only*: sin `UPDATE`, sin `DELETE`, sin políticas RLS que lo permitan; un trigger lanza excepción incluso para el propietario autenticado.
4. **Evidencia con sello del servidor.** Fecha/hora, IP (de las cabeceras de la petición HTTP, no del cuerpo) y user-agent se capturan en el servidor; el cliente no puede declararlos.
5. **Versionado con aviso.** Cada publicación crea una versión nueva, cierra la anterior y exige re-aceptación; los cambios se publican con ≥ 90 días de antelación (Res. 58/2022 art. 8.d).
6. **Sin *backfill* de voluntad.** No se crean aceptaciones por los 41 usuarios existentes: cada uno acepta realmente en su próxima sesión.
7. **Proporcionalidad y graduación.** Cada consentimiento es independiente; retirar uno no invalida los demás, pero sí las funciones que dependen de él.

### 6.2 Modelo de datos (DDL)

> Migraciones propuestas: `041_taxi_legal_documentos.sql` (tablas, RLS, funciones de estado), `042_taxi_legal_gates.sql` (RPC de registro, gates en RPC de viaje, triggers de perfil) y `043_taxi_retencion_datos.sql` (cron de purga). **El número es indicativo**: el plan usa 031–038 y los RPC de H3 ocupan 038–040; hay que renumerar al integrar. Requiere `pgcrypto` (ya instalado) para `digest`.

```sql
-- 041_taxi_legal_documentos.sql  (esquema muevete)
BEGIN;

-- ---------------------------------------------------------------
-- 1) Documentos legales versionados. Texto canónico + hash.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.documentos_legales (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo           text NOT NULL CHECK (codigo IN (
                     'politica_privacidad', 'terminos_uso',
                     'consentimiento_datos',
                     'consentimiento_geolocalizacion',
                     'consentimiento_identidad',
                     'consentimiento_contactos_emergencia')),
  version          text NOT NULL CHECK (version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
  titulo           text NOT NULL,
  texto_md         text NOT NULL CHECK (length(btrim(texto_md)) > 200),
  hash_sha256      text NOT NULL CHECK (hash_sha256 ~ '^[a-f0-9]{64}$'),
  vigente_desde    timestamptz NOT NULL,
  vigente_hasta    timestamptz,
  notificado_at    timestamptz,          -- aviso a usuarios (Res. 58/2022 art. 8.d)
  publicado_por    uuid REFERENCES auth.users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT documentos_legales_version_unica UNIQUE (codigo, version),
  CONSTRAINT documentos_legales_hash_unico    UNIQUE (codigo, version, hash_sha256),
  CONSTRAINT documentos_legales_vigencia_ok   CHECK (vigente_hasta IS NULL OR vigente_hasta > vigente_desde)
);

-- Solo una versión abierta (la última o la programada) por documento.
CREATE UNIQUE INDEX IF NOT EXISTS documentos_legales_abierto_uidx
  ON muevete.documentos_legales (codigo) WHERE vigente_hasta IS NULL;

-- El hash lo calcula SIEMPRE el servidor a partir del texto; y el texto
-- publicado es inmutable (cambiarlo exige nueva versión, lo que fuerza
-- re-aceptación).
CREATE OR REPLACE FUNCTION muevete.fn_documento_legal_hash()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, public, extensions
AS $$
BEGIN
  NEW.titulo      := btrim(NEW.titulo);
  NEW.hash_sha256 := encode(digest(NEW.texto_md, 'sha256'), 'hex');
  IF TG_OP = 'UPDATE' THEN
    IF NEW.codigo        IS DISTINCT FROM OLD.codigo
       OR NEW.version       IS DISTINCT FROM OLD.version
       OR NEW.texto_md      IS DISTINCT FROM OLD.texto_md
       OR NEW.vigente_desde IS DISTINCT FROM OLD.vigente_desde THEN
      RAISE EXCEPTION 'documento_legal_inmutable: publica una versión nueva';
    END IF;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_documentos_legales_hash ON muevete.documentos_legales;
CREATE TRIGGER trg_documentos_legales_hash
  BEFORE INSERT OR UPDATE ON muevete.documentos_legales
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_documento_legal_hash();

-- ---------------------------------------------------------------
-- 2) EVIDENCIA de aceptación/rechazo. Append-only.
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.consentimientos (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Sin FK a auth.users a propósito: la evidencia sobrevive a la baja de la
  -- cuenta (se conserva seudonimizada hasta 5 años, Ley 149 art. 39.4).
  usuario_uuid      uuid NOT NULL,
  usuario_rol       text NOT NULL DEFAULT 'cliente'
                      CHECK (usuario_rol IN ('cliente','chofer','carrier','shipper')),
  -- Cuentas de empresa: la aceptación la otorga el representante legal, a
  -- nombre de la persona jurídica; se deja rastro de a quién representa.
  cuenta_tipo       text NOT NULL DEFAULT 'persona_natural'
                      CHECK (cuenta_tipo IN ('persona_natural','persona_juridica')),
  en_nombre_de      text,
  documento_codigo  text NOT NULL,
  documento_version text NOT NULL,
  documento_hash    text NOT NULL CHECK (documento_hash ~ '^[a-f0-9]{64}$'),
  aceptado          boolean NOT NULL,
  motivo            text,
  registrado_at     timestamptz NOT NULL DEFAULT now(),   -- hora del servidor
  ip                inet,
  user_agent        text,
  plataforma        text NOT NULL DEFAULT 'desconocida'
                      CHECK (plataforma IN ('android','ios','web','desconocida')),
  app_version       text,
  dispositivo_id    text,
  origen            text NOT NULL DEFAULT 'app'
                      CHECK (origen IN ('app','consola','migracion')),
  CONSTRAINT consentimientos_documento_fkey
    FOREIGN KEY (documento_codigo, documento_version, documento_hash)
    REFERENCES muevete.documentos_legales (codigo, version, hash_sha256)
);

CREATE INDEX IF NOT EXISTS consentimientos_usuario_idx
  ON muevete.consentimientos (usuario_uuid, documento_codigo, registrado_at DESC);
CREATE INDEX IF NOT EXISTS consentimientos_documento_idx
  ON muevete.consentimientos (documento_codigo, documento_version, aceptado);
CREATE INDEX IF NOT EXISTS consentimientos_fecha_idx
  ON muevete.consentimientos (registrado_at DESC);

CREATE OR REPLACE FUNCTION muevete.fn_consentimiento_inmutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = muevete, public
AS $$
BEGIN
  RAISE EXCEPTION 'consentimiento_inmutable: la evidencia no se modifica ni se borra';
END $$;

DROP TRIGGER IF EXISTS trg_consentimientos_inmutables ON muevete.consentimientos;
CREATE TRIGGER trg_consentimientos_inmutables
  BEFORE UPDATE OR DELETE ON muevete.consentimientos
  FOR EACH ROW EXECUTE FUNCTION muevete.fn_consentimiento_inmutable();

-- ---------------------------------------------------------------
-- 3) Configuración legal (singleton)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS muevete.configuracion_legal (
  id                         smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  aviso_cambio_dias          integer NOT NULL DEFAULT 90 CHECK (aviso_cambio_dias >= 90),
  contactos_emergencia_activo boolean NOT NULL DEFAULT false,
  exigir_perfil_completo     boolean NOT NULL DEFAULT true,
  actualizado_at             timestamptz NOT NULL DEFAULT now()
);
INSERT INTO muevete.configuracion_legal (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------
-- 4) Cuentas de empresa: documento acreditativo de la persona jurídica
--    (los datos fiscales ya existen en users/drivers: empresa_nombre,
--    empresa_rut, empresa_direccion).
-- ---------------------------------------------------------------
ALTER TABLE muevete.users   ADD COLUMN IF NOT EXISTS empresa_doc_url text;
ALTER TABLE muevete.drivers ADD COLUMN IF NOT EXISTS empresa_doc_url text;

CREATE INDEX IF NOT EXISTS consentimientos_empresa_idx
  ON muevete.consentimientos (cuenta_tipo, usuario_uuid);

COMMIT;
```

> **Nota sobre cuentas de empresa.** Los documentos legales y consentimientos se aceptan **a nombre de la cuenta**, pero los firma el **representante legal** con su propia sesión: `usuario_uuid` es el del representante, `cuenta_tipo = 'persona_juridica'` y `en_nombre_de` guarda la razón social, para que la evidencia diga en nombre de quién se aceptó. La verificación de identidad se hace sobre las **personas físicas** (CI y fotos del representante; en choferes, también del conductor), y el **documento acreditativo de la empresa** se guarda en `empresa_doc_url` con el mismo régimen de almacenamiento privado. Se conserva mientras la cuenta esté activa y **5 años** después de la baja por obligación fiscal; las imágenes del carnet del representante, 90 días tras la verificación. `[VALIDAR]` el documento que acredita la representación y si debe conservarse copia.

> **Nota sobre `vigente_desde` futura.** Para programar un cambio se publica la versión nueva con `vigente_desde = fecha_efectiva` y se cierra la anterior con `vigente_hasta = fecha_efectiva`. La versión «vigente ahora» es la que cumple `vigente_desde <= now() AND (vigente_hasta IS NULL OR vigente_hasta > now())`. Así el usuario sigue aceptando la versión actual hasta el día del cambio, y a partir de ese día queda en `desactualizado` y se le exige re-aceptar.

### 6.3 Hash y verificación de integridad

- `fn_documento_legal_hash()` calcula `encode(digest(texto_md, 'sha256'), 'hex')` **siempre**, ignorando cualquier hash enviado. El hash forma parte de la clave del `FOREIGN KEY` de `consentimientos`: una aceptación no puede apuntar a un texto que no existe.
- La app obtiene el documento por RPC (`fn_documentos_legales_vigentes`) y **hashea los bytes UTF-8 exactos** del `texto_md` recibido. La RPC de registro compara contra `documentos_legales.hash_sha256`; si no coincide, devuelve `texto_no_coincide` y no registra nada.
- Verificación periódica en superadmin: recalcular el hash de cada fila publicada y compararlo; cualquier divergencia es un incidente (§6.11).
- La aceptación registrada queda ligada a `(codigo, version, hash)`, de modo que cambiar una coma del texto obliga a publicar versión nueva y a re-aceptar.

### 6.4 RLS y permisos

```sql
ALTER TABLE muevete.documentos_legales ENABLE ROW LEVEL SECURITY;
ALTER TABLE muevete.consentimientos    ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON muevete.documentos_legales FROM PUBLIC;
REVOKE ALL ON muevete.consentimientos    FROM PUBLIC;
GRANT SELECT ON muevete.documentos_legales TO anon, authenticated;
GRANT SELECT ON muevete.consentimientos    TO authenticated;

-- Textos públicos (se pueden leer antes de registrarse: transparencia).
CREATE POLICY "documentos_legales_select_publico"
  ON muevete.documentos_legales FOR SELECT TO anon, authenticated
  USING (true);

-- El superadmin publica y audita; la app no escribe documentos.
CREATE POLICY "documentos_legales_all_superadmin"
  ON muevete.documentos_legales FOR ALL TO authenticated
  USING (muevete.is_superadmin()) WITH CHECK (muevete.is_superadmin());

-- El titular solo ve SUS consentimientos; el superadmin audita todos.
CREATE POLICY "consentimientos_select_own"
  ON muevete.consentimientos FOR SELECT TO authenticated
  USING (usuario_uuid = auth.uid());

CREATE POLICY "consentimientos_select_superadmin"
  ON muevete.consentimientos FOR SELECT TO authenticated
  USING (muevete.is_superadmin());

-- NO se crean políticas de INSERT/UPDATE/DELETE: quedan denegadas.
-- La única escritura posible es por RPC SECURITY DEFINER (propietario).
```

> **Prueba de que no hay atajo:** un `INSERT` directo a `muevete.consentimientos` con el `anon key` o con un JWT de usuario falla por RLS y por falta de `GRANT`; un `UPDATE`/`DELETE` falla además por el trigger. La aceptación solo puede entrar por `fn_registrar_consentimiento`, que exige sesión y valida el hash.

### 6.5 RPCs nuevas (firma y responsabilidad)

| RPC | Firma | Responsabilidad |
|---|---|---|
| `fn_documento_legal_vigente` | `(p_codigo text) → documentos_legales` | Devuelve la versión efectiva **ahora** (o nada si aún no entra en vigor). |
| `fn_documentos_legales_vigentes` | `() → jsonb` | Array `{codigo, version, titulo, texto_md, hash, vigente_desde, notificado_at}` para pintar la pantalla y calcular el hash. `SECURITY DEFINER` para funcionar también con `anon` (registro). |
| `fn_consentimiento_estado` | `(p_usuario uuid, p_codigo text) → text` | `sin_consentimiento` / `vigente` / `desactualizado` / `rechazado` / `pendiente_publicacion`. |
| `fn_consentimientos_ok` | `(p_usuario uuid, p_rol text) → jsonb` | `{ok, faltan:[...]}` con la lista de documentos obligatorios no vigentes. |
| `fn_registrar_consentimiento` | `(p_documentos jsonb, p_aceptado bool, p_motivo text, p_plataforma text, p_app_version text, p_dispositivo_id text, p_en_nombre_de text) → jsonb` | Registra una aceptación o un rechazo (uno por documento del array) en una sola transacción, con IP/UA del servidor y el rol del usuario. Si la cuenta es de empresa, marca `cuenta_tipo = 'persona_juridica'` y exige la razón social en `p_en_nombre_de`. Idempotente en ventanas de 10 s. |
| `fn_retirar_consentimiento` | `(p_codigo text, p_motivo text) → jsonb` | Inserta un evento `aceptado = false` (retirada). No borra nada. |
| `fn_publicar_documento_legal` | `(p_codigo, p_version, p_titulo, p_texto_md, p_vigente_desde, p_notificado bool) → jsonb` | Solo superadmin. Valida ≥ 90 días de aviso para versiones posteriores, cierra la anterior y publica la nueva. |
| `fn_mis_consentimientos` | `() → jsonb` | Estado e historial del usuario autenticado, para la pantalla «Privacidad». |
| `fn_puede_operar` | `(p_usuario uuid, p_rol text) → jsonb` | Consentimientos + perfil completo + (chofer) KYC aprobado. Devuelve `{puede_operar, faltan, perfil_incompleto}`. |
| `fn_exigir_operacion` | `(p_rol text) → void` | Lanza `consentimiento_requerido` (`ERRCODE P0001`, `DETAIL` con el JSON) si `auth.uid()` no puede operar. |
| `fn_exportar_consentimientos` | `(p_desde, p_hasta timestamptz, p_codigo text) → setof jsonb` | Solo superadmin; auditoría y exportación controlada. |
| `fn_purgar_datos_vencidos` | `() → jsonb` | Cron diario: histórico de posiciones > 90 días, tokens inactivos > 180 días; **nunca** consentimientos. |

**Esqueleto de `fn_registrar_consentimiento`** (referencia para H-Legal):

```sql
CREATE OR REPLACE FUNCTION muevete.fn_registrar_consentimiento(
  p_documentos   jsonb,
  p_aceptado     boolean,
  p_motivo       text DEFAULT NULL,
  p_plataforma   text DEFAULT 'desconocida',
  p_app_version  text DEFAULT NULL,
  p_dispositivo_id text DEFAULT NULL,
  p_en_nombre_de text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = muevete, public, extensions
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_doc   jsonb;
  v_cod   text; v_ver text; v_hash text;
  v_of    muevete.documentos_legales%ROWTYPE;
  v_ip    inet; v_ua text;
  v_rol   text;
  v_cuenta_tipo text;
  v_en_nombre   text;
  v_n     int := 0;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'no_autenticado'; END IF;
  IF p_documentos IS NULL OR jsonb_typeof(p_documentos) <> 'array'
     OR jsonb_array_length(p_documentos) = 0 THEN
    RAISE EXCEPTION 'documentos_vacios';
  END IF;

  -- Sello del servidor (no del cliente).
  v_ip := COALESCE(
    NULLIF(btrim(split_part(
      COALESCE(current_setting('request.headers', true)::jsonb ->> 'x-forwarded-for', ''), ',', 1)), '')::inet,
    inet_client_addr());
  v_ua := left(COALESCE(current_setting('request.headers', true)::jsonb ->> 'user-agent', ''), 500);

  v_rol := CASE
             WHEN EXISTS (SELECT 1 FROM muevete.drivers d WHERE d.uuid = v_uid) THEN 'chofer'
             ELSE 'cliente'
           END;

  -- Cuenta de empresa: la acepta el representante legal en nombre de la
  -- persona jurídica. En el registro el perfil aún no existe, así que la
  -- razón social enviada califica el evento; la coherencia con
  -- users.tipo_cuenta se exige al insertar el perfil (trigger).
  v_en_nombre := NULLIF(btrim(COALESCE(p_en_nombre_de, '')), '');
  v_cuenta_tipo := CASE
                     WHEN v_en_nombre IS NOT NULL THEN 'persona_juridica'
                     ELSE 'persona_natural'
                   END;
  IF EXISTS (SELECT 1 FROM muevete.users u
              WHERE u.uuid = v_uid AND u.tipo_cuenta = 'empresa')
     AND v_en_nombre IS NULL THEN
    RAISE EXCEPTION 'razon_social_requerida';
  END IF;

  FOR v_doc IN SELECT * FROM jsonb_array_elements(p_documentos) LOOP
    v_cod  := v_doc ->> 'codigo';
    v_ver  := v_doc ->> 'version';
    v_hash := v_doc ->> 'hash';

    SELECT * INTO v_of FROM muevete.documentos_legales d
      WHERE d.codigo = v_cod AND d.version = v_ver;
    IF NOT FOUND THEN RAISE EXCEPTION 'documento_inexistente: %', v_cod; END IF;
    IF v_hash IS DISTINCT FROM v_of.hash_sha256 THEN
      RAISE EXCEPTION 'texto_no_coincide: %', v_cod;          -- evita mostrar un texto y aceptar otro
    END IF;
    IF v_of.vigente_desde > now() THEN
      RAISE EXCEPTION 'documento_no_vigente_aun: %', v_cod;
    END IF;

    -- Idempotencia ante doble toque / reintento de red.
    IF EXISTS (SELECT 1 FROM muevete.consentimientos c
                WHERE c.usuario_uuid = v_uid AND c.documento_codigo = v_cod
                  AND c.documento_version = v_ver AND c.aceptado = p_aceptado
                  AND c.registrado_at > now() - interval '10 seconds') THEN
      CONTINUE;
    END IF;

    INSERT INTO muevete.consentimientos (
      usuario_uuid, usuario_rol, cuenta_tipo, en_nombre_de,
      documento_codigo, documento_version,
      documento_hash, aceptado, motivo, registrado_at, ip, user_agent,
      plataforma, app_version, dispositivo_id, origen)
    VALUES (
      v_uid, v_rol, v_cuenta_tipo, v_en_nombre,
      v_cod, v_ver,
      v_of.hash_sha256, p_aceptado, NULLIF(btrim(COALESCE(p_motivo,'')),''),
      now(), v_ip, v_ua,
      COALESCE(p_plataforma, 'desconocida'), p_app_version, p_dispositivo_id, 'app');
    v_n := v_n + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'registrados', v_n,
                            'usuario_rol', v_rol, 'cuenta_tipo', v_cuenta_tipo,
                            'consentimientos_ok', muevete.fn_consentimientos_ok(v_uid, v_rol));
END $$;

REVOKE ALL ON FUNCTION muevete.fn_registrar_consentimiento(jsonb,boolean,text,text,text,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION muevete.fn_registrar_consentimiento(jsonb,boolean,text,text,text,text,text) TO authenticated;
```

**Estados y re-aceptación.** `fn_consentimiento_estado` toma el **último evento** por documento (por `registrado_at, id`): si el último es un rechazo → `rechazado`; si es una aceptación cuya versión/hash no coincide con la versión efectiva actual → `desactualizado`; si coincide → `vigente`. Por eso una versión nueva invalida automáticamente todas las aceptaciones anteriores sin tocar filas: solo cambia la comparación.

### 6.6 Regla de no evasión: dónde se aplica el gate (servidor)

| Superficie | Regla | Mecanismo exacto |
|---|---|---|
| Registro de cliente | Consentimientos obligatorios del rol + CI y fotos del documento + mayoría de edad | Trigger `BEFORE INSERT` en `muevete.users` → `fn_consentimientos_ok` + validación de `NEW.ci`, `NEW.doc_frente_url`, `NEW.doc_dorso_url` |
| Registro de chofer | Ídem + licencias de conducción y circulación + KYC | Trigger `BEFORE INSERT` en `muevete.drivers` |
| **Cuenta de empresa** (persona jurídica) | Representante legal verificado (CI + fotos) + documento acreditativo de la empresa + datos fiscales; la aceptación se registra a nombre de la cuenta | Trigger `BEFORE INSERT` en `users`/`drivers` → cuando la cuenta se declara de empresa (`users.tipo_cuenta = 'empresa'`) exige `NEW.empresa_doc_url`, `empresa_nombre` y `empresa_rut`, además de la verificación del representante; `fn_registrar_consentimiento` guarda `en_nombre_de` |
| **Publicar viaje** (`fn_crear_solicitud`) | Cliente con consentimientos y perfil completo | Primera línea: `PERFORM muevete.fn_exigir_operacion('cliente');` |
| **Listar viajes** (`fn_viajes_disponibles`) | Chofer habilitado | Si `NOT (fn_puede_operar(auth.uid(),'chofer')->>'puede_operar')::boolean THEN RETURN;` |
| **Tomar viaje** (`fn_tomar_viaje`) | Chofer habilitado (defensa en profundidad) | `PERFORM muevete.fn_exigir_operacion('chofer');` antes del `UPDATE` atómico |
| Publicar ubicación (`place`, `track_place_history`) | Consentimiento de geolocalización vigente y ser el propio chofer | RLS `INSERT/UPDATE` con `fn_consentimiento_estado(auth.uid(),'consentimiento_geolocalizacion') = 'vigente'` y `driver_id` propio |
| Token push (`push_tokens`) | Consentimiento de datos vigente | RLS `INSERT/UPDATE` con `fn_consentimiento_estado(auth.uid(),'consentimiento_datos') = 'vigente'` |
| Botón de pánico / compartir viaje (nuevas) | Consentimientos de contactos y geolocalización | `fn_exigir_operacion('cliente'/'chofer')` + estado específico de `consentimiento_contactos_emergencia` cuando la función lo use |
| Recargar wallet (`fn_recargar_wallet`) | Consentimiento de datos vigente | `PERFORM muevete.fn_exigir_operacion(<rol>);` |
| Completar un viaje en curso | **No se bloquea** por retirada de consentimiento | Regla de seguridad: nunca abandonar a un pasajero; la retirada se aplica al finalizar |

**Inserto para las RPC del plan** (ejemplo real sobre la firma de `PLAN-IMPLEMENTACION.md` §5):

```sql
-- fn_crear_solicitud(...) — al inicio del cuerpo
PERFORM muevete.fn_exigir_operacion('cliente');

-- fn_tomar_viaje(p_solicitud_id bigint) — al inicio del cuerpo
PERFORM muevete.fn_exigir_operacion('chofer');

-- fn_viajes_disponibles() — al inicio
IF NOT COALESCE((muevete.fn_puede_operar(auth.uid(), 'chofer') ->> 'puede_operar')::boolean, false) THEN
  RETURN;
END IF;
```

**Prueba de no evasión del lado del cliente.** Llamar la RPC directamente (PostgREST/curl) sin consentimiento devuelve:

```json
{"code":"P0001","message":"consentimiento_requerido",
 "details":"{\"puede_operar\":false,\"faltan\":[\"consentimiento_geolocalizacion\"],\"perfil_incompleto\":[\"ci\",\"doc_frente_url\"]}"}
```

Un APK modificado no puede saltarlo: no tiene `service_role` (cuando se corrija el hallazgo 1.2.4) y las tablas no aceptan su escritura.

### 6.7 Cambio de versión y re-aceptación (aviso de 3 meses)

1. El responsable decide un cambio de texto. Se redacta la versión nueva (p. ej. `1.1.0`).
2. Se publica con `vigente_desde = fecha_efectiva` **≥ ahora + 90 días** (Res. 58/2022 art. 8.d). La RPC `fn_publicar_documento_legal` **rechaza** publicaciones con menos antelación cuando ya existe una versión anterior, salvo que sea la primera publicación.
3. Se **notifica** a todos los usuarios por correo, SMS, push y/o aviso en la app (se registra `notificado_at`). La app muestra un banner «Actualizaremos nuestros documentos el …» sin bloquear todavía.
4. En la fecha efectiva, la versión anterior se cierra (`vigente_hasta = fecha_efectiva`); las aceptaciones antiguas pasan a `desactualizado` automáticamente.
5. La app, al abrir y en cada operación, detecta `desactualizado` y muestra **pantalla bloqueante** hasta la re-aceptación. Los gates del servidor ya están cerrados: no hace falta esperar a la UI.
6. Si el usuario no acepta, puede seguir viendo los textos y solicitar la baja, pero no operar.
7. Excepción por seguridad urgente: **no** se ejecuta desde la app ni desde la consola. Solo mediante migración `service_role` firmada por el responsable, con revisión jurídica y registro de la excepción. `[VALIDAR]` si el ordenamiento cubano admite un aviso menor a 3 meses por cambio de seguridad.

### 6.8 Flujo UX (pantallas y copy exacto)

**Pantalla 1 — Registro (bloqueante).** Al final del formulario de registro, antes de «Crear cuenta», se muestran los avisos y casillas. El botón está **deshabilitado** hasta que todas las casillas obligatorias estén marcadas (ninguna premarcada).

```
ANTES DE EMPEZAR
Para usar Muévete necesitamos tu autorización. Léela con calma:
puedes consultar los textos completos en cualquier momento.

[ ] He leído y acepto los Términos y Condiciones de Uso (versión 1.0.0).  [Ver]
[ ] He leído y acepto la Política de Privacidad (versión 1.0.0).           [Ver]
[ ] Autorizo el tratamiento de mis datos personales para las finalidades
    descritas en la Política de Privacidad (versión 1.0.0).               [Ver]
[ ] Autorizo el uso de mi ubicación, incluso en segundo plano o con la app
    cerrada, para asignarme viajes, mostrar el trayecto y proteger mi
    seguridad (versión 1.0.0).                                            [Ver]
[ ] Autorizo la verificación de mi identidad con fotografías del frente y
    el dorso de mi carnet y, si soy chofer, de mis licencias (versión 1.0.0).[Ver]
[ ] Autorizo el uso de mis contactos de emergencia solo para avisarles si
    activo el botón de pánico o comparto un viaje (versión 1.0.0).
    Declaro que les informé.                                              [Ver]
[Solo cuentas de empresa] Razón social: ______________________________
[ ] Declaro ser mayor de 18 años y, si actúo por una empresa, tener su
    representación vigente y facultades para aceptar estos documentos.

[ Aceptar y continuar ]   (deshabilitado hasta marcar todo lo obligatorio)
[ No acepto ]
```

**Pantalla 2 — Visor del documento.** Título, versión, fecha de vigencia y hash visible en letra pequeña. Al pie: «He leído este documento» (marca local) y «Volver». El visor no puede modificar el texto.

**Pantalla 3 — Rechazo.** Diálogo con copy exacto:

```
SI NO ACEPTAS, NO PODRÁS USAR MUÉVETE
Sin estas autorizaciones no podemos crear tu perfil ni asignarte viajes.
Puedes cambiar de opinión cuando quieras desde Perfil → Privacidad.

[ Volver ]   [ Rechazar y salir ]
```

Si rechaza: se registra el rechazo (con `fn_registrar_consentimiento(p_aceptado=false)`), no se crea el perfil y se le lleva a una pantalla informativa:

```
TU CUENTA ESTÁ CREADA, PERO NO PUEDE OPERAR
Puedes aceptar las autorizaciones cuando quieras y completar tu registro.

[ Aceptar ahora ]   [ Eliminar mi cuenta ]   [ Cerrar sesión ]
```

**Pantalla 4 — Bloqueo al abrir la app** (consentimiento desactualizado, retirado o cuenta existente sin aceptación):

```
FALTA TU AUTORIZACIÓN
Actualizamos nuestros documentos (versión 1.1.0, vigente desde el 15/03/2027).
Para seguir usando Muévete, revisa y acepta la nueva versión.

[ Revisar y aceptar ]   [ Cerrar sesión ]
```

**Reglas de UX.**
- La pantalla es **bloqueante**: no se puede volver atrás ni saltar; el `Navigator` no permite *pop*.
- Si no hay red, **no se puede aceptar**: se muestra «Sin conexión: no podemos registrar tu aceptación. Inténtalo de nuevo cuando tengas internet». Se puede guardar la marca local para reintentar, pero **no se opera** hasta que el servidor confirme.
- Un doble toque no duplica evidencia (idempotencia de 10 s).
- Accesibilidad: casillas con etiqueta semántica, tamaño táctil ≥ 48 dp, contraste AA, texto escalable; el visor admite lector de pantalla.
- En Perfil → Privacidad: ver los documentos aceptados (versión, fecha), retirar cada consentimiento por separado y descargar una copia de los textos.

**Pantalla de aviso previo** (durante los 90 días anteriores al cambio): banner no bloqueante «Estamos actualizando nuestros documentos. Entrarán en vigor el …» con enlace al texto nuevo.

### 6.9 Reglas de negocio

**Menores de edad.**
- Requisito 18+ en Términos y en el registro (casilla propia, no premarcada).
- No se permite el registro de menores; no se implementa el consentimiento parental del art. 13 de la Ley 149 porque la actividad (transporte con licencia, pagos) exige capacidad contractual. `[VALIDAR]`
- Si se detecta una cuenta de menor: bloqueo inmediato, eliminación de datos en ≤ 30 días, conservando solo la evidencia de la incidencia.
- **Falta un dato para verificar la edad:** no existe `fecha_nacimiento` en `muevete.users`. Recomendación: añadirla como obligatoria en el registro (cambio de código del especialista Flutter) y validar 18+ en servidor; mientras no exista, la única prueba es la declaración, con el riesgo que implica (§8.8).

**Cuentas existentes (41 usuarios y 23 choferes; sin CI ni aceptación).**
- **No se fabrica consentimiento**: no se insertan filas `aceptado = true` para ellos.
- Al abrir la app después del despliegue, `fn_mis_consentimientos` / `fn_consentimientos_ok` devuelven todo pendiente y ven la pantalla bloqueante (pantalla 4). Aceptan, y luego un asistente de perfil les pide CI, fotos y (choferes) licencias.
- Mientras no lo completen: pueden iniciar sesión y ver su cuenta, pero **no publicar ni tomar viajes** (los gates ya están activos). Pasados **30 días** desde el aviso, la cuenta queda suspendida hasta completar el proceso (no se elimina).
- Los choferes que ya tenían KYC aprueban solo la parte de consentimiento + CI.
- La app ya tiene diálogo de actualización obligatoria (`widgets/update_dialog_helper.dart`): se usa para forzar la versión que incluye el consentimiento.

**Cuentas de empresa (persona jurídica).**
- La cuenta la abre el **representante legal**, que se verifica como persona física (CI y fotos) y acredita la representación con el **documento acreditativo de la empresa** y los **datos fiscales** (razón social, NIT/RUC, domicilio).
- Los documentos y consentimientos se aceptan **a nombre de la cuenta**: el evento queda con `cuenta_tipo = 'persona_juridica'`, `en_nombre_de` = razón social y `usuario_uuid` = representante legal. Así la evidencia dice **quién** aceptó y **por quién**.
- La empresa **responde por el uso de la cuenta y de sus usuarios**. Si cambia el representante legal, hay que verificarlo de nuevo y actualizar el documento; mientras no se acredite, la cuenta queda suspendida.
- Conservación: documento de la empresa y datos fiscales mientras la cuenta esté activa y **5 años** después de la baja (obligación fiscal, art. 17.a); CI y fotos del representante, **90 días** tras la verificación. `[VALIDAR]` el documento de representación exigible y su plazo.
- El alta de una cuenta de empresa exige comprobar que el documento acredita la **representación vigente**, no solo la constitución de la sociedad. `[VALIDAR]`

**Qué pasa si rechaza.**
- Se registra el rechazo con su versión y hash (evidencia de que se le informó).
- La cuenta de autenticación puede existir, pero **no se crea el perfil** y no puede operar.
- Puede aceptar después; el rechazo queda en el historial (no se borra).
- En la pantalla de rechazo se ofrece «Eliminar mi cuenta», que borra los datos y conserva solo la evidencia mínima.

**Retirada de un consentimiento ya otorgado.**
- Se registra como evento nuevo (`aceptado = false`) con motivo opcional.
- Efectos inmediatos: geolocalización → se detiene el servicio en segundo plano y no puede operar; identidad → cuenta bloqueada; datos → cuenta inutilizable (se ofrece baja); contactos → se desactivan pánico y viaje compartido.
- Si hay un viaje en curso, se completa por seguridad y la retirada se aplica al finalizar.
- No se borra la evidencia anterior: se conserva el historial completo (aceptó, retiró, volvió a aceptar).

**Conservación de la evidencia.**
- 5 años desde la última aceptación o la baja (art. 39.4), en tabla *append-only*.
- Tras la baja se conserva seudonimizada (UUID + hashes + fechas + IP), sin nombre, CI ni teléfono; se documenta en el procedimiento de baja. `[VALIDAR]`
- Revisión anual: `fn_purgar_datos_vencidos` **no** toca `consentimientos`; un procedimiento manual y firmado decide qué evidencia supera los 5 años y se destruye con acta.

**Personal y superadmin.**
- Confidencialidad firmada (art. 45 de la Ley 149).
- Acceso mínimo: solo el rol de verificación ve fotos del carnet; solo liquidaciones ve wallet; el superadmin que audita ve metadatos y estados, no necesariamente las imágenes.
- MFA recomendado para superadmin y registro de accesos a datos sensibles (§8.9).

### 6.10 Cómo probarlo (SQL + Flutter)

**SQL (`docs/plan-taxi-precio-fijo/sql/test_consentimiento.sql`).** Dentro de una transacción con `SET LOCAL role authenticated;` y `set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true)`:

1. **Sin consentimiento no hay viaje:** `SELECT muevete.fn_crear_solicitud(...)` → excepción `consentimiento_requerido`; `fn_tomar_viaje` idem.
2. **Aceptación válida:** `fn_registrar_consentimiento` con los seis documentos vigentes → `registrados = 6`; la fila tiene `ip` no nula, `user_agent` no nulo, `registrado_at` del servidor.
3. **Hash manipulado:** enviar un hash distinto → `texto_no_coincide`, sin filas nuevas.
4. **Documento futuro:** `vigente_desde > now()` → `documento_no_vigente_aun`.
5. **Inmutabilidad:** `UPDATE` y `DELETE` sobre `consentimientos` → excepción; `INSERT` directo con `authenticated` → denegado por RLS/GRANT.
6. **Aislamiento:** el usuario A no ve consentimientos de B (`SELECT` devuelve 0 filas).
7. **Re-aceptación:** publicar v1.1.0 con fecha futura; antes de la fecha `estado = 'vigente'`; después, `'desactualizado'` y `fn_puede_operar` → `false`.
8. **Perfil sin consentimiento:** `INSERT INTO muevete.users (...)` → excepción `consentimiento_requerido`.
9. **Perfil sin CI:** consentimiento completo pero `ci` nulo → excepción `ci_obligatorio`.
10. **Ubicación sin consentimiento:** `INSERT INTO muevete.track_place_history` con el usuario de prueba → denegado por RLS.
11. **Idempotencia:** dos llamadas idénticas seguidas → una sola fila.
12. **Auditoría:** `fn_exportar_consentimientos` devuelve lo esperado y solo con `is_superadmin()`.
13. **Cuenta de empresa:** alta sin `empresa_doc_url` → excepción; con documento y representante verificado, la aceptación queda con `cuenta_tipo = 'persona_juridica'` y `en_nombre_de = razón social`; el cambio de representante obliga a re-verificar.

**Flutter (`inventtia_muevete/test/legal/`).**
- Widget test: «Aceptar y continuar» deshabilitado con casillas vacías; se habilita al marcar las cinco obligatorias; la sexta (contactos) no bloquea.
- Test de flujo: rechazo → pantalla informativa → «Aceptar ahora» → perfil creado.
- Test de error de red al aceptar → mensaje «Sin conexión…» y no se navega.
- Test de bloqueo: sesión con `pendientes` no vacío → no se monta `HomeMapScreen`.

**Checklist de aceptación (Definition of Done).**
- [ ] Textos publicados con hash y versión; visibles sin sesión.
- [ ] Consents registrados con IP/UA del servidor; tabla append-only verificada.
- [ ] `fn_crear_solicitud` y `fn_tomar_viaje` fallan sin consentimiento (probado por PostgREST directo).
- [ ] Triggers de perfil bloquean altas sin consentimiento, sin CI y, en cuentas de empresa, sin documento acreditativo ni datos fiscales.
- [ ] RLS de `track_place_history` y `place` exige geolocalización vigente.
- [ ] Cambio de versión con 90 días y re-aceptación probado.
- [ ] Los 41 usuarios existentes ven la pantalla bloqueante y no operan hasta aceptar.
- [ ] Auditoría en superadmin operativa.
- [ ] Clave `service_role` fuera del cliente (hallazgo 1.2.4).

### 6.11 Auditoría desde superadmin

**Pantalla nueva** `ventiq_superadmin/lib/screens/muevete/muevete_consentimientos_screen.dart`, ruta `/muevete/consentimientos` (grupo «Muévete»), entrada en `widgets/app_drawer.dart`, `config/app_routes.dart` y `main.dart`; métodos en `services/muevete_service.dart`. Sigue el patrón de `muevete_kyc_screen.dart`.

**Contenido.**
1. **Documentos publicados:** código, versión, vigencia, hash, notificación, quién publicó. Botón «Verificar hash» (recalcula y compara) y «Próximos cambios» (versiones futuras y días restantes).
2. **Cumplimiento por versión:** tabla con usuarios por rol y por tipo de cuenta (persona natural/empresa), aceptados, pendientes, rechazos y retiradas. KPI grande: «% de usuarios operativos con consentimiento vigente».
3. **Pendientes:** lista de cuentas que no pueden operar, con motivo (`falta documento`, `perfil incompleto`, `KYC pendiente`, `empresa sin verificar`), filtro por rol y exportación CSV (con registro de la exportación).
4. **Rechazos y retiradas:** motivo, fecha, documento y versión; útil para mejorar los textos.
5. **Historial por usuario:** línea de tiempo de eventos (nunca editable).
6. **Integridad:** consulta que recalcula los hashes y alerta si alguno no coincide.
7. **Accesos a datos sensibles** (si se implementa el registro del §8.9): quién vio fotos de carnet y cuándo.

**Consultas de referencia.**

```sql
-- % de operativos con consentimiento vigente (por rol y versión)
SELECT c.usuario_rol,
       count(DISTINCT c.usuario_uuid) FILTER (WHERE e.estado = 'vigente') AS vigentes,
       count(DISTINCT c.usuario_uuid) AS con_historial
FROM muevete.consentimientos c
JOIN LATERAL (SELECT muevete.fn_consentimiento_estado(c.usuario_uuid, c.documento_codigo) AS estado) e ON true
GROUP BY c.usuario_rol;

-- Pendientes de aceptar (usuarios con perfil pero sin todos los vigentes)
SELECT u.uuid, u.name, 'cliente' AS rol,
       muevete.fn_consentimientos_ok(u.uuid, 'cliente') AS faltan
FROM muevete.users u
WHERE NOT (muevete.fn_consentimientos_ok(u.uuid, 'cliente') ->> 'ok')::boolean;

-- Documentos publicados y su hash
SELECT codigo, version, vigente_desde, vigente_hasta, notificado_at, hash_sha256
FROM muevete.documentos_legales ORDER BY codigo, vigente_desde DESC;
```

**Regla de oro de la consola:** puede **leer** y **publicar**, nunca editar ni borrar consentimientos. Toda publicación queda con `publicado_por` y `notificado_at`.

### 6.12 Plan de migración (orden seguro)

| Fase | Qué | Criterio de salida |
|---|---|---|
| **L0** | Migración 041 (tablas, RLS, funciones) + seed de los 6 documentos `1.0.0` con `vigente_desde = [FECHA]`. | Textos consultables sin sesión; hash verificado. |
| **L1** | Migración 042: RPC de registro, triggers de perfil, gates en las RPC de viaje (se integran en el mismo momento en que se crean `fn_crear_solicitud`/`fn_tomar_viaje`), RLS de ubicación. | Tests SQL 1–13 en verde. |
| **L2** | App: pantallas legales + casillas en registro + CI obligatoria + gate en splash + wizard para cuentas existentes + retirada en Perfil + alta de cuentas de empresa (representante legal + documento de la empresa). | Build de prueba con flujo completo. |
| **L3** | Distribución con actualización forzada; aviso a los 41 usuarios; apertura del plazo de 30 días. | 100 % de cuentas activas con consentimiento; 0 operaciones sin consentimiento. |
| **L4** | Migración 043: cron de purga + pantalla de auditoría en superadmin + procedimiento de incidentes. | Purga corriendo; auditoría usable. |
| **L5** | Revisión jurídica final, registro de la base de datos ante la autoridad y DPA con proveedores. | Expediente de cumplimiento firmado. |

**Compatibilidad.** Las apps viejas que inserten perfiles serán bloqueadas por los triggers (es intencional). El despliegue debe coordinarse con la actualización forzada para no dejar usuarios sin poder registrarse; el diálogo de actualización ya existe y debe apuntar a la versión con consentimiento.

---

## 7. C — Matriz dato → finalidad → base legal → conservación → quién accede

**Leyenda de base de licitud:** **C** = consentimiento expreso (arts. 10.l, 11 y 12); **L** = disposición legal (art. 17.a); **E** = emergencia / riesgo para una persona (art. 17.c); **A** = datos anonimizados o disociados (art. 17.f y art. 9 Res. 58/2022). Todas las bases marcadas con `[VALIDAR]` requieren confirmación del abogado.

| # | Dato | Finalidad | Base | Conservación | Quién accede |
|---|---|---|---|---|---|
| 1 | Nombre, email, teléfono, foto de perfil | Cuenta, contacto operativo, seguridad | C | Activa + 5 años | Titular; contraparte del viaje (limitado); soporte; superadmin; Supabase (encargado) |
| 2 | CI (`ci`, `tipo_documento`) | Identidad, antifraude, habilitación | C | Activa + 90 días tras verificación (se conserva resultado) | Solo verificación/KYC y superadmin auditado; **nunca** la contraparte |
| 3 | Fotos del carnet (frente/dorso) | Verificación de identidad | C | 90 días tras verificación; excepción por investigación de fraude `[VALIDAR]` | Solo rol de verificación con registro de acceso |
| 4 | **Cuenta de empresa:** documento acreditativo de la persona jurídica, datos fiscales (razón social, NIT/RUC, domicilio) y CI + fotos del **representante legal** | Verificar que quien contrata representa válidamente a la empresa, habilitar la cuenta y facturar | C | Documento y datos fiscales: activa + **5 años**; imágenes del representante: **90 días** tras la verificación | KYC, liquidaciones y superadmin con registro de acceso; **no** contrapartes |
| 5 | Licencias del chofer (conducción, circulación, operativa) | Habilitación legal para operar, verificación | C | Vigencia + 1 año tras la baja | KYC, superadmin, soporte |
| 6 | Provincia, municipio, dirección, país | Cobertura, asignación, facturación | C | Activa + 5 años | Titular; chofer (solo origen/destino del viaje); soporte |
| 7 | Ubicación en vivo (`place`) | Asignación y seguimiento del viaje | C | Mientras conectado; última posición 24 h | Chofer (propia); pasajero asignado (durante el viaje); soporte; superadmin |
| 8 | Histórico de posiciones (`track_place_history`, 387 351 filas) | Seguridad, disputas, antifraude, mejora | C | **90 días** en bruto; agregado anonimizado 1 año; luego borrado | Personal de seguridad/soporte con acceso restringido; **no** contrapartes; **no** marketing |
| 9 | Viajes: origen/destino, coordenadas, direcciones, km, precio, método de pago | Ejecutar, documentar, cobrar, defender | C + L `[VALIDAR]` | 5 años | Titular; contraparte (limitado); soporte; superadmin; autoridades con requerimiento |
| 10 | Valoraciones | Confianza y calidad | C | 2 años (autor anonimizado al año) | Contraparte (puntuación y comentario); superadmin |
| 11 | Wallet: saldos, transacciones, recargas, evidencia | Pagos, comisión, contabilidad | C + L `[VALIDAR]` | 5 años | Titular; liquidaciones; superadmin |
| 12 | Token push, plataforma, versión, notificaciones | Avisos operativos | C | Dispositivo activo; 180 días inactivo | Sistema; soporte |
| 13 | Contactos de emergencia (nombre, teléfono, relación) | Aviso en emergencia | C + declaración del titular `[VALIDAR]` | Mientras la cuenta; se borran al revocar | El contacto (solo al activarse); seguridad; **no** marketing |
| 14 | Eventos de pánico | Respuesta de seguridad y evidencia | C (geo) + E `[VALIDAR]` | 5 años | Equipo de seguridad; superadmin; autoridades con requerimiento |
| 15 | Enlaces de viaje compartido (token y accesos) | Seguridad de terceros elegidos por el titular | C (geo) | Token válido hasta fin del viaje + 30 días; log 90 días | Destinatarios elegidos por el titular; titular |
| 16 | Incidentes de seguridad reportados | Investigación y defensa | C + E `[VALIDAR]` | 5 años | Seguridad; superadmin; autoridades |
| 17 | Registros de consentimiento (versión, hash, fecha, IP, UA, **cuenta y razón social**) | Prueba de cumplimiento | L / C `[VALIDAR]` | 5 años | Titular (lectura); superadmin; autoridad |
| 18 | Logs de acceso y seguridad | Integridad y auditoría | L / seguridad (art. 10.f) | 2 años | Superadmin; responsable de seguridad |

**Notas de la matriz.**
- Los datos 2, 3 y 8 son los de mayor riesgo: identifican a la persona y revelan rutinas. Deben tener acceso restringido, registro y plazos cortos.
- Los datos 9 y 11 sostienen la defensa jurídica y la contabilidad: no se borran a los 30 días aunque el usuario los pida; se explican en la Política.
- La fila 13 tiene un problema de base jurídica (datos de terceros) que se analiza en §8.4.
- La fila 4 (empresa) no duplica la identidad del representante: su CI y sus fotos son las mismas de la fila 2-3, pero la verificación se hace **en su condición de representante** y se guarda la razón social a la que obliga (`en_nombre_de`).
- Cualquier nueva función aprobada (contactos, pánico, enlace compartido, incidentes) entra en esta matriz **antes** de implementarse; si no está en la matriz, no se recoge.

---

## 8. D — Riesgos y recomendaciones

### 8.1 Ubicación en segundo plano (batería, permisos del sistema operativo, tiendas)

**Riesgo.** La app declara `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `ACCESS_BACKGROUND_LOCATION`, `FOREGROUND_SERVICE` y `FOREGROUND_SERVICE_LOCATION` (`android/app/src/main/AndroidManifest.xml`). En Android 10+ la ubicación en segundo plano exige un permiso separado y un flujo de concesión adicional; en Android 14+ el servicio en primer plano debe declarar `foregroundServiceType="location"` y mostrar una notificación persistente. En iOS, el permiso «Always» exige justificación y explicación en el diálogo del sistema. El `background_service.dart` escribe `place` y `track_place_history` cada ~10 s mientras el chofer está online.

**Consecuencias.** Batería (quejas, desinstalaciones), muerte del servicio por optimizadores de fabricante (Xiaomi/Huawei/Samsung), denegación del permiso «Always» (el chofer no puede operar), y —si se publica en Google Play— rechazo por no cumplir la política de ubicación en segundo plano (declaración, divulgación destacada y vídeo de demostración). En Cuba la distribución suele ser por APK, pero si se publica en tiendas, la política aplica.

**Recomendaciones.**
- Solicitar el permiso «mientras se usa» y luego elevar a «siempre» **en el momento en que el chofer se conecta**, con pantalla explicativa propia (no solo el diálogo del sistema) y enlace a la Política.
- Reducir frecuencia: `distanceFilter` 25–50 m y envío por lotes cada 60 s (hoy 5 m/10 s); detener el servicio al desconectarse y al finalizar el viaje.
- Notificación persistente clara («Muévete está compartiendo tu ubicación como chofer conectado») con acción «Desconectarme».
- Guía de ahorro de batería por fabricante; detección de servicio muerto y reconexión.
- Si se publica en Play: preparar la declaración de ubicación en segundo plano y el vídeo; si no se cumple, publicar sin esa función es mejor que arriesgar la cuenta.
- `[VALIDAR]` requisitos concretos de Google Play y de la tienda que se use.

### 8.2 Histórico de 387 351 posiciones: ¿cuánto se conserva?

**Riesgo.** El histórico permite reconstruir rutinas, domicilio, trabajo, lugares de culto, reuniones o visitas médicas: datos que, cruzados, pueden revelar información sensible (art. 15) aunque no se recojan como tales. Además crece sin límite (10 s por posición, todo el tiempo que el chofer está conectado) y hoy no se ve una política de purga en el código.

**Recomendaciones (política concreta).**
| Capa | Plazo | Tratamiento |
|---|---|---|
| Posición en vivo (`place`) | Mientras conectado | Sobrescritura; última posición 24 h para soporte |
| Histórico bruto (`track_place_history`) | **90 días** | Borrado por cron; acceso restringido y registrado |
| Histórico agregado | 1 año | Por viaje/zona y **anonimizado o disociado**; sin identificador de chofer |
| Analítica | Indefinido | Solo agregados con k ≥ 10 y sin coordenadas exactas |

- Implementar `fn_purgar_datos_vencidos()` con `pg_cron` (extensión ya instalada) y alerta si falla.
- Reducir la escritura: un registro cada 60 s o por cambio de 50 m; guardar solo durante el viaje y el desplazamiento, no en toda la jornada.
- No permitir exportaciones masivas desde la consola; el mapa histórico del superadmin debe limitarse a 7 días por defecto.
- Documentar la retención en la Política (ya incluida) y en el registro de la base de datos (art. 41.i).
- `[VALIDAR]` si la conservación de 90 días es compatible con las necesidades de defensa legal; si no, justificar por escrito una ampliación (art. 39.4 permite otro plazo si el titular consiente o la ley lo dispone).

### 8.3 Exposición de la CI parcial en la verificación mutua

**Riesgo.** Si para «verificar» la identidad del pasajero o del chofer se muestra total o parcialmente el número de CI (o las fotos del carnet) a la contraparte, se abre la puerta a suplantaciones, acoso, extorsión y robo de identidad. Hoy la consola del dispatcher muestra `carnet` del chofer (`dispatcher_home_screen.dart:1487`), lo que es aceptable **solo** para personal interno con acceso restringido; el riesgo está en exponerlo al otro usuario.

**Recomendaciones.**
- **Nunca** mostrar el carnet ni las fotos a la contraparte. La verificación se comunica con un sello «Identidad verificada» y, como máximo, nombre de pila, foto de perfil y placa del vehículo.
- Si la operación exige una comprobación en el punto de recogida, usar un **código de viaje de un solo uso** (4–6 dígitos) que el pasajero dicta al chofer, o el QR del viaje; no la CI.
- Si por exigencia legal o de la autoridad hubiera que mostrar un dato parcial, mostrar solo los **4 últimos dígitos** enmascarados (`****1234`), únicamente durante el viaje, con registro de acceso, y nunca en notificaciones, logs ni capturas de pantalla.
- Excluir la CI de logs, mensajes de error, analítica y payloads push (el proveedor de notificaciones es externo).
- Capacitar al personal: la CI es dato de identificación de alto riesgo aunque la Ley 149 no la enumere como «sensible»; aplica igualmente el deber de confidencialidad (arts. 10.k y 45).

### 8.4 Datos de terceros: contactos de emergencia

**Riesgo.** El titular no puede consentir por sus contactos (la Ley 149 solo prevé representación para menores —art. 13— y apoyos —art. 14—). Guardar nombre y teléfono de terceros para usarlos «algún día» es un tratamiento sin base clara; el art. 17.c solo cubre el momento de la emergencia real.

**Recomendaciones.**
- **Opción A (recomendada): guardar los contactos solo en el dispositivo**, no en la base de datos. El botón de pánico envía el SMS/WhatsApp con la ubicación desde el propio teléfono. Cero datos de terceros en los servidores de la Plataforma.
- **Opción B (si se requiere servidor):** minimizar (nombre y teléfono), declaración del titular de que informó a la persona, uso exclusivo en emergencia, borrado inmediato al revocar, vía para que el contacto ejerza sus derechos, y revisión jurídica de la base. `[VALIDAR]`
- No incluir a los contactos en notificaciones push masivas ni en campañas.
- Registrar en la Política y en el consentimiento exactamente qué se hace (ya redactado en §5.4 y §3.7).

### 8.5 Cuentas de empresa: verificación del representante legal

**Riesgo.** Aceptar cuentas de personas jurídicas sin verificar quién las representa abre la puerta a cuentas creadas con documentos de empresas ajenas o extinguidas, a que alguien actúe fuera de sus facultades y a que la empresa eluda su responsabilidad. El carnet del representante es el mismo dato de alto riesgo que el de un particular; lo que cambia es que el consentimiento se otorga **a nombre de la cuenta**.

**Recomendaciones.**
- Exigir en el alta: CI y fotos del **representante legal**, **documento acreditativo de la empresa** (constitución y representación) y **datos fiscales**; verificar la **vigencia** de la representación, no solo la existencia de la sociedad. `[VALIDAR]` cuál es el documento exigible en Cuba y si basta copia o la constancia de verificación.
- Registrar la aceptación con `cuenta_tipo = 'persona_juridica'` y `en_nombre_de` (razón social), con el UUID del representante: así la evidencia dice **quién** aceptó y **por quién**.
- Si cambia el representante legal, **suspender la cuenta** hasta verificar al nuevo y actualizar el documento.
- La empresa titular responde por el uso que hagan sus usuarios; los datos de estos no se comparten con la empresa salvo lo necesario para administrar la cuenta (informado en la Política, punto 12).
- Conservar el documento de la empresa y los datos fiscales mientras la cuenta esté activa y **5 años** después de la baja (fiscal); las imágenes del carnet del representante, **90 días** tras la verificación.
- No aceptar como representante a un menor de edad ni a una persona cuyo CI no coincida con el documento de la empresa.
- No mostrar el documento de la empresa ni el CI del representante a otros usuarios ni incluirlo en notificaciones o logs.

### 8.6 Registro nacional de la base de datos y notificación de incidentes

**Riesgo.** Ley 149 arts. 40–43 y Disposiciones Especiales: la base debe declararse ante el control nacional (Ministerio de Justicia) y notificar cambios; el art. 48 y la Res. 58/2022 art. 4.c obligan a notificar incidentes de ciberseguridad. No hacerlo añade una infracción independiente del tratamiento.

**Recomendaciones.** Designar un **responsable de protección de datos** interno; elaborar el expediente con los 10 datos del art. 41 (finalidad, categorías, ubicación, medidas, cesiones, conservación, etc.); presentar la declaración cuando el registro esté operativo `[VALIDAR]`; y aprobar un **procedimiento de incidentes** con detección, contención, evaluación, notificación a la autoridad (objetivo interno: 72 h) y comunicación a los afectados si hay riesgo alto, con registro y post-mortem.

### 8.7 Obligatoriedad del consentimiento y libertad

**Riesgo.** El consentimiento debe ser «libre» (art. 10.l). Cuando la totalidad de los datos es obligatoria, el regulador podría considerar que no hay libertad real. La contrapartida es que el servicio no puede funcionar sin identidad, ubicación y datos de pago; la Ley 149 no contiene una cláusula tipo art. 7.4 del RGPD, pero la proporcionalidad del art. 10.a sí aplica.

**Recomendaciones.** Consentimientos **granulares** (ya diseñados), explicación clara de la consecuencia de no otorgar cada uno, alternativa real para lo no imprescindible (valoraciones, contactos, notificaciones), y revisión jurídica de la proporcionalidad de las fotos del carnet: si el abogado considera excesivo conservarlas, alternativa = verificación por videollamada o presencial, guardando solo el resultado. `[VALIDAR]`

### 8.8 Menores de edad

**Riesgo.** Sin `fecha_nacimiento` no se puede verificar la edad; la declaración es una prueba débil. Un menor con cuenta de chofer es un riesgo grave (conducción, contratos, datos).

**Recomendaciones.** Añadir `fecha_nacimiento` obligatoria en el registro (cambio de código), validar 18+ en servidor, bloquear y eliminar cuentas detectadas, y revisar el proceso de KYC para detectar incongruencias. `[VALIDAR]` la regla de edad mínima para licencia de conducción en Cuba.

### 8.9 Seguridad interna y acceso a datos sensibles

**Riesgo.** El mayor riesgo de fuga no es un hacker: es el acceso interno sin control. La consola permite hoy ver CI y documentos sin registro; la clave `service_role` en el cliente (hallazgo 1.2.4) agrava todo.

**Recomendaciones.** Rotar la clave `service_role`, retirarla del cliente, usar solo `anon` + RLS; MFA para superadmin; roles separados (KYC, liquidaciones, seguridad, auditoría); registro de accesos a datos sensibles en `muevete.accesos_datos_sensibles` (tabla append-only, RLS de lectura solo superadmin); enlaces firmados de 60 s para imágenes; prohibir descargas masivas; política de escritorio limpio y bloqueo tras inactividad; revisión trimestral de accesos.

### 8.10 Notificaciones push y minimización

**Riesgo.** El contenido de una notificación pasa por el proveedor externo de push y por el sistema operativo; si incluye nombre, dirección o CI, se produce una exposición innecesaria y un riesgo en la pantalla de bloqueo.

**Recomendación.** Notificaciones genéricas («Tienes un viaje disponible», «Tu chofer está llegando») y detalles solo dentro de la app; no incluir direcciones ni nombres; permitir desactivar notificaciones no esenciales.

### 8.11 App modificada y valor probatorio

**Riesgo.** Un APK modificado podría mostrar un texto distinto del canónico. El hash ata la aceptación al texto publicado, pero no impide que el usuario vea otra cosa.

**Recomendaciones.** Distribuir por canales controlados y con firma; usar Play Integrity/App Check si se publica en tienda; registrar también la versión de la app (`app_version`) en cada consentimiento (ya diseñado); y conservar el historial de versiones de los textos.

### 8.12 Presión de soporte y experiencia

**Riesgo.** Un bloqueo total puede disparar el abandono. Los 41 usuarios existentes tendrán que aceptar y completar perfil en un momento incómodo.

**Recomendaciones.** Wizard claro, posibilidad de aceptar y completar el perfil en dos pasos, mensajes que expliquen el «por qué» (seguridad y requisitos), y plazo de gracia de 30 días antes de suspender la cuenta (nunca antes para operar, que ya está bloqueado por los gates).

---

## 9. Supuestos

- **S1.** El responsable legal será una persona natural o jurídica cubana con los datos registrales que el usuario aporte; los `[HUECO]` se completan antes de publicar.
- **S2.** La fecha objetivo de primera publicación es **≥ 2026-12-15**; la de entrada en vigor se fija al publicar.
- **S3.** Existen 41 usuarios y 23 choferes; ninguno tiene evidencia de aceptación previa. No se fabrica consentimiento.
- **S4.** Los RPC `fn_crear_solicitud` y `fn_tomar_viaje` del plan se implementan después de las tablas legales o en la misma tanda, de modo que el gate se inserta desde su nacimiento.
- **S5.** La app seguirá distribuyéndose como APK (sin tienda) o, si se publica en tienda, se cumplirán sus políticas.
- **S6.** `pgcrypto` y `pg_cron` están disponibles (verificado en el plan §2.5).
- **S7.** Las cuentas de empresa se identifican con `tipo_cuenta = 'empresa'` en `muevete.users`; el **representante legal** es el usuario autenticado que acepta los documentos y opera la cuenta.
- **S8.** El personal de KYC es personal autorizado con contrato de confidencialidad.
- **S9.** Las nuevas funciones (contactos, pánico, viaje compartido, incidentes) no recogen datos adicionales no previstos en la matriz §7.
- **S10.** Los números de emergencia 106/105/104/107 son los vigentes; se confirman al publicar.
- **S11.** Cada persona jurídica tiene un representante legal identificable y un documento acreditativo vigente; si no lo aporta, no se abre la cuenta de empresa.

## 10. Riesgos

| ID | Riesgo | Prob. | Impacto | Mitigación |
|---|---|---|---|---|
| R1 | Clave `service_role` embebida en el APK | **Confirmada** | **Crítico** | Rotar clave; retirar del cliente; RLS real; auditoría de accesos |
| R2 | Registro nacional de la BD y notificación de incidentes no realizados | Alta | Alto (sanción, art. 56) | Designar DPO; expediente del art. 41; procedimiento de incidentes |
| R3 | Cambio de textos sin aviso de 3 meses | Media | Alto | `fn_publicar_documento_legal` exige ≥ 90 días; notificación registrada |
| R4 | Exposición de CI/fotos (interna o externa) | Media | Alto | No mostrar a contrapartes; buckets privados; log; minimización |
| R5 | Ubicación en segundo plano: batería, permisos, tienda | Alta | Medio-alto | Frecuencia reducida; educación; cumplimiento de políticas de tienda |
| R6 | Histórico de 387k posiciones sin retención | Alta | Alto | 90 días bruto + agregado; cron; acceso restringido |
| R7 | Consentimiento «no libre» por obligatoriedad total | Media | Medio | Granularidad; explicación; revisión de proporcionalidad |
| R8 | Datos de terceros (contactos) sin base clara | Media | Medio-alto | Guardar solo en el dispositivo; declaración; borrado |
| R9 | Menores sin verificación de edad | Media | Alto | `fecha_nacimiento` + validación 18+ |
| R10 | App modificada / texto no canónico | Baja | Medio | Hash; firma; integridad de app; versión registrada |
| R11 | Abandono por fricción en el registro | Media | Medio | UX clara, wizard, plazo de gracia, mensajes explicativos |
| R12 | Migración de datos y RLS mal probados | Baja | Alto | Tests SQL 1–13; migraciones aditivas y reversibles |
| R13 | `push_tokens` y notificaciones con datos personales | Media | Medio | Payload genérico; minimización |
| R14 | Cuenta de empresa con representación no acreditada o extinguida | Media | Alto | CI del representante + documento de la empresa + comprobar vigencia; suspender ante cambio de representante |

## 11. Recomendación

1. **No publicar los textos sin dictamen jurídico.** El usuario revisa y aprueba el contenido, pero la Ley 149 y la Res. 58/2022 exigen una lectura profesional del caso concreto (registro de la base, proporcionalidad, encuadre del intermediario y representación de las cuentas de empresa). Entregar este documento al abogado con el checklist del §12.
2. **Resolver primero el bloqueante técnico:** retirar la clave `service_role` del cliente y rotarla. Mientras siga embebida, la Política es falsa y cualquier control de consentimiento se puede saltar.
3. **Implementar 041 → 042 → 043 en ese orden**, con los gates en las RPC de viaje desde el primer momento y los tests SQL como puerta de calidad. La UI puede llegar después; el servidor no se negocia.
4. **Publicar los seis documentos `1.0.0` con hash**, con la pantalla bloqueante en el registro y en la apertura, y el flujo de rechazo/retirada ya descrito. No inventar consentimientos para los 41 usuarios.
5. **Aprobar la política de retención** del §7 y automatizarla con `pg_cron`; en particular, 90 días para el histórico de posiciones y 90 días para las imágenes del carnet.
6. **Aplicar el KYC de empresa:** representante legal verificado con su CI y fotos, documento acreditativo de la persona jurídica y datos fiscales; registrar la aceptación con `cuenta_tipo = 'persona_juridica'` y la razón social; suspender la cuenta ante cualquier cambio de representante hasta verificarlo.
7. **No mostrar la CI a la contraparte**; usar sello «identidad verificada» y código de viaje. Restringir y registrar el acceso interno.
8. **Designar un responsable de protección de datos**, firmar confidencialidades, preparar el expediente de registro de la base y el procedimiento de incidentes.
9. **Auditoría trimestral** desde superadmin: hashes, pendientes, rechazos, cuentas de empresa sin verificar y accesos; y revisión anual de los textos.
10. **Lanzar por fases** (L0–L5 del §6.12) con actualización forzada y aviso a los usuarios existentes.
11. **Medir el abandono** del registro y ajustar la UX sin relajar los gates.

---

## 12. Anexo — Checklist de validación legal

- [ ] Confirmar la naturaleza y datos registrales del responsable y el régimen aplicable (persona natural/MIPYME).
- [ ] Confirmar el documento que acredita la constitución y la representación vigente de una persona jurídica, y si la Plataforma debe conservar copia o solo la constancia de verificación.
- [ ] Confirmar el estado del control nacional de bases de datos (Ministerio de Justicia) y el procedimiento de declaración (arts. 40–43 y Disposiciones Especiales Primera y Segunda).
- [ ] Confirmar la autoridad y el plazo de notificación de incidentes (art. 48; Res. 58/2022 art. 4.c).
- [ ] Confirmar si la primera publicación de los documentos exige el aviso de 3 meses del art. 8.d de la Res. 58/2022.
- [ ] Confirmar la base de licitud de la conservación contable/fiscal (art. 17.a) y su plazo.
- [ ] Confirmar la base de licitud del uso de datos en emergencias (art. 17.c).
- [ ] Confirmar la proporcionalidad de exigir fotos del carnet y la alternativa si se considera excesiva.
- [ ] Confirmar la base del tratamiento de datos de contactos de emergencia y la opción de guardarlos solo en el dispositivo.
- [ ] Confirmar la regla de edad y si se admite consentimiento parental (art. 13) para 16–17 años en algún supuesto.
- [ ] Confirmar la autoridad competente para la acción de protección de datos (art. 30) en Villa Clara.
- [ ] Confirmar el encuadre del intermediario frente a MITRANS y la exigencia de licencia operativa del chofer.
- [ ] Confirmar los límites de responsabilidad admisibles frente a consumidores (Decreto-Ley 321/2014 y Código Civil).
- [ ] Confirmar los plazos y vías de reclamación del consumidor.
- [ ] Confirmar los números de emergencia y la posibilidad de integración con servicios públicos.

---

*Fin del documento. Versión 1.0.0 del anexo legal del plan de taxi con precio fijo. Cualquier cambio de los textos exige nueva versión, hash nuevo y re-aceptación conforme a §6.7.*