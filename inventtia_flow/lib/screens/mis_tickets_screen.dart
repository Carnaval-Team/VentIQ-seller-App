import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../models/cobro.dart';
import '../models/entidad.dart';
import '../models/servicio.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../providers/modo_vista_provider.dart';
import '../providers/reservas_provider.dart';
import '../services/agenda_admin_service.dart';
import '../services/agenda_service.dart';
import '../services/auth_service.dart';
import '../services/catalogo_service.dart';
import '../services/cobro_service.dart';
import '../utils/estado_pago.dart';
import '../utils/motivo_cancelacion.dart';
import '../utils/precio_reserva.dart';
import '../utils/reserva_listado.dart';
import '../utils/telefono_contacto.dart';
import '../widgets/datos_adicionales_view.dart';
import '../widgets/dialogo_motivo_cancelacion.dart';
import '../widgets/notificaciones_bell.dart';
import '../widgets/pago_adelantado_sheet.dart';

/// ¿Se le ofrece al cliente el botón de pago de esta reserva?
///
/// Es la regla única de la tarjeta, separada del widget para poder probarla sin
/// montar la pantalla ni hablar con el servidor:
///
///  * reserva cancelada o completada → nunca;
///  * con intento de pago (`pagoEstado != null`, incluido `rechazado`/`expirado`)
///    → manda el estado del intento, como antes;
///  * sin intento todavía → solo si el servidor **confirmó** que ese
///    local-servicio cobra por adelantado. Con `cobroDisponible == null` (aún sin
///    resolver, o la consulta falló) **no se ofrece**: antes que un botón que
///    lleva a un error del servidor, ninguno. El reintento es del usuario: al
///    volver a la pestaña o con pull-to-refresh se vuelve a consultar.
bool puedeOfrecerPagoAlCliente({
  required bool activa,
  required String? pagoEstado,
  required bool? cobroDisponible,
}) {
  if (!activa) return false;
  if (pagoEstado != null) {
    return EstadoPago.enCurso(pagoEstado) || EstadoPago.sePuedePagar(pagoEstado);
  }
  return cobroDisponible == true;
}

class MisTicketsScreen extends StatefulWidget {
  const MisTicketsScreen({super.key});

  @override
  State<MisTicketsScreen> createState() => MisTicketsScreenState();
}

class MisTicketsScreenState extends State<MisTicketsScreen> {
  List<Agenda> _tickets = [];
  List<Agenda> _filteredTickets = [];
  bool _isLoading = true;
  bool _filtrosExpanded = false;
  final _searchController = TextEditingController();
  bool _isSearching = false;

  DateTime _fecha = DateTime.now();
  int? _idEstadoFiltro;
  Local? _localFiltro;
  LocalServicio? _lsFiltro;
  List<Local> _locales = [];
  List<LocalServicio> _localServicios = [];
  List<EstadoAgenda> _estados = [];

  /// ¿Este local-servicio admite **pago por adelantado**?
  /// (`flow.cliente_cobro_info`, migración 62).
  ///
  /// Lo decide el servidor —servicio **y** entidad— y aquí solo se cachea por
  /// `id_local_servicio`: la tarjeta se repinta en cada gesto del listado y el RPC
  /// no es gratis. Solo se resuelven los servicios de reservas **activas y sin
  /// intento de pago**, que son las únicas que pueden llegar a ofrecer el botón.
  ///
  /// No estar en el mapa = todavía no se sabe (o la consulta falló): en ese caso
  /// el botón no se pinta. Nunca se inventa un «sí», porque el servidor rechaza
  /// el pago de un servicio que no lo tenga activado.
  final Map<int, bool> _cobroDisponible = {};

  /// Local-servicios con una consulta en vuelo: evita lanzar dos veces el mismo
  /// RPC si la lista se recarga mientras la primera sigue en el aire.
  final Set<int> _cobroConsultando = {};

  /// `true` cuando la próxima resolución debe reconsultar aunque ya haya cache.
  ///
  /// Lo encienden las recargas **explícitas** (volver a la pestaña, llegar desde
  /// un aviso, pull-to-refresh): es la forma de ver un cambio del admin sin
  /// reabrir la app. El refresco de Realtime NO lo enciende, para no lanzar el
  /// RPC en cada evento de `flow.agenda`.
  bool _cobroRevalidar = false;

  /// Suscripción **ya viva** de [ReservasProvider] que se reutiliza como fuente
  /// de tiempo real (ver [_escucharTiempoReal]).
  ReservasProvider? _reservas;

  /// `true` mientras hay una recarga silenciosa (Realtime) en vuelo.
  bool _recargaSilenciosaEnVuelo = false;

  final _fmt = DateFormat('dd/MM/yyyy');
  final _fmtDiaSemana = DateFormat('EEEE', 'es');

  bool get _esHoy {
    final now = DateTime.now();
    return _fecha.year == now.year &&
        _fecha.month == now.month &&
        _fecha.day == now.day;
  }

  bool get _hayFiltrosActivos =>
      _idEstadoFiltro != null || _localFiltro != null || _lsFiltro != null;

  Entidad? get _entidad =>
      context.read<EntidadProvider>().entidadVendedorSeleccionada;

  /// `true` cuando esta pantalla se está usando como panel de trabajo del staff.
  ///
  /// No es «el usuario es vendedor» sino «esta vista es la del staff»: un
  /// admin+vendedor que pidió ver la app como cliente está en la pestaña Reservas
  /// del cliente y aquí tiene que ver SUS reservas, no la agenda del local.
  ///
  /// Se lee con `listen: false` porque también se usa en `_load()`, fuera de
  /// build; la reactividad la aporta el `watch` de `build`.
  bool get _esVendedor {
    final comoCliente = Provider.of<ModoVistaProvider?>(
      context,
      listen: false,
    )?.comoCliente;
    return _entidad != null && comoCliente != true;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _escucharTiempoReal();
      _loadLocales();
      _load();
    });
  }

  void reload() {
    // Al volver a la pestaña (o llegar aquí desde un aviso de pago) se revalida
    // también la disponibilidad del cobro: el interruptor lo mueve el admin en
    // otro dispositivo y `flow.cobro_config` todavía no está en Realtime (es la
    // parte que queda pendiente de SQL).
    //
    // Se revalida **sin borrar** el mapa: el botón sigue con el último valor
    // conocido mientras llega la respuesta (si se vaciara, parpadearía en cada
    // entrada a la pestaña). Si el admin lo apagó, desaparece al contestar el
    // servidor; y el toque se vuelve a validar en el servidor de todas formas.
    _cobroRevalidar = true;
    _loadLocales();
    _load();
  }

  /// Pull-to-refresh: además de la lista, fuerza la relectura de la
  /// disponibilidad del cobro, que es la vía del usuario para reintentar una
  /// consulta que falló (con error de red el botón se queda oculto a propósito).
  Future<void> _refrescar() async {
    _cobroRevalidar = true;
    await _load();
  }

  /// Engancha esta lista a la suscripción de Realtime que **ya** tiene
  /// [ReservasProvider] sobre `flow.agenda` (migración 37).
  ///
  /// No se abre una segunda: el provider ya escucha la tabla por `uuid_usuario` y
  /// por `reservado_por`, agrupa las ráfagas y avisa al terminar de recargar.
  /// Aquí ese aviso solo se traduce en recargar esta lista, que es la que pinta
  /// el chip del pago. Así, cuando el admin verifica el pago, el chip pasa de
  /// «Pago pendiente» a «Pago verificado» sin reabrir la app.
  void _escucharTiempoReal() {
    if (!mounted) return;
    final reservas = context.read<ReservasProvider>();
    if (identical(reservas, _reservas)) return;
    _reservas?.removeListener(_alCambiarReservas);
    _reservas = reservas..addListener(_alCambiarReservas);
  }

  void _alCambiarReservas() {
    if (!mounted) return;
    // Sin sesión no hay nada que listar (el shell ya está yendo a login).
    if (AuthService.currentUserId == null) return;
    // Con una carga normal en marcha (entrada a la pestaña, arranque) esa misma
    // carga ya trae los datos frescos: no se lanza otra igual.
    if (_isLoading) return;
    // Una recarga silenciosa a la vez: el provider puede avisar por una ráfaga
    // de filas y no tiene sentido pisar la misma consulta.
    if (_recargaSilenciosaEnVuelo) return;
    _recargaSilenciosaEnVuelo = true;
    _load(silencioso: true).whenComplete(() {
      _recargaSilenciosaEnVuelo = false;
    });
  }

  @override
  void dispose() {
    _reservas?.removeListener(_alCambiarReservas);
    _searchController.dispose();
    super.dispose();
  }

  void _filterTickets(String query) {
    setState(() {
      _isSearching = query.isNotEmpty;
      _filteredTickets = _applySearch(_tickets, query);
    });
  }

  String _datoCliente(Agenda r, String clave) {
    final v = r.datosAdicionales?[clave];
    if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    final cli = r.cliente;
    return switch (clave) {
      'nombre' => cli?.nombre ?? '-',
      'apellidos' => cli?.apellidos ?? '-',
      'ci' => cli?.ci ?? '-',
      'telefono' => cli?.telefono ?? '-',
      _ => '-',
    };
  }

  /// Abre el pago por adelantado de una reserva del cliente.
  ///
  /// Sirve para las tres situaciones, sin que la tarjeta tenga que saber cuál es:
  ///  * ya hay un intento vivo (`pendiente`/`reportado`) → reabre su hoja;
  ///  * el anterior se rechazó o caducó → crea uno nuevo;
  ///  * no hay intento (la reserva se hizo sin pagar) → comprueba que el local
  ///    tenga el cobro activo y lo crea.
  ///
  /// Los importes y las URLs SIEMPRE los calcula el servidor: aquí no se inventa
  /// ningún precio.
  Future<void> _pagarPorAdelantado(Agenda ticket) async {
    try {
      var pago = await CobroService.pagoDeReserva(ticket.id);
      CobroInfo? info;

      // Un pago verificado (o en un estado que esta versión no conoce) no se
      // vuelve a tocar: no hay nada que ofrecer.
      if (pago != null &&
          !EstadoPago.enCurso(pago.estado) &&
          !EstadoPago.sePuedePagar(pago.estado)) {
        if (!mounted) return;
        _toast('Este pago ya no se puede modificar.', AppTheme.success);
        return;
      }

      // Solo hay que crear intento si no existe o si el anterior murió
      // (rechazado / caducado).
      if (pago == null || !EstadoPago.enCurso(pago.estado)) {
        // Antes de crear nada: ¿este local cobra por adelantado?
        info = await CobroService.infoLocalServicio(ticket.idLocalServicio);
        if (!info.disponible) {
          if (!mounted) return;
          _toast(
            'Este servicio no tiene activado el pago por adelantado.',
            AppTheme.warning,
          );
          return;
        }
        pago = await CobroService.crearPago(ticket.id);
      }

      if (!mounted) return;
      await PagoAdelantadoSheet.mostrar(
        context,
        pago: pago,
        info: info,
        // Mismo criterio que en la ficha: se muestra el local, no el número.
        nombreComercio: ticket.localServicio?.local?.nombre,
      );
      if (mounted) await _load();
    } catch (e) {
      if (!mounted) return;
      _toast(
        e.toString().replaceFirst('Exception: ', '').trim(),
        AppTheme.error,
      );
    }
  }

  void _toast(String mensaje, Color color) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(mensaje), backgroundColor: color));
  }

  Future<void> _cancelar(Agenda ticket) async {
    final uuid = AuthService.currentUserId ?? '';
    if (uuid.isEmpty) return;

    final ahora = DateTime.now();

    // Validación única antes de confirmar: estado, fecha no pasada y plazo de
    // anticipación. Si no se puede, se explica el motivo exacto al cliente.
    if (!puedeCancelarCliente(ticket, ahora: ahora)) {
      final horas = ticket.entidad?.horasAnticipacionCancelacion ?? 0;
      final motivo = switch (ticket.estado?.esReservado) {
        // Ya no está en estado Reservado (cancelada o completada).
        false => 'Esta reserva ya no se puede cancelar',
        _ when !ahora.isBefore(ticket.fechaHoraReserva) =>
          'Esta reserva ya pasó',
        _ when horas > 0 =>
          'Solo puedes cancelar hasta $horas horas antes de la reserva',
        _ => 'Esta reserva ya no se puede cancelar',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(motivo), backgroundColor: AppTheme.error),
      );
      return;
    }

    // [61] El motivo es OPCIONAL para el cliente. El diálogo sustituye al
    // «¿Estás seguro?»: es la misma confirmación, con un campo que puede
    // quedarse vacío. Se abre antes de llamar al servicio.
    final motivo = await dialogoMotivoCancelacion(
      context,
      titulo: 'Cancelar reserva',
      detalle: '¿Estás seguro de que quieres cancelar esta reserva?',
      obligatorio: false,
    );
    if (motivo == null || !mounted) return;

    try {
      await AgendaService.cancelarTicketCliente(
        uuidUsuario: uuid,
        idAgenda: ticket.id,
        motivo: motivo,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reserva cancelada'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // [61] Mensajes del servidor traducidos (antes: `e.toString()`).
          content: Text(mensajeErrorCancelacion(e)),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── Acciones de staff (solo vendedor): completar / cancelar una reserva ──
  Future<void> _completarStaff(Agenda ticket) => _cambiarEstadoStaff(
    ticket,
    3,
    titulo: 'Confirmar consumo',
    mensaje: '¿Confirmar que el cliente consumió esta reserva?',
    confirmar: 'Confirmar consumido',
    okMsg: 'Consumo confirmado',
    colorConfirmar: AppTheme.success,
  );

  /// Cancelar como staff (vendedor): [61] el motivo es **obligatorio**.
  ///
  /// El diálogo del motivo hace también de confirmación («Sí, cancelar»), así
  /// que después no se vuelve a preguntar.
  Future<void> _cancelarStaff(Agenda ticket) async {
    final motivo = await dialogoMotivoCancelacion(
      context,
      titulo: 'Cancelar reserva',
      detalle:
          '¿Cancelar esta reserva? Se liberará el turno y se notificará al cliente.',
    );
    if (motivo == null || !mounted) return;
    await _aplicarEstadoStaff(ticket, 2, 'Reserva cancelada', motivo: motivo);
  }

  Future<void> _cambiarEstadoStaff(
    Agenda ticket,
    int idEstado, {
    required String titulo,
    required String mensaje,
    required String confirmar,
    required String okMsg,
    required Color colorConfirmar,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: colorConfirmar),
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmar),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _aplicarEstadoStaff(ticket, idEstado, okMsg);
  }

  /// Aplica el cambio de estado una vez confirmado (y, al cancelar, con el
  /// motivo ya recogido).
  Future<void> _aplicarEstadoStaff(
    Agenda ticket,
    int idEstado,
    String okMsg, {
    String? motivo,
  }) async {
    try {
      await AgendaAdminService.marcarEstadoAgenda(
        idAgenda: ticket.id,
        idEstado: idEstado,
        motivo: motivo,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(okMsg), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          // [61] Mensajes del servidor traducidos (antes: `e.toString()`).
          content: Text(mensajeErrorCancelacion(e)),
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  void _irDia(int delta) {
    if (_isLoading) return;
    setState(() {
      _fecha = _fecha.add(Duration(days: delta));
      _searchController.clear();
      _isSearching = false;
    });
    _load();
  }

  Future<void> _pickFecha() async {
    if (_isLoading) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime(2024),
      lastDate: DateTime(2028),
    );
    if (picked != null) {
      setState(() {
        _fecha = DateTime(picked.year, picked.month, picked.day);
        _searchController.clear();
        _isSearching = false;
      });
      _load();
    }
  }

  void _irHoy() {
    if (_isLoading) return;
    final now = DateTime.now();
    setState(() {
      _fecha = DateTime(now.year, now.month, now.day);
      _searchController.clear();
      _isSearching = false;
    });
    _load();
  }

  void _resetFiltros() {
    if (_isLoading) return;
    setState(() {
      _idEstadoFiltro =
          null; // Todos: muestra reservadas, completadas y canceladas.
      _localFiltro = null;
      _lsFiltro = null;
      _localServicios = [];
      _filtrosExpanded = false;
    });
    _load();
  }

  Future<void> _onLocalChange(Local? local) async {
    if (_isLoading) return;
    setState(() {
      _localFiltro = local;
      _lsFiltro = null;
      _localServicios = [];
    });
    if (local != null) {
      final ls = await CatalogoService.getLocalServicios(idLocal: local.id);
      if (mounted) setState(() => _localServicios = ls);
    }
    _load();
  }

  Future<void> _loadLocales() async {
    final entidad = _entidad;
    if (entidad == null) return;
    final results = await Future.wait([
      CatalogoService.getLocalesByEntidad(entidad.id),
      AgendaService.getEstados(),
    ]);
    if (!mounted) return;
    final estados = results[1] as List<EstadoAgenda>;
    setState(() {
      _locales = results[0] as List<Local>;
      _estados = estados;
      // Por defecto "Todos": así las canceladas quedan atenuadas y las
      // completadas con borde azul, en vez de desaparecer del listado.
    });
  }

  /// Recarga la lista de reservas.
  ///
  /// [silencioso] deja en pantalla la lista que ya había mientras llega la nueva.
  /// Es lo que usa el refresco por Realtime: poner `_isLoading` a `true` apagaría
  /// toda la pantalla (spinner + `AbsorbPointer`) por un cambio que el usuario no
  /// pidió y le quitaría la posición del scroll.
  Future<void> _load({bool silencioso = false}) async {
    if (!mounted) return;
    final esVendedor = _esVendedor;
    if (!silencioso) setState(() => _isLoading = true);
    try {
      final uuid = AuthService.currentUserId ?? '';
      List<Agenda> tickets;
      if (esVendedor) {
        final entidad = _entidad!;
        final desde = DateTime(_fecha.year, _fecha.month, _fecha.day);
        final hasta = DateTime(
          _fecha.year,
          _fecha.month,
          _fecha.day,
          23,
          59,
          59,
        );
        tickets = await AgendaAdminService.listarAgendasVendedor(
          uuidUsuario: uuid,
          idEntidad: entidad.id,
          idLocal: _localFiltro?.id,
          idLocalServicio: _lsFiltro?.id,
          idEstado: _idEstadoFiltro,
          desde: desde,
          hasta: hasta,
        );
      } else {
        tickets = await AgendaService.getMisTickets(uuid);
        // Activas primero, luego canceladas y al final completadas; dentro de
        // cada grupo, la cita más cercana al día de hoy (utilidad del listado
        // del cliente, no del panel del staff por día).
        tickets = ordenarReservasCliente(tickets);
      }
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _filteredTickets = _isSearching
            ? _applySearch(tickets, _searchController.text)
            : tickets;
        _isLoading = false;
      });
      // Después de pintar: ¿alguna de estas reservas puede ofrecer pago? El
      // staff no pinta el botón, así que no se consulta nada por él.
      if (!esVendedor) await _resolverCobroDisponible(tickets);
    } catch (e) {
      print('[flow] MisTicketsScreen _load ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Resuelve si se puede ofrecer pagar en cada local-servicio de la lista.
  ///
  /// Solo pregunta por los servicios de reservas activas y **sin intento de
  /// pago**: en las demás el botón ni se plantea, así que sería una llamada de
  /// red regalada. Los resultados se guardan en [_cobroDisponible] y se
  /// reutilizan en las siguientes cargas; solo una recarga explícita
  /// ([_cobroRevalidar]) vuelve a preguntar. Ese mapa es lo único que leen las
  /// tarjetas en `build`: **ningún `build` dispara red**.
  Future<void> _resolverCobroDisponible(Iterable<Agenda> tickets) async {
    // La revalidación explícita se consume aquí: vuelve a preguntar por los
    // servicios ya cacheados y conserva el último valor en pantalla mientras
    // tanto.
    final revalidar = _cobroRevalidar;
    _cobroRevalidar = false;

    final ids = <int>{};
    for (final t in tickets) {
      if (t.pagoEstado != null) continue;
      if (t.estado?.esCancelado == true || t.idEstado == 2) continue;
      if (t.estado?.esCompletado == true || t.idEstado == 3) continue;
      if (!revalidar && _cobroDisponible.containsKey(t.idLocalServicio)) {
        continue;
      }
      if (_cobroConsultando.contains(t.idLocalServicio)) continue;
      ids.add(t.idLocalServicio);
    }
    if (ids.isEmpty) return;

    _cobroConsultando.addAll(ids);
    try {
      final respuestas = await Future.wait(
        ids.map((id) async {
          try {
            final info = await CobroService.infoLocalServicio(id);
            return MapEntry(id, info.disponible);
          } catch (e) {
            // Error de red (o migración sin aplicar): se deja SIN resolver. El
            // botón no se pinta y se reintenta en la próxima recarga o en el
            // pull-to-refresh; guardar un `false` aquí lo ocultaría para siempre.
            debugPrint('[flow] MisTicketsScreen cobro $id ERROR: $e');
            return null;
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        for (final r in respuestas) {
          if (r != null) _cobroDisponible[r.key] = r.value;
        }
      });
    } finally {
      _cobroConsultando.removeAll(ids);
    }
  }

  List<Agenda> _applySearch(List<Agenda> source, String query) {
    if (query.isEmpty) return source;
    final q = query.toLowerCase();
    return source.where((ticket) {
      final cli = ticket.cliente;
      final datos = ticket.datosAdicionales;
      if (cli != null) {
        if (cli.ci?.toLowerCase().contains(q) == true) return true;
        if (cli.nombre?.toLowerCase().contains(q) == true) return true;
        if (cli.apellidos?.toLowerCase().contains(q) == true) return true;
        if (cli.nombreCompleto.toLowerCase().contains(q)) return true;
      }
      if (datos != null) {
        if (datos['ci']?.toString().toLowerCase().contains(q) == true)
          return true;
        if (datos['nombre']?.toString().toLowerCase().contains(q) == true)
          return true;
        if (datos['apellidos']?.toString().toLowerCase().contains(q) == true)
          return true;
      }
      return false;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Registrar la dependencia del modo: los hijos del `IndexedStack` del shell
    // son instancias fijas (se crean una vez), así que el repintado al cambiar de
    // vista tiene que venir de esta dependencia y no del padre.
    context.watch<ModoVistaProvider?>();

    return AbsorbPointer(
      absorbing: _isLoading,
      child: Scaffold(
        backgroundColor: AppTheme.surface,
        body: Column(
          children: [
            _buildHero(),
            if (_esVendedor) _buildBarraFecha(),
            if (_esVendedor) _buildFiltrosColapsables(),
            _buildSearchBar(),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragEnd: (details) {
                  if (_isLoading || !_esVendedor) return;
                  final v = details.primaryVelocity ?? 0;
                  if (v < -200) _irDia(1);
                  if (v > 200) _irDia(-1);
                },
                child: _isLoading
                    ? _buildLoading()
                    : _filteredTickets.isEmpty
                    ? _isSearching
                          ? _buildNoResultsState()
                          : _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _refrescar,
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _filteredTickets.length,
                          itemBuilder: (_, i) => _TicketCard(
                            ticket: _filteredTickets[i],
                            miUuid: context.read<AuthProvider>().user?.id ?? '',
                            onCancelar: _esVendedor ? null : _cancelar,
                            esVendedor: _esVendedor,
                            onPagar: _esVendedor ? null : _pagarPorAdelantado,
                            // `null` = todavía no se sabe si este local-servicio
                            // cobra por adelantado; la tarjeta no pinta el botón.
                            pagoDisponible: _esVendedor
                                ? null
                                : _cobroDisponible[_filteredTickets[i]
                                      .idLocalServicio],
                            onCompletarStaff: _esVendedor
                                ? _completarStaff
                                : null,
                            onCancelarStaff: _esVendedor
                                ? _cancelarStaff
                                : null,
                          ),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBarraFecha() {
    final diaSemana = _fmtDiaSemana.format(_fecha);
    final diaCapitalizado = diaSemana[0].toUpperCase() + diaSemana.substring(1);
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Día anterior',
            onPressed: _isLoading ? null : () => _irDia(-1),
            color: AppTheme.primary,
          ),
          Expanded(
            child: InkWell(
              onTap: _pickFecha,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Column(
                  children: [
                    Text(
                      _fmt.format(_fecha),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: _isLoading
                            ? AppTheme.textSecondary
                            : AppTheme.textPrimary,
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          diaCapitalizado,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                        if (_esHoy) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'Hoy',
                              style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Día siguiente',
            onPressed: _isLoading ? null : () => _irDia(1),
            color: AppTheme.primary,
          ),
          if (!_esHoy)
            TextButton(
              onPressed: _isLoading ? null : _irHoy,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: const Text(
                'Hoy',
                style: TextStyle(fontSize: 12, color: AppTheme.primary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFiltrosColapsables() {
    return Container(
      color: Colors.white,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: _isLoading
                ? null
                : () => setState(() => _filtrosExpanded = !_filtrosExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_list,
                    size: 16,
                    color: _hayFiltrosActivos
                        ? AppTheme.primary
                        : AppTheme.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      () {
                        final parts = [
                          if (_localFiltro != null) _localFiltro!.nombre,
                          if (_lsFiltro != null)
                            _lsFiltro!.servicio?.nombre ?? '',
                          if (_idEstadoFiltro != null)
                            _estados
                                .firstWhere(
                                  (e) => e.id == _idEstadoFiltro,
                                  orElse: () => EstadoAgenda(id: 0, nombre: ''),
                                )
                                .nombre,
                        ].where((s) => s.isNotEmpty).join(' · ');
                        return parts.isNotEmpty ? parts : 'Filtros';
                      }(),
                      style: TextStyle(
                        fontSize: 12,
                        color: _hayFiltrosActivos
                            ? AppTheme.primary
                            : AppTheme.textSecondary,
                        fontWeight: _hayFiltrosActivos
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (_filteredTickets.isNotEmpty)
                    Text(
                      '${_filteredTickets.length} reserva${_filteredTickets.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  const SizedBox(width: 6),
                  if (_hayFiltrosActivos)
                    GestureDetector(
                      onTap: _isLoading ? null : _resetFiltros,
                      child: const Icon(
                        Icons.clear,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                    )
                  else
                    Icon(
                      _filtrosExpanded ? Icons.expand_less : Icons.expand_more,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                ],
              ),
            ),
          ),
          if (_filtrosExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<Local?>(
                          initialValue: _localFiltro,
                          isExpanded: true,
                          // Sin `contentPadding`/`isDense`: se toman del tema
                          // (`vertical: 14`). Con 8 px la etiqueta "Local" se
                          // dibujaba encima del valor (punto 2 del plan).
                          decoration: const InputDecoration(labelText: 'Local'),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Todos'),
                            ),
                            ..._locales.map(
                              (l) => DropdownMenuItem(
                                value: l,
                                child: Text(
                                  l.nombre,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _isLoading ? null : _onLocalChange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<LocalServicio?>(
                          initialValue: _lsFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Servicio',
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Todos'),
                            ),
                            ..._localServicios.map(
                              (ls) => DropdownMenuItem(
                                value: ls,
                                child: Text(
                                  ls.servicio?.nombre ?? '',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                          onChanged: _isLoading
                              ? null
                              : (v) {
                                  setState(() {
                                    _lsFiltro = v;
                                    _filtrosExpanded = false;
                                  });
                                  _load();
                                },
                        ),
                      ),
                    ],
                  ),
                  if (_estados.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _FiltroChip(
                          label: 'Todos',
                          selected: _idEstadoFiltro == null,
                          onTap: () {
                            setState(() {
                              _idEstadoFiltro = null;
                              _filtrosExpanded = false;
                            });
                            _load();
                          },
                        ),
                        ..._estados.map(
                          (e) => _FiltroChip(
                            label:
                                e.nombre[0].toUpperCase() +
                                e.nombre.substring(1),
                            selected: _idEstadoFiltro == e.id,
                            onTap: () {
                              setState(() {
                                _idEstadoFiltro = e.id;
                                _filtrosExpanded = false;
                              });
                              _load();
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Cabecera "hero" alineada con el catálogo y Mis Listas.
  Widget _buildHero() {
    final n = _tickets.length;
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.primaryDark, AppTheme.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Color(0x33405F90),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TUS TURNOS',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Mis Reservas',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _isLoading
                          ? 'Cargando tus reservas...'
                          : n == 0
                          ? 'No tienes reservas activas'
                          : n == 1
                          ? 'Tienes 1 reserva activa'
                          : 'Tienes $n reservas activas',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  _HeroIconButton(onTap: _load),
                  const SizedBox(width: 4),
                  const NotificacionesBell(color: Colors.white),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppTheme.primary),
          SizedBox(height: 16),
          Text(
            'Cargando tus reservas...',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return SizedBox.expand(
      child: RefreshIndicator(
        onRefresh: _load,
        color: AppTheme.primary,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.12),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primary.withValues(alpha: 0.10),
                          AppTheme.accent.withValues(alpha: 0.10),
                        ],
                      ),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.confirmation_number_rounded,
                      size: 46,
                      color: AppTheme.primary.withValues(alpha: 0.55),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'No hay reservas',
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _esVendedor
                        ? 'Desliza para cambiar de día'
                        : 'Tus turnos reservados aparecerán aquí',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Botón circular translúcido para acciones dentro del hero.
class _HeroIconButton extends StatelessWidget {
  final VoidCallback onTap;
  const _HeroIconButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.16),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(8),
          child: Icon(Icons.refresh, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  final Agenda ticket;
  final String miUuid;
  final ValueChanged<Agenda>? onCancelar;
  final bool esVendedor;
  final ValueChanged<Agenda>? onCompletarStaff;
  final ValueChanged<Agenda>? onCancelarStaff;

  /// Pago por adelantado (migración 62): abrir/gestionar el pago de esta
  /// reserva. Null = no se ofrece (staff).
  final ValueChanged<Agenda>? onPagar;

  /// Disponibilidad del pago resuelta por el servidor para el local-servicio de
  /// esta reserva: `true` si lo tiene activo, `false` si no, `null` si todavía no
  /// se sabe (o la consulta falló). Solo decide cuando la reserva aún no tiene
  /// intento de pago; ver [puedeOfrecerPagoAlCliente].
  final bool? pagoDisponible;

  const _TicketCard({
    required this.ticket,
    required this.miUuid,
    this.onCancelar,
    this.esVendedor = false,
    this.onCompletarStaff,
    this.onCancelarStaff,
    this.onPagar,
    this.pagoDisponible,
  });

  bool get _esCompletada =>
      ticket.estado?.esCompletado == true || ticket.idEstado == 3;
  bool get _esCancelada =>
      ticket.estado?.esCancelado == true || ticket.idEstado == 2;
  bool get _esActiva => !_esCompletada && !_esCancelada;

  Color get _estadoColor {
    switch (ticket.estado?.nombre) {
      case 'reservado':
        return AppTheme.primary;
      case 'completado':
        return AppTheme.success;
      case 'cancelado':
        return AppTheme.error;
      default:
        return AppTheme.textSecondary;
    }
  }

  // Una sola fuente de verdad (estado Reservado + reserva futura + plazo de
  // anticipación de la entidad), compartida con la validación de `_cancelar`.
  bool get _puedeCancelar => puedeCancelarCliente(ticket);

  /// Texto del chip de pago («Pago pendiente · 1500 CUP»), o `null` si esta
  /// reserva no pide pago por adelantado.
  String? get _textoPago {
    final etiqueta = EstadoPago.etiqueta(ticket.pagoEstado);
    if (etiqueta == null) return null;
    final monto = ticket.pagoMonto;
    if (monto == null || monto <= 0) return etiqueta;
    final texto = monto == monto.roundToDouble()
        ? monto.toStringAsFixed(0)
        : monto.toStringAsFixed(2);
    final moneda = ticket.pagoMoneda;
    return moneda == null ? '$etiqueta · $texto' : '$etiqueta · $texto $moneda';
  }

  /// ¿El cliente puede hacer algo con el pago?
  ///
  /// Delega en [puedeOfrecerPagoAlCliente]: con un intento ya creado manda su
  /// estado (como antes); sin intento hace falta que el servidor haya confirmado
  /// que el local-servicio cobra por adelantado. Antes bastaba `pagoEstado ==
  /// null` para pintar el botón, así que toda reserva activa lo enseñaba aunque
  /// la entidad tuviera el cobro apagado y al pulsarlo llegara el error.
  bool get _puedeAccionarPago => puedeOfrecerPagoAlCliente(
    activa: _esActiva,
    pagoEstado: ticket.pagoEstado,
    cobroDisponible: pagoDisponible,
  );

  IconData get _estadoIcon {
    switch (ticket.estado?.nombre) {
      case 'reservado':
        return Icons.schedule_rounded;
      case 'completado':
        return Icons.check_circle_rounded;
      case 'cancelado':
        return Icons.cancel_rounded;
      default:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ticket.localServicio?.local;
    final servicio = ticket.localServicio?.servicio;
    final cliente = ticket.cliente;
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    final color = _estadoColor;
    final esTercero = ticket.esParaTercero(miUuid);

    final card = Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: _esCompletada
            ? Border.all(
                color: AppTheme.primary.withValues(alpha: 0.35),
                width: 1.5,
              )
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Franja de acento vertical, teñida según el estado.
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Ícono de estado.
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(_estadoIcon, color: color, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                local?.nombre ?? 'Local',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: AppTheme.textPrimary,
                                  letterSpacing: -0.3,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (servicio != null) ...[
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.design_services_outlined,
                                      size: 12,
                                      color: AppTheme.accent,
                                    ),
                                    const SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        servicio.nombre,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppTheme.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Chip de estado.
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: color.withValues(alpha: 0.30),
                            ),
                          ),
                          child: Text(
                            ticket.estado?.nombre ?? '',
                            style: TextStyle(
                              color: color,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(height: 1, color: AppTheme.border),
                    const SizedBox(height: 12),
                    _InfoLinea(
                      icon: Icons.calendar_today_rounded,
                      texto:
                          'Reserva: ${fmt.format(ticket.fechaHoraReserva.toLocal())}',
                    ),
                    if (ticket.tipoTrayecto != null) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.directions_bus_outlined,
                        texto:
                            '${ticket.tipoTrayecto == 'ida' ? 'Ida' : 'Vuelta'}${ticket.recursoNombre == null ? '' : ' · ${ticket.recursoNombre}'}',
                        color: AppTheme.accent,
                      ),
                    ],
                    if (ticket.cantidad > 1) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.confirmation_number_outlined,
                        texto: '${ticket.cantidad} turnos reservados',
                        color: AppTheme.accent,
                      ),
                    ],
                    if (ticket.precioTotal != null &&
                        ticket.precioTotal! > 0) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.payments_outlined,
                        texto: PrecioReserva.formatear(
                          ticket.precioTotal!,
                          ticket.moneda ?? 'USD',
                        ),
                        color: AppTheme.primary,
                      ),
                    ],
                    if (esTercero) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.group_outlined,
                        texto:
                            'Para: ${cliente?.nombreCompleto.isNotEmpty == true ? cliente!.nombreCompleto : 'otra persona'}',
                        color: AppTheme.accent,
                      ),
                    ],
                    if (ticket.fechaHoraAtencion != null) ...[
                      const SizedBox(height: 6),
                      _InfoLinea(
                        icon: Icons.done_all_rounded,
                        texto:
                            'Atendido: ${fmt.format(ticket.fechaHoraAtencion!.toLocal())}',
                        color: AppTheme.success,
                      ),
                    ],
                    // [61] Motivo de la cancelación, justo bajo el chip de
                    // estado. Las canceladas antiguas no tienen motivo: en ese
                    // caso no se pinta el bloque.
                    if (_esCancelada &&
                        hayMotivoCancelacion(ticket.motivoCancelacion)) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.error.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.error.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.event_busy,
                                  size: 15,
                                  color: AppTheme.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Motivo de cancelación: '
                                    '${textoMotivoCancelacion(ticket.motivoCancelacion)}',
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      height: 1.3,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.error,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (textoCanceladoPor(ticket.canceladoPorRol)
                                .isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Padding(
                                padding: const EdgeInsets.only(left: 21),
                                child: Text(
                                  'Cancelada por: '
                                  '${textoCanceladoPor(ticket.canceladoPorRol)}',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.error,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                    ...[
                      const SizedBox(height: 12),
                      _ClienteDataSection(ticket: ticket),
                    ],
                    () {
                      const clavesFijas = {
                        'nombre',
                        'apellidos',
                        'ci',
                        'telefono',
                        'email',
                        'notas',
                      };
                      final datos = ticket.datosAdicionales;
                      if (datos == null) return const SizedBox.shrink();
                      final camposAdic = servicio?.camposAdicionales ?? [];
                      final extras = datos.entries
                          .where(
                            (e) =>
                                !clavesFijas.contains(e.key) &&
                                e.value != null &&
                                e.value.toString().trim().isNotEmpty,
                          )
                          .toList();
                      if (extras.isEmpty) return const SizedBox.shrink();
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppTheme.surface,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'INFORMACIÓN ADICIONAL',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 1,
                                    color: AppTheme.textSecondary.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                DatosAdicionalesView(
                                  valores: Map.fromEntries(extras),
                                  campos: camposAdic
                                      .where(
                                        (c) => !clavesFijas.contains(c.clave),
                                      )
                                      .toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }(),
                    // ── Pago por adelantado (migración 62) ──────────────────────────────────
                    // Chip con el estado del pago (lo ve también el staff: le
                    // sirve para saber si la reserva está cobrada) y, solo para
                    // el cliente, el botón de pagar/gestionar/reintentar.
                    if (_textoPago != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: EstadoPago.color(
                            ticket.pagoEstado,
                          ).withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: EstadoPago.color(
                              ticket.pagoEstado,
                            ).withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              EstadoPago.icono(ticket.pagoEstado),
                              size: 16,
                              color: EstadoPago.color(ticket.pagoEstado),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _textoPago!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: EstadoPago.color(ticket.pagoEstado),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (!esVendedor && onPagar != null && _puedeAccionarPago) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => onPagar!(ticket),
                          icon: Icon(
                            EstadoPago.icono(ticket.pagoEstado),
                            size: 18,
                          ),
                          label: Text(EstadoPago.etiquetaBoton(ticket.pagoEstado)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.primary,
                            side: const BorderSide(color: AppTheme.primary),
                          ),
                        ),
                      ),
                    ],
                    if (_puedeCancelar && onCancelar != null) ...[
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () => onCancelar!(ticket),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text('Cancelar reserva'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.error,
                            side: const BorderSide(color: AppTheme.error),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                    // Acciones de staff (solo vendedor) sobre reservas activas.
                    if (esVendedor && _esActiva) ...[
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: onCompletarStaff == null
                                  ? null
                                  : () => onCompletarStaff!(ticket),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 18,
                              ),
                              label: const Text('Confirmar consumido'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.success,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: onCancelarStaff == null
                                  ? null
                                  : () => onCancelarStaff!(ticket),
                              icon: const Icon(Icons.cancel_outlined, size: 18),
                              label: const Text('Cancelar'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.error,
                                side: const BorderSide(color: AppTheme.error),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    // Reservas canceladas se muestran atenuadas.
    return _esCancelada ? Opacity(opacity: 0.55, child: card) : card;
  }
}

class _ClienteDataSection extends StatelessWidget {
  final Agenda ticket;
  const _ClienteDataSection({required this.ticket});

  String _dato(String clave) {
    final v = ticket.datosAdicionales?[clave]?.toString().trim();
    if (v != null && v.isNotEmpty) return v;
    final cli = ticket.cliente;
    return switch (clave) {
      'nombre' => cli?.nombre ?? '',
      'apellidos' => cli?.apellidos ?? '',
      'ci' => cli?.ci ?? '',
      'telefono' => cli?.telefono ?? '',
      _ => '',
    };
  }

  @override
  Widget build(BuildContext context) {
    final nombre = _dato('nombre');
    final apellidos = _dato('apellidos');
    final ci = _dato('ci');
    final telefono = _dato('telefono');
    final email = _dato('email');
    final notas = _dato('notas');

    final nombreCompleto = [
      nombre,
      apellidos,
    ].where((s) => s.isNotEmpty).join(' ');

    final hayDatos =
        nombreCompleto.isNotEmpty ||
        ci.isNotEmpty ||
        telefono.isNotEmpty ||
        email.isNotEmpty ||
        notas.isNotEmpty;

    if (!hayDatos) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DATOS DEL CLIENTE',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: AppTheme.textSecondary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 8),
          if (nombreCompleto.isNotEmpty)
            _ClienteRow(Icons.person_outlined, nombreCompleto),
          if (ci.isNotEmpty) _ClienteRow(Icons.badge_outlined, 'CI: $ci'),
          if (telefono.isNotEmpty) _TelefonoRow(telefono),
          if (email.isNotEmpty) _ClienteRow(Icons.email_outlined, email),
          if (notas.isNotEmpty) _ClienteRow(Icons.notes_outlined, notas),
        ],
      ),
    );
  }
}

class _TelefonoRow extends StatelessWidget {
  final String telefono;
  const _TelefonoRow(this.telefono);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: GestureDetector(
        onTap: () => TelefonoContacto.mostrarOpciones(context, telefono),
        child: Row(
          children: [
            const Icon(Icons.phone_outlined, size: 13, color: AppTheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                telefono,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Línea de info con ícono + texto (fechas del ticket).
class _InfoLinea extends StatelessWidget {
  final IconData icon;
  final String texto;
  final Color? color;

  const _InfoLinea({required this.icon, required this.texto, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.textSecondary;
    return Row(
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            style: TextStyle(fontSize: 12, color: c),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ClienteRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ClienteRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 13, color: AppTheme.textSecondary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltroChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FiltroChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primary
              : AppTheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.primary
                : AppTheme.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.primary,
          ),
        ),
      ),
    );
  }
}

// Extension for search functionality
extension _SearchWidgets on MisTicketsScreenState {
  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: _filterTickets,
        decoration: InputDecoration(
          hintText: 'Buscar por CI, nombre o apellidos...',
          prefixIcon: const Icon(Icons.search, color: AppTheme.textSecondary),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, color: AppTheme.textSecondary),
                  onPressed: () {
                    _searchController.clear();
                    _filterTickets('');
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: AppTheme.textSecondary),
          const SizedBox(height: 16),
          Text(
            'No se encontraron resultados',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Intenta con otros términos de búsqueda',
            style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
