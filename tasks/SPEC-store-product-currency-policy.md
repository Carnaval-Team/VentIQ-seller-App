# Spec: Política de moneda por producto por tienda

- Module id: `store-product-currency-policy`.
- Estado: BORRADOR PARA REVISIÓN; no aprobado para implementar.
- Mapa de capacidades aprobado por el usuario: `plan_admin_multimoneda.md`, sección «Mapa revisado de capacidades».
- Intención funcional: mismo documento, sección «Intención confirmada».
- Consumidor posterior: `product-currency-sale`.
- Esta spec no modifica ni sustituye los documentos de Fondo de Caja.

## 1. Objetivo

Permitir que un administrador autorizado habilite por tienda una modalidad de moneda por detalle de producto, conservando el comportamiento actual cuando está apagada y entregando al vendedor una política consistente tanto online como offline.

El flag controla moneda, no medios de pago. La selección existente de medio en el producto permanece. Este módulo no implementa el selector del producto ni cambia el checkout: publica la política que consumirá el módulo de venta.

### Requisitos confirmados por el usuario

- Flag apagado por defecto.
- Apagado conserva exactamente el flujo legacy, incluido «Distribuir pagos».
- Encendido añade moneda al detalle junto al medio existente.
- Una moneda forzada por tienda prevalece sobre la elección del vendedor.
- Sin moneda forzada, el vendedor podrá elegir entre monedas habilitadas con precio propio disponible.
- Alcance inmediato CUP/USD; otras monedas requieren reglas aprobadas antes de habilitarlas en esta modalidad.
- Los nuevos detalles conservarán tasa y equivalente CUP separados del importe nativo.

### Propuestas técnicas que aún requieren revisión

- Nombre de columna: `permitir_moneda_por_producto`.
- Política de configuración ligada a `id_tienda`, nunca únicamente a estado global del teléfono.
- Ausencia de flag en configuración válida legacy equivale a false. Error al cargar la configuración no equivale a una política nueva conocida.
- Política fijada para órdenes activas/pendientes y transición de configuración: contrato del módulo de venta, pendiente de especificación; no migrar automáticamente órdenes existentes.
- Solución de seguridad para la configuración: bloqueada por los hallazgos de main; requiere aprobación específica antes de DDL.

## 2. Alcance y exclusiones

### Incluye

1. Contrato persistente del flag y valor por defecto.
2. Lectura/escritura autorizada desde admin, con feedback y manejo de fallo.
3. Transporte por `store_config` y `SyncModule.storeConfig` existentes.
4. Resolución de política por tienda para sus consumidores.
5. Inicialización, invalidación y protección ante cargas concurrentes/cambio de tienda.
6. Pruebas de regresión legacy, acceso y caché.

### Excluye

- Modelo monetario final de `OrderItem` y DDL de `app_dat_extraccion_productos`.
- Checkout, unión de líneas, precios/promociones y registro de venta/pago.
- Nuevas monedas, tasas globales o edición de precios.
- Nuevas vistas de reportes y reconstrucción histórica.
- Activación de tiendas antes de completar y verificar el módulo de venta.

## 3. Evidencia existente y riesgos

### Admin

- `ventiq_admin_app/lib/widgets/monedas_tienda_card.dart`: integra monedas aceptadas y moneda forzada. El guardado actual primero guarda monedas y después configuración; puede fallar parcialmente y recarga el estado persistido.
- `ventiq_admin_app/lib/widgets/global_config_tab_view.dart`: incorpora esa tarjeta.
- `ventiq_admin_app/lib/services/store_config_service.dart`: `updateStoreConfig` admite parámetros opcionales y solo añade al mapa las opciones suministradas.
- `ventiq_admin_app/lib/screens/settings_screen.dart`: resuelve permisos de edición. La tarjeta no recibe actualmente un `canEdit`; no asumir que ocultar un botón externo protege sus escrituras.

### Vendedor y offline

- `ventiq_app/lib/services/store_config_service.dart`: lectura remota `select('*')`; en modo offline/full-offline usa caché sin ping; online intenta remoto y luego caché.
- `saveStoreConfigToCache` y `syncStoreConfig` transportan el mapa; existen flags sincrónicos para decisiones de UI.
- `ventiq_app/lib/services/user_preferences_service.dart`: almacena `store_config` como JSON en SharedPreferences; logout limpia la caché. Debe verificarse pertenencia a tienda antes de consumirla, no asumir aislamiento por el nombre de la clave.
- `ventiq_app/lib/services/auto_sync_service.dart`: sincroniza configuración mediante `StoreConfigService.syncStoreConfig`.
- `ventiq_app/lib/services/device_offline_prep_service.dart`: `prepModules` ya incluye `SyncModule.storeConfig`. No se necesita un catálogo ni módulo de sync paralelo para un booleano.
- `ventiq_app/lib/services/moneda_venta_service.dart`: mantiene comportamiento de moneda general y forzada; no reutilizar su fallback para descartar una restricción forzada en modo nuevo.

### Main, comprobación MCP de solo lectura

`public.app_dat_configuracion_tienda` contiene:

| Columna | Tipo | Estado |
|---|---|---|
| `id_tienda` | bigint, no nulo | Identificador de tienda. |
| `mostrar_selector_moneda` | boolean, no nulo, default false | Flag legacy; no reutilizar para esta modalidad. |
| `forzar_moneda_venta` | boolean, no nulo, default false | Restricción existente. |
| `moneda_venta_forzada` | character, nullable | Código de moneda forzada. |

La columna propuesta nueva no figura en la inspección de columnas monetarias.

**Bloqueo S01:** RLS está desactivado y no hay policies en esta tabla. Se comprobó con `has_table_privilege` que `anon` y `authenticated` tienen permisos efectivos SELECT, INSERT y UPDATE. Una consulta inicial a `information_schema.role_table_grants` no mostró filas para esos roles: ese resultado no prueba ausencia de privilegios efectivos y no debe utilizarse como garantía.

No se ejecutaron escrituras ni una explotación de estos permisos. No extrapolar este resultado a una auditoría de todo el proyecto.

### Decisión de alcance para S01

El usuario autorizó incluir el endurecimiento de la tabla existente. No autorizó aplicar una migración concreta a main. No basta proteger el switch ni una RPC si quedan escrituras directas o lecturas SECURITY DEFINER sin validación.

Artefactos preparados para revisión:

- `docs/plan-multimoneda/configuracion_tienda_rls_propuesta.sql`: migración propuesta, transaccional y de una sola aplicación. No añade el flag todavía.
- `docs/plan-multimoneda/verificar_configuracion_tienda_rls.sql`: consultas de catálogo de solo lectura para antes/después. No sustituyen pruebas de comportamiento con roles.

La propuesta usa la tabla existente, sin crear una tabla satélite. No modifica datos ni cambia globalmente los helpers compartidos.

### Análisis de impacto de acceso

| Ruta | Comportamiento actual localizado | Efecto propuesto |
|---|---|---|
| Admin StoreConfigService | SELECT de configuración, INSERT por defecto si no hay fila y UPDATE parcial con retorno. | Lectura de tienda autorizada; INSERT/UPDATE solo dueño, gerente o superadmin activo de acceso completo. |
| Admin CocinaService | SELECT restaurante/cocina y UPDATE de flags. | Mismas restricciones por tienda; jefe de cocina conserva lectura pero no permiso global para modificar configuración de tienda. |
| Vendedor StoreConfigService | SELECT para sync/caché. Escritura conectada a UI confirmada: modo_restaurante desde settings_screen, sección Modo de Operación. Setters de guardar impresora por defecto, tickets a imprimir, copias y autocompletar conteo existen, pero no se encontraron llamadores en el código Dart actual fuera de sus declaraciones. | Lectura para trabajador con acceso. El switch de restaurante deja de poder escribir bajo rol vendedor; ocultarlo/deshabilitarlo o mostrar autorización requerida en la entrega cliente. No afirmar que los otros setters están expuestos en UI ni ampliar permisos para conservar una ruta insegura. Las preferencias locales de impresión/SKU/datos/offline no escriben esta tabla. |
| fn_user_can_access_tienda | Incluye dueño/gerente/supervisor/auditor, no vendedor ni almacenero. | No utilizarlo como única policy de lectura. |
| check_user_has_access_to_tienda | Incluye vendedor, almacenero, supervisor, auditor, gerente, dueño y jefe de cocina; no es SECURITY DEFINER. | Referencia semántica para lectores; no alterar su contrato ni depender de sus consultas bajo RLS en esta propuesta. |
| fn_require_gerente_tienda | Admite gerente y cualquier superadmin considerado activo; no distingue nivel completo. | No reutilizarlo para ampliar escritura; helpers nuevos acotados a esta tabla incluyen dueño y exigen superadmin activo nivel 1. |
| sync_bundle(bigint,bigint) | SECURITY DEFINER; serializa la configuración. El filtro de vendedor del turno no autoriza por sí solo la lectura del resto del bundle. | Guardar acceso a tienda antes de consultar datos y comprobar que un TPV no nulo pertenece a esa tienda. Revocar EXECUTE a PUBLIC/anon. |
| fn_obtener_licencia_firmada(bigint) | SECURITY DEFINER; lee parámetros offline de configuración, sin guarda de tienda observada en el cuerpo. | Exigir acceso a tienda antes de ejecutar lógica. Mantener firma/payload y lógica de licencia; verificar descarga con usuario real autenticado. |
| fn_moneda_consolidacion(bigint) | SECURITY DEFINER SQL; lee moneda forzada sin validación de tienda en su cuerpo. | Exigir acceso antes de resolver; conservar firma, query original y retorno. |

En main se localizaron 12 funciones públicas cuyo cuerpo referencia textualmente la tabla; no se detectaron escrituras directas mediante el patrón SQL inspeccionado. Esto no prueba ausencia de SQL dinámico, llamadas indirectas ni problemas de autorización en otras funciones. Las otras funciones corresponden a ventas, inventario, recepción, reportes y triggers; esta propuesta no declara una auditoría completa ni cambia sus permisos en bloque.

No se encontraron vistas de `public` con referencia textual a la tabla. Los roles anon/authenticated no tienen CREATE en public. La tabla pertenece a postgres y no tiene FORCE RLS; service_role tiene BYPASSRLS. No se alteran esas características globales.

### Diseño RLS propuesto

- SELECT para usuarios autenticados con acceso por dueño, gerente, supervisor, auditor, vendedor vía TPV, almacenero vía almacén no eliminado y jefe de cocina vía cocina no eliminada. Superadmin activo nivel 1 puede leer.
- INSERT/UPDATE solo dueño o gerente de la tienda, o superadmin activo nivel 1. UPDATE comprueba tanto fila previa como nueva para evitar reasignaciones a una tienda no autorizada.
- DELETE sin policy permisiva ni grant para authenticated; no existe flujo local identificado que lo necesite. Policy explícita de denegación.
- Revocar todos los permisos de tabla a PUBLIC/anon y los excesivos de authenticated; conceder a authenticated SELECT/INSERT/UPDATE sujetos a RLS. No cambiar grants de otras tablas ni de service_role.
- Helpers nuevos SECURITY DEFINER con tablas calificadas, search_path fijo y sin acceso anónimo. No modificar los helpers compartidos existentes.
- Las tres RPC indicadas validan tienda antes de leer; service_role de un backend confiable conserva su ruta. El cliente nunca debe usar una credencial service_role para demostrar aislamiento.
- Se conserva SELECT de la fila para los lectores actuales. La configuración incluye campos sensibles como master_password: no se consultaron sus valores. RLS por fila no es separación por columna ni sustituye una futura revisión de esa exposición y de los clientes que usan select('*').

### Salvaguardas de la propuesta SQL

- Transacción única, límites de espera de locks y ejecución esperada como postgres.
- Requiere opt-in de sesión `app.config_tienda_rls_approved=yes`; no basta ejecutar accidentalmente el archivo. Este marcador no sustituye aprobación humana ni es una frontera de seguridad contra administradores.
- Aborta si el estado de tabla/policies/helpers difiere del inspeccionado. No es un script idempotente: no reejecutar después de aplicado.
- Comprueba huellas MD5 de las definiciones actuales inspeccionadas en newa antes de insertar guardas en sus propios cuerpos. Newa es la referencia de desarrollo; no se sustituyen funciones por versiones de main. Son controles contra divergencia accidental, no firmas criptográficas de seguridad.
- Conserva los cuerpos y comentarios existentes; para la función SQL de consolidación, cambia a PL/pgSQL con guarda previa y RETURN QUERY, conservando el query original y declarando resolución de columnas para evitar ambigüedad con parámetros de salida.
- No renombra funciones a implementaciones públicamente invocables y no crea wrappers que dejen una entrada alternativa sin guarda.
- Revoca EXECUTE de PUBLIC/anon en las RPC modificadas y comprueba privilegios efectivos residuales al terminar.
- Si algo falla antes del COMMIT, la transacción debe abortar completa. No corregir divergencias quitando controles para forzar el despliegue.

### Verificación requerida antes de main

| Caso en entorno de prueba | Resultado requerido |
|---|---|
| anon | Sin lectura/escritura directa ni EXECUTE de las tres RPC guardadas. |
| Usuario autenticado sin roles | Ninguna fila visible de configuración; INSERT/UPDATE rechazados o cero filas según ruta. Ninguna RPC revela configuración. |
| Vendedor tienda A | Lee A por SELECT, sync y RPC de licencia; no lee B ni puede insertar/actualizar A/B. |
| Dueño/gerente A | Lee y actualiza A; upsert legítimo funciona; no lee/escribe B si no tiene rol allí. |
| Supervisor, auditor, almacenero, jefe de cocina | Lectura limitada al alcance de tienda definido; ninguna escritura de configuración. |
| Superadmin inactivo o limitado sin otro rol | No obtiene privilegios de superadmin completo. |
| Superadmin activo nivel 1 | Lectura y escritura autorizadas; sin DELETE desde authenticated. |
| Mezcla tienda A y TPV B en sync_bundle | Rechazo antes de leer el bundle. |
| service_role backend confiable | Acceso previsto conservado; no usar esta prueba como validación de RLS de usuarios. |
| Restaurante/cocina, impresión, apertura/cierre, licencia offline | Flujos autorizados siguen operando; setters no autorizados no muestran éxito falso. |
| Búsqueda por tienda B o cambio de id_tienda | Sin fuga ni escalada por UPDATE de la clave de tienda. |

Las pruebas deben utilizar JWT/roles reales o una simulación controlada en una base de prueba, verificando resultados por tienda. Ejecutar SELECT como postgres no demuestra estas propiedades. Las descargas antes de autenticación, si existen en otro cliente no inventariado, requieren análisis y no deben resolverse reabriendo anon.

Estado de verificación: huellas y transformación textual de las tres RPC contrastadas en main y newa mediante SELECT, sin ejecutar DDL. No equivale a compilar PL/pgSQL ni probar RLS. El usuario confirmó que newa es su entorno de pruebas y que ejecuta SQL manualmente en Supabase SQL Editor. No se requiere psql para ese flujo; el agente no ejecuta migraciones remotas.

### Compatibilidad de newa e instrucciones de SQL Editor

- newa tiene la tabla con owner postgres, RLS off, sin policies y grants efectivos equivalentes a main.
- Las tablas/columnas de membresía utilizadas por los helpers existen. Los nombres nuevos de helpers están libres; anon/authenticated no pueden crear objetos en public.
- sync_bundle y licencia firmada tienen las mismas huellas que main.
- Consolidación difiere en formato/comentarios del cuerpo revisado, conservando la lógica. La propuesta toma exclusivamente su versión actual de newa, huella `132b5269a00df2573d632fe81bad29f2`. No acepta la versión de main como alternativa.
- Flujo confirmado por el usuario: desarrollar y probar en newa; promover después a main. Diferencias de firma/cuerpo son esperables y no justifican alinear newa hacia atrás. Antes de promover, comparar main con la versión final validada y preparar una migración específica, preservando los avances de desarrollo.
- Resultado: viable para primera ejecución controlada de pruebas en newa. Todavía no ejecutado ni certificado por pruebas de comportamiento.

El usuario ejecuta lo siguiente en el proyecto newa, con rol postgres, en una sola ejecución de SQL Editor:

1. Pegar `SET app.config_tienda_rls_approved = 'yes';` y debajo el contenido completo de `docs/plan-multimoneda/configuracion_tienda_rls_propuesta.sql`, incluido su BEGIN/COMMIT. La línea de aprobación y el script deben ejecutarse juntos: no depender de que distintas ejecuciones del editor compartan sesión.
2. Ejecutar después `docs/plan-multimoneda/verificar_configuracion_tienda_rls.sql`. Su última consulta devuelve un resumen; las seis columnas deben ser true. Esto verifica estructura/ACL/guardas presentes, no demuestra aislamiento funcional por sí solo.
3. Probar lectura/sync/licencia con vendedor y configuración con gerente; verificar denegación para tienda ajena y escrituras de vendedor. No usar el rol postgres del editor como evidencia de RLS de usuarios.
4. Si aparece error, conservarlo completo y no quitar preflight ni reabrir permisos. El script es de una sola aplicación: no reejecutarlo si ya terminó correctamente.

No ejecutarlo en main hasta completar esas pruebas y obtener autorización específica. La propuesta no añade el flag ni cambia el código Dart.

### Despliegue y reversión

1. Aprobar spec y propuesta; obtener snapshot de definiciones/ACL/policies e identificar clientes afectados sin registrar credenciales ni valores sensibles.
2. Ejecutar y probar en clon/staging con estado equivalente; si las huellas no coinciden, revisar diferencias y actualizar un artefacto específico revisado para ese entorno, no eliminar el control.
3. Corregir controles y manejo de errores en clientes donde los setters estén expuestos a roles de solo lectura. Comprobar que los clientes usan sesión autenticada y no service_role.
4. Solicitar autorización específica para aplicar el archivo revisado a main, con ventana de despliegue y pruebas de humo por rol.
5. Validar catálogos, lecturas y escrituras autorizadas; mantener el flag nuevo apagado y no habilitarlo hasta completar venta/sync.
6. Si una operación legítima falla, preferir una corrección mínima de policy/cliente. No desactivar RLS ni reabrir anon como fallback automático; cualquier reversión de controles requiere aprobación explícita y evaluación de exposición.

## 4. Contrato de política propuesto

### Persistencia preferida, sujeta a S01

Añadir un booleano `permitir_moneda_por_producto` con default false y no nulo en configuración por tienda, mediante migración aditiva. No aplicar migración como parte de esta spec.

El campo no altera `mostrar_selector_moneda`, `forzar_moneda_venta` ni `moneda_venta_forzada`. Guardarlo no cambia otras opciones de tienda ni resetea monedas aceptadas.

### Lectura normalizada

El proveedor devuelve un resultado asociado a tienda con al menos:

- `idTienda`.
- `estado`: disponible o no disponible; puede incluir un motivo de fallo.
- `origen`: remoto o caché, si está disponible.
- `monedaPorProducto`: true solo cuando el valor configurado es booleano true.
- `forzarMonedaVenta` y `monedaVentaForzada` normalizada cuando corresponda.
- Monedas habilitadas obtenidas del pipeline existente; distinguir lista vacía confirmada de catálogo no disponible.

Nombres y representación Dart definitivos se fijarán en el plan técnico. No persistir campos derivados como si fueran una segunda configuración independiente.

Ampliación técnica aprobada por el usuario con el contrato consolidado de SPEC-product-currency-sale.md, sección 0.2 (todavía sin implementación ni DDL): el proveedor entrega una revisión inmutable de política y una constancia de emisión al usuario/dispositivo, además del snapshot consistente de flag/forzado/monedas. Integrarlas al módulo storeConfig y su caché por tienda, no a otro catálogo ni pipeline de precios. El servidor valida procedencia y alcance; un JSON local no autoriza seleccionar cualquier política histórica.

El almacenamiento protegido de revisiones/constancias, si se aprueba, es una migración posterior con RLS/policies explícitas desde su creación. No forma parte del SQL S01 ya ejecutado y no reemplaza app_dat_configuracion_tienda. Propuesta operativa: reutilizar la ventana offline/licencia existente para iniciar órdenes con la última política entregada; retener para revisión envíos iniciales fuera de autorización, sin perder ni convertir la venta. Ese comportamiento, no una revocación instantánea imposible sin red, quedó aprobado junto con el contrato consolidado de la spec de venta; siguen pendientes plan/tareas y ejecución.

Si modo nuevo está activo pero faltan revisión/constancia requeridas para operar offline, devolver política incompleta/no utilizable para iniciar órdenes nuevas, no degradarla silenciosamente a legacy. Las órdenes legacy y los reintentos de ventas ya aceptadas conservan su contrato.

**Separación de responsabilidades:** la política define restricciones de tienda; el consumidor verifica precio disponible por producto, tasa contable y otras condiciones de venta. Una moneda habilitada no garantiza que un producto tenga precio propio.

### Resolución

| Situación | Resultado |
|---|---|
| Configuración válida con flag false | Modo legacy, sin cambios. |
| Configuración válida antigua sin nuevo campo | Modo legacy. |
| Flag true, sin forzado | Modalidad por producto; candidatos habilitados dentro de CUP/USD. |
| Flag true, forzado CUP/USD válido | Solo la moneda forzada, si el producto tiene precio válido. |
| Flag true, forzado inconsistente/inactivo/no habilitado | Política no utilizable para iniciar una venta nueva en ese modo; no sustituir por CUP en silencio. |
| Flag true, forzado fuera de CUP/USD | No vender en modalidad nueva con reglas no especificadas; informar incompatibilidad y solicitar configuración compatible. |
| Caché pertenece a otra tienda | Descartarla para esta resolución; no usar su flag ni su forzado. |
| No hay remoto ni caché válida | Estado no disponible; no inventar política conocida ni activar la modalidad nueva. |
| Falla remoto con caché válida de la misma tienda | Usar la política cacheada, declarando su origen. |

La ausencia de configuración utilizable debe impedir decisiones nuevas que dependan de este contrato; esta spec no redefine cómo el flujo legacy maneja sus propios errores ni autoriza eliminar órdenes pendientes.

## 5. Admin y permisos

- Ubicación propuesta: tarjeta de monedas de la tienda dentro de Configuración.
- Etiqueta: «Permitir moneda por producto».
- Ayuda: «El vendedor elige la moneda de cada producto. El cobro respeta la moneda y el medio seleccionados en el detalle».
- Solo dueño/gerente y superadmin con autorización aplicable pueden escribir, acotados a la tienda. Confirmar mapeo con helpers/roles reales antes del SQL.
- Vendedor puede leer para operar; no modificar el flag.
- `anon` no puede leer ni escribir esta configuración sensible por la nueva ruta; no cambiar privilegios globales sin aprobación específica.
- En lectura fallida no mostrar false como valor confirmado editable; mostrar error y permitir reintentar.
- Deshabilitar edición mientras se carga/guarda y para roles sin permiso.
- Guardar false debe funcionar igual que true; omitir el parámetro no modifica el valor.
- Un error de guardado no muestra éxito ni deja el UI afirmando un estado persistido falso.
- Si el guardado comparte flujo con monedas/forzado, recargar tras fallo parcial y mostrar lo realmente confirmado.
- Un flag encendido no habilita la funcionalidad hasta que el cliente y backend soporten el recorrido completo. La UI de activación se libera al final, no al añadir la columna.

## 6. Caché y ciclo de vida

- Guardar el flag en el mapa `store_config`, sin otra fuente de verdad ni otro catálogo.
- Si hace falta un getter síncrono, inicializarlo al cargar caché y al guardar/sincronizar configuración; asociarlo a tienda y estado disponible, no solo a un booleano global.
- Antes del primer detalle, completar la hidratación de política o representar carga/no disponible; no renderizar provisionalmente otra modalidad y luego cambiar una orden ya iniciada.
- Cambio de tienda/logout invalida memoria. Una respuesta tardía de la tienda anterior no puede sobrescribir la política actual.
- Cachear la configuración original, no solo el resultado de su resolución, para conservar procedencia y detectar pertenencia a tienda.
- No extender silenciosamente la política con TTL nuevo ni elegir un plazo arbitrario. Frescura, revocación y órdenes iniciadas bajo política anterior se resolverán con el módulo de venta y, si afectan negocio, con el usuario.
- Offline con caché fresca de la tienda: misma política que al descargarla.
- Offline con caché vacía/corrupta/de otra tienda: no activar el modo nuevo ni afirmar un forzado válido.
- Offline con caché stale: mantener estado/procedencia disponibles; no reinterpretar ni convertir órdenes ya guardadas. La regla final para iniciar nuevas órdenes requiere resolver O02 antes del plan de venta.

## 7. Criterios de aceptación

| ID | Condición verificable |
|---|---|
| SPC-AC-01 | Configuración nueva y payload legacy sin campo resuelven modo por producto apagado. |
| SPC-AC-02 | Guardar true/false persiste solo la opción solicitada, sin alterar selector legacy, forzado o monedas habilitadas. |
| SPC-AC-03 | Una lectura/guardado fallida muestra estado de error; no simula confirmación de false ni éxito. |
| SPC-AC-04 | Autorizado de tienda A puede configurar A; vendedor, anon y usuario sin acceso a A no pueden escribir por ninguna ruta relevante. |
| SPC-AC-05 | El vendedor autorizado puede obtener la política de su tienda, no la de otra. |
| SPC-AC-06 | Sync y preparación offline descargan el flag con store_config existente, sin un segundo pipeline. |
| SPC-AC-07 | Reiniciar offline conserva política y forzado con caché válida; caché ausente/corrupta/ajena no activa modo nuevo. |
| SPC-AC-08 | Cambio de tienda, logout y respuestas concurrentes no contaminan política ni getters síncronos. |
| SPC-AC-09 | Con modo activo y moneda forzada no se ofrecen alternativas; forzado inválido no se convierte en elección libre. |
| SPC-AC-10 | Con modo inactivo no se modifica la moneda general, los precios, el editor de pagos ni los payloads legacy. |
| SPC-AC-11 | La opción no puede activarse operativamente en tiendas antes de completar backend y cliente compatibles. |
| SPC-AC-12 | No hay cambios históricos ni migración de órdenes pendientes en este módulo. |

SPC-AC-04/SPC-AC-05 no pueden considerarse cumplidos con la tabla main tal como está; S01 debe resolverse antes.

## 8. Stack, estructura y convenciones

- Flutter/Dart. Restricción SDK en pubspec: vendedor `^3.7.0`, admin `^3.10.0`; no afirmar que son versiones instaladas verificadas.
- Supabase Flutter declarado `^2.5.6` en ambas apps; SharedPreferences ya disponible. No añadir dependencias para este módulo.
- Código de configuración en los servicios/widget existentes; tests de cada app en su carpeta `test/`.
- Migración SQL versionada en `docs/plan-multimoneda/` si se aprueba esa ruta; no es SQL de inventtia_flow.
- Seguir snake_case en campos SQL, camelCase en Dart y configuración opcional en actualizaciones parciales.
- No añadir ni quitar comentarios del código existente salvo solicitud explícita.

Patrón real de lectura de flags en el vendedor, a adaptar sin ocultar estado/tienda:

```dart
final config = await getStoreConfig(storeId);
final value = config?['modo_restaurante'] ?? false;
```

Para la normalización del flag nuevo, true debe ser booleano true; no activar por cadenas como `'true'` o valores numéricos. Ese caso inválido se documenta como contrato inválido y no como activación.

## 9. Estrategia de pruebas y comandos

Pruebas propuestas, todavía no creadas:

- Vendedor `test/store_product_currency_policy_test.dart`: tabla de resolución, forzado, listas vacías/ausentes y formato legacy.
- Vendedor `test/store_product_currency_policy_cache_test.dart`: mock de preferencias/servicios, hidratación, tienda y concurrencia; no exigir red real a unit tests.
- Admin `test/store_product_currency_policy_test.dart`: actualización parcial y errores.
- Admin `test/store_product_currency_policy_widget_test.dart`: permisos visuales, carga, guardado y rollback/recarga.
- Pruebas SQL de permisos y aislamiento en entorno de prueba, con roles reales; no usar service_role para demostrar RLS.

Comandos desde `ventiq_app`, PowerShell, después de crear los tests:

```powershell
flutter.bat test --no-pub test/store_product_currency_policy_test.dart test/store_product_currency_policy_cache_test.dart
flutter.bat test --no-pub test/checkout_payment_lines_test.dart test/moneda_venta_test.dart test/multimoneda_core_test.dart test/home/app_compile_test.dart
flutter.bat analyze
```

Desde `ventiq_admin_app`, después de crear los tests nuevos:

```powershell
flutter.bat test --no-pub test/store_product_currency_policy_test.dart test/store_product_currency_policy_widget_test.dart
flutter.bat test --no-pub test/app_compile_test.dart test/sales_totals_summary_test.dart
flutter.bat analyze
```

Build de comprobación propuesto, tras las pruebas y en cada app si corresponde a sus plataformas habilitadas:

```powershell
flutter.bat build apk --debug --no-pub
```

No iniciar APIs, `flutter run` ni despliegues como seguimiento automático. No se ejecutaron estos comandos al redactar esta spec; la lista de pruebas existentes debe confirmarse nuevamente al implementar.

Matriz manual requerida: online con flag on/off y forzado on/off; reinicio offline con caché fresca, vacía y stale; dos tiendas en la misma sesión; error de lectura/guardado; rol vendedor y rol administrador autorizado.

## 10. Límites de ejecución

### Siempre

- Cambios aditivos y default false; mantener flag legacy independiente.
- Verificar permisos backend y todas las vías de escritura, no solo navegación.
- Reutilizar sync y caché existentes; registrar evidencia por entorno.
- Probar fallos además de casos felices.

### Preguntar/aprobar primero

- Solución concreta de S01 y cualquier modificación de RLS/grants sobre la tabla compartida.
- Aplicación remota de migraciones, nuevas tablas, dependencias o cambio de reglas de frescura.
- Tratamiento de órdenes en curso si una nueva configuración entra en conflicto con lo ya seleccionado.

### Nunca

- Activar la modalidad por error de red o ausencia de campo.
- Reducir permisos por tienda a una comprobación del cliente.
- Aplicar DDL remoto durante la fase de especificación.
- Modificar históricos, eliminar pendientes o sustituir precio propio USD por conversión CUP.
- Habilitar el flag de producción antes de soporte completo de venta y sync.

## 11. Preguntas y bloqueos

| ID | Estado | Tema |
|---|---|---|
| S01 | Aplicado por el usuario en newa desde SQL Editor; estructura verificada por MCP | Las seis comprobaciones de catálogo dieron true; policies y helpers coinciden con la propuesta. Pendientes pruebas funcionales con vendedor/gerente y aislamiento entre tiendas. No aplicado a main por esta iniciativa. |
| O01 | Regla de negocio confirmada por el usuario; contrato técnico pendiente en spec de venta | Órdenes iniciadas/pendientes conservan modalidad y condiciones monetarias ya seleccionadas; cambios de flag/forzado aplican a órdenes nuevas. Sin conversión, redistribución ni reinterpretación de snapshots al sincronizar. |
| O02 | Ausencia de tasa resuelta por el usuario; criterios técnicos de frescura pendientes de spec | Sin tasa USD→CUP válida online ni en caché, bloquear nuevas líneas USD aun con precio propio; no inventar tasa ni sustituir precio. CUP puede continuar solo si la política lo permite; forzado USD no admite fallback CUP. Pendientes con tasa histórica válida conservan snapshot. No se ha aprobado un TTL nuevo para caché. |
| O03 | Pendiente de revisión de spec | Aprobar nombre técnico `permitir_moneda_por_producto` y ubicación en tarjeta de monedas. |

## 12. Estado y siguiente puerta

- Mapa de capacidades: aprobado por el usuario.
- Intención: confirmada.
- Spec: redactada y ampliada con endurecimiento autorizado en alcance; pendiente de revisión final.
- Plan de implementación/tareas del flag: no aprobado ni ejecutado.
- SQL de seguridad: ejecutado por el usuario en newa desde SQL Editor. El agente verificó mediante SELECT: seis comprobaciones true, cuatro policies correctas y tres helpers SECURITY DEFINER propiedad de postgres con search_path=pg_catalog, sin EXECUTE anon.
- Flag nuevo: se confirmó que permitir_moneda_por_producto todavía no existe en newa.
- Main y código Dart: no modificados por esta entrega.
- Verificación funcional reportada por el usuario: «no hubo problemas» después de solicitar pruebas desde las apps en newa. Resultado manual favorable, no ejecución automatizada del agente. No se detallaron identidades/casos ni evidencia específica de denegación entre tiendas; no dar por demostrada toda la matriz de aislamiento solo con este reporte.

Siguiente paso: probar sync/licencia con vendedor, lectura/escritura con gerente y denegación entre tiendas en newa; revisar la spec antes de preparar tareas pequeñas del flag con trazabilidad SPC-AC-xx. No reejecutar la migración de una sola aplicación en newa. La promoción a main requiere comparación y autorización específicas. El contrato consolidado de `product-currency-sale` ya fue aprobado y fija la política de órdenes/offline; el paso actual es revisar el plan técnico, no volver a entrevistar sobre esas reglas.
