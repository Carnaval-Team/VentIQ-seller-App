import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/carga_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/map_widget.dart';

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
    context.read<CargaProvider>().loadCargasDisponibles();
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
            icon: Icon(Icons.refresh_outlined, color: textPrimary),
            onPressed: _load,
            tooltip: 'Actualizar',
          ),
          IconButton(
            icon: Icon(Icons.logout, color: textPrimary),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
      ),
      body: const _CargasDisponiblesTab(),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 1 – Cargas Disponibles
// ──────────────────────────────────────────────────────────────────────────────

class _CargasDisponiblesTab extends StatefulWidget {
  const _CargasDisponiblesTab();

  @override
  State<_CargasDisponiblesTab> createState() =>
      _CargasDisponiblesTabState();
}

class _CargasDisponiblesTabState extends State<_CargasDisponiblesTab> {
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
  bool _soloRefrigeracion = false;
  bool _soloSeguro = false;

  @override
  void dispose() {
    _ciudadOrigenCtrl.dispose();
    _ciudadDestinoCtrl.dispose();
    _pesoMaxCtrl.dispose();
    _precioMaxCtrl.dispose();
    _distMaxCtrl.dispose();
    super.dispose();
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
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;
    final cardBg = isDark ? AppTheme.darkCard : Colors.white;

    final all = provider.cargasDisponibles.where(_applyFilter).toList();
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
                  onApply: () => setState(() {
                    _page = 0;
                    _showFiltros = false;
                  }),
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
                      _soloRefrigeracion = false;
                      _soloSeguro = false;
                      _page = 0;
                      _showFiltros = false;
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
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  showCheckboxColumn: false,
                  columnSpacing: 16,
                  headingRowHeight: 40,
                  dataRowMinHeight: 48,
                  dataRowMaxHeight: 48,
                  headingRowColor: WidgetStateProperty.all(
                    isDark ? AppTheme.darkCard : Colors.grey[100],
                  ),
                  columns: [
                    DataColumn(label: _headerCell('Cliente', isDark)),
                    DataColumn(label: _headerCell('Origen', isDark)),
                    DataColumn(label: _headerCell('Destino', isDark)),
                    DataColumn(label: _headerCell('Tipo', isDark)),
                    DataColumn(label: _headerCell('Peso', isDark)),
                    DataColumn(label: _headerCell('Precio', isDark)),
                  ],
                  rows: pageItems.map((c) {
                    final cliente = c.shipperNombre ??
                        (c.shipperId.length > 8
                            ? '${c.shipperId.substring(0, 8)}…'
                            : c.shipperId);
                    final peso = c.pesoKg != null
                        ? '${c.pesoKg!.toStringAsFixed(0)} ${c.unidadPeso}'
                        : '—';
                    final precio = c.precioOfertado != null
                        ? '\$${c.precioOfertado!.toStringAsFixed(0)}'
                        : '—';
                    return DataRow(
                      onSelectChanged: (_) => _openDetalle(context, c),
                      cells: [
                        DataCell(_cell(cliente, isDark)),
                        DataCell(
                            _cell(c.ciudadOrigen ?? c.dirOrigen, isDark)),
                        DataCell(_cell(
                            c.ciudadDestino ?? c.dirDestino, isDark)),
                        DataCell(_Badge(
                            estado: c.tipoLabel,
                            color: AppTheme.primaryColor)),
                        DataCell(_cell(peso, isDark)),
                        DataCell(Text(
                          precio,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primaryColor,
                          ),
                        )),
                      ],
                    );
                  }).toList(),
                ),
              ),
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

  Widget _headerCell(String text, bool isDark) => Text(
        text,
        style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.grey[700]),
      );

  Widget _cell(String text, bool isDark) => SizedBox(
        width: 110,
        child: Text(
          text,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white : const Color(0xFF1A1D27),
          ),
        ),
      );

  void _openDetalle(BuildContext context, CargaModel carga) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalleCargaCarrierScreen(carga: carga),
      ),
    );
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
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _fitMapToRoute());
  }

  void _fitMapToRoute() {
    final c = widget.carga;
    if (c.latOrigen == 0 && c.latDestino == 0) return;
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([
            LatLng(c.latOrigen, c.lonOrigen),
            LatLng(c.latDestino, c.lonDestino),
          ]),
          padding: const EdgeInsets.all(40),
        ),
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
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
          SizedBox(
            height: 200,
            child: MapWidget(
              isDark: isDark,
              mapController: _mapController,
              center: LatLng(
                (carga.latOrigen + carga.latDestino) / 2,
                (carga.lonOrigen + carga.lonDestino) / 2,
              ),
              zoom: 7.0,
              markers: [
                if (carga.latOrigen != 0)
                  Marker(
                    point: LatLng(carga.latOrigen, carga.lonOrigen),
                    width: 36,
                    height: 36,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppTheme.success,
                        border:
                            Border.all(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.local_shipping,
                          color: Colors.white, size: 18),
                    ),
                  ),
                if (carga.latDestino != 0)
                  Marker(
                    point: LatLng(carga.latDestino, carga.lonDestino),
                    width: 36,
                    height: 44,
                    alignment: Alignment.topCenter,
                    child: Icon(Icons.location_on,
                        color: AppTheme.error, size: 32),
                  ),
              ],
              polylines: (carga.latOrigen != 0 && carga.latDestino != 0)
                  ? [
                      Polyline(
                        points: [
                          LatLng(carga.latOrigen, carga.lonOrigen),
                          LatLng(carga.latDestino, carga.lonDestino),
                        ],
                        color: AppTheme.primaryColor
                            .withValues(alpha: 0.65),
                        strokeWidth: 2.5,
                      )
                    ]
                  : const [],
            ),
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
                _InfoCard(
                  isDark: isDark,
                  children: [
                    if (carga.tipoMercancia != null)
                      _InfoRow(
                        icon: Icons.category_outlined,
                        label: 'Mercancía',
                        value: carga.tipoMercancia!,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    if (carga.pesoKg != null) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.scale_outlined,
                        label: 'Peso',
                        value:
                            '${carga.pesoKg!.toStringAsFixed(1)} ${carga.unidadPeso}',
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                    if (carga.tipoEquipo != null) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.local_shipping_outlined,
                        label: 'Equipo requerido',
                        value: carga.tipoEquipo!.toUpperCase(),
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                    if (carga.precioOfertado != null) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.attach_money_outlined,
                        label: 'Precio del shipper',
                        value:
                            '\$${carga.precioOfertado!.toStringAsFixed(2)} ${carga.moneda}',
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                    if (carga.requiereRefrigeracion) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.ac_unit_outlined,
                        label: 'Requiere refrigeración',
                        value: 'Sí',
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                    if (carga.horasCarga != null) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.timer_outlined,
                        label: 'Horas de carga',
                        value:
                            '${carga.horasCarga!.toStringAsFixed(1)} h',
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                    if (carga.horasDescarga != null) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.timer_off_outlined,
                        label: 'Horas de descarga',
                        value:
                            '${carga.horasDescarga!.toStringAsFixed(1)} h',
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                    if (carga.descripcion != null) ...[
                      const Divider(height: 1),
                      _InfoRow(
                        icon: Icons.description_outlined,
                        label: 'Notas del shipper',
                        value: carga.descripcion!,
                        textPrimary: textPrimary,
                        textSecondary: textSecondary,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _colorFor(String estado) {
    switch (estado) {
      case 'publicada':
        return Colors.blue;
      case 'ofertada':
        return Colors.orange;
      case 'aceptada':
      case 'en_transito':
        return Colors.green;
      default:
        return Colors.grey;
    }
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
  final bool soloRefrigeracion;
  final bool soloSeguro;
  final ValueChanged<String?> onTipoChanged;
  final ValueChanged<String?> onEquipoChanged;
  final ValueChanged<String?> onMercanciaChanged;
  final ValueChanged<bool> onRefChanged;
  final ValueChanged<bool> onSeguroChanged;
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
    required this.soloRefrigeracion,
    required this.soloSeguro,
    required this.onTipoChanged,
    required this.onEquipoChanged,
    required this.onMercanciaChanged,
    required this.onRefChanged,
    required this.onSeguroChanged,
    required this.onApply,
    required this.onClear,
  });

  static const _equipoOpciones = [
    'flatbed', 'van', 'reefer', 'dryvan', 'tanker', 'curtain'
  ];
  static const _mercanciaOpciones = [
    'General', 'Refrigerada', 'Peligrosa', 'Sobredimensionada',
    'Vehículos', 'Electrónica', 'Otros'
  ];

  @override
  Widget build(BuildContext context) {
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final bg = isDark ? AppTheme.darkCard : Colors.grey[50]!;
    const fieldDeco = InputDecoration(
      isDense: true,
      contentPadding:
          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ciudadOrigenCtrl,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration:
                        fieldDeco.copyWith(hintText: 'Ciudad origen'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: ciudadDestinoCtrl,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration:
                        fieldDeco.copyWith(hintText: 'Ciudad destino'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: tipoEquipoFiltro,
                    dropdownColor:
                        isDark ? AppTheme.darkCard : Colors.white,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration: fieldDeco.copyWith(hintText: 'Equipo'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Todos')),
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
                    dropdownColor:
                        isDark ? AppTheme.darkCard : Colors.white,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration:
                        fieldDeco.copyWith(hintText: 'Mercancía'),
                    items: [
                      const DropdownMenuItem(
                          value: null, child: Text('Todas')),
                      ..._mercanciaOpciones.map((e) =>
                          DropdownMenuItem(value: e, child: Text(e))),
                    ],
                    onChanged: onMercanciaChanged,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: pesoMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration:
                        fieldDeco.copyWith(hintText: 'Peso máx (kg)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: precioMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration:
                        fieldDeco.copyWith(hintText: 'Precio máx'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: distMaxCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(color: textPrimary, fontSize: 13),
                    decoration:
                        fieldDeco.copyWith(hintText: 'Dist. máx (km)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: soloRefrigeracion,
                    onChanged: (v) => onRefChanged(v ?? false),
                    title: Text('Refrigeración',
                        style: TextStyle(
                            color: textPrimary, fontSize: 12)),
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
                        style: TextStyle(
                            color: textPrimary, fontSize: 12)),
                    activeColor: AppTheme.primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onClear,
                  child: const Text('Limpiar'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: onApply,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Aplicar'),
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
