import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_colors.dart';
import '../models/warehouse.dart';
import '../services/warehouse_service.dart';
import '../services/inventory_service.dart';
import '../services/export_service.dart';
import '../services/user_preferences_service.dart';

class InventoryExportDialog extends StatefulWidget {
  const InventoryExportDialog({super.key});

  @override
  State<InventoryExportDialog> createState() => _InventoryExportDialogState();
}

class _InventoryExportDialogState extends State<InventoryExportDialog> {
  final WarehouseService _warehouseService = WarehouseService();
  final ExportService _exportService = ExportService();
  final UserPreferencesService _prefsService = UserPreferencesService();

  // State variables
  bool _isLoading = false;
  bool _isExporting = false;
  String? _exportingFormat; // 'pdf' | 'excel' mientras exporta
  int? _selectedWarehouseId;
  String _selectedWarehouseName = 'Todos';
  DateTime? _selectedDate;
  DateTime? _selectedDateTo;
  List<Warehouse> _warehouses = [];
  String? _error;

  // Opciones de columnas adicionales
  bool _includeSku = true; // Habilitado por defecto
  bool _includeNombreCorto = false;
  bool _includeMarca = false;
  bool _includeDescripcionCorta = false;
  bool _includeDescripcion = false;

  bool _includePrecios = false;

  // Opciones de filtrado
  bool _includeZeroStock = false; // Incluir productos con stock cero
  bool _soloConMovimientos =
      false; // Solo productos que se movieron en el período

  @override
  void initState() {
    super.initState();
    _loadWarehouses();
  }

  Future<void> _loadWarehouses() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final warehouses = await _warehouseService.listWarehouses();
      setState(() {
        _warehouses = warehouses;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Error al cargar almacenes: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _selectDateRange() async {
    final now = DateTime.now();
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _selectedDate != null && _selectedDateTo != null
          ? DateTimeRange(start: _selectedDate!, end: _selectedDateTo!)
          : null,
      firstDate: DateTime(2020),
      lastDate: now,
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked.start;
        _selectedDateTo = picked.end;
      });
    }
  }

  Future<void> _exportInventory(String format) async {
    setState(() {
      _isExporting = true;
      _exportingFormat = format;
    });

    try {
      // Obtener ID de tienda del usuario
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        throw Exception('No se encontró el ID de tienda del usuario');
      }

      // Siempre el reporte por movimientos (datos reales del período).
      var inventoryData = await InventoryService.getInventarioMovimientos(
        idAlmacen: _selectedWarehouseId,
        idTienda: storeId,
        fechaDesde: _selectedDate,
        fechaHasta: _selectedDateTo,
        includeZero: _includeZeroStock,
      );
      if (_soloConMovimientos) {
        inventoryData = inventoryData.where((row) {
          final extracciones =
              (row['extracciones_periodo'] as num?)?.toDouble() ?? 0;
          final ventas = (row['ventas_periodo'] as num?)?.toDouble() ?? 0;
          final pendientes =
              (row['cantidad_reservada'] as num?)?.toDouble() ?? 0;
          return extracciones > 0 || ventas > 0 || pendientes > 0;
        }).toList();
      }

      if (inventoryData.isEmpty) {
        throw Exception('No se encontraron datos de inventario para exportar');
      }

      // Si se pidieron precios completos, enriquecer filas
      List<Map<String, dynamic>> enrichedData = inventoryData;
      if (_includePrecios) {
        enrichedData = await _enrichWithPrices(inventoryData, storeId);
      }

      if (enrichedData.isEmpty) {
        throw Exception(
          'No hay productos con stock para exportar el reporte de costos',
        );
      }

      // Generar y compartir el archivo según el método seleccionado
      await _exportService.exportInventorySimple(
        context: context,
        inventoryData: enrichedData,
        warehouseName: _selectedWarehouseName,
        filterDateFrom: _selectedDate,
        filterDateTo: _selectedDateTo,
        format: format,
        includeSku: _includeSku,
        includeNombreCorto: _includeNombreCorto,
        includeMarca: _includeMarca,
        includeDescripcionCorta: _includeDescripcionCorta,
        includeDescripcion: _includeDescripcion,
        includePrecios: _includePrecios,
        includeReservado: true,
        includePresentacion: true,
      );

      // Cerrar el diálogo después de la exportación exitosa
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExporting = false;
          _exportingFormat = null;
        });
      }
    }
  }

  /// Consulta precios y costos vigentes para cada producto del inventario
  /// y los mergea en cada fila del mapa.
  Future<List<Map<String, dynamic>>> _enrichWithPrices(
    List<Map<String, dynamic>> inventoryData,
    int storeId,
  ) async {
    final supabase = Supabase.instance.client;
    final today = DateTime.now().toIso8601String().split('T')[0];

    final ids = inventoryData
        .map((r) => r['id_producto'])
        .whereType<int>()
        .toSet()
        .toList();

    if (ids.isEmpty) return inventoryData;

    // Tasa USD→CUP vigente de la tienda, fallback a tasas_conversion
    double tasa = 1.0;
    try {
      final tasaResp = await supabase
          .from('tasa_cambio_extraoficial')
          .select('valor_cambio')
          .eq('id_tienda', storeId)
          .eq('activo', true)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();
      tasa = (tasaResp?['valor_cambio'] as num?)?.toDouble() ?? 1.0;
    } catch (_) {
      try {
        final t = await supabase
            .from('tasas_conversion')
            .select('tasa')
            .eq('moneda_origen', 'USD')
            .eq('moneda_destino', 'CUP')
            .order('fecha_actualizacion', ascending: false)
            .limit(1)
            .maybeSingle();
        tasa = (t?['tasa'] as num?)?.toDouble() ?? 1.0;
      } catch (_) {}
    }

    // Precio de venta vigente por producto
    final preciosResp = await supabase
        .from('app_dat_precio_venta')
        .select('id_producto, precio_venta_cup, precio_venta_usd')
        .inFilter('id_producto', ids)
        .lte('fecha_desde', today)
        .or('fecha_hasta.is.null,fecha_hasta.gte.$today')
        .order('created_at', ascending: false);

    final Map<int, Map<String, dynamic>> preciosPorProducto = {};
    for (final row in (preciosResp as List)) {
      final pid = row['id_producto'] as int;
      if (!preciosPorProducto.containsKey(pid)) {
        preciosPorProducto[pid] = Map<String, dynamic>.from(row);
      }
    }

    // Costo promedio USD (presentación base) por producto
    final costosResp = await supabase
        .from('app_dat_producto_presentacion')
        .select('id_producto, precio_promedio')
        .inFilter('id_producto', ids)
        .eq('es_base', true);

    final Map<int, double> costoUsdPorProducto = {};
    for (final row in (costosResp as List)) {
      final pid = row['id_producto'] as int;
      costoUsdPorProducto[pid] =
          (row['precio_promedio'] as num?)?.toDouble() ?? 0.0;
    }

    // Merge de precios en cada fila
    return inventoryData.map((row) {
      final pid = row['id_producto'] as int?;
      if (pid == null) return row;

      final precio = preciosPorProducto[pid];
      final costoUsd = costoUsdPorProducto[pid] ?? 0.0;
      final costoCup = costoUsd * tasa;

      final precioVentaCup =
          (precio?['precio_venta_cup'] as num?)?.toDouble() ?? 0.0;
      final precioVentaUsd = tasa > 0 ? precioVentaCup / tasa : 0.0;
      final gananciaCup = precioVentaCup - costoCup;
      final gananciaUsd = tasa > 0 ? gananciaCup / tasa : 0.0;
      final gananciaPorc = costoCup > 0 ? (gananciaCup / costoCup) * 100 : 0.0;

      return {
        ...row,
        'precio_costo_usd': costoUsd,
        'precio_costo_cup': costoCup,
        'precio_venta_usd_calc': precioVentaUsd,
        'precio_venta_cup_actual': precioVentaCup,
        'ganancia_usd': gananciaUsd,
        'ganancia_cup': gananciaCup,
        'ganancia_pct': gananciaPorc,
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.file_download_outlined,
                    size: 24,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(width: 16),
                const Expanded(
                  child: Text(
                    'Exportar Inventario',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: AppColors.textSecondary),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Selección de almacén
                    const Text(
                      'Almacén',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isLoading)
                      const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      )
                    else if (_error != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.error.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: AppColors.error.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _error!,
                                style: const TextStyle(
                                  color: AppColors.error,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      DropdownButtonFormField<int?>(
                        value: _selectedWarehouseId,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        hint: const Text('Seleccionar almacén'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text(
                              'Todos los almacenes',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ..._warehouses.map((warehouse) {
                            return DropdownMenuItem<int?>(
                              value: int.parse(warehouse.id),
                              child: Text(
                                warehouse.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            );
                          }),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _selectedWarehouseId = value;
                            _selectedWarehouseName = value == null
                                ? 'Todos los almacenes'
                                : _warehouses
                                      .firstWhere(
                                        (w) => int.parse(w.id) == value,
                                      )
                                      .name;
                          });
                        },
                      ),

                    const SizedBox(height: 24),

                    // Período: un solo selector de rango (desde–hasta)
                    const Text(
                      'Período (Opcional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: _selectDateRange,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: Colors.grey.withOpacity(0.5),
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.date_range,
                              color: AppColors.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _selectedDate != null && _selectedDateTo != null
                                    ? '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year} – ${_selectedDateTo!.day}/${_selectedDateTo!.month}/${_selectedDateTo!.year}'
                                    : 'Seleccionar período',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _selectedDate != null
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (_selectedDate != null ||
                                _selectedDateTo != null)
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _selectedDate = null;
                                    _selectedDateTo = null;
                                  });
                                },
                                icon: const Icon(
                                  Icons.clear,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 24,
                                  minHeight: 24,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Columnas adicionales
                    const Text(
                      'Columnas Adicionales (Opcional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: [
                          CheckboxListTile(
                            title: const Text(
                              'SKU',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Código SKU del producto',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includeSku,
                            onChanged: (value) {
                              setState(() {
                                _includeSku = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            title: const Text(
                              'Nombre Corto',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Denominación corta del producto',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includeNombreCorto,
                            onChanged: (value) {
                              setState(() {
                                _includeNombreCorto = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            title: const Text(
                              'Marca',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Nombre comercial/marca del producto',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includeMarca,
                            onChanged: (value) {
                              setState(() {
                                _includeMarca = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            title: const Text(
                              'Descripción Corta',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Descripción corta del producto',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includeDescripcionCorta,
                            onChanged: (value) {
                              setState(() {
                                _includeDescripcionCorta = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            title: const Text(
                              'Descripción',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Descripción completa del producto',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includeDescripcion,
                            onChanged: (value) {
                              setState(() {
                                _includeDescripcion = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          CheckboxListTile(
                            title: const Text(
                              'Incluir Precios',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Costo USD/CUP, Precio Venta USD/CUP, Ganancia USD/CUP y %Ganancia',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includePrecios,
                            onChanged: (value) {
                              setState(() {
                                _includePrecios = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const Divider(height: 24),

                          // Sección de filtros
                          const Text(
                            'Opciones de Filtrado',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 8),

                          CheckboxListTile(
                            title: const Text(
                              'Incluir productos con stock cero',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Mostrar productos que tienen registro en inventario pero sin stock actual',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _includeZeroStock,
                            onChanged: (value) {
                              setState(() {
                                _includeZeroStock = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),

                          const SizedBox(height: 8),
                          CheckboxListTile(
                            title: const Text(
                              'Solo productos con movimientos',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: const Text(
                              'Excluir productos que no tuvieron extracciones, ventas ni pendientes en el período',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            value: _soloConMovimientos,
                            onChanged: (value) {
                              setState(() {
                                _soloConMovimientos = value ?? false;
                              });
                            },
                            activeColor: AppColors.primary,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Información adicional
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.info.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.info.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppColors.info,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'El reporte incluirá las columnas básicas (nombre del producto, stock disponible, cantidad inicial, cantidad final, precio de venta y presentación) más las columnas adicionales seleccionadas.',
                              style: TextStyle(
                                color: AppColors.info.withOpacity(0.8),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Botones de acción: cada formato exporta directo
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                TextButton(
                  onPressed: _isExporting
                      ? null
                      : () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                  ),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _exportInventory('pdf'),
                  icon: const Icon(Icons.picture_as_pdf, size: 20),
                  label: _exportingFormat == 'pdf'
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Exportar PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _isExporting
                      ? null
                      : () => _exportInventory('excel'),
                  icon: const Icon(Icons.table_chart, size: 20),
                  label: _exportingFormat == 'excel'
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Exportar Excel'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: 12,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Función helper para mostrar el diálogo de exportación de inventario
Future<void> showInventoryExportDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return const InventoryExportDialog();
    },
  );
}
