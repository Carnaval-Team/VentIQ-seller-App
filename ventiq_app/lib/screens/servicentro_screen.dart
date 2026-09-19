import 'package:flutter/material.dart';

import '../services/servicentro_service.dart';
import '../services/user_preferences_service.dart';
import '../utils/navigation_helper.dart';
import '../widgets/app_drawer.dart';
import '../widgets/bottom_navigation.dart';
import 'servicentro_cantidad_screen.dart';

/// Home del modo servicentro: grid de combustibles configurados por TPV.
class ServicentroScreen extends StatefulWidget {
  const ServicentroScreen({super.key});

  @override
  State<ServicentroScreen> createState() => _ServicentroScreenState();
}

class _ServicentroScreenState extends State<ServicentroScreen> {
  bool _loading = true;
  String? _warning;
  bool _fromCache = false;
  List<ServicentroFuelItem> _items = [];
  int _columnas = 2;
  String _titulo = 'Servicentro';

  @override
  void initState() {
    super.initState();
    final cachedName = ServicentroService.tpvNombreSync;
    if (cachedName != null && cachedName.isNotEmpty) {
      _titulo = cachedName;
    }
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _loading = true;
      _warning = null;
      _columnas = ServicentroService.servicentroColumnasSync.clamp(1, 4);
      final name = ServicentroService.tpvNombreSync;
      if (name != null && name.isNotEmpty) {
        _titulo = name;
      }
    });

    try {
      final prefs = UserPreferencesService();
      final idTienda = await prefs.getIdTienda();
      final idTpv = await prefs.getIdTpv();

      ServicentroLoadResult result;
      if (idTienda != null) {
        result = await ServicentroService.loadProductos(
          idTienda: idTienda,
          idTpv: idTpv,
        );
      } else {
        final cached = await ServicentroService.getCachedProductos(idTpv: idTpv);
        result = ServicentroLoadResult(
          items: cached,
          fromCache: true,
          syncedAt: ServicentroService.lastSyncedAtSync,
          warning: cached.isEmpty
              ? 'No hay sesión de tienda ni cache de combustibles.'
              : null,
        );
      }

      final cols = ServicentroService.servicentroColumnasSync;
      final name = ServicentroService.tpvNombreSync;

      if (!mounted) return;
      setState(() {
        _items = result.items;
        _columnas = cols.clamp(1, 4);
        if (name != null && name.isNotEmpty) {
          _titulo = name;
        }
        _fromCache = result.fromCache;
        _warning = result.warning;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final cached = await ServicentroService.getCachedProductos();
      setState(() {
        _items = cached;
        _fromCache = true;
        _loading = false;
        _warning = cached.isEmpty
            ? e.toString()
            : 'Mostrando cache local (error al actualizar).';
      });
    }
  }

  Color _cardColor(String hex, {required bool enabled}) {
    final base = Color(ServicentroFuelItem.parseColor(hex).argb);
    if (enabled) return base;
    return Color.lerp(base, Colors.grey.shade700, 0.55) ?? Colors.grey;
  }

  double _aspectRatioForColumns(int cols) {
    switch (cols) {
      case 1:
        return 2.2;
      case 2:
        return 1.05;
      case 3:
        return 0.9;
      default:
        return 0.75;
    }
  }

  String _formatStock(ServicentroFuelItem item) {
    final n = item.stockDisponible;
    final um = (item.um != null && item.um!.trim().isNotEmpty)
        ? item.um!.trim()
        : 'L';
    if (n == n.roundToDouble()) {
      return '${n.toInt()} $um';
    }
    return '${n.toStringAsFixed(2)} $um';
  }

  Future<void> _onBottomNavTap(int index) async {
    switch (index) {
      case 0:
        await _cargar();
        break;
      case 1:
        await NavigationHelper.goCarrito(context);
        break;
      case 2:
        Navigator.pushNamed(context, '/orders');
        break;
      case 3:
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }

  void _onFuelTap(ServicentroFuelItem item) {
    if (!item.puedeVender) {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sin stock'),
          content: Text(
            '${item.denominacion} no tiene stock disponible '
            '(${_formatStock(item)}).',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Aceptar'),
            ),
          ],
        ),
      );
      return;
    }
    if (item.precioVenta <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Este combustible no tiene precio. Configúralo en Admin antes de vender.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ServicentroCantidadScreen(fuel: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const AppDrawer(),
      appBar: AppBar(
        title: Text(_titulo),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            onPressed: _loading ? null : _cargar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: AppBottomNavigation(
        currentIndex: 0,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _cargar,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (_warning != null || _fromCache)
            SliverToBoxAdapter(child: _buildBanner()),
          if (_items.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmpty(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: _columnas,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: _aspectRatioForColumns(_columnas),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _buildCard(_items[index]),
                  childCount: _items.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBanner() {
    final theme = Theme.of(context);
    final isError = _items.isEmpty && _warning != null;
    return Material(
      color: isError
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isError ? Icons.warning_amber_rounded : Icons.cloud_off_outlined,
              size: 20,
              color: isError
                  ? theme.colorScheme.onErrorContainer
                  : theme.colorScheme.onSecondaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _warning ?? 'Mostrando combustibles del cache local.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: isError
                      ? theme.colorScheme.onErrorContainer
                      : theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.local_gas_station_outlined, size: 48),
          const SizedBox(height: 16),
          Text(
            _warning ??
                'No hay combustibles configurados para este TPV.\n'
                    'El gerente debe agregarlos en Admin → Gestión de TPVs → Servicentro.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _cargar, child: const Text('Reintentar')),
        ],
      ),
    );
  }

  Widget _buildCard(ServicentroFuelItem item) {
    final enabled = item.puedeVender;
    final color = _cardColor(item.color, enabled: enabled);
    final sinPrecio = item.precioVenta <= 0;

    return Opacity(
      opacity: enabled ? 1 : 0.72,
      child: Material(
        color: color,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _onFuelTap(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.denominacion,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  enabled ? 'Stock: ${_formatStock(item)}' : 'Sin stock',
                  style: TextStyle(
                    color: enabled ? Colors.white70 : Colors.orangeAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  sinPrecio
                      ? 'Sin precio'
                      : '\$${item.precioVenta.toStringAsFixed(2)}'
                          '${item.um != null && item.um!.isNotEmpty ? ' / ${item.um}' : ''}',
                  style: TextStyle(
                    color: sinPrecio ? Colors.orangeAccent : Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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
