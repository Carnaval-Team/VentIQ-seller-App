import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/carga_model.dart';
import '../../models/estado_carga_model.dart';
import '../../models/oferta_carga_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/nomencladores_provider.dart';
import '../../utils/peso_unidad_util.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/carga_fechas_section.dart';
import '../../widgets/carga_mercancia_equipo_section.dart';
import '../../widgets/route_map_widget.dart';
import 'cargo_location_picker_screen.dart';
import 'carrier_directory_screen.dart';
import '../common/unified_profile_screen.dart';

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
            icon: Icon(Icons.person_outline, color: textPrimary),
            tooltip: 'Mi Perfil',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => const UnifiedProfileScreen()),
            ),
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
        final uid = context.read<AuthProvider>().user?.id;
        if (uid != null) {
          return context.read<CargaProvider>().loadMisCargas(uid);
        }
        return Future.value();
      },
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
                  DataColumn(label: _hdr('Prioridad', isDark)),
                  DataColumn(label: _hdr('Origen', isDark)),
                  DataColumn(label: _hdr('Destino', isDark)),
                  DataColumn(label: _hdr('Tipo', isDark)),
                  DataColumn(label: _hdr('Equipo', isDark)),
                  DataColumn(label: _hdr('Mercancía', isDark)),
                  DataColumn(label: _hdr('Peso', isDark)),
                  DataColumn(label: _hdr('Dist.', isDark)),
                  DataColumn(label: _hdr('Precio', isDark)),
                  DataColumn(label: _hdr('Recogida', isDark)),
                  DataColumn(label: _hdr('Ofertas', isDark)),
                  DataColumn(label: _hdr('Estado', isDark)),
                ],
                rows: provider.misCargas.map((c) {
                  final now = DateTime.now();
                  final vencida = c.fechaRecogida != null &&
                      c.fechaRecogida!.isBefore(DateTime(now.year, now.month, now.day)) &&
                      !['tomada','en_transito','completada_carrier','entregada','completada'].contains(c.estado);
                  final peso = c.pesoDisplay ?? '—';
                  final dist = c.distanciaKm != null
                      ? '${c.distanciaKm!.toStringAsFixed(0)} km'
                      : '—';
                  final precio = c.precioOfertado != null
                      ? '\$${c.precioOfertado!.toStringAsFixed(0)} ${c.moneda}'
                      : '—';
                  final recogida = c.fechaRecogida != null
                      ? '${c.fechaRecogida!.day.toString().padLeft(2, '0')}/'
                          '${c.fechaRecogida!.month.toString().padLeft(2, '0')}/'
                          '${c.fechaRecogida!.year}'
                      : '—';
                  final ofertas = c.ofertasCount != null && c.ofertasCount! > 0
                      ? '${c.ofertasCount}'
                      : '—';
                  return DataRow(
                    color: vencida
                        ? WidgetStateProperty.all(
                            Colors.red.withValues(alpha: isDark ? 0.18 : 0.07))
                        : null,
                    onSelectChanged: (_) => _showDetalle(context, c, isDark),
                    cells: [
                      DataCell(_ShipperPrioridadBadge(prioridad: c.prioridad)),
                      DataCell(_cel(c.ciudadOrigen ?? c.dirOrigen, isDark, bold: true)),
                      DataCell(_cel(c.ciudadDestino ?? c.dirDestino, isDark, bold: true)),
                      DataCell(_EstadoBadge(estado: c.tipoLabel, color: AppTheme.primaryColor)),
                      DataCell(_cel(c.tipoEquipo?.toUpperCase() ?? '—', isDark)),
                      DataCell(_cel(c.tipoMercancia ?? '—', isDark)),
                      DataCell(_cel(peso, isDark)),
                      DataCell(_cel(dist, isDark)),
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
                              child: Icon(Icons.warning_amber_rounded, size: 14, color: Colors.red[700]),
                            ),
                          Text(
                            recogida,
                            style: TextStyle(
                              fontSize: 12,
                              color: vencida ? Colors.red[700] : (isDark ? Colors.white : const Color(0xFF1A1D27)),
                              fontWeight: vencida ? FontWeight.w700 : FontWeight.normal,
                            ),
                          ),
                        ],
                      )),
                      DataCell(ofertas == '—'
                          ? _cel('—', isDark)
                          : _EstadoBadge(
                              estado: '$ofertas oferta(s)',
                              color: Colors.amber[800]!)),
                      DataCell(_EstadoBadge(estado: c.estadoLabel)),
                    ],
                  );
                }).toList(),
              ),
            ),
          );
        },
      ),
    );
  }

  static Widget _hdr(String t, bool isDark) => Text(t,
      style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: isDark ? Colors.white70 : Colors.grey[700]));

  static Widget _cel(String t, bool isDark, {bool bold = false}) => Text(
        t,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: isDark ? Colors.white : const Color(0xFF1A1D27),
        ),
      );

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
  final _largoCtrl = TextEditingController();
  final _anchoCtrl = TextEditingController();
  final _altoCtrl = TextEditingController();
  final _precioCtrl = TextEditingController();
  final _instruccionesCtrl = TextEditingController();
  final _horasCargaCtrl = TextEditingController();
  final _horasDescargaCtrl = TextEditingController();

  // Nuevos campos Truckstop — ubicación detallada
  final _nombreUbicOrigenCtrl = TextEditingController();
  final _cpOrigenCtrl = TextEditingController();
  final _contactoOrigenNombreCtrl = TextEditingController();
  final _contactoOrigenTelCtrl = TextEditingController();
  final _nombreUbicDestinoCtrl = TextEditingController();
  final _cpDestinoCtrl = TextEditingController();
  final _contactoDestinoNombreCtrl = TextEditingController();
  final _contactoDestinoTelCtrl = TextEditingController();

  // Nuevos campos Truckstop — comercial / equipo
  final _refNumCtrl = TextEditingController();
  int? _commodityNomId;
  final List<int> _opcionesEquipoSelIds = [];
  bool _esPrivada = false;
  int? _horasAnticipacionPublica;

  // Horarios de ventana (formato 'HH:mm')
  String? _ventanaRecogidaDesde;
  String? _ventanaRecogidaHasta;
  String? _ventanaEntregaDesde;
  String? _ventanaEntregaHasta;

  String _tipo = 'ftl';
  int? _unidadPesoId;
  double? _distanciaKm;
  int? _tipoMercanciaId;
  int? _tipoEquipoId;
  bool _requiereRefrigeracion = false;
  bool _requiereSeguro = false;
  DateTime? _fechaRecogida;
  DateTime? _fechaEntrega;
  String _prioridad = 'normal';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final noms = context.read<NomencladoresProvider>();
      await noms.cargar();
      if (mounted && _unidadPesoId == null) {
        setState(() => _unidadPesoId = noms.unidadPesoKg?.id);
      }
    });
  }

  @override
  void dispose() {
    _descripcionCtrl.dispose();
    _pesoCtrl.dispose();
    _largoCtrl.dispose();
    _anchoCtrl.dispose();
    _altoCtrl.dispose();
    _precioCtrl.dispose();
    _instruccionesCtrl.dispose();
    _horasCargaCtrl.dispose();
    _horasDescargaCtrl.dispose();
    _nombreUbicOrigenCtrl.dispose();
    _cpOrigenCtrl.dispose();
    _contactoOrigenNombreCtrl.dispose();
    _contactoOrigenTelCtrl.dispose();
    _nombreUbicDestinoCtrl.dispose();
    _cpDestinoCtrl.dispose();
    _contactoDestinoNombreCtrl.dispose();
    _contactoDestinoTelCtrl.dispose();
    _refNumCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickHora(bool esRecogida, bool esDesde) async {
    final inicial = TimeOfDay.now();
    final picked = await showTimePicker(
      context: context,
      initialTime: inicial,
      helpText: esRecogida
          ? (esDesde ? 'Hora inicio recogida' : 'Hora fin recogida')
          : (esDesde ? 'Hora inicio entrega' : 'Hora fin entrega'),
    );
    if (picked != null && mounted) {
      final str =
          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
      setState(() {
        if (esRecogida && esDesde) _ventanaRecogidaDesde = str;
        if (esRecogida && !esDesde) _ventanaRecogidaHasta = str;
        if (!esRecogida && esDesde) _ventanaEntregaDesde = str;
        if (!esRecogida && !esDesde) _ventanaEntregaHasta = str;
      });
    }
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

    // IDs nomenclador: 1=FTL, 2=LTL (seed migración 022)
    final tipoCargaId = _tipo == 'ltl' ? 2 : 1;

    double? parseNum(String txt) {
      final v = double.tryParse(txt.replaceAll(',', '.'));
      return v == null || v <= 0 ? null : v;
    }

    final noms = context.read<NomencladoresProvider>();
    final unidadPeso = noms.unidadPesoPorId(_unidadPesoId) ?? noms.unidadPesoKg;
    final pesoIngresado = () {
      final cleaned = _pesoCtrl.text.replaceAll(',', '.');
      final v = double.tryParse(cleaned);
      return v == null || v <= 0 ? null : v;
    }();

    final carga = CargaModel(
      id: 0,
      shipperId: uid,
      tipoCargaId: tipoCargaId,
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
      tipoMercanciaId: _tipoMercanciaId,
      commodityNomId: _commodityNomId,
      pesoValor: pesoIngresado,
      unidadPesoId: unidadPeso?.id,
      pesoKg: pesoIngresado != null && unidadPeso != null
          ? PesoUnidadUtil.aKilogramos(pesoIngresado, unidadPeso.factorAKg)
          : null,
      longitudM: parseNum(_largoCtrl.text),
      anchoM: parseNum(_anchoCtrl.text),
      altoM: parseNum(_altoCtrl.text),
      unidadPeso: unidadPeso?.simbolo ?? 'kg',
      horasCarga: double.tryParse(_horasCargaCtrl.text.replaceAll(',', '.')),
      horasDescarga:
          double.tryParse(_horasDescargaCtrl.text.replaceAll(',', '.')),
      distanciaKm: _distanciaKm,
      requiereRefrigeracion: _requiereRefrigeracion,
      requiereSeguro: _requiereSeguro,
      instrucciones: _instruccionesCtrl.text.trim().isEmpty
          ? null
          : _instruccionesCtrl.text.trim(),
      tipoEquipoId: _tipoEquipoId,
      opcionesEquipoManejo: _opcionesEquipoSelIds,
      fechaRecogida: _fechaRecogida,
      fechaEntrega: _fechaEntrega,
      ventanaRecogidaDesde: _ventanaRecogidaDesde,
      ventanaRecogidaHasta: _ventanaRecogidaHasta,
      ventanaEntregaDesde: _ventanaEntregaDesde,
      ventanaEntregaHasta: _ventanaEntregaHasta,
      precioOfertado: double.tryParse(_precioCtrl.text),
      // Ubicación detallada
      nombreUbicacionOrigen: _nombreUbicOrigenCtrl.text.trim().isEmpty ? null : _nombreUbicOrigenCtrl.text.trim(),
      cpOrigen: _cpOrigenCtrl.text.trim().isEmpty ? null : _cpOrigenCtrl.text.trim(),
      contactoOrigenNombre: _contactoOrigenNombreCtrl.text.trim().isEmpty ? null : _contactoOrigenNombreCtrl.text.trim(),
      contactoOrigenTel: _contactoOrigenTelCtrl.text.trim().isEmpty ? null : _contactoOrigenTelCtrl.text.trim(),
      nombreUbicacionDestino: _nombreUbicDestinoCtrl.text.trim().isEmpty ? null : _nombreUbicDestinoCtrl.text.trim(),
      cpDestino: _cpDestinoCtrl.text.trim().isEmpty ? null : _cpDestinoCtrl.text.trim(),
      contactoDestinoNombre: _contactoDestinoNombreCtrl.text.trim().isEmpty ? null : _contactoDestinoNombreCtrl.text.trim(),
      contactoDestinoTel: _contactoDestinoTelCtrl.text.trim().isEmpty ? null : _contactoDestinoTelCtrl.text.trim(),
      // Comercial
      numerosReferencia: _refNumCtrl.text.trim().isEmpty
          ? []
          : _refNumCtrl.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
      // Privacidad
      esPrivada: _esPrivada,
      horasAnticipacionPublica: _horasAnticipacionPublica,
      prioridad: _prioridad,
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
        _tipoMercanciaId = null;
        _tipoEquipoId = null;
        _requiereRefrigeracion = false;
        _requiereSeguro = false;
        _fechaRecogida = null;
        _fechaEntrega = null;
        _ventanaRecogidaDesde = null;
        _ventanaRecogidaHasta = null;
        _ventanaEntregaDesde = null;
        _ventanaEntregaHasta = null;
        _unidadPesoId = context.read<NomencladoresProvider>().unidadPesoKg?.id;
        _distanciaKm = null;
        _latOrigen = null; _lonOrigen = null; _dirOrigen = null;
        _ciudadOrigen = null; _provinciaOrigen = null; _paisOrigen = null;
        _latDestino = null; _lonDestino = null; _dirDestino = null;
        _ciudadDestino = null; _provinciaDestino = null; _paisDestino = null;
        _commodityNomId = null;
        _opcionesEquipoSelIds.clear();
        _esPrivada = false;
        _horasAnticipacionPublica = null;
        _prioridad = 'normal';
      });
      _largoCtrl.clear();
      _anchoCtrl.clear();
      _altoCtrl.clear();
      _horasCargaCtrl.clear();
      _horasDescargaCtrl.clear();
      _nombreUbicOrigenCtrl.clear();
      _cpOrigenCtrl.clear();
      _contactoOrigenNombreCtrl.clear();
      _contactoOrigenTelCtrl.clear();
      _nombreUbicDestinoCtrl.clear();
      _cpDestinoCtrl.clear();
      _contactoDestinoNombreCtrl.clear();
      _contactoDestinoTelCtrl.clear();
      _refNumCtrl.clear();
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
    final noms = context.watch<NomencladoresProvider>();
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Prioridad
            _SectionLabel('Prioridad de la Carga', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final op in [
                  ('normal', 'Normal', Colors.blueGrey),
                  ('alta', 'Alta', Colors.orange),
                  ('urgente', 'Urgente', Colors.red),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: GestureDetector(
                      onTap: () => setState(() => _prioridad = op.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _prioridad == op.$1
                              ? op.$3.withValues(alpha: 0.15)
                              : (isDark ? AppTheme.darkCard : Colors.grey[100]),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _prioridad == op.$1
                                ? op.$3
                                : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
                            width: _prioridad == op.$1 ? 1.5 : 1,
                          ),
                        ),
                        child: Text(
                          op.$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _prioridad == op.$1
                                ? op.$3
                                : (isDark ? Colors.white60 : Colors.grey[600]),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

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
            // Tipo mercancia dropdown — desde BD
            noms.loading
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                : DropdownButtonFormField<int>(
                    value: _tipoMercanciaId,
                    dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1D27),
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tipo de mercancía',
                      prefixIcon:
                          const Icon(Icons.category_outlined, size: 18),
                      hintStyle: TextStyle(
                          color:
                              isDark ? Colors.white38 : Colors.grey[500]),
                    ),
                    items: noms.tiposMercancia
                        .map((m) => DropdownMenuItem<int>(
                              value: m.id,
                              child: Text(m.nombre),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _tipoMercanciaId = v),
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
                  child: noms.unidadesPeso.isEmpty
                      ? const SizedBox(
                          height: 48,
                          child: Center(
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        )
                      : DropdownButtonFormField<int>(
                          value: _unidadPesoId,
                          dropdownColor:
                              isDark ? AppTheme.darkCard : Colors.white,
                          style: TextStyle(color: textPrimary, fontSize: 14),
                          decoration:
                              const InputDecoration(hintText: 'Unidad'),
                          items: noms.unidadesPeso
                              .map((u) => DropdownMenuItem(
                                    value: u.id,
                                    child: Text(
                                      '${u.nombre} (${u.simbolo})',
                                      style: TextStyle(color: textPrimary),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) =>
                              setState(() => _unidadPesoId = v),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Medidas (largo × ancho × alto)
            _SectionLabel('Medidas (m)', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _largoCtrl,
                    hint: 'Largo',
                    icon: Icons.straighten_outlined,
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    controller: _anchoCtrl,
                    hint: 'Ancho',
                    icon: Icons.width_normal_outlined,
                    isDark: isDark,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    controller: _altoCtrl,
                    hint: 'Alto',
                    icon: Icons.height_outlined,
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
            // Tipo equipo dropdown — desde BD
            noms.loading
                ? const SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(),
                  )
                : DropdownButtonFormField<int>(
                    value: _tipoEquipoId,
                    dropdownColor: isDark ? AppTheme.darkCard : Colors.white,
                    style: TextStyle(
                        color: isDark ? Colors.white : const Color(0xFF1A1D27),
                        fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Tipo de carrocería / equipo',
                      prefixIcon: const Icon(
                          Icons.local_shipping_outlined,
                          size: 18),
                      hintStyle: TextStyle(
                          color:
                              isDark ? Colors.white38 : Colors.grey[500]),
                    ),
                    items: noms.tiposEquipo
                        .map((e) => DropdownMenuItem<int>(
                              value: e.id,
                              child: Text(e.nombre),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _tipoEquipoId = v),
                  ),

            const SizedBox(height: 20),
            _SectionLabel('Recogida', isDark),
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
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: _ventanaRecogidaDesde == null
                        ? 'Desde (hora)'
                        : _ventanaRecogidaDesde!,
                    icon: Icons.access_time_outlined,
                    isDark: isDark,
                    onTap: () => _pickHora(true, true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateButton(
                    label: _ventanaRecogidaHasta == null
                        ? 'Hasta (hora)'
                        : _ventanaRecogidaHasta!,
                    icon: Icons.access_time_filled_outlined,
                    isDark: isDark,
                    onTap: () => _pickHora(true, false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _nombreUbicOrigenCtrl,
              hint: 'Nombre del lugar (ej: Almacén Central)',
              icon: Icons.business_outlined,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _cpOrigenCtrl,
                    hint: 'Código postal',
                    icon: Icons.markunread_mailbox_outlined,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _contactoOrigenNombreCtrl,
                    hint: 'Contacto (nombre)',
                    icon: Icons.person_outline,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    controller: _contactoOrigenTelCtrl,
                    hint: 'Teléfono',
                    icon: Icons.phone_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            _SectionLabel('Entrega', isDark),
            const SizedBox(height: 8),
            Row(
              children: [
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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DateButton(
                    label: _ventanaEntregaDesde == null
                        ? 'Desde (hora)'
                        : _ventanaEntregaDesde!,
                    icon: Icons.access_time_outlined,
                    isDark: isDark,
                    onTap: () => _pickHora(false, true),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _DateButton(
                    label: _ventanaEntregaHasta == null
                        ? 'Hasta (hora)'
                        : _ventanaEntregaHasta!,
                    icon: Icons.access_time_filled_outlined,
                    isDark: isDark,
                    onTap: () => _pickHora(false, false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _Field(
              controller: _nombreUbicDestinoCtrl,
              hint: 'Nombre del lugar (ej: Centro de Distribución)',
              icon: Icons.business_outlined,
              isDark: isDark,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _cpDestinoCtrl,
                    hint: 'Código postal',
                    icon: Icons.markunread_mailbox_outlined,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _contactoDestinoNombreCtrl,
                    hint: 'Contacto (nombre)',
                    icon: Icons.person_outline,
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _Field(
                    controller: _contactoDestinoTelCtrl,
                    hint: 'Teléfono',
                    icon: Icons.phone_outlined,
                    isDark: isDark,
                    keyboardType: TextInputType.phone,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),
            _SectionLabel('Precio Ofertado', isDark),
            const SizedBox(height: 8),
            _Field(
              controller: _precioCtrl,
              hint: 'Ej: 15000.00',
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

            // ── Ubicación detallada ──────────────────────────────────────
            

            

            // ── Opciones de equipo — desde BD ────────────────────────────
            const SizedBox(height: 24),
            _SectionLabel('Opciones de Equipo', isDark),
            const SizedBox(height: 8),
            noms.loading
                ? const SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: noms.opcionesEquipoManejo.map((op) {
                      final sel = _opcionesEquipoSelIds.contains(op.id);
                      return FilterChip(
                        label: Text(op.nombre,
                            style: TextStyle(
                                fontSize: 12,
                                color: sel
                                    ? Colors.white
                                    : (isDark
                                        ? Colors.white70
                                        : Colors.grey[700]))),
                        selected: sel,
                        selectedColor: AppTheme.primaryColor,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : Colors.grey.withValues(alpha: 0.1),
                        checkmarkColor: Colors.white,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _opcionesEquipoSelIds.add(op.id);
                          } else {
                            _opcionesEquipoSelIds.remove(op.id);
                          }
                        }),
                      );
                    }).toList(),
                  ),

            // ── Clasificación de mercancía (Commodity) — desde BD ────────
            const SizedBox(height: 24),
            _SectionLabel('Clasificación de Mercancía', isDark),
            const SizedBox(height: 8),
            noms.loading
                ? const SizedBox(
                    height: 4,
                    child: LinearProgressIndicator(),
                  )
                : DropdownButtonFormField<int>(
                    value: _commodityNomId,
                    decoration: InputDecoration(
                      hintText: 'Tipo de producto (commodity)',
                      prefixIcon:
                          const Icon(Icons.inventory_2_outlined, size: 18),
                      hintStyle: TextStyle(
                          color:
                              isDark ? Colors.white38 : Colors.grey[500]),
                    ),
                    dropdownColor:
                        isDark ? const Color(0xFF2A2D3E) : Colors.white,
                    style: TextStyle(
                        color: isDark
                            ? Colors.white
                            : const Color(0xFF1A1D27),
                        fontSize: 14),
                    items: noms.commodities
                        .map((c) => DropdownMenuItem<int>(
                              value: c.id,
                              child: Text(c.nombre),
                            ))
                        .toList(),
                    onChanged: (v) =>
                        setState(() => _commodityNomId = v),
                  ),

            // ── Números de referencia ────────────────────────────────────
            const SizedBox(height: 24),
            _SectionLabel('Números de Referencia', isDark),
            const SizedBox(height: 8),
            _Field(
              controller: _refNumCtrl,
              hint: 'Ej: REF-001, PO-4521 (separados por coma)',
              icon: Icons.tag_outlined,
              isDark: isDark,
            ),

            // ── Privacidad ───────────────────────────────────────────────
            const SizedBox(height: 24),
            _SectionLabel('Visibilidad de la Carga', isDark),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _esPrivada,
              onChanged: (v) => setState(() {
                _esPrivada = v;
                if (!v) _horasAnticipacionPublica = null;
              }),
              title: Text('Carga privada',
                  style: TextStyle(color: textPrimary, fontSize: 14)),
              subtitle: Text(
                'Solo visible para carriers de tu red',
                style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.white38 : Colors.grey[500]),
              ),
              activeColor: AppTheme.primaryColor,
              contentPadding: EdgeInsets.zero,
            ),
            if (_esPrivada) ...
              [
                const SizedBox(height: 8),
                DropdownButtonFormField<int>(
                  value: _horasAnticipacionPublica,
                  decoration: InputDecoration(
                    hintText: 'Horas antes de hacer pública automáticamente',
                    prefixIcon: const Icon(Icons.timer_outlined, size: 18),
                    hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey[500]),
                  ),
                  dropdownColor:
                      isDark ? const Color(0xFF2A2D3E) : Colors.white,
                  style: TextStyle(
                      color: isDark ? Colors.white : const Color(0xFF1A1D27),
                      fontSize: 14),
                  items: const [
                    DropdownMenuItem(value: 24, child: Text('24 horas')),
                    DropdownMenuItem(value: 48, child: Text('48 horas')),
                    DropdownMenuItem(value: 72, child: Text('72 horas')),
                    DropdownMenuItem(value: 0,  child: Text('Siempre privada')),
                  ],
                  onChanged: (v) =>
                      setState(() => _horasAnticipacionPublica = v),
                ),
              ],

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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<CargaProvider>();
      p.loadOfertasCarga(widget.carga.id);
      p.loadHistorialEstados(widget.carga.id);
    });
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
          // Estado badge
          Row(
            children: [
              _EstadoBadge(estado: carga.estado),
              const SizedBox(width: 8),
              _EstadoBadge(
                  estado: carga.tipoLabel,
                  color: AppTheme.primaryColor),
              const SizedBox(width: 8),
              _ShipperPrioridadBadge(prioridad: carga.prioridad),
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
          CargaMercanciaEquipoSection(
            carga: carga,
            isDark: isDark,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            precioLabel: 'Precio ofertado',
          ),

          // ── Contacto en origen ─────────────────────────────────────────
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

          // ── Contacto en destino ────────────────────────────────────────
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
                    if (carga.cpDestino != null) 'CP: ${carga.cpDestino}',
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

          // ── Referencia y privacidad ────────────────────────────────────
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

          /* const SizedBox(height: 20),
          Text(
            'Ofertas recibidas',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: textPrimary,
            ),
          ), */
          /* const SizedBox(height: 10),

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

           */const SizedBox(height: 24),

          // ── Acciones del shipper ────────────────────────────────────────
          if (carga.estado == 'publicada' ||
              carga.estado == 'ofertada') ...
            [
              ElevatedButton.icon(
                onPressed: provider.actionLoading
                    ? null
                    : () => _marcarComoTomada(context, carga),
                icon: const Icon(Icons.how_to_reg_outlined),
                label: const Text('Marcar como Tomada'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: provider.actionLoading
                    ? null
                    : () => _cancelarCarga(context, carga.id),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancelar Carga'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.error,
                  side: BorderSide(color: AppTheme.error),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          if (carga.estado == 'completada_carrier')
            ElevatedButton.icon(
              onPressed: provider.actionLoading
                  ? null
                  : () => _confirmarCompletada(context, carga.id),
              icon: const Icon(Icons.check_circle_outlined),
              label: const Text('Confirmar Completada'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),

          // ── Historial de estados ───────────────────────────────────────
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
            _HistorialTimeline(
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
    try {
      await context
          .read<CargaProvider>()
          .loadOfertasCarga(oferta.cargaId);
    } catch (_) {}
  }

  Future<void> _marcarComoTomada(
      BuildContext context, CargaModel carga) async {
    final carrier = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _SeleccionarCarrierDialog(isDark:
          context.read<ThemeProvider>().isDark),
    );
    if (carrier == null || !mounted) return;
    final driverId = carrier['id'] as int?;
    final carrierUuid = carrier['uuid'] as String?;
    if (driverId == null || carrierUuid == null) {
      _snack('Carrier no válido: sin id o uuid', false);
      return;
    }
    final confirmed = await _confirm(
      context,
      '¿Marcar carga como Tomada?',
      'Se asignará a ${carrier['name'] ?? 'el carrier seleccionado'} y quedará oculta del listado público.',
    );
    if (!confirmed || !mounted) return;
    final shipperUuid =
        context.read<AuthProvider>().user?.id;
    final ok = await context.read<CargaProvider>().marcarComoTomada(
          carga.id,
          carrierDriverId: driverId,
          carrierUuid: carrierUuid,
          shipperUuid: shipperUuid,
        );
    if (!mounted) return;
    _snack(
        ok ? 'Carga marcada como Tomada' : context.read<CargaProvider>().error,
        ok);
    if (ok) Navigator.pop(context);
  }

  Future<void> _confirmarCompletada(
      BuildContext context, int cargaId) async {
    final confirmed = await _confirm(
      context,
      '¿Confirmar carga Completada?',
      'Esto cerrará el ciclo de la carga definitivamente.',
    );
    if (!confirmed || !mounted) return;
    final shipperUuid =
        context.read<AuthProvider>().user?.id;
    final ok = await context
        .read<CargaProvider>()
        .completarCargaShipper(cargaId, shipperUuid: shipperUuid);
    if (!mounted) return;
    _snack(
        ok ? 'Carga completada' : context.read<CargaProvider>().error, ok);
    if (ok) Navigator.pop(context);
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

class _ShipperPrioridadBadge extends StatelessWidget {
  final String prioridad;
  const _ShipperPrioridadBadge({required this.prioridad});

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
      case 'tomada':
        return Colors.indigo;
      case 'completada_carrier':
        return Colors.cyan;
      case 'entregada':
      case 'completada':
        return Colors.teal;
      case 'cancelada':
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
// Historial de estados – timeline widget
// ──────────────────────────────────────────────────────────────────────────────

class _HistorialTimeline extends StatelessWidget {
  final List<EstadoCargaModel> historial;
  final bool isDark;
  final Color textPrimary;
  final Color textSecondary;

  const _HistorialTimeline({
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
    return '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}  '
        '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
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
                        color: color,
                        shape: BoxShape.circle,
                      ),
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
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _fmt(e.createdAt),
                        style: TextStyle(fontSize: 11, color: textSecondary),
                      ),
                      if (e.motivo != null && e.motivo!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            e.motivo!,
                            style:
                                TextStyle(fontSize: 11, color: textSecondary),
                          ),
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
// Seleccionar Carrier Dialog – lista de carriers del directorio
// ──────────────────────────────────────────────────────────────────────────────

class _SeleccionarCarrierDialog extends StatefulWidget {
  final bool isDark;
  const _SeleccionarCarrierDialog({required this.isDark});

  @override
  State<_SeleccionarCarrierDialog> createState() =>
      _SeleccionarCarrierDialogState();
}

class _SeleccionarCarrierDialogState
    extends State<_SeleccionarCarrierDialog> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _carriers = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(_filter);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_filter);
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await _supabase
          .schema('muevete')
          .from('drivers')
          .select('id, uuid, name, telefono, categoria, kyc, pais, province')
          .eq('tipo_usuario', 'carrier_carga')
          .order('name', ascending: true);
      if (mounted) {
        setState(() {
          _carriers = List<Map<String, dynamic>>.from(data as List);
          _filtered = _carriers;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _filter() {
    final q = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      _filtered = q.isEmpty
          ? _carriers
          : _carriers
              .where((c) =>
                  (c['name'] as String? ?? '').toLowerCase().contains(q))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final bg = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary = isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary = isDark ? Colors.white60 : Colors.grey[600]!;

    return Dialog(
      backgroundColor: bg,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520, maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Text(
                'Seleccionar Carrier',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchCtrl,
                style: TextStyle(color: textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Buscar por nombre...',
                  prefixIcon:
                      const Icon(Icons.search, size: 18),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                      vertical: 10, horizontal: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No se encontraron carriers.',
                            style: TextStyle(color: textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          itemCount: _filtered.length,
                          separatorBuilder: (_, __) =>
                              Divider(height: 1, color:
                                  isDark ? AppTheme.darkBorder : Colors.grey[200]),
                          itemBuilder: (_, i) {
                            final c = _filtered[i];
                            final hasUuid = c['uuid'] != null;
                            return ListTile(
                              dense: true,
                              leading: CircleAvatar(
                                backgroundColor:
                                    AppTheme.primaryColor.withValues(alpha: 0.12),
                                radius: 18,
                                child: Text(
                                  (c['name'] as String? ?? '?')
                                      .substring(0, 1)
                                      .toUpperCase(),
                                  style: TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(
                                c['name'] as String? ?? '—',
                                style: TextStyle(
                                    color: textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13),
                              ),
                              subtitle: Text(
                                [
                                  if (c['categoria'] != null)
                                    c['categoria'] as String,
                                  if (c['pais'] != null)
                                    c['pais'] as String,
                                  if (!hasUuid) '⚠ sin UUID',
                                ].join(' · '),
                                style: TextStyle(
                                    color: textSecondary, fontSize: 11),
                              ),
                              trailing: c['kyc'] == true
                                  ? const Icon(Icons.verified,
                                      color: Colors.green, size: 16)
                                  : null,
                              onTap: hasUuid
                                  ? () => Navigator.pop(context, c)
                                  : null,
                              enabled: hasUuid,
                            );
                          },
                        ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

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
