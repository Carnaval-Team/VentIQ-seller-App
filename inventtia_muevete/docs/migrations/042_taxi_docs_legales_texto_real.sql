-- ============================================================================
-- 042_taxi_docs_legales_texto_real.sql
-- Reemplaza los textos PLACEHOLDER de `muevete.documentos_legales` por el
-- TEXTO LEGAL REAL Y COMPLETO, versionado como 1.1.0. **BLOQUEANTE DE CUTOVER.**
--
-- ── OBJETIVO ────────────────────────────────────────────────────────────────
--   Hasta hoy las tres filas de `documentos_legales` (privacidad, terminos,
--   kyc) eran esqueletos de 279 / 460 / 388 caracteres que empezaban por
--   `<!-- PLACEHOLDER: reemplazar por el texto legal aprobado antes del
--   cutover -->`. Publicar la app con esos textos es publicar un consentimiento
--   sobre un documento que no dice nada. Esta migración:
--
--     1. CIERRA la versión vigente (1.0.0) de cada código con
--        `vigente_hasta = now()`. NO se borra: queda el historial y las
--        aceptaciones que ya existan siguen apuntando a ella.
--     2. INSERTA la versión 1.1.0 con el texto completo, `publicado = true`,
--        `es_obligatorio = true`, `vigente_desde = now()`, `vigente_hasta = NULL`.
--     3. Deja que el TRIGGER calcule `hash_contenido` (ver nota de abajo).
--     4. Comprueba, antes de hacer COMMIT, que los tres textos son largos, no
--        contienen la marca de placeholder y tienen hash. Si algo falla, la
--        migración aborta entera.
--
-- ── DE DÓNDE SALE EL TEXTO ──────────────────────────────────────────────────
--   Fuente: `docs/plan-taxi-precio-fijo/08-privacidad-y-consentimiento.md`
--   (revisión 1.1, 2026-11-12), §3 (Política), §4 (Términos), §5.1–§5.4
--   (consentimientos) y §7 (matriz dato → finalidad → base → conservación).
--
--   · DE LA FUENTE, ÍNTEGROS Y ADAPTADOS A LA APP: los capítulos, la
--     estructura, la matriz de datos, las finalidades, las bases legales y los
--     plazos de conservación de la Política y de los Términos.
--   · REDACTADO AQUÍ (no venía listo en el anexo): el documento `kyc`
--     completo —el anexo lo trata como «consentimiento_identidad» dentro de una
--     lista de cuatro, no como documento autónomo— y la costura entre los tres
--     documentos (remisiones, canal de contacto único, aviso de re-aceptación
--     idéntico en los tres). Ver «PENDIENTE DE FIRMA LEGAL» más abajo.
--   · ELIMINADO A PROPÓSITO: todas las marcas `[VALIDAR]`, `[HUECO: …]`,
--     `[FECHA]` y `[HASH]` del anexo. Son notas internas del borrador, no texto
--     para el usuario, y no pueden quedar en la app.
--
--   Decisiones cerradas del usuario que estos textos respetan al pie de la
--   letra (revisión 1.1 del anexo):
--     · NO se menciona el alojamiento ni la ubicación de los servidores, y NO
--       se menciona ninguna transferencia internacional de datos. No aparece
--       ni una vez «servidores nacionales», «alojamiento», «transferencia» ni
--       el país donde se aloja nada.
--     · Consentimiento VERSIONADO con re-aceptación OBLIGATORIA al cambiar de
--       versión, y auditoría explícita (fecha y hora, IP, dispositivo, versión
--       de la app, versión y huella del texto). Está en Privacidad §18,
--       Términos §16 y §18, y KYC §13.
--     · Quedan tratados y nombrados todos los datos sensibles: CI, fotos del
--       carnet frente y dorso, provincia/municipio/poblado, dirección,
--       teléfono, ubicación durante el viaje y contactos de emergencia
--       (teléfono de un tercero, con declaración de autorización del titular).
--     · El tratamiento para verificación de identidad es un documento APARTE
--       (`codigo = 'kyc'`), y los otros dos lo referencian sin repetirlo.
--
-- ── ⚠️ PENDIENTE DE FIRMA LEGAL ─────────────────────────────────────────────
--   Estos textos son el borrador profesional del anexo, cerrado en contenido,
--   NO asesoría jurídica firmada. El anexo §11.1 lo dice: no se publican sin
--   dictamen. Lo que falta es exactamente lo que un dato interno no puede
--   suplir y por eso NO se inventó aquí:
--     1. Identificación registral del responsable (denominación, domicilio,
--        NIT/RUC y registro). En el texto se resuelve diciendo que se entrega
--        por escrito a quien la solicite por el canal de contacto, y que se
--        publica en la sección de información legal de la app. Al firmar hay
--        que sustituir esa fórmula por los datos concretos.
--     2. Correo y teléfono de privacidad. Hoy `muevete.configuracion_seguridad
--        .contacto_soporte` está VACÍO y no hay buzón de privacidad definido,
--        así que el canal de contacto se describe como el flujo dentro de la
--        app (Perfil → Privacidad → Contactar al responsable) más el soporte
--        publicado. Al firmar hay que poner el buzón real y, si se quiere,
--        cablearlo en `contacto_soporte`.
--     3. Confirmación de los plazos de conservación y del encuadre del
--        intermediario (anexo §12, checklist).
--     4. Los números de emergencia (106/105/104/107) citados en Términos §11.
--
-- ── DISCREPANCIAS DETECTADAS (para el responsable, no se tocan aquí) ───────
--   a) `muevete.configuracion_seguridad.dias_retencion_ubicaciones = 30`,
--      mientras el texto aprobado (anexo §7 y §8.2) promete conservar el
--      histórico de posiciones **hasta 90 días**. El texto se redactó con la
--      fórmula «hasta 90 días» + «la depuración se ejecuta conforme a la
--      configuración vigente», que es cierta con 30 y con 90, pero hay que
--      decidir: o se sube la configuración a 90, o se enmienda el texto.
--   b) `meses_retencion_incidentes = 24` frente a los 5 años del anexo §7
--      (fila 14). Mismo criterio: el texto dice «hasta 5 años o hasta que
--      prescriba la acción», que admite una depuración anterior.
--   Ninguna de las dos se corrige en esta migración: 042 sólo publica texto.
--
-- ── DEPENDENCIAS ────────────────────────────────────────────────────────────
--   · 036_taxi_identidad_consentimiento.sql — crea `muevete.documentos_legales`,
--     el trigger `trg_documentos_legales_hash`, `muevete.fn_doc_legal_hash()`,
--     `muevete.consentimientos` y el gate `muevete.fn_usuario_habilitado()`.
--     **No se redefine nada de eso aquí.**
--   · 038/039/040 — las RPC de viaje consultan el gate, que es quien exige
--     re-aceptar. Esta migración no las toca.
--   · `pgcrypto` (ya instalado) para el `digest()` del trigger de hash.
--   · `timezone 'America/Havana'` sólo para escribir la fecha de vigencia
--     dentro del texto con el formato cubano DD/MM/AAAA.
--
-- ── NOTA SOBRE `hash_contenido` (revisado en la BD antes de escribir esto) ──
--   La firma real es:
--       muevete.fn_doc_legal_hash() RETURNS trigger, LANGUAGE plpgsql
--       (sin argumentos, SECURITY INVOKER, SET search_path = muevete, …)
--   Es una función de TRIGGER, no una función escalar: **no se puede llamar
--   desde SQL** para calcular el hash de un texto (`select
--   muevete.fn_doc_legal_hash('...')` falla; y `fn_doc_legal_hash()` devuelve
--   un `trigger`, no un `text`). El hash lo calcula el trigger
--   `trg_documentos_legales_hash` (BEFORE INSERT OR UPDATE OF contenido_md)
--   como `encode(digest(coalesce(NEW.contenido_md,''), 'sha256'), 'hex')`.
--   Por eso **NO se pone `hash_contenido` a mano en el INSERT**: se omite de la
--   lista de columnas y lo rellena el trigger. Escribirlo a mano sería, además,
--   la única forma de que el texto y su huella pudieran no coincidir.
--
-- ── IDEMPOTENCIA ────────────────────────────────────────────────────────────
--   1. El UPDATE que cierra la versión vigente lleva `version <> '1.1.0'`.
--      Es el detalle que hace la migración re-ejecutable: en la segunda pasada
--      la única fila con `vigente_hasta IS NULL` es la 1.1.0, y el filtro la
--      excluye, así que no se cierra a sí misma.
--   2. El INSERT es `INSERT … SELECT … WHERE NOT EXISTS (… codigo = X AND
--      version = '1.1.0')`: la segunda pasada no inserta nada.
--   3. `BEGIN; … COMMIT;` único: el índice parcial
--      `documentos_legales_vigente_uidx (codigo) WHERE publicado AND
--      vigente_hasta IS NULL` exige que el cierre de la 1.0.0 y la publicación
--      de la 1.1.0 ocurran en la misma transacción (primero se libera el
--      hueco, después se ocupa).
--   4. Re-ejecutar dos veces no debe fallar ni cambiar ninguna fila.
--
-- ── NO EJECUTAR CONTRA PRODUCCIÓN DESDE ESTE ENTORNO. ──────────────────────
--   Validada en el proyecto de PRUEBAS `qhprswhhfasrikhawjoz`.
-- ============================================================================

BEGIN;

-- ----------------------------------------------------------------------------
-- 0. Prerrequisitos (falla ruidoso si el entorno no es el esperado)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_falta text[] := ARRAY[]::text[];
BEGIN
  IF to_regclass('muevete.documentos_legales') IS NULL THEN
    v_falta := array_append(v_falta, 'tabla muevete.documentos_legales (036)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_doc_legal_hash') THEN
    v_falta := array_append(v_falta, 'muevete.fn_doc_legal_hash() (036)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
                  JOIN pg_namespace n ON n.oid = c.relnamespace
                  WHERE n.nspname = 'muevete' AND c.relname = 'documentos_legales'
                    AND t.tgname = 'trg_documentos_legales_hash') THEN
    v_falta := array_append(v_falta, 'trigger trg_documentos_legales_hash (036)');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'muevete' AND p.proname = 'fn_usuario_habilitado') THEN
    v_falta := array_append(v_falta, 'muevete.fn_usuario_habilitado() (036)');
  END IF;

  IF cardinality(v_falta) > 0 THEN
    RAISE EXCEPTION 'prerrequisitos_faltantes: %', v_falta USING ERRCODE = 'P0001';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. Cerrar la versión vigente de cada código
--    `version <> '1.1.0'` es lo que hace esto idempotente (ver cabecera).
--    No se borra ninguna fila: la 1.0.0 queda con su hash y sus aceptaciones.
-- ----------------------------------------------------------------------------
UPDATE muevete.documentos_legales
   SET vigente_hasta = now()
 WHERE codigo IN ('privacidad', 'terminos', 'kyc')
   AND version <> '1.1.0'
   AND vigente_hasta IS NULL;

-- ----------------------------------------------------------------------------
-- 2. Publicar la versión 1.1.0 — POLÍTICA DE PRIVACIDAD
--    `hash_contenido` NO se enumera: lo calcula el trigger (ver cabecera).
-- ----------------------------------------------------------------------------
INSERT INTO muevete.documentos_legales
  (codigo, version, titulo, resumen, contenido_md,
   es_obligatorio, publicado, vigente_desde, vigente_hasta)
SELECT
  'privacidad',
  '1.1.0',
  'Política de Privacidad',
  'Qué datos tratamos, para qué, con quién, durante cuánto tiempo y cómo ejercer tus derechos.',
  '# POLÍTICA DE PRIVACIDAD DE MUÉVETE' || E'\n\n' ||
  '**Versión 1.1.0 · Vigente desde el '
    || to_char(now() AT TIME ZONE 'America/Havana', 'DD/MM/YYYY') || '**' || E'\n\n' ||
  $md$
## 1. Quién responde por tus datos

El responsable del tratamiento de tus datos personales es la entidad que opera la aplicación **Muévete** (en adelante, «Muévete» o «la Plataforma»), que decide para qué y cómo se tratan los datos que nos das al crear tu cuenta y al usar el servicio.

Los datos de identificación completos del responsable —denominación, domicilio legal, municipio y provincia, número de identificación tributaria y registro— se entregan por escrito y sin coste a cualquier titular que los solicite por el canal de contacto del punto 16, dentro de los cinco días hábiles siguientes.

Esta Política se lee junto con los **Términos y Condiciones de Uso** y con el documento **«Uso y tratamiento de datos para la verificación de identidad»**, que explica con detalle qué hacemos con tu carnet y con las fotos de tu documento. Los tres son obligatorios y se aceptan por separado, cada uno con su propia casilla.

## 2. A qué se aplica esta Política

Se aplica a los datos personales que tratamos cuando:

- te registras como pasajero o como chofer;
- abres o administras una cuenta a nombre de una empresa (persona jurídica) como representante legal;
- pides, aceptas, realizas o pagas un viaje;
- activas las funciones de seguridad (botón de pánico, contactos de emergencia, viaje compartido);
- escribes a soporte o presentas una reclamación.

No se aplica a lo que un chofer o un pasajero hagan por su cuenta fuera de la aplicación. Cuando el chofer presta el servicio de transporte actúa como prestador independiente y responde de sus propios tratamientos; Muévete sólo le entrega los datos imprescindibles para hacer el viaje.

## 3. Qué datos tratamos

| Datos | ¿Son obligatorios? | Para qué |
|---|---|---|
| Nombre y apellidos, correo electrónico, teléfono y foto de perfil | Sí, para tener cuenta | Crear y administrar tu cuenta, contactarte por el viaje e identificarte ante la otra parte del viaje |
| Número de carnet de identidad (CI), tipo de documento y fotografías del frente y del dorso del carnet | Sí | Verificar que eres quien dices ser, evitar suplantaciones y fraude y habilitarte para operar |
| Provincia, municipio, poblado y dirección | Sí | Comprobar que operas en la zona donde damos servicio, coordinar la recogida y atender reclamaciones |
| Ubicación del dispositivo durante el viaje, y del chofer mientras está conectado | Sí | Asignar viajes, mostrar el recorrido, calcular distancia y precio y atender emergencias |
| Datos del viaje: origen, destino, distancia, duración, precio, forma de pago, estado y cancelaciones | Sí | Ejecutar y documentar el servicio, cobrar y atender reclamaciones |
| Monedero: saldo, recargas, comisiones y transacciones | Sí, si usas el monedero | Cobrar la comisión, liquidar saldos y llevar la contabilidad |
| Valoraciones y comentarios sobre el viaje | No | Confianza y calidad del servicio |
| Contactos de emergencia: nombre, teléfono y relación contigo | No (voluntario) | Avisarles sólo si activas el botón de pánico o compartes un viaje |
| Token del dispositivo, plataforma, versión de la aplicación y notificaciones enviadas | Sí, para poder avisarte | Enviarte los avisos operativos del viaje |
| Dirección IP, datos del dispositivo y registros de aceptación de documentos | Sí, al aceptar | Probar que aceptaste los documentos y proteger la Plataforma |

**Datos obligatorios.** Los marcados como obligatorios son necesarios para prestarte el servicio. Si no los aportas no podemos crear tu cuenta o no podemos asignarte viajes, y te lo decimos en el momento en que te los pedimos.

**Datos opcionales.** Los valoraciones y los contactos de emergencia son voluntarios: puedes operar sin ellos, pero no podrás usar las funciones que dependen de esos datos (en el caso de los contactos, el botón de pánico y el viaje compartido).

**No tratamos** datos de salud, creencias religiosas, filiación política ni orientación sexual. Si alguna función futura los necesitara, te pediríamos un consentimiento aparte y expreso antes de recogerlos.

## 4. Para qué usamos tus datos y con qué base legal

| Finalidad | Datos que usa | Base legal |
|---|---|---|
| Crear y administrar tu cuenta y prestarte el servicio | Identificación y contacto | Tu consentimiento expreso y la aceptación de los Términos y Condiciones |
| Verificar tu identidad y habilitarte para operar | CI, fotos del carnet y licencias | Tu consentimiento expreso, recogido en el documento de verificación de identidad |
| Geolocalizarte durante el viaje | Ubicación | Tu consentimiento expreso |
| Asignar, ejecutar y documentar viajes y calcular el precio | Ubicación y datos del viaje | Tu consentimiento expreso y la aceptación de los Términos y Condiciones |
| Cobrar la comisión, liquidar el monedero y llevar la contabilidad | Datos del monedero | Tu consentimiento expreso y, para la conservación contable, el cumplimiento de una obligación legal |
| Avisarte de lo que pasa en el viaje | Token, plataforma y versión | Tu consentimiento expreso |
| Atender emergencias y proteger tu seguridad | Contactos, ubicación y eventos de pánico | Tu consentimiento expreso y la protección de una persona en peligro |
| Atender reclamaciones y defender nuestros derechos | Datos del viaje y de la reclamación | Tu consentimiento expreso y el cumplimiento de obligaciones legales |
| Prevenir fraude y usos indebidos | Identidad, dispositivo y patrones de viaje | Tu consentimiento expreso y nuestro deber de seguridad |
| Estadísticas y mejora del servicio | Datos anonimizados o disociados | Datos que ya no permiten identificarte |
| Cumplir requerimientos de las autoridades | Sólo lo estrictamente solicitado | Cumplimiento de una obligación legal; se registra cada entrega |

**No vendemos tus datos personales, no los cedemos para publicidad y no los usamos para elaborar perfiles comerciales.**

## 5. Tu ubicación durante el viaje

**Qué recogemos.** Mientras un chofer está conectado, la aplicación envía periódicamente su posición para que pueda recibir viajes. Mientras un pasajero tiene un viaje activo, se envía su posición para mostrar el recorrido y calcular distancia, precio y tiempo. En ambos casos la recogida **continúa con la aplicación en segundo plano o cerrada**, porque el servicio deja de funcionar si la ubicación se interrumpe cada vez que se apaga la pantalla.

**Para qué.** Asignarte viajes compatibles con la zona; mostrar al pasajero dónde está su chofer; calcular el precio y la distancia; detectar desvíos; atender emergencias, incidentes y reclamaciones; prevenir el fraude.

**Qué no hacemos.** No mostramos tu ubicación a otros usuarios fuera del viaje, no la publicamos, no la vendemos y no la usamos para publicidad. El histórico de posiciones sólo lo consulta personal autorizado, con acceso registrado.

**Cómo desactivarla.** Puedes retirar el permiso de ubicación desde los ajustes del teléfono o retirar el consentimiento desde la aplicación, en Perfil → Privacidad. Si lo retiras, **no podrás solicitar ni aceptar viajes ni mantenerte conectado como chofer**, porque sin ubicación el servicio no existe. Si lo retiras con un viaje en curso, el viaje se termina por seguridad y la retirada se aplica al finalizar.

## 6. Tu carnet y las fotos de tu documento

Para verificar tu identidad tratamos tu número de carnet de identidad, el tipo de documento y las fotografías del frente y del dorso. En los choferes tratamos además las fotografías de la licencia de conducción y de la licencia de circulación del vehículo; en las cuentas de empresa, el documento que acredita la representación y los datos fiscales de la empresa.

La finalidad, quién las revisa, cómo se guardan, cuánto tiempo se conservan y qué ocurre si no das tu consentimiento están explicados, en detalle y por separado, en el documento **«Uso y tratamiento de datos para la verificación de identidad»**, que aceptas junto con esta Política. En resumen: **el pasajero no ve el carnet del chofer ni el chofer ve el carnet del pasajero**; las imágenes las revisa únicamente personal autorizado, se guardan en almacenamiento privado con enlaces temporales y se eliminan cuando termina la verificación, conservando sólo el resultado y la fecha.

## 7. Contactos de emergencia

Puedes registrar personas a las que avisar si activas el botón de pánico o compartes un viaje. De ellas tratamos **nombre, teléfono y relación contigo**, y se usan **sólo** para esa finalidad: no les enviamos publicidad ni los incluimos en ninguna otra comunicación.

Al registrar un contacto **declaras que le informaste** de que podríamos contactarle en una emergencia y que es mayor de edad. Puedes retirar este consentimiento y eliminar los contactos en cualquier momento; si lo haces, no podrás usar el botón de pánico ni compartir viajes.

La persona contactada puede ejercer sus derechos sobre sus propios datos (saber qué tenemos, rectificarlo o pedir que lo borremos) por el canal de contacto del punto 16.

## 8. Pagos y monedero

Registramos saldos, comisiones, transacciones, recargas y la evidencia que aportes de una recarga (por ejemplo, el número de operación o una captura). **No almacenamos números de tarjetas bancarias ni códigos de seguridad.** Los datos económicos sólo los consulta el personal autorizado para liquidaciones, contabilidad y atención de reclamaciones.

## 9. Viajes, direcciones y valoraciones

Registramos el origen y el destino del viaje, las coordenadas, las direcciones, la distancia, el precio y la forma de pago para ejecutar el servicio, emitir el comprobante, atender reclamaciones y defendernos ante un proceso. Las valoraciones se muestran de forma agregada y sin exponer datos de contacto.

## 10. Notificaciones y token del dispositivo

Para avisarte usamos un identificador técnico del teléfono (token) y la plataforma (Android). **No incluimos direcciones, nombres ni datos del carnet en el contenido de las notificaciones**: la notificación te avisa y los detalles los ves dentro de la aplicación. Puedes desactivar las notificaciones del sistema, aunque algunas son necesarias para operar.

## 11. Menores de edad

Muévete es **sólo para personas mayores de 18 años**. No recogemos conscientemente datos de menores. Si detectamos que una cuenta pertenece a un menor, la bloqueamos y eliminamos sus datos personales, conservando sólo la evidencia mínima de la incidencia.

Si eres padre, madre o representante y crees que un menor nos dio datos, escríbenos por el canal del punto 16 y lo resolvemos.

## 12. Con quién compartimos tus datos

| Destinatario | Qué recibe | Cuándo |
|---|---|---|
| **La otra parte del viaje** (tu chofer o tu pasajero) | Nombre, foto de perfil, valoración y teléfono; origen, destino y recorrido. **Nunca el carnet ni las fotos del documento** | Sólo cuando el viaje está asignado y mientras se ejecuta |
| **Personal autorizado de Muévete** | Lo estrictamente necesario según su función (verificación, soporte, liquidaciones, seguridad) | Con acceso registrado y obligación de confidencialidad |
| **La empresa titular de la cuenta**, si la cuenta es de empresa | Datos de la cuenta, de sus usuarios y de los viajes que gestione | Cuando la cuenta es de empresa y la empresa administra usuarios |
| **Proveedores tecnológicos que actúan como encargados del tratamiento**: Supabase (base de datos, autenticación y almacenamiento), Pushy (notificaciones al teléfono), OpenStreetMap, Nominatim y OSRM (mapas, búsqueda de direcciones y rutas) y los servidores de teselas del mapa | Sólo los datos necesarios para su función: el token y el texto genérico de la notificación; las coordenadas de origen y destino o la zona consultada | Cuando usas la aplicación, cuando se envía una notificación o cuando pides una ruta |
| **Autoridades** | Lo estrictamente requerido por ley, por resolución judicial o fiscal, o en una emergencia real | Con registro de la entrega |
| **Otros** | Ninguno. No vendemos ni cedemos datos a terceros con fines publicitarios | — |

Los proveedores que actúan como encargados están obligados por contrato a tratar los datos sólo siguiendo nuestras instrucciones y a aplicar medidas de seguridad y confidencialidad.

## 13. Cuánto tiempo conservamos tus datos

| Dato | Plazo | Por qué |
|---|---|---|
| Cuenta y perfil | Mientras la cuenta esté activa y hasta 5 años desde la última actividad o desde la baja | Obligación legal de conservación |
| CI y fotos del carnet, y licencias del chofer | Durante la verificación y hasta 90 días después; luego se eliminan las imágenes y se conserva el resultado, la fecha y un resumen técnico | Necesidad de la verificación y minimización |
| Documento de la empresa y datos fiscales | Mientras la cuenta esté activa y hasta 5 años después de la baja | Obligación fiscal |
| Ubicación en vivo | Mientras estás conectado o en viaje; la última posición se conserva 24 horas para soporte | Minimización |
| Histórico de posiciones | Hasta 90 días en bruto; después se agrega y se anonimiza para estadísticas y se elimina el dato individual | Minimización y mejora del servicio |
| Viajes, precios, comprobantes y reclamaciones | Hasta 5 años | Defensa jurídica y obligación legal |
| Monedero y transacciones | Hasta 5 años | Contabilidad y obligación legal |
| Contactos de emergencia | Mientras la cuenta esté activa; se borran al retirar el consentimiento o al cerrar la cuenta | Minimización |
| Eventos de pánico e incidentes | Hasta 5 años o hasta que prescriba la acción | Defensa y seguridad |
| Registros de aceptación de documentos (versión, huella, fecha, IP, dispositivo) | 5 años desde la última aceptación o desde la baja | Probar el cumplimiento |
| Notificaciones y token | Mientras el teléfono esté activo; 180 días de inactividad | Minimización |
| Registros de seguridad y accesos | 2 años | Seguridad |

**La depuración se ejecuta de forma automática** conforme a la configuración vigente del servicio, por lo que varios de estos datos se suprimen antes de alcanzar el plazo máximo indicado. Cuando termina el plazo, los datos se suprimen de oficio o a tu solicitud. La evidencia de consentimiento puede conservarse seudonimizada para poder demostrar el cumplimiento.

## 14. Seguridad

Adoptamos medidas técnicas y organizativas para proteger tus datos: control de acceso por roles, cifrado en tránsito, almacenamiento privado de documentos con enlaces temporales, registro de accesos, copias de seguridad, revisión de permisos y formación del personal. Ningún sistema es infalible; si ocurre un incidente, actuamos según el punto 17.

## 15. Tus derechos y cómo ejercerlos

Puedes ejercerlos en cualquier momento, sin orden de prelación y **sin pagar nada**:

- **Acceso:** saber qué datos tenemos y cómo los tratamos.
- **No divulgación e intimidad:** que no se difundan tus datos.
- **Rectificación, corrección, modificación y actualización** de lo que esté mal o haya cambiado.
- **Cancelación** cuando el fin se cumplió o el tratamiento es inadecuado.
- **Oposición** al tratamiento que te cause daño o afecte tus derechos.

**Cómo.** Por el canal de contacto del punto 16. Indica tu nombre, el derecho que ejerces y, si rectificas, el documento que lo respalda. Responderemos en **5 días hábiles** sobre si procede y lo haremos efectivo en **10 días hábiles**, prorrogables una sola vez por igual plazo. Si no somos competentes para lo que pides, te lo diremos en 5 días hábiles y te orientaremos sobre quién lo es.

Si no atendemos tu solicitud o no estás conforme, puedes interponer la acción de protección de datos personales ante la autoridad o el tribunal competente.

## 16. Cómo contactarnos

El canal de contacto para cualquier asunto de privacidad es la propia aplicación: **Perfil → Privacidad → Contactar al responsable**. Al enviar la solicitud recibes un número de seguimiento y queda registrada la fecha y la hora.

Si no puedes entrar a la aplicación, usa el mismo contacto de soporte que aparece en la ficha de instalación y en el material con que se distribuye Muévete.

En tu mensaje incluye tu nombre y apellidos, el número de teléfono con el que te registraste y el derecho que deseas ejercer. No necesitas abogado ni pagar nada.

## 17. Incidentes de seguridad

Si se produce un incidente que afecte tus datos, lo contenemos, evaluamos su alcance y lo notificamos a la autoridad competente. Si el incidente puede afectar de forma significativa tus derechos, te lo comunicamos por los canales de contacto de tu cuenta. Conservamos un registro interno de incidentes.

## 18. Cambios, versiones y re-aceptación

Cada cambio de esta Política se publica como una **versión nueva**, con su número de versión y su huella, y la anterior deja de estar vigente. La versión que está vigente y su fecha de entrada en vigor constan en el propio documento, dentro de la aplicación.

**Los cambios se avisan con al menos tres meses de antelación** por correo electrónico, mensaje de texto, notificación o aviso dentro de la aplicación. Si el cambio es urgente por motivos de seguridad, se avisa tan pronto como sea posible y se explica el motivo.

**La re-aceptación es obligatoria.** Cuando cambia la versión, la aceptación anterior deja de valer: hasta que aceptes la nueva versión **no podrás solicitar ni aceptar viajes ni usar las funciones de seguridad**. Mientras no la aceptes sí podrás consultar los textos, ver tu cuenta y pedir la baja.

**Qué se registra cuando aceptas.** Al marcar la casilla y confirmar, el servidor guarda como prueba, junto con la versión y la huella del texto que se te mostró:

- la fecha y la hora de la aceptación;
- la dirección IP de tu conexión;
- el dispositivo y la versión de la aplicación desde la que aceptaste;
- el canal por el que aceptaste (aplicación, consola de administración o migración).

Ese registro es **inmutable**: no se puede editar ni borrar desde la aplicación ni desde la consola, y se conserva según el punto 13. Si el texto cambiara sin cambiar la versión, la huella no coincidiría y la aceptación no se registraría: por eso es imposible aceptar un texto distinto del publicado.

## 19. Autoridad de control y reclamaciones

Puedes reclamar ante el **Ministerio de Comunicaciones (MINCOM)**, que controla el cumplimiento de la normativa de protección de datos personales en soporte electrónico, y ante el **Ministerio de Justicia**, a cuyo cargo está el control nacional de registros, ficheros, archivos y bases de datos personales. También puedes acudir a los tribunales.

## 20. Cierre

**Versión 1.1.0.** Esta versión sustituye por completo a la 1.0.0 y es la que se te muestra y se te registra al aceptar. Si no la aceptas, no podrás operar en Muévete, pero podrás seguir consultándola y pedir la baja de tu cuenta cuando quieras.
$md$,
  true, true, now(), NULL
WHERE NOT EXISTS (
  SELECT 1 FROM muevete.documentos_legales
   WHERE codigo = 'privacidad' AND version = '1.1.0'
);

-- ----------------------------------------------------------------------------
-- 3. Publicar la versión 1.1.0 — TÉRMINOS Y CONDICIONES DE USO
-- ----------------------------------------------------------------------------
INSERT INTO muevete.documentos_legales
  (codigo, version, titulo, resumen, contenido_md,
   es_obligatorio, publicado, vigente_desde, vigente_hasta)
SELECT
  'terminos',
  '1.1.0',
  'Términos y Condiciones de Uso',
  'Reglas de uso de Muévete: requisitos, precio, comisiones, seguridad, cancelaciones y reclamaciones.',
  '# TÉRMINOS Y CONDICIONES DE USO DE MUÉVETE' || E'\n\n' ||
  '**Versión 1.1.0 · Vigentes desde el '
    || to_char(now() AT TIME ZONE 'America/Havana', 'DD/MM/YYYY') || '**' || E'\n\n' ||
  $md$
## 1. Qué regulan estos Términos

Estos Términos regulan el uso de la aplicación y de la plataforma «Muévete» (en adelante, «Muévete» o «la Plataforma»). Al crear tu cuenta los aceptas junto con la **Política de Privacidad** y el documento **«Uso y tratamiento de datos para la verificación de identidad»**. **Sin esas tres aceptaciones no se puede crear el perfil ni operar.**

Los datos del prestador (denominación, domicilio legal, municipio y provincia, número de identificación tributaria y registro) se entregan por escrito a quien los solicite por el canal de contacto del punto 19, y se publican en la sección de información legal de la aplicación.

## 2. Qué es Muévete: somos un intermediario tecnológico

Muévete es una **plataforma tecnológica de intermediación** que conecta pasajeros con choferes independientes. **No somos una empresa de transporte, no prestamos el servicio de transporte, no somos dueños de los vehículos ni empleamos a los choferes.** El contrato de transporte se celebra entre el pasajero y el chofer; la Plataforma sólo facilita el encuentro, fija el precio, registra el viaje y cobra su comisión.

El chofer actúa como prestador independiente y es responsable de tener la **licencia operativa** y las demás autorizaciones que exija la autoridad provincial o municipal, así como del estado técnico del vehículo, del seguro y de la legalidad de su servicio.

## 3. Requisitos para usar Muévete

Para usar Muévete debes:

- ser **mayor de 18 años** y tener capacidad legal para contratar;
- registrarte con datos veraces y completos, incluido un **carnet de identidad válido** y las fotografías que se te pidan;
- superar la **verificación de identidad**;
- tener una sola cuenta y no compartirla;
- contar con un teléfono compatible y conexión a internet;
- si eres chofer, además: licencia de conducción vigente, licencia de circulación del vehículo, licencia operativa cuando corresponda y el vehículo en condiciones.

El incumplimiento de estos requisitos impide operar y puede provocar la suspensión o el bloqueo de la cuenta.

### 3.1 Cuentas de empresa (persona jurídica)

Una persona jurídica puede abrir una cuenta a través de su **representante legal**. En ese caso:

- el representante legal aporta su **carnet de identidad válido** y sus **fotografías**, y supera la verificación de identidad **a título personal**;
- aporta el **documento que acredita la empresa** y la representación que ejerce, y los **datos fiscales** de la empresa (razón social, número de identificación tributaria y domicilio);
- la empresa es la titular de la cuenta y **responde por el uso que hagan sus usuarios** y por la veracidad de los datos;
- cualquier cambio de representante legal, de razón social o de datos fiscales debe comunicarse y verificarse de nuevo; mientras no se acredite, la cuenta puede quedar suspendida.

## 4. Registro, veracidad e identidad

El registro implica la aceptación de estos Términos, de la Política de Privacidad y de los consentimientos que se te presentan. **Los datos deben ser exactos** y actualizarse cuando cambien. Podemos pedirte documentación adicional razonable para verificar tu identidad, la titularidad del vehículo o tu habilitación.

Una cuenta es **personal e intransferible**. Usar la cuenta de otra persona, suplantar una identidad o aportar documentos falsos o ajenos son incumplimientos graves y motivo de bloqueo.

## 5. Tus obligaciones como pasajero

- Dar datos veraces y mantener actualizado tu teléfono.
- Estar en el punto de recogida a la hora indicada y facilitar el contacto.
- Pagar el precio que muestra la aplicación y no pactar cobros fuera de ella.
- Tratar con respeto al chofer y al vehículo; no comer, fumar, consumir alcohol ni sustancias ilícitas dentro del vehículo.
- No transportar mercancías ilícitas, peligrosas o prohibidas.
- No usar la aplicación para acosar, amenazar, discriminar o cometer delitos.
- Dar información veraz en una reclamación o en un reporte de incidente.

## 6. Tus obligaciones como chofer

- Mantener vigentes la **licencia operativa**, la licencia de conducción y la circulación del vehículo, y acreditarlas cuando se te pidan.
- Mantener el vehículo en condiciones técnicas, de limpieza y de seguridad, con seguro vigente.
- Conducir sin haber consumido alcohol, drogas ni medicamentos que afecten la conducción, y respetar las normas de tránsito.
- Aceptar sólo los viajes que puedas cumplir; no ceder el viaje a un tercero ni usar el vehículo de otro sin autorización.
- No cobrar un precio distinto del que muestra la aplicación, no exigir pagos adicionales fuera de ella y no negarte a usar la forma de pago elegida.
- Tratar con respeto y sin discriminación a los pasajeros, y prestar ayuda razonable a personas con movilidad reducida.
- **No pedir, fotografiar ni guardar el carnet del pasajero** ni otros documentos: la verificación de identidad la hace la Plataforma.
- Mantener la confidencialidad de los datos del pasajero a los que accedas por el viaje.
- No usar la aplicación mientras conduces; el teléfono se maneja con el vehículo detenido o mediante soporte y voz.
- Reportar de inmediato accidentes, incidentes de seguridad o sospechas de fraude.

## 7. Prohibiciones generales

Se prohíbe usar la aplicación para fines ilícitos; suplantar identidades; manipular la ubicación, el precio o los registros del viaje; crear cuentas falsas o múltiples para eludir bloqueos; extraer, copiar o automatizar datos de la Plataforma; interferir en su funcionamiento; acosar, amenazar o difamar a otros usuarios; discriminar por cualquier motivo; y cualquier conducta que ponga en riesgo la seguridad de las personas.

## 8. Precio, comisión y forma de pago

El precio del viaje lo calcula **la Plataforma en el servidor** según la zona, la distancia y el tipo de vehículo, y se te muestra antes de confirmar. **El precio no se negocia** y no puede modificarlo el pasajero ni el chofer. Puede incluir recargos informados (por ejemplo, nocturno o espera) y se redondea según la configuración vigente.

La Plataforma cobra una **comisión** sobre el precio del viaje, que **actualmente es del 15 %** y se muestra en la aplicación; el resto corresponde al chofer. Si el pago es en efectivo, el chofer retiene el importe y acumula la deuda de la comisión; si es por monedero, la comisión se descuenta automáticamente. Las condiciones de la deuda, su tope y los días máximos se muestran en la aplicación y pueden cambiar según la configuración de la Plataforma.

El pago con monedero y las recargas se rigen por las condiciones que muestra la aplicación. El comprobante del viaje queda en tu historial. **No almacenamos datos de tarjetas bancarias.**

## 9. Cancelaciones y no presentación

El pasajero puede cancelar antes de que el chofer llegue; si el viaje ya está en curso o el chofer ya está en el punto, pueden aplicarse las condiciones informadas en la aplicación. El chofer puede cancelar por causas justificadas (seguridad, accidente, fuerza mayor) y debe informarlo. Las cancelaciones reiteradas o abusivas pueden afectar tu valoración y tu acceso al servicio.

## 10. Valoraciones

Pasajero y chofer pueden valorarse. Las valoraciones deben ser honestas y respetuosas; se prohíbe usarlas para amenazar, extorsionar o condicionar servicios. Podemos moderar o eliminar contenidos ilícitos y usar las valoraciones para mejorar la calidad.

## 11. Seguridad: botón de pánico, contactos y viaje compartido

La Plataforma ofrece funciones de seguridad: **botón de pánico, contactos de emergencia y enlace de viaje compartido**. **Estas funciones son una ayuda y no sustituyen a los servicios de emergencia.** En una emergencia llama de inmediato a los servicios públicos: **Policía 106, Bomberos 105, Ambulancia 104, Salvamento y rescate 107**.

El botón de pánico puede compartir tu ubicación y los datos del viaje con los contactos que elegiste, alertar al equipo de seguridad de la Plataforma y registrar el evento. **No garantiza** que una persona acuda en tu auxilio, ni que la policía o una ambulancia lleguen, ni tiempos de respuesta: depende de la cobertura, la batería, la red y de terceros. **No graba audio ni video.** El enlace de viaje compartido muestra tu ubicación a quien tenga el enlace, y eres responsable de a quién se lo envías.

## 12. Responsabilidad

La Plataforma responde por el funcionamiento del servicio tecnológico que presta y por el tratamiento de datos conforme a la ley y a la Política de Privacidad. **No responde** por el servicio de transporte en sí, por la conducta de choferes o pasajeros, por accidentes, daños o pérdidas ocurridos durante el viaje, ni por el incumplimiento de obligaciones legales propias del chofer, sin perjuicio de las responsabilidades que la ley imponga y de la colaboración que prestemos a las autoridades.

La Plataforma no garantiza disponibilidad ininterrumpida: puede haber mantenimientos, fallos de red, fuerza mayor o causas ajenas. Tampoco garantiza que siempre haya choferes disponibles.

## 13. Reclamaciones y atención

Puedes reclamar por el canal de contacto del punto 19, por el formulario de la aplicación o por el teléfono de soporte. Responderemos en un plazo razonable y, cuando la ley lo exija, en los plazos legales. Conservamos la evidencia del viaje y de la reclamación. Como consumidor puedes acudir además a las vías que establece la normativa de protección al consumidor.

## 14. Propiedad intelectual

La aplicación, su código, sus marcas, textos y diseño son de titularidad del responsable de la Plataforma o de sus licenciantes. No puedes copiar, modificar, distribuir ni explotar la Plataforma sin autorización. Los mapas y datos geográficos pertenecen a sus proveedores y se usan conforme a sus licencias.

## 15. Suspensión, bloqueo y baja

Podemos suspender o bloquear una cuenta, temporal o definitivamente, por incumplimiento de estos Términos, por fraude, por riesgo para la seguridad, por requerimiento de una autoridad o por inactividad prolongada. Se informará el motivo cuando sea posible y se permitirá la reclamación. Puedes pedir la baja en cualquier momento; la baja no elimina las obligaciones pendientes (por ejemplo, la deuda de comisión) ni la evidencia que deba conservarse por ley.

## 16. Modificaciones y re-aceptación

Podemos modificar estos Términos y la Política de Privacidad. Cada cambio se publica como una **versión nueva**, con su número de versión y su huella, y la anterior deja de estar vigente. **Los cambios se avisan con al menos tres meses de antelación** por correo electrónico, mensaje de texto, notificación o aviso en la aplicación, salvo que sean urgentes por seguridad.

**La re-aceptación es obligatoria:** hasta que aceptes la versión nueva no podrás solicitar ni aceptar viajes. Si no aceptas, puedes dejar de usar el servicio y pedir la baja.

## 17. Nulidad parcial, ley aplicable y jurisdicción

Si alguna cláusula es nula, las demás siguen vigentes. Estos Términos se rigen por la **ley cubana**. Las partes se someten a los tribunales competentes del domicilio del prestador, sin perjuicio de los derechos que como consumidor te correspondan.

## 18. Aceptación electrónica y prueba

La aceptación de estos Términos se hace electrónicamente al marcar la casilla correspondiente y confirmar. El consentimiento se manifiesta de forma **expresa**, nunca tácita ni por el simple uso.

Al aceptar, el servidor registra como prueba, junto con la versión y la huella del texto que se te mostró:

- la fecha y la hora de la aceptación;
- la dirección IP de tu conexión;
- el dispositivo y la versión de la aplicación desde la que aceptaste;
- el canal por el que aceptaste (aplicación, consola de administración o migración).

Ese registro es **inmutable** y tiene valor probatorio: no se puede editar ni borrar desde la aplicación ni desde la consola.

## 19. Contacto

El canal de contacto es la propia aplicación: **Perfil → Privacidad → Contactar al responsable**, con número de seguimiento. Si no puedes entrar a la aplicación, usa el mismo contacto de soporte que aparece en la ficha de instalación y en el material con que se distribuye Muévete.

## 20. Cierre

**Versión 1.1.0.** Esta versión sustituye por completo a la 1.0.0. Si no la aceptas, no podrás usar el servicio, pero podrás seguir consultándola y pedir la baja de tu cuenta cuando quieras.
$md$,
  true, true, now(), NULL
WHERE NOT EXISTS (
  SELECT 1 FROM muevete.documentos_legales
   WHERE codigo = 'terminos' AND version = '1.1.0'
);

-- ----------------------------------------------------------------------------
-- 4. Publicar la versión 1.1.0 — USO Y TRATAMIENTO DE DATOS PARA LA
--    VERIFICACIÓN DE IDENTIDAD (código `kyc`)
--    Documento AUTÓNOMO: la Política y los Términos lo referencian, pero aquí
--    está todo lo del carnet sin obligar a leer los otros dos.
-- ----------------------------------------------------------------------------
INSERT INTO muevete.documentos_legales
  (codigo, version, titulo, resumen, contenido_md,
   es_obligatorio, publicado, vigente_desde, vigente_hasta)
SELECT
  'kyc',
  '1.1.0',
  'Uso y tratamiento de datos para la verificación de identidad',
  'Qué hacemos con tu carnet, las fotos de tu documento y tus datos de identificación, y por cuánto tiempo.',
  '# USO Y TRATAMIENTO DE DATOS PARA LA VERIFICACIÓN DE IDENTIDAD' || E'\n\n' ||
  '**Versión 1.1.0 · Vigente desde el '
    || to_char(now() AT TIME ZONE 'America/Havana', 'DD/MM/YYYY') || '**' || E'\n\n' ||
  $md$
## 1. Para qué sirve este documento

Este documento explica, **por separado del resto**, qué hacemos con tus documentos de identidad y con los datos que nos das para comprobar quién eres. Es un consentimiento propio: se te presenta con su casilla, aparte de los Términos y Condiciones y de la Política de Privacidad, y sin él **no se puede verificar tu identidad ni habilitarte para operar**.

Complementa a la Política de Privacidad, que explica el resto de los tratamientos. Si hay contradicción entre los dos, prevalece lo que aquí se dice sobre tus documentos de identidad.

## 2. Qué datos tratamos

| Dato | ¿Obligatorio? | Para qué |
|---|---|---|
| Número de carnet de identidad (CI) | Sí | Comprobar que eres quien dices ser |
| Tipo de documento | Sí | Saber qué documento estás presentando |
| Fotografía del **frente** del carnet | Sí | Leer los datos del documento y comprobar que la foto corresponde a la persona |
| Fotografía del **dorso** del carnet | Sí | Comprobar que el documento está completo y vigente |
| Provincia, municipio y **poblado** | Sí | Verificar que los datos que declaras coinciden con tu documento y con la zona donde operas |
| Dirección | Sí | Completar tu perfil de identidad y poder localizarte para el servicio |
| Teléfono | Sí | Contactarte durante la verificación y ante cualquier problema con tu cuenta |
| En choferes: licencia de conducción y licencia de circulación del vehículo (frente y dorso) | Sí, para el chofer | Comprobar que estás habilitado para conducir y para prestar el servicio |
| En cuentas de empresa: documento que acredita la representación y datos fiscales de la empresa (razón social, número de identificación tributaria y domicilio) | Sí, si la cuenta es de empresa | Comprobar que representas válidamente a la empresa y poder facturar |

**No pedimos** datos de salud, creencias religiosas, filiación política ni orientación sexual, y no usamos tus documentos para ninguna finalidad distinta de las de la tabla.

## 3. Para qué usamos estos datos

- **Verificar tu identidad**: comprobar que el documento es tuyo, que está vigente y que la persona que opera la cuenta es la del documento.
- **Evitar suplantaciones, cuentas falsas y fraude.**
- **Habilitarte para operar**: sin identidad verificada no se puede ser chofer ni usar las funciones que exigen identidad.
- **Comprobar la representación** cuando la cuenta es de una persona jurídica.
- **Resolver disputas** de identidad y atender reclamaciones relacionadas con el uso de una cuenta.

**No usamos tus documentos para publicidad, no los vendemos y no los mostramos a otros usuarios.**

## 4. Con qué base legal

Tratamos estos datos con tu **consentimiento expreso**, que otorgas al marcar la casilla de este documento y confirmar. Es un consentimiento informado, específico y separado del de los demás documentos, y puedes retirarlo (ver el punto 8).

## 5. Quién revisa tus documentos

Únicamente **personal autorizado de Muévete**, a través de la consola de verificación, con obligación de confidencialidad y con registro del acceso.

**El pasajero no ve el carnet del chofer y el chofer no ve el carnet del pasajero.** La otra parte del viaje sólo ve tu nombre, tu foto de perfil, tu valoración y, durante el viaje, tu teléfono. La verificación se comunica con un sello de «identidad verificada», nunca mostrando el documento.

## 6. Cómo los guardamos

- Las imágenes se guardan en **almacenamiento privado**, separado del resto de los datos.
- El acceso se hace mediante **enlaces temporales firmados** y queda registrado.
- No incluimos documentos en notificaciones, mensajes de error ni registros de fallos.
- El personal accede sólo a lo que necesita para su función.

## 7. Cuánto tiempo los conservamos

| Dato | Plazo |
|---|---|
| Fotografías del carnet (frente y dorso) y de las licencias | Durante la verificación y **hasta 90 días después**; luego se eliminan |
| Resultado de la verificación (verificado o no verificado), fecha y resumen técnico | Mientras la cuenta esté activa y hasta 5 años, como evidencia |
| Número de CI, tipo de documento, provincia, municipio, poblado, dirección y teléfono | Mientras la cuenta esté activa y hasta 5 años desde la última actividad o la baja |
| Documento de la empresa y datos fiscales | Mientras la cuenta esté activa y hasta 5 años después de la baja |

Si hay una investigación de fraude en curso, las imágenes se conservan hasta que concluya, con acceso restringido. La depuración se ejecuta de forma automática conforme a la configuración vigente del servicio, por lo que varios de estos datos se suprimen antes de alcanzar el plazo máximo.

## 8. Si no lo das o si lo retiras

**Es obligatorio para operar.** Si no otorgas este consentimiento, no podemos verificar tu identidad: podrás tener cuenta, pero **no podrás solicitar ni aceptar viajes**.

**Puedes retirarlo en cualquier momento** por el canal de contacto del punto 12. La retirada **bloquea tu cuenta** hasta que se verifique de nuevo o pidas la baja; no borra la evidencia de las verificaciones ya realizadas, que se conserva según el punto 7. Si tienes un viaje en curso, el viaje se termina por seguridad y la retirada se aplica al finalizar.

## 9. Tu declaración

Al aceptar este documento **declaras que**:

- los documentos que presentas son **tuyos**, auténticos y están vigentes;
- los datos que declaras (nombre, CI, provincia, municipio, poblado, dirección y teléfono) son **ciertos** y corresponden con tu documento;
- si actúas como representante legal de una empresa, **tienes la representación vigente** y facultades para aceptar este documento en su nombre.

Aportar documentos falsos o ajenos, o suplantar a otra persona, es un incumplimiento grave: la cuenta se bloquea y podemos ponerlo en conocimiento de las autoridades.

## 10. Cuentas de empresa

Si la cuenta se abre a nombre de una persona jurídica, la verificación de identidad se hace sobre la **persona del representante legal**: su carnet y sus fotos, a título personal. Además se trata el **documento que acredita la empresa** y sus **datos fiscales**, con la finalidad de comprobar que quien contrata representa válidamente a la empresa.

La aceptación queda registrada a nombre de la cuenta, indicando la razón social y la persona que la otorgó. Cualquier cambio de representante legal debe comunicarse y verificarse de nuevo; mientras no se acredite, la cuenta puede quedar suspendida.

## 11. Tus derechos

Puedes pedir **acceso** a los datos que tenemos, **rectificarlos** si están mal, **cancelarlos** cuando el fin se cumplió y **oponerte** al tratamiento que te cause daño, sin pagar nada y por el canal del punto 12. Responderemos en **5 días hábiles** sobre si procede y lo haremos efectivo en **10 días hábiles**, prorrogables una sola vez por igual plazo.

## 12. Cómo contactarnos

El canal es la propia aplicación: **Perfil → Privacidad → Contactar al responsable**, con número de seguimiento. Si no puedes entrar a la aplicación, usa el mismo contacto de soporte que aparece en la ficha de instalación y en el material con que se distribuye Muévete.

## 13. Cambios, versiones y re-aceptación

Cada cambio de este documento se publica como una **versión nueva**, con su número de versión y su huella, y la anterior deja de estar vigente. **Los cambios se avisan con al menos tres meses de antelación** por correo electrónico, mensaje de texto, notificación o aviso en la aplicación, salvo que sean urgentes por seguridad.

**La re-aceptación es obligatoria:** cuando cambia la versión, la aceptación anterior deja de valer y no podrás operar hasta que aceptes la nueva. Mientras no la aceptes sí podrás consultar el texto y pedir la baja.

Al aceptar, el servidor registra como prueba, junto con la versión y la huella del texto mostrado: la **fecha y hora**, la **dirección IP**, el **dispositivo** y la **versión de la aplicación** desde la que aceptaste, y el canal de aceptación. Ese registro es **inmutable**.

## 14. Cierre

**Versión 1.1.0.** Esta versión sustituye por completo a la 1.0.0 de este documento. Si no la aceptas, no podremos verificar tu identidad y no podrás operar en Muévete.
$md$,
  true, true, now(), NULL
WHERE NOT EXISTS (
  SELECT 1 FROM muevete.documentos_legales
   WHERE codigo = 'kyc' AND version = '1.1.0'
);

-- ----------------------------------------------------------------------------
-- 5. Guarda de calidad: la migración no confirma si el texto no está completo
--    (esto es lo que evita que vuelva a colarse un esqueleto)
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  v_mal   text[] := ARRAY[]::text[];
  v_abiertos int;
  v_row   record;
BEGIN
  FOR v_row IN
    SELECT codigo, length(contenido_md) AS largo, hash_contenido, contenido_md
      FROM muevete.documentos_legales
     WHERE version = '1.1.0'
  LOOP
    IF v_row.contenido_md ILIKE '%PLACEHOLDER%'
       OR v_row.contenido_md ILIKE '%lorem ipsum%'
       OR v_row.contenido_md ~ '\[(VALIDAR|HUECO|FECHA|HASH|RAZÓN SOCIAL|RAZON SOCIAL|DOMICILIO|CORREO|TELÉFONO|NIT/RUC|MUNICIPIO|PROVINCIA)[^\]]*\]'
    THEN
      v_mal := array_append(v_mal, v_row.codigo || ':marcas_de_borrador');
    END IF;
    IF v_row.largo < 3000 THEN
      v_mal := array_append(v_mal, v_row.codigo || ':demasiado_corto(' || v_row.largo || ')');
    END IF;
    IF v_row.hash_contenido IS NULL OR length(v_row.hash_contenido) <> 64 THEN
      v_mal := array_append(v_mal, v_row.codigo || ':sin_hash');
    END IF;
  END LOOP;

  -- Debe haber exactamente 3 documentos 1.1.0 publicados, obligatorios y vigentes.
  SELECT count(*) INTO v_abiertos
    FROM muevete.documentos_legales
   WHERE version = '1.1.0' AND publicado AND es_obligatorio
     AND vigente_desde <= now() AND vigente_hasta IS NULL;
  IF v_abiertos <> 3 THEN
    v_mal := array_append(v_mal, 'vigentes_1_1_0=' || v_abiertos || ' (esperado 3)');
  END IF;

  -- Y ninguna versión anterior puede seguir abierta.
  SELECT count(*) INTO v_abiertos
    FROM muevete.documentos_legales
   WHERE codigo IN ('privacidad', 'terminos', 'kyc')
     AND version <> '1.1.0' AND vigente_hasta IS NULL;
  IF v_abiertos > 0 THEN
    v_mal := array_append(v_mal, 'versiones_anteriores_abiertas=' || v_abiertos);
  END IF;

  IF cardinality(v_mal) > 0 THEN
    RAISE EXCEPTION 'texto_legal_1_1_0_invalido: %', v_mal USING ERRCODE = 'P0001';
  END IF;

  RAISE NOTICE '042 OK: 3 documentos legales 1.1.0 publicados, vigentes y con hash.';
END $$;

COMMIT;

-- ============================================================================
-- VERIFICACIÓN (ejecutar a mano; NO forma parte de la migración)
-- ============================================================================
-- 1) Estado de las 6 filas (esperado: 1.0.0 cerrada + 1.1.0 vigente por código):
--
--   SELECT codigo, version, publicado, es_obligatorio,
--          vigente_hasta IS NULL AS vigente,
--          length(contenido_md) AS largo,
--          left(contenido_md, 80) AS inicio,
--          hash_contenido IS NOT NULL AS tiene_hash
--     FROM muevete.documentos_legales
--    ORDER BY codigo, version;
--   -- Esperado: largo ~8 000-12 000 en la 1.1.0 y NINGUNA fila con
--   --           'PLACEHOLDER' en `inicio`.
--
-- 2) Que no queda ni un esqueleto ni una marca de borrador:
--
--   SELECT codigo, version,
--          contenido_md ILIKE '%PLACEHOLDER%'      AS tiene_placeholder,
--          contenido_md ILIKE '%[VALIDAR]%'        AS tiene_validar,
--          contenido_md ~ '\[[A-ZÁÉÍÓÚÑ /]+\]'     AS tiene_corchetes
--     FROM muevete.documentos_legales
--    ORDER BY codigo, version;
--
-- 3) Coherencia del trigger de hash (la huella guardada debe ser la del texto):
--
--   SELECT codigo, version,
--          hash_contenido = encode(digest(contenido_md, 'sha256'), 'hex') AS hash_ok
--     FROM muevete.documentos_legales
--    WHERE version = '1.1.0';
--   -- Esperado: hash_ok = true en las tres.
--
-- 4) El gate exige re-aceptar (usuario que sólo aceptó la 1.0.0):
--
--   SELECT jsonb_pretty(
--     muevete.fn_usuario_habilitado('148c8191-2797-44e2-b3c2-9eabd657735c'::uuid, 'cliente'));
--   -- Esperado: habilitado = false, motivos = ["consentimiento_pendiente"],
--   --           consentimiento.faltantes = ["kyc@1.1.0","privacidad@1.1.0",
--   --                                       "terminos@1.1.0"]
--
-- 5) Re-aceptar como ese usuario y confirmar que vuelve a operar
--    (sustituir los claims por los del usuario de prueba):
--
--   SELECT set_config('request.jwt.claims',
--          '{"sub":"148c8191-2797-44e2-b3c2-9eabd657735c","role":"authenticated"}', true);
--   SELECT muevete.fn_aceptar_consentimiento('privacidad','1.1.0','app','verificacion-042',NULL);
--   SELECT muevete.fn_aceptar_consentimiento('terminos', '1.1.0','app','verificacion-042',NULL);
--   SELECT muevete.fn_aceptar_consentimiento('kyc',      '1.1.0','app','verificacion-042',NULL);
--   SELECT jsonb_pretty(
--     muevete.fn_usuario_habilitado('148c8191-2797-44e2-b3c2-9eabd657735c'::uuid, 'cliente'));
--   -- Esperado: habilitado = true, faltantes = []
--
-- 6) `fn_doc_legal_hash` y `fn_token_hash` siguen sanas:
--
--   SELECT count(*) FROM muevete.documentos_legales WHERE version = '1.1.0'
--     AND hash_contenido IS NOT NULL;                     -- 3
--   SELECT muevete.fn_token_hash('prueba-042');           -- 64 hex, sin error
--
-- 7) Idempotencia: re-ejecutar 042 completo no cambia nada (mismo `id`, mismo
--    `hash_contenido`, misma `vigente_desde`).
-- ============================================================================

-- ============================================================================
-- ROLLBACK (documentado; NO ejecutar en despliegue normal)
-- ----------------------------------------------------------------------------
-- Criterio: 042 es ADITIVA. Revierte volviendo a dejar vigente la 1.0.0 y
-- cerrando la 1.1.0. NO se borra la 1.0.0 en ningún caso, y la 1.1.0 sólo se
-- borra si NADIE la aceptó (el FK de `consentimientos` lo impide si hay
-- evidencia, y la evidencia no se destruye).
--
-- BEGIN;
--   -- 1. Cerrar la 1.1.0 (deja de estar vigente y deja de ser obligatoria).
--   UPDATE muevete.documentos_legales
--      SET vigente_hasta = now(), publicado = false
--    WHERE version = '1.1.0'
--      AND codigo IN ('privacidad','terminos','kyc');
--
--   -- 2. Reabrir la 1.0.0 (vuelve a estar vigente).
--   UPDATE muevete.documentos_legales
--      SET vigente_hasta = NULL, publicado = true
--    WHERE version = '1.0.0'
--      AND codigo IN ('privacidad','terminos','kyc');
-- COMMIT;
--
--   -- 3. (Opcional, sólo si de verdad hay que eliminar el texto del todo y
--   --     nadie aceptó la 1.1.0.) El NOT EXISTS respeta el FK:
--   DELETE FROM muevete.documentos_legales dl
--    WHERE dl.version = '1.1.0'
--      AND dl.codigo IN ('privacidad','terminos','kyc')
--      AND NOT EXISTS (SELECT 1 FROM muevete.consentimientos c
--                       WHERE c.documento_id = dl.id);
--
-- Nota: volver a la 1.0.0 devuelve los PLACEHOLDER a la app. Sólo tiene
-- sentido como paso previo a publicar una 1.2.0 corregida, nunca como estado
-- final de un cutover.
-- ============================================================================