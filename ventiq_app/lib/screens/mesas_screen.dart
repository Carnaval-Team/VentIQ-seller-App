import 'dart:async';
import 'package:flutter/material.dart';
import '../models/mesa.dart';
import '../services/mesa_service.dart';
import '../services/store_config_service.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/mesa_form_dialog.dart';

/// Pantalla principal del modo restaurante: grilla de mesas + métricas globales.
///
/// Patrón de UI: gradient header con métricas (estilo orders_screen), grilla
/// responsive con tarjetas coloreadas por estado (libre/ocupada/saturada),
/// filtro por zona, búsqueda por número, FAB para crear, long-press para
/// editar/eliminar.
class MesasScreen extends StatefulWidget {
  const MesasScreen({Key? key}) : super(key: key);

  @override
  State<MesasScreen> createState() => _MesasScreenState();
}

class _MesasScreenState extends State<MesasScreen> with WidgetsBindingObserver {
  final MesaService _mesaService = MesaService();
  final TextEditingController _searchController = TextEditingController();

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
      _loadAll();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Mesa creada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Mesa actualizada'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      _loadAll();
    }
  }

  Future<void> _confirmDelete(Mesa mesa) async {
    final hasOpenOrders = mesa.ordenesAbiertas > 0;
    final confirm = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hardDeleted
                  ? '🗑️ Mesa eliminada'
                  : '⚠️ Mesa marcada como inactiva (tiene histórico)',
            ),
            backgroundColor: hardDeleted ? Colors.green : Colors.orange,
          ),
        );
        _loadAll();
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showMesaActions(Mesa mesa) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder:
          (ctx) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.edit, color: Color(0xFF4A90E2)),
                  title: Text('Editar "${mesa.numero}"'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _openEditDialog(mesa);
                  },
                ),
                ListTile(
                  leading: Icon(
                    mesa.activa ? Icons.visibility_off : Icons.visibility,
                    color: Colors.orange,
                  ),
                  title: Text(
                    mesa.activa ? 'Marcar inactiva' : 'Marcar activa',
                  ),
                  onTap: () async {
                    Navigator.pop(ctx);
                    try {
                      await _mesaService.updateMesa(
                        idMesa: mesa.id,
                        activa: !mesa.activa,
                      );
                      _loadAll();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('❌ $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: const Text('Eliminar mesa'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmDelete(mesa);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
    );
  }

  void _openMesaDetail(Mesa mesa) {
    Navigator.pushNamed(
      context,
      '/mesa-detail',
      arguments: mesa.id,
    ).then((_) => _loadAll(silent: true));
  }

  // ----------------------------------------------------------------------
  // Build
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Mesas y Comensales',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Refrescar',
            onPressed: () => _loadAll(),
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
      ),
      endDrawer: const AppDrawer(),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildFilters()),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_mesasFiltradas.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyState(),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 170,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.82,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildMesaCard(_mesasFiltradas[i]),
                    childCount: _mesasFiltradas.length,
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        backgroundColor: const Color(0xFF4A90E2),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Nueva mesa', style: TextStyle(color: Colors.white)),
      ),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0, // No coincide con ninguna pestaña fija; usamos Home
        onTap: _onBottomNavTap,
      ),
    );
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0:
        // Home en modo restaurante = esta misma pantalla → solo refrescar.
        // Si por alguna razón modo restaurante se desactivó, ir a categories.
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4A90E2), Color(0xFF357ABD)],
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMetricChip(
                  icon: Icons.table_bar,
                  label: 'Total',
                  value: '${_resumen.total}',
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                _buildMetricChip(
                  icon: Icons.event_seat,
                  label: 'Ocupadas',
                  value: '${_resumen.ocupadas}',
                  color: Colors.orange.shade100,
                  valueColor: Colors.orange.shade900,
                ),
                const SizedBox(width: 8),
                _buildMetricChip(
                  icon: Icons.check_circle_outline,
                  label: 'Libres',
                  value: '${_resumen.libres}',
                  color: Colors.green.shade100,
                  valueColor: Colors.green.shade900,
                ),
                const SizedBox(width: 8),
                _buildMetricChip(
                  icon: Icons.receipt_long,
                  label: 'Pendientes',
                  value: '${_resumen.ordenesPendientesTotal}',
                  color: Colors.blue.shade100,
                  valueColor: Colors.blue.shade900,
                ),
              ],
            ),
          ),
          if (top != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Text('🔥', style: TextStyle(fontSize: 14)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mesa con más actividad: ${top.numero} — ${top.comensales} cuenta(s) activa(s)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
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

  Widget _buildMetricChip({
    required IconData icon,
    required String label,
    required String value,
    Color color = Colors.white,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: valueColor ?? const Color(0xFF4A90E2)),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: (valueColor ?? const Color(0xFF4A90E2)).withOpacity(
                    0.8,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? const Color(0xFF4A90E2),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Buscador
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Buscar por número o zona...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchController.clear(),
                      )
                      : null,
            ),
          ),
          if (zonas.isNotEmpty) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildZonaChip(null, 'Todas'),
                  for (final z in zonas) ...[
                    const SizedBox(width: 6),
                    _buildZonaChip(z, z),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildZonaChip(String? value, String label) {
    final isSelected = _zonaFiltro == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: isSelected,
      onSelected: (_) => setState(() => _zonaFiltro = value),
      selectedColor: const Color(0xFF4A90E2),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : const Color(0xFF1F2937),
        fontWeight: FontWeight.w500,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: Colors.grey[300]!),
    );
  }

  /// Tarjeta de mesa rediseñada — estilo "panel de control de restaurante":
  ///  - Cabecera coloreada (estado) con icono + label.
  ///  - Cuerpo grande con el número de la mesa centrado (lectura instantánea).
  ///  - Pie con métricas (capacidad + cuentas abiertas + histórico).
  ///  - Sombra sutil + radios suaves; el accent color pinta el borde lateral
  ///    como "ribbon" para identificación periférica rápida.
  Widget _buildMesaCard(Mesa mesa) {
    // Paleta por estado
    final Color accent;        // color principal del estado
    final Color bgSoft;        // fondo suave para el body
    final String estadoLabel;
    final IconData estadoIcon;

    if (!mesa.activa) {
      accent = Colors.grey.shade500;
      bgSoft = Colors.grey.shade50;
      estadoLabel = 'Inactiva';
      estadoIcon = Icons.visibility_off_outlined;
    } else if (mesa.ordenesAbiertas == 0) {
      accent = const Color(0xFF10B981); // verde esmeralda
      bgSoft = const Color(0xFFECFDF5);
      estadoLabel = 'LIBRE';
      estadoIcon = Icons.check_circle_outline;
    } else if (mesa.ordenesAbiertas == 1) {
      accent = const Color(0xFFF59E0B); // ámbar
      bgSoft = const Color(0xFFFFFBEB);
      estadoLabel = 'OCUPADA';
      estadoIcon = Icons.local_dining;
    } else {
      accent = const Color(0xFFEF4444); // rojo
      bgSoft = const Color(0xFFFEF2F2);
      estadoLabel = 'LLENA';
      estadoIcon = Icons.event_busy;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openMesaDetail(mesa),
        onLongPress: () => _showMesaActions(mesa),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: accent.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
            border: Border.all(color: accent.withOpacity(0.25), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Banner superior con estado
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                color: accent,
                child: Row(
                  children: [
                    Icon(estadoIcon, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        estadoLabel,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    if (mesa.ordenesAbiertas > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
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
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Cuerpo: número de mesa dominante
              Expanded(
                child: Container(
                  color: bgSoft,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.table_restaurant,
                        size: 28,
                        color: accent.withOpacity(0.4),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mesa.numero,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1F2937),
                          letterSpacing: -0.5,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mesa.zona != null && mesa.zona!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            mesa.zona!,
                            style: TextStyle(
                              fontSize: 10,
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
              ),
              // Pie con métricas
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey[200]!)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.people_alt_outlined,
                        size: 12, color: Colors.grey[600]),
                    const SizedBox(width: 3),
                    Text(
                      '${mesa.capacidad}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[700],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (mesa.ordenesCompletadasHistoricas > 0) ...[
                      Icon(Icons.receipt_long,
                          size: 11, color: Colors.grey[500]),
                      const SizedBox(width: 2),
                      Text(
                        '${mesa.ordenesCompletadasHistoricas}',
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasFilter = _zonaFiltro != null || _busqueda.isNotEmpty;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasFilter ? Icons.search_off : Icons.table_restaurant_outlined,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter
                  ? 'No se encontraron mesas con esos filtros'
                  : 'Aún no tienes mesas creadas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasFilter
                  ? 'Prueba a limpiar los filtros'
                  : 'Toca "Nueva mesa" para crear la primera',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            if (hasFilter) ...[
              const SizedBox(height: 12),
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
