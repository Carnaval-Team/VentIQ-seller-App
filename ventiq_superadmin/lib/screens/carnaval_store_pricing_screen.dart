import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../services/carnaval_store_pricing_service.dart';
import '../utils/platform_utils.dart';
import '../widgets/app_drawer.dart';

class CarnavalStorePricingScreen extends StatefulWidget {
  const CarnavalStorePricingScreen({super.key});

  @override
  State<CarnavalStorePricingScreen> createState() =>
      _CarnavalStorePricingScreenState();
}

class _CarnavalStorePricingScreenState
    extends State<CarnavalStorePricingScreen> {
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _showOnlyWithProducts = true;
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _filteredStores = [];
  double _globalFloorCash = 0.0;
  double _globalFloorTransfer = 0.0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_applyFilter);
  }

  Future<void> _showGlobalFloorDialog() async {
    final cashController = TextEditingController(
      text: _globalFloorCash.toStringAsFixed(2),
    );
    final transferController = TextEditingController(
      text: _globalFloorTransfer.toStringAsFixed(2),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Editar piso global'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPctField(
                  cashController,
                  'Piso efectivo (%)',
                ),
                const SizedBox(height: 12),
                _buildPctField(
                  transferController,
                  'Piso transferencia (%)',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      final cash = double.tryParse(cashController.text) ?? 0.0;
      final transfer = double.tryParse(transferController.text) ?? 0.0;

      final ok = await CarnavalStorePricingService.updateGlobalFloor(
        efectivo: cash,
        transferencia: transfer,
      );

      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Piso global actualizado'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error actualizando piso global'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    cashController.dispose();
    transferController.dispose();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        CarnavalStorePricingService.getStoresWithPricing(
          onlyWithProducts: _showOnlyWithProducts,
        ),
        CarnavalStorePricingService.getGlobalFloor(),
      ]);
      final stores = results[0] as List<Map<String, dynamic>>;
      final floor = results[1] as Map<String, double>;
      if (!mounted) return;
      setState(() {
        _stores = stores;
        _globalFloorCash = floor['efectivo'] ?? 0.0;
        _globalFloorTransfer = floor['transferencia'] ?? 0.0;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error cargando tiendas: $e'),
          backgroundColor: AppColors.error,
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    setState(() {
      _filteredStores = query.isEmpty
          ? _stores
          : _stores
              .where(
                (s) => (s['denominacion'] as String? ?? '')
                    .toLowerCase()
                    .contains(query),
              )
              .toList();
    });
  }

  Future<void> _showEditDialog(Map<String, dynamic> store) async {
    final regularController = TextEditingController(
      text: _formatPct(store['precio_regular']),
    );
    final cashController = TextEditingController(
      text: _formatPct(store['precio_venta_carnaval']),
    );
    final transferController = TextEditingController(
      text: _formatPct(store['precio_venta_carnaval_transferencia']),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Editar recargos: ${store['denominacion']}'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPctField(regularController, 'Precio regular (%)'),
                const SizedBox(height: 12),
                _buildPctField(
                  cashController,
                  'Carnaval efectivo (%)',
                  suffixInfo:
                      'Piso global: ${_globalFloorCash.toStringAsFixed(2)}%',
                ),
                const SizedBox(height: 12),
                _buildPctField(
                  transferController,
                  'Carnaval transferencia (%)',
                  suffixInfo:
                      'Piso global: ${_globalFloorTransfer.toStringAsFixed(2)}%',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Guardar'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      final regular = double.tryParse(regularController.text) ?? 0.0;
      final cash = double.tryParse(cashController.text) ?? 0.0;
      final transfer = double.tryParse(transferController.text) ?? 0.0;

      if (cash < _globalFloorCash || transfer < _globalFloorTransfer) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Los porcentajes de carnaval no pueden ser menores que el piso global '
                '(efectivo: ${_globalFloorCash.toStringAsFixed(2)}%, '
                'transferencia: ${_globalFloorTransfer.toStringAsFixed(2)}%).',
              ),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      final ok = await CarnavalStorePricingService.updateStorePricing(
        storeId: store['id'] as int,
        precioRegular: regular,
        precioVentaCarnaval: cash,
        precioVentaCarnavalTransferencia: transfer,
      );

      if (!mounted) return;
      if (ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuración guardada'),
            backgroundColor: AppColors.success,
          ),
        );
        await _loadData();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error guardando la configuración'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }

    regularController.dispose();
    cashController.dispose();
    transferController.dispose();
  }

  Widget _buildPctField(
    TextEditingController controller,
    String label, {
    String? suffixInfo,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        helperText: suffixInfo,
        border: const OutlineInputBorder(),
      ),
    );
  }

  String _formatPct(dynamic value) =>
      ((value as num?)?.toDouble() ?? 0.0).toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final screenPadding = PlatformUtils.getScreenPadding();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recargos Carnaval por Tienda'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Editar piso global',
            onPressed: _showGlobalFloorDialog,
          ),
          const SizedBox(width: 8),
        ],
      ),
      drawer: const AppDrawer(),
      body: Padding(
        padding: EdgeInsets.all(screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildGlobalFloorChip(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      labelText: 'Buscar tienda',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  label: const Text('Con productos en Carnaval'),
                  selected: _showOnlyWithProducts,
                  onSelected: (value) {
                    setState(() => _showOnlyWithProducts = value);
                    _loadData();
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildStoresList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalFloorChip() {
    return Wrap(
      spacing: 8,
      children: [
        Chip(
          avatar: const Icon(Icons.trending_up, size: 18),
          label: Text(
            'Piso global efectivo: ${_globalFloorCash.toStringAsFixed(2)}%',
          ),
        ),
        Chip(
          avatar: const Icon(Icons.credit_card, size: 18),
          label: Text(
            'Piso global transferencia: ${_globalFloorTransfer.toStringAsFixed(2)}%',
          ),
        ),
      ],
    );
  }

  Widget _buildStoresList() {
    if (_filteredStores.isEmpty) {
      return const Center(
        child: Text('No se encontraron tiendas'),
      );
    }

    return ListView.separated(
      itemCount: _filteredStores.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final store = _filteredStores[index];
        return ListTile(
          title: Text(
            store['denominacion'] as String,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            'Regular: ${_formatPct(store['precio_regular'])}%  |  '
            'Efectivo: ${_formatPct(store['precio_venta_carnaval'])}%  |  '
            'Transferencia: ${_formatPct(store['precio_venta_carnaval_transferencia'])}%',
          ),
          trailing: IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () => _showEditDialog(store),
          ),
        );
      },
    );
  }
}
