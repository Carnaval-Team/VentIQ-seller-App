import 'package:flutter/material.dart';

import '../../config/app_colors.dart';
import '../../services/sales_service.dart';

/// Selector de producto para el widget de seguimiento.
///
/// Se alimenta de `fn_vista_precios_productos3` (el mismo RPC que ya usa la
/// pestaña de análisis de SalesScreen), así que la lista trae de una sola vez
/// nombre, precio y costos: no hace falta ningún endpoint nuevo.
///
/// Devuelve `(id, nombre)` al hacer pop.
class WidgetProductPickerScreen extends StatefulWidget {
  const WidgetProductPickerScreen({super.key, required this.storeId});

  final int storeId;

  @override
  State<WidgetProductPickerScreen> createState() =>
      _WidgetProductPickerScreenState();
}

class _WidgetProductPickerScreenState extends State<WidgetProductPickerScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _loading = true;
  String? _error;
  List<ProductAnalysis> _all = const [];
  List<ProductAnalysis> _filtered = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final products = await SalesService.getProductAnalysis(
        storeId: widget.storeId,
      );
      // Orden alfabético: el usuario busca por nombre, no por margen.
      products.sort(
        (a, b) => a.nombreProducto.toLowerCase().compareTo(
              b.nombreProducto.toLowerCase(),
            ),
      );
      if (!mounted) return;
      setState(() {
        _all = products;
        _filtered = products;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _filter(String query) {
    final normalized = query.trim().toLowerCase();
    setState(() {
      _filtered = normalized.isEmpty
          ? _all
          : _all
              .where(
                (product) =>
                    product.nombreProducto.toLowerCase().contains(normalized),
              )
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Elegir producto')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: _filter,
              decoration: InputDecoration(
                hintText: 'Buscar producto…',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: AppColors.error, size: 40),
              const SizedBox(height: 12),
              Text(
                'No se pudieron cargar los productos.\n$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    if (_filtered.isEmpty) {
      return const Center(
        child: Text(
          'Sin productos que coincidan.',
          style: TextStyle(color: AppColors.textSecondary),
        ),
      );
    }

    return ListView.separated(
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final product = _filtered[index];
        return ListTile(
          title: Text(product.nombreProducto),
          subtitle: Text(
            'Venta \$${product.precioVentaCup.toStringAsFixed(2)} · '
            'Costo \$${product.precioCostoCup.toStringAsFixed(2)}',
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pop(
            (id: product.idProducto, nombre: product.nombreProducto),
          ),
        );
      },
    );
  }
}
