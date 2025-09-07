import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../services/inventory_service.dart';
import '../services/warehouse_service.dart';
import '../services/user_preferences_service.dart';

class InventoryWarehouseScreen extends StatefulWidget {
  const InventoryWarehouseScreen({super.key});

  @override
  State<InventoryWarehouseScreen> createState() =>
      _InventoryWarehouseScreenState();
}

class _InventoryWarehouseScreenState extends State<InventoryWarehouseScreen> {
  // Services
  final InventoryService _inventoryService = InventoryService();
  final WarehouseService _warehouseService = WarehouseService();

  // State variables
  bool _isLoading = false;
  String? _error;

  // Data
  List<Warehouse> _warehouses = [];
  List<InventoryProduct> _inventoryProducts = [];

  // Warehouse expansion state
  Map<String, bool> _expandedWarehouses = {};
  Map<String, bool> _expandedLayouts = {};
  Map<String, bool> _expandedZones = {}; // Nuevo: estado de expansión por zona
  Map<String, bool> _expandedProducts =
      {}; // Nuevo estado para expansión de variantes
  Map<String, List<InventoryProduct>> _layoutInventory = {};
  Map<String, bool> _loadingInventory = {};
  Map<String, int> _layoutProductCounts = {};

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      await Future.wait([_loadWarehouses(), _loadInventoryData()]);
      await _loadAllProductCounts();
    } catch (e) {
      setState(() {
        _error = 'Error al cargar datos: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadWarehouses() async {
    try {
      // Primero obtener la lista básica de warehouses
      final basicWarehouses = await _warehouseService.listWarehouses();

      // Luego obtener el detalle completo de cada warehouse para tener la jerarquía correcta
      final List<Warehouse> detailedWarehouses = [];

      for (final warehouse in basicWarehouses) {
        try {
          print(
            '🔍 Obteniendo detalle completo para warehouse: ${warehouse.name} (ID: ${warehouse.id})',
          );
          final detailedWarehouse = await _warehouseService.getWarehouseDetail(
            warehouse.id,
          );
          detailedWarehouses.add(detailedWarehouse);
        } catch (e) {
          print('⚠️ Error obteniendo detalle de warehouse ${warehouse.id}: $e');
          // Si falla el detalle, usar el warehouse básico
          detailedWarehouses.add(warehouse);
        }
      }

      setState(() {
        _warehouses = detailedWarehouses;
      });
    } catch (e) {
      print('Error loading warehouses: $e');
    }
  }

  Future<void> _loadInventoryData() async {
    try {
      // En lugar de cargar inventario general, cargar inventario por almacenes
      // Esto se hará automáticamente cuando se expandan las zonas de cada almacén
      // Por ahora, inicializar la lista vacía ya que los productos se cargan por zona
      setState(() {
        _inventoryProducts = [];
      });

      // Opcional: Pre-cargar inventario de todas las zonas si se desea
      // _loadAllWarehouseInventory();
    } catch (e) {
      print('Error loading inventory: $e');
    }
  }

  Future<void> _loadAllProductCounts() async {
    print('🚀 === INICIANDO _loadAllProductCounts ===');
    print('🔍 Warehouses disponibles: ${_warehouses.length}');

    for (final warehouse in _warehouses) {
      print('🏭 Procesando warehouse: ${warehouse.name} (ID: ${warehouse.id})');
      print('🔍 Zones en warehouse: ${warehouse.zones.length}');

      for (final zone in warehouse.zones) {
        final layoutKey = '${warehouse.id}_${zone.id}';
        print('📍 Procesando zona: ${zone.name} (ID: ${zone.id})');
        print('🔑 Layout key: $layoutKey');

        try {
          print('🔄 Llamando getProductosByLayout para zona ${zone.id}...');
          final productsData = await _warehouseService.getProductosByLayout(
            zone.id,
          );

          print(
            '✅ Respuesta recibida para zona ${zone.id}: ${productsData.length} productos',
          );

          setState(() {
            _layoutProductCounts[layoutKey] = productsData.length;
          });

          print(
            '💾 Guardado en _layoutProductCounts[$layoutKey] = ${productsData.length}',
          );
        } catch (e) {
          print('❌ Error loading product count for zone ${zone.id}: $e');
          print(
            '📍 Zone details: ${zone.name}, Code: ${zone.code}, Type: ${zone.type}',
          );
          setState(() {
            _layoutProductCounts[layoutKey] = 0;
          });
        }
      }
    }

    print('🏁 === FIN _loadAllProductCounts ===');
    print('📊 Resumen de contadores cargados:');
    _layoutProductCounts.forEach((key, count) {
      print('  - $key: $count productos');
    });
  }

  @override
  Widget build(BuildContext context) {
    return _buildBody();
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadInitialData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_warehouses.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warehouse, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay almacenes configurados',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _warehouses.length,
        itemBuilder:
            (context, index) => _buildWarehouseTreeNode(_warehouses[index]),
      ),
    );
  }

  Widget _buildWarehouseTreeNode(Warehouse warehouse) {
    final isExpanded = _expandedWarehouses[warehouse.id] ?? false;

    int totalProducts = 0;
    for (final zone in warehouse.zones) {
      final layoutKey = '${warehouse.id}_${zone.id}';
      totalProducts += _layoutProductCounts[layoutKey] ?? 0;
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Warehouse header
          InkWell(
            onTap: () {
              setState(() {
                _expandedWarehouses[warehouse.id] = !isExpanded;

                // Si se está expandiendo el warehouse, expandir automáticamente todas las zonas
                if (!isExpanded) {
                  _expandAllZonesInWarehouse(warehouse.id, warehouse.zones);
                }
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.primary,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.warehouse,
                      color: AppColors.primary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          warehouse.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${warehouse.address} • ${warehouse.zones.length} zonas • $totalProducts productos',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (totalProducts > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$totalProducts',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          warehouse.isActive
                              ? AppColors.success.withOpacity(0.1)
                              : Colors.grey.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      warehouse.isActive ? 'Activo' : 'Inactivo',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color:
                            warehouse.isActive
                                ? AppColors.success
                                : Colors.grey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Expanded zones with hierarchy
          if (isExpanded) ...[
            const Divider(height: 1),
            if (warehouse.zones.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                child: const Center(
                  child: Text(
                    'No hay zonas configuradas en este almacén',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14,
                    ),
                  ),
                ),
              )
            else
              ..._buildAllZonesExpanded(warehouse.id, warehouse.zones),
          ],
        ],
      ),
    );
  }

  /// Expande automáticamente todas las zonas de un warehouse
  void _expandAllZonesInWarehouse(
    String warehouseId,
    List<WarehouseZone> zones,
  ) {
    print(
      '🚀 Expandiendo automáticamente todas las zonas del warehouse $warehouseId',
    );

    for (final zone in zones) {
      final zoneKey = '${warehouseId}_${zone.id}_zone';
      _expandedZones[zoneKey] = true;

      // Recursivamente expandir zonas hijas
      final children =
          zones.where((z) {
            final zoneParentId = z.parentId?.toString().trim();
            final currentZoneId = zone.id.toString().trim();

            return zoneParentId != null &&
                zoneParentId.isNotEmpty &&
                zoneParentId != "null" &&
                zoneParentId != "0" &&
                zoneParentId == currentZoneId;
          }).toList();

      if (children.isNotEmpty) {
        _expandAllZonesInWarehouse(warehouseId, children);
      }
    }

    print('✅ Expansión automática completada');
  }

  /// Construye todas las zonas expandidas automáticamente
  List<Widget> _buildAllZonesExpanded(
    String warehouseId,
    List<WarehouseZone> zones,
  ) {
    print('🚀 === CONSTRUYENDO TODAS LAS ZONAS EXPANDIDAS ===');
    print('📍 Warehouse ID: $warehouseId');
    print('📊 Total zones: ${zones.length}');

    // Debug: Mostrar todas las zonas con sus parentId
    print('📋 TODAS LAS ZONAS DISPONIBLES:');
    for (final zone in zones) {
      print(
        '  - ${zone.name} (ID: ${zone.id}) -> Parent: ${zone.parentId ?? "NULL"}',
      );
    }

    // Filtrar solo zonas padre (nivel 0)
    final parentZones =
        zones.where((zone) {
          final isParent =
              zone.parentId == null ||
              zone.parentId!.isEmpty ||
              zone.parentId == "null" ||
              zone.parentId == "0";
          return isParent;
        }).toList();

    print('🌲 Zonas padre encontradas: ${parentZones.length}');
    for (final zone in parentZones) {
      print('  ✅ ${zone.name} (ID: ${zone.id})');
    }

    List<Widget> widgets = [];

    for (final parentZone in parentZones) {
      print('\n🏗️ Procesando zona padre: ${parentZone.name}');

      // Agregar zona padre
      widgets.add(_buildZoneCard(warehouseId, parentZone, zones, level: 0));

      // Agregar todas las zonas hijas recursivamente
      final childWidgets = _buildAllChildZones(
        warehouseId,
        parentZone,
        zones,
        level: 1,
      );
      print(
        '🔄 Zonas hijas generadas para ${parentZone.name}: ${childWidgets.length}',
      );
      widgets.addAll(childWidgets);
    }

    print('✅ Total widgets construidos: ${widgets.length}');
    print('🚀 === FIN CONSTRUCCIÓN ZONAS EXPANDIDAS ===\n');
    return widgets;
  }

  /// Construye recursivamente todas las zonas hijas
  List<Widget> _buildAllChildZones(
    String warehouseId,
    WarehouseZone parentZone,
    List<WarehouseZone> allZones, {
    required int level,
  }) {
    print('🔍 === CONSTRUYENDO HIJOS DE ${parentZone.name} (Nivel $level) ===');

    List<Widget> childWidgets = [];

    // Buscar hijos directos - CORREGIDO: comparar parentId con NOMBRE de zona
    final directChildren =
        allZones.where((z) {
          final zoneParentName = z.parentId?.toString().trim();
          final currentZoneName = parentZone.name.toString().trim();

          final isChild =
              zoneParentName != null &&
              zoneParentName.isNotEmpty &&
              zoneParentName != "null" &&
              zoneParentName != "0" &&
              zoneParentName ==
                  currentZoneName; // ← CAMBIO: comparar con nombre

          if (isChild) {
            print(
              '  ✅ Hijo encontrado: ${z.name} (ID: ${z.id}) -> Parent: "$zoneParentName" == "${currentZoneName}"',
            );
          }

          return isChild;
        }).toList();

    print('👥 Hijos directos de ${parentZone.name}: ${directChildren.length}');

    for (final childZone in directChildren) {
      print('🏗️ Construyendo hijo: ${childZone.name} (Nivel $level)');

      // Agregar zona hija
      childWidgets.add(
        _buildZoneCard(warehouseId, childZone, allZones, level: level),
      );

      // Recursivamente agregar nietos
      print('🔄 Buscando nietos de ${childZone.name}...');
      final grandChildWidgets = _buildAllChildZones(
        warehouseId,
        childZone,
        allZones,
        level: level + 1,
      );
      print(
        '👶 Nietos encontrados para ${childZone.name}: ${grandChildWidgets.length}',
      );
      childWidgets.addAll(grandChildWidgets);
    }

    print(
      '📊 Total widgets hijos para ${parentZone.name}: ${childWidgets.length}',
    );
    print('🔍 === FIN HIJOS DE ${parentZone.name} ===\n');

    return childWidgets;
  }

  Widget _buildZoneCard(
    String warehouseId,
    WarehouseZone zone,
    List<WarehouseZone> allZones, {
    int level = 0,
  }) {
    final layoutKey = '${warehouseId}_${zone.id}';
    final zoneKey = '${warehouseId}_${zone.id}_zone';
    final isExpanded = _expandedLayouts[layoutKey] ?? false;
    final isZoneExpanded = _expandedZones[zoneKey] ?? false;
    final isLoading = _loadingInventory[layoutKey] ?? false;
    final inventory = _layoutInventory[layoutKey] ?? [];
    final productCount = _layoutProductCounts[layoutKey] ?? 0;

    // Buscar hijos directos de esta zona - MEJORADO
    final directChildren =
        allZones.where((z) {
          final zoneParentId = z.parentId?.toString().trim();
          final currentZoneId = zone.id.toString().trim();

          final isDirectChild =
              zoneParentId != null &&
              zoneParentId.isNotEmpty &&
              zoneParentId != "null" &&
              zoneParentId != "0" &&
              zoneParentId == currentZoneId;

          return isDirectChild;
        }).toList();

    // Calcular utilización (ejemplo)
    final utilization =
        productCount > 0 ? (productCount * 10).clamp(0, 100) : 0;

    return Column(
      children: [
        // Card principal de la zona
        Container(
          margin: EdgeInsets.only(left: level * 16.0, right: 16, bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
            border: Border.all(color: Colors.grey.withOpacity(0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header de la zona
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Icono de jerarquía
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            level == 0
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.secondary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        level == 0
                            ? Icons.home_work_outlined
                            : level == 1
                            ? Icons.layers_outlined
                            : Icons.crop_square_outlined,
                        color:
                            level == 0
                                ? AppColors.primary
                                : AppColors.secondary,
                        size: 20,
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Información de la zona
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Nombre de la zona
                          Text(
                            zone.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                          ),

                          const SizedBox(height: 4),

                          // Código y badge ABC
                          Row(
                            children: [
                              Text(
                                zone.code.isNotEmpty ? zone.code : 'sin_codigo',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.grey[600],
                                  fontFamily: 'monospace',
                                ),
                              ),

                              if (zone.abc != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getAbcColor(
                                      zone.abc!,
                                    ).withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _getAbcColor(
                                        zone.abc!,
                                      ).withOpacity(0.3),
                                    ),
                                  ),
                                  child: Text(
                                    _getAbcLabel(zone.abc!),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _getAbcColor(zone.abc!),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Menú de opciones
                    IconButton(
                      onPressed: () {
                        // TODO: Implementar menú de opciones
                      },
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.grey,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                    ),
                  ],
                ),
              ),

              // Métricas de la zona
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    // Productos
                    Row(
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$productCount productos',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(width: 16),

                    // Utilización
                    Row(
                      children: [
                        Icon(
                          Icons.pie_chart_outline,
                          size: 16,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$utilization% uso',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Botón "Ver productos"
              if (productCount > 0)
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _expandedLayouts[layoutKey] = !isExpanded;
                        });
                        if (!isExpanded &&
                            _layoutInventory[layoutKey] == null) {
                          _loadLayoutInventory(layoutKey, zone.id);
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Ver productos ($productCount)',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: AppColors.primary,
                              ),
                            ),
                            Icon(
                              isExpanded
                                  ? Icons.keyboard_arrow_up
                                  : Icons.keyboard_arrow_down,
                              color: AppColors.primary,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              // Lista de productos expandida
              if (isExpanded) ...[
                const Divider(height: 1),
                if (isLoading)
                  Container(
                    padding: const EdgeInsets.all(20),
                    child: const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                else if (inventory.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'No hay productos en esta zona',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          inventory.take(5).map((product) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          product.nombreProducto,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (product.skuProducto.isNotEmpty)
                                          Text(
                                            product.skuProducto,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.grey[600],
                                              fontFamily: 'monospace',
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          product.stockDisponible > 0
                                              ? AppColors.success.withOpacity(
                                                0.1,
                                              )
                                              : AppColors.error.withOpacity(
                                                0.1,
                                              ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '${product.stockDisponible.toInt()}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color:
                                            product.stockDisponible > 0
                                                ? AppColors.success
                                                : AppColors.error,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                if (inventory.length > 5)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      'y ${inventory.length - 5} productos más...',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),

        // Mostrar zonas hijas si están expandidas
        // NOTA: Las zonas hijas ahora se muestran automáticamente en _buildAllZonesExpanded
        // por lo que no necesitamos lógica de expansión manual aquí
      ],
    );
  }

  // Helper methods para ABC
  Color _getAbcColor(String abc) {
    switch (abc.toUpperCase()) {
      case 'A':
        return Colors.red;
      case 'B':
        return Colors.orange;
      case 'C':
        return AppColors.success;
      default:
        return Colors.grey;
    }
  }

  String _getAbcLabel(String abc) {
    switch (abc.toUpperCase()) {
      case 'A':
        return 'Pasillo Principal';
      case 'B':
        return 'Zona Cuarentena';
      case 'C':
        return 'Anaqueles';
      default:
        return abc.toUpperCase();
    }
  }

  Future<void> _loadLayoutInventory(String layoutKey, String zoneId) async {
    setState(() {
      _loadingInventory[layoutKey] = true;
    });

    try {
      final productsData = await _warehouseService.getProductosByLayout(zoneId);
      final layoutInventory =
          productsData.map((productData) {
            return InventoryProduct(
              id: productData['id'] ?? 0,
              nombreProducto:
                  productData['denominacion'] ?? 'Producto sin nombre',
              skuProducto: productData['sku'] ?? 'N/A',
              idCategoria: productData['id_categoria'] ?? 0,
              categoria: productData['categoria'] ?? 'Sin categoría',
              idSubcategoria: productData['id_subcategoria'] ?? 0,
              subcategoria: productData['subcategoria'] ?? 'Sin subcategoría',
              idTienda: productData['id_tienda'] ?? 0,
              tienda: productData['tienda'] ?? '',
              idAlmacen: productData['id_almacen'] ?? 0,
              almacen: productData['almacen'] ?? 'Sin almacén',
              idUbicacion: productData['id_ubicacion'] ?? 0,
              ubicacion: productData['ubicacion'] ?? 'Sin ubicación',
              variante: productData['variante'] ?? 'Unidad',
              opcionVariante: productData['opcion_variante'] ?? 'Única',
              presentacion: productData['um'] ?? 'UN',
              stockDisponible:
                  (productData['stock_disponible'] ?? 0).toDouble(),
              stockReservado: (productData['stock_reservado'] ?? 0).toDouble(),
              cantidadFinal: (productData['stock_actual'] ?? 0).toDouble(),
              cantidadInicial: (productData['stock_actual'] ?? 0).toDouble(),
              stockDisponibleAjustado:
                  (productData['stock_disponible'] ?? 0).toDouble(),
              esVendible: true,
              esInventariable: true,
              clasificacionAbc: 3,
              abcDescripcion: 'Clasificación C',
              precioVenta: null,
              costoPromedio: null,
              margenActual: null,
              fechaUltimaActualizacion: DateTime.now(),
              idVariante: 0,
              idOpcionVariante: 0,
              totalCount: 0,
            );
          }).toList();

      setState(() {
        _layoutInventory[layoutKey] = layoutInventory;
        _loadingInventory[layoutKey] = false;
      });
    } catch (e) {
      print('Error loading products for zone $zoneId: $e');
      setState(() {
        _layoutInventory[layoutKey] = [];
        _loadingInventory[layoutKey] = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar inventario: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }
}
