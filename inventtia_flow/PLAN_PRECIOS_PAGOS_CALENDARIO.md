# Plan y ejecución — cancelación con motivo, calendario, precios automáticos y pago por adelantado

**Ámbito:** app Flutter `inventtia_flow` (GoReserva) + esquema `flow` de Supabase
(**debug** `qhprswhhfasrikhawjoz` y **release** `vsieeihstajlrdvpuooh`).
**Creado:** 27-10-2026. **Estado:** en ejecución (ver §9 para el avance real).

> Este documento es a la vez el **plan** y la **especificación de implementación**:
> cada punto fija contratos (RPC, JSON, ids de ancla, ficheros) para que el trabajo
> del admin, del cliente y del servidor no se desincronice.

---

## 0. Resumen

| # | Cambio | Tamaño | BD | Cliente | Admin | Tutorial |
|---|---|---|:--:|:--:|:--:|:--:|
| 1 | Botón «Admin» a la **izquierda** de la campana | menor | — | ✅ | — | — |
| 2 | **Motivo obligatorio** al cancelar + notificación al cliente + motivo en el detalle + **cancelaciones en rojo** | menor | 61, 63 | ✅ | ✅ | — |
| 3 | **Resumen calendario** de reservas (modo calendario + modo lista), botón en el AppBar de Reservas | mediano | 63 | — | ✅ | admin |
| 4 | **Precios automáticos** por tasa de cambio («el toque») | grande | 60, 64(+EF) | — | ✅ | admin |
| 5 | **Pago por adelantado** del servicio (pago en línea con Transfermóvil del admin) | grande | 62, 63 | ✅ | ✅ | cliente |

**Orden de ejecución:** la BD primero (hecho, §1), luego en paralelo los cuatro
frentes de app (§2-§5), y al final tutoriales (§6) y verificación (§7).

---

## 1. Base de datos — HECHO

Migraciones nuevas en `docs/flow_schema/migraciones/`:

| Fichero | Qué crea |
|---|---|
| `60_tasa_cambio_y_precio_config.sql` | `flow.tasa_cambio` (caché diaria), `flow.precio_config` (por entidad), `tasas_actuales()`, `tasa_factor()`, `admin_precio_config_get/set()`, `_puede_ver_entidad()` |
| `61_cancelacion_motivo_y_notificacion.sql` | 4 columnas de cancelación en `flow.agenda`; `staff_marcar_estado_agenda`, `staff_cancelar_reserva`, `admin_cancelar_agenda` y `cliente_cancelar_reserva` con `p_motivo`; `_mensaje_cancelacion()`; notificación `tipo='cancelacion'` |
| `62_pago_adelantado_servicio.sql` | `flow.cobro_config` (por entidad), `flow.reserva_pago`, 4 columnas de pago en `flow.agenda`, 8 RPC (cliente y admin) + `reserva_pago_expirar()` |
| `63_listados_motivo_pago_y_calendario.sql` | los 4 listados devuelven motivo + pago; nueva `admin_calendario_reservas()` |
| `64_tasas_refresco_pg_net.sql` | refresco de la tasa **sin** Edge Function: `tasas_refrescar()`, `tasas_ingest()`, `_tasas_conversiones()`, `flow.tasa_cambio_sondeo` |
| `65_grants_service_role_schema_flow.sql` | **[FIX]** `grant usage on schema flow to service_role` (+ privilegios de tabla). Sin esto la Edge Function fallaba con «permission denied for schema flow» en release |
| `66_bot_al_cancelar_reserva.sql` | **[NUEVO]** trigger diferido en `flow.agenda`: al pasar de Reservado a Cancelado, al hacer COMMIT corre el bot de la cola para el turno/día liberado |
| `67_cobro_por_servicio.sql` | **[NUEVO]** `app_dat_servicios.cobro_adelantado` (interruptor **por servicio**): `cliente_cobro_info` exige servicio + entidad, y un trigger impide crear un intento de pago en un servicio que no lo acepta |

Edge Function (código listo, **pendiente de desplegar**, ver §8):
`docs/flow_schema/edge_functions/flow-tasas/index.ts`.

### 1.1 Contratos que la app consume

**Tasas** — `flow.tasas_actuales()` → `{ok, fecha, hora, fuente, actualizado, vigente, tasas, conversiones}`;
`flow.tasas_refrescar(p_forzar)` → `{estado:'vigente'|'solicitado', request_id?}`;
`flow.tasas_ingest(request_id)` → `{estado:'pendiente'|'ingerido'|'error', conversiones?}`;
`flow.tasa_factor(origen, destino)` → `numeric`.
`conversiones` es una matriz `{"USD":{"CUP":840,"EUR":0.908108,"MLC":1.2},"EUR":{...},"MLC":{...},"CUP":{...}}`
y **ya trae el cruce por CUP** (MLC→EUR = 697.62/925 = 0.754184).

**Cancelación** — los 4 RPC aceptan `p_motivo text`. `staff_*` y `admin_cancelar_agenda`
**fallan** sin motivo (`Debes indicar el motivo de la cancelacion`); el cliente no lo
necesita. Los 4 listados devuelven además:
`motivo_cancelacion, cancelado_por, cancelado_por_rol ('cliente'|'admin'|'staff'|'sistema'), cancelado_at`.

**Pago por adelantado**
- **Dos niveles**: la entidad aporta la cuenta que cobra (`flow.cobro_config`: proveedor,
  WhatsApp, moneda, plazo) y **cada servicio** decide si la usa
  (`app_dat_servicios.cobro_adelantado`, migración 67). Hacen falta las dos cosas.
- `flow.cliente_cobro_info(p_id_local_servicio)` → `{ok, data:{disponible, moneda, horas_vigencia, whatsapp_verificacion, instrucciones, numero_proveedor, titulo}}`
- `flow.cliente_crear_pago_reserva(p_id_agenda)` → `{ok, data:{id, monto, moneda, importe, url_intent, url_http, expira_at, numero_proveedor, whatsapp_verificacion, instrucciones}}`
- `flow.cliente_reportar_pago_reserva(p_id_pago, p_codigo_confirmacion, p_comprobante_url)` → `{ok}`
- `flow.cliente_pago_reserva(p_id_agenda)` → `{ok, data: null | {id, monto, moneda, estado, url_intent, url_http, motivo_rechazo, expira_at, vencido, ...}}`
- `flow.admin_cobro_config_get/set(p_id_entidad, ...)`; `flow.admin_listar_pagos_reserva(p_id_entidad, p_estado)`;
  `flow.admin_verificar_pago_reserva(p_id_pago, p_observaciones)`; `flow.admin_rechazar_pago_reserva(p_id_pago, p_motivo)`
- `agenda.pago_estado ∈ {null, 'pendiente','reportado','verificado','rechazado','expirado'}`;
  `agenda.pago_monto`, `agenda.pago_moneda`, `agenda.pago_id`.
- Notificaciones del circuito: `tipo='pago'` (avisar al admin de un pago reportado y al
  cliente de verificado/rechazado).

**Calendario** — `flow.admin_calendario_reservas(p_uuid_usuario, p_id_entidad, p_desde, p_hasta, p_incluir_items)` →
```json
{ "ok": true,
  "rango": { "hoy":"2026-10-27", "desde":"2026-10-27", "hasta":"2027-03-31",
             "ultimo_dia_con_reserva":"2027-03-14", "truncado":false },
  "resumen": { "total":12, "reservadas":6, "canceladas":2, "completadas":4,
               "por_servicio":[{"servicio":"Corte","total":7}] },
  "dias": [ { "fecha":"2026-10-27", "total":2, "reservadas":1, "canceladas":1,
              "completadas":0, "personas":3, "pagos_pendientes":0,
              "items":[ { "id":41,"fecha_hora_reserva":"...","cantidad":1,"estado":"Reservado",
                          "id_estado":1,"servicio":"Corte","local":"Salon 1","cliente":"Ana",
                          "cliente_telefono":"...","turno":"10:00","motivo_cancelacion":null,
                          "pago_estado":null,"precio_total":18,"moneda":"USD",
                          "id_local_servicio":7 } ] } ] }
```
`p_incluir_items=false` devuelve solo contadores (marcadores del calendario, payload mínimo).

### 1.2 Migración del esquema en **release**: pendiente

El MCP de release está configurado **read-only** y ningún token del perfil tiene
`edge_functions_write`. Por eso, en release hay que pegar `60`→`64` en el SQL Editor
y desplegar la función (§8). En debug ya está todo aplicado y verificado.

---

## 2. Punto 1 — botón «Admin» en la cabecera del cliente (menor)

`lib/screens/home_client_screen.dart`, en `_buildTopBar`. **Estado final** (tras la
segunda vuelta): el selector de provincia («Todas las provincias») se **ocultó** de la
cabecera y en su fila va el botón de vuelta al panel.

- Fila de iconos: `[ 🔔 ] [ avatar ]`.
- Debajo: si el usuario es admin, la píldora de ancho completo
  «Volver al panel de administración ›» (`_BotonVolverAAdmin(expandido: true)`); si es
  cliente puro no ocupa nada (no queda hueco ni espacio extra).
- El **filtro por provincia sigue existiendo** en la hoja de filtros del Home
  (`FiltrosServicios`), que se aplica en memoria: no se perdió la capacidad.
- Sin cambios de BD. Sin tests nuevos (ningún test dependía del orden ni del selector).

Criterio: con un admin, la cabecera se lee `Hola, … / [ 🔔 ] [avatar] / [ Volver al panel… ]`;
con un cliente puro no aparece la píldora y nada se desplaza. Sin overflow a 320 pt.

---

## 3. Punto 2 — motivo de cancelación y notificaciones en rojo (menor)

### 3.1 Modelo y utilidades
- `lib/models/agenda.dart`: +`motivoCancelacion`, +`canceladoPorRol` (**nullable**, para no
  romper los 3 tests que construyen `Agenda` con argumentos nombrados). `fromJson` los lee.
- `lib/utils/reserva_listado.dart`: getter `String? get motivoCancelacion` en
  `ReservaListItem` (fuente única para las 3 tarjetas).
- `lib/utils/motivo_cancelacion.dart` (nuevo, puro y testeable):
  `String? validarMotivo(String?)` (obligatorio: mínimo 3 caracteres tras `trim()`, máximo 500),
  `String? mensajeErrorCancelacion(Object e)` (traduce `Debes indicar el motivo...`,
  `Solo se pueden cancelar reservas activas`, `No tiene permisos...`),
  `String textoMotivo(String? motivo)` (lo que se pinta en la tarjeta).
- `lib/widgets/dialogo_motivo_cancelacion.dart` (nuevo): `Future<String?> dialogoMotivoCancelacion(BuildContext, {required String titulo, required String detalle, String? motivoInicial})`.
  `AlertDialog` con `TextField(maxLength: 500, maxLines: 3)` + validación en línea + botones
  «No» / «Sí, cancelar» (este último deshabilitado hasta que el motivo sea válido).
  **El diálogo se abre SIEMPRE antes de `setState(_loading = true)`.**

### 3.2 Captura en los 4 caminos
| Camino | Fichero | RPC | Motivo |
|---|---|---|---|
| Admin, listado de reservas | `screens/admin/reservas_screen.dart` `_cancelarReserva` | `staff_cancelar_reserva` | **obligatorio** |
| Vendedor, listado | `screens/vendedor/vendedor_screen.dart` `_cancelarReserva` | `staff_cancelar_reserva` | **obligatorio** |
| Staff, Mis tickets | `screens/mis_tickets_screen.dart` `_cancelarStaff`/`_cambiarEstadoStaff` | `staff_marcar_estado_agenda(id,2,motivo)` | **obligatorio** |
| Cliente, Mis tickets | `screens/mis_tickets_screen.dart` `_cancelar` | `cliente_cancelar_reserva(...,motivo)` | opcional (campo vacío = sin motivo) |

Servicios: `AgendaAdminService.cancelarReserva({idAgenda, motivo})`,
`marcarEstadoAgenda({idAgenda, idEstado, motivo})`,
`AgendaService.cancelarTicketCliente({uuidUsuario, idAgenda, motivo})`.

### 3.3 Pintado del motivo (3 tarjetas)
- `reservas_screen.dart` (~`:1648-1651`, tras las columnas dinámicas) `if (esCancelada)`:
  bloque destacado en `AppTheme.error` con «Motivo de cancelación: …» y, si existe,
  «Cancelada por: administración|cliente|sistema».
- `vendedor_screen.dart` (~`:1681-1685`): idéntico.
- `mis_tickets_screen.dart` `_TicketCard` (~`:1168-1172`): idéntico, con el chip de estado.
- Si el motivo es nulo (reservas canceladas antes de esta migración) el bloque **no** se pinta.

### 3.4 Notificaciones en rojo
- `lib/models/notificacion.dart`: `tipo='cancelacion'` → `color = AppTheme.error`,
  `icono = Icons.event_busy`; `tipo='pago'` → `color = AppTheme.warning`,
  `icono = Icons.payments_outlined`. **Completar el switch de `color` también para
  `suscripcion`** (hoy tiene icono y no color: es un fallo preexistente).
- `lib/screens/notificaciones_screen.dart` `_etiquetaTipo`: «Cancelación» y «Pago».
- **Compatibilidad hacia atrás**: las cancelaciones ya guardadas tienen `tipo='reserva'`.
  El color se decide con: `tipo == 'cancelacion'` **o** (`tipo == 'reserva'` y el título
  empieza por «Reserva cancelada»). Se resuelve en el getter, no en la pantalla.

---

## 4. Punto 3 — resumen calendario de reservas (mediano)

Pantalla nueva para el admin: **de hoy al último mes que tenga reservas**, con dos modos.

### 4.1 Ficheros nuevos
| Fichero | Contenido |
|---|---|
| `lib/utils/vista_reservas.dart` | `enum VistaReservas { calendario, lista }`, `VistaReservas vistaReservasPorDefecto()`, `({DateTime firstDay, DateTime lastDay}) rangoReservas({required DateTime? ultimoDiaConReserva, required DateTime hoy, DateTime? hasta})` (sin horizonte artificial; `lastDay` = último día del mes del último dato) y `String claveDia(DateTime)` / `Map<DateTime,List<T>> agruparPorDia(...)`. **Puro y testeable.** |
| `lib/models/resumen_reservas.dart` | `RangoReservas`, `ResumenReservas`, `DiaResumen`, `ReservaResumen` (parseo del JSON de §1.1; tolerante a `num`/`String`/faltantes). |
| `lib/services/calendario_service.dart` | `CalendarioService.calcular({int idEntidad, DateTime? desde, DateTime? hasta, bool incluirItems})` → `ResumenReservas` vía RPC `admin_calendario_reservas` con el `uuid` de `AuthService.getCurrentUserId()`. |
| `lib/screens/admin/resumen_reservas_screen.dart` | `ResumenReservasScreen({required Entidad entidad})`. |

### 4.2 Comportamiento
- **Carga en dos tiempos**: primero `incluirItems:false` para el rango completo (marcadores,
  barato); los items del día se piden al tocar un día (`incluirItems:true`, `desde=hasta=día`).
- **Modo calendario**: `TableCalendar<DiaResumen>` (`table_calendar` **ya está** en
  `pubspec.yaml`), `locale:'es_ES'`, `firstDay/lastDay` **calculados** (nunca 2024..2027),
  marcadores por color: verde = todas reservadas, ámbar = hay pagos pendientes,
  rojo = solo canceladas, azul = completadas. Leyenda + resumen del rango arriba.
  Swipe horizontal de mes (`AvailableGestures.horizontalSwipe`) — **no** añadir el
  `GestureDetector` de swipe del listado de reservas (pelea con el del calendario).
- **Modo lista (to-do)**: `ListView.builder` agrupado por día con cabecera pegajosa
  («Hoy», «Mañana», «vie 30 oct»), y por reserva: hora, servicio, local, cliente, estado,
  chip de pago y puntos de color. Sin reservas ⇒ estado vacío explicado.
- **Toggle** calendario/lista en el AppBar (`SegmentedButton` o `IconButton` con
  `Icons.view_list_outlined` / `Icons.calendar_month_outlined`); el modo vive en el `State`.
- Tocar un día en modo calendario baja/navega a la lista de ese día.
- `TutorialAnchor(id: 'admin_calendario')` envolviendo el botón que abre la pantalla
  (vive en `reservas_screen.dart`, lo añade el frente de cancelación).

### 4.3 Acceso
- `lib/screens/admin/reservas_screen.dart:1126-1141`, en `actions:` **antes** del PDF:
  `IconButton(icon: Icon(Icons.calendar_month_outlined), tooltip: 'Resumen por calendario', onPressed: _loading ? null : _abrirResumenCalendario)`
  → `Navigator.push(MaterialPageRoute(builder: (_) => ResumenReservasScreen(entidad: widget.entidad)))`.
  La AppBar pasa de 3 a 4 acciones: usar `visualDensity: VisualDensity.compact` para no
  recortar el título a 320 pt.

---

## 5. Punto 4 — precios automáticos por tasa de cambio (grande)

### 5.1 Ficheros nuevos
| Fichero | Contenido |
|---|---|
| `lib/models/tasa_cambio.dart` | `TasasDia { fecha, hora, actualizado, vigente, tasas, conversiones }` con `double? factor(String origen, String destino)` y `fromJson` tolerante. |
| `lib/services/tasa_cambio_service.dart` | `Future<TasasDia?> obtener({bool forzar = false})` con caché en memoria (por sesión + `vigente`): **1)** Edge Function `flow-tasas` (`functions.invoke`), **2)** si falla, `tasas_refrescar()` + bucle de `tasas_ingest()` (~250 ms, 6 intentos) + `tasas_actuales()`, **3)** si no hay nada, devuelve `null`. `Future<void> limpiarCache()`. |
| `lib/utils/conversion_precio.dart` | Puro: `double? factorDesde(TasasDia, origen, destino)`, `double redondearPrecio(double, int decimales)`, `double? convertirPrecio({double valor, String origen, String destino, TasasDia? tasas, int decimales})`, `Map<String,double?> preciosConvertidos({required Map<String,double> precios, required String origen, required List<String> monedas, TasasDia? tasas, required int Function(String) decimalesDe})`. **Nunca inventa un factor**: sin tasa, devuelve `null` para esa moneda. |
| `lib/models/precio_config.dart` | `PrecioConfig { autoActivo, monedaOrigen, redondeoCup, redondeoDivisa }` + `decimalesDe(moneda)`. |
| `lib/services/precio_config_service.dart` | `get(idEntidad)` / `set(...)` → RPC `admin_precio_config_get/set`. |
| `lib/screens/admin/precio_config_screen.dart` | Ajustes: switch de cálculo automático, moneda de origen, redondeo CUP (0-2) y divisas (0-2), y **estado de la tasa** (fecha, si es de hoy, botón «Actualizar tasa»). |

### 5.2 Comportamiento en el formulario de servicio
`lib/screens/admin/gestion_servicios_screen.dart` (`ServicioFormSheet`):
- En la cabecera de **Precio base** (`:1037-1043`), una fila:
  `Row([Expanded(Text('Precio base')), TextButton.icon(Icons.calculate_outlined, 'Calcular desde ${_monedaOrigen}', onPressed: _calcularRestoDesdeOrigen)])`
- `_calcularRestoDesdeOrigen()`:
  1. `setState(() => _calculandoPrecios = true)` y **cartel de carga** (overlay/dialogo no
     descartable) con `CircularProgressIndicator` + **«Extrayendo los precios automáticamente…»**.
  2. `final tasas = await TasaCambioService.obtener()`. Si es `null` → SnackBar
     «No se pudo obtener la tasa de cambio. Los precios existentes no se han tocado.» y fin.
  3. Toma el valor del campo de la **moneda de origen** (si está vacío, usa la primera moneda
     con precio). Calcula el resto y escribe en los controladores.
  4. Aplica también a **todas las reglas por opción** (`_reglasPrecio`: fuerza
     `syncMonedas(_monedasHabilitadas)` antes, y convierte `preciosPorOpcion[opcion]` de la
     moneda de origen al resto).
  5. `finally`: quitar el cartel y `_calculandoPrecios = false`.
- Se dispara **automáticamente** la primera vez que el admin escribe un precio en la moneda
  de origen y hay más de una moneda habilitada (con `onEditingComplete`/debounce ~600 ms);
  el botón queda para recalcular a mano.
- **Redondeo antes de escribir**: `toStringAsFixed(decimales)` y `trimCeros` — NUNCA
  `v.toString()` (un `18.375` se relee como **18375** por la regla de los 3 dígitos de
  `parseMonto`). Decimales: `redondeoCup` (0) para CUP, `redondeoDivisa` (2) para el resto.
- Aviso visible en el formulario: «Precios calculados con la tasa del <fecha> — revísalos
  antes de guardar». El admin siempre puede sobrescribir a mano.
- `lib/screens/admin/config_recursos_screen.dart` (`_TurnoFormSheet`): mismo botón/cartel
  para el **precio del turno**; guarda `precios` con **todas** las monedas habilitadas del
  servicio (`{USD: x, EUR: y, CUP: z}`), no solo la moneda por defecto.

### 5.3 Acceso a la configuración
Botón en la AppBar de `gestion_servicios_screen.dart` (`Icons.tune` / «Precios automáticos»)
→ `PrecioConfigScreen(idEntidad)`.

---

## 6. Punto 5 — pago por adelantado del servicio (grande)

### 6.1 Ficheros nuevos
| Fichero | Contenido |
|---|---|
| `lib/models/cobro.dart` | `CobroConfig`, `CobroInfo`, `PagoReserva`, `PagoAdminItem` (+`fromJson` tolerantes). |
| `lib/services/cobro_service.dart` | RPC de §1.1: `infoLocalServicio`, `crearPago`, `reportarPago`, `pagoDeReserva`, `configGet/Set`, `listarPagos`, `verificarPago`, `rechazarPago`. |
| `lib/screens/admin/cobro_config_screen.dart` | Switch «Cobrar por adelantado», número de proveedor Transfermóvil, título, **WhatsApp de verificación**, WhatsApp de soporte, instrucciones, moneda, plazo (horas) y «cancelar si expira». Guarda con `admin_cobro_config_set`. |
| `lib/screens/admin/pagos_reserva_screen.dart` | Bandeja: tabs «Por verificar» / «Verificados» / «Rechazados» / «Expirados»; cada fila con cliente+teléfono, servicio, fecha, importe, código de confirmación, botón WhatsApp (`wa.me/<telefono>`) y «Verificar» / «Rechazar» (rechazar pide motivo). Al abrir llama a `reserva_pago_expirar()`. |
| `lib/widgets/pago_adelantado_sheet.dart` | Hoja del cliente: importe y moneda, instrucciones del admin, botón «Abrir Transfermóvil» (`url_launcher`), «Ya he pagado» (código opcional), «Enviar comprobante por WhatsApp», estado actual (pendiente/reportado/verificado/rechazado + motivo) y cuenta atrás hasta `expira_at`. |

### 6.2 Flujo de cliente
1. En `lib/screens/local_servicio_detail_screen.dart`, tras reservar (o antes, si el
   servicio lo permite), llamar a `CobroService.infoLocalServicio(...)`; si
   `disponible = true` mostrar la opción **«Pagar por adelantado»** con el importe.
   `TutorialAnchor(id:'detalle_pago_adelantado')` envolviendo esa opción.
2. Al aceptar: crear la reserva (como hoy) → `cliente_crear_pago_reserva(idAgenda)` →
   abrir `PagoAdelantadoSheet` con el `url_intent` (deep link Transfermóvil, con respaldo
   `url_http`, igual que `mi_suscripcion_screen.dart:126-236`).
3. «Ya he pagado» → `cliente_reportar_pago_reserva`.
4. En `mis_tickets_screen.dart`, la tarjeta muestra el estado del pago y un botón
   «Pagar por adelantado» / «Gestionar pago» cuando `agenda.pago_estado` no es `verificado`.

### 6.3 Flujo de admin
1. Configura en «Cobro por adelantado» (entrada nueva en
   `lib/screens/admin/mi_suscripcion_screen.dart`, sección CUENTA, o en Mi suscripción).
2. Ve los pagos reportados en la bandeja y verifica/rechaza. El aviso también llega a la
   campana (`tipo='pago'`).
3. Reservas con pago pendiente se ven con chip en el listado de Reservas y en el calendario.

---

## 7. Tutoriales (cliente y admin)

- `lib/services/tutorial_service.dart`: versión `'v2'` → **`'v3'`** (republica el recorrido;
  afecta a los dos flujos, es lo esperado).
- **Cliente** (`pasosCliente()`): un paso nuevo, `detalle_pago_adelantado`, **opcional**,
  insertado antes de `detalle_continuar`, sin `destino` (vive en la hoja de reserva).
- **Admin** (`pasosAdmin()`): dos pasos nuevos, **opcionales**, insertados para no cambiar
  el último (que debe seguir siendo `admin_categorias`):
  - `admin_precio_auto` (tras `admin_precio`, `destino: serviciosFormulario`)
  - `admin_calendario` (antes de `admin_reservas`, `destino: reservas`)
- `test/tutorial_flujos_test.dart`: actualizar la lista exacta y el `length` del cliente
  (13 → 14) y añadir los ids nuevos a los conjuntos de opcionales.
- Anclas nuevas: `detalle_pago_adelantado`, `admin_precio_auto`, `admin_calendario`.

---

## 8. Pendiente en release + Edge Function

| Paso | Estado | Cómo |
|---|---|---|
| Migraciones `60`→`64` en debug | ✅ aplicadas y verificadas | MCP debug (token de escritura de la rama) |
| Migraciones `60`→`64` en **release** | ⏳ **lo aplica el usuario** | pegar **`docs/flow_schema/migraciones/_APLICAR_RELEASE_60_64.sql`** (los 5 ficheros ya concatenados, en orden, idempotente) en el SQL Editor de `vsieeihstajlrdvpuooh` |
| Edge Function `flow-tasas` | ⏳ **la despliega el usuario** | Dashboard → Edge Functions → Deploy a new function → nombre **`flow-tasas`** → pegar `docs/flow_schema/edge_functions/flow-tasas/index.ts` → **Verify JWT activado**. Alternativa: `supabase functions deploy flow-tasas` |

Comprobado en release antes de preparar el pegado: `pg_net 0.14.0` presente con
`net.http_get(url, params, headers, timeout_milliseconds)` y
`net._http_response(id, status_code, content_type, headers, content, timed_out, error_msg, created)`
— exactamente las columnas/firma que usa la migración 64. `pg_cron 1.6` y
`public.fn_is_superadmin_full_access()` también están.

> **El sistema funciona sin la Edge Function**: `flow.tasas_refrescar()` +
> `flow.tasas_ingest()` hacen el refresco con `pg_net` desde Postgres (verificado de
> punta a punta en debug). La Edge Function es el camino principal (una sola llamada) y
> `pg_net` el respaldo: si la función no está desplegada, la app cae sola al respaldo.

### 8.1 Qué hace la app cuando no hay Edge Function
`TasaCambioService.obtener()` intenta `functions.invoke('flow-tasas')`; si falla,
llama a `tasas_refrescar()`, espera ~1,5 s (con el cartel «Extrayendo los precios
automáticamente…» visible) ingiriendo la respuesta y devuelve la tasa cacheada. El
resultado se guarda en memoria durante la sesión.

---

## 9. Verificación

### 9.1 App Flutter
- `mcp__dart__analyze_files` sobre **todo** `inventtia_flow` → **0 errores** (solo
  avisos/infos preexistentes: `print`, `withOpacity`, `value:` deprecado, imports muertos
  en ficheros ajenos). Los 3 avisos nuevos que aparecieron en código nuevo se corrigieron.
- `flutter test` (vía `mcp__dart__run_tests`) → **880/880 en verde** (antes ~700; +180
  tests, de ellos ~150 nuevos de este trabajo).
- Tests nuevos: `conversion_precio_test` (38 con los otros dos de precios),
  `tasa_cambio_model_test`, `precio_config_test`, `vista_reservas_test` (24),
  `resumen_reservas_model_test` (35), `motivo_cancelacion_test`, `notificacion_color_test`,
  `cobro_model_test` (28). `tutorial_flujos_test` actualizado (14 pasos de cliente).

> Nota de entorno: el CLI `flutter analyze` / `dart analyze` **se cuelga** en esta
> máquina (el sandbox de Windows no deja lanzar el `analysis_server`); por eso la
> verificación se hizo con el analizador y el runner del **MCP de Dart**, que es
> justo lo que fija la convención del repo.

### 9.2 Base de datos (debug) — pruebas de extremo a extremo ejecutadas
| Prueba | Resultado |
|---|---|
| Re-aplicar el bundle completo 60→64 sobre una BD ya migrada | ✅ OK (idempotente) |
| `admin_cancelar_agenda(1)` sin motivo | ✅ `Debes indicar el motivo de la cancelacion` |
| `staff_cancelar_reserva(1)` sin motivo | ✅ mismo error |
| `staff_marcar_estado_agenda(1,2)` sin motivo | ✅ mismo error |
| Cancelación **real** como admin (claims JWT del dueño, reserva de otro usuario) | ✅ `motivo_cancelacion` guardado, `cancelado_por_rol='admin'`, `cancelado_at` sellado |
| Notificación de esa cancelación | ✅ `tipo='cancelacion'`, título «Reserva cancelada», mensaje con el motivo, `data.motivo`, `data.cancelada_por='admin'`, destinatario = el cliente |
| `admin_listar_agendas` tras cancelar | ✅ el item trae `motivo_cancelacion` |
| `_mensaje_cancelacion` con motivo / sin motivo / cliente | ✅ las tres variantes textuales correctas |
| `_tasas_conversiones` | ✅ MLC→EUR = 0,754184 (cruce por CUP), USD→CUP 840, EUR→CUP 925 |
| `tasas_refrescar()` + `tasas_ingest()` contra el proveedor real | ✅ tasa cacheada en `flow.tasa_cambio` |
| `cliente_cobro_info` sin config | ✅ `{ok:true, data:{disponible:false}}` |
| Cobro por adelantado E2E: config → reserva → intento → «ya he pagado» → verificación | ✅ monto 1500 CUP, `numero_proveedor` en el deep link, código de confirmación guardado, `pago_estado='verificado'`, `verificado_por` = admin, 2 notificaciones `tipo='pago'` |
| Expiración automática: intento vencido → barrido | ✅ pago `expirado`, reserva cancelada, `cancelado_por_rol='sistema'`, motivo «No se verifico el pago…», notificación `tipo='cancelacion'`; **2ª pasada: 0 canceladas** (idempotente) |
| Guards de permisos (`admin_calendario_reservas`, `admin_precio_config_get`) con usuario ajeno | ✅ `{ok:false, error:'No tiene permisos…'}` |
| Limpieza de los datos de prueba | ✅ `agenda`, `reserva_pago`, `cobro_config` y `notificaciones` de prueba borrados; queda solo la tasa real cacheada |

### 9.3 Lo que queda por verificar **en el dispositivo**
No hay emulador en esta sesión, así que el recorrido visual (calendario, hoja de pago,
cartel de extracción de precios) está pendiente de una pasada manual: §10.

## 10. Checklist de prueba manual (15 minutos)

1. **Cabecera del cliente**: entrar como admin → el Home muestra `Hola, … / [🔔][avatar] /`
   y debajo la píldora «Volver al panel de administración»; no se ve el selector de
   provincia. Entrar como cliente puro: ni píldora ni hueco.
2. **Cancelar con motivo**: Gestión → Reservas → tarjeta con acción «Cancelar» → escribir
   el motivo → aceptar. Comprobar: bloque rojo «Motivo de cancelación» en la tarjeta;
   en la cuenta del cliente, notificación **roja** «Reserva cancelada» con el motivo.
3. **Calendario**: Reservas → icono de calendario (AppBar) → se abre en el mes de hoy y
   llega hasta el último mes con reservas; alternar calendario ↔ lista; tocar un día.
4. **Precios automáticos**: Catálogo → editar un servicio con 2+ monedas → escribir un
   precio y pulsar «Calcular desde USD» → aparece «Extrayendo los precios automáticamente…»
   y se rellenan las demás monedas (y las reglas). Repetir en un turno (Recursos → Turno).
   En el AppBar de Catálogo, el icono de ajustes abre «Precios automáticos».
5. **Pago por adelantado**: Mi suscripción → «Cobro por adelantado» → activar con número
   de proveedor y WhatsApp → como cliente, reservar y pagar por adelantado → «Ya he
   pagado» → como admin, Reservas → icono de pagos → verificar.
6. **Tutoriales**: Perfil → «Ver el tutorial otra vez» (cliente) y Gestión → icono de
   tutorial (admin): deben aparecer los pasos nuevos.
7. **Bot de la cola**: anotar un cliente en la lista de espera de un turno, llenar ese
   turno con una reserva y cancelarla. El cliente de la cola debe recibir su reserva
   (y su notificación) sin que nadie ejecute nada a mano.

## 11. Bitácora de ejecución

| Fecha | Paso | Resultado |
|---|---|---|
| 27-10-2026 | Reconocimiento | 4 informes (cancelación/notificaciones, precios, tutoriales, calendario) + introspección de la BD viva en debug y release (`pg_get_functiondef` de las 6 funciones a reescribir). |
| 27-10-2026 | Migraciones 60-64 | Escritas y **aplicadas en debug** vía MCP. Verificado: 4 tablas, 8 columnas en `agenda`, 18 funciones nuevas, 7 políticas RLS, sin sobrecargas. |
| 27-10-2026 | Tasa real cacheada | `tasas_refrescar()` + `tasas_ingest()` contra `widgets.directoriocubano.info`: USD→CUP 840, EUR→CUP 925, MLC→EUR 0,754184. |
| 27-10-2026 | Bug encontrado y corregido | `jsonb_set` no crea objetos intermedios: la matriz `conversiones` salía vacía. Se armó por filas de moneda y se verificó el cruce por CUP. |
| 27-10-2026 | Edge Function | `flow-tasas/index.ts` escrito. **No desplegable con los tokens disponibles** (`edge_functions_write` ausente) → se añadió el respaldo `pg_net` (migración 64), probado de punta a punta. La despliega el usuario. |
| 27-10-2026 | Bundle de release | `_APLICAR_RELEASE_60_64.sql` (los 5 ficheros concatenados, 141 KB) y probado re-aplicándolo entero sobre debug: idempotente. `pg_net 0.14.0` de release verificado compatible con la 64. |
| 27-10-2026 | App Flutter (5 frentes en paralelo) | Cancelación+rojo, calendario, precios, pagos y tutoriales entregados; el Lead integró los dos botones nuevos del AppBar de Reservas y limpió 3 avisos nuevos. |
| 27-10-2026 | Verificación | analyze **0 errores**, **880/880 tests**, y las 13 pruebas SQL de §9.2 en verde. |
| 27-10-2026 | **Fix 1 — permiso del schema** | La Edge Function devolvía `{"ok":false,"error":"No se pudo leer la cache: permission denied for schema flow"}`. Causa: en **release** `flow` solo tenía `USAGE` para `anon`/`authenticated`; `service_role` no. Solución: migración **65** (`grant usage on schema flow to service_role`) + el mismo grant añadido a la 60. En debug era no-op. |
| 27-10-2026 | **Fix 2 — la función no muere por la caché** | `flow-tasas` ya no devuelve 500 si no puede leer/escribir la caché: la caché es una optimización, así que consulta el proveedor y devuelve las tasas con un `aviso`. Requiere **volver a desplegar** la función para que aplique. |
| 27-10-2026 | **Fix 3 — cálculo automático de verdad** | Antes solo se disparaba **una vez** y solo escribiendo en la moneda de origen (y abría un diálogo modal). Ahora: se dispara **al teclear en cualquier moneda** (debounce 700 ms), recalcula base **y reglas**, reutiliza la tasa de hoy sin red, y muestra un **banner discreto** dentro del formulario («Extrayendo los precios automáticamente…») en vez del diálogo. El botón queda para forzar el refresco de la tasa. También se rellena al habilitar una moneda nueva. |
| 27-10-2026 | Fix 3 — robustez del respaldo | `TasaCambioService`: sondeo hasta ~3 s y **reutilización del `request_id` pendiente** (si la respuesta de `pg_net` llega entre dos teclas, se recoge sin otra petición HTTP). |
| 27-10-2026 | **Bot al cancelar (punto 6)** | Al cancelar se liberaba cupo pero **nadie avisaba al bot**: no había cron del bot ni trigger en `agenda`, así que el hueco quedaba vacío y el siguiente de `flow.sala_espera` no recibía su turno. Solución: **migración 66** — trigger `trg_agenda_bot_al_cancelar` **diferido** (`initially deferred`) que, al confirmarse la transacción, llama a `bot_procesar_recurso_dia(turno, día)` o a `bot_procesar_plan(id_plan)`. Diferido porque las funciones de cancelación actualizan el estado **antes** de devolver el cupo: en el COMMIT ya está libre. Cubre las 4 vías (admin, vendedor/staff, cliente y expiración de pago) sin tocarlas. |
| 27-10-2026 | Prueba E2E del bot | Con cupo 1/1 lleno y un cliente en la cola de ese turno: al cancelar, el trigger repartió el hueco → `bot_log` `{resultado:'ok', movidos:1, cupo:1}`, la cola quedó vacía, se creó la reserva del cliente con notificación «Reservacion confirmada» y al ocupante le llegó «Reserva cancelada». Datos de prueba borrados. |
| 27-10-2026 | Cabecera del cliente | Se ocultó el selector de provincia («Todas las provincias») y en su fila va la píldora «Volver al panel de administración» (solo admin); la fila de iconos queda `[🔔][avatar]`. El filtro por provincia sigue en la hoja de filtros. Se eliminó el código del selector que quedaba sin uso. analyze 0 errores y 880/880 tests. |
| 27-10-2026 | Acceso rápido a suscripción y cobros | Nuevo `_ModuloCard` **«Suscripción y cobros»** en el grid de Gestión (el 6.º), que abre **Mi suscripción**: ahí están el plan, «Configurar el cobro» y «Pagos por verificar» con su contador. |
| 27-10-2026 | Cierre del hueco del pago en «Mis reservas» | Se completó lo que faltaba del §6.2: `Agenda` gana `pagoEstado/pagoMonto/pagoMoneda` (migración 63), `utils/estado_pago.dart` centraliza el vocabulario (etiqueta/color/icono/`enCurso`/`sePuedePagar`) y la tarjeta de **Mis reservas** pinta el chip del pago y el botón **Pagar / Gestionar / Reintentar** (el staff solo ve el chip). El mismo vocabulario lo usa ya el resumen-calendario. 888/888 tests (8 nuevos de `estado_pago_test`). |
| 27-10-2026 | AppBar de Reservas: calendario a la izquierda | El botón del **resumen-calendario** pasó de `actions` a `leading` (2 iconos a la izquierda —volver + calendario— y 4 a la derecha: pagos, PDF, Excel, refrescar). `leadingWidth: 104` como en Gestión; el nombre de la entidad pasa a `ellipsis` para que un nombre largo no desborde con el hueco más estrecho. El ancla `admin_calendario` se movió con el botón: el paso del tutorial sigue funcionando sin tocar los flujos. 888/888. |
| 27-10-2026 | Precios automáticos: fiabilidad y señales visuales | Tras el aviso de que editar CUP no recalculaba: (a) la firma global `_firmaCalculada` pasa a un **mapa por moneda de origen** (`_ultimoCalculado`), de modo que un cálculo no puede bloquear a otro —mismo cambio en el precio del turno—; (b) cambiar la **moneda base** en el desplegable ahora **recalcula al instante** (antes solo se recalculaba si tocabas el campo de USD); (c) la **moneda base va primera** en el bloque de precios y se distingue con un sello **BASE** y el color de marca; (d) todo precio puesto por el cálculo sale **verde con un icono ✨ dentro del cuadro** (base y reglas por opción) y pierde el verde al editarlo a mano. 888/888. |
| 27-10-2026 | **Causa raíz del «BASE en $»** | `_origenEfectivo` miraba `precio_config.moneda_origen` (**la preferencia de la entidad**, USD por defecto) y le daba prioridad sobre el desplegable «Moneda por defecto»: por eso elegir MLC dejaba el sello BASE en `$` y el cálculo seguía saliendo del USD. Ahora **la base es la del desplegable**; la preferencia de la entidad solo se usa para *proponerla* al crear un servicio nuevo. Mismo criterio en el precio del turno (la base es la del servicio, `widget.moneda`). Además: la lista de precios se reordena con **animación** (`AnimatedSwitcher` con clave = moneda base: fundido + deslizamiento) para que la base quede siempre de primera, y bajo el desplegable se explica «Esta es la moneda base: es la que escribes y de la que se calculan las demás». |
| 27-10-2026 | **Pago por adelantado POR SERVICIO (migración 67)** | Faltaba el interruptor: el cobro se activaba por entidad y eso encendía la opción en **todos** los servicios. Ahora `app_dat_servicios.cobro_adelantado` (nace en `false`) decide servicio a servicio, con la cuenta de la entidad como interruptor maestro. `cliente_cobro_info` exige las dos condiciones y un trigger en `reserva_pago` corta cualquier intento en un servicio que no lo acepta. En el admin: switch «Pago por adelantado en línea» en el formulario del servicio (deshabilitado con su explicación si la entidad no lo tiene activo), fila «Pago por adelantado: Sí/No» en el detalle y `setCobroAdelantado` por PostgREST (la RLS valida la pertenencia, como con `activo`). Verificado en la BD: servicio apagado ⇒ `disponible:false`; encendido ⇒ `disponible:true`; y el trigger aborta el intento con un mensaje claro. 888/888. |

## 12. Qué queda pendiente (y de quién es)

| Paso | De quién | Dónde |
|---|---|---|
| **Si ya aplicaste 60-64**: ejecuta solo `_PENDIENTE_RELEASE_65_67.sql` (17 KB) | usuario | `docs/flow_schema/migraciones/_PENDIENTE_RELEASE_65_67.sql` |
| **Si no has aplicado nada**: el bundle completo 60→67 | usuario | `docs/flow_schema/migraciones/_APLICAR_RELEASE_60_67.sql` |
| Re-desplegar la Edge Function **`flow-tasas`** (opcional: la hace tolerante a fallos de caché) | usuario | Dashboard → Edge Functions → `flow-tasas` → editar y desplegar |
| Pasada manual del checklist §10 en un dispositivo | usuario | app en debug (`flutter run`) |

Qué arregla cada una de las pendientes:
- **65** — el `permission denied for schema flow` de la Edge Function (permiso, no datos).
- **66** — que al cancelar se le dé el turno al siguiente de la cola (bot). Sin esta
  migración, la cancelación funciona igual pero el hueco no se reparte solo.
- **67** — el interruptor de pago por adelantado **por servicio**. Sin ella, el switch
  del formulario no tiene columna donde guardarse y todos los servicios de una entidad
  con cobro activo lo ofrecerían.

Mientras no se apliquen las migraciones en release, la app **degrada con mensajes
legibles** (no con errores técnicos): `mensajeErrorCancelacion` traduce el PGRST202 a
«Falta aplicar la migración 61 en Supabase…» y `esErrorDeEsquemaAusente` hace lo mismo en
el calendario y en el cobro.

## 13. Entregables (ficheros tocados)

### SQL + servidor (nuevos)
`docs/flow_schema/migraciones/60…64_*.sql`, `docs/flow_schema/migraciones/_APLICAR_RELEASE_60_64.sql`,
`docs/flow_schema/edge_functions/flow-tasas/index.ts`.

### App — nuevos
| Área | Ficheros |
|---|---|
| Cancelación | `utils/motivo_cancelacion.dart`, `widgets/dialogo_motivo_cancelacion.dart` |
| Calendario | `utils/vista_reservas.dart`, `models/resumen_reservas.dart`, `services/calendario_service.dart`, `screens/admin/resumen_reservas_screen.dart` |
| Precios | `models/tasa_cambio.dart`, `models/precio_config.dart`, `services/tasa_cambio_service.dart`, `services/precio_config_service.dart`, `utils/conversion_precio.dart`, `screens/admin/precio_config_screen.dart` |
| Pago | `models/cobro.dart`, `services/cobro_service.dart`, `screens/admin/cobro_config_screen.dart`, `screens/admin/pagos_reserva_screen.dart`, `widgets/pago_adelantado_sheet.dart` |
| Tests | `conversion_precio_test`, `tasa_cambio_model_test`, `precio_config_test`, `vista_reservas_test`, `resumen_reservas_model_test`, `motivo_cancelacion_test`, `notificacion_color_test`, `cobro_model_test` |

### App — modificados
`models/agenda.dart`, `models/notificacion.dart`, `utils/reserva_listado.dart`,
`services/agenda_service.dart`, `services/agenda_admin_service.dart`,
`screens/home_client_screen.dart`, `screens/admin/reservas_screen.dart`,
`screens/vendedor/vendedor_screen.dart`, `screens/mis_tickets_screen.dart`,
`screens/notificaciones_screen.dart`, `screens/admin/gestion_servicios_screen.dart`,
`screens/admin/config_recursos_screen.dart`, `screens/admin/mi_suscripcion_screen.dart`,
`screens/local_servicio_detail_screen.dart`, `tutorial/tutorial_flujos.dart`,
`services/tutorial_service.dart`, `test/tutorial_flujos_test.dart`.

> `tutorial_navegacion.dart` **no** necesitó cambios: `serviciosFormulario` y `reservas` ya
> se resolvían allí.

### Scripts de apoyo (fuera de la app, en `.dsh/`)
`apply_migration.py` y `deploy_edge_function.py`: aplican las migraciones y despliegan
Edge Functions leyendo los ficheros del repo, para no pegar SQL en la conversación. No son
parte del producto; si molestan, se borran sin afectar a nada.