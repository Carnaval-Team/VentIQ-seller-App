import 'package:flutter/material.dart';

import '../models/carnaval_pickup_summary.dart';
import '../services/export_service.dart';

class CarnavalPickupProductsSheet extends StatefulWidget {
  const CarnavalPickupProductsSheet({
    super.key,
    required this.summary,
    required this.orderCount,
  });

  final List<CarnavalPickupProvider> summary;
  final int orderCount;

  @override
  State<CarnavalPickupProductsSheet> createState() =>
      _CarnavalPickupProductsSheetState();
}

class _CarnavalPickupProductsSheetState
    extends State<CarnavalPickupProductsSheet> {
  bool _isExporting = false;

  Future<void> _chooseExportFormat() async {
    if (_isExporting || widget.summary.isEmpty) return;
    final action = await showModalBottomSheet<_PickupExportAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Exportar productos por recoger',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('Selecciona el formato del reporte'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('PDF completo'),
              subtitle: const Text('Todas las tiendas en un archivo'),
              onTap: () =>
                  Navigator.pop(context, _PickupExportAction.completePdf),
            ),
            ListTile(
              leading: const Icon(Icons.storefront_outlined),
              title: const Text('PDF por tiendas'),
              subtitle: const Text('Elegir una o varias tiendas'),
              onTap: () => Navigator.pop(context, _PickupExportAction.storePdf),
            ),
            ListTile(
              leading: const Icon(Icons.table_chart, color: Colors.green),
              title: const Text('Excel'),
              onTap: () => Navigator.pop(context, _PickupExportAction.excel),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    List<CarnavalPickupProvider>? providers;
    if (action == _PickupExportAction.storePdf) {
      providers = await _chooseProviders();
      if (providers == null || providers.isEmpty || !mounted) return;
    }

    final selectedSummary = providers ?? widget.summary;
    final orderCount = providers == null
        ? widget.orderCount
        : providers
              .expand((provider) => provider.products)
              .expand((product) => product.orders)
              .map((order) => order.orderId)
              .toSet()
              .length;
    final format = action == _PickupExportAction.excel
        ? ExportFormat.excel
        : ExportFormat.pdf;

    setState(() => _isExporting = true);
    try {
      await ExportService().exportCarnavalPickupProducts(
        context: context,
        rows: buildCarnavalPickupExportRows(selectedSummary),
        orderCount: orderCount,
        format: format,
        providerName: providers?.length == 1
            ? providers!.single.providerName
            : null,
        groupByProvider: action == _PickupExportAction.storePdf,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al exportar el listado: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<List<CarnavalPickupProvider>?> _chooseProviders() {
    final selectedIds = widget.summary
        .map((provider) => provider.providerId)
        .toSet();
    return showModalBottomSheet<List<CarnavalPickupProvider>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Column(
              children: [
                const ListTile(
                  title: Text(
                    'Seleccionar tiendas',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    'El PDF tendrá una sección para cada tienda seleccionada',
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => setModalState(
                          () => selectedIds.addAll(
                            widget.summary.map(
                              (provider) => provider.providerId,
                            ),
                          ),
                        ),
                        child: const Text('Seleccionar todas'),
                      ),
                      TextButton(
                        onPressed: () => setModalState(selectedIds.clear),
                        child: const Text('Limpiar'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.builder(
                    itemCount: widget.summary.length,
                    itemBuilder: (context, index) {
                      final provider = widget.summary[index];
                      return CheckboxListTile(
                        value: selectedIds.contains(provider.providerId),
                        title: Text(provider.providerName),
                        subtitle: Text('${provider.products.length} productos'),
                        secondary: const Icon(Icons.storefront_outlined),
                        onChanged: (selected) => setModalState(() {
                          if (selected == true) {
                            selectedIds.add(provider.providerId);
                          } else {
                            selectedIds.remove(provider.providerId);
                          }
                        }),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: selectedIds.isEmpty
                          ? null
                          : () => Navigator.pop(
                              context,
                              widget.summary
                                  .where(
                                    (provider) => selectedIds.contains(
                                      provider.providerId,
                                    ),
                                  )
                                  .toList(),
                            ),
                      icon: const Icon(Icons.picture_as_pdf),
                      label: Text(
                        'Exportar ${selectedIds.length} ${selectedIds.length == 1 ? 'tienda' : 'tiendas'}',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: 0.9,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.local_shipping_outlined),
              title: const Text(
                'Productos por recoger',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                'Productos externos a la tienda 177 · ${widget.orderCount} órdenes',
              ),
              trailing: IconButton(
                onPressed: widget.summary.isEmpty || _isExporting
                    ? null
                    : _chooseExportFormat,
                tooltip: 'Exportar listado',
                icon: _isExporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.summary.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'No hay productos externos en las órdenes que coinciden con los filtros actuales.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                      itemCount: widget.summary.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final provider = widget.summary[index];
                        return Card(
                          margin: EdgeInsets.zero,
                          child: ExpansionTile(
                            initiallyExpanded: true,
                            leading: const Icon(Icons.storefront_outlined),
                            title: Text(
                              provider.providerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              '${provider.products.length} productos',
                            ),
                            children: [
                              for (final product in provider.products)
                                _ProductOrderDetail(product: product),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PickupExportAction { completePdf, storePdf, excel }

class _ProductOrderDetail extends StatelessWidget {
  const _ProductOrderDetail({required this.product});

  final CarnavalPickupProduct product;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  product.productName,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Total: ${_formatQuantity(product.quantity)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final order in product.orders)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  const Icon(Icons.receipt_long_outlined, size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Orden #${order.orderId}')),
                  Text(
                    _formatQuantity(order.quantity),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          const Divider(height: 16),
        ],
      ),
    );
  }

  String _formatQuantity(double quantity) {
    return quantity == quantity.truncateToDouble()
        ? quantity.toInt().toString()
        : quantity.toStringAsFixed(2);
  }
}
