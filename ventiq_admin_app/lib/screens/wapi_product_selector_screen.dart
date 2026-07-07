import 'dart:async';

import 'package:flutter/material.dart';

import '../config/app_colors.dart';
import '../services/marketplace_product_service.dart';

/// Modo del selector:
///  - manual: el padre lo abre con push y, al "Continuar",
///    retorna `List<int>` (ids) vía Navigator.pop.
///  - schedule: idéntico, pero el texto del botón cambia.
enum WapiProductSelectorMode { manual, schedule }

/// Selector multi-select de productos para difundir por WhatsApp.
///
/// Datos vienen del RPC paginado `get_productos_marketplace`. Sólo se
/// muestran productos con imagen (WAPI requiere URL pública).
class WapiProductSelectorScreen extends StatefulWidget {
  final int idTienda;
  final WapiProductSelectorMode mode;
  final Set<int> initialSelected;

  const WapiProductSelectorScreen({
    super.key,
    required this.idTienda,
    this.mode = WapiProductSelectorMode.manual,
    this.initialSelected = const {},
  });

  @override
  State<WapiProductSelectorScreen> createState() =>
      _WapiProductSelectorScreenState();
}

class _WapiProductSelectorScreenState extends State<WapiProductSelectorScreen> {
  static const int _pageSize = 20;

  final Set<int> _selected = {};
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  final List<MarketplaceProduct> _items = [];
  bool _loadingInitial = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  String _query = '';
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.initialSelected);
    _scrollCtrl.addListener(_onScroll);
    _reload();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Future<void> _reload() async {
    setState(() {
      _loadingInitial = true;
      _error = null;
      _items.clear();
      _hasMore = true;
    });
    try {
      final page = await MarketplaceProductService.getProductos(
        idTienda: widget.idTienda,
        limit: _pageSize,
        offset: 0,
        search: _query,
        soloDisponibles: false,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingInitial = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loadingInitial = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loadingInitial) return;
    setState(() => _loadingMore = true);
    try {
      final page = await MarketplaceProductService.getProductos(
        idTienda: widget.idTienda,
        limit: _pageSize,
        offset: _items.length,
        search: _query,
        soloDisponibles: false,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando más: $e')),
      );
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      final q = v.trim();
      if (q == _query) return;
      _query = q;
      _reload();
    });
  }

  bool _canSend(MarketplaceProduct p) =>
      p.imagen.isNotEmpty &&
      p.denominacion.isNotEmpty &&
      p.precioVenta > 0;

  List<MarketplaceProduct> get _visibleItems =>
      _items.where(_canSend).toList();

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
      body: _loadingInitial
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(error: _error!, onRetry: _reload)
              : Column(
                  children: [
                    _buildHeader(_visibleItems),
                    Expanded(
                      child: _visibleItems.isEmpty
                          ? const _EmptyView()
                          : RefreshIndicator(
                              onRefresh: _reload,
                              child: isWeb
                                  ? _buildGrid(_visibleItems)
                                  : _buildList(_visibleItems),
                            ),
                    ),
                    _buildBottomBar(),
                  ],
                ),
    );
  }

  Widget _buildHeader(List<MarketplaceProduct> filtered) {
    final allSelectedVisible = filtered.isNotEmpty &&
        filtered.every((p) => _selected.contains(p.idProducto));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: Colors.white,
      child: Column(
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Buscar producto…',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                    ),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${filtered.length} mostrado(s)'
                '${_hasMore ? ' • más al hacer scroll' : ''}',
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
                            for (final p in filtered) {
                              _selected.remove(p.idProducto);
                            }
                          } else {
                            for (final p in filtered) {
                              _selected.add(p.idProducto);
                            }
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

  Widget _buildList(List<MarketplaceProduct> items) {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      itemCount: items.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= items.length) return _buildLoaderTile();
        return _ProductTile(
          product: items[i],
          selected: _selected.contains(items[i].idProducto),
          onTap: () => _toggle(items[i]),
        );
      },
    );
  }

  Widget _buildGrid(List<MarketplaceProduct> items) {
    return GridView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 380,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 150,
      ),
      itemCount: items.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i >= items.length) return _buildLoaderTile();
        return _ProductTile(
          product: items[i],
          selected: _selected.contains(items[i].idProducto),
          onTap: () => _toggle(items[i]),
        );
      },
    );
  }

  Widget _buildLoaderTile() => const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );

  void _toggle(MarketplaceProduct p) {
    setState(() {
      if (_selected.contains(p.idProducto)) {
        _selected.remove(p.idProducto);
      } else {
        _selected.add(p.idProducto);
      }
    });
  }

  /// Si entre los seleccionados hay productos sin stock, pedir confirmación
  /// antes de devolver la lista al padre. "Revisar" cancela y deja al usuario
  /// en el picker para ajustar; "Continuar" envía igual (el backend filtrará
  /// nada por stock — el caption del mensaje sí refleja la disponibilidad).
  Future<void> _confirmAndPop() async {
    final sinStock = _items
        .where((p) =>
            _selected.contains(p.idProducto) &&
            (!p.tieneStock || p.stockDisponible <= 0))
        .toList();

    if (sinStock.isEmpty) {
      Navigator.of(context).pop(_selected.toList());
      return;
    }

    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: AppColors.warning),
            SizedBox(width: 8),
            Expanded(child: Text('Productos sin stock')),
          ],
        ),
        content: SizedBox(
          width: 360,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Los siguientes ${sinStock.length} producto(s) no tienen '
                'stock disponible. Aún puedes difundirlos, pero los '
                'destinatarios verán "Sin stock" en el mensaje.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: sinStock
                        .map((p) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  const Text('• ',
                                      style: TextStyle(
                                          color: AppColors.warning,
                                          fontWeight: FontWeight.bold)),
                                  Expanded(
                                    child: Text(
                                      p.denominacion,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          color: AppColors.textPrimary),
                                    ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'revisar'),
            child: const Text('Revisar'),
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.arrow_forward),
            label: const Text('Continuar igual'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, 'continuar'),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (action == 'continuar') {
      Navigator.of(context).pop(_selected.toList());
    }
    // En "revisar" no hacemos nada — el usuario sigue en el picker.
  }

  Widget _buildBottomBar() {
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
            onPressed: _selected.isEmpty ? null : _confirmAndPop,
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
  final MarketplaceProduct product;
  final bool selected;
  final VoidCallback onTap;

  const _ProductTile({
    required this.product,
    required this.selected,
    required this.onTap,
  });

  String _formatStock(double s) {
    if (s % 1 == 0) return s.toStringAsFixed(0);
    return s.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final sinStock = !product.tieneStock || product.stockDisponible <= 0;
    final stockText = sinStock
        ? 'Sin stock'
        : '${_formatStock(product.stockDisponible)} disp.';
    final borderColor = selected
        ? AppColors.primary
        : sinStock
            ? AppColors.warning
            : AppColors.border;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: sinStock ? AppColors.warning.withOpacity(0.04) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
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
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 68,
                      height: 68,
                      child: product.imagen.isNotEmpty
                          ? Image.network(
                              product.imagen,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surfaceVariant,
                                child: const Icon(Icons.broken_image,
                                    color: AppColors.textLight),
                              ),
                            )
                          : Container(
                              color: AppColors.surfaceVariant,
                              child: const Icon(
                                  Icons.image_not_supported_outlined),
                            ),
                    ),
                  ),
                  if (sinStock)
                    Positioned(
                      top: 2,
                      left: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppColors.warning,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.warning_amber_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
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
                            '\$${product.precioVenta.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (product.categoriaNombre.isNotEmpty)
                          Flexible(
                            child: Text(
                              product.categoriaNombre,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textLight),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          sinStock
                              ? Icons.warning_amber_rounded
                              : Icons.inventory_2_outlined,
                          size: 13,
                          color: sinStock
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          stockText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: sinStock
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: sinStock
                                ? AppColors.warning
                                : AppColors.textSecondary,
                          ),
                        ),
                        if (product.ubicacion != null &&
                            product.ubicacion!.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          const Icon(Icons.place_outlined,
                              size: 13, color: AppColors.textLight),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              product.ubicacion!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textLight,
                              ),
                            ),
                          ),
                        ],
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
