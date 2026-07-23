# Mapa de pruebas funcionales — Inventtia Muévete

## Objetivo

Validar de punta a punta los flujos de pasajeros y carga, usando cuentas separadas para cada rol. Cada caso indica quién ejecuta la acción, qué debe ocurrir y qué evidencia guardar.

## Preparación

- **[Dispositivos]** Usa al menos dos dispositivos físicos con GPS, datos móviles y notificaciones activas: uno para cliente/remitente y otro para conductor/transportista. Para el dispatcher puede usarse un tercer dispositivo o una sesión web.
- **[Cuentas]** Registra cuentas nuevas y distintas para los cinco roles:
  - `cliente_pasajero`: Cliente Pasajero
  - `conductor_pasajeros`: Conductor Pasajeros
  - `shipper`: Remitente de carga
  - `carrier_carga`: Transportista de carga
  - `dispatcher`: Despachador
- **[Datos de prueba]** Define dos puntos distintos y seguros para cada prueba: origen y destino. Para carga, prepara datos de mercancía, peso, fecha y vehículo.
- **[Saldo]** Para que un conductor pueda enviar una oferta, su billetera debe cubrir la comisión mostrada por la app. Para pagos por billetera, el cliente debe tener saldo suficiente.
- **[Evidencia]** Captura pantalla del resultado de cada caso y registra el ID de la solicitud o carga.

## Matriz rápida de roles

| Rol | Acciones principales a probar |
|---|---|
| Cliente Pasajero | Registro, perfil, direcciones, solicitud de viaje, ofertas, aceptación, seguimiento, pago, cancelación, historial y calificación. |
| Conductor Pasajeros | Registro y vehículo, conexión, ubicación, solicitudes, oferta, navegación, inicio, espera, QR, finalización, billetera e historial. |
| Remitente de carga | Registro, perfil, publicación de carga, edición/cancelación, ofertas, selección de transportista, seguimiento e historial. |
| Transportista de carga | Registro y documentación, cargas disponibles, oferta, cargas asignadas, estados y perfil. |
| Despachador | Registro, flota, asignación/consulta de conductores, cargas disponibles y gestión operativa. |

---

# Flujo A — Viaje de pasajeros completo

## A1. Registro y configuración inicial

| Paso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| A1.1 | Cliente Pasajero | Abrir la app, elegir **Crear cuenta**, seleccionar el tipo Cliente Pasajero y completar el registro. | La cuenta se crea y se abre el mapa de cliente. |
| A1.2 | Cliente Pasajero | Aceptar permisos de ubicación y notificaciones. | Se muestra la posición actual y el dispositivo puede recibir alertas. |
| A1.3 | Cliente Pasajero | Abrir Perfil y actualizar nombre, teléfono, foto o los campos disponibles. | Los cambios persisten al cerrar y volver a abrir el perfil. |
| A1.4 | Cliente Pasajero | Crear una dirección guardada desde Perfil/Direcciones guardadas. | La dirección aparece en la lista y puede reutilizarse al pedir un viaje. |
| A1.5 | Conductor Pasajeros | Crear una segunda cuenta, seleccionar Conductor Pasajeros y completar los datos solicitados de conductor y vehículo. | La cuenta abre el inicio de conductor. |
| A1.6 | Conductor Pasajeros | Aceptar ubicación y notificaciones; abrir Perfil y comprobar datos y vehículo. | El perfil se carga y la ubicación queda disponible. |

## A2. Solicitud y oferta

| Paso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| A2.1 | Conductor Pasajeros | Entrar a Inicio y activar el estado **En línea**. | La app confirma el estado y empieza a actualizar la ubicación del conductor. |
| A2.2 | Cliente Pasajero | En el mapa, seleccionar origen y destino mediante búsqueda o mapa. | Se muestran las direcciones, ruta, distancia y tipo de vehículo. |
| A2.3 | Cliente Pasajero | Elegir tipo de vehículo, método de pago y precio ofertado; revisar la vista previa de ruta. | El resumen refleja origen, destino, distancia, precio y pago elegidos. |
| A2.4 | Cliente Pasajero | Confirmar **Solicitar viaje**. | Se crea una solicitud pendiente, aparece la espera de ofertas y no permite crear un segundo viaje activo. |
| A2.5 | Conductor Pasajeros | Abrir la solicitud entrante o Solicitudes; revisar origen, destino y precio sugerido. | La solicitud recién creada aparece para el conductor cercano. |
| A2.6 | Conductor Pasajeros | Enviar una oferta con precio, tiempo estimado y mensaje. | La app confirma el envío y la solicitud deja de mostrarse como disponible para ese conductor. |
| A2.7 | Cliente Pasajero | Verificar la notificación y abrir la pantalla de ofertas. Probar filtros **Mejor**, **Menor precio** y **Más rápido** si hay más de una oferta. | La oferta aparece sin tener que recrear la solicitud; los filtros ordenan las ofertas. |

## A3. Aceptación, seguimiento y viaje

| Paso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| A3.1 | Cliente Pasajero | Aceptar la oferta del conductor. Si usa billetera, seleccionar una oferta con saldo suficiente. | La oferta queda aceptada, se bloquean las demás y se abre el viaje confirmado. Con billetera se reserva el importe correspondiente. |
| A3.2 | Cliente Pasajero | Verificar nombre/teléfono del conductor, posición en mapa, ruta hacia recogida y opción de contacto. | Los datos del conductor y el seguimiento se actualizan. |
| A3.3 | Conductor Pasajeros | Confirmar que recibe la aceptación y abre el viaje activo. | Se muestran los datos del cliente, origen, destino y navegación hacia recogida. |
| A3.4 | Conductor Pasajeros | Desplazarse físicamente o simular ubicación hacia el punto de recogida. | El cliente observa el avance del conductor y el conductor ve la navegación actualizada. |
| A3.5 | Conductor Pasajeros | Al llegar, iniciar el viaje desde el control disponible. | Ambos roles reciben el cambio de estado a viaje iniciado. |
| A3.6 | Conductor Pasajeros | Probar iniciar una parada/espera y finalizarla. | Se muestra el tiempo de espera y, si aplica, el importe adicional calculado. |
| A3.7 | Conductor Pasajeros y Cliente Pasajero | Si el flujo está habilitado, probar el QR de inicio o finalización: un rol muestra el QR y el otro lo escanea. | El escaneo valida la acción y no permite confirmar con un código inválido. |
| A3.8 | Conductor Pasajeros | Llegar al destino y seleccionar **Completar viaje**. | La solicitud cambia a completada y el conductor vuelve a tener disponibilidad para nuevas solicitudes. |
| A3.9 | Cliente Pasajero | Verificar la finalización, importe final y diálogo de calificación. Enviar una calificación/comentario. | La calificación se guarda y el viaje desaparece de los activos. |
| A3.10 | Cliente Pasajero y Conductor Pasajeros | Revisar historial y billetera. | El viaje aparece con estado completado; los movimientos de billetera, si se usó ese pago, son coherentes. |

## A4. Variantes y errores de pasajeros

| Caso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| Cancelar antes de aceptar | Cliente Pasajero | Crear solicitud y cancelarla mientras espera ofertas. | Estado cancelada, se cierran las ofertas y el cliente puede crear otra solicitud. |
| Rechazar una oferta | Cliente Pasajero | Quitar/rechazar una oferta y conservar otra. | La oferta se oculta localmente y la solicitud continúa esperando opciones. |
| Saldo insuficiente | Cliente Pasajero | Elegir pago por billetera sin saldo suficiente y aceptar una oferta. | La aceptación se bloquea con mensaje claro; no se acepta la oferta. |
| Saldo de comisión insuficiente | Conductor Pasajeros | Intentar ofertar sin saldo para comisión. | La oferta no se envía y se informa el monto necesario. |
| Recuperar viaje activo | Cliente Pasajero | Cerrar y volver a abrir la app durante espera de ofertas o viaje confirmado. | La app recupera la solicitud, ofertas o viaje activo. |
| Sin conexión temporal | Ambos | Desactivar datos brevemente y reactivarlos durante seguimiento. | La interfaz informa o reintenta; al reconectar se recupera el estado sin duplicar el viaje. |
| Modo oscuro | Ambos | Cambiar tema y recorrer los flujos principales. | Texto, controles y mapa permanecen legibles. |

---

# Flujo B — Carga completo

## B1. Registro y publicación de carga

| Paso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| B1.1 | Remitente de carga | Crear cuenta seleccionando **Remitente de carga**. | Se abre el panel de cargas del remitente. |
| B1.2 | Remitente de carga | Actualizar el perfil y comprobar el cierre/inicio de sesión. | Los datos permanecen guardados. |
| B1.3 | Remitente de carga | Crear una carga: origen, destino, mercancía, peso/unidad, equipo requerido, fechas y precio o condiciones disponibles. | La carga se guarda en **Mis cargas** con estado inicial correcto. |
| B1.4 | Remitente de carga | Revisar el mapa de ruta y editar los datos antes de recibir ofertas. | La ruta y los campos modificados se actualizan. |
| B1.5 | Transportista de carga | Crear otra cuenta seleccionando **Transportista de carga** y completar documentos/vehículo requeridos. | Se abre el listado de cargas disponibles. |

## B2. Oferta, selección y seguimiento de carga

| Paso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| B2.1 | Transportista de carga | Refrescar cargas disponibles y abrir la creada por el remitente. | La carga aparece con origen, destino, mercancía, peso y fechas correctas. |
| B2.2 | Transportista de carga | Enviar una oferta de transporte con precio, disponibilidad y mensaje si la interfaz lo permite. | El sistema confirma la oferta y la asocia a esa carga. |
| B2.3 | Remitente de carga | Abrir la carga en Mis cargas y revisar ofertas recibidas. | La oferta muestra transportista, importe y condiciones. |
| B2.4 | Remitente de carga | Aceptar una oferta o seleccionar un transportista desde el directorio, si está habilitado. | La carga queda asignada y el transportista puede verla entre sus cargas. |
| B2.5 | Transportista de carga | Abrir la carga asignada y actualizar sus estados operativos disponibles. | El remitente observa los cambios de estado en su carga. |
| B2.6 | Remitente de carga | Verificar historial, información del transportista y estado final. | La carga conserva trazabilidad y no aparece como disponible después de asignada/completada. |

## B3. Variantes de carga

| Caso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| Cancelar publicación | Remitente de carga | Cancelar una carga sin asignar. | Deja de aparecer entre cargas disponibles. |
| Datos obligatorios | Remitente de carga | Intentar publicar sin origen, destino, mercancía, peso o fecha requeridos. | La app marca los campos obligatorios y no publica. |
| Perfil/documentos | Transportista de carga | Guardar un documento o dato de vehículo incompleto/no válido. | La app valida el error o impide finalizar si el campo es requerido. |
| Carga asignada | Transportista de carga | Intentar tomar u ofertar una carga ya asignada. | La app no permite una asignación duplicada. |

---

# Flujo C — Despachador y flota

| Paso | Rol | Acción | Resultado esperado |
|---|---|---|---|
| C1 | Despachador | Crear cuenta como **Despachador** e iniciar sesión. | Se abre el panel con las pestañas de flota y cargas. |
| C2 | Despachador | Abrir Flota y verificar conductores, teléfonos, estado, vehículos, carrocerías y documentos. | La información asignada al dispatcher se muestra sin campos cruzados. |
| C3 | Despachador | Abrir el detalle de un conductor y revisar imágenes/documentos disponibles. | Los documentos se visualizan o muestran un estado claro cuando faltan. |
| C4 | Despachador | Actualizar la lista y revisar cargas disponibles. | La carga publicada en B1 aparece con los datos correctos. |
| C5 | Despachador | Ejecutar las acciones de asignación o gestión disponibles en la interfaz. | La modificación se refleja en la carga, la flota y el rol involucrado. |
| C6 | Despachador | Abrir Perfil, actualizar los datos permitidos y cerrar sesión. | Los cambios persisten y el cierre devuelve a la pantalla inicial. |

---

# Pruebas transversales

| Área | Prueba | Resultado esperado |
|---|---|---|
| Inicio de sesión | Iniciar con cada una de las cinco cuentas y salir. | Cada rol abre solo su pantalla principal: cliente, conductor, remitente, transportista o despachador. |
| Recuperación de sesión | Cerrar completamente la app y abrirla con sesión iniciada. | Restaura la sesión y navega al inicio correcto según el rol. |
| Notificaciones | Generar oferta, aceptación, inicio y finalización de viaje con la app del otro rol en segundo plano. | Llegan notificaciones y al tocarlas llevan al contexto correspondiente. |
| Permisos | Negar ubicación/notificaciones, luego concederlas desde Ajustes. | La app muestra un estado entendible y retoma la función al otorgar permiso. |
| Validación | En formularios de registro, solicitud, oferta y carga, usar campos vacíos, números inválidos y textos largos. | No se generan registros incompletos ni fallos visuales. |
| Duplicados | Tocar dos veces botones críticos: solicitar, ofertar, aceptar, iniciar o completar. | Solo se crea o actualiza una operación. |
| Web y móvil | Repetir registro, perfil y los flujos esenciales en web y móvil si ambas plataformas están habilitadas. | Los controles son utilizables y los estados quedan sincronizados. |

# Criterio de aprobación

La prueba se considera aprobada cuando cada flujo alcanza su estado final sin intervención manual en la base de datos, los dos roles ven el mismo estado y no quedan solicitudes, ofertas, viajes o cargas duplicados. Cualquier discrepancia debe reportarse con: rol, paso, ID del registro, hora, dispositivo/plataforma, captura y mensaje de error.
