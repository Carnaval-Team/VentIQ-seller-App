import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_theme.dart';
import '../../models/carga_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/carga_provider.dart';
import '../../providers/theme_provider.dart';

class DispatcherHomeScreen extends StatefulWidget {
  const DispatcherHomeScreen({super.key});

  @override
  State<DispatcherHomeScreen> createState() =>
      _DispatcherHomeScreenState();
}

class _DispatcherHomeScreenState extends State<DispatcherHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  // Fleet carriers managed by this dispatcher
  List<Map<String, dynamic>> _flota = [];
  bool _loadingFlota = false;

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

  Future<void> _load() async {
    await Future.wait([
      _loadFlota(),
      _loadCargas(),
    ]);
  }

  Future<void> _loadFlota() async {
    setState(() => _loadingFlota = true);
    try {
      final authProvider = context.read<AuthProvider>();
      // dispatcher_id on muevete.drivers is a BIGINT FK → muevete.drivers(id)
      final dispatcherDriverId =
          authProvider.driverProfile?['id'] as int?;
      if (dispatcherDriverId == null) return;
      final data = await Supabase.instance.client
          .schema('muevete')
          .from('drivers')
          .select('id, name, telefono, estado')
          .eq('dispatcher_id', dispatcherDriverId);
      if (mounted) {
        setState(() => _flota = List<Map<String, dynamic>>.from(data));
      }
    } catch (_) {
      // Graceful: empty fleet on error
    } finally {
      if (mounted) setState(() => _loadingFlota = false);
    }
  }

  Future<void> _loadCargas() async {
    final ids = _flota.map((f) => f['id'] as int).toList();
    final provider = context.read<CargaProvider>();
    // Available loads for assignment
    await provider.loadCargasDisponibles();
    // Active loads of managed fleet
    if (ids.isNotEmpty) {
      await provider.loadCargasDispatcher(ids);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final auth = context.watch<AuthProvider>();
    final name =
        (auth.driverProfile?['name'] as String?) ?? 'Dispatcher';
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
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor:
              isDark ? Colors.white54 : Colors.grey[500],
          indicatorColor: AppTheme.primaryColor,
          tabs: const [
            Tab(icon: Icon(Icons.groups_outlined), text: 'Mi Flota'),
            Tab(
                icon: Icon(Icons.search_outlined),
                text: 'Asignar'),
            Tab(
                icon: Icon(Icons.track_changes_outlined),
                text: 'En Curso'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FlotaTab(
              flota: _flota,
              loading: _loadingFlota,
              onRefresh: _loadFlota),
          _AsignarCargaTab(flota: _flota),
          _CargasEnCursoTab(),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 1 – Mi Flota
// ──────────────────────────────────────────────────────────────────────────────

class _FlotaTab extends StatelessWidget {
  final List<Map<String, dynamic>> flota;
  final bool loading;
  final VoidCallback onRefresh;
  const _FlotaTab(
      {required this.flota,
      required this.loading,
      required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (flota.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.groups_outlined,
                  size: 64, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                'Sin transportistas en la flota',
                style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textPrimary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Los transportistas que te asignen como su dispatcher aparecerán aquí.',
                style:
                    TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: flota.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final driver = flota[i];
          final nombre =
              driver['name'] as String? ?? 'Transportista';
          final phone =
              driver['telefono'] as String? ?? '';
          final activo = driver['estado'] == true;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark
                      ? AppTheme.darkBorder
                      : Colors.grey[200]!),
            ),
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppTheme.primaryColor
                      .withValues(alpha: 0.15),
                  child: Text(
                    nombre.isNotEmpty
                        ? nombre[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                        color: AppTheme.primaryColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 18),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nombre,
                          style: GoogleFonts.plusJakartaSans(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: textPrimary)),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(phone,
                            style: TextStyle(
                                fontSize: 12,
                                color: textSecondary)),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (activo ? Colors.green : Colors.grey)
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color:
                            (activo ? Colors.green : Colors.grey)
                                .withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    activo ? 'Activo' : 'Inactivo',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color:
                            activo ? Colors.green : Colors.grey),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 2 – Asignar Carga
// ──────────────────────────────────────────────────────────────────────────────

class _AsignarCargaTab extends StatefulWidget {
  final List<Map<String, dynamic>> flota;
  const _AsignarCargaTab({required this.flota});

  @override
  State<_AsignarCargaTab> createState() => _AsignarCargaTabState();
}

class _AsignarCargaTabState extends State<_AsignarCargaTab> {
  CargaModel? _cargaSeleccionada;
  int? _carrierSeleccionado;

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    if (widget.flota.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Necesitas transportistas en tu flota para asignar cargas.',
            style: TextStyle(color: textSecondary, fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Step 1: Select carga
        _StepCard(
          isDark: isDark,
          step: '1',
          title: 'Seleccionar Carga Disponible',
          child: provider.loadingDisponibles
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  ))
              : provider.cargasDisponibles.isEmpty
                  ? Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No hay cargas disponibles en este momento.',
                        style: TextStyle(
                            color: textSecondary, fontSize: 13),
                      ),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        showCheckboxColumn: false,
                        columnSpacing: 12,
                        headingRowHeight: 36,
                        dataRowMinHeight: 44,
                        dataRowMaxHeight: 44,
                        headingRowColor: WidgetStateProperty.all(
                          isDark
                              ? AppTheme.darkBg
                              : Colors.grey[100],
                        ),
                        columns: [
                          DataColumn(
                              label: Text('Ruta',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: textSecondary))),
                          DataColumn(
                              label: Text('Tipo',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: textSecondary))),
                          DataColumn(
                              label: Text('Precio',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: textSecondary))),
                        ],
                        rows: provider.cargasDisponibles.map((c) {
                          final sel =
                              _cargaSeleccionada?.id == c.id;
                          return DataRow(
                            selected: sel,
                            onSelectChanged: (_) =>
                                setState(() =>
                                    _cargaSeleccionada = c),
                            color:
                                WidgetStateProperty.resolveWith(
                                    (states) {
                              if (states.contains(
                                  WidgetState.selected)) {
                                return AppTheme.primaryColor
                                    .withValues(alpha: 0.1);
                              }
                              return null;
                            }),
                            cells: [
                              DataCell(SizedBox(
                                width: 160,
                                child: Text(
                                  c.rutaCorta,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: textPrimary),
                                ),
                              )),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColor
                                      .withValues(alpha: 0.12),
                                  borderRadius:
                                      BorderRadius.circular(999),
                                ),
                                child: Text(
                                  c.tipoLabel,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.primaryColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              )),
                              DataCell(Text(
                                c.precioOfertado != null
                                    ? '\$${c.precioOfertado!.toStringAsFixed(0)}'
                                    : '—',
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

        const SizedBox(height: 16),

        // Step 2: Select carrier
        _StepCard(
          isDark: isDark,
          step: '2',
          title: 'Seleccionar Transportista',
          child: Column(
            children: widget.flota
                .map((driver) => _SeleccionableDriverTile(
                      driver: driver,
                      selected: _carrierSeleccionado ==
                          (driver['id'] as int?),
                      isDark: isDark,
                      onTap: () => setState(
                        () => _carrierSeleccionado =
                            driver['id'] as int?,
                      ),
                    ))
                .toList(),
          ),
        ),

        const SizedBox(height: 24),

        // Confirm
        if (_cargaSeleccionada != null &&
            _carrierSeleccionado != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color:
                      AppTheme.primaryColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Resumen de asignación',
                    style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: textPrimary)),
                const SizedBox(height: 8),
                Text(
                    '📦 Carga: ${_cargaSeleccionada!.rutaCorta}',
                    style: TextStyle(
                        fontSize: 13, color: textSecondary)),
                Text(
                    '🚛 Transportista: ${widget.flota.firstWhere((f) => f['id'] == _carrierSeleccionado)['name']}',
                    style: TextStyle(
                        fontSize: 13, color: textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: provider.actionLoading ? null : _asignar,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: provider.actionLoading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white))
                : Text('Asignar Carga',
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  Future<void> _asignar() async {
    if (_cargaSeleccionada == null || _carrierSeleccionado == null) {
      return;
    }
    final ok = await context.read<CargaProvider>().asignarCargaACarrier(
          _cargaSeleccionada!.id,
          _carrierSeleccionado!,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok ? 'Carga asignada con éxito' : 'Error al asignar'),
      backgroundColor: ok ? Colors.green[700] : AppTheme.error,
    ));
    if (ok) {
      setState(() {
        _cargaSeleccionada = null;
        _carrierSeleccionado = null;
      });
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Tab 3 – Cargas En Curso
// ──────────────────────────────────────────────────────────────────────────────

class _CargasEnCursoTab extends StatelessWidget {
  const _CargasEnCursoTab();

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final provider = context.watch<CargaProvider>();
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);

    if (provider.loadingMisCargas) {
      return const Center(child: CircularProgressIndicator());
    }

    final cargas = provider.cargasActivas;

    if (cargas.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.local_shipping_outlined,
                  size: 64, color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text('Sin cargas activas',
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPrimary),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(
                'Las cargas asignadas a tu flota aparecerán aquí.',
                style:
                    TextStyle(fontSize: 13, color: textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Group by estado
    final enCurso = cargas
        .where((c) =>
            c.estado == 'aceptada' || c.estado == 'en_transito')
        .toList();
    final entregadas = cargas
        .where((c) =>
            c.estado == 'entregada' || c.estado == 'completada')
        .toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (enCurso.isNotEmpty) ...[
          _SectionHeader('En Tránsito (${enCurso.length})',
              isDark: isDark),
          const SizedBox(height: 8),
          ...enCurso.map((c) => _DispatcherCargaCard(
                carga: c,
                isDark: isDark,
              )),
          const SizedBox(height: 16),
        ],
        if (entregadas.isNotEmpty) ...[
          _SectionHeader('Entregadas (${entregadas.length})',
              isDark: isDark),
          const SizedBox(height: 8),
          ...entregadas.map((c) => _DispatcherCargaCard(
                carga: c,
                isDark: isDark,
              )),
        ],
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Shared widgets
// ──────────────────────────────────────────────────────────────────────────────

class _StepCard extends StatelessWidget {
  final bool isDark;
  final String step;
  final String title;
  final Widget child;
  const _StepCard({
    required this.isDark,
    required this.step,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                isDark ? AppTheme.darkBorder : Colors.grey[200]!),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(step,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: textPrimary)),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _SeleccionableDriverTile extends StatelessWidget {
  final Map<String, dynamic> driver;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;
  const _SeleccionableDriverTile({
    required this.driver,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;
    final nombre = driver['name'] as String? ?? 'Transportista';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? AppTheme.primaryColor
                : isDark
                    ? AppTheme.darkBorder
                    : Colors.grey[300]!,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              color: selected
                  ? AppTheme.primaryColor
                  : textSecondary,
              size: 20,
            ),
            const SizedBox(width: 10),
            CircleAvatar(
              radius: 16,
              backgroundColor: AppTheme.primaryColor
                  .withValues(alpha: 0.15),
              child: Text(
                nombre.isNotEmpty ? nombre[0].toUpperCase() : '?',
                style: TextStyle(
                    color: AppTheme.primaryColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 14),
              ),
            ),
            const SizedBox(width: 10),
            Text(nombre,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textPrimary)),
          ],
        ),
      ),
    );
  }
}

class _DispatcherCargaCard extends StatelessWidget {
  final CargaModel carga;
  final bool isDark;
  const _DispatcherCargaCard(
      {required this.carga, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark ? AppTheme.darkCard : Colors.white;
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF1A1D27);
    final textSecondary =
        isDark ? Colors.white60 : Colors.grey[600]!;

    Color badgeColor;
    switch (carga.estado) {
      case 'aceptada':
        badgeColor = Colors.blue;
        break;
      case 'en_transito':
        badgeColor = Colors.orange;
        break;
      case 'entregada':
      case 'completada':
        badgeColor = Colors.green;
        break;
      default:
        badgeColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                isDark ? AppTheme.darkBorder : Colors.grey[200]!),
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
                      color: textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: badgeColor.withValues(alpha: 0.4)),
                ),
                child: Text(
                  carga.estadoLabel,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.local_shipping_outlined,
                  size: 13, color: textSecondary),
              const SizedBox(width: 4),
              Text(carga.tipoLabel,
                  style: TextStyle(
                      fontSize: 12, color: textSecondary)),
              if (carga.precioFinal != null ||
                  carga.precioOfertado != null) ...[
                const SizedBox(width: 12),
                Icon(Icons.attach_money_outlined,
                    size: 13, color: textSecondary),
                Text(
                    '\$${(carga.precioFinal ?? carga.precioOfertado)!.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontSize: 12, color: textSecondary)),
              ],
              if (carga.carrierDriverId != null) ...[
                const Spacer(),
                Icon(Icons.person_outline,
                    size: 13, color: textSecondary),
                const SizedBox(width: 3),
                Text('#${carga.carrierDriverId}',
                    style: TextStyle(
                        fontSize: 12, color: textSecondary)),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionHeader(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.plusJakartaSans(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.white70 : Colors.grey[700],
      ),
    );
  }
}
