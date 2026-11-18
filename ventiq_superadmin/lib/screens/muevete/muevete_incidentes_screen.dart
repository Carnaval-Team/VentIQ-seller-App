import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../config/app_colors.dart';
import '../../services/muevete_incidentes_service.dart';
import '../../utils/platform_utils.dart';
import '../../widgets/app_drawer.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Pantalla: Incidentes y Bloqueos (H2)
//
// 1) Bandeja de incidentes: filtros, detalle, resolución (fn_resolver_incidente)
//    y bloqueo del implicado (bloqueos / emparejamientos_bloqueados).
// 2) Pánico reciente: sólo lectura de eventos_panico.
// 3) Puerta de identidad: estado de configuracion_identidad y suspensión
//    temporal (fn_suspender_bloqueo_identidad). `drivers.kyc` NO se suspende.
// ═══════════════════════════════════════════════════════════════════════════

class MueveteIncidentesScreen extends StatefulWidget {
  const MueveteIncidentesScreen({super.key});

  @override
  State<MueveteIncidentesScreen> createState() =>
      _MueveteIncidentesScreenState();
}

class _MueveteIncidentesScreenState extends State<MueveteIncidentesScreen> {
  static const String _todos = '__todos__';

  // ── Incidentes ──────────────────────────────────────────────────────
  bool _cargandoIncidentes = true;
  String? _errorIncidentes;
  List<Map<String, dynamic>> _incidentes = [];
  Map<String, int> _reincidencia = {};
  Map<String, Map<String, dynamic>> _usuarios = {};
  Map<String, Map<String, dynamic>> _choferes = {};
  int _paginaIncidentes = 0;
  bool _haySiguiente = false;
  String? _filtroEstado;
  String? _filtroSeveridad;

  // ── Pánico ──────────────────────────────────────────────────────────
  bool _cargandoPanico = true;
  String? _errorPanico;
  List<Map<String, dynamic>> _panico = [];

  // ── Bloqueos recientes ──────────────────────────────────────────────
  List<Map<String, dynamic>> _bloqueos = [];

  // ── Puerta de identidad ─────────────────────────────────────────────
  bool _cargandoPuerta = true;
  String? _errorPuerta;
  Map<String, dynamic>? _config;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    await Future.wait([
      _cargarIncidentes(pagina: 0),
      _cargarPanico(),
      _cargarPuerta(),
      _cargarBloqueos(),
    ]);
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Carga
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _cargarIncidentes({int? pagina}) async {
    final destino = pagina ?? _paginaIncidentes;
    setState(() {
      _cargandoIncidentes = true;
      _errorIncidentes = null;
      _paginaIncidentes = destino;
    });
    try {
      final filas = await MueveteIncidentesService.listarIncidentes(
        estado: _filtroEstado,
        severidad: _filtroSeveridad,
        page: destino,
        filas: MueveteIncidentesService.filasPorPagina,
      );
      final haySiguiente =
          filas.length > MueveteIncidentesService.filasPorPagina;
      final visibles =
          haySiguiente
              ? filas
                  .take(MueveteIncidentesService.filasPorPagina)
                  .toList(growable: false)
              : filas;

      final reincidencia = await MueveteIncidentesService.reincidencia();
      final usuarios = await MueveteIncidentesService.usuariosPorUuid(
        visibles.expand(
          (i) => [
            '${i['reportado_por_uuid'] ?? ''}',
            '${i['contraparte_uuid'] ?? ''}',
          ],
        ),
      );
      final choferes = await MueveteIncidentesService.choferesPorId(
        visibles
            .map((i) => i['contraparte_driver_id'])
            .whereType<num>()
            .map((n) => n.toInt()),
      );

      if (!mounted) return;
      setState(() {
        _incidentes = List<Map<String, dynamic>>.from(visibles);
        _reincidencia = reincidencia;
        _usuarios = usuarios;
        _choferes = choferes;
        _haySiguiente = haySiguiente;
        _cargandoIncidentes = false;
      });
    } on MueveteSeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoIncidentes = false;
        _errorIncidentes = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoIncidentes = false;
        _errorIncidentes = 'No se pudieron cargar los incidentes: $e';
      });
    }
  }

  Future<void> _cargarPanico() async {
    setState(() {
      _cargandoPanico = true;
      _errorPanico = null;
    });
    try {
      final filas = await MueveteIncidentesService.listarEventosPanico();
      if (!mounted) return;
      setState(() {
        _panico = filas;
        _cargandoPanico = false;
      });
    } on MueveteSeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoPanico = false;
        _errorPanico = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoPanico = false;
        _errorPanico = 'No se pudieron cargar los eventos de pánico: $e';
      });
    }
  }

  Future<void> _cargarBloqueos() async {
    try {
      final filas = await MueveteIncidentesService.listarBloqueos();
      if (!mounted) return;
      setState(() => _bloqueos = filas);
    } catch (_) {
      if (!mounted) return;
      setState(() => _bloqueos = []);
    }
  }

  Future<void> _cargarPuerta() async {
    setState(() {
      _cargandoPuerta = true;
      _errorPuerta = null;
    });
    try {
      final config = await MueveteIncidentesService.configuracionIdentidad();
      if (!mounted) return;
      setState(() {
        _config = config;
        _cargandoPuerta = false;
      });
    } on MueveteSeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoPuerta = false;
        _errorPuerta = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cargandoPuerta = false;
        _errorPuerta = 'No se pudo cargar la puerta de identidad: $e';
      });
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Acciones
  // ═══════════════════════════════════════════════════════════════════════

  Future<void> _abrirDetalle(Map<String, dynamic> incidente) async {
    final cambio = await showDialog<bool>(
      context: context,
      builder:
          (_) => _IncidenteDetalleDialog(
            incidente: incidente,
            usuarios: _usuarios,
            choferes: _choferes,
            reincidencia: _reincidencia,
          ),
    );
    if (cambio == true) {
      await _cargarIncidentes();
      await _cargarBloqueos();
    }
  }

  Future<void> _suspender() async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _SuspensionDialog(),
    );
    if (datos == null) return;
    final minutos = (datos['minutos'] as num).toInt();
    final motivo = (datos['motivo'] as String?)?.trim();
    setState(() => _cargandoPuerta = true);
    try {
      await MueveteIncidentesService.suspenderPuertaIdentidad(
        minutos: minutos,
        motivo: motivo,
      );
      await _cargarPuerta();
      _avisar(
        'Puerta de identidad suspendida ${_duracion(minutos)}. '
        'drivers.kyc no se toca.',
      );
    } on MueveteSeguridadException catch (e) {
      _avisar(e.mensaje, error: true);
      await _cargarPuerta();
    } catch (e) {
      _avisar('No se pudo suspender la puerta: $e', error: true);
      await _cargarPuerta();
    }
  }

  Future<void> _reanudar() async {
    setState(() => _cargandoPuerta = true);
    try {
      await MueveteIncidentesService.reanudarPuertaIdentidad();
      await _cargarPuerta();
      _avisar('Puerta de identidad reanudada: vuelve a exigirse el perfil.');
    } on MueveteSeguridadException catch (e) {
      _avisar(e.mensaje, error: true);
      await _cargarPuerta();
    } catch (e) {
      _avisar('No se pudo reanudar la puerta: $e', error: true);
      await _cargarPuerta();
    }
  }

  Future<void> _revocarBloqueo(Map<String, dynamic> bloqueo) async {
    final motivo = await _pedirMotivo(
      titulo: 'Revocar bloqueo',
      ayuda:
          'El bloqueo deja de aplicar de inmediato. El motivo queda en la '
          'fila (revocado_por / creado_motivo).',
    );
    if (motivo == null) return;
    try {
      await MueveteIncidentesService.revocarBloqueo(
        bloqueoId: (bloqueo['id'] as num).toInt(),
        motivo: motivo,
      );
      await _cargarBloqueos();
      await _cargarIncidentes();
      _avisar('Bloqueo revocado');
    } on MueveteSeguridadException catch (e) {
      _avisar(e.mensaje, error: true);
    } catch (e) {
      _avisar('No se pudo revocar el bloqueo: $e', error: true);
    }
  }

  Future<String?> _pedirMotivo({
    required String titulo,
    required String ayuda,
  }) {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              titulo,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ayuda,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: ctrl,
                  maxLines: 3,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Motivo (mínimo 5 caracteres)',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final texto = ctrl.text.trim();
                  if (texto.length >= 5) Navigator.pop(ctx, texto);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text('Revocar'),
              ),
            ],
          ),
    );
  }

  void _avisar(String mensaje, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: error ? AppColors.error : AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final ancho = MediaQuery.of(context).size.width;
    final isDesktop = PlatformUtils.shouldUseDesktopLayout(ancho);
    final suspendida =
        MueveteIncidentesService.suspensionVigente(_config);

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        drawer: const AppDrawer(),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          surfaceTintColor: Colors.white,
          elevation: 0.5,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      suspendida ? AppColors.warning : AppColors.error,
                      (suspendida ? AppColors.warning : AppColors.error)
                          .withValues(alpha: 0.7),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.shield_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Incidentes y Bloqueos',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      _resumenCabecera(suspendida),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: 'Recargar todo',
              onPressed: _cargarTodo,
              icon: Icon(Icons.refresh_rounded, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 8),
          ],
          bottom: const TabBar(
            isScrollable: true,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            labelStyle: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            unselectedLabelStyle: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            tabs: [
              Tab(height: 44, text: 'Incidentes'),
              Tab(height: 44, text: 'Pánico reciente'),
              Tab(height: 44, text: 'Puerta de identidad'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _tabIncidentes(isDesktop),
            _tabPanico(isDesktop),
            _tabPuerta(isDesktop),
          ],
        ),
      ),
    );
  }

  String _resumenCabecera(bool suspendida) {
    if (_cargandoIncidentes) return 'Cargando bandeja…';
    final reincidentes =
        _reincidencia.values.where((v) => v >= 2).length;
    return '${_incidentes.length} en la página · '
        '$reincidentes implicado(s) reincidente(s) · puerta de identidad '
        '${suspendida ? 'SUSPENDIDA' : 'activa'}';
  }

  // ─── Tab 1: incidentes ────────────────────────────────────────────────

  Widget _tabIncidentes(bool isDesktop) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _filtrosIncidentes(),
              const SizedBox(height: 14),
              if (_cargandoIncidentes)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_errorIncidentes != null)
                SizedBox(
                  height: 260,
                  child: _EstadoError(
                    mensaje: _errorIncidentes!,
                    onReintentar: () => _cargarIncidentes(),
                  ),
                )
              else if (_incidentes.isEmpty)
                const SizedBox(
                  height: 260,
                  child: _EstadoVacio(
                    icono: Icons.shield_outlined,
                    titulo: 'Sin incidentes en este filtro',
                    mensaje:
                        'No hay incidentes reportados con los filtros '
                        'elegidos. Los reportes llegan desde las apps del '
                        'cliente y del chofer.',
                  ),
                )
              else
                _tablaIncidentes(),
              const SizedBox(height: 10),
              _paginador(),
              const SizedBox(height: 18),
              _bloqueosRecientes(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filtrosIncidentes() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 220,
            child: DropdownButtonFormField<String>(
              key: ValueKey('inc-estado-${_filtroEstado ?? 'todos'}'),
              initialValue: _filtroEstado ?? _todos,
              isExpanded: true,
              isDense: true,
              decoration: _decoracion('Estado'),
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              items: [
                const DropdownMenuItem<String>(
                  value: _todos,
                  child: Text(
                    'Todos los estados',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                ...MueveteIncidentesService.estados.map(
                  (e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(
                      MueveteIncidentesService.etiquetaEstado(e),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _filtroEstado = (v == _todos) ? null : v);
                _cargarIncidentes(pagina: 0);
              },
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              key: ValueKey('inc-sev-${_filtroSeveridad ?? 'todos'}'),
              initialValue: _filtroSeveridad ?? _todos,
              isExpanded: true,
              isDense: true,
              decoration: _decoracion('Severidad'),
              style: TextStyle(fontSize: 12, color: AppColors.textPrimary),
              items: [
                const DropdownMenuItem<String>(
                  value: _todos,
                  child: Text(
                    'Todas las severidades',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                ...MueveteIncidentesService.severidades.map(
                  (s) => DropdownMenuItem<String>(
                    value: s,
                    child: Text(
                      MueveteIncidentesService.etiquetaSeveridad(s),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
              onChanged: (v) {
                setState(() => _filtroSeveridad = (v == _todos) ? null : v);
                _cargarIncidentes(pagina: 0);
              },
            ),
          ),
          if (_filtroEstado != null || _filtroSeveridad != null)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _filtroEstado = null;
                  _filtroSeveridad = null;
                });
                _cargarIncidentes(pagina: 0);
              },
              icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
              label: const Text(
                'Limpiar filtros',
                style: TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          Text(
            'Reincidencia: ≥ 2 incidentes confirmados',
            style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _tablaIncidentes() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                _celda('ID', flex: 1, cabecera: true),
                _celda('FECHA', flex: 3, cabecera: true),
                _celda('TIPO', flex: 3, cabecera: true),
                _celda('SEVERIDAD', flex: 2, cabecera: true),
                _celda('ESTADO', flex: 2, cabecera: true),
                _celda('SOLICITUD / VIAJE', flex: 3, cabecera: true),
                _celda('IMPLICADOS', flex: 4, cabecera: true),
                _celda('', flex: 1, cabecera: true),
              ],
            ),
          ),
          ..._incidentes.map(_filaIncidente),
        ],
      ),
    );
  }

  Widget _filaIncidente(Map<String, dynamic> inc) {
    final id = (inc['id'] as num).toInt();
    final estado = '${inc['estado']}';
    final severidad = '${inc['severidad']}';
    final reporta = '${inc['reportado_por_uuid'] ?? ''}';
    final contraparteUuid = inc['contraparte_uuid'] as String?;
    final contraparteDriver = inc['contraparte_driver_id'];
    final nombreReporta = _nombreUsuario(reporta);
    final nombreContraparte = _nombreContraparte(
      contraparteUuid,
      contraparteDriver,
    );
    final reinc = _conteoReincidencia(contraparteUuid, contraparteDriver);
    final solicitud = inc['solicitud_id'];
    final viaje = inc['viaje_id'];

    return InkWell(
      onTap: () => _abrirDetalle(inc),
      child: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _celda('#$id', flex: 1, secundario: true),
            _celda(_fecha(inc['created_at'] as String?), flex: 3),
            _celda(MueveteIncidentesService.etiquetaTipo('${inc['tipo']}'),
                flex: 3),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _chip(
                    MueveteIncidentesService.etiquetaSeveridad(severidad),
                    _colorSeveridad(severidad),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _chip(
                    MueveteIncidentesService.etiquetaEstado(estado),
                    _colorEstado(estado),
                  ),
                ),
              ),
            ),
            _celda(
              [
                if (solicitud != null) 'Sol. #$solicitud',
                if (viaje != null) 'Viaje #$viaje',
                if (solicitud == null && viaje == null) '—',
              ].join(' · '),
              flex: 3,
              secundario: true,
            ),
            Expanded(
              flex: 4,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$nombreReporta → $nombreContraparte',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    if (reinc >= 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: _chip(
                          'REINCIDENTE · $reinc confirmados',
                          AppColors.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                tooltip: 'Ver detalle',
                onPressed: () => _abrirDetalle(inc),
                icon: const Icon(Icons.chevron_right_rounded, size: 20),
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bloqueosRecientes() {
    if (_bloqueos.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.surfaceVariant,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.block_rounded, size: 15,
                    color: AppColors.textSecondary),
                const SizedBox(width: 8),
                Text(
                  'Bloqueos recientes',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_bloqueos.where((b) => b['revocado_at'] == null).length} '
                  'vigentes',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          ..._bloqueos.take(10).map((b) {
            final revocado = b['revocado_at'] != null;
            final sujeto = b['user_uuid'] != null
                ? _nombreUsuario('${b['user_uuid']}')
                : 'Chofer #${b['driver_id']}';
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '#${b['id']} · $sujeto · '
                          '${MueveteIncidentesService.etiquetaTipoBloqueo('${b['tipo_bloqueo']}')}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${b['motivo'] ?? '—'} · desde '
                          '${_fecha(b['vigente_desde'] as String?)}'
                          '${b['vigente_hasta'] != null ? ' · hasta ${_fecha(b['vigente_hasta'] as String?)}' : ' · sin fecha de fin'}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (revocado)
                    _chip('Revocado', AppColors.textSecondary)
                  else
                    TextButton(
                      onPressed: () => _revocarBloqueo(b),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                        textStyle: const TextStyle(fontSize: 11.5),
                      ),
                      child: const Text('Revocar'),
                    ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _paginador() {
    if (_cargandoIncidentes) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'Página anterior',
          onPressed:
              _paginaIncidentes == 0
                  ? null
                  : () => _cargarIncidentes(pagina: _paginaIncidentes - 1),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text(
          'Página ${_paginaIncidentes + 1}',
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
        IconButton(
          tooltip: 'Página siguiente',
          onPressed:
              _haySiguiente
                  ? () => _cargarIncidentes(pagina: _paginaIncidentes + 1)
                  : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  // ─── Tab 2: pánico reciente (sólo lectura) ───────────────────────────

  Widget _tabPanico(bool isDesktop) {
    if (_cargandoPanico) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorPanico != null) {
      return _EstadoError(mensaje: _errorPanico!, onReintentar: _cargarPanico);
    }
    if (_panico.isEmpty) {
      return const _EstadoVacio(
        icono: Icons.sos_rounded,
        titulo: 'Sin eventos de pánico',
        mensaje:
            'No hay eventos registrados. Esta pestaña es sólo lectura: la '
            'consola observa, no dispara ni cierra alertas.',
      );
    }

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded, size: 18,
                        color: AppColors.info),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Sólo lectura. El pánico no garantiza que alguien '
                        'acuda: Muevete no sustituye a la policía. Si estás en '
                        'peligro, llama al 106. Los contactos se muestran '
                        'enmascarados a propósito.',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.divider),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    Container(
                      color: AppColors.surfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          _celda('ID', flex: 1, cabecera: true),
                          _celda('RECIBIDO', flex: 3, cabecera: true),
                          _celda('ROL', flex: 2, cabecera: true),
                          _celda('ESTADO', flex: 2, cabecera: true),
                          _celda('ENVÍO', flex: 3, cabecera: true),
                          _celda('UBICACIÓN', flex: 3, cabecera: true),
                          _celda('CONTACTO NOTIFICADO', flex: 3, cabecera: true),
                        ],
                      ),
                    ),
                    ..._panico.map(_filaPanico),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filaPanico(Map<String, dynamic> p) {
    final lat = (p['lat'] as num?)?.toDouble();
    final lon = (p['lon'] as num?)?.toDouble();
    final notificados = p['notificados'];
    final cuantos =
        notificados is List ? notificados.length : 0;
    final estado = '${p['estado']}';
    final envio = '${p['envio_estado']}';
    final intentos = (p['envio_intentos'] as num?)?.toInt() ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _celda('#${p['id']}', flex: 1, secundario: true),
          _celda(_fecha(p['recibido_at'] as String?), flex: 3),
          _celda('${p['rol'] ?? '—'}', flex: 2),
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: _chip(
                  MueveteIncidentesService.etiquetaEstadoPanico(estado),
                  _colorEstadoPanico(estado),
                ),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    MueveteIncidentesService.etiquetaEnvio(envio),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color:
                          envio == 'fallido'
                              ? AppColors.error
                              : AppColors.textPrimary,
                    ),
                  ),
                  if (intentos > 0)
                    Text(
                      '$intentos intento(s)',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _celda(
            lat == null || lon == null
                ? 'Sin GPS'
                : '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}',
            flex: 3,
            secundario: lat == null || lon == null,
          ),
          _celda(
            [
              '${p['contacto_ppal_enmascarado'] ?? 'sin contacto'}',
              if (cuantos > 0) '$cuantos notificado(s)',
            ].join('\n'),
            flex: 3,
            secundario: true,
          ),
        ],
      ),
    );
  }

  // ─── Tab 3: puerta de identidad ──────────────────────────────────────

  Widget _tabPuerta(bool isDesktop) {
    if (_cargandoPuerta) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorPuerta != null) {
      return _EstadoError(mensaje: _errorPuerta!, onReintentar: _cargarPuerta);
    }
    if (_config == null) {
      return const _EstadoVacio(
        icono: Icons.lock_outline_rounded,
        titulo: 'Sin configuración de identidad',
        mensaje:
            'No existe la fila única (id = 1) de configuracion_identidad. '
            'Aplica la migración de identidad antes de operar la puerta.',
      );
    }

    final config = _config!;
    final suspendida = MueveteIncidentesService.suspensionVigente(config);
    final hasta = DateTime.tryParse(
      '${config['bloqueo_suspendido_hasta'] ?? ''}',
    )?.toLocal();

    return SingleChildScrollView(
      padding: EdgeInsets.all(isDesktop ? 24 : 16),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tarjetaEstadoPuerta(config, suspendida, hasta),
              const SizedBox(height: 14),
              _tarjetaConfiguracionPuerta(config),
              const SizedBox(height: 14),
              _avisoKyc(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tarjetaEstadoPuerta(
    Map<String, dynamic> config,
    bool suspendida,
    DateTime? hasta,
  ) {
    final color = suspendida ? AppColors.warning : AppColors.success;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                suspendida ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suspendida
                          ? 'Bloqueo de identidad SUSPENDIDO'
                          : 'Bloqueo de identidad activo',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      suspendida
                          ? 'Se permite operar sin perfil completo hasta '
                              '${_fecha(config['bloqueo_suspendido_hasta'] as String?)}'
                              '${hasta != null ? ' (queda ${_restante(hasta)})' : ''}'
                          : 'Nadie publica ni toma viajes sin perfil completo y '
                              'consentimiento vigente.',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if ((config['suspension_motivo'] as String?)?.trim().isNotEmpty ==
              true) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.sticky_note_2_rounded, size: 14,
                      color: AppColors.textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Motivo: ${config['suspension_motivo']}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ElevatedButton.icon(
                onPressed: _suspender,
                icon: const Icon(Icons.timer_outlined, size: 17),
                label: const Text('Suspender temporalmente'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              OutlinedButton.icon(
                onPressed: suspendida ? _reanudar : null,
                icon: const Icon(Icons.play_arrow_rounded, size: 17),
                label: const Text('Reanudar ahora'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: BorderSide(
                    color: AppColors.success.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed:
                    () => Navigator.of(context).pushNamed('/muevete/kyc'),
                icon: const Icon(Icons.verified_user_rounded, size: 16),
                label: const Text(
                  'Ir a Verificación KYC',
                  style: TextStyle(fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'La suspensión es temporal (máximo 30 días) y queda registrada con '
            'motivo y autor. Al reanudar, la puerta vuelve a exigir todo.',
            style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaConfiguracionPuerta(Map<String, dynamic> config) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 16,
                  color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Configuración vigente de la puerta',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chipBooleano('KYC obligatorio', config['kyc_obligatorio']),
              _chipBooleano(
                'Consentimiento obligatorio',
                config['consentimiento_obligatorio'],
              ),
              _chipBooleano(
                'Aprueba KYC de cliente',
                config['requiere_aprobacion_kyc_cliente'],
              ),
              _chipBooleano(
                'Aprueba KYC de chofer',
                config['requiere_aprobacion_kyc_chofer'],
              ),
              _chip('Días de gracia: ${config['dias_gracia'] ?? 0}',
                  AppColors.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surfaceVariant,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mensaje que ve el usuario bloqueado',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (config['mensaje_bloqueo'] as String?)?.trim().isNotEmpty ==
                          true
                      ? config['mensaje_bloqueo'] as String
                      : '—',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avisoKyc() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gpp_maybe_rounded, size: 18, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'drivers.kyc NO se suspende nunca',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Suspender esta puerta sólo deja de exigir perfil completo y '
                  'consentimiento durante la ventana indicada. Un chofer con '
                  'KYC pendiente o rechazado sigue sin poder operar: el estado '
                  'KYC se cambia únicamente desde Verificación KYC '
                  '(fn_kyc_revisar).',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chipBooleano(String etiqueta, Object? valor) {
    final activo = valor == true;
    return _chip(
      '$etiqueta: ${activo ? 'sí' : 'no'}',
      activo ? AppColors.success : AppColors.textSecondary,
    );
  }

  // ─── Celdas y chips ───────────────────────────────────────────────────

  Widget _celda(
    String texto, {
    int flex = 1,
    bool cabecera = false,
    bool secundario = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          texto,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: cabecera ? 9.5 : 11.5,
            fontWeight: cabecera ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: cabecera ? 0.4 : 0,
            color:
                cabecera
                    ? AppColors.textSecondary
                    : (secundario
                        ? AppColors.textSecondary
                        : AppColors.textPrimary),
          ),
        ),
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Color _colorSeveridad(String severidad) {
    switch (severidad) {
      case 'critica':
        return AppColors.error;
      case 'alta':
        return AppColors.warning;
      case 'media':
        return AppColors.info;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _colorEstado(String estado) {
    switch (estado) {
      case 'confirmado':
        return AppColors.error;
      case 'en_revision':
        return AppColors.warning;
      case 'escalado':
        return AppColors.info;
      case 'descartado':
        return AppColors.textSecondary;
      default:
        return AppColors.primary;
    }
  }

  Color _colorEstadoPanico(String estado) {
    switch (estado) {
      case 'activo':
        return AppColors.error;
      case 'gestionado':
        return AppColors.success;
      case 'cancelado_falso':
        return AppColors.textSecondary;
      default:
        return AppColors.info;
    }
  }

  // ─── Utilidades ───────────────────────────────────────────────────────

  String _nombreUsuario(String uuid) {
    final u = _usuarios[uuid];
    final nombre = (u?['name'] as String?)?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    if (uuid.isEmpty) return '—';
    return 'Usuario ${uuid.substring(0, 8)}…';
  }

  String _nombreContraparte(String? uuid, Object? driverId) {
    if (uuid != null && uuid.isNotEmpty) return _nombreUsuario(uuid);
    if (driverId != null) {
      final d = _choferes['$driverId'];
      final nombre = (d?['name'] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) return '$nombre (chofer)';
      return 'Chofer #$driverId';
    }
    return 'sin implicado';
  }

  int _conteoReincidencia(String? uuid, Object? driverId) {
    var maximo = 0;
    if (uuid != null && uuid.isNotEmpty) {
      final v = _reincidencia['u:$uuid'] ?? 0;
      if (v > maximo) maximo = v;
    }
    if (driverId != null) {
      final v = _reincidencia['d:$driverId'] ?? 0;
      if (v > maximo) maximo = v;
    }
    return maximo;
  }

  InputDecoration _decoracion(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
      labelStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }

  String _fecha(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$mi';
  }

  String _duracion(int minutos) {
    if (minutos < 60) return '$minutos min';
    final horas = minutos ~/ 60;
    final resto = minutos % 60;
    return resto == 0 ? '$horas h' : '$horas h $resto min';
  }

  String _restante(DateTime hasta) {
    final diff = hasta.difference(DateTime.now());
    if (diff.isNegative) return 'vencida';
    final horas = diff.inHours;
    final minutos = diff.inMinutes % 60;
    if (horas <= 0) return '$minutos min';
    return '$horas h $minutos min';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo: detalle del incidente + resolver + bloquear
// ═══════════════════════════════════════════════════════════════════════════

class _IncidenteDetalleDialog extends StatefulWidget {
  final Map<String, dynamic> incidente;
  final Map<String, Map<String, dynamic>> usuarios;
  final Map<String, Map<String, dynamic>> choferes;
  final Map<String, int> reincidencia;

  const _IncidenteDetalleDialog({
    required this.incidente,
    required this.usuarios,
    required this.choferes,
    required this.reincidencia,
  });

  @override
  State<_IncidenteDetalleDialog> createState() =>
      _IncidenteDetalleDialogState();
}

class _IncidenteDetalleDialogState extends State<_IncidenteDetalleDialog> {
  bool _ocupado = false;
  bool _cambio = false;
  String? _error;

  Map<String, dynamic> get _inc => widget.incidente;

  @override
  Widget build(BuildContext context) {
    final tipo = '${_inc['tipo']}';
    final severidad = '${_inc['severidad']}';
    final estado = '${_inc['estado']}';
    final uuid = _inc['contraparte_uuid'] as String?;
    final driverId = _inc['contraparte_driver_id'];
    final reporta = '${_inc['reportado_por_uuid'] ?? ''}';
    final reinc = _conteoReincidencia(uuid, driverId);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Incidente #${_inc['id']} · '
                          '${MueveteIncidentesService.etiquetaTipo(tipo)}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${_fecha(_inc['created_at'] as String?)} · '
                          'severidad '
                          '${MueveteIncidentesService.etiquetaSeveridad(severidad)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed:
                        _ocupado ? null : () => Navigator.pop(context, _cambio),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        _chip(
                          MueveteIncidentesService.etiquetaEstado(estado),
                          AppColors.info,
                        ),
                        if (reinc >= 2)
                          _chip(
                            'REINCIDENTE · $reinc confirmados',
                            AppColors.error,
                          ),
                        if (_inc['solicita_no_emparejar'] == true)
                          _chip('Pidió no volver a emparejar', AppColors.warning),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _fila('Reporta', _nombreUsuario(reporta)),
                    _fila('Rol', '${_inc['rol_reporta'] ?? '—'}'),
                    _fila(
                      'Implicado',
                      _nombreContraparte(uuid, driverId),
                    ),
                    _fila(
                      'Solicitud',
                      '${_inc['solicitud_id'] ?? '—'}',
                    ),
                    _fila('Viaje', '${_inc['viaje_id'] ?? '—'}'),
                    _fila(
                      'Revisado',
                      _inc['revisado_at'] == null
                          ? 'sin revisar'
                          : '${_fecha(_inc['revisado_at'] as String?)} '
                              'por ${_corto('${_inc['revisado_por'] ?? ''}')}',
                    ),
                    if ((_inc['resolucion'] as String?)?.trim().isNotEmpty ==
                        true)
                      _fila('Resolución', '${_inc['resolucion']}'),
                    const SizedBox(height: 12),
                    Text(
                      'DESCRIPCIÓN',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SelectableText(
                        (_inc['descripcion'] as String?) ?? '—',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Resolver con estado «confirmado» puede crear el bloqueo '
                      'automáticamente (severidad crítica, o reincidencia ≥ 2 en '
                      'la ventana configurada).',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: AppColors.textHint,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppColors.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.divider)),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed:
                        _ocupado
                            ? null
                            : _resolver,
                    icon: const Icon(Icons.task_alt_rounded, size: 17),
                    label: const Text('Resolver incidente'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: BorderSide(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed:
                        (_ocupado || (uuid == null && driverId == null))
                            ? null
                            : () => _bloquear(uuid, driverId),
                    icon:
                        _ocupado
                            ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                            : const Icon(Icons.block_rounded, size: 17),
                    label: const Text('Bloquear implicado'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
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

  Widget _fila(String etiqueta, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              etiqueta,
              style: TextStyle(
                fontSize: 11.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              valor,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(String texto, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Future<void> _resolver() async {
    final resultado = await showDialog<Map<String, String>>(
      context: context,
      builder: (_) => _ResolverDialog(estadoActual: '${_inc['estado']}'),
    );
    if (resultado == null || !mounted) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      final res = await MueveteIncidentesService.resolverIncidente(
        id: (_inc['id'] as num).toInt(),
        estado: resultado['estado']!,
        resolucion: resultado['resolucion']!,
      );
      _cambio = true;
      if (!mounted) return;
      setState(() => _ocupado = false);
      final bloqueo = res['bloqueo_id'];
      final mensaje = bloqueo == null
          ? 'Incidente resuelto'
          : 'Incidente resuelto · bloqueo #$bloqueo creado por la RPC';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensaje),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } on MueveteSeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = 'No se pudo resolver: $e';
      });
    }
  }

  Future<void> _bloquear(String? uuid, Object? driverId) async {
    final datos = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (_) => _BloqueoDialog(
            nombre: _nombreContraparte(uuid, driverId),
            puedeNoEmparejar: uuid != null && driverId != null,
          ),
    );
    if (datos == null || !mounted) return;
    setState(() {
      _ocupado = true;
      _error = null;
    });
    try {
      await MueveteIncidentesService.bloquear(
        motivo: datos['motivo'] as String,
        userUuid: uuid,
        driverId: driverId is num ? driverId.toInt() : null,
        tipoBloqueo: datos['tipo'] as String,
        dias: datos['dias'] as int?,
        incidenteId: (_inc['id'] as num).toInt(),
      );
      if (datos['noEmparejar'] == true && uuid != null && driverId is num) {
        await MueveteIncidentesService.noVolverAEmparejar(
          motivo: datos['motivo'] as String,
          userUuid: uuid,
          driverId: driverId.toInt(),
          incidenteId: (_inc['id'] as num).toInt(),
        );
      }
      _cambio = true;
      if (!mounted) return;
      setState(() => _ocupado = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bloqueo registrado'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context, true);
    } on MueveteSeguridadException catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = e.mensaje;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _error = 'No se pudo bloquear: $e';
      });
    }
  }

  int _conteoReincidencia(String? uuid, Object? driverId) {
    var maximo = 0;
    if (uuid != null && uuid.isNotEmpty) {
      final v = widget.reincidencia['u:$uuid'] ?? 0;
      if (v > maximo) maximo = v;
    }
    if (driverId != null) {
      final v = widget.reincidencia['d:$driverId'] ?? 0;
      if (v > maximo) maximo = v;
    }
    return maximo;
  }

  String _nombreUsuario(String uuid) {
    final u = widget.usuarios[uuid];
    final nombre = (u?['name'] as String?)?.trim();
    if (nombre != null && nombre.isNotEmpty) return nombre;
    if (uuid.isEmpty) return '—';
    return 'Usuario ${uuid.substring(0, 8)}…';
  }

  String _nombreContraparte(String? uuid, Object? driverId) {
    if (uuid != null && uuid.isNotEmpty) return _nombreUsuario(uuid);
    if (driverId != null) {
      final d = widget.choferes['$driverId'];
      final nombre = (d?['name'] as String?)?.trim();
      if (nombre != null && nombre.isNotEmpty) return '$nombre (chofer)';
      return 'Chofer #$driverId';
    }
    return 'sin implicado';
  }

  String _corto(String uuid) =>
      uuid.length <= 13 ? (uuid.isEmpty ? '—' : uuid) : '${uuid.substring(0, 8)}…';

  String _fecha(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$mi';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo: resolver incidente
// ═══════════════════════════════════════════════════════════════════════════

class _ResolverDialog extends StatefulWidget {
  final String estadoActual;

  const _ResolverDialog({required this.estadoActual});

  @override
  State<_ResolverDialog> createState() => _ResolverDialogState();
}

class _ResolverDialogState extends State<_ResolverDialog> {
  late String _estado;
  final _resolucion = TextEditingController();

  @override
  void initState() {
    super.initState();
    _estado =
        MueveteIncidentesService.estadosResolucion.contains(widget.estadoActual)
            ? widget.estadoActual
            : 'en_revision';
  }

  @override
  void dispose() {
    _resolucion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido = _resolucion.text.trim().length >= 5;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Resolver incidente',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              key: ValueKey('resolver-$_estado'),
              initialValue: _estado,
              isExpanded: true,
              isDense: true,
              decoration: InputDecoration(
                labelText: 'Estado final',
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: MueveteIncidentesService.estadosResolucion
                  .map(
                    (e) => DropdownMenuItem<String>(
                      value: e,
                      child: Text(
                        MueveteIncidentesService.etiquetaEstado(e),
                        style: const TextStyle(fontSize: 12.5),
                      ),
                    ),
                  )
                  .toList(),
              onChanged:
                  (v) => setState(() => _estado = v ?? 'en_revision'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _resolucion,
              maxLines: 4,
              onChanged: (_) => setState(() {}),
              style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: 'Resolución (mínimo 5 caracteres)',
                alignLabelWithHint: true,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Llama a fn_resolver_incidente(p_incidente_id, p_estado, '
              'p_resolucion).',
              style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              valido
                  ? () => Navigator.pop(context, {
                    'estado': _estado,
                    'resolucion': _resolucion.text.trim(),
                  })
                  : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Guardar resolución'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo: bloquear implicado
// ═══════════════════════════════════════════════════════════════════════════

class _BloqueoDialog extends StatefulWidget {
  final String nombre;
  final bool puedeNoEmparejar;

  const _BloqueoDialog({
    required this.nombre,
    required this.puedeNoEmparejar,
  });

  @override
  State<_BloqueoDialog> createState() => _BloqueoDialogState();
}

class _BloqueoDialogState extends State<_BloqueoDialog> {
  String _tipo = 'administrativo';
  bool _noEmparejar = false;
  final _motivo = TextEditingController();
  final _dias = TextEditingController();

  @override
  void dispose() {
    _motivo.dispose();
    _dias.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido = _motivo.text.trim().length >= 5;
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Bloquear a ${widget.nombre}',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey('bloqueo-$_tipo'),
                initialValue: _tipo,
                isExpanded: true,
                isDense: true,
                decoration: InputDecoration(
                  labelText: 'Tipo de bloqueo',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                items: MueveteIncidentesService.tiposBloqueo
                    .map(
                      (t) => DropdownMenuItem<String>(
                        value: t,
                        child: Text(
                          MueveteIncidentesService.etiquetaTipoBloqueo(t),
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    )
                    .toList(),
                onChanged:
                    (v) => setState(() => _tipo = v ?? 'administrativo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _dias,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Duración en días (vacío = sin fecha de fin)',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _motivo,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Motivo (mínimo 5 caracteres)',
                  alignLabelWithHint: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              if (widget.puedeNoEmparejar) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _noEmparejar,
                  onChanged:
                      (v) => setState(() => _noEmparejar = v),
                  title: Text(
                    'No volver a emparejarlos',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Inserta el par en emparejamientos_bloqueados.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Se inserta en muevete.bloqueos con incidente_id del reporte. '
                'Un bloqueo vigente impide publicar o tomar viajes.',
                style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              valido
                  ? () {
                    final dias = int.tryParse(_dias.text.trim());
                    Navigator.pop(context, <String, dynamic>{
                      'tipo': _tipo,
                      'motivo': _motivo.text.trim(),
                      'dias': (dias != null && dias > 0) ? dias : null,
                      'noEmparejar': _noEmparejar,
                    });
                  }
                  : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.error,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Bloquear'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Diálogo: suspender la puerta de identidad
// ═══════════════════════════════════════════════════════════════════════════

class _SuspensionDialog extends StatefulWidget {
  const _SuspensionDialog();

  @override
  State<_SuspensionDialog> createState() => _SuspensionDialogState();
}

class _SuspensionDialogState extends State<_SuspensionDialog> {
  static const List<int> _presets = [15, 30, 60, 120, 240, 480, 1440, 4320];

  int _minutos = 60;
  final _personalizado = TextEditingController();
  final _motivo = TextEditingController();

  @override
  void dispose() {
    _personalizado.dispose();
    _motivo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final valido =
        _minutos > 0 &&
        _minutos <= MueveteIncidentesService.minutosMaxSuspension &&
        _motivo.text.trim().length >= 5;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Suspender temporalmente la puerta de identidad',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Durante la ventana, el servidor deja de exigir perfil completo y '
                'consentimiento para publicar o tomar viajes. Sirve para un '
                'cutover o una incidencia, no para saltarse el KYC: '
                'drivers.kyc no cambia.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _presets.map((m) {
                      final activo = _minutos == m;
                      return ChoiceChip(
                        label: Text(
                          _etiqueta(m),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight:
                                activo ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        selected: activo,
                        selectedColor: AppColors.warning.withValues(alpha: 0.2),
                        onSelected:
                            (_) => setState(() {
                              _minutos = m;
                              _personalizado.clear();
                            }),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _personalizado,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onChanged:
                    (v) => setState(() {
                      final m = int.tryParse(v.trim());
                      if (m != null) _minutos = m;
                    }),
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Minutos exactos '
                      '(máx. ${MueveteIncidentesService.minutosMaxSuspension})',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _motivo,
                maxLines: 3,
                onChanged: (_) => setState(() {}),
                style: TextStyle(fontSize: 13, color: AppColors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Motivo (queda en suspension_motivo)',
                  alignLabelWithHint: true,
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Llama a fn_suspender_bloqueo_identidad(p_minutos, p_motivo). '
                'Suspensión elegida: ${_etiqueta(_minutos)}.',
                style: TextStyle(fontSize: 10.5, color: AppColors.textHint),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed:
              valido
                  ? () {
                    Navigator.pop(context, <String, dynamic>{
                      'minutos': _minutos,
                      'motivo': _motivo.text.trim(),
                    });
                  }
                  : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.warning,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: const Text('Suspender'),
        ),
      ],
    );
  }

  String _etiqueta(int minutos) {
    if (minutos < 60) return '$minutos min';
    if (minutos % 1440 == 0) return '${minutos ~/ 1440} día(s)';
    if (minutos % 60 == 0) return '${minutos ~/ 60} h';
    return '$minutos min';
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Estados de carga / error / vacío
// ═══════════════════════════════════════════════════════════════════════════

class _EstadoError extends StatelessWidget {
  final String mensaje;
  final VoidCallback onReintentar;

  const _EstadoError({required this.mensaje, required this.onReintentar});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cloud_off_rounded,
                size: 40,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No se pudieron cargar los datos',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: onReintentar,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Reintentar'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.error,
                side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoVacio extends StatelessWidget {
  final IconData icono;
  final String titulo;
  final String mensaje;

  const _EstadoVacio({
    required this.icono,
    required this.titulo,
    required this.mensaje,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(icono, size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              titulo,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Text(
                mensaje,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}