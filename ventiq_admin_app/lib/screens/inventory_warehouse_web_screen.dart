import 'package:flutter/material.dart';
import '../config/app_colors.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../services/inventory_service.dart';
import '../services/warehouse_service.dart';
import '../services/user_preferences_service.dart';
import '../services/export_service.dart';
import '../services/warehouse_valuation_service.dart';
import '../widgets/export_dialog.dart';

class InventoryWarehouseWebScreen extends StatefulWidget {
  const InventoryWarehouseWebScreen({super.key});

  @override
  State<InventoryWarehouseWebScreen> createState() =>
      _InventoryWarehouseWebScreenState();
}

class _InventoryWarehouseWebScreenState extends State<InventoryWarehouseWebScreen> {
  // Services
  final InventoryService _inventoryService = InventoryService();
  final WarehouseService _warehouseService = WarehouseService();
  final ExportService _exportService = ExportService();
  final WarehouseValuationService _valuationService =
      WarehouseValuationService();

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

  // ===== Valuation state =====
  WarehousesValuationSummary? _valuationSummary;
  bool _loadingValuation = false;
  // Per-warehouse valuation details (zones) — keyed by warehouse id string
  final Map<String, WarehouseZonesValuation> _warehouseZonesValuation = {};
  final Map<String, bool> _loadingWarehouseValuation = {};
  // Per-zone product valuation — keyed by layout (zone) id string
  final Map<String, ZoneProductsValuation> _zoneProductsValuation = {};
  final Map<String, bool> _loadingZoneValuation = {};

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
      // Solo cargar la lista básica de warehouses, sin conteos de productos
      await Future.wait([
        _loadWarehouses(),
        _loadInventoryData(),
        _loadValuationSummary(),
      ]);
      // Eliminamos _loadAllProductCounts() para mejorar rendimiento inicial
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
      // Solo obtener la lista básica de warehouses para carga rápida inicial
      final basicWarehouses = await _warehouseService.listWarehouses();
      
      setState(() {
        _warehouses = basicWarehouses;
      });
      
      print('✅ Cargados ${basicWarehouses.length} almacenes básicos');
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

  /// Carga la valoración total de todos los almacenes de la tienda
  Future<void> _loadValuationSummary() async {
    if (!mounted) return;
    setState(() {
      _loadingValuation = true;
    });
    try {
      final summary = await _valuationService.getTiendaSummary();
      if (!mounted) return;
      setState(() {
        _valuationSummary = summary;
      });
      print(
        '💰 Valuation summary cargada: '
        'costo=${summary.totales.valorCostoUsd.toStringAsFixed(2)} USD, '
        'venta=${summary.totales.valorVentaUsd.toStringAsFixed(2)} USD, '
        'ganancia=${summary.totales.gananciaUsd.toStringAsFixed(2)} USD, '
        'almacenes=${summary.almacenes.length}',
      );
    } catch (e) {
      print('❌ Error cargando valoración global: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingValuation = false;
        });
      }
    }
  }

  /// Carga valoración por zonas de un almacén específico
  Future<void> _loadWarehouseValuation(String warehouseId) async {
    if (_warehouseZonesValuation.containsKey(warehouseId)) return;
    final idAlmacen = int.tryParse(warehouseId) ?? 0;
    if (idAlmacen == 0) return;

    setState(() {
      _loadingWarehouseValuation[warehouseId] = true;
    });

    try {
      final data = await _valuationService.getWarehouseZones(idAlmacen);
      if (!mounted) return;
      setState(() {
        _warehouseZonesValuation[warehouseId] = data;
      });
    } catch (e) {
      print('❌ Error cargando valoración del almacén $warehouseId: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingWarehouseValuation[warehouseId] = false;
        });
      }
    }
  }

  /// Carga valoración de productos por zona/layout
  Future<void> _loadZoneValuation(String zoneId) async {
    if (_zoneProductsValuation.containsKey(zoneId)) return;
    final idLayout = int.tryParse(zoneId) ?? 0;
    if (idLayout == 0) return;

    setState(() {
      _loadingZoneValuation[zoneId] = true;
    });

    try {
      final data = await _valuationService.getZoneProducts(idLayout);
      if (!mounted) return;
      setState(() {
        _zoneProductsValuation[zoneId] = data;
      });
    } catch (e) {
      print('❌ Error cargando valoración de zona $zoneId: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingZoneValuation[zoneId] = false;
        });
      }
    }
  }

  /// Carga los detalles completos de un warehouse específico cuando se expande
  Future<void> _loadWarehouseDetails(String warehouseId) async {
    setState(() {
      _loadingInventory['warehouse_$warehouseId'] = true;
    });

    try {
      print('🔍 Cargando detalles para warehouse: $warehouseId');
      
      // Obtener el detalle completo del warehouse
      final detailedWarehouse = await _warehouseService.getWarehouseDetail(warehouseId);
      
      // Actualizar el warehouse en la lista con los detalles completos
      setState(() {
        final index = _warehouses.indexWhere((w) => w.id == warehouseId);
        if (index != -1) {
          _warehouses[index] = detailedWarehouse;
        }
      });
      
      // Cargar conteos de productos para todas las zonas de este warehouse
      await _loadWarehouseProductCounts(detailedWarehouse);
      
      print('✅ Detalles cargados para warehouse: ${detailedWarehouse.name}');
    } catch (e) {
      print('❌ Error cargando detalles del warehouse $warehouseId: $e');
    } finally {
      setState(() {
        _loadingInventory['warehouse_$warehouseId'] = false;
      });
    }
  }

  /// Carga los conteos de productos para todas las zonas de un warehouse específico
  Future<void> _loadWarehouseProductCounts(Warehouse warehouse) async {
    print('📊 Cargando conteos de productos para warehouse: ${warehouse.name}');
    
    for (final zone in warehouse.zones) {
      final layoutKey = '${warehouse.id}_${zone.id}';
      
      try {
        final productsData = await _warehouseService.getProductosByLayout(zone.id);
        
        setState(() {
          _layoutProductCounts[layoutKey] = productsData.length;
        });
        
        print('✅ Zona ${zone.name}: ${productsData.length} productos');
      } catch (e) {
        print('❌ Error cargando conteo para zona ${zone.name}: $e');
        setState(() {
          _layoutProductCounts[layoutKey] = 0;
        });
      }
    }
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
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        // +2 for the summary header + warehouses section header
        itemCount: _warehouses.length + 2,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _buildValuationSummaryCard();
          }
          if (index == 1) {
            return _buildWarehousesSectionHeader();
          }
          return _buildWarehouseTreeNode(_warehouses[index - 2]);
        },
      ),
    );
  }

  Widget _buildWarehousesSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 14),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 18,
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          const Text(
            'Almacenes',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_warehouses.length}',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // Valuation UI helpers
  // ===========================================================================

  String _formatUsd(double v) {
    // Two decimals, thousands separator
    return '\$${_formatNumber(v, 2)}';
  }

  String _formatCup(double v) {
    return '${_formatNumber(v, 0)} CUP';
  }

  String _formatNumber(double v, int decimals) {
    if (v.isNaN || v.isInfinite) return '0';
    final fixed = v.toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      final remaining = intPart.length - i;
      buf.write(intPart[i]);
      if (remaining > 1 && remaining % 3 == 1) buf.write(',');
    }
    return decimals > 0 ? '${buf.toString()}.${parts[1]}' : buf.toString();
  }

  Widget _buildValuationSummaryCard() {
    final summary = _valuationSummary;
    if (_loadingValuation && summary == null) {
      return Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final totales = summary?.totales ?? ValuationTotals.empty;
    final tasa = summary?.tasa ?? 0;
    final isWide = MediaQuery.of(context).size.width >= 700;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E3A8A),
            AppColors.primary,
            const Color(0xFF3B82F6),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.2),
                        ),
                      ),
                      child: const Icon(
                        Icons.account_balance_wallet_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Valoración Total de Inventario',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Resumen consolidado de toda la tienda',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tasa > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.22),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.currency_exchange_rounded,
                              size: 12,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '1 USD = ${_formatNumber(tasa, 0)} CUP',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
            const SizedBox(height: 18),
            if (isWide)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _buildValuationTile(
                        label: 'Costo invertido',
                        usd: totales.valorCostoUsd,
                        cup: totales.valorCostoCup,
                        icon: Icons.inventory_2_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildValuationTile(
                        label: 'Si se vende todo',
                        usd: totales.valorVentaUsd,
                        cup: totales.valorVentaCup,
                        icon: Icons.sell_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildValuationTile(
                        label: 'Ganancia potencial',
                        usd: totales.gananciaUsd,
                        cup: totales.gananciaCup,
                        icon: Icons.trending_up_rounded,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: [
                  _buildValuationTile(
                    label: 'Costo invertido',
                    usd: totales.valorCostoUsd,
                    cup: totales.valorCostoCup,
                    icon: Icons.inventory_2_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildValuationTile(
                    label: 'Si se vende todo',
                    usd: totales.valorVentaUsd,
                    cup: totales.valorVentaCup,
                    icon: Icons.sell_rounded,
                  ),
                  const SizedBox(height: 10),
                  _buildValuationTile(
                    label: 'Ganancia potencial',
                    usd: totales.gananciaUsd,
                    cup: totales.gananciaCup,
                    icon: Icons.trending_up_rounded,
                    highlight: true,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildValuationTile({
    required String label,
    required double usd,
    required double cup,
    required IconData icon,
    bool highlight = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: highlight
            ? Colors.white.withOpacity(0.18)
            : Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.white.withOpacity(highlight ? 0.32 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatUsd(usd),
            style: TextStyle(
              color: Colors.white,
              fontSize: highlight ? 19 : 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatCup(cup),
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// Finds a warehouse valuation entry from the summary by id
  WarehouseValuation? _findWarehouseValuation(String warehouseId) {
    final summary = _valuationSummary;
    if (summary == null) return null;
    final id = int.tryParse(warehouseId);
    if (id == null) return null;
    for (final w in summary.almacenes) {
      if (w.idAlmacen == id) return w;
    }
    return null;
  }

  Widget _buildWarehouseValuationChips(String warehouseId) {
    final wv = _findWarehouseValuation(warehouseId);
    if (wv == null) {
      if (_loadingValuation) {
        return const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SizedBox(
            height: 12,
            child: LinearProgressIndicator(
              color: AppColors.primary,
              backgroundColor: Colors.transparent,
              minHeight: 2,
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    final isWide = MediaQuery.of(context).size.width >= 700;
    final chips = [
      _buildValChip(
        label: 'Costo',
        usd: wv.valorCostoUsd,
        cup: wv.valorCostoCup,
        color: const Color(0xFF4A90E2),
        icon: Icons.inventory_2_outlined,
      ),
      _buildValChip(
        label: 'Venta',
        usd: wv.valorVentaUsd,
        cup: wv.valorVentaCup,
        color: const Color(0xFF10B981),
        icon: Icons.sell_outlined,
      ),
      _buildValChip(
        label: 'Ganancia',
        usd: wv.gananciaUsd,
        cup: wv.gananciaCup,
        color: const Color(0xFFFF8C42),
        icon: Icons.trending_up_rounded,
      ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      child: isWide
          ? Row(
              children: [
                Expanded(child: chips[0]),
                const SizedBox(width: 8),
                Expanded(child: chips[1]),
                const SizedBox(width: 8),
                Expanded(child: chips[2]),
              ],
            )
          : Wrap(
              spacing: 8,
              runSpacing: 6,
              children: chips,
            ),
    );
  }

  Widget _buildValChip({
    required String label,
    required double usd,
    required double cup,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            color.withOpacity(0.10),
            color.withOpacity(0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: color.withOpacity(0.85),
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _formatUsd(usd),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  _formatCup(cup),
                  style: TextStyle(
                    fontSize: 10,
                    color: color.withOpacity(0.75),
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildZoneValuationChips(String warehouseId, String zoneId) {
    final wzv = _warehouseZonesValuation[warehouseId];
    if (wzv == null) return const SizedBox.shrink();
    final id = int.tryParse(zoneId);
    if (id == null) return const SizedBox.shrink();
    ZoneValuation? zv;
    for (final z in wzv.zonas) {
      if (z.idLayout == id) {
        zv = z;
        break;
      }
    }
    if (zv == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Builder(
        builder: (context) {
          final isWide = MediaQuery.of(context).size.width >= 640;
          final chips = [
            _buildValChip(
              label: 'Costo',
              usd: zv!.valorCostoUsd,
              cup: zv.valorCostoCup,
              color: const Color(0xFF4A90E2),
              icon: Icons.inventory_2_outlined,
            ),
            _buildValChip(
              label: 'Venta',
              usd: zv.valorVentaUsd,
              cup: zv.valorVentaCup,
              color: const Color(0xFF10B981),
              icon: Icons.sell_outlined,
            ),
            _buildValChip(
              label: 'Ganancia',
              usd: zv.gananciaUsd,
              cup: zv.gananciaCup,
              color: const Color(0xFFFF8C42),
              icon: Icons.trending_up_rounded,
            ),
          ];
          if (isWide) {
            return Row(
              children: [
                Expanded(child: chips[0]),
                const SizedBox(width: 6),
                Expanded(child: chips[1]),
                const SizedBox(width: 6),
                Expanded(child: chips[2]),
              ],
            );
          }
          return Wrap(
            spacing: 6,
            runSpacing: 4,
            children: chips,
          );
        },
      ),
    );
  }

  ProductValuation? _findProductValuation(String zoneId, int idProducto) {
    final zpv = _zoneProductsValuation[zoneId];
    if (zpv == null) return null;
    for (final p in zpv.productos) {
      if (p.idProducto == idProducto) return p;
    }
    return null;
  }

  Widget _buildProductValuationRow(ProductValuation pv) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _buildMiniValChip(
          label: 'Costo',
          usd: pv.valorCostoUsd,
          cup: pv.valorCostoCup,
          color: const Color(0xFF4A90E2),
        ),
        _buildMiniValChip(
          label: 'Venta',
          usd: pv.valorVentaUsd,
          cup: pv.valorVentaCup,
          color: const Color(0xFF10B981),
        ),
        _buildMiniValChip(
          label: 'Ganancia',
          usd: pv.gananciaUsd,
          cup: pv.gananciaCup,
          color: const Color(0xFFFF8C42),
        ),
      ],
    );
  }

  Widget _buildMiniValChip({
    required String label,
    required double usd,
    required double cup,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.85),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
            TextSpan(
              text: _formatUsd(usd),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            TextSpan(
              text: ' · ${_formatCup(cup)}',
              style: TextStyle(
                fontSize: 10,
                color: color.withOpacity(0.78),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarehouseTreeNode(Warehouse warehouse) {
    final isExpanded = _expandedWarehouses[warehouse.id] ?? false;
    final isLoadingDetails = _loadingInventory['warehouse_${warehouse.id}'] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? AppColors.primary.withOpacity(0.35)
              : AppColors.border,
          width: isExpanded ? 1.2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isExpanded ? 0.05 : 0.025),
            blurRadius: isExpanded ? 12 : 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Warehouse header
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                if (!isExpanded) {
                  await _loadWarehouseDetails(warehouse.id);
                  _loadWarehouseValuation(warehouse.id);
                }

                setState(() {
                  _expandedWarehouses[warehouse.id] = !isExpanded;

                  if (!isExpanded &&
                      _warehouses.any(
                        (w) =>
                            w.id == warehouse.id && w.zones.isNotEmpty,
                      )) {
                    final detailedWarehouse = _warehouses.firstWhere(
                      (w) => w.id == warehouse.id,
                    );
                    _expandAllZonesInWarehouse(
                      warehouse.id,
                      detailedWarehouse.zones,
                    );
                  }
                });
              },
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppColors.primary.withOpacity(0.15),
                            AppColors.primary.withOpacity(0.06),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.primary.withOpacity(0.18),
                        ),
                      ),
                      child: const Icon(
                        Icons.warehouse_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            warehouse.name,
                            style: const TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                              letterSpacing: 0.1,
                              height: 1.2,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _miniInfoChip(
                                icon: Icons.place_outlined,
                                text: warehouse.address.isNotEmpty
                                    ? warehouse.address
                                    : 'Sin dirección',
                                color: AppColors.textSecondary,
                              ),
                              if (isExpanded && !isLoadingDetails)
                                _miniInfoChip(
                                  icon: Icons.layers_rounded,
                                  text:
                                      '${warehouse.zones.length} zonas',
                                  color: const Color(0xFF6366F1),
                                )
                              else
                                _miniInfoChip(
                                  icon: Icons.touch_app_rounded,
                                  text: 'Toca para ver detalles',
                                  color: AppColors.textLight,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (isLoadingDetails)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      )
                    else
                      _statusBadge(active: warehouse.isActive),
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: isExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              AppColors.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.expand_more_rounded,
                          color: AppColors.primary,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Valoración del almacén (chips)
          _buildWarehouseValuationChips(warehouse.id),
          // Expanded zones with hierarchy
          if (isExpanded) ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.border,
            ),
            const SizedBox(height: 12),
            if (warehouse.zones.isEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'No hay zonas configuradas en este almacén',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ..._buildAllZonesExpanded(warehouse.id, warehouse.zones),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _miniInfoChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge({required bool active}) {
    final color = active ? AppColors.success : AppColors.textLight;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            active ? 'Activo' : 'Inactivo',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
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
    final hasProductCountLoaded = _layoutProductCounts.containsKey(layoutKey);

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

    final levelColor = level == 0
        ? AppColors.primary
        : level == 1
            ? const Color(0xFF6366F1)
            : const Color(0xFF8B5CF6);
    final levelIcon = level == 0
        ? Icons.home_work_rounded
        : level == 1
            ? Icons.layers_rounded
            : Icons.crop_square_rounded;

    return Column(
      children: [
        // Card principal de la zona
        Container(
          margin:
              EdgeInsets.fromLTRB(16 + (level * 18.0), 0, 16, 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.025),
                blurRadius: 6,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: levelColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      bottomLeft: Radius.circular(12),
                    ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header de la zona
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                color: levelColor.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: levelColor.withOpacity(0.18),
                                ),
                              ),
                              child: Icon(
                                levelIcon,
                                color: levelColor,
                                size: 19,
                              ),
                            ),
                            const SizedBox(width: 11),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    zone.name,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      letterSpacing: 0.1,
                                      height: 1.2,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 5),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets
                                            .symmetric(
                                          horizontal: 7,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors
                                              .surfaceVariant
                                              .withOpacity(0.6),
                                          borderRadius:
                                              BorderRadius.circular(
                                                  6),
                                          border: Border.all(
                                            color: AppColors.border,
                                          ),
                                        ),
                                        child: Text(
                                          zone.code.isNotEmpty
                                              ? zone.code
                                              : 'sin_codigo',
                                          style: const TextStyle(
                                            fontSize: 10.5,
                                            color: AppColors
                                                .textSecondary,
                                            fontFamily: 'monospace',
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      if (zone.abc != null)
                                        Container(
                                          padding: const EdgeInsets
                                              .symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getAbcColor(
                                                    zone.abc!)
                                                .withOpacity(0.10),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    6),
                                            border: Border.all(
                                              color: _getAbcColor(
                                                      zone.abc!)
                                                  .withOpacity(0.28),
                                            ),
                                          ),
                                          child: Text(
                                            _getAbcLabel(zone.abc!),
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              fontWeight:
                                                  FontWeight.w700,
                                              color: _getAbcColor(
                                                  zone.abc!),
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                // TODO: Implementar menú de opciones
                              },
                              icon: const Icon(
                                Icons.more_horiz_rounded,
                                color: AppColors.textLight,
                                size: 18,
                              ),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 30,
                                minHeight: 30,
                              ),
                              splashRadius: 18,
                            ),
                          ],
                        ),
                      ),

                      // Métricas de la zona (pills)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _zoneMetricPill(
                              icon: Icons.inventory_2_rounded,
                              label: hasProductCountLoaded
                                  ? '$productCount productos'
                                  : 'Cargando...',
                              color: const Color(0xFF6366F1),
                            ),
                            _zoneMetricPill(
                              icon: Icons.pie_chart_rounded,
                              label: '$utilization% uso',
                              color: utilization >= 80
                                  ? const Color(0xFFEF4444)
                                  : utilization >= 50
                                      ? const Color(0xFFF59E0B)
                                      : const Color(0xFF10B981),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Valoración de la zona (chips)
                      _buildZoneValuationChips(warehouseId, zone.id),

                      const SizedBox(height: 2),

                      // Botones "Ver productos" y "Exportar"
                      if (hasProductCountLoaded && productCount > 0)
                        Container(
                          margin: const EdgeInsets.symmetric(
                              horizontal: 14),
                          child: Column(
                            children: [
                              // Botón "Ver productos"
                              Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    setState(() {
                                      _expandedLayouts[layoutKey] =
                                          !isExpanded;
                                    });
                                    if (!isExpanded &&
                                        _layoutInventory[
                                                layoutKey] ==
                                            null) {
                                      _loadLayoutInventory(
                                          layoutKey, zone.id);
                                    }
                                    if (!isExpanded) {
                                      _loadZoneValuation(zone.id);
                                    }
                                  },
                                  borderRadius:
                                      BorderRadius.circular(10),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets
                                        .symmetric(
                                      horizontal: 12,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          AppColors.primary
                                              .withOpacity(0.07),
                                          AppColors.primary
                                              .withOpacity(0.03),
                                        ],
                                      ),
                                      borderRadius:
                                          BorderRadius.circular(10),
                                      border: Border.all(
                                        color: AppColors.primary
                                            .withOpacity(0.22),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary
                                                .withOpacity(0.12),
                                            borderRadius:
                                                BorderRadius.circular(
                                                    7),
                                          ),
                                          child: const Icon(
                                            Icons.list_alt_rounded,
                                            color: AppColors.primary,
                                            size: 14,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            'Ver productos ($productCount)',
                                            style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight:
                                                  FontWeight.w700,
                                              color: AppColors
                                                  .primary,
                                              letterSpacing: 0.1,
                                            ),
                                          ),
                                        ),
                                        AnimatedRotation(
                                          turns:
                                              isExpanded ? 0.5 : 0,
                                          duration: const Duration(
                                              milliseconds: 200),
                                          child: const Icon(
                                            Icons
                                                .expand_more_rounded,
                                            color: AppColors.primary,
                                            size: 20,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                      
                      // Botón de exportación (solo visible cuando los productos están expandidos)
                      // if (isExpanded && inventory.isNotEmpty) ...[
                      //   const SizedBox(height: 8),
                      //   Material(
                      //     color: Colors.transparent,
                      //     child: InkWell(
                      //       onTap: () => _showExportDialog(warehouseId, zone, inventory),
                      //       borderRadius: BorderRadius.circular(8),
                      //       child: Container(
                      //         width: double.infinity,
                      //         padding: const EdgeInsets.symmetric(
                      //           horizontal: 12,
                      //           vertical: 10,
                      //         ),
                      //         decoration: BoxDecoration(
                      //           color: AppColors.success.withOpacity(0.05),
                      //           borderRadius: BorderRadius.circular(8),
                      //           border: Border.all(
                      //             color: AppColors.success.withOpacity(0.3),
                      //           ),
                      //         ),
                      //         child: Row(
                      //           mainAxisAlignment: MainAxisAlignment.center,
                      //           children: [
                      //             Icon(
                      //               Icons.file_download_outlined,
                      //               color: AppColors.success,
                      //               size: 18,
                      //             ),
                      //             const SizedBox(width: 8),
                      //             Text(
                      //               'Exportar Lista',
                      //               style: const TextStyle(
                      //                 fontSize: 14,
                      //                 fontWeight: FontWeight.w500,
                      //                 color: AppColors.success,
                      //               ),
                      //             ),
                      //           ],
                      //         ),
                      //       ),
                      //     ),
                      //   ),
                      // ],
                    ],
                  ),
                ),

              const SizedBox(height: 14),

              // Lista de productos expandida
              if (isExpanded) ...[
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(horizontal: 14),
                  color: AppColors.border,
                ),
                if (isLoading)
                  Container(
                    padding: const EdgeInsets.all(22),
                    child: const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2.2,
                        ),
                      ),
                    ),
                  )
                else if (inventory.isEmpty)
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color:
                            AppColors.surfaceVariant.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 16,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'No hay productos en esta zona',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children:
                          inventory.map((product) {
                            final pv = _findProductValuation(
                              zone.id,
                              product.idProducto,
                            );
                            final hasStock =
                                product.stockDisponible > 0;
                            final stockColor = hasStock
                                ? AppColors.success
                                : AppColors.error;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius:
                                    BorderRadius.circular(10),
                                border:
                                    Border.all(color: AppColors.border),
                              ),
                              child: IntrinsicHeight(
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Container(
                                      width: 3,
                                      decoration: BoxDecoration(
                                        color: stockColor,
                                        borderRadius:
                                            const BorderRadius.only(
                                          topLeft:
                                              Radius.circular(10),
                                          bottomLeft:
                                              Radius.circular(10),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Padding(
                                        padding: const EdgeInsets
                                            .fromLTRB(11, 10, 11, 10),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize:
                                              MainAxisSize.min,
                                          children: [
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment
                                                      .start,
                                              children: [
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    mainAxisSize:
                                                        MainAxisSize
                                                            .min,
                                                    children: [
                                                      Text(
                                                        product
                                                            .nombreProducto,
                                                        style:
                                                            const TextStyle(
                                                          fontSize:
                                                              13.5,
                                                          fontWeight:
                                                              FontWeight
                                                                  .w700,
                                                          color: AppColors
                                                              .textPrimary,
                                                          height: 1.2,
                                                        ),
                                                        maxLines: 2,
                                                        overflow:
                                                            TextOverflow
                                                                .ellipsis,
                                                      ),
                                                      if (product
                                                          .skuProducto
                                                          .isNotEmpty) ...[
                                                        const SizedBox(
                                                            height: 3),
                                                        Container(
                                                          padding: const EdgeInsets
                                                              .symmetric(
                                                            horizontal:
                                                                6,
                                                            vertical:
                                                                1,
                                                          ),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: AppColors
                                                                .surfaceVariant
                                                                .withOpacity(
                                                                    0.55),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        5),
                                                          ),
                                                          child: Text(
                                                            product
                                                                .skuProducto,
                                                            style:
                                                                const TextStyle(
                                                              fontSize:
                                                                  10.5,
                                                              color: AppColors
                                                                  .textSecondary,
                                                              fontFamily:
                                                                  'monospace',
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(
                                                    width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 9,
                                                    vertical: 5,
                                                  ),
                                                  decoration:
                                                      BoxDecoration(
                                                    color: stockColor
                                                        .withOpacity(
                                                            0.10),
                                                    borderRadius:
                                                        BorderRadius
                                                            .circular(
                                                                8),
                                                    border: Border.all(
                                                      color: stockColor
                                                          .withOpacity(
                                                              0.22),
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize
                                                            .min,
                                                    children: [
                                                      Icon(
                                                        hasStock
                                                            ? Icons
                                                                .check_circle_rounded
                                                            : Icons
                                                                .error_outline_rounded,
                                                        size: 11,
                                                        color:
                                                            stockColor,
                                                      ),
                                                      const SizedBox(
                                                          width: 4),
                                                      Text(
                                                        '${product.stockDisponible.toInt()}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight
                                                                  .w800,
                                                          color:
                                                              stockColor,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (pv != null) ...[
                                              const SizedBox(
                                                  height: 8),
                                              _buildProductValuationRow(
                                                  pv),
                                            ] else if (_loadingZoneValuation[
                                                    zone.id] ==
                                                true) ...[
                                              const SizedBox(
                                                  height: 8),
                                              const SizedBox(
                                                height: 2,
                                                child:
                                                    LinearProgressIndicator(
                                                  color: AppColors
                                                      .primary,
                                                  backgroundColor:
                                                      Colors
                                                          .transparent,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                  ),
                // if (inventory.length > 5)
                //   Container(
                //     padding: const EdgeInsets.symmetric(
                //       horizontal: 16,
                //       vertical: 8,
                //     ),
                //     child: Text(
                //       'y ${inventory.length - 5} productos más...',
                //       style: TextStyle(
                //         fontSize: 12,
                //         color: Colors.grey[600],
                //         fontStyle: FontStyle.italic,
                //       ),
                //     ),
                //   ),
              ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // Mostrar zonas hijas si están expandidas
        // NOTA: Las zonas hijas ahora se muestran automáticamente en _buildAllZonesExpanded
        // por lo que no necesitamos lógica de expansión manual aquí
      ],
    );
  }

  Widget _zoneMetricPill({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
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
              idProducto: productData['id_producto'] ?? productData['id'] ?? 0,
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

  /// Muestra el diálogo de exportación y maneja la exportación
  Future<void> _showExportDialog(String warehouseId, WarehouseZone zone, List<InventoryProduct> products) async {
    // Encontrar el warehouse completo
    final warehouse = _warehouses.firstWhere((w) => w.id == warehouseId);
    
    // Verificar si hay más de 400 productos
    if (products.length > 400) {
      // Mostrar mensaje informativo y exportar directamente en Excel
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hay ${products.length} productos. Por rendimiento, se exportará automáticamente en Excel.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      
      // Exportar directamente en Excel
      await _exportProducts(warehouse.name, zone.name, products, ExportFormat.excel);
      return;
    }
    
    // Si hay 400 o menos productos, mostrar el diálogo normal
    await showExportDialog(
      context: context,
      warehouseName: warehouse.name,
      zoneName: zone.name,
      onPdfSelected: () => _exportProducts(warehouse.name, zone.name, products, ExportFormat.pdf),
      onExcelSelected: () => _exportProducts(warehouse.name, zone.name, products, ExportFormat.excel),
    );
  }
  
  /// Exporta los productos en el formato seleccionado
  Future<void> _exportProducts(
    String warehouseName,
    String zoneName,
    List<InventoryProduct> products,
    ExportFormat format,
  ) async {
    await _exportService.exportInventoryProducts(
      context: context,
      warehouseName: warehouseName,
      zoneName: zoneName,
      products: products,
      format: format,
    );
  }
}
