import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';

/// Modelo local para un item por defecto configurado por el vendedor.
class DefaultOrderItem {
  final Product product;
  double cantidad;

  DefaultOrderItem({required this.product, required this.cantidad});

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'cantidad': cantidad,
      };

  static DefaultOrderItem fromJson(Map<String, dynamic> json) {
    return DefaultOrderItem(
      product: Product.fromJson(json['product'] as Map<String, dynamic>),
      cantidad: (json['cantidad'] as num).toDouble(),
    );
  }
}

class DefaultOrderItemsScreen extends StatefulWidget {
  const DefaultOrderItemsScreen({Key? key}) : super(key: key);

  @override
  State<DefaultOrderItemsScreen> createState() =>
      _DefaultOrderItemsScreenState();
}

class _DefaultOrderItemsScreenState extends State<DefaultOrderItemsScreen> {
  final UserPreferencesService _prefs = UserPreferencesService();
  final ProductService _productService = ProductService();

  List<DefaultOrderItem> _items = [];
  bool _loading = true;
  bool _saving = false;

  // Product search state
  final TextEditingController _searchController = TextEditingController();
  List<Product> _searchResults = [];
  bool _isSearching = false;
  bool _showResults = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final raw = await _prefs.getDefaultOrderItems();
      final items = raw.map((e) => DefaultOrderItem.fromJson(e)).toList();
      if (mounted) setState(() => _items = items);
    } catch (e) {
      print('❌ Error cargando productos por defecto: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveItems() async {
    setState(() => _saving = true);
    try {
      await _prefs.saveDefaultOrderItems(
        _items.map((i) => i.toJson()).toList(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Productos por defecto guardados'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error guardando: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _onSearchChanged() {
    final q = _searchController.text.trim();
    if (q.length >= 2) {
      _runSearch(q);
    } else {
      setState(() {
        _searchResults = [];
        _showResults = false;
      });
    }
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _isSearching = true;
      _showResults = true;
    });
    try {
      final results = await _productService.searchProducts(query: q);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    }
  }

  void _addProduct(Product product) {
    final existing = _items.indexWhere((i) => i.product.id == product.id);
    if (existing != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${product.denominacion} ya está en la lista'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    setState(() {
      _items.add(DefaultOrderItem(product: product, cantidad: 1));
      _searchController.clear();
      _showResults = false;
      _searchResults = [];
    });
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _updateCantidad(int index, double value) {
    if (value < 0) return;
    setState(() => _items[index].cantidad = value);
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar lista'),
        content: const Text(
            '¿Eliminar todos los productos por defecto?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Eliminar todo',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _items.clear());
      await _prefs.clearDefaultOrderItems();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lista limpiada'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: const Color(0xFF4A90E2),
        elevation: 0,
        title: const Text(
          'Productos por Defecto',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Limpiar todo',
              onPressed: _clearAll,
            ),
          IconButton(
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.save_outlined),
            tooltip: 'Guardar',
            onPressed: _saving ? null : _saveItems,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildInfoBanner(),
                _buildSearchBar(),
                if (_showResults) _buildSearchResults(),
                Expanded(child: _buildItemList()),
              ],
            ),
      bottomNavigationBar: _items.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _saveItems,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save),
                  label: Text(_saving ? 'Guardando...' : 'Guardar cambios'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4A90E2),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF4A90E2).withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF4A90E2).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline,
              color: Color(0xFF4A90E2), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Estos productos se agregarán automáticamente al iniciar una nueva orden. '
              'Funciona también en modo offline.',
              style: TextStyle(fontSize: 12, color: Color(0xFF374151)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar producto por nombre o SKU...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: _isSearching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child:
                        CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Icon(Icons.search, color: Color(0xFF4A90E2)),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _showResults = false;
                      _searchResults = [];
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: Color(0xFF4A90E2), width: 1.5),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            'No se encontraron productos',
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 240),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: Colors.grey[100]),
        itemBuilder: (_, i) {
          final p = _searchResults[i];
          final alreadyAdded = _items.any((item) => item.product.id == p.id);
          return ListTile(
            dense: true,
            title: Text(
              p.denominacion,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (p.sku != null && p.sku!.isNotEmpty)
                  Text('SKU: ${p.sku}',
                      style: const TextStyle(
                          fontSize: 11, color: Color(0xFF4A90E2))),
                Text('\$${p.precio.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF0EA5E9))),
              ],
            ),
            trailing: alreadyAdded
                ? const Icon(Icons.check_circle,
                    color: Color(0xFF10B981), size: 20)
                : IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: Color(0xFF4A90E2)),
                    onPressed: () => _addProduct(p),
                  ),
            onTap: alreadyAdded ? null : () => _addProduct(p),
          );
        },
      ),
    );
  }

  Widget _buildItemList() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.playlist_add, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text(
              'Sin productos configurados',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[500]),
            ),
            const SizedBox(height: 6),
            Text(
              'Busca un producto arriba para agregarlo',
              style: TextStyle(fontSize: 13, color: Colors.grey[400]),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _items.length,
      itemBuilder: (_, i) => _buildItemTile(i),
    );
  }

  Widget _buildItemTile(int index) {
    final item = _items[index];
    final cantidadController = TextEditingController(
      text: item.cantidad == item.cantidad.roundToDouble()
          ? item.cantidad.toInt().toString()
          : item.cantidad.toString(),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.denominacion,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                if (item.product.sku != null &&
                    item.product.sku!.isNotEmpty)
                  Text(
                    'SKU: ${item.product.sku}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF4A90E2)),
                  ),
                Text(
                  '\$${item.product.precio.toStringAsFixed(2)} c/u',
                  style:
                      TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Qty controls
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _iconBtn(
                icon: Icons.remove,
                onTap: () => _updateCantidad(index, item.cantidad - 1),
                color: const Color(0xFF6B7280),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 52,
                child: TextField(
                  controller: cantidadController,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9.]')),
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide:
                          BorderSide(color: Colors.grey[300]!),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: const BorderSide(
                          color: Color(0xFF4A90E2), width: 1.5),
                    ),
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed >= 0) {
                      _updateCantidad(index, parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: 4),
              _iconBtn(
                icon: Icons.add,
                onTap: () => _updateCantidad(index, item.cantidad + 1),
                color: const Color(0xFF0EA5E9),
              ),
            ],
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(Icons.delete_outline, color: Colors.red[400]),
            onPressed: () => _removeItem(index),
            tooltip: 'Eliminar',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}
