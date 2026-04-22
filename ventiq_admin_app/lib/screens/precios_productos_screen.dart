import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../services/currency_service.dart';
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
  double _usdRate = 0.0;
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

      // Cargar tasa de cambio (con fallback si falla)
      try {
        _usdRate = await CurrencyService.getEffectiveUsdToCupRate();
        if (_usdRate <= 0) _usdRate = 440.0;
      } catch (_) {
        _usdRate = 440.0;
      }

      // Productos activos de la tienda con su precio de venta y proveedor
      final productosResp = await _supabase
          .from('app_dat_producto')
          .select('''
            id, denominacion, sku, imagen, id_proveedor,
            app_dat_precio_venta(id, precio_venta_cup, precio_venta_usd),
            app_dat_proveedor(id, denominacion)
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

      // Stock por (id_producto, id_presentacion): sumar cantidad_final
      // del último registro de cada ubicación (fuente: app_dat_inventario_productos).
      final Map<String, double> stockByProductoPresentacion = {};
      if (productoIds.isNotEmpty) {
        final presentacionIds = presentacionesResp
            .map((p) => p['id'] as int)
            .toSet()
            .toList();
        if (presentacionIds.isNotEmpty) {
          final inventarioResp = await _supabase
              .from('app_dat_inventario_productos')
              .select(
                'id, id_producto, id_presentacion, id_ubicacion, cantidad_final, created_at',
              )
              .inFilter('id_producto', productoIds)
              .inFilter('id_presentacion', presentacionIds)
              .order('created_at', ascending: false)
              .order('id', ascending: false);

          // Último registro por (producto, presentacion, ubicacion)
          final Map<String, double> lastByCombo = {};
          for (final row in (inventarioResp as List)) {
            final pid = row['id_producto'];
            final presId = row['id_presentacion'];
            final ubId = row['id_ubicacion'];
            if (pid == null || presId == null) continue;
            final key = '${pid}_${presId}_${ubId ?? 'null'}';
            if (lastByCombo.containsKey(key)) continue; // ya tenemos el más reciente
            final qty = (row['cantidad_final'] as num?)?.toDouble() ?? 0.0;
            lastByCombo[key] = qty;
          }

          // Sumar por (producto, presentacion)
          lastByCombo.forEach((key, qty) {
            final parts = key.split('_');
            final aggKey = '${parts[0]}_${parts[1]}';
            stockByProductoPresentacion[aggKey] =
                (stockByProductoPresentacion[aggKey] ?? 0) + qty;
          });
        }
      }

      // Adjuntar stock a cada presentación
      for (final p in presentacionesResp) {
        final aggKey = '${p['id_producto']}_${p['id']}';
        p['stock_total'] = stockByProductoPresentacion[aggKey] ?? 0.0;
      }

      // Combinar
      final List<Map<String, dynamic>> combined = [];
      for (final prod in productosResp) {
        final pid = prod['id'] as int;
        final precioVentaList =
            List<Map<String, dynamic>>.from(prod['app_dat_precio_venta'] as List? ?? []);
        // Sort descending by id to get the latest record first
        precioVentaList.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
        final latest = precioVentaList.isNotEmpty ? precioVentaList.first : null;
        final precioVenta = (latest?['precio_venta_cup'] as num?)?.toDouble();
        final precioVentaUsd = (latest?['precio_venta_usd'] as num?)?.toDouble();
        final precioVentaId = latest?['id'] as int?;

        final proveedor = prod['app_dat_proveedor'] as Map<String, dynamic>?;
        combined.add({
          'id': pid,
          'denominacion': prod['denominacion'] ?? '',
          'sku': prod['sku'] ?? '',
          'imagen': prod['imagen'],
          'id_proveedor': prod['id_proveedor'],
          'proveedor': proveedor?['denominacion'] as String?,
          'precio_venta': precioVenta,
          'precio_venta_usd': precioVentaUsd,
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
    final cupController = TextEditingController(
      text: producto['precio_venta'] != null
          ? (producto['precio_venta'] as double).toStringAsFixed(2)
          : '',
    );
    final usdController = TextEditingController(
      text: producto['precio_venta_usd'] != null
          ? (producto['precio_venta_usd'] as double).toStringAsFixed(2)
          : '',
    );
    bool updatingFromCup = false;
    bool updatingFromUsd = false;

    // Returns null if cancelled, otherwise {cup, usd}
    final result = await showDialog<Map<String, double?>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          return AlertDialog(
            title: const Text('Editar Precio de Venta'),
            content: SingleChildScrollView(
              child: Column(
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
                  if (_usdRate > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Tasa: ${_usdRate.toStringAsFixed(0)} CUP/USD',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Campo CUP
                  TextField(
                    controller: cupController,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      if (updatingFromUsd) return;
                      updatingFromCup = true;
                      if (_usdRate > 0) {
                        final cup = double.tryParse(value);
                        if (cup != null && cup > 0) {
                          final usdText = (cup / _usdRate).toStringAsFixed(2);
                          if (usdController.text != usdText) {
                            usdController.text = usdText;
                          }
                        } else {
                          usdController.clear();
                        }
                      }
                      setS(() {});
                      updatingFromCup = false;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Precio CUP',
                      prefixText: '₱ ',
                      border: OutlineInputBorder(),
                      hintText: '0.00',
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Campo USD
                  TextField(
                    controller: usdController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (value) {
                      if (updatingFromCup) return;
                      updatingFromUsd = true;
                      if (_usdRate > 0) {
                        final usd = double.tryParse(value);
                        if (usd != null && usd > 0) {
                          final cupText = (usd * _usdRate).toStringAsFixed(2);
                          if (cupController.text != cupText) {
                            cupController.text = cupText;
                          }
                        } else {
                          cupController.clear();
                        }
                      }
                      setS(() {});
                      updatingFromUsd = false;
                    },
                    decoration: const InputDecoration(
                      labelText: 'Precio USD',
                      prefixText: '\$ ',
                      border: OutlineInputBorder(),
                      hintText: '0.00',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              ElevatedButton(
                onPressed: () {
                  final cup = double.tryParse(cupController.text);
                  if (cup == null || cup <= 0) return;
                  final usd = double.tryParse(usdController.text);
                  Navigator.pop(ctx, {
                    'cup': cup,
                    'usd': (usd != null && usd > 0) ? usd : null,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Guardar'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;

    final newCup = result['cup'];
    final newUsd = result['usd'];
    if (newCup == null || newCup < 0) {
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
      newPrice: newCup,
      newPriceUsd: newUsd,
    );

    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Precio de venta actualizado'),
          backgroundColor: AppColors.success,
        ),
      );
      // Recargar solo el producto modificado (último precio = mayor id)
      final productId = producto['id'] as int;
      final precioVentaList = await _supabase
          .from('app_dat_precio_venta')
          .select('id, precio_venta_cup, precio_venta_usd')
          .eq('id_producto', productId)
          .order('id', ascending: false)
          .limit(1);

      final latest = precioVentaList.isNotEmpty ? precioVentaList.first : null;
      final precioVenta = (latest?['precio_venta_cup'] as num?)?.toDouble();
      final precioVentaUsd = (latest?['precio_venta_usd'] as num?)?.toDouble();
      final precioVentaId = latest?['id'] as int?;

      if (mounted) {
        setState(() {
          final index = _productos.indexWhere((p) => p['id'] == productId);
          if (index != -1) {
            _productos[index]['precio_venta'] = precioVenta;
            _productos[index]['precio_venta_usd'] = precioVentaUsd;
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
                labelText: 'Precio Costo (Promedio) USD',
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
    final precioVentaUsd = producto['precio_venta_usd'] as double?;
    final hasBoth = (precioVenta != null && precioVenta > 1) &&
        (precioVentaUsd != null && precioVentaUsd > 0);
    bool mismatch = false;
    if (hasBoth && _usdRate > 0) {
      final cup = (producto['precio_venta'] as double);
      final usd = (producto['precio_venta_usd'] as double);
      mismatch = ((cup - usd * _usdRate).abs() / (usd * _usdRate)) > 0.02;
    }

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
                      if ((producto['proveedor'] as String?)?.isNotEmpty ?? false) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Icon(
                              Icons.local_shipping_outlined,
                              size: 11,
                              color: Colors.grey[500],
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                producto['proveedor'] as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[600],
                                  fontStyle: FontStyle.italic,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.sell_outlined, size: 16, color: AppColors.primary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'Precio de Venta',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                          if (mismatch) ...[
                            const SizedBox(width: 6),
                            Tooltip(
                              message:
                                  'CUP y USD no coinciden con la tasa\n'
                                  '(Tasa: ${_usdRate.toStringAsFixed(0)} CUP/USD)',
                              child: const Icon(
                                Icons.warning_amber_rounded,
                                size: 14,
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        precioVenta != null && precioVenta > 1
                            ? '₱${precioVenta.toStringAsFixed(2)} CUP'
                            : 'Sin precio CUP',
                        style: TextStyle(
                          fontSize: 16,
                          color: precioVenta != null && precioVenta > 1
                              ? const Color(0xFF1F2937)
                              : Colors.red[600],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (precioVentaUsd != null && precioVentaUsd > 0) ...[
                        const SizedBox(height: 1),
                        Text(
                          '\$${precioVentaUsd.toStringAsFixed(2)} USD',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: mismatch
                                ? Colors.orange[700]
                                : const Color(0xFF4A90E2),
                          ),
                        ),
                      ],
                      if (mismatch) ...[
                        const SizedBox(height: 3),
                        Text(
                          'Esperado: ₱${(precioVentaUsd! * _usdRate).toStringAsFixed(2)} CUP',
                          style: TextStyle(fontSize: 13, color: Colors.orange[700]),
                        ),
                      ],
                    ],
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
    final rawCosto = pres['precio_promedio'];
    final costoUsdVal = rawCosto is num
        ? rawCosto.toDouble()
        : double.tryParse(rawCosto?.toString() ?? '') ?? 0.0;
    final esBase = pres['es_base'] as bool? ?? false;

    final tieneCosto = costoUsdVal > 0 && costoUsdVal != 0.0019;

    // Precio de venta en USD (directo o convertido desde CUP)
    final ventaCup = (producto['precio_venta'] as double?) ?? 0.0;
    final ventaUsd = (producto['precio_venta_usd'] as double?) ??
        (_usdRate > 0 && ventaCup > 1 ? ventaCup / _usdRate : null);

    // Costo ya está en USD (precio_promedio se almacena en USD)
    final costoUsd = tieneCosto ? costoUsdVal : null;

    // Ganancia
    double? gananciaUsd;
    double? porcGanancia;
    if (ventaUsd != null && ventaUsd > 0 && costoUsd != null && costoUsd > 0) {
      gananciaUsd = ventaUsd - costoUsd;
      porcGanancia = (gananciaUsd / ventaUsd) * 100;
    }
    final esPositiva = gananciaUsd != null && gananciaUsd >= 0;

    final costoCup = (tieneCosto && _usdRate > 0) ? costoUsdVal * _usdRate : null;
    final stockTotal = (pres['stock_total'] as num?)?.toDouble() ?? 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Fila 1: nombre presentación + badge BASE + botón editar
          Row(
            children: [
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF374151),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              InkWell(
                onTap: () => _editPrecioPromedio(producto, pres),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit,
                    size: 14,
                    color: Color(0xFF10B981),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Fila 2: Costo (label + USD + CUP)
          if (!tieneCosto)
            Text(
              'Sin costo',
              style: TextStyle(fontSize: 12, color: Colors.red[400]),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Costo',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '\$${costoUsdVal.toStringAsFixed(2)} USD',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 18,
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (costoCup != null)
                      Text(
                        '${_formatMoney(costoCup)} CUP',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 15,
                          color: Colors.grey[700],
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ],
          // Fila 3: Stock (izq) + Ganancia (der)
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Stock por presentación a la izquierda
              _buildStockBadge(stockTotal),
              const Spacer(),
              // Ganancia alineada a la derecha
              if (gananciaUsd != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (esPositiva ? Colors.green : Colors.red).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        esPositiva ? Icons.trending_up : Icons.trending_down,
                        size: 14,
                        color: esPositiva ? Colors.green[700] : Colors.red[700],
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '\$${gananciaUsd.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: esPositiva ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '(${porcGanancia!.toStringAsFixed(1)}%)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: esPositiva ? Colors.green[700] : Colors.red[700],
                        ),
                      ),
                    ],
                  ),
                )
              else if (tieneCosto && ventaUsd == null)
                Text(
                  'Sin precio venta',
                  style: TextStyle(fontSize: 11, color: Colors.orange[600]),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatMoney(double v) {
    final s = v.toStringAsFixed(0);
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final remaining = s.length - i;
      buf.write(s[i]);
      if (remaining > 1 && remaining % 3 == 1) buf.write(',');
    }
    return buf.toString();
  }

  Widget _buildStockBadge(double stock) {
    final hasStock = stock > 0;
    final color = hasStock ? const Color(0xFF4A90E2) : Colors.grey;
    final qtyText = stock % 1 == 0
        ? stock.toInt().toString()
        : stock.toStringAsFixed(2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_outlined, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            'Stock: $qtyText',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
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
