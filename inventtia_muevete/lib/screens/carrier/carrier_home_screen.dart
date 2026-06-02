import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/carga_model.dart';
import '../../models/estado_carga_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/carga_fechas_section.dart';
import '../../widgets/carga_mercancia_equipo_section.dart';
import '../../widgets/route_map_widget.dart';
import 'carrier_carga_profile_screen.dart';

class CarrierHomeScreen extends StatefulWidget {
  const CarrierHomeScreen({super.key});

  @override
  State<CarrierHomeScreen> createState() => _CarrierHomeScreenState();
}

class _CarrierHomeScreenState extends State<CarrierHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final p = context.read<CargaProvider>();
    p.loadCargasDisponibles();
    // Load loads assigned directly to this carrier by UUID
    final carrierUuid =
        context.read<AuthProvider>().user?.id;
    if (carrierUuid != null) {
      p.loadCargasCarrierByUuid(carrierUuid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final name =
        (auth.driverProfile?['name'] as String?) ?? 'Transportista';
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
        elevation: 0,
        title: Text(
          'Hola, $name',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            fontSize: 18,
            color: textPrimary,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.person_outline, color: textPrimary),
            tooltip: 'Mi Perfil',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const CarrierCargaProfileScreen()),
            ),
          ),
          IconButton(
            icon: Icon(Icons.refresh_outlined, color: textPrimary),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: Icon(Icons.logout, color: textPrimary),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/landing');
              }
            },
          ),
        ],
      ),
      body: const CargasDisponiblesTab(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 1 – Cargas Disponibles
// ──────────────────────────────────────────────────────────────────────────────

class CargasDisponiblesTab extends StatefulWidget {
  const CargasDisponiblesTab();

  @override
  State<CargasDisponiblesTab> createState() =>
      CargasDisponiblesTabState();
}

class CargasDisponiblesTabState extends State<CargasDisponiblesTab> {
  static const _perPage = 30;
  int _page = 0;
  bool _showFiltros = false;

  final _ciudadOrigenCtrl = TextEditingController();
  final _ciudadDestinoCtrl = TextEditingController();
  final _pesoMaxCtrl = TextEditingController();
  final _precioMaxCtrl = TextEditingController();
  final _distMaxCtrl = TextEditingController();

  String? _tipoFiltro;
  String? _tipoEquipoFiltro;
  String? _tipoMercanciaFiltro;
  String? _opcionEquipoExtraFiltro;
  bool _soloRefrigeracion = false;
  bool _soloSeguro = false;
  bool _soloPrivadas = false;
  DateTime? _fechaRecogidaDesde;

  @override
  void dispose() {
    _ciudadOrigenCtrl.dispose();
    _ciudadDestinoCtrl.dispose();
    _pesoMaxCtrl.dispose();
    _precioMaxCtrl.dispose();
    _distMaxCtrl.dispose();
    super.dispose();
  }

  void _swapOrigenDestino() {
    final tmpO = _ciudadOrigenCtrl.text;
    _ciudadOrigenCtrl.text = _ciudadDestinoCtrl.text;
    _ciudadDestinoCtrl.text = tmpO;
    setState(() => _page = 0);
  }

  bool _applyFilter(CargaModel c) {
    final qO = _ciudadOrigenCtrl.text.trim().toLowerCase();
    if (qO.isNotEmpty &&
        !(c.ciudadOrigen?.toLowerCase().contains(qO) ?? false)) {
      return false;
    }
    final qD = _ciudadDestinoCtrl.text.trim().toLowerCase();
    if (qD.isNotEmpty &&
        !(c.ciudadDestino?.toLowerCase().contains(qD) ?? false)) {
      return false;
    }
    if (_tipoFiltro != null && c.tipo != _tipoFiltro) return false;
    if (_tipoEquipoFiltro != null && c.tipoEquipo != _tipoEquipoFiltro) {
      return false;
    }
    if (_tipoMercanciaFiltro != null &&
        c.tipoMercancia != _tipoMercanciaFiltro) {
      return false;
    }
    final pesoMax = double.tryParse(_pesoMaxCtrl.text);
    if (pesoMax != null && (c.pesoKg ?? double.infinity) > pesoMax) {
      return false;
    }
    final precioMax = double.tryParse(_precioMaxCtrl.text);
    if (precioMax != null &&
        (c.precioOfertado ?? double.infinity) > precioMax) {
      return false;
    }
    final distMax = double.tryParse(_distMaxCtrl.text);
    if (distMax != null && (c.distanciaKm ?? double.infinity) > distMax) {
      return false;
    }
    if (_soloRefrigeracion && !c.requiereRefrigeracion) return false;
    if (_soloSeguro && !c.requiereSeguro) return false;
    if (_soloPrivadas && !c.esPrivada) return false;
    if (_opcionEquipoExtraFiltro != null &&
        !c.opcionesEquipo.contains(_opcionEquipoExtraFiltro)) return false;
    if (_fechaRecogidaDesde != null && c.fechaRecogida != null &&
        c.fechaRecogida!.isBefore(_fechaRecogidaDesde!)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;

    final all = provider.cargasDisponibles.where(_applyFilter).toList()
      ..sort((a, b) {
        if (a.fechaRecogida == null && b.fechaRecogida == null) return 0;
        if (a.fechaRecogida == null) return 1;
        if (b.fechaRecogida == null) return -1;
        return a.fechaRecogida!.compareTo(b.fechaRecogida!);
      });
    final totalPages = all.isEmpty ? 1 : (all.length / _perPage).ceil();
    final start = (_page * _perPage).clamp(0, all.length);
    final end = (start + _perPage).clamp(0, all.length);
    final pageItems = all.sublist(start, end);

    return Column(
      children: [
        // ── Toolbar ────────────────────────────────────────────────────────
        Material(
          color: cardBg,
          elevation: 1,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${all.length} de ${provider.cargasDisponibles.length} cargas',
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => _showFiltros = !_showFiltros),
                  icon: const Icon(Icons.tune_outlined, size: 18),
                  label: Text(_showFiltros ? 'Ocultar' : 'Filtros'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.primaryColor,
                    padding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_outlined, size: 20),
                  onPressed: () =>
                      context.read<CargaProvider>().loadCargasDisponibles(),
                  color: textSecondary,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),

        // ── Filtros expandibles ─────────────────────────────────────────────
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _showFiltros
              ? _FilterPanel(
                  isDark: isDark,
                  ciudadOrigenCtrl: _ciudadOrigenCtrl,
                  ciudadDestinoCtrl: _ciudadDestinoCtrl,
                  pesoMaxCtrl: _pesoMaxCtrl,
                  precioMaxCtrl: _precioMaxCtrl,
                  distMaxCtrl: _distMaxCtrl,
                  tipoFiltro: _tipoFiltro,
                  tipoEquipoFiltro: _tipoEquipoFiltro,
                  tipoMercanciaFiltro: _tipoMercanciaFiltro,
                  soloRefrigeracion: _soloRefrigeracion,
                  soloSeguro: _soloSeguro,
                  onTipoChanged: (v) => setState(() {
                    _tipoFiltro = v;
                    _page = 0;
                  }),
                  onEquipoChanged: (v) => setState(() {
                    _tipoEquipoFiltro = v;
                    _page = 0;
                  }),
                  onMercanciaChanged: (v) => setState(() {
                    _tipoMercanciaFiltro = v;
                    _page = 0;
                  }),
                  onRefChanged: (v) => setState(() {
                    _soloRefrigeracion = v;
                    _page = 0;
                  }),
                  onSeguroChanged: (v) => setState(() {
                    _soloSeguro = v;
                    _page = 0;
                  }),
                  opcionEquipoExtraFiltro: _opcionEquipoExtraFiltro,
                  soloPrivadas: _soloPrivadas,
                  fechaRecogidaDesde: _fechaRecogidaDesde,
                  onOpcionEquipoExtraChanged: (v) => setState(() {
                    _opcionEquipoExtraFiltro = v;
                    _page = 0;
                  }),
                  onSoloPrivadasChanged: (v) => setState(() {
                    _soloPrivadas = v;
                    _page = 0;
                  }),
                  onFechaRecogidaDesdeChanged: (v) => setState(() {
                    _fechaRecogidaDesde = v;
                    _page = 0;
                  }),
                  onSwapOrigenDestino: _swapOrigenDestino,
                  onApply: () => setState(() => _page = 0),
                  onClear: () {
                    _ciudadOrigenCtrl.clear();
                    _ciudadDestinoCtrl.clear();
                    _pesoMaxCtrl.clear();
                    _precioMaxCtrl.clear();
                    _distMaxCtrl.clear();
                    setState(() {
                      _tipoFiltro = null;
                      _tipoEquipoFiltro = null;
                      _tipoMercanciaFiltro = null;
                      _opcionEquipoExtraFiltro = null;
                      _soloRefrigeracion = false;
                      _soloSeguro = false;
                      _soloPrivadas = false;
                      _fechaRecogidaDesde = null;
                      _page = 0;
                    });
                  },
                )
              : const SizedBox.shrink(),
        ),

        // ── Tabla / cargando / vacío ──────────────────────────────────────
        if (provider.loadingDisponibles)
          const Expanded(child: Center(child: CircularProgressIndicator()))
        else if (all.isEmpty)
          Expanded(
            child: _CarrierEmpty(
              title: 'No hay cargas disponibles',
              subtitle: provider.cargasDisponibles.isEmpty
                  ? 'Actualiza o vuelve más tarde.'
                  : 'Ninguna carga coincide con los filtros.',
            ),
          )
        else ...[
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tableWidth = constraints.maxWidth;
                return SingleChildScrollView(
                  child: SizedBox(
                    width: tableWidth,
                    child: DataTable(
                      showCheckboxColumn: false,
                      columnSpacing: 10,
                      horizontalMargin: 12,
                      headingRowHeight: 38,
                      dataRowMinHeight: 44,
                      dataRowMaxHeight: 56,
                      headingRowColor: WidgetStateProperty.all(
                        isDark ? AppTheme.darkCard : Colors.grey[100],
                      ),
                      columns: [
                        DataColumn(label: _headerCell('Prioridad', isDark)),
                        DataColumn(label: _headerCell('Origen', isDark)),
                        DataColumn(label: _headerCell('Destino', isDark)),
                        DataColumn(label: _headerCell('Tipo', isDark)),
                        DataColumn(label: _headerCell('Equipo', isDark)),
                        DataColumn(label: _headerCell('Peso', isDark)),
                        DataColumn(label: _headerCell('Precio', isDark)),
                        DataColumn(label: _headerCell('Recogida', isDark)),
                        DataColumn(label: _headerCell('Estado', isDark)),
                      ],
                      rows: pageItems.map((c) {
                        final now = DateTime.now();
                        final vencida = c.fechaRecogida != null &&
                            c.fechaRecogida!.isBefore(DateTime(now.year, now.month, now.day)) &&
                            !['tomada','en_transito','completada_carrier','entregada','completada'].contains(c.estado);
                        final peso = c.pesoKg != null
                            ? '${c.pesoKg!.toStringAsFixed(0)} ${c.unidadPeso}'
                            : '—';
                        final precio = c.precioOfertado != null
                            ? '\$${c.precioOfertado!.toStringAsFixed(0)}'
                            : '—';
                        final recogida = c.fechaRecogida != null
                            ? '${c.fechaRecogida!.day.toString().padLeft(2, '0')}/'
                              '${c.fechaRecogida!.month.toString().padLeft(2, '0')}/'
                              '${c.fechaRecogida!.year}'
                            : '—';
                        return DataRow(
                          color: vencida
                              ? WidgetStateProperty.all(
                                  Colors.red.withValues(alpha: isDark ? 0.18 : 0.07))
                              : null,
                          onSelectChanged: (_) => _openDetalle(context, c),
                          cells: [
                            DataCell(_PrioridadBadge(prioridad: c.prioridad)),
                            DataCell(_cell(
                                c.ciudadOrigen ?? c.dirOrigen, isDark,
                                bold: true)),
                            DataCell(_cell(
                                c.ciudadDestino ?? c.dirDestino, isDark,
                                bold: true)),
                            DataCell(_Badge(
                                estado: c.tipoLabel,
                                color: AppTheme.primaryColor)),
                            DataCell(_cell(
                                c.tipoEquipo?.toUpperCase() ?? '—', isDark)),
                            DataCell(_cell(peso, isDark)),
                            DataCell(Text(
                              precio,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primaryColor,
                              ),
                            )),
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (vencida)
                                  Padding(
                                    padding: const EdgeInsets.only(right: 4),
                                    child: Icon(Icons.warning_amber_rounded,
                                        size: 14, color: Colors.red[700]),
                                  ),
                                Text(recogida,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: vencida
                                          ? Colors.red[700]
                                          : (isDark ? Colors.white : const Color(0xFF1A1D27)),
                                      fontWeight: vencida ? FontWeight.w700 : FontWeight.normal,
                                    )),
                              ],
                            )),
                            DataCell(_Badge(
                                estado: c.estadoLabel,
                                color: _colorForEstado(c.estado))),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
          ),
          // ── Pagination ──────────────────────────────────────────────────
          Container(
            color: cardBg,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.first_page),
                  onPressed: _page > 0
                      ? () => setState(() => _page = 0)
                      : null,
                  color: AppTheme.primaryColor,
                  iconSize: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed:
                      _page > 0 ? () => setState(() => _page--) : null,
                  color: AppTheme.primaryColor,
                  iconSize: 20,
                ),
                Text(
                  'Pág. ${_page + 1} / $totalPages  (${all.length})',
                  style: TextStyle(fontSize: 12, color: textSecondary),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _page < totalPages - 1
                      ? () => setState(() => _page++)
                      : null,
                  color: AppTheme.primaryColor,
                  iconSize: 20,
                ),
                IconButton(
                  icon: const Icon(Icons.last_page),
                  onPressed: _page < totalPages - 1
                      ? () => setState(() => _page = totalPages - 1)
                      : null,
                  color: AppTheme.primaryColor,
                  iconSize: 20,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _openDetalle(BuildContext context, CargaModel carga) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalleCargaCarrierScreen(carga: carga),
      ),
    );
  }

  Widget _headerCell(String text, bool isDark) => Text(
        text,
        style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 11,
            color: isDark ? Colors.white70 : Colors.grey[700]),
      );

  Widget _cell(String text, bool isDark, {bool bold = false}) => Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: isDark ? Colors.white : const Color(0xFF1A1D27),
        ),
      );

  Color _colorForEstado(String estado) {
    switch (estado) {
      case 'publicada':
        return Colors.blue;
      case 'ofertada':
        return Colors.orange;
      case 'en_matching':
        return Colors.deepOrange;
      case 'aceptada':
      case 'en_transito':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }
}


// ──────────────────────────────────────────────────────────────────────────────
// Detalle carga (Carrier view) + formulario de oferta
// ──────────────────────────────────────────────────────────────────────────────

class _DetalleCargaCarrierScreen extends StatefulWidget {
  final CargaModel carga;
  const _DetalleCargaCarrierScreen({required this.carga});

  @override
  State<_DetalleCargaCarrierScreen> createState() =>
      _DetalleCargaCarrierScreenState();
}

class _DetalleCargaCarrierScreenState
    extends State<_DetalleCargaCarrierScreen> {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CargaProvider>().loadHistorialEstados(widget.carga.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();
    final carga = widget.carga;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : AppTheme.lightBg,
      appBar: AppBar(
        backgroundColor: cardColor,
        elevation: 0,
        title: Text(
          'Detalle de Carga',
          style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700, color: textPrimary),
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          RouteMapWidget(
            isDark: isDark,
            latOrigen: carga.latOrigen,
            lonOrigen: carga.lonOrigen,
            latDestino: carga.latDestino,
            lonDestino: carga.lonDestino,
            height: 220,
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _Badge(
                        estado: carga.estadoLabel,
                        color: _colorFor(carga.estado)),
                    const SizedBox(width: 8),
                    _Badge(
                        estado: carga.tipoLabel,
                        color: AppTheme.primaryColor),
                    const SizedBox(width: 8),
                    _PrioridadBadge(prioridad: carga.prioridad),
                    if (carga.distanciaKm != null) ...[
                      const SizedBox(width: 8),
                      _Badge(
                        estado:
                            '${carga.distanciaKm!.toStringAsFixed(0)} km',
                        color: Colors.teal,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 14),
                _InfoCard(
                  isDark: isDark,
                  children: [
                    _InfoRow(
                      icon: Icons.location_on_outlined,
                      label: 'Origen',
                      value: carga.ciudadOrigen != null
                          ? '${carga.ciudadOrigen} — ${carga.dirOrigen}'
                          : carga.dirOrigen,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                    const Divider(height: 1),
                    _InfoRow(
                      icon: Icons.flag_outlined,
                      label: 'Destino',
                      value: carga.ciudadDestino != null
                          ? '${carga.ciudadDestino} — ${carga.dirDestino}'
                          : carga.dirDestino,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CargaMercanciaEquipoSection(
                  carga: carga,
                  isDark: isDark,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  precioLabel: 'Precio del shipper',
                ),

                // ── Contacto en origen ───────────────────────────────────
                if (carga.nombreUbicacionOrigen != null ||
                    carga.cpOrigen != null ||
                    carga.contactoOrigenNombre != null ||
                    carga.contactoOrigenTel != null) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    isDark: isDark,
                    children: [
                      _InfoRow(
                        icon: Icons.location_city_outlined,
                        label: 'Lugar de origen',
                        value: [
                          if (carga.nombreUbicacionOrigen != null)
                            carga.nombreUbicacionOrigen!,
                          if (carga.cpOrigen != null) 'CP: ${carga.cpOrigen}',
                        ].join(' · '),
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      if (carga.contactoOrigenNombre != null) ...[
                        const Divider(height: 1),
                        _InfoRow(
                          icon: Icons.person_outline,
                          label: 'Contacto origen',
                          value: [
                            carga.contactoOrigenNombre!,
                            if (carga.contactoOrigenTel != null)
                              carga.contactoOrigenTel!,
                          ].join(' · '),
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      ],
                    ],
                  ),
                ],

                // ── Contacto en destino ──────────────────────────────────
                if (carga.nombreUbicacionDestino != null ||
                    carga.cpDestino != null ||
                    carga.contactoDestinoNombre != null ||
                    carga.contactoDestinoTel != null) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    isDark: isDark,
                    children: [
                      _InfoRow(
                        icon: Icons.location_city_outlined,
                        label: 'Lugar de destino',
                        value: [
                          if (carga.nombreUbicacionDestino != null)
                            carga.nombreUbicacionDestino!,
                          if (carga.cpDestino != null)
                            'CP: ${carga.cpDestino}',
                        ].join(' · '),
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                      if (carga.contactoDestinoNombre != null) ...[
                        const Divider(height: 1),
                        _InfoRow(
                          icon: Icons.person_outline,
                          label: 'Contacto destino',
                          value: [
                            carga.contactoDestinoNombre!,
                            if (carga.contactoDestinoTel != null)
                              carga.contactoDestinoTel!,
                          ].join(' · '),
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      ],
                    ],
                  ),
                ],

                if (carga.fechaRecogida != null ||
                    carga.fechaEntrega != null ||
                    carga.ventanaRecogidaDisplay != null ||
                    carga.ventanaEntregaDisplay != null) ...[
                  const SizedBox(height: 12),
                  CargaFechasSection(
                    carga: carga,
                    isDark: isDark,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],

                // ── Referencia y privacidad ──────────────────────────────
                if (carga.numerosReferencia.isNotEmpty || carga.esPrivada) ...[
                  const SizedBox(height: 12),
                  _InfoCard(
                    isDark: isDark,
                    children: [
                      if (carga.numerosReferencia.isNotEmpty)
                        _InfoRow(
                          icon: Icons.tag_outlined,
                          label: 'Referencia',
                          value: carga.numerosReferencia.join(', '),
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      if (carga.esPrivada) ...[
                        if (carga.numerosReferencia.isNotEmpty)
                          const Divider(height: 1),
                        _InfoRow(
                          icon: Icons.lock_outline,
                          label: 'Visibilidad',
                          value: carga.horasAnticipacionPublica != null &&
                                  carga.horasAnticipacionPublica! > 0
                              ? 'Privada · pública en ${carga.horasAnticipacionPublica}h'
                              : 'Privada (solo red)',
                          textPrimary: textPrimary,
                          textSecondary: textSecondary,
                        ),
                      ],
                    ],
                  ),
                ],

                // ── Acciones del carrier ──────────────────────────────────
                if (carga.estado == 'tomada') ...
                  [
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: provider.actionLoading
                          ? null
                          : () => _marcarCompletada(context, carga),
                      icon: const Icon(Icons.check_circle_outlined),
                      label: const Text('Marcar como Completada'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],

                // ── Historial de estados ────────────────────────────────
                const SizedBox(height: 24),
                Text(
                  'Historial de estados',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                if (provider.loadingHistorial)
                  const Center(child: CircularProgressIndicator())
                else if (provider.historialEstados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Sin historial registrado.',
                      style: TextStyle(color: textSecondary),
                    ),
                  )
                else
                  _HistorialTimelineCarrier(
                    historial: provider.historialEstados,
                    isDark: isDark,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),

                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _marcarCompletada(
      BuildContext context, CargaModel carga) async {
    final confirmed = await _confirmCarrier(
      context,
      '¿Marcar carga como Completada?',
      'Confirmas que la entrega fue realizada. El shipper deberá confirmar para cerrar el ciclo.',
    );
    if (!confirmed || !mounted) return;
    final auth = context.read<AuthProvider>();
    final driverId = auth.driverProfile?['id'] as int?;
    final ok = await context
        .read<CargaProvider>()
        .completarCargaCarrier(carga.id, driverId: driverId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Carga marcada como completada'
          : context.read<CargaProvider>().error ?? 'Error'),
      backgroundColor: ok ? Colors.green[700] : Colors.red,
    ));
    if (ok) Navigator.pop(context);
  }

  Future<bool> _confirmCarrier(
      BuildContext context, String title, String subtitle) async {
    final isDark = context.read<ThemeProvider>().isDark;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? AppTheme.darkCard : Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(title,
                style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700)),
            content: Text(subtitle),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white),
                child: const Text('Confirmar'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Color _colorFor(String estado) {
    switch (estado) {
      case 'publicada':          return Colors.blue;
      case 'en_matching':        return Colors.orange;
      case 'ofertada':           return Colors.amber[700]!;
      case 'aceptada':           return Colors.green;
      case 'tomada':             return Colors.indigo;
      case 'en_transito':        return Colors.teal;
      case 'completada_carrier': return Colors.cyan[700]!;
      case 'entregada':          return Colors.green[700]!;
      case 'completada':         return Colors.green[900]!;
      case 'cancelada':          return Colors.red;
      default:                   return Colors.grey;
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Historial de estados – timeline (carrier)
// ──────────────────────────────────────────────────────────────────────────────

class _HistorialTimelineCarrier extends StatelessWidget {
  final List<EstadoCargaModel> historial;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _HistorialTimelineCarrier({
    required this.historial,
    required this.isDark,
    required this.textPrimary,
    required this.textSecondary,
  });

  static Color _colorFor(String codigo) {
    switch (codigo) {
      case 'publicada':          return Colors.blue;
      case 'en_matching':        return Colors.orange;
      case 'ofertada':           return Colors.amber[700]!;
      case 'aceptada':           return Colors.green;
      case 'tomada':             return Colors.indigo;
      case 'en_transito':        return Colors.teal;
      case 'completada_carrier': return Colors.cyan[700]!;
      case 'entregada':          return Colors.green[700]!;
      case 'completada':         return Colors.green[900]!;
      case 'cancelada':          return Colors.red;
      default:                   return Colors.grey;
    }
  }

  String _fmt(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}  '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(historial.length, (i) {
        final e = historial[i];
        final isLast = i == historial.length - 1;
        final color = _colorFor(e.estadoCodigo);
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: isDark
                              ? Colors.white12
                              : Colors.grey[300],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.estadoNombre ?? e.estadoCodigo,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(_fmt(e.createdAt),
                          style: TextStyle(
                              fontSize: 11, color: textSecondary)),
                      if (e.motivo != null && e.motivo!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(e.motivo!,
                              style: TextStyle(
                                  fontSize: 11, color: textSecondary)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Filter panel
// ──────────────────────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  final bool isDark;
  final TextEditingController ciudadOrigenCtrl;
  final TextEditingController ciudadDestinoCtrl;
  final TextEditingController pesoMaxCtrl;
  final TextEditingController precioMaxCtrl;
  final TextEditingController distMaxCtrl;
  final String? tipoFiltro;
  final String? tipoEquipoFiltro;
  final String? tipoMercanciaFiltro;
  final String? opcionEquipoExtraFiltro;
  final bool soloRefrigeracion;
  final bool soloSeguro;
  final bool soloPrivadas;
  final DateTime? fechaRecogidaDesde;
  final ValueChanged<String?> onTipoChanged;
  final ValueChanged<String?> onEquipoChanged;
  final ValueChanged<String?> onMercanciaChanged;
  final ValueChanged<String?> onOpcionEquipoExtraChanged;
  final ValueChanged<bool> onRefChanged;
  final ValueChanged<bool> onSeguroChanged;
  final ValueChanged<bool> onSoloPrivadasChanged;
  final ValueChanged<DateTime?> onFechaRecogidaDesdeChanged;
  final VoidCallback onSwapOrigenDestino;
  final VoidCallback onApply;
  final VoidCallback onClear;

  const _FilterPanel({
    required this.isDark,
    required this.ciudadOrigenCtrl,
    required this.ciudadDestinoCtrl,
    required this.pesoMaxCtrl,
    required this.precioMaxCtrl,
    required this.distMaxCtrl,
    required this.tipoFiltro,
    required this.tipoEquipoFiltro,
    required this.tipoMercanciaFiltro,
    required this.opcionEquipoExtraFiltro,
    required this.soloRefrigeracion,
    required this.soloSeguro,
    required this.soloPrivadas,
    required this.fechaRecogidaDesde,
    required this.onTipoChanged,
    required this.onEquipoChanged,
    required this.onMercanciaChanged,
    required this.onOpcionEquipoExtraChanged,
    required this.onRefChanged,
    required this.onSeguroChanged,
    required this.onSoloPrivadasChanged,
    required this.onFechaRecogidaDesdeChanged,
    required this.onSwapOrigenDestino,
    required this.onApply,
    required this.onClear,
  });

  static const _equipoOpciones = [
    'flatbed', 'van', 'reefer', 'dryvan', 'tanker', 'curtain',
  ];
  static const _equipoExtraOpciones = [
    'liftgate', 'pallet_return', 'team_driver',
    'blanket_wrap', 'tarps', 'straps',
  ];
  static const _mercanciaOpciones = [
    'General', 'Refrigerada', 'Peligrosa', 'Sobredimensionada',
    'Vehículos', 'Electrónica', 'Otros',
  ];

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final bg = isDark ? AppTheme.darkCard : Colors.grey[50]!;
    const fieldDeco = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Origen / Destino con botón swap ──────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ciudadOrigenCtrl,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Ciudad origen'),
                  ),
                ),
                IconButton(
                  tooltip: 'Intercambiar origen y destino',
                  icon: const Icon(Icons.swap_horiz_outlined),
                  color: AppTheme.primaryColor,
                  iconSize: 22,
                  onPressed: onSwapOrigenDestino,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: EdgeInsets.zero,
                ),
                Expanded(
                  child: TextField(
                    controller: ciudadDestinoCtrl,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Ciudad destino'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Tipo FTL / LTL ────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: tipoFiltro,
              dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
              style: TextStyle(color: textPrimary, fontSize: 13),
              decoration: fieldDeco.copyWith(hintText: 'Tipo (FTL/LTL)'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Todos')),
                DropdownMenuItem(value: 'ftl', child: Text('FTL')),
                DropdownMenuItem(value: 'ltl', child: Text('LTL')),
              ],
              onChanged: onTipoChanged,
            ),
            const SizedBox(height: 8),
            // ── Equipo principal / Mercancía ──────────────────────────────
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: tipoEquipoFiltro,
                    dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Equipo'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todos')),
                      ..._equipoOpciones.map((e) =>
                          DropdownMenuItem(value: e, child: Text(e))),
                    ],
                    onChanged: onEquipoChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: tipoMercanciaFiltro,
                    dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Mercancía'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Todas')),
                      ..._mercanciaOpciones.map((e) =>
                          DropdownMenuItem(value: e, child: Text(e))),
                    ],
                    onChanged: onMercanciaChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Opción equipo extra ───────────────────────────────────────
            DropdownButtonFormField<String>(
              value: opcionEquipoExtraFiltro,
              dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
              style: TextStyle(color: textPrimary, fontSize: 13),
              decoration: fieldDeco.copyWith(hintText: 'Opción equipo extra'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Cualquiera')),
                ..._equipoExtraOpciones.map((e) =>
                    DropdownMenuItem(value: e, child: Text(e))),
              ],
              onChanged: onOpcionEquipoExtraChanged,
            ),
            const SizedBox(height: 8),
            // ── Numéricos ─────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pesoMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Peso máx (kg)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: precioMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Precio máx'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: distMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Dist. máx (km)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // ── Fecha recogida desde ──────────────────────────────────────
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: fechaRecogidaDesde ?? DateTime.now(),
                  firstDate: DateTime.now().subtract(const Duration(days: 1)),
                  lastDate: DateTime.now().add(const Duration(days: 365)),
                );
                onFechaRecogidaDesdeChanged(picked);
              },
              child: InputDecorator(
                decoration: fieldDeco.copyWith(
                  hintText: 'Recogida desde',
                  prefixIcon: const Icon(Icons.calendar_today_outlined, size: 16),
                  suffixIcon: fechaRecogidaDesde != null
                      ? GestureDetector(
                          onTap: () => onFechaRecogidaDesdeChanged(null),
                          child: const Icon(Icons.clear, size: 16),
                        )
                      : null,
                ),
                child: Text(
                  fechaRecogidaDesde != null
                      ? '${fechaRecogidaDesde!.day.toString().padLeft(2, '0')}/'
                          '${fechaRecogidaDesde!.month.toString().padLeft(2, '0')}/'
                          '${fechaRecogidaDesde!.year}'
                      : '',
                  style: TextStyle(color: textPrimary, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 4),
            // ── Checkboxes ────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: soloRefrigeracion,
                    onChanged: (v) => onRefChanged(v ?? false),
                    title: Text('Refrigeración',
                        style: TextStyle(color: textPrimary, fontSize: 12)),
                    activeColor: AppTheme.primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    value: soloSeguro,
                    onChanged: (v) => onSeguroChanged(v ?? false),
                    title: Text('Seguro',
                        style: TextStyle(color: textPrimary, fontSize: 12)),
                    activeColor: AppTheme.primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    value: soloPrivadas,
                    onChanged: (v) => onSoloPrivadasChanged(v ?? false),
                    title: Text('Privadas',
                        style: TextStyle(color: textPrimary, fontSize: 12)),
                    activeColor: AppTheme.primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
            // ── Botones ───────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onClear,
                  child: const Text('Limpiar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.search, size: 16),
                  label: const Text('Buscar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared helpers
// ──────────────────────────────────────────────────────────────────────────────

class _CarrierEmpty extends StatelessWidget {
  final String title;
  final String subtitle;
  const _CarrierEmpty({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_shipping_outlined,
                size: 64, color: AppTheme.primaryColor),
            const SizedBox(height: 16),
            Text(title,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String estado;
  final Color color;
  const _Badge({required this.estado, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        estado,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color),
      ),
    );
  }
}

class _PrioridadBadge extends StatelessWidget {
  final String prioridad;
  const _PrioridadBadge({required this.prioridad});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (prioridad) {
      case 'urgente':
        color = Colors.red;
        label = 'Urgente';
        break;
      case 'alta':
        color = Colors.orange;
        label = 'Alta';
        break;
      default:
        color = Colors.blueGrey;
        label = 'Normal';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _InfoCard({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                isDark ? AppTheme.darkBorder : Colors.grey[200]!),
      ),
      child: Column(children: children),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color textPrimary;
  final Color textSecondary;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppTheme.primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: textSecondary)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
