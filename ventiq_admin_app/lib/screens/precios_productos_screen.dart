import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../utils/navigation_guard.dart';

class PreciosProductosScreen extends StatefulWidget {
  const PreciosProductosScreen({super.key});

  @override
  State<PreciosProductosScreen> createState() => _PreciosProductosScreenState();
}

class _PreciosProductosScreenState extends State<PreciosProductosScreen> {
  final _supabase = Supabase.instance.client;
  final _userPrefs = UserPreferencesService();

  List<Map<String, dynamic>> _productos = [];
  List<Map<String, dynamic>> _filteredProductos = [];
  bool _isLoading = true;
  String _searchQuery = '';
  bool _filterSinPrecioVenta = false;
  bool _filterSinPrecioCosto = false;
  double? _filterPrecioCosto;
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _filterPrecioController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _filterPrecioController.dispose();
    super.dispose();
  }

  // ── carga ─────────────────────────────────────────────────────

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final storeId = await _userPrefs.getIdTienda();
      if (storeId == null) throw Exception('No se pudo obtener la tienda');

      // Productos activos de la tienda con su precio de venta
      final productosResp = await _supabase
          .from('app_dat_producto')
          .select('''
            id, denominacion, sku, imagen,
            app_dat_precio_venta(id, precio_venta_cup)
          ''')
          .eq('id_tienda', storeId)
          .isFilter('deleted_at', null)
          .order('denominacion');

      // Presentaciones de todos esos productos
      final productoIds = (productosResp as List)
          .map((p) => p['id'] as int)
          .toList();

      List<Map<String, dynamic>> presentacionesResp = [];
      if (productoIds.isNotEmpty) {
        final resp = await _supabase
            .from('app_dat_producto_presentacion')
            .select('''
              id, id_producto, cantidad, es_base, precio_promedio,
              app_nom_presentacion!inner(id, denominacion)
            ''')
            .inFilter('id_producto', productoIds);
        presentacionesResp = List<Map<String, dynamic>>.from(resp);
      }

      // Agrupar presentaciones por id_producto
      final Map<int, List<Map<String, dynamic>>> pressByProduct = {};
      for (final p in presentacionesResp) {
        final pid = p['id_producto'] as int;
        pressByProduct.putIfAbsent(pid, () => []).add(p);
      }

      // Combinar
      final List<Map<String, dynamic>> combined = [];
      for (final prod in productosResp) {
        final pid = prod['id'] as int;
        final precioVentaList = prod['app_dat_precio_venta'] as List? ?? [];
        final precioVenta = precioVentaList.isNotEmpty
            ? (precioVentaList.first['precio_venta_cup'] as num?)?.toDouble()
            : null;
        final precioVentaId = precioVentaList.isNotEmpty
            ? precioVentaList.first['id'] as int?
            : null;

        combined.add({
          'id': pid,
          'denominacion': prod['denominacion'] ?? '',
          'sku': prod['sku'] ?? '',
          'imagen': prod['imagen'],
          'precio_venta': precioVenta,
          'precio_venta_id': precioVentaId,
          'presentaciones': pressByProduct[pid] ?? [],
        });
      }

      if (!mounted) return;
      setState(() {
        _productos = combined;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al cargar productos: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  void _applyFilter() {
    final q = _searchQuery.toLowerCase().trim();
    _filteredProductos = _productos.where((p) {
      // Filtro texto
      if (q.isNotEmpty) {
        final matchText =
            (p['denominacion'] as String).toLowerCase().contains(q) ||
            (p['sku'] as String).toLowerCase().contains(q);
        if (!matchText) return false;
      }
      // Filtro sin precio de venta
      if (_filterSinPrecioVenta) {
        final pv = p['precio_venta'] as double?;
        if (pv != null && pv != 0 && pv != 1) return false;
      }
      // Filtro sin precio de costo (alguna presentacion sin costo)
      if (_filterSinPrecioCosto) {
        final pres = p['presentaciones'] as List<Map<String, dynamic>>;
        final sinCosto = pres.any(
          (pp) {
            final precio = (pp['precio_promedio'] as num?)?.toDouble() ?? 0.0;
            return precio == 0 || precio == 0.0019;
          },
        );
        if (!sinCosto) return false;
      }
      // Filtro por precio de costo específico
      if (_filterPrecioCosto != null) {
        final pres = p['presentaciones'] as List<Map<String, dynamic>>;
        final tienePrecio = pres.any(
          (pp) {
            final precio = (pp['precio_promedio'] as num?)?.toDouble() ?? 0.0;
            return (precio - _filterPrecioCosto!).abs() < 0.0001;
          },
        );
        if (!tienePrecio) return false;
      }
      return true;
    }).toList()
      ..sort((a, b) => (a['denominacion'] as String)
          .toLowerCase()
          .compareTo((b['denominacion'] as String).toLowerCase()));
  }

  // ── edición precio de venta ───────────────────────────────────

  Future<void> _editPrecioVenta(Map<String, dynamic> producto) async {
    final controller = TextEditingController(
      text: producto['precio_venta']?.toStringAsFixed(2) ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Precio de Venta'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              producto['denominacion'] as String,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio de Venta CUP',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final newPrice = double.tryParse(controller.text);
    if (newPrice == null || newPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio inválido'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final success = await ProductService.updateBasePriceVenta(
      productId: producto['id'] as int,
      newPrice: newPrice,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio de venta actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
      // Actualizar solo el producto modificado
      final productId = producto['id'] as int;
      final precioVentaList = await _supabase
          .from('app_dat_precio_venta')
          .select('id, precio_venta_cup')
          .eq('id_producto', productId);
      
      final precioVenta = precioVentaList.isNotEmpty
          ? (precioVentaList.first['precio_venta_cup'] as num?)?.toDouble()
          : null;
      final precioVentaId = precioVentaList.isNotEmpty
          ? precioVentaList.first['id'] as int?
          : null;

      if (mounted) {
        setState(() {
          // Encontrar y actualizar el producto en la lista
          final index = _productos.indexWhere((p) => p['id'] == productId);
          if (index != -1) {
            _productos[index]['precio_venta'] = precioVenta;
            _productos[index]['precio_venta_id'] = precioVentaId;
            _applyFilter();
          }
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar precio de venta'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ── edición precio promedio (costo) de presentación ──────────

  Future<void> _editPrecioPromedio(
    Map<String, dynamic> producto,
    Map<String, dynamic> presentacion,
  ) async {
    final precioActual =
        (presentacion['precio_promedio'] as num?)?.toDouble() ?? 0.0;
    final controller = TextEditingController(
      text: precioActual > 0 ? precioActual.toStringAsFixed(2) : '',
    );
    final nomPres =
        (presentacion['app_nom_presentacion'] as Map?)?['denominacion'] ??
        'Presentación';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar Precio de Costo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              producto['denominacion'] as String,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            Text(
              'Presentación: $nomPres',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Precio Costo (Promedio) CUP',
                prefixText: '\$ ',
                border: OutlineInputBorder(),
                hintText: '0.00',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final newPrice = double.tryParse(controller.text);
    if (newPrice == null || newPrice < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio inválido'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }

    final success = await ProductService.updatePresentationAveragePrice(
      presentationId: presentacion['id'].toString(),
      newPrice: newPrice,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio de costo actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
      // Actualizar solo la presentación modificada
      final presentationId = presentacion['id'] as int;
      final updatedPres = await _supabase
          .from('app_dat_producto_presentacion')
          .select('id, id_producto, cantidad, es_base, precio_promedio, app_nom_presentacion!inner(id, denominacion)')
          .eq('id', presentationId)
          .single();

      if (mounted) {
        setState(() {
          // Encontrar el producto y actualizar su presentación
          final productId = producto['id'] as int;
          final productIndex = _productos.indexWhere((p) => p['id'] == productId);
          if (productIndex != -1) {
            final presentaciones = _productos[productIndex]['presentaciones'] as List<Map<String, dynamic>>;
            final presIndex = presentaciones.indexWhere((p) => p['id'] == presentationId);
            if (presIndex != -1) {
              presentaciones[presIndex] = updatedPres;
            }
            _applyFilter();
          }
        });
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error al actualizar precio de costo'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Gestión de Precios',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: AppColors.primary,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: _loadData,
            tooltip: 'Recargar',
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildLegend(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProductos.isEmpty
                    ? _buildEmpty()
                    : _buildList(),
          ),
        ],
      ),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 1,
        onTap: (index) {
          switch (index) {
            case 0:
              NavigationGuard.navigateAndRemoveUntil(context, '/dashboard');
              break;
            case 1:
              Navigator.pop(context);
              break;
            case 2:
              NavigationGuard.navigateWithPermission(context, '/inventory');
              break;
            case 3:
              NavigationGuard.navigateWithPermission(context, '/warehouse');
              break;
          }
        },
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar por nombre o SKU...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _applyFilter();
                    });
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        onChanged: (v) => setState(() {
          _searchQuery = v;
          _applyFilter();
        }),
      ),
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Chips de filtro rápido
          Row(
            children: [
              _filterChip(
                label: 'Sin precio venta',
                icon: Icons.sell_outlined,
                active: _filterSinPrecioVenta,
                activeColor: Colors.orange[700]!,
                onTap: () => setState(() {
                  _filterSinPrecioVenta = !_filterSinPrecioVenta;
                  _applyFilter();
                }),
              ),
              const SizedBox(width: 8),
              _filterChip(
                label: 'Sin precio costo',
                icon: Icons.inventory_2_outlined,
                active: _filterSinPrecioCosto,
                activeColor: const Color(0xFF10B981),
                onTap: () => setState(() {
                  _filterSinPrecioCosto = !_filterSinPrecioCosto;
                  _applyFilter();
                }),
              ),
              const Spacer(),
              Text(
                '${_filteredProductos.length} producto${_filteredProductos.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, color: Colors.grey[500]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Filtro por precio de costo específico
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _filterPrecioController,
                  decoration: InputDecoration(
                    hintText: 'Filtrar por precio costo...',
                    prefixIcon: const Icon(Icons.attach_money, size: 18),
                    suffixIcon: _filterPrecioCosto != null
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _filterPrecioController.clear();
                              setState(() {
                                _filterPrecioCosto = null;
                                _applyFilter();
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (value) {
                    setState(() {
                      _filterPrecioCosto = double.tryParse(value);
                      _applyFilter();
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required IconData icon,
    required bool active,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(0.12) : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? activeColor : Colors.grey[300]!,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: active ? activeColor : Colors.grey[500],
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? activeColor : Colors.grey[600],
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              Icon(Icons.close, size: 11, color: activeColor),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.price_change_outlined, size: 56, color: Colors.grey[300]),
          const SizedBox(height: 12),
          Text(
            _searchQuery.isEmpty
                ? 'No hay productos en esta tienda'
                : 'Sin resultados para "$_searchQuery"',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: _filteredProductos.length,
      itemBuilder: (_, i) => _buildProductCard(_filteredProductos[i]),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> producto) {
    final presentaciones =
        (producto['presentaciones'] as List<Map<String, dynamic>>);
    final precioVenta = producto['precio_venta'] as double?;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header producto ──
            Row(
              children: [
                // Thumbnail
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: producto['imagen'] != null
                      ? Image.network(
                          producto['imagen'] as String,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => _productPlaceholder(),
                        )
                      : _productPlaceholder(),
                ),
                const SizedBox(width: 12),
                // Nombre y SKU
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        producto['denominacion'] as String,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      if ((producto['sku'] as String).isNotEmpty)
                        Text(
                          'SKU: ${producto['sku']}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[500],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),

            // ── Precio de Venta ──
            Row(
              children: [
                Icon(Icons.sell_outlined, size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Text(
                  'Precio de Venta:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    precioVenta != null && precioVenta != 0 && precioVenta != 1
                        ? '\$ ${precioVenta.toStringAsFixed(2)} CUP'
                        : 'Sin precio',
                    style: TextStyle(
                      fontSize: 13,
                      color: precioVenta != null && precioVenta != 0 && precioVenta != 1
                          ? const Color(0xFF1F2937)
                          : Colors.red[600],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _editPrecioVenta(producto),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.edit,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),

            // ── Presentaciones / precio costo ──
            if (presentaciones.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 16,
                    color: const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Precio Costo por presentación:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ...presentaciones.map(
                (pres) => _buildPresentacionRow(producto, pres),
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Sin presentaciones configuradas',
                style: TextStyle(fontSize: 11, color: Colors.grey[400]),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPresentacionRow(
    Map<String, dynamic> producto,
    Map<String, dynamic> pres,
  ) {
    final nomPres =
        (pres['app_nom_presentacion'] as Map?)?['denominacion'] ?? 'Base';
    final cantidad = (pres['cantidad'] as num?)?.toDouble() ?? 1.0;
    final costo = (pres['precio_promedio'] as num?)?.toDouble() ?? 0.0;
    final esBase = pres['es_base'] as bool? ?? false;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          const SizedBox(width: 22),
          if (esBase)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'BASE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF10B981),
                ),
              ),
            ),
          Expanded(
            child: Text(
              '$nomPres (x${cantidad % 1 == 0 ? cantidad.toInt() : cantidad})',
              style: const TextStyle(fontSize: 12, color: Color(0xFF374151)),
            ),
          ),
          Text(
            costo != 0 && costo != 0.0019 ? '\$ ${costo.toStringAsFixed(4)}' : 'Sin costo',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: costo != 0 && costo != 0.0019 ? const Color(0xFF1F2937) : Colors.red[600],
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: () => _editPrecioPromedio(producto, pres),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.edit,
                size: 14,
                color: const Color(0xFF10B981),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _productPlaceholder() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.inventory_2_outlined, size: 22, color: Colors.grey[400]),
    );
  }
}
