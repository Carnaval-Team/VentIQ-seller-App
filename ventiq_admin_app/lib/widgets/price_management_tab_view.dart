import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../config/app_colors.dart';
import '../services/price_management_service.dart';
import '../services/user_preferences_service.dart';

class PriceManagementTabView extends StatefulWidget {
  const PriceManagementTabView({super.key});

  @override
  State<PriceManagementTabView> createState() => _PriceManagementTabViewState();
}

class _PriceManagementTabViewState extends State<PriceManagementTabView> {
  final UserPreferencesService _userPreferencesService =
      UserPreferencesService();

  bool _isLoading = true;
  bool _isSaving = false;
  int? _storeId;

  GeneralPriceConfig? _priceConfig;
  List<ProductPriceItem> _products = [];
  final Set<int> _selected = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() {
        _isLoading = true;
      });

      _storeId = await _userPreferencesService.getIdTienda();
      if (_storeId == null) {
        throw Exception('No se pudo obtener la tienda actual');
      }

      final config = await PriceManagementService.getOrCreatePriceConfig(
        _storeId!,
      );
      final products = await PriceManagementService.getProductsWithLastPrice(
        _storeId!,
      );

      setState(() {
        _priceConfig = config;
        _products = products;
        _selected.clear();
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar datos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showGlobalDialog() async {
    if (_storeId == null || _priceConfig == null) return;

    final regularController = TextEditingController(
      text: _priceConfig!.precioRegular.toStringAsFixed(1),
    );
    final carnavalController = TextEditingController(
      text: _priceConfig!.precioVentaCarnaval.toStringAsFixed(1),
    );
    final transferenciaController = TextEditingController(
      text: _priceConfig!.precioVentaCarnavalTransferencia.toStringAsFixed(1),
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(
            'Cambiar precio global',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildPercentField(
                controller: regularController,
                label: 'Precio regular (%)',
              ),
              const SizedBox(height: 12),
              _buildPercentField(
                controller: carnavalController,
                label: 'Precio venta carnaval (%)',
              ),
              const SizedBox(height: 12),
              _buildPercentField(
                controller: transferenciaController,
                label: 'Precio carnaval transferencia (%)',
              ),
              const SizedBox(height: 8),
              const Text(
                'Estos porcentajes actualizarán todos los productos de la tienda '
                'y también los precios en Carnaval App cuando corresponda.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed:
                  _isSaving
                      ? null
                      : () async {
                        final regular =
                            double.tryParse(regularController.text) ?? 0.0;
                        final carnaval =
                            double.tryParse(carnavalController.text) ?? 0.0;
                        final transferencia =
                            double.tryParse(transferenciaController.text) ??
                            0.0;
                        Navigator.of(context).pop();
                        await _applyGlobalChange(
                          regular: regular,
                          carnaval: carnaval,
                          transferencia: transferencia,
                        );
                      },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Aplicar'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _applyGlobalChange({
    required double regular,
    required double carnaval,
    required double transferencia,
  }) async {
    if (_storeId == null) return;

    setState(() {
      _isSaving = true;
    });

    final ok = await PriceManagementService.applyGlobalPriceChange(
      storeId: _storeId!,
      precioRegular: regular,
      precioCarnaval: carnaval,
      precioCarnavalTransferencia: transferencia,
    );

    setState(() {
      _isSaving = false;
    });

    if (!mounted) return;
    if (ok) {
      setState(() {
        _priceConfig = GeneralPriceConfig(
          precioRegular: regular,
          precioVentaCarnaval: carnaval,
          precioVentaCarnavalTransferencia: transferencia,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precios globales actualizados'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar precios globales'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showSelectedDialog() async {
    if (_storeId == null || _priceConfig == null || _selected.isEmpty) return;

    String changeType = 'percent';
    final valueController = TextEditingController(text: '0.0');

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return AlertDialog(
              title: const Text(
                'Modificar precio de seleccionados',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Tipo de ajuste',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: RadioListTile<String>(
                          value: 'percent',
                          groupValue: changeType,
                          onChanged: (v) {
                            setLocalState(() {
                              changeType = v ?? 'percent';
                            });
                          },
                          title: const Text('Porcentaje'),
                          dense: true,
                        ),
                      ),
                      Expanded(
                        child: RadioListTile<String>(
                          value: 'fixed',
                          groupValue: changeType,
                          onChanged: (v) {
                            setLocalState(() {
                              changeType = v ?? 'percent';
                            });
                          },
                          title: const Text('Cantidad fija'),
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: valueController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText:
                          changeType == 'percent'
                              ? 'Porcentaje a aumentar'
                              : 'Cantidad fija a aumentar',
                      suffixText: changeType == 'percent' ? '%' : 'CUP',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Se actualizarán ${_selected.length} productos. '
                    'También se reflejará en Carnaval App cuando aplique.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                ElevatedButton(
                  onPressed:
                      _isSaving
                          ? null
                          : () async {
                            final value =
                                double.tryParse(valueController.text) ?? 0.0;
                            Navigator.of(context).pop();
                            await _applySelectedChange(
                              changeType: changeType,
                              changeValue: value,
                            );
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                  ),
                  child: const Text('Aplicar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _applySelectedChange({
    required String changeType,
    required double changeValue,
  }) async {
    if (_storeId == null || _priceConfig == null) return;

    setState(() {
      _isSaving = true;
    });

    final ok = await PriceManagementService.applySelectedPriceChange(
      storeId: _storeId!,
      productIds: _selected.toList(),
      changeType: changeType,
      changeValue: changeValue,
      precioCarnaval: _priceConfig!.precioVentaCarnaval,
      precioCarnavalTransferencia:
          _priceConfig!.precioVentaCarnavalTransferencia,
    );

    setState(() {
      _isSaving = false;
    });

    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precios actualizados'),
          backgroundColor: Colors.green,
        ),
      );
      await _loadData();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo actualizar precios'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildPercentField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: '%',
        border: const OutlineInputBorder(),
      ),
    );
  }

  String _formatPrice(double? value) {
    if (value == null) return 'Sin precio';
    return '\$${value.toStringAsFixed(2)}';
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Sin historial';
    return DateFormat('dd/MM/yyyy').format(dt);
  }

  Future<void> _toggleSelection(int productId) async {
    setState(() {
      if (_selected.contains(productId)) {
        _selected.remove(productId);
      } else {
        _selected.add(productId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_storeId == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('No se pudo obtener la tienda actual'),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildActionsRow(),
              const SizedBox(height: 16),
              _buildProductsList(),
              const SizedBox(height: 120),
            ],
          ),
        ),
        if (_selected.isNotEmpty)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              heroTag: 'price_selected_fab',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: _isSaving ? null : _showSelectedDialog,
              icon: const Icon(Icons.playlist_add_check, color: Colors.white),
              label: Text('Proceder (${_selected.length})'),
            ),
          ),
      ],
    );
  }

  Widget _buildHeader() {
    return Card(
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sell, color: AppColors.primary),
                const SizedBox(width: 8),
                const Text(
                  'Gestión de precios',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildChip(
                  label:
                      'Precio regular: ${_priceConfig?.precioRegular.toStringAsFixed(2) ?? '0'}%',
                  color: Colors.blue,
                ),
                _buildChip(
                  label:
                      'Carnaval: ${_priceConfig?.precioVentaCarnaval.toStringAsFixed(2) ?? '5.3'}%',
                  color: Colors.deepPurple,
                ),
                _buildChip(
                  label:
                      'Carnaval transferencia: ${_priceConfig?.precioVentaCarnavalTransferencia.toStringAsFixed(2) ?? '11.1'}%',
                  color: Colors.teal,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip({required String label, required MaterialColor color}) {
    return Chip(
      backgroundColor: color.withOpacity(0.12),
      label: Text(
        label,
        style: TextStyle(color: color.shade700, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildActionsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _isSaving ? null : _showGlobalDialog,
            icon: const Icon(Icons.auto_fix_high),
            label: const Text('Cambiar precio global'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed:
                _isSaving || _selected.isEmpty ? null : _showSelectedDialog,
            icon: const Icon(Icons.check_box),
            label: const Text('Cambiar seleccionados'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(color: AppColors.primary),
              foregroundColor: AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductsList() {
    if (_products.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: const [
              Icon(Icons.inventory_2_outlined, size: 42, color: Colors.grey),
              SizedBox(height: 12),
              Text(
                'No hay productos registrados',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 1,
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _products.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final item = _products[index];
          final selected = _selected.contains(item.id);
          return ListTile(
            onTap: () => _toggleSelection(item.id),
            leading: Checkbox(
              value: selected,
              onChanged: (_) => _toggleSelection(item.id),
            ),
            title: Text(
              item.name,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SKU: ${item.sku.isNotEmpty ? item.sku : 'N/A'}'),
                const SizedBox(height: 4),
                Text(
                  'Último precio: ${_formatPrice(item.lastPrice)} · ${_formatDate(item.lastPriceDate)}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (item.vendedorAppId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.sync_alt,
                          size: 14,
                          color: Colors.orange.shade700,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Sincroniza con Carnaval (id: ${item.vendedorAppId})',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            trailing: Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? AppColors.primary : Colors.grey,
            ),
          );
        },
      ),
    );
  }
}
