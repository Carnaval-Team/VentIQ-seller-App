import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/product.dart';
import '../models/inventory.dart'; // Contains InventoryProduct, InventoryResponse, etc.
import '../services/product_service.dart';
import '../services/inventory_service.dart';
import '../services/warehouse_service.dart';
import '../services/presentation_service.dart';
import '../services/variant_service.dart';

class InventoryAdjustmentScreen extends StatefulWidget {
  final int operationType; // 3 para faltante (sumar), 4 para exceso (restar)
  final String adjustmentType; // 'shortage' o 'excess'

  const InventoryAdjustmentScreen({
    super.key,
    required this.operationType,
    required this.adjustmentType,
  });

  @override
  State<InventoryAdjustmentScreen> createState() => _InventoryAdjustmentScreenState();
}

class _InventoryAdjustmentScreenState extends State<InventoryAdjustmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _quantityController = TextEditingController();
  final _reasonController = TextEditingController();
  final _observationsController = TextEditingController();

  List<Product> _products = [];
  List<Product> _filteredProducts = [];
  Product? _selectedProduct;
  
  List<Map<String, dynamic>> _warehousesWithZones = [];
  Map<String, dynamic>? _selectedZone;
  
  List<Map<String, dynamic>> _presentations = [];
  Map<String, dynamic>? _selectedPresentation;
  
  List<Map<String, dynamic>> _variants = [];
  Map<String, dynamic>? _selectedVariant;
  
  double? _currentStock;
  
  bool _isLoading = false;
  bool _isLoadingProducts = false;
  bool _isLoadingZones = false;
  bool _isLoadingPresentations = false;
  bool _isLoadingVariants = false;
  bool _isLoadingStock = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _quantityController.dispose();
    _reasonController.dispose();
    _observationsController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoadingProducts = true);
    try {
      // Obtener productos con stock disponible usando el servicio real
      final inventoryResponse = await InventoryService.getInventoryProducts(
        mostrarSinStock: false, // Solo productos con stock
        esInventariable: true,  // Solo productos inventariables
        limite: 100,
      );
      
      // Agrupar productos por ID para evitar duplicados
      final Map<int, InventoryProduct> uniqueProducts = {};
      for (final inventoryProduct in inventoryResponse.products) {
        final productId = inventoryProduct.id;
        if (!uniqueProducts.containsKey(productId)) {
          uniqueProducts[productId] = inventoryProduct;
        } else {
          // Si ya existe, sumar el stock disponible
          final existing = uniqueProducts[productId]!;
          uniqueProducts[productId] = InventoryProduct(
            id: existing.id,
            skuProducto: existing.skuProducto,
            nombreProducto: existing.nombreProducto,
            idCategoria: existing.idCategoria,
            categoria: existing.categoria,
            idSubcategoria: existing.idSubcategoria,
            subcategoria: existing.subcategoria,
            idTienda: existing.idTienda,
            tienda: existing.tienda,
            idAlmacen: existing.idAlmacen,
            almacen: existing.almacen,
            idUbicacion: existing.idUbicacion,
            ubicacion: existing.ubicacion,
            idVariante: existing.idVariante,
            variante: existing.variante,
            idOpcionVariante: existing.idOpcionVariante,
            opcionVariante: existing.opcionVariante,
            idPresentacion: existing.idPresentacion,
            presentacion: existing.presentacion,
            cantidadInicial: existing.cantidadInicial + inventoryProduct.cantidadInicial,
            cantidadFinal: existing.cantidadFinal + inventoryProduct.cantidadFinal,
            stockDisponible: existing.stockDisponible + inventoryProduct.stockDisponible,
            stockReservado: existing.stockReservado + inventoryProduct.stockReservado,
            stockDisponibleAjustado: existing.stockDisponibleAjustado + inventoryProduct.stockDisponibleAjustado,
            esVendible: existing.esVendible,
            esInventariable: existing.esInventariable,
            precioVenta: existing.precioVenta,
            costoPromedio: existing.costoPromedio,
            margenActual: existing.margenActual,
            clasificacionAbc: existing.clasificacionAbc,
            abcDescripcion: existing.abcDescripcion,
            fechaUltimaActualizacion: existing.fechaUltimaActualizacion,
            totalCount: existing.totalCount,
            resumenInventario: existing.resumenInventario,
            infoPaginacion: existing.infoPaginacion,
          );
        }
      }
      
      // Convertir productos únicos a Product para compatibilidad
      final productsWithStock = uniqueProducts.values.map((inventoryProduct) => Product(
        id: inventoryProduct.id.toString(),
        name: inventoryProduct.nombreProducto,
        denominacion: inventoryProduct.nombreProducto,
        description: '', // InventoryProduct doesn't have descripcionProducto
        categoryId: inventoryProduct.idCategoria.toString(),
        categoryName: inventoryProduct.categoria, // Use categoria instead of categoriaProducto
        brand: '', // InventoryProduct doesn't have nombreComercial
        sku: inventoryProduct.skuProducto,
        barcode: '', // InventoryProduct doesn't have codigoBarras
        basePrice: inventoryProduct.precioVenta ?? 0.0,
        imageUrl: '', // InventoryProduct doesn't have imagenProducto
        isActive: true,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        stockDisponible: inventoryProduct.cantidadFinal.toInt(),
        precioVenta: inventoryProduct.precioVenta ?? 0.0,
      )).toList();
      
      setState(() {
        _products = productsWithStock;
        _filteredProducts = productsWithStock;
        _isLoadingProducts = false;
      });
    } catch (e) {
      setState(() => _isLoadingProducts = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar productos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadZonesForProduct() async {
    if (_selectedProduct == null) return;
    
    setState(() => _isLoadingZones = true);
    try {
      // Obtener almacenes/zonas donde existe el producto usando el servicio real
      final warehouses = await WarehouseService().listWarehouses();
      
      // Convertir almacenes a formato de zonas para el dropdown
      final warehousesWithZones = warehouses.map((warehouse) => {
        'id': int.tryParse(warehouse.id) ?? 0,
        'name': warehouse.name,
        'denominacion': warehouse.denominacion ?? warehouse.name,
        'direccion': warehouse.direccion ?? warehouse.address,
        'zones': warehouse.zones.map((zone) => {
          'id': int.tryParse(zone.id) ?? 0,
          'denominacion': zone.name ?? zone.name,
          'code': zone.code ?? '',
        }).toList(),
      }).toList();
      
      setState(() {
        _warehousesWithZones = warehousesWithZones;
        _isLoadingZones = false;
      });
    } catch (e) {
      setState(() => _isLoadingZones = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar zonas: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadPresentationsForZone() async {
    if (_selectedProduct == null || _selectedZone == null) return;
    
    setState(() => _isLoadingPresentations = true);
    try {
      // Obtener presentaciones del producto que están presentes en la zona seleccionada
      final productId = int.tryParse(_selectedProduct!.id);
      final zoneId = _selectedZone!['id'] as int;
      
      if (productId == null) {
        throw Exception('ID de producto inválido');
      }
      
      // Primero obtener todas las presentaciones del producto (sin filtrar por zona)
      final allPresentationsResponse = await InventoryService.getInventoryProducts(
        idProducto: productId,
        mostrarSinStock: false, // Solo mostrar presentaciones con stock
        limite: 100,
      );
      
      // Luego verificar cuáles están disponibles en la zona específica
      final zoneSpecificResponse = await InventoryService.getInventoryProducts(
        idProducto: productId,
        idUbicacion: zoneId,
        mostrarSinStock: false,
        limite: 100,
      );
      
      // Extraer presentaciones únicas de todos los productos de inventario
      final Map<int, Map<String, dynamic>> uniquePresentations = {};
      
      // Primero agregar todas las presentaciones disponibles del producto
      for (final product in allPresentationsResponse.products) {
        if (product.idPresentacion != null) {
          uniquePresentations[product.idPresentacion!] = {
            'id': product.idPresentacion!,
            'name': product.presentacion,
            'denominacion': product.presentacion,
            'codigo': product.idPresentacion.toString(),
            'stock_disponible': 0.0, // Inicializar en 0
            'available_in_zone': false,
          };
        }
      }
      
      // Luego actualizar con el stock específico de la zona seleccionada
      for (final product in zoneSpecificResponse.products) {
        if (product.idPresentacion != null && uniquePresentations.containsKey(product.idPresentacion!)) {
          uniquePresentations[product.idPresentacion!]!['stock_disponible'] = product.cantidadFinal;
          uniquePresentations[product.idPresentacion!]!['available_in_zone'] = true;
        }
      }
      
      final presentations = uniquePresentations.values.toList();
      
      setState(() {
        _presentations = presentations;
        _isLoadingPresentations = false;
        
        // Auto-seleccionar si solo hay una presentación disponible
        if (presentations.length == 1) {
          _selectedPresentation = presentations.first;
          // Cargar variantes para la presentación seleccionada automáticamente
          _loadVariantsForPresentation();
        } else {
          // Reset selección si hay múltiples opciones
          _selectedPresentation = null;
          _selectedVariant = null;
          _currentStock = null;
        }
      });
      
      // Mostrar mensaje informativo sobre las presentaciones encontradas
      if (mounted) {
        final presentationsInZone = presentations.where((p) => p['available_in_zone'] == true).length;
        final message = presentations.isEmpty 
            ? 'No hay presentaciones disponibles para este producto'
            : presentationsInZone == 0
                ? 'Se encontraron ${presentations.length} presentación(es) del producto, pero ninguna tiene stock en la zona seleccionada'
                : presentations.length == 1
                    ? 'Se seleccionó automáticamente la única presentación disponible: ${presentations.first['name']}'
                    : 'Se encontraron ${presentations.length} presentación(es), ${presentationsInZone} con stock en esta zona';
                
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: presentations.isEmpty ? Colors.red : 
                           presentationsInZone == 0 ? Colors.orange : Colors.green,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      setState(() => _isLoadingPresentations = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar presentaciones: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadVariantsForPresentation() async {
    if (_selectedProduct == null || _selectedZone == null || _selectedPresentation == null) return;
    
    setState(() => _isLoadingVariants = true);
    try {
      // Obtener variantes disponibles usando el servicio real
      final variants = await VariantService.getVariants();
      
      // Convertir a formato para el dropdown
      final variantOptions = variants.expand((variant) => 
        variant.options.map((option) => {
          'id': option.id,
          'name': '${variant.denominacion}: ${option.denominacion}',
          'denominacion': option.denominacion,
          'variant_id': variant.id,
          'variant_name': variant.denominacion,
        })
      ).toList();
      
      setState(() {
        _variants = variantOptions;
        _isLoadingVariants = false;
      });
    } catch (e) {
      setState(() => _isLoadingVariants = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar variantes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadCurrentStock() async {
    if (_selectedProduct == null || _selectedZone == null || 
        _selectedPresentation == null || _selectedVariant == null) {
      return;
    }

    setState(() => _isLoadingStock = true);
    try {
      // Obtener stock específico usando el servicio de inventario real
      final productId = int.tryParse(_selectedProduct!.id);
      final zoneId = _selectedZone!['id'] as int;
      final presentationId = _selectedPresentation!['id'] as int;
      final variantId = _selectedVariant!['id'] as int;
      
      if (productId == null) {
        throw Exception('ID de producto inválido');
      }
      
      // Usar el servicio de inventario para obtener stock específico
      final inventoryResponse = await InventoryService.getInventoryProducts(
        idProducto: productId,
        idUbicacion: zoneId,
        idPresentacion: presentationId,
        idOpcionVariante: variantId,
        mostrarSinStock: true,
        limite: 1,
      );
      
      double stock = 0.0;
      if (inventoryResponse.products.isNotEmpty) {
        stock = inventoryResponse.products.first.cantidadFinal ?? 0.0;
      }
      
      setState(() {
        _currentStock = stock;
        _isLoadingStock = false;
      });
    } catch (e) {
      setState(() => _isLoadingStock = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar stock: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filterProducts(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredProducts = _products;
      } else {
        _filteredProducts = _products.where((product) {
          return product.denominacion.toLowerCase().contains(query.toLowerCase()) ||
                 product.sku.toLowerCase().contains(query.toLowerCase());
        }).toList();
      }
    });
  }

  void _selectProduct(Product product) {
    setState(() {
      _selectedProduct = product;
      _searchController.text = '${product.denominacion} (${product.sku})';
      _filteredProducts = [];
      // Reset dependent selections
      _selectedZone = null;
      _selectedPresentation = null;
      _selectedVariant = null;
      _currentStock = null;
    });
    _loadZonesForProduct();
  }

  void _clearProductSelection() {
    setState(() {
      _selectedProduct = null;
      _searchController.clear();
      _filteredProducts = _products;
      _selectedZone = null;
      _selectedPresentation = null;
      _selectedVariant = null;
      _currentStock = null;
    });
  }

  Future<void> _submitAdjustment() async {
    if (!_formKey.currentState!.validate() || 
        _selectedProduct == null || 
        _selectedZone == null || 
        _selectedPresentation == null || 
        _selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor complete todos los campos requeridos'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final quantity = double.parse(_quantityController.text);
      final reason = _reasonController.text.trim();
      final observations = _observationsController.text.trim();

      // TODO: Implementar llamada al servicio de ajuste de inventario granular
      // await InventoryService.createGranularAdjustment(
      //   productId: _selectedProduct!.id,
      //   zoneId: _selectedZone!['id'],
      //   presentationId: _selectedPresentation!['id'],
      //   variantId: _selectedVariant!['id'],
      //   operationType: widget.operationType,
      //   quantity: quantity,
      //   reason: reason,
      //   observations: observations,
      // );

      // Simular procesamiento
      await Future.delayed(const Duration(seconds: 2));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.adjustmentType == 'excess'
                  ? 'Ajuste por exceso registrado exitosamente'
                  : 'Ajuste por faltante registrado exitosamente'
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al registrar ajuste: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isExcess = widget.adjustmentType == 'excess';
    final title = isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante';
    final subtitle = isExcess ? 'Reducir inventario por sobrante' : 'Aumentar inventario por faltante';
    final color = isExcess ? const Color(0xFFFF6B35) : const Color(0xFFFF8C42);
    final icon = isExcess ? Icons.trending_up : Icons.trending_down;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: color,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: Colors.white),
              onPressed: () => Scaffold.of(context).openEndDrawer(),
              tooltip: 'Menú',
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header info
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              fontSize: 14,
                              color: color.withOpacity(0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Product selection
              Text(
                'Selección de Producto',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _searchController,
                decoration: InputDecoration(
                  labelText: 'Buscar producto *',
                  hintText: 'Escriba el nombre o SKU del producto',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _selectedProduct != null
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: _clearProductSelection,
                        )
                      : null,
                ),
                onChanged: _filterProducts,
                validator: (value) {
                  if (_selectedProduct == null) {
                    return 'Debe seleccionar un producto';
                  }
                  return null;
                },
              ),

              // Product suggestions
              if (_filteredProducts.isNotEmpty && _selectedProduct == null) ...[
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(maxHeight: 200),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: _isLoadingProducts
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(20),
                            child: CircularProgressIndicator(),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) {
                            final product = _filteredProducts[index];
                            return ListTile(
                              title: Text(product.denominacion),
                              subtitle: Text('SKU: ${product.sku}'),
                              onTap: () => _selectProduct(product),
                            );
                          },
                        ),
                ),
              ],

              const SizedBox(height: 24),

              // Zone selection
              Text(
                'Selección de Zona',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // Tree view for warehouses and zones
              if (_isLoadingZones)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (_warehousesWithZones.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'No hay zonas disponibles para este producto',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: _warehousesWithZones.map((warehouse) {
                      return ExpansionTile(
                        leading: const Icon(Icons.warehouse, color: Colors.blue),
                        title: Text(
                          warehouse['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                        subtitle: Text(
                          '${warehouse['zones'].length} zona(s) disponible(s)',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 12,
                          ),
                        ),
                        children: (warehouse['zones'] as List<Map<String, dynamic>>)
                            .map<Widget>((zone) {
                          final isSelected = _selectedZone != null && 
                                           _selectedZone!['id'] == zone['id'];
                          
                          return ListTile(
                            contentPadding: const EdgeInsets.only(left: 72, right: 16),
                            leading: Icon(
                              Icons.location_on,
                              color: isSelected ? Colors.green : Colors.orange,
                              size: 20,
                            ),
                            title: Text(
                              zone['denominacion'],
                              style: TextStyle(
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Colors.green : null,
                              ),
                            ),
                            subtitle: zone['code'].isNotEmpty 
                                ? Text('Código: ${zone['code']}')
                                : null,
                            trailing: isSelected 
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                            selected: isSelected,
                            onTap: () {
                              setState(() {
                                _selectedZone = zone;
                                // Reset dependent selections
                                _selectedPresentation = null;
                                _selectedVariant = null;
                                _currentStock = null;
                              });
                              _loadPresentationsForZone();
                            },
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
                ),

              // Validation message for zone selection
              if (_selectedZone == null && _selectedProduct != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Debe seleccionar una zona',
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontSize: 12,
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Presentation selection
              Text(
                'Selección de Presentación',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField(
                decoration: const InputDecoration(
                  labelText: 'Presentación *',
                  border: OutlineInputBorder(),
                ),
                items: _presentations.map((presentation) {
                  return DropdownMenuItem(
                    value: presentation,
                    child: Text(presentation['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedPresentation = value as Map<String, dynamic>?;
                    _loadVariantsForPresentation();
                  });
                },
                validator: (value) {
                  if (_selectedPresentation == null) {
                    return 'Debe seleccionar una presentación';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Variant selection
              Text(
                'Selección de Variante',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField(
                decoration: const InputDecoration(
                  labelText: 'Variante *',
                  border: OutlineInputBorder(),
                ),
                items: _variants.map((variant) {
                  return DropdownMenuItem(
                    value: variant,
                    child: Text(variant['name']),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedVariant = value as Map<String, dynamic>?;
                    _loadCurrentStock();
                  });
                },
                validator: (value) {
                  if (_selectedVariant == null) {
                    return 'Debe seleccionar una variante';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Current stock
              Text(
                'Stock Actual',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                _isLoadingStock ? 'Cargando...' : _currentStock != null ? 'Stock actual: ${_currentStock}' : 'No hay stock disponible',
                style: const TextStyle(fontSize: 16),
              ),

              const SizedBox(height: 24),

              // Quantity
              Text(
                'Cantidad a Ajustar',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _quantityController,
                decoration: const InputDecoration(
                  labelText: 'Cantidad *',
                  hintText: 'Ingrese la cantidad',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.inventory),
                  suffixText: 'unidades',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}')),
                ],
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'La cantidad es requerida';
                  }
                  final quantity = double.tryParse(value);
                  if (quantity == null || quantity <= 0) {
                    return 'Ingrese una cantidad válida mayor a 0';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Reason
              Text(
                'Motivo del Ajuste',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Motivo *',
                  hintText: 'Ej: Conteo físico, Merma, Error de registro',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.description),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'El motivo es requerido';
                  }
                  if (value.trim().length < 5) {
                    return 'El motivo debe tener al menos 5 caracteres';
                  }
                  return null;
                },
              ),

              const SizedBox(height: 24),

              // Observations
              Text(
                'Observaciones',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _observationsController,
                decoration: const InputDecoration(
                  labelText: 'Observaciones adicionales',
                  hintText: 'Información adicional sobre el ajuste (opcional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.note),
                ),
                maxLines: 3,
              ),

              const SizedBox(height: 32),

              // Submit button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitAdjustment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: color,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isLoading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text('Procesando...'),
                          ],
                        )
                      : Text(
                          'Registrar ${isExcess ? 'Ajuste por Exceso' : 'Ajuste por Faltante'}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 2,
        onTap: (index) {
          switch (index) {
            case 0:
              Navigator.pushNamedAndRemoveUntil(context, '/dashboard', (route) => false);
              break;
            case 1:
              Navigator.pushNamed(context, '/products');
              break;
            case 2:
              Navigator.pushNamed(context, '/inventory');
              break;
            case 3:
              Navigator.pushNamed(context, '/settings');
              break;
          }
        },
      ),
    );
  }
}
