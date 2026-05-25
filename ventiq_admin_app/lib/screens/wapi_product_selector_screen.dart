import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../models/product.dart';
import '../services/product_service.dart';

/// Modo del selector:
///  - manual: el padre lo abre con push y, al "Continuar",
///    retorna `List<int>` (ids) vía Navigator.pop.
///  - schedule: idéntico, pero el texto del botón cambia.
enum WapiProductSelectorMode { manual, schedule }

/// Selector multi-select de productos para difundir por WhatsApp.
///
/// Reglas:
///  - Sólo productos con imagen + precio > 0 (los demás aparecen pero deshabilitados).
///  - Inputs: búsqueda, filtro por categoría, "Seleccionar todos los visibles".
class WapiProductSelectorScreen extends StatefulWidget {
  final WapiProductSelectorMode mode;
  final Set<int> initialSelected;

  const WapiProductSelectorScreen({
    super.key,
    this.mode = WapiProductSelectorMode.manual,
    this.initialSelected = const {},
  });

  @override
  State<WapiProductSelectorScreen> createState() =>
      _WapiProductSelectorScreenState();
}

class _WapiProductSelectorScreenState extends State<WapiProductSelectorScreen> {
  late Future<List<Product>> _future;
  final Set<int> _selected = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  String? _categoryFilter;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    _future = ProductService.getProductsByTienda();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  bool _canSend(Product p) =>
      p.imageUrl.isNotEmpty &&
      (p.basePrice > 0 || p.precioVenta > 0) &&
      p.denominacion.isNotEmpty;

  List<Product> _filter(List<Product> all) {
    Iterable<Product> it = all;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      it = it.where((p) =>
          p.denominacion.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          (p.sku).toLowerCase().contains(q));
    }
    if (_categoryFilter != null && _categoryFilter!.isNotEmpty) {
      it = it.where((p) => p.categoryName == _categoryFilter);
    }
    return it.toList();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = MediaQuery.of(context).size.width >= 900;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Seleccionar productos'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Product>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _ErrorView(error: '${snap.error}', onRetry: () {
              setState(() => _future = ProductService.getProductsByTienda());
            });
          }
          final all = snap.data ?? [];
          final eligible = all.where(_canSend).toList();
          final filtered = _filter(eligible);
          final categories = eligible
              .map((e) => e.categoryName)
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();

          return Column(
            children: [
              _buildHeader(filtered, categories),
              if (filtered.isEmpty)
                const Expanded(child: _EmptyView())
              else
                Expanded(
                  child: isWeb
                      ? _buildGrid(filtered)
                      : _buildList(filtered),
                ),
              _buildBottomBar(filtered),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(List<Product> filtered, List<String> categories) {
    final allSelectedVisible =
        filtered.isNotEmpty && filtered.every((p) => _selected.contains(_idInt(p)));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar producto, SKU…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      }),
            ),
            onChanged: (v) => setState(() => _query = v.trim()),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                FilterChip(
                  label: const Text('Todas'),
                  selected: _categoryFilter == null,
                  onSelected: (_) =>
                      setState(() => _categoryFilter = null),
                  selectedColor: AppColors.primary.withOpacity(0.15),
                ),
                const SizedBox(width: 6),
                ...categories.map((c) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: FilterChip(
                        label: Text(c),
                        selected: _categoryFilter == c,
                        onSelected: (_) => setState(
                            () => _categoryFilter = _categoryFilter == c ? null : c),
                        selectedColor: AppColors.primary.withOpacity(0.15),
                      ),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${filtered.length} productos',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const Spacer(),
              TextButton.icon(
                icon: Icon(allSelectedVisible
                    ? Icons.deselect
                    : Icons.select_all),
                label: Text(allSelectedVisible
                    ? 'Deseleccionar visibles'
                    : 'Seleccionar visibles'),
                onPressed: filtered.isEmpty
                    ? null
                    : () {
                        setState(() {
                          if (allSelectedVisible) {
                            for (final p in filtered) _selected.remove(_idInt(p));
                          } else {
                            for (final p in filtered) _selected.add(_idInt(p));
                          }
                        });
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Product> items) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: items.length,
      itemBuilder: (_, i) => _ProductTile(
        product: items[i],
        selected: _selected.contains(_idInt(items[i])),
        onTap: () => _toggle(items[i]),
      ),
    );
  }

  Widget _buildGrid(List<Product> items) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 380,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          mainAxisExtent: 130,
        ),
        itemCount: items.length,
        itemBuilder: (_, i) => _ProductTile(
          product: items[i],
          selected: _selected.contains(_idInt(items[i])),
          onTap: () => _toggle(items[i]),
        ),
      ),
    );
  }

  int _idInt(Product p) => int.tryParse(p.id) ?? -1;

  void _toggle(Product p) {
    final id = _idInt(p);
    if (id < 0) return;
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  Widget _buildBottomBar(List<Product> filtered) {
    final label = widget.mode == WapiProductSelectorMode.manual
        ? 'Continuar (${_selected.length})'
        : 'Guardar selección (${_selected.length})';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _selected.isEmpty
                  ? 'Selecciona al menos un producto para continuar'
                  : '${_selected.length} producto(s) listos',
              style: TextStyle(
                color: _selected.isEmpty
                    ? AppColors.textSecondary
                    : AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: Text(label),
            onPressed: _selected.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected.toList()),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final bool selected;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = product.precioVenta > 0
        ? product.precioVenta
        : product.basePrice;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: product.imageUrl.isNotEmpty
                      ? Image.network(
                          product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppColors.surfaceVariant,
                            child: const Icon(Icons.broken_image,
                                color: AppColors.textLight),
                          ),
                        )
                      : Container(
                          color: AppColors.surfaceVariant,
                          child:
                              const Icon(Icons.image_not_supported_outlined),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.denominacion,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    if (product.description.isNotEmpty)
                      Text(
                        product.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '\$${price.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (product.categoryName.isNotEmpty)
                          Flexible(
                            child: Text(
                              product.categoryName,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textLight),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Checkbox(
                value: selected,
                onChanged: (_) => onTap(),
                activeColor: AppColors.primary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 64, color: AppColors.textLight),
            SizedBox(height: 12),
            Text(
              'No hay productos publicables.\nAsegúrate de que tienen foto y precio.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                size: 56, color: AppColors.error),
            const SizedBox(height: 10),
            Text(error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
