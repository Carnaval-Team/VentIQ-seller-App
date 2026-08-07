import 'dart:async';
import 'package:flutter/material.dart';
import '../models/mesa.dart';
import '../services/mesa_service.dart';
import '../services/store_config_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/mesa_form_dialog.dart';

/// Versión web de la pantalla de mesas (modo restaurante).
///
/// Reaprovecha toda la lógica de datos de [MesasScreen] pero con un layout
/// pensado para pantallas anchas: header de métricas centrado con ancho
/// máximo, buscador + filtros de zona en una barra amplia, y una grilla
/// responsive de tarjetas grandes con efecto hover. Mantiene la paleta
/// (#4A90E2) y la semántica de estado por color (verde libre / ámbar ocupada
/// / rojo llena / gris inactiva).
class MesasWebScreen extends StatefulWidget {
  const MesasWebScreen({Key? key}) : super(key: key);

  @override
  State<MesasWebScreen> createState() => _MesasWebScreenState();
}

class _MesasWebScreenState extends State<MesasWebScreen>
    with WidgetsBindingObserver {
  final MesaService _mesaService = MesaService();
  final TextEditingController _searchController = TextEditingController();

  static const Color _primary = Color(0xFF4A90E2);
  static const double _maxContentWidth = 1400;

  List<Mesa> _mesas = [];
  MesasResumen _resumen = MesasResumen.empty();
  bool _loading = true;
  String? _zonaFiltro;
  String _busqueda = '';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      if (_busqueda != _searchController.text) {
        setState(() => _busqueda = _searchController.text);
      }
    });
    _loadAll();
    _startPolling();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollingTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAll(silent: true);
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) _loadAll(silent: true);
    });
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final results = await Future.wait([
        _mesaService.listMesasWithStats(),
        _mesaService.getResumenMesas(),
      ]);
      if (!mounted) return;
      setState(() {
        _mesas = results[0] as List<Mesa>;
        _resumen = results[1] as MesasResumen;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error cargando mesas: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _zonasDisponibles {
    final set = <String>{};
    for (final m in _mesas) {
      final z = m.zona?.trim();
      if (z != null && z.isNotEmpty) set.add(z);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<Mesa> get _mesasFiltradas {
    return _mesas.where((m) {
      if (_zonaFiltro != null && m.zona != _zonaFiltro) return false;
      if (_busqueda.trim().isNotEmpty) {
        final q = _busqueda.trim().toLowerCase();
        if (!m.numero.toLowerCase().contains(q) &&
            !(m.zona?.toLowerCase().contains(q) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  // ----------------------------------------------------------------------
  // Acciones
  // ----------------------------------------------------------------------

  Future<void> _openCreateDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => MesaFormDialog(zonasSugeridas: _zonasDisponibles),
    );
    if (result == true) {
      _snack('✅ Mesa creada', Colors.green);
      _loadAll();
    }
  }

  Future<void> _openEditDialog(Mesa mesa) async {
    final result = await showDialog<bool>(
      context: context,
      builder:
          (_) => MesaFormDialog(mesa: mesa, zonasSugeridas: _zonasDisponibles),
    );
    if (result == true) {
      _snack('✅ Mesa actualizada', Colors.green);
      _loadAll();
    }
  }

  Future<void> _toggleActiva(Mesa mesa) async {
    try {
      await _mesaService.updateMesa(idMesa: mesa.id, activa: !mesa.activa);
      _loadAll();
    } catch (e) {
      _snack('❌ $e', Colors.red);
    }
  }

  Future<void> _confirmDelete(Mesa mesa) async {
    final hasOpenOrders = mesa.ordenesAbiertas > 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              hasOpenOrders
                  ? 'No puedes eliminar esta mesa'
                  : 'Eliminar mesa ${mesa.numero}',
            ),
            content: Text(
              hasOpenOrders
                  ? 'Esta mesa tiene ${mesa.ordenesAbiertas} cuenta(s) abierta(s). Cierra o cobra las cuentas antes de eliminar.'
                  : '¿Confirmas eliminar la mesa "${mesa.numero}"?\n\nSi tiene órdenes históricas se marcará como inactiva (preservando histórico).',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              if (!hasOpenOrders)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                  child: const Text('Eliminar'),
                ),
            ],
          ),
    );

    if (confirm == true) {
      try {
        final hardDeleted = await _mesaService.deleteMesa(mesa.id);
        if (!mounted) return;
        _snack(
          hardDeleted
              ? '🗑️ Mesa eliminada'
              : '⚠️ Mesa marcada como inactiva (tiene histórico)',
          hardDeleted ? Colors.green : Colors.orange,
        );
        _loadAll();
      } catch (e) {
        if (!mounted) return;
        _snack('❌ $e', Colors.red);
      }
    }
  }

  /// Menú de acciones anclado al botón "más" de la tarjeta (natural en web).
  Future<void> _showMesaMenu(Mesa mesa, Offset globalPosition) async {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        globalPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: const [
              Icon(Icons.edit, color: _primary, size: 20),
              SizedBox(width: 12),
              Text('Editar mesa'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle',
          child: Row(
            children: [
              Icon(
                mesa.activa ? Icons.visibility_off : Icons.visibility,
                color: Colors.orange,
                size: 20,
              ),
              const SizedBox(width: 12),
              Text(mesa.activa ? 'Marcar inactiva' : 'Marcar activa'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red, size: 20),
              SizedBox(width: 12),
              Text('Eliminar mesa'),
            ],
          ),
        ),
      ],
    );

    if (!mounted) return;
    switch (selected) {
      case 'edit':
        _openEditDialog(mesa);
        break;
      case 'toggle':
        _toggleActiva(mesa);
        break;
      case 'delete':
        _confirmDelete(mesa);
        break;
    }
  }

  void _openMesaDetail(Mesa mesa) {
    Navigator.pushNamed(
      context,
      '/mesa-detail',
      arguments: mesa.id,
    ).then((_) => _loadAll(silent: true));
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ----------------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: _primary,
        elevation: 2,
        shadowColor: _primary.withOpacity(0.3),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Mesas y Comensales - VentIQ POS',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white, size: 26),
            tooltip: 'Refrescar',
            onPressed: () => _loadAll(),
          ),
          const SizedBox(width: 8),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white, size: 28),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      endDrawer: const AppDrawer(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        backgroundColor: _primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Nueva mesa',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        color: _primary,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _maxContentWidth),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _buildHeader()),
                SliverToBoxAdapter(child: _buildFilters()),
                if (_loading)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: CircularProgressIndicator(color: _primary),
                    ),
                  )
                else if (_mesasFiltradas.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _buildEmptyState(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 120),
                    sliver: SliverLayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.crossAxisExtent;
                        return SliverGrid(
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: _crossAxisCount(width),
                            mainAxisSpacing: 20,
                            crossAxisSpacing: 20,
                            childAspectRatio: 0.92,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (ctx, i) => _MesaWebCard(
                              mesa: _mesasFiltradas[i],
                              onTap: () => _openMesaDetail(_mesasFiltradas[i]),
                              onMenu: (pos) =>
                                  _showMesaMenu(_mesasFiltradas[i], pos),
                            ),
                            childCount: _mesasFiltradas.length,
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  int _crossAxisCount(double width) {
    if (width > 1250) return 6;
    if (width > 1050) return 5;
    if (width > 820) return 4;
    if (width > 600) return 3;
    return 2;
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        if (StoreConfigService.modoRestauranteSync) {
          _loadAll();
        } else {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/categories',
            (route) => false,
          );
        }
        break;
      case 1:
        Navigator.pushNamed(context, '/preorder');
        break;
      case 2:
        Navigator.pushNamed(context, '/orders');
        break;
      case 3:
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  // ----- subwidgets -----

  Widget _buildHeader() {
    final top = _resumen.mesaTopComensales;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 20, 24, 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _primary.withOpacity(0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.restaurant_menu, color: Colors.white, size: 26),
              SizedBox(width: 10),
              Text(
                'Panel de mesas',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              _buildMetricCard(
                icon: Icons.table_bar,
                label: 'Total',
                value: '${_resumen.total}',
              ),
              _buildMetricCard(
                icon: Icons.event_seat,
                label: 'Ocupadas',
                value: '${_resumen.ocupadas}',
                valueColor: Colors.orange.shade800,
              ),
              _buildMetricCard(
                icon: Icons.check_circle_outline,
                label: 'Libres',
                value: '${_resumen.libres}',
                valueColor: Colors.green.shade700,
              ),
              _buildMetricCard(
                icon: Icons.receipt_long,
                label: 'Pendientes',
                value: '${_resumen.ordenesPendientesTotal}',
                valueColor: Colors.blue.shade700,
              ),
            ],
          ),
          if (top != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Mesa con más actividad: ${top.numero} — ${top.comensales} cuenta(s) activa(s)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    final color = valueColor ?? _primary;
    return Container(
      width: 168,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 22, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    final zonas = _zonasDisponibles;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por número o zona...',
                prefixIcon: const Icon(Icons.search, color: _primary),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primary, width: 1.5),
                ),
                suffixIcon:
                    _searchController.text.isNotEmpty
                        ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () => _searchController.clear(),
                        )
                        : null,
              ),
            ),
          ),
          if (zonas.isNotEmpty) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildZonaChip(null, 'Todas'),
                for (final z in zonas) _buildZonaChip(z, z),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZonaChip(String? value, String label) {
    final isSelected = _zonaFiltro == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 13)),
      selected: isSelected,
      onSelected: (_) => setState(() => _zonaFiltro = value),
      selectedColor: _primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF1F2937),
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(
        color: isSelected ? _primary : Colors.grey[300]!,
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilter = _zonaFiltro != null || _busqueda.isNotEmpty;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter ? Icons.search_off : Icons.table_restaurant_outlined,
              size: 88,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 20),
            Text(
              hasFilter
                  ? 'No se encontraron mesas con esos filtros'
                  : 'Aún no tienes mesas creadas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Prueba a limpiar los filtros'
                  : 'Toca "Nueva mesa" para crear la primera',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _zonaFiltro = null;
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.clear),
                label: const Text('Limpiar filtros'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Tarjeta de mesa optimizada para web: más grande, con hover elevado y un
/// botón de acciones (menú) explícito en lugar de long-press.
class _MesaWebCard extends StatefulWidget {
  final Mesa mesa;
  final VoidCallback onTap;
  final void Function(Offset globalPosition) onMenu;

  const _MesaWebCard({
    required this.mesa,
    required this.onTap,
    required this.onMenu,
  });

  @override
  State<_MesaWebCard> createState() => _MesaWebCardState();
}

class _MesaWebCardState extends State<_MesaWebCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final mesa = widget.mesa;

    // Paleta por estado (misma semántica que la vista móvil).
    final Color accent;
    final Color bgSoft;
    final String estadoLabel;
    final IconData estadoIcon;

    if (!mesa.activa) {
      accent = Colors.grey.shade500;
      bgSoft = Colors.grey.shade50;
      estadoLabel = 'INACTIVA';
      estadoIcon = Icons.visibility_off_outlined;
    } else if (mesa.ordenesAbiertas == 0) {
      accent = const Color(0xFF10B981);
      bgSoft = const Color(0xFFECFDF5);
      estadoLabel = 'LIBRE';
      estadoIcon = Icons.check_circle_outline;
    } else if (mesa.ordenesAbiertas == 1) {
      accent = const Color(0xFFF59E0B);
      bgSoft = const Color(0xFFFFFBEB);
      estadoLabel = 'OCUPADA';
      estadoIcon = Icons.local_dining;
    } else {
      accent = const Color(0xFFEF4444);
      bgSoft = const Color(0xFFFEF2F2);
      estadoLabel = 'LLENA';
      estadoIcon = Icons.event_busy;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        transform: _hovered
            ? (Matrix4.identity()..translate(0.0, -4.0))
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: accent.withOpacity(_hovered ? 0.22 : 0.10),
              blurRadius: _hovered ? 18 : 8,
              offset: Offset(0, _hovered ? 8 : 3),
            ),
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
          border: Border.all(
            color: accent.withOpacity(_hovered ? 0.5 : 0.25),
            width: _hovered ? 1.5 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Banner de estado
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: accent,
                  child: Row(
                    children: [
                      Icon(estadoIcon, size: 15, color: Colors.white),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          estadoLabel,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                      if (mesa.ordenesAbiertas > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '${mesa.ordenesAbiertas}',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // Cuerpo: número dominante
                Expanded(
                  child: Container(
                    width: double.infinity,
                    color: bgSoft,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.table_restaurant,
                          size: 40,
                          color: accent.withOpacity(0.45),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          mesa.numero,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF1F2937),
                            letterSpacing: -0.5,
                            height: 1.0,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (mesa.zona != null && mesa.zona!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.location_on_outlined,
                                  size: 13,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    mesa.zona!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Pie: capacidad + histórico + menú
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Colors.grey[200]!)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.people_alt_outlined,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        '${mesa.capacidad}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (mesa.ordenesCompletadasHistoricas > 0) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.receipt_long,
                            size: 13, color: Colors.grey[500]),
                        const SizedBox(width: 3),
                        Text(
                          '${mesa.ordenesCompletadasHistoricas}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                      const Spacer(),
                      Builder(
                        builder: (btnContext) => InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            final box =
                                btnContext.findRenderObject() as RenderBox;
                            final pos =
                                box.localToGlobal(box.size.center(Offset.zero));
                            widget.onMenu(pos);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.more_vert,
                              size: 18,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
