import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_theme.dart';
import '../models/agenda.dart';
import '../models/entidad.dart';
import '../models/servicio.dart';
import '../providers/auth_provider.dart';
import '../providers/entidad_provider.dart';
import '../services/agenda_admin_service.dart';
import '../services/agenda_service.dart';
import '../services/auth_service.dart';
import '../services/catalogo_service.dart';
import '../utils/precio_reserva.dart';
import '../utils/telefono_contacto.dart';
import '../widgets/datos_adicionales_view.dart';
import '../widgets/notificaciones_bell.dart';

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

  bool get _esVendedor => _entidad != null;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fecha = DateTime(now.year, now.month, now.day);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLocales();
      _load();
    });
  }

  void reload() {
    _loadLocales();
    _load();
  }

  @override
  void dispose() {
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

  Future<void> _cancelar(Agenda ticket) async {
    final uuid = AuthService.currentUserId ?? '';
    if (uuid.isEmpty) return;

    final entidad = ticket.entidad;
    final horas = entidad?.horasAnticipacionCancelacion ?? 0;

    // Si la entidad configuró horas de anticipación, validamos el plazo.
    // Si no hay configuración (0 o null), el cliente puede cancelar en cualquier momento.
    if (horas > 0) {
      final ahora = DateTime.now();
      final limite = ticket.fechaHoraReserva.subtract(Duration(hours: horas));
      if (ahora.isAfter(limite)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Solo puedes cancelar hasta $horas horas antes de la reserva',
            ),
            backgroundColor: AppTheme.error,
          ),
        );
        return;
      }
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Cancelar reserva'),
        content: const Text(
          '¿Estás seguro de que quieres cancelar esta reserva?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar reserva'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    try {
      await AgendaService.cancelarTicketCliente(
        uuidUsuario: uuid,
        idAgenda: ticket.id,
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
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
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

  Future<void> _cancelarStaff(Agenda ticket) => _cambiarEstadoStaff(
    ticket,
    2,
    titulo: 'Cancelar reserva',
    mensaje:
        '¿Cancelar esta reserva? Se liberará el turno y se notificará al cliente.',
    confirmar: 'Cancelar reserva',
    okMsg: 'Reserva cancelada',
    colorConfirmar: AppTheme.error,
  );

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
    try {
      await AgendaAdminService.marcarEstadoAgenda(
        idAgenda: ticket.id,
        idEstado: idEstado,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(okMsg), backgroundColor: AppTheme.success),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: AppTheme.error),
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

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final uuid = AuthService.currentUserId ?? '';
      List<Agenda> tickets;
      if (_esVendedor) {
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
        tickets.sort(
          (a, b) => a.fechaHoraReserva.compareTo(b.fechaHoraReserva),
        );
      }
      if (!mounted) return;
      setState(() {
        _tickets = tickets;
        _filteredTickets = _isSearching
            ? _applySearch(tickets, _searchController.text)
            : tickets;
        _isLoading = false;
      });
    } catch (e) {
      print('[flow] MisTicketsScreen _load ERROR: $e');
      if (mounted) setState(() => _isLoading = false);
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
                        onRefresh: _load,
                        color: AppTheme.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                          itemCount: _filteredTickets.length,
                          itemBuilder: (_, i) => _TicketCard(
                            ticket: _filteredTickets[i],
                            miUuid: context.read<AuthProvider>().user?.id ?? '',
                            onCancelar: null,
                            esVendedor: _esVendedor,
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
                          value: _localFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Local',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
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
                          value: _lsFiltro,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Servicio',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(),
                            isDense: true,
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

  const _TicketCard({
    required this.ticket,
    required this.miUuid,
    this.onCancelar,
    this.esVendedor = false,
    this.onCompletarStaff,
    this.onCancelarStaff,
  });

  bool get _esCompletada =>
      ticket.estado?.esCompletado == true || ticket.idEstado == 3;
  bool get _esCancelada =>
      ticket.estado?.nombre == 'cancelado' || ticket.idEstado == 2;
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

  bool get _puedeCancelar {
    if (ticket.estado?.nombre != 'reservado') return false;
    final horas = ticket.entidad?.horasAnticipacionCancelacion ?? 0;
    if (horas <= 0) return true;
    final limite = ticket.fechaHoraReserva.subtract(Duration(hours: horas));
    return DateTime.now().isBefore(limite);
  }

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
