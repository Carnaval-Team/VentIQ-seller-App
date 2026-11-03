import 'dart:async';
import 'package:flutter/material.dart';
import '../models/mesa.dart';
import '../services/mesa_cuenta_service.dart';
import '../theme/ventiq_home_theme.dart';
import '../services/mesa_service.dart';
import '../services/order_service.dart';
import '../services/sales_mode_service.dart';
import '../services/store_config_service.dart';
import '../utils/navigation_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_navigation.dart';
import '../widgets/mesa_form_dialog.dart';
import '../tutorial/tutorial_anchor.dart';
import '../tutorial/tutorial_flujos.dart';

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
  final MesaCuentaService _cuentaService = MesaCuentaService();
  final OrderService _orderService = OrderService();
  final TextEditingController _searchController = TextEditingController();

  List<Mesa> _mesas = [];
  MesasResumen get _resumen => MesasResumen.fromMesas(_mesas);
  bool _loading = true;
  bool _hasLoaded = false;
  String? _loadError;
  int _loadRequestId = 0;
  String? _zonaFiltro;
  String _busqueda = '';
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
    // Estar en la pantalla de mesas cierra cualquier venta de mostrador en
    // curso: a partir de aquí el contexto vuelve a ser el de mesas.
    SalesModeService.salirDeMostrador();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(() {
      if (_busqueda != _searchController.text) {
        setState(() => _busqueda = _searchController.text);
      }
    });
    _loadAll();
    _startPolling();
    // Un usuario de restaurante puede caer directo aquí tras el login: el
    // tutorial también arranca desde esta pantalla (una sola vez por modo).
    unawaited(TutorialAutoStart.intentar(context, restaurante: true));
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
      _startPolling();
    } else {
      _pollingTimer?.cancel();
    }
  }

  void _startPolling() {
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted && (ModalRoute.of(context)?.isCurrent ?? true)) {
        _loadAll(silent: true);
      }
    });
  }

  Future<void> _loadAll({bool silent = false}) async {
    if (!mounted) return;
    final requestId = ++_loadRequestId;
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final mesas = await _mesaService.listMesasWithStats(throwOnError: true);
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _mesas = mesas;
        _hasLoaded = true;
        _loadError = null;
        _loading = false;
      });
    } catch (e) {
      print('❌ Error cargando mesas: $e');
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _loading = false;
        _loadError =
            _hasLoaded
                ? 'No se pudo actualizar. Se muestran los últimos datos recibidos.'
                : 'No se pudieron cargar las mesas. Intenta actualizar.';
      });
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
          backgroundColor: VentiqHomeTheme.success,
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
          backgroundColor: VentiqHomeTheme.success,
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
                  style: TextButton.styleFrom(
                    foregroundColor: VentiqHomeTheme.danger,
                  ),
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
            backgroundColor:
                hardDeleted ? VentiqHomeTheme.success : VentiqHomeTheme.warning,
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
              color: VentiqHomeTheme.card,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(VentiqHomeTheme.radiusBlock),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: VentiqHomeTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: Row(
                      children: <Widget>[
                        const Icon(
                          Icons.table_restaurant_rounded,
                          size: 18,
                          color: VentiqHomeTheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Mesa ${mesa.numero}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.2,
                              color: VentiqHomeTheme.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          mesa.estadoTexto,
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: VentiqHomeTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.edit_rounded,
                      color: VentiqHomeTheme.primary,
                    ),
                    title: const Text(
                      'Editar mesa',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _openEditDialog(mesa);
                    },
                  ),
                  ListTile(
                    leading: Icon(
                      mesa.activa
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      color: VentiqHomeTheme.warning,
                    ),
                    title: Text(
                      mesa.activa ? 'Marcar inactiva' : 'Marcar activa',
                      style: const TextStyle(fontWeight: FontWeight.w600),
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
                              backgroundColor: VentiqHomeTheme.danger,
                            ),
                          );
                        }
                      }
                    },
                  ),
                  ListTile(
                    leading: const Icon(
                      Icons.delete_outline_rounded,
                      color: VentiqHomeTheme.danger,
                    ),
                    title: const Text(
                      'Eliminar mesa',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDelete(mesa);
                    },
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
    );
  }

  Future<void> _openMesaDetail(Mesa mesa) async {
    // Si la mesa tiene una única cuenta abierta, ir directo a su detalle
    // en vez de pasar por la pantalla intermedia de la mesa. Con varias
    // cuentas abiertas se muestra MesaDetailScreen para elegir cuál atender.
    if (mesa.ocupada) {
      try {
        final cuentas = await _cuentaService.listarCuentasMesa(mesa.id);
        if (!mounted) return;
        if (cuentas.length == 1) {
          final cuenta = cuentas.first;
          _orderService.setActiveMesa(idMesa: mesa.id, numero: mesa.numero);
          _cuentaService.setActive(
            idCuenta: cuenta.id,
            idMesa: mesa.id,
            mesaNumero: mesa.numero,
            mesaZona: mesa.zona,
          );
          await Navigator.pushNamed(
            context,
            '/cuenta-mesa',
            arguments: cuenta.id,
          );
          if (mounted) _loadAll(silent: true);
          return;
        }
      } catch (e) {
        // Sin conexión o error de RPC: caer a la vista de mesa de siempre.
        print('⚠️ No se pudieron listar cuentas de la mesa ${mesa.id}: $e');
      }
    }
    if (!mounted) return;
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
      backgroundColor: VentiqHomeTheme.surface,
      appBar: AppBar(
        // Mismo tono que el inicio del degradado de la cabecera: antes el
        // AppBar era `primary` y la cabecera empezaba en `primaryDark`, y se
        // veía la costura de dos azules.
        backgroundColor: VentiqHomeTheme.heroGradient.first,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Mesas y Comensales',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
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
            SliverToBoxAdapter(
              child: TutorialAnchor(id: 'mesas_resumen', child: _buildHeader()),
            ),
            if (_loadError != null)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: VentiqHomeTheme.warning.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: VentiqHomeTheme.warning,
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_loadError!)),
                      TextButton(
                        onPressed: () => _loadAll(),
                        child: const Text('Actualizar'),
                      ),
                    ],
                  ),
                ),
              ),
            SliverToBoxAdapter(child: _buildFilters()),
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!_hasLoaded && _loadError != null)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('Datos no disponibles')),
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
                    maxCrossAxisExtent: 190,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.78,
                  ),
                  delegate: SliverChildBuilderDelegate((ctx, i) {
                    final Mesa mesa = _mesasFiltradas[i];
                    final Widget tarjeta = _buildMesaCard(mesa);
                    return _EntradaAnimada(
                      key: ValueKey<int>(mesa.id),
                      index: i,
                      child:
                          i == 0
                              ? TutorialAnchor(
                                id: 'mesas_primera',
                                child: tarjeta,
                              )
                              : tarjeta,
                    );
                  }, childCount: _mesasFiltradas.length),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateDialog,
        backgroundColor: VentiqHomeTheme.primary,
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.add_rounded, color: Colors.white),
        label: const Text(
          'Nueva mesa',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
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
        // Mismo criterio que el resto de pantallas: en flujo de mesa el
        // carrito es la cuenta abierta, no la preorden local.
        NavigationHelper.goCarrito(context).then((_) => _loadAll(silent: true));
        break;
      case 2:
        Navigator.pushNamed(
          context,
          '/orders',
        ).then((_) => _loadAll(silent: true));
        break;
      case 3:
        Navigator.pushNamed(
          context,
          '/settings',
        ).then((_) => _loadAll(silent: true));
        break;
    }
  }

  // ----- subwidgets -----

  /// Cabecera compacta: anillo de ocupación + resumen en una sola fila. Antes
  /// ocupaba ~190 px (tiles grandes y chip de «mesa con más actividad»); ahora
  /// ~100 px para que la cuadrícula de mesas gane protagonismo.
  Widget _buildHeader() {
    final resumen = _resumen;
    final top = resumen.mesaTopComensales;
    final double fraccion =
        resumen.total > 0 ? resumen.ocupadas / resumen.total : 0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: VentiqHomeTheme.heroGradient,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          _buildAnilloOcupacion(fraccion),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  _hasLoaded
                      ? '${resumen.ocupadas} de ${resumen.total} mesas en uso'
                      : 'Cargando salón…',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 7),
                Row(
                  children: <Widget>[
                    _buildHeroStat(
                      'Libres',
                      _hasLoaded ? '${resumen.libres}' : '—',
                      Icons.check_circle_outline,
                      VentiqHomeTheme.success,
                    ),
                    const SizedBox(width: 6),
                    _buildHeroStat(
                      'Ocupadas',
                      _hasLoaded ? '${resumen.ocupadas}' : '—',
                      Icons.local_dining,
                      VentiqHomeTheme.warning,
                    ),
                    const SizedBox(width: 6),
                    _buildHeroStat(
                      'Cuentas',
                      _hasLoaded ? '${resumen.ordenesPendientesTotal}' : '—',
                      Icons.receipt_long,
                      VentiqHomeTheme.accent,
                    ),
                  ],
                ),
                if (top != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    '🔥 ${top.numero} · ${top.comensales} cuenta(s) activa(s)',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.82),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Anillo de ocupación animado: el porcentaje se "llena" al entrar a la
  /// pantalla. Compacto (62 px) para no comerse la cuadrícula.
  Widget _buildAnilloOcupacion(double fraccion) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: fraccion.clamp(0.0, 1.0)),
      duration: const Duration(milliseconds: 750),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double value, Widget? child) {
        return SizedBox(
          width: 62,
          height: 62,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              SizedBox(
                width: 62,
                height: 62,
                child: CircularProgressIndicator(
                  value: value,
                  strokeWidth: 6,
                  strokeCap: StrokeCap.round,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '${(value * 100).round()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  Text(
                    'ocupado',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  /// Stat compacto de la cabecera: icono + valor + rótulo en una píldora.
  Widget _buildHeroStat(
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.0,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78),
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
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

  Widget _buildFilters() {
    final zonas = _zonasDisponibles;
    final int visibles = _mesasFiltradas.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _searchController,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Buscar por número o zona…',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              suffixIcon:
                  _searchController.text.isNotEmpty
                      ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        tooltip: 'Limpiar búsqueda',
                        onPressed: () => _searchController.clear(),
                      )
                      : null,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      _buildZonaChip(null, 'Todas'),
                      for (final z in zonas) ...<Widget>[
                        const SizedBox(width: 6),
                        _buildZonaChip(z, z),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$visibles ${visibles == 1 ? 'mesa' : 'mesas'}',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: VentiqHomeTheme.textSecondary,
                ),
              ),
            ],
          ),
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
      selectedColor: VentiqHomeTheme.primary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : VentiqHomeTheme.textPrimary,
        fontWeight: FontWeight.w700,
      ),
      backgroundColor: VentiqHomeTheme.card,
      side: BorderSide(
        color: isSelected ? VentiqHomeTheme.primary : VentiqHomeTheme.border,
      ),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
    );
  }

  /// Tarjeta de mesa: cabecera con el color del estado, número dominante y
  /// pie con ocupación real (comensales/capacidad) e histórico. El color
  /// transiciona con `AnimatedContainer`, así el cambio de estado que llega por
  /// el polling se anima en vez de saltar.
  Widget _buildMesaCard(Mesa mesa) {
    // Paleta por estado
    final Color accent; // color principal del estado
    final Color bgSoft; // fondo suave para el body
    final String estadoLabel;
    final IconData estadoIcon;

    if (!mesa.activa) {
      accent = VentiqHomeTheme.textSecondary;
      bgSoft = VentiqHomeTheme.surface;
      estadoLabel = 'Inactiva';
      estadoIcon = Icons.visibility_off_outlined;
    } else if (mesa.ordenesAbiertas == 0) {
      accent = VentiqHomeTheme.success;
      bgSoft = VentiqHomeTheme.success.withValues(alpha: 0.08);
      estadoLabel = 'LIBRE';
      estadoIcon = Icons.check_circle_outline;
    } else if (mesa.ordenesAbiertas == 1) {
      accent = VentiqHomeTheme.warning;
      bgSoft = VentiqHomeTheme.warning.withValues(alpha: 0.08);
      estadoLabel = 'OCUPADA';
      estadoIcon = Icons.local_dining;
    } else {
      accent = VentiqHomeTheme.danger;
      bgSoft = VentiqHomeTheme.danger.withValues(alpha: 0.08);
      estadoLabel = 'LLENA';
      estadoIcon = Icons.event_busy;
    }

    final int ocupacionActual =
        mesa.comensalesActivos > 0
            ? mesa.comensalesActivos
            : mesa.ordenesAbiertas;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _openMesaDetail(mesa),
        onLongPress: () => _showMesaActions(mesa),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: VentiqHomeTheme.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
            border: Border.all(color: accent.withValues(alpha: 0.28), width: 1),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // Banner superior con estado y ocupación
              AnimatedContainer(
                duration: const Duration(milliseconds: 280),
                color: accent,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(estadoIcon, size: 13, color: Colors.white),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        estadoLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                    Text(
                      '$ocupacionActual/${mesa.capacidad}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              // Cuerpo: número de mesa dominante
              Expanded(
                child: Container(
                  color: bgSoft,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Text(
                        mesa.numero,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: VentiqHomeTheme.textPrimary,
                          letterSpacing: -0.8,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (mesa.zona != null && mesa.zona!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            mesa.zona!,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: VentiqHomeTheme.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      if (mesa.ocupada) ...<Widget>[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Icon(
                                Icons.people_alt_rounded,
                                size: 11,
                                color: accent,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${mesa.ordenesAbiertas} '
                                '${mesa.ordenesAbiertas == 1 ? 'cuenta' : 'cuentas'}',
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w800,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Pie con capacidad e histórico
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: const BoxDecoration(
                  color: VentiqHomeTheme.card,
                  border: Border(
                    top: BorderSide(color: VentiqHomeTheme.border),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    const Icon(
                      Icons.chair_outlined,
                      size: 12,
                      color: VentiqHomeTheme.textSecondary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Cap. ${mesa.capacidad}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: VentiqHomeTheme.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    if (mesa.ordenesCompletadasHistoricas > 0) ...<Widget>[
                      const Icon(
                        Icons.receipt_long_outlined,
                        size: 11,
                        color: VentiqHomeTheme.textSecondary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        '${mesa.ordenesCompletadasHistoricas}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: VentiqHomeTheme.textSecondary,
                          fontWeight: FontWeight.w600,
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
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: VentiqHomeTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: VentiqHomeTheme.border),
              ),
              child: Icon(
                hasFilter
                    ? Icons.search_off_rounded
                    : Icons.table_restaurant_outlined,
                size: 38,
                color: VentiqHomeTheme.textSecondary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              hasFilter ? 'Sin resultados' : 'Aún no tienes mesas',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16.5,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
                color: VentiqHomeTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              hasFilter
                  ? 'Prueba a cambiar la zona o a limpiar la búsqueda.'
                  : 'Crea la primera mesa para empezar a abrir cuentas por comensal.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: VentiqHomeTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            if (hasFilter)
              OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _zonaFiltro = null;
                    _searchController.clear();
                  });
                },
                icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                label: const Text('Limpiar filtros'),
              )
            else
              FilledButton.icon(
                onPressed: _openCreateDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Nueva mesa'),
              ),
          ],
        ),
      ),
    );
  }
}

/// Entrada escalonada de las tarjetas: aparecen con un fade + slide corto y un
/// retardo por índice. Da vida a la cuadrícula sin retrasar la interacción
/// (los toques funcionan desde el primer frame).
class _EntradaAnimada extends StatefulWidget {
  const _EntradaAnimada({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  State<_EntradaAnimada> createState() => _EntradaAnimadaState();
}

class _EntradaAnimadaState extends State<_EntradaAnimada>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOut,
  );
  late final Animation<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.06),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    final int retardo = (widget.index.clamp(0, 12)) * 35;
    Future<void>.delayed(Duration(milliseconds: retardo), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}
