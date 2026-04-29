import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../models/carga_model.dart';
import '../../models/oferta_carga_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/map_widget.dart';
import 'cargo_location_picker_screen.dart';
import 'carrier_directory_screen.dart';

class ShipperHomeScreen extends StatefulWidget {
  const ShipperHomeScreen({super.key});

  @override
  State<ShipperHomeScreen> createState() => _ShipperHomeScreenState();
}

class _ShipperHomeScreenState extends State<ShipperHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _load() {
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.id;
    if (uid != null) {
      context.read<CargaProvider>().loadMisCargas(uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final name = (auth.userProfile?['name'] as String?) ?? 'Shipper';
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
            icon: Icon(Icons.logout, color: textPrimary),
            onPressed: () async {
              await context.read<AuthProvider>().signOut();
              if (context.mounted) {
                Navigator.pushReplacementNamed(context, '/login');
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor:
              isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.list_alt_outlined), text: 'Mis Cargas'),
            Tab(icon: Icon(Icons.add_box_outlined), text: 'Publicar'),
            Tab(icon: Icon(Icons.people_alt_outlined), text: 'Transportistas'),
          ],
          isScrollable: true,
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _MisCargasTab(onTabSwitch: () => _tabs.animateTo(1)),
          _PublicarCargaTab(onPublished: () {
            _load();
            _tabs.animateTo(0);
          }),
          const CarrierDirectoryScreen(embedded: true),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 1 – Mis Cargas
// ──────────────────────────────────────────────────────────────────────────────

class _MisCargasTab extends StatelessWidget {
  final VoidCallback onTabSwitch;
  const _MisCargasTab({required this.onTabSwitch});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();

    if (provider.loadingMisCargas) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.misCargas.isEmpty) {
      return _EmptyState(
        icon: Icons.inventory_2_outlined,
        title: 'Sin cargas publicadas',
        subtitle:
            'Publica tu primera carga para recibir ofertas de transportistas.',
        actionLabel: 'Publicar Carga',
        onAction: onTabSwitch,
      );
    }

    return RefreshIndicator(
      onRefresh: () {
        final uid =
            context.read<AuthProvider>().user?.id;
        if (uid != null) {
          return context.read<CargaProvider>().loadMisCargas(uid);
        }
        return Future.value();
      },
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: provider.misCargas.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, i) {
          final carga = provider.misCargas[i];
          return _CargaCard(
            carga: carga,
            isDark: isDark,
            onTap: () => _showDetalle(context, carga, isDark),
          );
        },
      ),
    );
  }

  void _showDetalle(
      BuildContext context, CargaModel carga, bool isDark) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _DetalleCargaScreen(carga: carga),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 2 – Publicar Carga
// ──────────────────────────────────────────────────────────────────────────────

class _PublicarCargaTab extends StatefulWidget {
  final VoidCallback onPublished;
  const _PublicarCargaTab({required this.onPublished});

  @override
  State<_PublicarCargaTab> createState() => _PublicarCargaTabState();
}

class _PublicarCargaTabState extends State<_PublicarCargaTab> {
  final _formKey = GlobalKey<FormState>();

  // Location state (set via CargoLocationPickerScreen)
  double? _latOrigen, _lonOrigen;
  String? _dirOrigen, _ciudadOrigen, _provinciaOrigen, _paisOrigen;
  double? _latDestino, _lonDestino;
  String? _dirDestino, _ciudadDestino, _provinciaDestino, _paisDestino;

  final _descripcionCtrl = TextEditingController();
  final _pesoCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _instruccionesCtrl = TextEditingController();
  final _horasCargaCtrl = TextEditingController();
  final _horasDescargaCtrl = TextEditingController();

  String _tipo = 'ftl';
  String _unidadPeso = 'kg';
  double? _distanciaKm;
  String? _tipoMercancia;
  String? _tipoEquipo;
  bool _requiereRefrigeracion = false;
  bool _requiereSeguro = false;
  DateTime? _fechaRecogida;
  DateTime? _fechaEntrega;

  static const _mercanciaOpciones = [
    'General',
    'Refrigerada',
    'Peligrosa',
    'Sobredimensionada',
    'Vehículos',
    'Electrónica',
    'Otros',
  ];

  static const _equipoOpciones = [
    'flatbed',
    'van',
    'reefer',
    'dryvan',
    'tanker',
    'curtain',
  ];

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _pesoCtrl.dispose();
    _precioCtrl.dispose();
    _instruccionesCtrl.dispose();
    _horasCargaCtrl.dispose();
    _horasDescargaCtrl.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final auth = context.read<AuthProvider>();
    final pais = auth.userProfile?['pais'] as String?
        ?? auth.driverProfile?['pais'] as String?;
    final provincia = auth.userProfile?['province'] as String?
        ?? auth.driverProfile?['province'] as String?;

    final result = await Navigator.push<CargoLocationResult>(
      context,
      MaterialPageRoute(
        builder: (_) => CargoLocationPickerScreen(
          perfilPais: pais,
          perfilProvincia: provincia,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _latOrigen = result.latOrigen;
        _lonOrigen = result.lonOrigen;
        _dirOrigen = result.dirOrigen;
        _ciudadOrigen = result.ciudadOrigen;
        _provinciaOrigen = result.provinciaOrigen;
        _paisOrigen = result.paisOrigen;
        _latDestino = result.latDestino;
        _lonDestino = result.lonDestino;
        _dirDestino = result.dirDestino;
        _ciudadDestino = result.ciudadDestino;
        _provinciaDestino = result.provinciaDestino;
        _paisDestino = result.paisDestino;
        _distanciaKm = result.distanciaKm;
      });
    }
  }

  Future<void> _pickFecha(bool esRecogida) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (esRecogida) {
          _fechaRecogida = picked;
        } else {
          _fechaEntrega = picked;
        }
      });
    }
  }

  Future<void> _submit() async {
    if (_dirOrigen == null || _dirDestino == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecciona los puntos de recogida y entrega'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final uid = auth.user?.id;
    if (uid == null) return;

    final carga = CargaModel(
      id: 0,
      shipperId: uid,
      tipo: _tipo,
      estado: 'publicada',
      dirOrigen: _dirOrigen!,
      latOrigen: _latOrigen ?? 0,
      lonOrigen: _lonOrigen ?? 0,
      ciudadOrigen: _ciudadOrigen,
      dirDestino: _dirDestino!,
      latDestino: _latDestino ?? 0,
      lonDestino: _lonDestino ?? 0,
      ciudadDestino: _ciudadDestino,
      descripcion: _descripcionCtrl.text.trim().isEmpty
          ? null
          : _descripcionCtrl.text.trim(),
      tipoMercancia: _tipoMercancia,
      pesoKg: () {
        final cleaned = _pesoCtrl.text.replaceAll(',', '.');
        final v = double.tryParse(cleaned);
        return v == null ? null : (_unidadPeso == 'tonelada' ? v * 1000 : v);
      }(),
      unidadPeso: _unidadPeso,
      horasCarga: double.tryParse(_horasCargaCtrl.text.replaceAll(',', '.')),
      horasDescarga:
          double.tryParse(_horasDescargaCtrl.text.replaceAll(',', '.')),
      distanciaKm: _distanciaKm,
      requiereRefrigeracion: _requiereRefrigeracion,
      requiereSeguro: _requiereSeguro,
      instrucciones: _instruccionesCtrl.text.trim().isEmpty
          ? null
          : _instruccionesCtrl.text.trim(),
      tipoEquipo: _tipoEquipo,
      fechaRecogida: _fechaRecogida,
      fechaEntrega: _fechaEntrega,
      precioOfertado: double.tryParse(_precioCtrl.text),
      createdAt: DateTime.now(),
    );

    final ok =
        await context.read<CargaProvider>().publicarCarga(carga);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Carga publicada con éxito'),
          backgroundColor: Colors.green[700],
        ),
      );
      _formKey.currentState!.reset();
      setState(() {
        _tipo = 'ftl';
        _tipoMercancia = null;
        _tipoEquipo = null;
        _requiereRefrigeracion = false;
        _requiereSeguro = false;
        _fechaRecogida = null;
        _fechaEntrega = null;
        _unidadPeso = 'kg';
        _distanciaKm = null;
        _latOrigen = null; _lonOrigen = null; _dirOrigen = null;
        _ciudadOrigen = null; _provinciaOrigen = null; _paisOrigen = null;
        _latDestino = null; _lonDestino = null; _dirDestino = null;
        _ciudadDestino = null; _provinciaDestino = null; _paisDestino = null;
      });
      _horasCargaCtrl.clear();
      _horasDescargaCtrl.clear();
      widget.onPublished();
    } else {
      final err = context.read<CargaProvider>().error ?? 'Error desconocido';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(err),
            backgroundColor: AppTheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Tipo FTL / LTL
            _SectionLabel('Tipo de Carga', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                _TipoChip(
                  label: 'FTL (Camión Completo)',
                  selected: _tipo == 'ftl',
                  isDark: isDark,
                  onTap: () => setState(() => _tipo = 'ftl'),
                ),
                const SizedBox(width: 10),
                _TipoChip(
                  label: 'LTL (Carga Parcial)',
                  selected: _tipo == 'ltl',
                  isDark: isDark,
                  onTap: () => setState(() => _tipo = 'ltl'),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _SectionLabel('Ruta de la Carga', isDark),
            const SizedBox(height: 8),
            // Map-based location picker tile
            _LocationPickerTile(
              isDark: isDark,
              dirOrigen: _dirOrigen,
              ciudadOrigen: _ciudadOrigen,
              provinciaOrigen: _provinciaOrigen,
              paisOrigen: _paisOrigen,
              dirDestino: _dirDestino,
              ciudadDestino: _ciudadDestino,
              provinciaDestino: _provinciaDestino,
              paisDestino: _paisDestino,
              onTap: _openPicker,
            ),

            const SizedBox(height: 20),
            _SectionLabel('Mercancía', isDark),
            const SizedBox(height: 8),
            _Field(
              controller: _descripcionCtrl,
              hint: 'Descripción de la carga',
              icon: Icons.description_outlined,
              isDark: isDark,
              maxLines: 2,
            ),
            const SizedBox(height: 10),
            // Tipo mercancia dropdown
            _Dropdown(
              value: _tipoMercancia,
              hint: 'Tipo de mercancía',
              items: _mercanciaOpciones,
              isDark: isDark,
              onChanged: (v) => setState(() => _tipoMercancia = v),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _Field(
                    controller: _pesoCtrl,
                    hint: 'Peso',
                    icon: Icons.scale_outlined,
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: _Dropdown(
                    value: _unidadPeso,
                    hint: 'Unidad',
                    items: const ['kg', 'tonelada'],
                    isDark: isDark,
                    onChanged: (v) =>
                        setState(() => _unidadPeso = v ?? 'kg'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _horasCargaCtrl,
                    hint: 'Horas de carga',
                    icon: Icons.timer_outlined,
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    controller: _horasDescargaCtrl,
                    hint: 'Horas descarga',
                    icon: Icons.timer_off_outlined,
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CheckboxListTile(
                    value: _requiereRefrigeracion,
                    onChanged: (v) =>
                        setState(() => _requiereRefrigeracion = v ?? false),
                    title: Text('Refrigeración',
                        style: TextStyle(
                            color: textPrimary, fontSize: 13)),
                    activeColor: AppTheme.primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Expanded(
                  child: CheckboxListTile(
                    value: _requiereSeguro,
                    onChanged: (v) =>
                        setState(() => _requiereSeguro = v ?? false),
                    title: Text('Seguro',
                        style: TextStyle(
                            color: textPrimary, fontSize: 13)),
                    activeColor: AppTheme.primaryColor,
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _SectionLabel('Equipo Requerido', isDark),
            const SizedBox(height: 8),
            _Dropdown(
              value: _tipoEquipo,
              hint: 'Tipo de carrocería / equipo',
              items: _equipoOpciones,
              isDark: isDark,
              onChanged: (v) => setState(() => _tipoEquipo = v),
            ),

            const SizedBox(height: 20),
            _SectionLabel('Fechas', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: _fechaRecogida == null
                        ? 'Fecha de recogida'
                        : _fmt(_fechaRecogida!),
                    icon: Icons.calendar_today_outlined,
                    isDark: isDark,
                    onTap: () => _pickFecha(true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateButton(
                    label: _fechaEntrega == null
                        ? 'Fecha de entrega'
                        : _fmt(_fechaEntrega!),
                    icon: Icons.event_outlined,
                    isDark: isDark,
                    onTap: () => _pickFecha(false),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _SectionLabel('Precio Ofertado (USD)', isDark),
            const SizedBox(height: 8),
            _Field(
              controller: _precioCtrl,
              hint: 'Ej: 1500.00',
              icon: Icons.attach_money_outlined,
              isDark: isDark,
              keyboardType: TextInputType.number,
            ),

            const SizedBox(height: 10),
            _Field(
              controller: _instruccionesCtrl,
              hint: 'Instrucciones especiales (opcional)',
              icon: Icons.note_outlined,
              isDark: isDark,
              maxLines: 3,
            ),

            const SizedBox(height: 28),
            ElevatedButton(
              onPressed:
                  provider.actionLoading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor:
                    AppTheme.primaryColor.withValues(alpha: 0.5),
              ),
              child: provider.actionLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Colors.white))
                  : Text(
                      'Publicar Carga',
                      style: GoogleFonts.plusJakartaSans(
                          fontSize: 16,
                          fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

// ──────────────────────────────────────────────────────────────────────────────
// Detalle de Carga (Shipper view) – push route
// ──────────────────────────────────────────────────────────────────────────────

class _DetalleCargaScreen extends StatefulWidget {
  final CargaModel carga;
  const _DetalleCargaScreen({required this.carga});

  @override
  State<_DetalleCargaScreen> createState() => _DetalleCargaScreenState();
}

class _DetalleCargaScreenState extends State<_DetalleCargaScreen> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CargaProvider>().loadOfertasCarga(widget.carga.id);
      _fitMapToRoute();
    });
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
    final provider = context.watch<CargaProvider>();
    final carga = widget.carga;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;
    final cardColor =
        isDark ? AppTheme.darkCard : Colors.white;

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
          // Route map
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
              polylines: (
                      carga.latOrigen != 0 && carga.latDestino != 0)
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
          // Estado badge
          Row(
            children: [
              _EstadoBadge(estado: carga.estado),
              const SizedBox(width: 8),
              _EstadoBadge(
                  estado: carga.tipoLabel,
                  color: AppTheme.primaryColor),
              if (carga.destacada) ...
                [
                  const SizedBox(width: 8),
                  _EstadoBadge(
                      estado: 'Destacada',
                      color: Colors.amber[700]!),
                ],
            ],
          ),
          const SizedBox(height: 16),

          // Ruta
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
          // Detalles mercancía
          _InfoCard(
            isDark: isDark,
            children: [
              if (carga.descripcion != null)
                _InfoRow(
                  icon: Icons.description_outlined,
                  label: 'Descripción',
                  value: carga.descripcion!,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                ),
              if (carga.tipoMercancia != null) ...
                [
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.category_outlined,
                    label: 'Mercancía',
                    value: carga.tipoMercancia!,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
              if (carga.pesoKg != null) ...
                [
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.scale_outlined,
                    label: 'Peso',
                    value: '${carga.pesoKg!.toStringAsFixed(1)} kg',
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
              if (carga.precioOfertado != null) ...
                [
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.attach_money_outlined,
                    label: 'Precio ofertado',
                    value:
                        '\$${carga.precioOfertado!.toStringAsFixed(2)} ${carga.moneda}',
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
              if (carga.tipoEquipo != null) ...
                [
                  const Divider(height: 1),
                  _InfoRow(
                    icon: Icons.local_shipping_outlined,
                    label: 'Equipo',
                    value: carga.tipoEquipo!.toUpperCase(),
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
            ],
          ),

          const SizedBox(height: 20),
          Text(
            'Ofertas recibidas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 10),

          if (provider.loadingOfertas)
            const Center(child: CircularProgressIndicator())
          else if (provider.ofertasCarga.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Aún no hay ofertas para esta carga.',
                style: TextStyle(color: textSecondary),
                textAlign: TextAlign.center,
              ),
            )
          else
            ...provider.ofertasCarga.map(
              (o) => _OfertaCard(
                oferta: o,
                isDark: isDark,
                cargaAceptada: carga.estado == 'aceptada',
                onAceptar: () => _aceptarOferta(o),
                onRechazar: () => _rechazarOferta(o),
              ),
            ),

          const SizedBox(height: 24),
          if (carga.estado == 'publicada' ||
              carga.estado == 'ofertada')
            OutlinedButton.icon(
              onPressed: provider.actionLoading
                  ? null
                  : () => _cancelarCarga(context, carga.id),
              icon: const Icon(Icons.cancel_outlined),
              label: const Text('Cancelar Carga'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.error,
                side: BorderSide(color: AppTheme.error),
                padding:
                    const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          const SizedBox(height: 32),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _aceptarOferta(OfertaCargaModel oferta) async {
    final confirmed = await _confirm(
      context,
      '¿Aceptar oferta de \$${oferta.precio.toStringAsFixed(2)}?',
      'El carrier será notificado y tu carga quedará asignada.',
    );
    if (!confirmed || !mounted) return;
    final ok = await context.read<CargaProvider>().aceptarOferta(
          oferta.id,
          oferta.cargaId,
          oferta.driverId,
        );
    if (!mounted) return;
    _snack(ok ? 'Oferta aceptada' : context.read<CargaProvider>().error,
        ok);
    if (ok) Navigator.pop(context);
  }

  Future<void> _rechazarOferta(OfertaCargaModel oferta) async {
    final confirmed = await _confirm(
      context,
      '¿Rechazar esta oferta?',
      'El carrier será notificado del rechazo.',
    );
    if (!confirmed || !mounted) return;
    // Use service directly for reject
    try {
      await context
          .read<CargaProvider>()
          .loadOfertasCarga(oferta.cargaId);
    } catch (_) {}
  }

  Future<void> _cancelarCarga(
      BuildContext context, int cargaId) async {
    final confirmed = await _confirm(
      context,
      '¿Cancelar esta carga?',
      'Esta acción no se puede deshacer.',
    );
    if (!confirmed || !mounted) return;
    final ok =
        await context.read<CargaProvider>().cancelarCarga(cargaId);
    if (!mounted) return;
    _snack(
        ok ? 'Carga cancelada' : context.read<CargaProvider>().error,
        ok);
    if (ok) Navigator.pop(context);
  }

  void _snack(String? msg, bool ok) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg ?? ''),
      backgroundColor: ok ? Colors.green[700] : AppTheme.error,
    ));
  }
}

Future<bool> _confirm(
    BuildContext context, String title, String subtitle) async {
  final isDark = context.read<ThemeProvider>().isDark;
  return await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor:
              isDark ? AppTheme.darkCard : Colors.white,
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
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      ) ??
      false;
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ──────────────────────────────────────────────────────────────────────────────

class _CargaCard extends StatelessWidget {
  final CargaModel carga;
  final bool isDark;
  final VoidCallback onTap;
  const _CargaCard(
      {required this.carga,
      required this.isDark,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isDark
                  ? AppTheme.darkBorder
                  : Colors.grey[200]!),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    carga.rutaCorta,
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                _EstadoBadge(estado: carga.estadoLabel),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    size: 14, color: textSecondary),
                const SizedBox(width: 4),
                Text(
                  carga.tipoLabel,
                  style: TextStyle(
                      fontSize: 12, color: textSecondary),
                ),
                if (carga.pesoKg != null) ...
                  [
                    const SizedBox(width: 12),
                    Icon(Icons.scale_outlined,
                        size: 14, color: textSecondary),
                    const SizedBox(width: 4),
                    Text(
                      '${carga.pesoKg!.toStringAsFixed(0)} kg',
                      style: TextStyle(
                          fontSize: 12, color: textSecondary),
                    ),
                  ],
                if (carga.precioOfertado != null) ...
                  [
                    const SizedBox(width: 12),
                    Icon(Icons.attach_money_outlined,
                        size: 14, color: textSecondary),
                    Text(
                      '\$${carga.precioOfertado!.toStringAsFixed(0)}',
                      style: TextStyle(
                          fontSize: 12, color: textSecondary),
                    ),
                  ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfertaCard extends StatelessWidget {
  final OfertaCargaModel oferta;
  final bool isDark;
  final bool cargaAceptada;
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;
  const _OfertaCard({
    required this.oferta,
    required this.isDark,
    required this.cargaAceptada,
    required this.onAceptar,
    required this.onRechazar,
  });

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;
    final isPendiente = oferta.estado == 'pendiente';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: oferta.estado == 'aceptada'
              ? Colors.green
              : isDark
                  ? AppTheme.darkBorder
                  : Colors.grey[200]!,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.person_outline,
                  color: AppTheme.primaryColor, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  oferta.driverNombre ?? 'Transportista #${oferta.driverId}',
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: textPrimary),
                ),
              ),
              _EstadoBadge(estado: oferta.estadoLabel),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '\$${oferta.precio.toStringAsFixed(2)} ${oferta.incluyeSeguro ? '· Incluye seguro' : ''}',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.primaryColor,
            ),
          ),
          if (oferta.tiempoEstimadoDias != null) ...
            [
              const SizedBox(height: 4),
              Text(
                'Tiempo estimado: ${oferta.tiempoEstimadoDias} día(s)',
                style: TextStyle(fontSize: 12, color: textSecondary),
              ),
            ],
          if (oferta.notas != null && oferta.notas!.isNotEmpty) ...
            [
              const SizedBox(height: 4),
              Text(
                oferta.notas!,
                style: TextStyle(fontSize: 12, color: textSecondary),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          if (isPendiente && !cargaAceptada) ...
            [
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRechazar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: BorderSide(color: AppTheme.error),
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(8)),
                      ),
                      child: const Text('Rechazar'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: onAceptar,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(8)),
                      ),
                      child: const Text('Aceptar'),
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });

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
            Icon(icon, size: 72, color: AppTheme.primaryColor),
            const SizedBox(height: 20),
            Text(title,
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textPrimary),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtitle,
                style: TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onAction,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoBadge extends StatelessWidget {
  final String estado;
  final Color? color;
  const _EstadoBadge({required this.estado, this.color});

  static Color _colorFor(String estado) {
    switch (estado) {
      case 'publicada':
        return Colors.blue;
      case 'ofertada':
      case 'en_matching':
        return Colors.orange;
      case 'aceptada':
      case 'en_transito':
        return Colors.green;
      case 'entregada':
      case 'completada':
        return Colors.teal;
      case 'cancelada':
      case 'disputa':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = color ?? _colorFor(estado);
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Text(
        estado,
        style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: c),
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
            color: isDark ? AppTheme.darkBorder : Colors.grey[200]!),
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

class _SectionLabel extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionLabel(this.text, this.isDark);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : Colors.grey[700],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool isDark;
  final int maxLines;
  final TextInputType keyboardType;
  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.isDark,
    this.maxLines = 1,
    this.keyboardType = TextInputType.text,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF1A1D27)),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 18),
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  final String? value;
  final String hint;
  final List<String> items;
  final bool isDark;
  final ValueChanged<String?> onChanged;
  const _Dropdown({
    required this.value,
    required this.hint,
    required this.items,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    return DropdownButtonFormField<String>(
      value: value,
      dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
      style: TextStyle(color: textPrimary, fontSize: 14),
      decoration: InputDecoration(hintText: hint),
      items: items
          .map((e) => DropdownMenuItem(
              value: e,
              child: Text(e, style: TextStyle(color: textPrimary))))
          .toList(),
      onChanged: onChanged,
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;
  const _DateButton({
    required this.label,
    required this.icon,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 16),
      label: Text(label,
          style: const TextStyle(fontSize: 12),
          overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        foregroundColor:
            isDark ? Colors.white70 : Colors.grey[700],
        side: BorderSide(
            color: isDark ? AppTheme.darkBorder : Colors.grey[300]!),
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

class _TipoChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _TipoChip({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.primaryColor.withValues(alpha: 0.15)
                : isDark
                    ? AppTheme.darkCard
                    : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? AppTheme.primaryColor
                  : isDark
                      ? AppTheme.darkBorder
                      : Colors.grey[300]!,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppTheme.primaryColor
                  : isDark
                      ? Colors.white70
                      : Colors.grey[700],
            ),
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Location picker tile (replaces manual address fields)
// ──────────────────────────────────────────────────────────────────────────────

class _LocationPickerTile extends StatelessWidget {
  final bool isDark;
  final String? dirOrigen;
  final String? ciudadOrigen;
  final String? provinciaOrigen;
  final String? paisOrigen;
  final String? dirDestino;
  final String? ciudadDestino;
  final String? provinciaDestino;
  final String? paisDestino;
  final VoidCallback onTap;

  const _LocationPickerTile({
    required this.isDark,
    this.dirOrigen,
    this.ciudadOrigen,
    this.provinciaOrigen,
    this.paisOrigen,
    this.dirDestino,
    this.ciudadDestino,
    this.provinciaDestino,
    this.paisDestino,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasOrigen = dirOrigen != null;
    final hasDestino = dirDestino != null;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white54 : Colors.grey[600]!;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: (hasOrigen && hasDestino)
                ? AppTheme.primaryColor.withValues(alpha: 0.5)
                : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
            width: (hasOrigen && hasDestino) ? 1.5 : 1,
          ),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Origin row
            Row(
              children: [
                Icon(Icons.local_shipping_outlined,
                    size: 18, color: AppTheme.success),
                const SizedBox(width: 10),
                Expanded(
                  child: hasOrigen
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dirOrigen!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary)),
                            if (ciudadOrigen != null ||
                                provinciaOrigen != null ||
                                paisOrigen != null)
                              Text(
                                [ciudadOrigen, provinciaOrigen, paisOrigen]
                                    .where((e) => e != null && e.isNotEmpty)
                                    .join(' · '),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: textSecondary),
                              ),
                          ],
                        )
                      : Text('Toca para seleccionar punto de recogida',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: textSecondary)),
                ),
              ],
            ),
            // Connector line
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Container(
                  height: 18,
                  width: 2,
                  color: (isDark ? AppTheme.darkBorder : Colors.grey[300])),
            ),
            // Destination row
            Row(
              children: [
                Icon(Icons.flag_outlined, size: 18, color: AppTheme.error),
                const SizedBox(width: 10),
                Expanded(
                  child: hasDestino
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(dirDestino!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary)),
                            if (ciudadDestino != null ||
                                provinciaDestino != null ||
                                paisDestino != null)
                              Text(
                                [ciudadDestino, provinciaDestino, paisDestino]
                                    .where((e) => e != null && e.isNotEmpty)
                                    .join(' · '),
                                style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11, color: textSecondary),
                              ),
                          ],
                        )
                      : Text('Toca para seleccionar punto de entrega',
                          style: GoogleFonts.plusJakartaSans(
                              fontSize: 13, color: textSecondary)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Change button
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Icon(Icons.map_outlined,
                    size: 14, color: AppTheme.primaryColor),
                const SizedBox(width: 4),
                Text(
                  hasOrigen && hasDestino
                      ? 'Cambiar ruta en mapa'
                      : 'Seleccionar en mapa',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w600,
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
