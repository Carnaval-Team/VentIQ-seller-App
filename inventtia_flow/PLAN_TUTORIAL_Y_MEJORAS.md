# Plan — Tutoriales guiados + ajustes cliente/admin (`inventtia_flow`)

**Ámbito:** app Flutter `inventtia_flow` (GoReserva) + esquema `flow` de Supabase.
**Creado:** antes de tocar código, a partir de auditoría del código real (no de los
`.sql` del repo, que están desactualizados).
**Regla de trabajo:** cada fase se implementa, se analiza con `dart analyze` y se
verifica con test. Nada se da por hecho sin evidencia.

> Nota de nombre: **no** sobreescribí `plan.md` porque ya contiene la auditoría
> verificada del Home (970 líneas). Este documento es el plan de esta iteración.

---

## 0. Decisiones cerradas

| # | Tema | Decisión |
|---|------|----------|
| D1 | FK al eliminar turno | `flow.agenda.id_turno` → **ON DELETE SET NULL** (la reserva sobrevive sin vínculo al turno). `flow.sala_espera.id_turno` → **ON DELETE CASCADE** (una entrada de cola con `id_turno` NULL significa "cualquier turno" para el bot, así que no puede quedar NULL). Confirmado por el usuario. |
| D2 | Orden de notificaciones | Se ordena por `created_at DESC, id DESC` (el `id` es el desempate porque `current_timestamp` es la hora de transacción y varios inserts de un mismo CTE comparten `created_at`). Vale para cliente y admin: **comparten pantalla y provider**. |
| D3 | Cancelación del cliente | Se arregla en la UI: hoy `onCancelar: null` deja el botón muerto. Regla: estado `Reservado` **y** la fecha/hora de la reserva no ha pasado **y** se respeta `horas_anticipacion_cancelacion`. |
| D4 | Calendario "fuera del mes" | El límite era `lastDay` = fin del mes del último día con datos. Se amplía el horizonte (12 meses en modo lista de espera, 6 meses en reserva directa) y se ancla `firstDay` al mes actual. El RPC acepta cualquier fecha (no valida mes). |
| D5 | Precio por dato adicional | El precio propio del turno pasa a ser **precio base del turno**; sobre él **sí** se evalúan las reglas de `config_precio` (hoy se ignoran por completo). Una regla sin precio para la moneda elegida ya **no** devuelve 0: cae al base. Se aceptan precios como número o string. |
| D6 | Reglas múltiples | Se mantiene "primera regla coincidente con precio gana" (cambiarlo alteraría precios ya guardados en silencio), pero se **avisa en la UI del admin** en vez de que sea un bug invisible. |
| D7 | Persistencia del tutorial | `SharedPreferences` con clave por usuario/entidad: `flow_tutorial_cliente_v1_<uuid>` y `flow_tutorial_admin_v1_<uuid>_<idEntidad>`. No se toca Supabase (no hay tabla de preferencias de usuario y no hace falta). Valores `visto` y `omitido` significan ambos "no volver a mostrar". Se añade botón "Ver tutorial otra vez". |
| D8 | Motor del tutorial | Sin dependencias nuevas (no hay `showcaseview` ni similar en `pubspec.yaml`): overlay propio con `MaterialApp.builder`, recorte por 4 rectángulos (así el widget resaltado **recibe de verdad** el toque del usuario), burbuja con el estilo de `PistaBusquedaAvanzada`, y avance automático cuando el ancla del paso siguiente se registra (permite tutorial multi-pantalla). |
| D9 | Migraciones | Los ficheros SQL se dejan en `inventtia_flow/docs/flow_schema/migraciones/` y **los aplica el usuario** desde el SQL Editor de Supabase. Numeración siguiente libre: **50** y **51**. |

---

## 1. Estado de partida verificado (evidencia)

### 1.1 Notificaciones
- Fetch único: `lib/services/notificacion_service.dart:35-41` → `.order('id', ascending: false).limit(100)`.
- Stream realtime: `lib/services/notificacion_service.dart:115-124` → `.order('id', ascending: false)`.
- **Bug de orden**: `lib/providers/notificacion_provider.dart:62-64` hace `rows.reversed` creyendo que el stream llega ascendente; en `supabase 2.13.0` (`SupabaseStreamBuilder._sortData`) ya llega `id DESC`, así que la lista queda **ascendente (lo más viejo primero)**. Además `recargar()` (`:117-130`) no invierte → realtime y pull-to-refresh muestran órdenes distintos.
- La pantalla `lib/screens/notificaciones_screen.dart:32-40` confía ciegamente en el orden y **no agrupa por día**; la fecha se pinta relativa (`:353-362`).
- El índice de la tabla es `(uuid_usuario, created_at desc)` → ordenar por `id` no lo aprovecha.
- **El área admin no tiene campana ni acceso propio**: 0 referencias a notificaciones en `lib/screens/admin/**`; el admin solo llega por `lib/screens/perfil_screen.dart:239-244,318`. La RLS aísla por `uuid_usuario`, así que el admin ve solo lo suyo (p. ej. `tipo='suscripcion'`, `docs/flow_schema/migraciones/45_suscripciones_pagos.sql:100-108`).

### 1.2 Calendario de "anotarme en la lista"
- Hoja: `lib/screens/local_servicio_detail_screen.dart:2716-3075` (`_DisponibilidadSheet`).
- `firstDay`/`lastDay` se derivan de los datos: `DateTime.utc(first.year, first.month, 1)` y `DateTime.utc(last.year, last.month + 1, 0)` (`:2933-2934`). Si el admin solo tiene planes del mes actual, `lastDay` es fin de mes → al deslizar al mes siguiente el `PageView` rebota: "hace como que cambia pero se queda".
- `onPageChanged` sí guarda `_focusedDay` (`:3053`); el problema es el rango, no el estado.
- En modo espera `enabledDayPredicate` ya devuelve `true` para cualquier día futuro (`:2961`), así que basta ampliar el rango para poder anotarse fuera del mes.
- `_anotarse()` (`:327-391`) llama a `ListaService.entrarSalaEspera` → RPC `cliente_entrar_sala_espera_reserva`, que hace `coalesce(p_fecha_regla, current_timestamp)` **sin validar mes** (`docs/flow_schema/rpc clientes/05_entrar_sala_espera.sql:128`). No hace falta cambio de backend.

### 1.3 Cancelación por el cliente
- La UI existe pero está **desconectada**: `lib/screens/mis_tickets_screen.dart:429` pasa `onCancelar: null`, y el botón solo se pinta si `_puedeCancelar && onCancelar != null` (`:1216`). `_cancelar()` (`:102-169`) es código muerto.
- `_puedeCancelar` (`:952-958`) compara `ticket.estado?.nombre != 'reservado'` (case-sensitive, en vez de usar `EstadoAgenda.esReservado`, `lib/models/agenda.dart:17`) y **no comprueba que la reserva no haya pasado**.
- El RPC cliente ya existe en el repo: `docs/flow_schema/rpc clientes/12_cliente_cancelar_reserva.sql` (valida propiedad, estado `Reservado` y `horas_anticipacion_cancelacion`). El servicio Dart ya lo llama: `lib/services/agenda_service.dart:259-273`.
- `lib/screens/mis_tickets_screen.dart:935-936` compara estados con strings en minúscula sin normalizar.

### 1.4 Eliminar turno (FK)
- `flow.agenda.id_turno` y `flow.sala_espera.id_turno` se crean sin `on delete`
  (`docs/flow_schema/migraciones/16_recursos_tramos_turnos.sql:130-138`); constraints reales
  `agenda_id_turno_fkey` / `sala_espera_id_turno_fkey` (`SQL_OPTIMIZATION/flow.sql:88,103`).
- `admin_eliminar_turno` hace `delete from flow.turno where id = p_id`
  (`docs/flow_schema/rpc admin/25_admin_recursos.sql:329`) → `23503`.
- UI: `lib/screens/admin/config_recursos_screen.dart:327,355` → `lib/services/recurso_service.dart:308-322`.

### 1.5 AppBar del dashboard admin
- Tema global: `lib/config/app_theme.dart:37-42` (`backgroundColor: scheme.primary` #405F90, `foregroundColor: scheme.onPrimary`).
- **Fallo de contraste**: `lib/screens/admin/gestion_screen.dart:113` y `:114-118` pintan el selector de entidad con `AppTheme.textPrimary` (#1A237E) sobre #405F90 → **2.05:1** (WCAG AA exige 4.5:1). Solo se ve con 2+ entidades (con una sola se usa un `Text` sin color y hereda blanco). Espejo: `lib/screens/vendedor/vendedor_screen.dart:1149-1156`.
- No existe widget compartido de AppBar: 15 `AppBar` inline en `lib/screens/admin/**`.

### 1.6 Datos adicionales y reglas de precio
- `CampoAdicional` (`lib/models/campo_adicional.dart:52-69`) **no tiene ningún campo de precio**; la expresividad vive en `ConfigPrecio.reglas[].preciosOpcion{opcion→{moneda→precio}}` (`lib/models/config_precio.dart:28`): precio absoluto por opción de un `select`, que **reemplaza** al base.
- Aritmética duplicada: Dart `lib/utils/precio_reserva.dart:34-60` y SQL `docs/flow_schema/migraciones/15_servicio_precio.sql:78-125`, ambas "primera regla coincidente gana, `unit × cantidad`".
- **Bug central**: `docs/flow_schema/migraciones/21_precio_turno.sql:36-45` devuelve el precio del turno **sin mirar `p_datos`** → en servicios con turno con precio fijo, las reglas por dato adicional nunca se cobran. Mismo atajo en Dart: `lib/screens/reserva_transporte_sheet.dart:162-165` y `lib/screens/admin/admin_reserva_transporte_sheet.dart:155-164`.
- Otros defectos probados: regla sin precio para la moneda elegida → total **0** en vez del base (`precio_reserva.dart:41`, `15_...sql:112`); precios guardados como string se descartan en la app y se cobran en el servidor (`config_precio.dart:64,123` vs `15_...sql:110`); el preview del admin ignora el turno (`lib/screens/admin/reservas_screen.dart:1963-1972`) mientras el guardado sí lo aplica (`lib/services/agenda_admin_service.dart:264-289`); `calcularTotales`/`contabilizar` es código muerto (`lib/widgets/totales_datos_adicionales.dart:14-102`, nunca llamado); `"1.500"` se guarda como 1,5 (`lib/screens/admin/gestion_servicios_screen.dart:449,468`).
- Config del admin: `lib/screens/admin/gestion_servicios_screen.dart:1004-1030` ("Reglas de precio por dato adicional") y `:1690-1835` (campos); guardado en `flow.app_dat_servicios.campos_adicionales / config_precio` (`docs/flow_schema/rpc admin/10_admin_config_datos_servicio.sql:30-32`).

### 1.7 Tutorial guiado
- **No hay paquete de tour/coachmark** en `pubspec.yaml`; sí `shared_preferences: ^2.3.5` y `provider: ^6.1.2`.
- No existe ningún `OverlayEntry` ni spotlight en todo `lib/`: el oscurecido con agujero **se construye desde cero**.
- El mensaje del botón "filtrar" es `PistaBusquedaAvanzada` (`lib/widgets/pista_busqueda_avanzada.dart`): burbuja blanca `Material(elevation: 6, radius 16)`, flecha `CustomPaint`, X de 44×44, copy `'¿No encuentras lo que buscas?'`. Anclaje con `LayerLink` + `CompositedTransformFollower` (`lib/screens/catalogo_screen.dart:44,540-550,694-700`) y "una sola vez" con `prefs.getBool('catalogo_pista_filtros_vista')` (`:85-108`). **Este es el estilo a reutilizar.**
- Rol: no hay rol persistido; `EntidadProvider.isAdmin = _misEntidades.isNotEmpty` (`lib/providers/entidad_provider.dart:19-20`). Por eso el tutorial de admin debe dispararse **dentro de** `GestionScreen`, no en `HomeShell`.
- Puntos de entrada: `/home` desde `lib/screens/perfil_setup_screen.dart:128` y `lib/screens/splash_screen.dart:115-123`.
- Casi ningún botón tiene `Key`: hay que **añadir anclas** (`GlobalKey`).

---

## 2. Fases

### F0 — Baseline (antes de escribir nada)
- `dart analyze` sobre `lib/` y `test/` para conocer avisos preexistentes.
- `flutter test` para tener el conteo verde de partida (referencia: 255 tests en el cierre anterior).
- **Criterio:** baseline anotado en este fichero (§7) antes de tocar código.

### F1 — Notificaciones ordenadas por fecha (cliente + admin)
**Ficheros:** `lib/services/notificacion_service.dart`, `lib/providers/notificacion_provider.dart`,
`lib/screens/notificaciones_screen.dart`, `lib/utils/notificacion_orden.dart` (nuevo),
`test/notificacion_orden_test.dart` (nuevo).

1. Helper puro y testeable en `lib/utils/notificacion_orden.dart`:
   `List<Notificacion> ordenarPorFecha(List<Notificacion>)` → `createdAt` desc, desempate `id` desc.
   Y `String etiquetaDiaNotificacion(DateTime)` → `'Hoy' | 'Ayer' | 'dd/MM/yyyy'`.
2. `notificacion_service.dart`: `.order('created_at', ascending: false).order('id', ascending: false)`
   en `getMisNotificaciones` (`:40`) y en `watch` (`:121`).
3. `notificacion_provider.dart`: quitar `rows.reversed` (`:64`) y usar `ordenarPorFecha(...)`
   tanto en el stream (`:76`) como en `recargar()` (`:121`).
4. `notificaciones_screen.dart`: cabeceras de día (`Hoy`, `Ayer`, fecha) intercaladas en el
   `ListView`, sin cambiar el diseño de la tarjeta. Contador del hero sin cambios.
5. Admin: añadir `NotificacionesBell(color: Colors.white)` a la AppBar de `GestionScreen`
   (ver F5, mismo fichero) para que el admin tenga acceso real a sus avisos.

**Criterio:** los tests del helper pasan; el orden es descendente y estable con `created_at`
idéntico; pull-to-refresh y realtime coinciden; el admin ve la campana.

### F2 — Calendario: anotarse en la lista fuera del mes actual
**Ficheros:** `lib/utils/rango_calendario.dart` (nuevo), `lib/screens/local_servicio_detail_screen.dart`,
`test/rango_calendario_test.dart` (nuevo).

1. Helper puro `rangoCalendario({required List<DateTime> diasDisponibles, required bool paraEspera, DateTime? ahora})`
   → `(DateTime firstDay, DateTime lastDay)`:
   - `firstDay` = primer día del mes actual (nunca después del primer día con datos).
   - `lastDay` = mayor entre (último día del mes del último día con datos) y
     (mes actual + 12 en modo espera / + 6 en reserva directa), siempre al último día del mes.
2. `_DisponibilidadSheet` (`local_servicio_detail_screen.dart:2716-3075`): usar el helper en
   `firstDay`/`lastDay` (`:2933-2934`); `_focusedDay` clampeado a `[firstDay, lastDay]` en
   `initState` (`:2737-2739`) y en `onPageChanged` (`:3053`).
3. En modo espera, el día elegido fuera de `widget.dias` ya funciona (`disp == null` → se ofrecen
   los turnos configurados en `_confirmar`, `:2762-2764`). Verificarlo con test de widget si es viable.

**Criterio:** en modo "Anotarme en la lista" se puede navegar y elegir días de meses siguientes
y la fecha elegida llega a `fechaRegla`; en reserva directa los días sin cupo siguen deshabilitados.

### F3 — El cliente puede cancelar su reserva
**Ficheros:** `lib/utils/reserva_listado.dart`, `lib/screens/mis_tickets_screen.dart`,
`test/reserva_cancelacion_test.dart` (nuevo).

1. Helper puro en `lib/utils/reserva_listado.dart`:
   `bool puedeCancelarCliente(Agenda agenda, {DateTime? ahora})`:
   - `agenda.estado?.esReservado == true` (usa el getter, `lib/models/agenda.dart:17`);
   - la fecha/hora de la reserva no ha pasado (`ahora == null || ahora.isBefore(agenda.fechaHoraReserva)`);
   - si `entidad.horasAnticipacionCancelacion > 0`, aún queda ese plazo.
2. `_TicketCard._puedeCancelar` (`:952-958`) delega en el helper (sin lógica duplicada).
3. `_esCompletada`/`_esCancelada` (`:935-936`) usan `esCompletado`/`esCancelado`.
4. `_cancelar()` (`:102-169`) valida también que la fecha no haya pasado antes de llamar al RPC.
5. **Cableado**: `itemBuilder` (`:426-437`) pasa `onCancelar: _esVendedor ? null : _cancelar`
   y `onCancelarStaff` sigue siendo solo para staff.
6. Si el RPC `flow.cliente_cancelar_reserva` no existiera en la BD viva, se aplica
   `docs/flow_schema/rpc clientes/12_cliente_cancelar_reserva.sql` (ya está en el repo; el
   servicio Dart ya lo invoca).

**Criterio:** una reserva activa y futura muestra "Cancelar reserva" al cliente; una pasada,
cancelada o completada no la muestra; el estado tras cancelar queda `Cancelado` y la lista se recarga.

### F4 — Admin: eliminar turno sin error de FK (migración 50)
**Ficheros:** `docs/flow_schema/migraciones/50_agenda_sala_espera_turno_on_delete.sql` (nuevo),
`lib/services/recurso_service.dart` (mensaje de error legible), `lib/screens/admin/config_recursos_screen.dart` (aviso previo).

1. Migración 50 (SQL completo en §3.1): `agenda` → `SET NULL`, `sala_espera` → `CASCADE`,
   `turno_tramo` reafirmado `CASCADE`.
2. `eliminarTurno` (`recurso_service.dart:308-322`): si el RPC responde `ok != true`, lanzar el
   mensaje del servidor en vez de un error genérico.
3. `_eliminarTurno` (`config_recursos_screen.dart:327-355`): diálogo de confirmación que avise de
   que las reservas de ese turno conservan su fecha pero pierden el turno, y que las personas en
   cola de ese turno salen de la lista.

**Criterio:** borrar un turno con agendas y con sala de espera devuelve `ok:true`; las reservas
siguen existiendo con `id_turno = null`; no hay `23503`.

### F5 — AppBar del dashboard admin con contraste
**Ficheros:** `lib/config/app_theme.dart`, `lib/screens/admin/gestion_screen.dart`,
`lib/screens/vendedor/vendedor_screen.dart`, `test/appbar_contraste_test.dart` (nuevo).

1. `_EntidadSelector` (`gestion_screen.dart:89-140`): color blanco (`Colors.white`) en texto e
   icono, y `dropdownColor: Colors.white` con texto `AppTheme.textPrimary` **dentro** del
   desplegable (que es donde sí contrasta).
2. AppBar de `GestionScreen` (`:48-71`): degradado de marca (`primaryDark → primary`) con
   `flexibleSpace`, `titleTextStyle` blanco w800 con sombra suave, iconos blancos, y acciones:
   campana de notificaciones, "Nueva entidad" y "Configurar entidad". Título descriptivo
   ("Gestión") cuando hay una sola entidad.
3. `app_theme.dart:37-42`: añadir `titleTextStyle` compartido (blanco, w700, 18) para que las 15
   AppBars admin hereden contraste.
4. Espejo en `vendedor_screen.dart:1149-1156`.
5. Test puro de contraste: calcular la razón WCAG de `blanco sobre #405F90` y de los pares usados
   por el AppBar y exigir ≥ 4.5.

**Criterio:** `test/appbar_contraste_test.dart` pasa; ningún `textPrimary`/`textSecondary` se pinta
sobre el fondo primario del AppBar; el desplegable de entidades es legible con 2+ entidades.

### F6 — Datos adicionales y reglas de precio integradas con los turnos
**SQL (nuevo):** `docs/flow_schema/migraciones/51_precio_turno_con_reglas.sql` (§3.2).
**Dart:** `lib/models/config_precio.dart`, `lib/utils/precio_reserva.dart`,
`lib/utils/parse_monto.dart` (nuevo), `lib/widgets/datos_adicionales_form.dart`,
`lib/widgets/totales_datos_adicionales.dart`, `lib/screens/reserva_transporte_sheet.dart`,
`lib/screens/admin/admin_reserva_transporte_sheet.dart`, `lib/screens/admin/reservas_screen.dart`,
`lib/screens/admin/gestion_servicios_screen.dart`, `lib/screens/admin/servicio_detail_screen.dart`,
`test/precio_reglas_test.dart` (nuevo), `test/parse_monto_test.dart` (nuevo).

1. **SQL**: extraer la aritmética a `flow.calcular_precio_con_reglas(p_id_servicio, p_datos,
   p_moneda, p_cantidad, p_base_unit)` y hacer que `calcular_precio_reserva` (base del servicio) y
   `calcular_precio_turno` (base del turno + reglas) la compartan. Se mantienen las firmas y las
   3 columnas de retorno de las funciones públicas para no romper `cotizar_reserva`.
2. **Dart `PrecioReserva.calcular`**: nuevo parámetro `double? baseUnitario` (precio del turno).
   Orden: base = `baseUnitario ?? preciosBase[moneda]`; primera regla coincidente **con precio
   resoluble** reemplaza; si ninguna, base; nunca `0` por falta de moneda en la regla. `origen`
   gana el valor `'turno'`.
3. **`ConfigPrecio`**: aceptar `num` **o** string numérico en `preciosBase` y `preciosOpcion`
   (`config_precio.dart:64,123`).
4. **Llamadas con turno**: `reserva_transporte_sheet.dart:156-165` y
   `admin_reserva_transporte_sheet.dart:155-164` dejan de sobrescribir el total a mano y pasan
   `baseUnitario` a `calcular`. `reservas_screen.dart:1963-1972` hace lo mismo para que el
   "Precio recalculado" coincida con lo que se cobra.
5. **`datos_adicionales_form.dart`**: tras aplicar los defaults en `initState` (`:41-64`) llamar a
   `_notifyChange()` para que el precio se cotice desde el primer render (hoy una regla ligada a
   un campo con default no se aplica hasta que el usuario toca algo).
6. **`parse_monto.dart`** + uso en `gestion_servicios_screen.dart:449,468`:
   `1.500 → 1500`, `1,50 → 1.5`, `1.500,50 → 1500.5`, `1500 → 1500`, `18.5 → 18.5`.
7. **`TotalesPanel`**: llamar a `calcularTotales(...)` (hoy muerto, `totales_datos_adicionales.dart:14-102`)
   para mostrar el desglose de los campos con `contabilizar = true`, que es lo que el admin
   configura como "Totalizar en reportes" (`gestion_servicios_screen.dart:1824`).
8. **Transparencia (D6)**: en la sección "Reglas de precio por dato adicional"
   (`gestion_servicios_screen.dart:1004-1030`) añadir la nota "Si dos reglas coinciden, se aplica
   la primera". En `servicio_detail_screen.dart` mostrar la regla resultante por moneda.

**Criterio:** turno con precio propio + regla por dato adicional → se cobra el precio del turno,
salvo que la regla case, y entonces el de la regla (antes: siempre el del turno). Regla sin precio
en la moneda elegida → base, nunca 0. Tests nuevos en verde y `precio_base_test.dart` existente intacto.

### F7 — Tutorial guiado: núcleo (nuevo, sin dependencias)
**Ficheros nuevos:** `lib/tutorial/tutorial_paso.dart`, `lib/tutorial/tutorial_registry.dart`,
`lib/tutorial/tutorial_anchor.dart`, `lib/tutorial/tutorial_controller.dart`,
`lib/tutorial/tutorial_overlay.dart`, `lib/tutorial/tutorial_flujos.dart`,
`lib/services/tutorial_service.dart`, `test/tutorial_service_test.dart` (nuevo),
`test/tutorial_controller_test.dart` (nuevo).
**Modificado:** `lib/main.dart` (montar el host).

1. `TutorialPaso`: `id` (id del ancla), `titulo`, `mensaje`, `accion` (`String?`: texto del botón
   principal), `preferencia` (arriba/abajo), `opcional` (bool).
2. `TutorialRegistry` (singleton): registra `GlobalKey` por `id`, expone `Rect? rectDe(id)` y un
   `ValueNotifier` de cambios para reposicionar el overlay.
3. `TutorialAnchor`: envuelve un widget, registra su `GlobalKey` al montar y la libera al
   desmontar. No altera el layout (`SizedBox.shrink` de relleno si hace falta).
4. `TutorialController` (`ChangeNotifier`): `pasos`, `indice`, `activo`, `flujoId`;
   `iniciar`, `siguiente`, `anterior`, `omitir`, `terminar`, y `onAnclaDisponible(id)` que avanza
   automáticamente si el ancla es la del paso siguiente (habilita el tutorial multi-pantalla).
5. `TutorialOverlay`: se monta con `MaterialApp.builder` (`Stack` sobre el `Navigator`), de modo
   que queda por encima también de los `showModalBottomSheet`:
   - oscurecido con **4 rectángulos** alrededor del hueco → el widget resaltado recibe el toque real;
   - anillo con halo animado (fade + escala) alrededor del hueco, `IgnorePointer`;
   - burbuja con el estilo de `PistaBusquedaAvanzada` (blanco, `elevation: 6`, radio 16, flecha,
     X de 44×44), `Paso N de M` con puntos de progreso, botones `Saltar` y `Siguiente`/`Entendido`;
   - animación de entrada/salida del hueco (200-250 ms, `CurvedAnimation`), respetando
     `MediaQuery.disableAnimations`.
   - Ajuste de posición con `MediaQuery.viewInsets` para no tapar teclados.
6. `tutorial_service.dart` (D7): `debeMostrarCliente(uuid)`, `marcarVistoCliente(uuid)`,
   `omitirCliente(uuid)`, `reiniciarCliente(uuid)` y las equivalentes por entidad
   (`debeMostrarAdmin(uuid, idEntidad)`, …). Lee/escribe `SharedPreferences` con las claves de D7.
7. Anclas y pasos en `tutorial_flujos.dart`: `pasosCliente()` y `pasosAdmin(idEntidad)` (F8/F9).

**Criterio:** test del controller (avance, retroceso, omitir, avance por ancla) y del service
(claves y valores) en verde; el overlay no intercepta toques fuera del hueco cuando está inactivo.

### F8 — Tutorial del cliente (reservar / anotarse en la lista)
**Modificados:** `lib/screens/home_client_screen.dart`, `lib/screens/catalogo_screen.dart`,
`lib/screens/local_servicio_detail_screen.dart`, `lib/screens/home_shell.dart`,
`lib/screens/perfil_screen.dart`.

Pasos (multi-pantalla, avance por ancla):
1. `home_buscar` — buscador del Home: "Busca el servicio que quieras reservar".
2. `home_ver_todo` — "Ver todo" de servicios: "Aquí está el catálogo completo".
3. `catalogo_tarjeta` — primera tarjeta del catálogo: "Toca un servicio para ver sus turnos".
4. `detalle_acciones` — barra inferior ("Reservar ahora" / "Anotarme en la lista"):
   "Reserva un turno libre o anótate en la lista si no hay cupo".
5. `detalle_calendario` — calendario: "Elige el día; el número son los turnos libres.
   Puedes cambiar de mes y anotarte en cualquier fecha futura".
6. `detalle_datos` — formulario de datos adicionales + total: "Si el local pide datos extra, los
   rellenas aquí". **Opcional**: el formulario solo se construye si el servicio tiene campos
   adicionales, así que en muchos servicios no hay nada que resaltar.
7. `detalle_continuar` — "Continuar" / confirmación: "Y listo: tu reserva queda guardada".

Disparo: en `HomeShell`, la primera vez que un cliente (no admin, no vendedor) entra en `/home`
si `debeMostrarCliente(uuid)`. Entrada "Ver el tutorial otra vez" en la tarjeta "CUENTA" de
`PerfilScreen` (solo cliente): el tile llama al callback `onRepetirTutorial` que inyecta
`HomeShell` (`_repetirTutorialCliente`), porque el recorrido empieza en la pestaña Home y es el
shell quien puede cambiarla antes de relanzar el tutorial.

**Criterio:** el tutorial recorre los 7 pasos, se puede saltar en cualquier momento, y tras
completarlo u omitirlo no vuelve a aparecer en el siguiente arranque. El botón de repetir lo
relanza.

### F9 — Tutorial del admin (publicar el primer negocio completo)
**Modificados:** `lib/screens/admin/gestion_screen.dart`, `gestion_locales_screen.dart`,
`gestion_servicios_screen.dart`, `planificacion_screen.dart`, `config_recursos_screen.dart`,
`config_plan_mensual_screen.dart`, `config_categorias_screen.dart`, `reservas_screen.dart`.
(`crear_planificacion_screen.dart` finalmente **no** se toca: el switch "Reserva directa" no está
ahí sino en la tarjeta de cada servicio vinculado de `planificacion_screen.dart`.)

Bloque obligatorio:
1. `admin_selector_entidad` — selector de entidad: "Esta es tu entidad; todo se configura aquí".
2. `admin_modulo_locales` — tarjeta "Locales": "Empieza creando el local".
3. `admin_nuevo_local` — FAB "Nuevo Local": nombre, dirección, teléfono, coordenadas, horario
   por días y apertura/cierre, y el switch "Disponible para clientes".
4. `admin_modulo_servicios` — tarjeta "Servicios": "Ahora el servicio que se reserva".
5. `admin_nuevo_servicio` — botón "Nuevo Servicio".
6. `admin_precio` — monedas habilitadas, moneda por defecto y precio base.
7. `admin_datos_adicionales` — campos adicionales (texto, número, select, booleano), requerido,
   mínimo/máximo, valor por defecto, "Totalizar en reportes" y reglas de default.
8. `admin_reglas_precio` — reglas de precio por dato adicional (con la nota de D6).
9. `admin_guardar_servicio` — guardar y explicar qué ve el cliente.
10. `admin_modulo_planificacion` — tarjeta "Planificación": "Vincula el servicio a un local".
11. `admin_vincular` — botón "Vincular servicio a local".
12. `admin_reserva_directa` — **opcional**: el switch "Reserva directa" vive dentro de la tarjeta
    plegable de cada servicio vinculado, así que su ancla no existe hasta que hay una vinculación y
    se despliega. El paso se explica igual y se puede avanzar sin ir a buscarlo.
13. `admin_recursos_turnos` — "Recursos y turnos": recursos, tramos, turnos (nombre, horario,
    precio propio, activo) y los modos de gestión.
14. `admin_config_mensual` — "Configuración mensual": capacidad por defecto, mes y "Generar
    planes del mes" (el paso que publica el turno en el calendario).
Opcionales (bloque final, saltable):
15. `admin_capacidades` — "Capacidades por reserva".
16. `admin_reservas` — tarjeta "Reservas" del dashboard: confirmar consumo, cancelar, filtrar.
17. `admin_categorias` — categorías y subcategorías.

Disparo: en `GestionScreen`, cuando `entidadProvider.isAdmin == true` y
`!debeMostrarAdmin(uuid, entidadSeleccionada.id)`. Al crear una entidad nueva, la clave por
`idEntidad` hace que el tutorial se muestre también para esa entidad (D7). Botón de repetir en
`EntidadDetailScreen` y en `PerfilScreen`.

**Criterio:** el tutorial del admin guía el camino completo (entidad → local → servicio con
precio y datos adicionales → vinculación → turno/recurso → generación del mes), incluye los
opcionales, y no vuelve a mostrarse una vez visto u omitido, por usuario **y** entidad.

### F10 — Verificación final
- `dart analyze` sobre `lib/` y `test/`: sin errores (los avisos preexistentes de `print`,
  `withOpacity` y deprecaciones pueden seguir).
- `flutter test`: todos en verde (baseline F0 + los nuevos).
- Revisión del diff completo por el Lead, incluyendo que el SQL no se aplicó solo.
- Entrega al usuario de la lista de SQL a ejecutar (§3) y de los pasos manuales de verificación.

---

## 3. SQL a aplicar (lo ejecuta el usuario en Supabase → SQL Editor)

> Los ficheros de `docs/flow_schema/*.sql` del repo **no** son la fuente de verdad de la BD viva.
> Antes de aplicar, comprobar la definición viva de `flow.calcular_precio_reserva` y
> `flow.calcular_precio_turno` (por si tienen cambios no reflejados en el repo).

### 3.1 `50_agenda_sala_espera_turno_on_delete.sql`
```sql
-- Eliminar un turno ya no puede fallar por FK.
-- agenda: la reserva se conserva, solo pierde el vínculo al turno (historial intacto).
alter table flow.agenda drop constraint if exists agenda_id_turno_fkey;
alter table flow.agenda
  add constraint agenda_id_turno_fkey
  foreign key (id_turno) references flow.turno(id) on delete set null;

-- sala_espera: no puede quedar a NULL porque el bot interpreta NULL como "cualquier turno".
alter table flow.sala_espera drop constraint if exists sala_espera_id_turno_fkey;
alter table flow.sala_espera
  add constraint sala_espera_id_turno_fkey
  foreign key (id_turno) references flow.turno(id) on delete cascade;

-- turno_tramo ya cascadeaba desde la migración 16; se reafirma por idempotencia.
alter table flow.turno_tramo drop constraint if exists turno_tramo_id_turno_fkey;
alter table flow.turno_tramo
  add constraint turno_tramo_id_turno_fkey
  foreign key (id_turno) references flow.turno(id) on delete cascade;
```

### 3.2 `51_precio_turno_con_reglas.sql`
Añade `flow.calcular_precio_con_reglas(...)` y reescribe `calcular_precio_reserva` y
`calcular_precio_turno` para que compartan la aritmética y para que el precio del turno actúe
como **base** (con las reglas por dato adicional aplicándose encima). Mantiene las firmas y las
3 columnas de retorno de las funciones públicas.

---

## 4. Tests nuevos

| Test | Qué cubre |
|------|-----------|
| `test/notificacion_orden_test.dart` | orden por fecha desc con empate de `created_at` (desempate por `id`), etiquetas `Hoy`/`Ayer`/fecha |
| `test/rango_calendario_test.dart` | horizonte de 12/6 meses, anclaje al mes actual, listas vacías, un solo día |
| `test/reserva_cancelacion_test.dart` | solo `Reservado` + futura + plazo de horas; cancelada/completada/pasada → no |
| `test/appbar_contraste_test.dart` | razón WCAG ≥ 4.5 para los pares del AppBar admin |
| `test/precio_reglas_test.dart` | base del turno + regla que reemplaza; regla sin moneda → base (no 0); precios string; `origen` |
| `test/parse_monto_test.dart` | `1.500`, `1,50`, `1.500,50`, `1500`, `18.5`, basura |
| `test/tutorial_service_test.dart` | claves por usuario/entidad, visto/omitido/reiniciar |
| `test/tutorial_controller_test.dart` | avance, retroceso, omitir, avance por ancla disponible |

Se conservan los 26 ficheros de test existentes (en particular `precio_base_test.dart`,
`turnos_servicio_test.dart`, `dropdown_sin_solape_test.dart` y `filtros_servicios_sheet_test.dart`).

---

## 5. Riesgos y notas

1. **SQL aplicado a mano**: F4 y F6 no se pueden probar end-to-end sin ejecutar las migraciones
   en Supabase. Todo el Dart se desarrolla y se testea de forma que no dependa de ello, y la UI
   degrada con mensaje si el RPC falla.
2. **`calcular_precio_reserva` es compartida** por `cotizar_reserva`,
   `admin_actualizar_datos_reserva` y las reservas de transporte: cualquier error de aritmética
   afecta a todas. Por eso el cambio se aísla en un helper y los tests Dart replican los casos.
3. **`SET NULL` en `agenda.id_turno`** deja reservas históricas sin turno. Es deliberado (no se
   pierden reservas ni reseñas).
4. **Cambio de precio del turno con reglas**: a partir de la migración 51 un turno con precio
   fijo puede cobrar un importe distinto si el cliente elige una opción con regla. Es el
   comportamiento pedido, pero cambia importes reales: conviene revisar los servicios en uso.
5. **Tutorial multi-pantalla** depende de que las anclas se registren. Reglas de degradación:
   si el elemento de un paso no está a la vista, la burbuja lo dice y el usuario puede avanzar con
   "Siguiente" o cerrar con "Saltar"; y el avance automático **solo** se produce desde un paso que
   el usuario llegó a ver, de modo que un paso cuyo elemento aún no existe se espera en lugar de
   saltarse (probado en `tutorial_overlay_test.dart`).
6. **Coste del tutorial**: mientras está activo, el overlay corre un latido por frame (reposiciona
   el hueco y reevalúa el avance) además del pulso. Son unos segundos, una sola vez, y con
   `MediaQuery.disableAnimations` el anillo se detiene; el latido se apaga al cerrar el tutorial.
7. **`desktop/web`**: `flutter_native_splash` y las notificaciones locales son no-op en Web;
   el overlay del tutorial usa APIs comunes, sin cambios por plataforma.

---

## 6. Checklist "nada por fuera"

- [x] F0 baseline de analyze/test anotado.
- [x] F1 orden por fecha + agrupación por día + campana en admin.
- [x] F2 calendario con horizonte ampliado (anotarse fuera del mes).
- [x] F3 cliente cancela su reserva (con reglas de estado y fecha).
- [x] F4 migración 50 + mensajes/confirmación de borrado de turno.
- [x] F5 AppBar del dashboard con contraste + test WCAG.
- [x] F6 migración 51 + precio del turno con reglas + parseo de montos + totales + transparencia UI.
- [x] F7 núcleo del tutorial (overlay, registry, anchors, controller, service).
- [x] F8 tutorial del cliente (7 pasos) + repetir.
- [x] F9 tutorial del admin (17 pasos, con opcionales) + repetir por entidad.
- [x] F10 analyze limpio, tests en verde, diff revisado, SQL listado para el usuario.

Pendiente **fuera del código**, y comprobado contra la base real el 15-10-2026 (§9):
la **50 ya está aplicada** (la FK de `agenda` ya es `ON DELETE SET NULL`). Quedan por
aplicar a mano en el SQL Editor **la 51 y la 52, en este orden**, en el proyecto de
release `vsieeihstajlrdvpuooh`:

- `docs/flow_schema/migraciones/51_precio_turno_con_reglas.sql`
- `docs/flow_schema/migraciones/52_turno_auto_en_recurso_elegido.sql`

Y en el proyecto de debug `qhprswhhfasrikhawjoz` (el que usa `flutter run`) **faltan las
40–52**: hay que aplicar la cola desde la 40 en orden, o ninguna prueba en debug reflejará
estos arreglos. (Ver §3.1/§3.2, §8 y el aviso de D9.)

---

## 8. Segundo bloque de peticiones (posteriores a la entrega)

Llegaron dos peticiones nuevas después de cerrar F0–F10. Se resuelven aquí y se añaden a
la verificación global (analyze + suite) del §6.

### F11 · Orden del listado de reservas del cliente

- **Pedido**: primero las activas, después las canceladas y al final las completadas;
  dentro de cada grupo, por fecha, la más cercana al día de hoy.
- **Dónde**: `lib/utils/reserva_listado.dart` (junto a `puedeCancelarCliente`, misma
  fuente única de verdad, funciones puras y con `ahora` inyectable).
  - `prioridadEstadoReserva(agenda)`: 0 activa (reservado **o cualquier otro estado**),
    1 cancelada, 2 completada.
  - `ordenarReservasCliente(reservas, {ahora})`: ordena por grupo y, dentro del grupo,
    por **distancia absoluta a `ahora`** (así una reserva de hoy sale arriba aunque su
    hora ya pasó, y en las completadas manda la más reciente). Desempate: la más próxima
    en el futuro y, si coinciden, el `id` mayor. Devuelve **copia** (no muta la lista).
- **Cableado**: sólo la rama de **cliente** de `mis_tickets_screen.dart` sustituye el
  `sort` por fecha ascendente. El listado del **staff/vendedor** está filtrado por día,
  donde "cercanía a ahora" no es el orden útil: se deja como lo devuelve el servidor.
- **Tests**: `test/reserva_orden_cliente_test.dart` (10) — grupos, cercanía en activas y
  en completadas, activa de hoy ya pasada, mezcla completa, desempate por `id`, no
  mutación y casos vacío/unitario.

### F12 · El turno nuevo caía siempre en el mismo recurso

- **Pedido**: "cuando tengo más de un recurso, me añade siempre los turnos al mismo
  recurso, no importa cuál seleccione".
- **Causa raíz** (SQL, `admin_guardar_turno_auto` de la migración 41): al **crear** un
  turno resolvía el recurso con
  `select ... order by r.orden, r.id limit 1` → **siempre el primero** del
  local_servicio. En el modo "no uso tramos" los recursos siguen visibles y cada tarjeta
  tiene su botón "Agregar turno" (`_editarTurno(r)`), pero ese botón no llegaba al SQL:
  el formulario llamaba a la RPC "auto" sin decir a qué recurso iba. En modo avanzado
  (con tramos) no pasaba, porque ahí se usa `admin_guardar_turno` con `p_id_recurso`.
- **Corrección**:
  1. **Migración 52** (`52_turno_auto_en_recurso_elegido.sql`): `admin_guardar_turno_auto`
     gana `p_id_recurso` (último, default `null`). Si viene y el turno es nuevo, se usa
     ese recurso validando pertenencia al local_servicio y permiso del admin (`error`
     claro si no); si no viene, comportamiento anterior; al **editar**, manda el recurso
     del propio turno. Con comprobación previa que aborta con mensaje claro y reversión
     documentada (convenciones del §Convenciones del README del esquema).
  2. **Cliente**: `RecursoService.guardarTurnoAuto(..., idRecurso:)` manda el parámetro y
     devuelve `TurnoAutoResultado { id, idRecurso, ignoroRecursoElegido }`; la hoja de
     turno le pasa `widget.recurso?.id`.
  3. **Red de seguridad**: si la base todavía no tiene la 52, PostgREST responde
     `PGRST202`; el servicio **reintenta sin el parámetro** (comportamiento anterior, sin
     romper el alta de turnos) y marca `ignoroRecursoElegido`, con lo que la hoja avisa:
     "El turno se guardó, pero en el primer recurso del servicio: falta aplicar la
     migración 52 en Supabase…".
- **Sin test automático**: la RPC vive en Postgres y el servicio usa
  `Supabase.instance` estático, así que no es verificable con la suite. Verificado por
  analyze y revisión; **queda probar en la app tras aplicar la 52** (crear un turno en
  cada recurso y comprobar en qué recurso aparece).
- **Aplicar**: la 52 va **después** de la 50 y la 51, a mano en el SQL Editor.

---

## 9. Verificación contra la base real (15-10-2026)

### 9.1 El MCP de Supabase: token inválido (resuelto el 15-10-2026)

Las herramientas MCP respondían `server is disconnected`. Hablando directamente con el
mismo endpoint y el mismo token del perfil (`~/.dsh/profiles/desktop/cordis.patch.yml`):

```
POST https://mcp.supabase.com/mcp?project_ref=vsieeihstajlrdvpuooh&read_only=true
  con el PAT viejo -> HTTP 401  {"message":"Invalid access token"}
  con el PAT nuevo -> HTTP 200  servidor supabase 0.14.0 | protocolo 2025-06-18
```

- **No era la red ni el proyecto**: el endpoint estaba vivo y el handshake llegaba.
- **No era Cloudflare**: probados 7 user-agents (undici, node, node-fetch, curl,
  `dsh-mcp-client`, Chrome). Todos llegaban a la autenticación y recibían el 401; sólo el
  UA por defecto de `Python-urllib` recibía `403 Error 1010 browser_signature_banned`,
  que era un problema del script de sondeo, no del cliente MCP.
- **Causa**: el Personal Access Token `sbp_…` del perfil estaba revocado o vencido.
  Arreglo aplicado: PAT nuevo (sólo lectura) en la cabecera `Authorization` de la línea
  215 del perfil. Con él, `tools/list` devuelve 14 herramientas (entre ellas
  `execute_sql`) y el cliente MCP de DSH vuelve a responder. El token no se guarda en
  ningún fichero del repo.
- Nota de sandbox: `curl`/PowerShell **no** pueden salir a Internet aquí
  (`schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS`); el Python del
  runtime sí (usa su propio almacén TLS). Los scripts de sondeo quedan en `.dsh/`:
  `mcp_supabase.py` (habla el MCP: `init`, `tools`, `sql`, `rows`, con
  `SUPABASE_MCP_TOKEN` / `SUPABASE_MCP_PROJECT` para probar sin tocar el perfil),
  `probe_rpc.py` / `probe_rpc2.py` (firmas de las RPC), `comparar_defs.py` (drift de los
  cuerpos), `check_ua.py` (Cloudflare) y las consultas `sql_*.sql`.

### 9.2 Estado real de las funciones (verificado con la anon key pública)

Método: `POST /rest/v1/rpc/<fn>` con `Accept-Profile`/`Content-Profile: flow` y la anon
key que la app lleva embebida (`lib/config/supabase_config.dart`). PostgREST resuelve la
función **por el nombre de los argumentos**, así que un 404 `PGRST202` significa "esa
firma no existe". Controles: `fn_que_no_existe_xyz` → 404 y `cliente_obtener_servicios`
→ 200 con datos reales, o sea que el rol anon **sí** ve las funciones y los 404 son
concluyentes. Ninguna llamada escribe: las RPC de admin fallan en su propio chequeo de
permisos antes de tocar nada.

| Comprobación (por marcadores) | release `vsieeihstajlrdvpuooh` | debug `qhprswhhfasrikhawjoz` |
|---|---|---|
| **40** `local_servicio.sin_tramos` + `turno.hora_inicio` | aplicada | **falta** |
| **41** `admin_guardar_turno_auto` (9 args) y `admin_guardar_turno` con horas | aplicadas | **faltan** |
| **42** `cliente_obtener_servicios(p_incluir_inactivos)` | aplicada | **falta** |
| **43–49** `suscripcion_config`, `entidad_activa`, `cliente_crear_intent_suscripcion`, `admin_notificaciones_pendientes`, `validar_jerarquia_tipo_actividad`, `cliente_home_feed`, `campanas_activas` | todas aplicadas | **faltan todas** |
| **50** FK `agenda` → `agenda_id_turno_fkey` = `n` (SET NULL) | **aplicada** | **falta** (`a` = NO ACTION) |
| **51** `calcular_precio_con_reglas` | **falta** | **falta** |
| **52** `admin_guardar_turno_auto` con `p_id_recurso` | **falta** | **falta** |

O sea: **en release está aplicado todo hasta la 50 y sólo quedan pendientes la 51 y la 52**;
el proyecto de debug se quedó antes de la 40, así que le faltan las 40–52.

Conclusiones:

1. **Las premisas de las migraciones se cumplen**: las tres funciones que recrea la 51
   existen con la firma y las columnas que el fichero asume, y la firma que la 52
   reemplaza es exactamente la de 9 args que está viva en release. Además, el error
   `recurso inexistente o sin permiso` que devuelve `admin_guardar_turno` es literalmente
   el chequeo de **`_admin_puede_recurso`**, la única dependencia nueva de la 52 → ya
   existe en la base.
2. **Sin drift**: comparado el cuerpo vivo (`pg_get_functiondef`) con el del repo que
   nuestras migraciones copian, sentencia a sentencia, los tres coinciden al 100 %
   (`calcular_precio_reserva` ↔ 15, `calcular_precio_turno` ↔ 21,
   `admin_guardar_turno_auto` ↔ 41). No hay arreglos hechos a mano que la 51/52 vayan a
   revertir, que es el riesgo que avisa el README con el caso de la 39.
   (`comparar_defs.py` deja la comprobación repetible.)
3. La 51 no referencia ninguna columna posterior a la 40 (`hora_inicio`, `sin_tramos`,
   `activo` no aparecen), así que no arrastra dependencias; aun así el orden correcto
   sigue siendo 50 → 51 → 52.
4. El historial `supabase_migrations.schema_migrations` de estos proyectos es de **otra
   aplicación** (carrito/pedidos/inventario) y no registra el esquema `flow`: las
   migraciones de `flow` se aplican a mano (D9), así que la única verificación posible es
   por marcadores como los de esta tabla.
5. **El proyecto de debug está muy por detrás**: sin 40 ni 41 ni 42… Le faltan las 40–52,
   así que cualquier prueba con `flutter run` (que usa el proyecto de debug) no verá los
   arreglos. El README ya avisa: se aplican en **ambos** proyectos o el comportamiento
   diferirá entre debug y release.

### 9.3 Migraciones 51 y 52 aplicadas y verificadas

El usuario aplicó las dos a mano en release. Comprobado después contra la base:

- **Firmas**: `calcular_precio_con_reglas(integer, jsonb, text, integer, numeric)` →
  `TABLE(precio_total, moneda, precio_unit, origen)`, `stable` e `invoker`; los dos
  envoltorios conservan sus 3 columnas de siempre y ahora **delegan en el helper**
  (`llama_helper_reglas = true`); `admin_guardar_turno_auto` ya tiene
  `p_id_recurso integer DEFAULT NULL` (10 argumentos).
- **Sin drift**: el cuerpo vivo de las cuatro funciones es **idéntico sentencia a
  sentencia** al del repo (`51_...sql` y `52_...sql`), o sea que lo aplicado es
  exactamente lo versionado (lo comprueba `comparar_defs.py`).
- **Precios con datos reales**: turno 17 (USD 70, servicio 6 con `precios_base` USD 40) →
  `calcular_precio_turno` = 70 (manda el turno) y el helper sin `p_base_unit` = 40 con
  `origen = 'base'`. `calcular_precio_reserva` sigue devolviendo la base del servicio.
- **Reglas configuradas: ninguna**. Los 12 servicios de release tienen en `config_precio`
  las claves `moneda_default`, `monedas`, `precios_base` y
  `aplica_precio_ida_vuelta_todos`, pero **`reglas` no aparece en ninguno**. El formato
  que guarda la app (`_configPrecioToJson` en `gestion_servicios_screen.dart`:
  `reglas[].si_clave` + `precios_opcion[opcion][moneda]`) coincide con el que lee el
  helper, así que no hay desajuste de claves: simplemente no hay ninguna regla guardada.
  Para verlas cobrar hay que configurar una, y tener presente que el precio de la opción
  **sustituye** al precio base/turno (no se suma).
- **Proyecto de debug**: vacío (0 servicios, 0 turnos, 0 recursos) y sin las migraciones
  40–52; no se usa para datos reales.

---

## 10. El tutorial navega solo (3.er bloque de peticiones)

Antes, cada paso se quedaba esperando a que el usuario llegara por su cuenta a la
pantalla del elemento resaltado. Ahora el paso declara **dónde vive** y la app lo abre
al pulsar «Siguiente» (y también al volver con «Atrás»).

- **`TutorialDestino`** (nuevo `lib/tutorial/tutorial_destino.dart`): `home`, `catalogo`,
  `servicio`, `gestion`, `locales`, `servicios`, `serviciosFormulario`,
  `planificacion`, `reservas`, `categorias`.
- **`TutorialPaso.destino`**: cada paso declara el suyo. Al entrar en un paso, el
  controlador mira si su ancla está a la vista; si no lo está y hay destino, pide a la
  app que navegue (`_prepararPaso`, diferido a un microtask para no navegar en plena
  fase de build). Mientras dura la transición, `navegando` evita que la burbuja le pida
  al usuario la acción del paso (era un parpadeo de medio segundo); si el destino no se
  abre, una red de seguridad de 1,5 s devuelve el aviso solo.
- **Quién navega**: `_navegarTutorial` en `home_shell.dart` (pestañas del cliente y
  detalle del primer servicio, con `CatalogoScreenState.abrirPrimerServicio`) y
  `TutorialNavegacion.irAAdmin` (`lib/tutorial/tutorial_navegacion.dart`), que usan
  tanto el arranque automático del admin como «Ver el tutorial otra vez» de Gestión.
  Toda navegación parte de la raíz del shell (`popUntil`), así que ir y venir con
  «Atrás»/«Siguiente» no apila pantallas.
- **Formulario de servicios**: el destino `serviciosFormulario` abre el módulo con
  `abrirNuevoAlEntrar: true`, que lanza el alta en post-frame; los pasos de precio,
  datos adicionales, reglas y guardar ya tienen su ancla dentro del formulario.
- **Lo que sigue siendo del usuario** (a propósito): los pasos que viven en una hoja
  que solo existe al tocar el elemento resaltado (calendario y formulario de la reserva
  del cliente) no declaran destino. Ahí navega el toque real sobre el hueco —que no
  intercepta gestos— y el recorrido avanza solo al aparecer el ancla de la hoja.
- **Brillos**: el botón «Siguiente» de la burbuja lleva ahora el brillo de marca del
  resto de CTA (sombra del color primario, `blurRadius` 14), sin tocar el `elevation`
  ni ningún otro botón de la app.
- **Tests**: `test/tutorial_navegacion_pasos_test.dart` (5) + 3 en
  `tutorial_controller_test.dart` + 3 en `tutorial_flujos_test.dart`. Suite completa
  **468/468 en verde** y análisis sin errores.

---

## 7. Bitácora de ejecución

| Fecha | Fase | Resultado |
|-------|------|-----------|
| — | F0 | `analyze` sobre `lib/` + `test/`: **0 errores**, solo infos/warnings preexistentes (`print`, `withOpacity`, `value` deprecado) y 1 warning que se corrige en F3 (`_cancelar` sin referenciar en `mis_tickets_screen.dart:102`). |
| — | F7 | Núcleo del tutorial escrito: `lib/tutorial/*` (paso, registry, anchor, controller, overlay, flujos) + `lib/services/tutorial_service.dart` + `builder:` en `main.dart`. `analyze` limpio y **18/18 tests** en verde (`tutorial_controller_test.dart` + `tutorial_service_test.dart`). Corregido un bug propio: `_cerrar()` limpiaba los callbacks y `repetir()` no volvía a marcar el tutorial como visto. |
| — | F4/F6 núcleo | Migraciones **50** y **51** creadas (pendientes de aplicar por el usuario). Núcleo de precios: `baseUnitario`, regla sin moneda → base (nunca 0), precios como string, `parseMonto`, defaults que cotizan desde el primer render, `TotalesPanel` cableado. 49/49 tests del área en verde. |
| — | Nota tooling | `flutter test` vía PowerShell se cuelga en este entorno; la verificación se hace con `mcp__dart__run_tests`. |
| — | F7 (cierre) | Tests de widget del overlay escritos y en verde (6 casos: no-op sin tutorial, burbuja del paso actual, el hueco deja pasar el toque real + avance solo, cambio de pestaña, saltar, avanzar/cerrar). **4 bugs propios encontrados por esos tests y corregidos**: (1) `Tooltip` en la burbuja lanzaba aserción porque la capa vive por encima del `Navigator` → sin `Overlay`; (2) el aviso de alta/baja de anclas llegaba en fase de build y el repintado diferido se quedaba atascado (se difiere el *registro* de las anclas, no el `setState`); (3) desbordaba la fila de progreso+botones (17 pasos) → progreso en su propia línea + barra fina a partir de 8 pasos; (4) el avance se disparaba solo en la *transición* de visibilidad y el ancla destino aparecía un frame después → ahora el overlay reevalúa cada frame mientras el tutorial está activo y **solo se auto-avanza desde un paso que el usuario llegó a ver** (`_alcanzados`), que es lo que impide saltarse pasos intermedios. 24/24 en verde. |
| — | F6 consumidores | El precio del turno dejó de sobrescribir el total: entra como `baseUnitario` y las reglas se evalúan encima (hojas cliente/admin + preview de reservas del admin, que ahora resuelve el turno por `idTurno` vía `RecursoService`). `parseMonto` en el formulario de servicio; nota D6 ("si dos reglas coinciden, se aplica la primera") en las dos pantallas de reglas. **76/76 tests** del área. Helper puro movido a `lib/utils/precio_turno.dart` (estaba en una pantalla y obligaba a importar una pantalla desde otra). |
| — | F1 | `utils/notificacion_orden.dart` (orden `created_at` desc + desempate `id` desc; etiquetas Hoy/Ayer/`dd/MM/yyyy`) + servicio con doble `order` + provider ordenando en el stream y en `recargar()` + cabeceras por día en la pantalla. 10 tests nuevos en verde. Hallazgo: `SupabaseStreamBuilder.order()` **sobrescribe** el orden (solo cuenta el último), por eso el orden determinista lo impone el helper en el provider; realtime y pull-to-refresh coinciden. |
| — | F2 | `utils/rango_calendario.dart` (horizonte 12 meses en cola / 6 en reserva, sin recortar meses con datos) + `_DisponibilidadSheet` con el helper y `_focusedDay` clampeado en `initState` y `onPageChanged`, y texto de ayuda "puedes cambiar de mes". Era el bug descrito por el usuario ("hace como para cambiar y se queda"). |
| — | F3 | `utils/reserva_listado.dart#puedeCancelarCliente` (solo `estado.esReservado`, fecha futura estricta y plazo de `horasAnticipacionCancelacion`) + `mis_tickets_screen.dart` con `_puedeCancelar` delegando en el helper, SnackBars con el motivo y `onCancelar: _esVendedor ? null : _cancelar`. 8 tests nuevos; desaparece el warning `_cancelar isn't referenced`. |
| — | F5 | `AppBarTheme.titleTextStyle` (onPrimary 18/w700) + AppBar con degradado en el dashboard, campana en blanco y selector de entidad en blanco; arreglado el dropdown del vendedor que se solapaba. Test de contraste (WCAG) en verde. |
| — | F8/F9 anclas | 24 anclas del tutorial colocadas (7 cliente + 17 admin) y verificadas una a una: cada `id` tiene **exactamente un** `TutorialAnchor` y todo `TutorialPaso` tiene ancla. Entradas para repetir: perfil del cliente (vía `HomeShell._repetirTutorialCliente`, que cambia a la pestaña Home antes de arrancar) y AppBar de «Gestión» para el admin. 2 pasos pasaron a `opcional` porque su ancla puede no montarse nunca: `detalle_datos` (el formulario solo existe si el servicio tiene campos adicionales) y `admin_reserva_directa` (el interruptor vive dentro de la tarjeta plegable de una vinculación); ambos se explican igual y la burbuja dice "Extra opcional… toca Siguiente". Se añadió `test/tutorial_flujos_test.dart` (ids únicos por flujo, sin colisión entre flujos, textos no vacíos y lista explícita de pasos opcionales). |
| — | Incidencia | Un subagente corrompió `lib/screens/local_servicio_detail_screen.dart` (lo dejó en 6 líneas) con un script de reindentado de PowerShell; el fichero se restauró desde git y **el Lead volvió a aplicar F2 y las 4 anclas a mano**, revisando con `git diff` que no se perdiera nada más (comprobado que `precioBaseTurno` nunca vivió en ese fichero y que F6 no lo tocaba). Se descartó el script y el resto de la integración se hizo con ediciones dirigidas. |
| — | F10 | `analyze` de todo el proyecto: **0 errores** (solo infos/warnings preexistentes: `print`, `withOpacity`, `value` deprecado, imports muertos de HEAD). Suite completa: **447/447 tests en verde**. `pubspec.lock` sin tocar y sin dependencias nuevas (D8). SQL de 50/51 pendiente de aplicar a mano (D9). |
| — | F8/F9 disparo | Arranque del tutorial por rol en `home_shell.dart` (cliente puro → recorrido de reserva, forzando la pestaña Home; admin → recorrido de publicación, por entidad, forzando «Gestión») + persistencia por usuario (y entidad en el admin) con `visto`/`omitido` y entradas para repetir. |
| — | F11 (2º bloque) | Orden del listado de reservas del cliente: `prioridadEstadoReserva` (activa 0 < cancelada 1 < completada 2, con cualquier otro estado como activa) y `ordenarReservasCliente` (dentro de cada grupo, distancia absoluta a `ahora`: la próxima cita arriba en las activas y la más reciente en las pasadas; desempate por fecha y luego por `id` mayor; devuelve copia). Cableado sólo en la rama de cliente de `mis_tickets_screen.dart`; el panel del staff por día conserva el orden del servidor. **10 tests nuevos** (`test/reserva_orden_cliente_test.dart`). |
| — | F12 (2º bloque) | Bug "el turno nuevo cae siempre en el mismo recurso": causa raíz en `admin_guardar_turno_auto` (migración 41), que resolvía el recurso con `order by r.orden, r.id limit 1`. Corregido con `p_id_recurso` (migración **52**, con comprobación previa y reversión documentadas) + `RecursoService.guardarTurnoAuto(idRecurso:)`. Si la base no tiene la 52, el guardado **no se rompe**: se reintenta sin el parámetro y la hoja avisa de que quedó en el primer recurso. Analyze limpio y **457/457 tests** en verde. |
| — | F13 (2º bloque) | Verificación contra la base real (§9), ya con el MCP de Supabase funcionando (el PAT del perfil estaba vencido: el endpoint devolvía `401 Invalid access token`; no era Cloudflare: probados 7 user-agents). Resultado: en release estaba aplicado **todo hasta la 50** y sólo faltaban **51 y 52**; en debug faltan las **40–52**. Los cuerpos vivos de las tres funciones que la 51/52 recrean eran **idénticos** a los del repo (sin drift) y `_admin_puede_recurso` ya existía. Las migraciones de `flow` no aparecen en `supabase_migrations.schema_migrations` (se aplican a mano, D9), así que la comprobación es por marcadores. |
| — | F14 (2º bloque) | El usuario aplica la 51 y la 52 en release. Verificado con SQL (§9.3): firmas correctas, los dos envoltorios delegando en el helper, `admin_guardar_turno_auto` con 10 argumentos y **drift cero** contra el SQL del repo en las cuatro funciones. Precios reales coherentes (turno 70 vs base 40). Hallazgo: **ningún servicio tiene reglas guardadas** (la clave `reglas` no existe en ninguno de los 12 `config_precio`), aunque el formato que guarda la app coincide con el que lee el helper. El proyecto de debug está vacío y sin las 40–52. |
| — | F15 (3.er bloque) | El tutorial navega solo (§10): `TutorialDestino` + `TutorialPaso.destino`, `_prepararPaso` en el controlador (con `navegando` y red de seguridad de 1,5 s), `_navegarTutorial` en el shell, `TutorialNavegacion.irAAdmin`, `abrirPrimerServicio` en el catálogo y `abrirNuevoAlEntrar` en el módulo de servicios. Brillo de marca en el botón «Siguiente» de la burbuja. **11 tests nuevos**; suite **468/468** y análisis sin errores. |
