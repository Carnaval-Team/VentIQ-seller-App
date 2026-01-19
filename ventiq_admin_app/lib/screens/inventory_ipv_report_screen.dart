import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' hide Border;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import '../config/app_colors.dart';
import '../services/user_preferences_service.dart';
import '../services/inventory_service.dart';
import '../services/web_download_stub.dart'
    if (dart.library.html) '../services/web_download_web.dart'
    as web_download;

class InventoryIPVReportScreen extends StatefulWidget {
  const InventoryIPVReportScreen({super.key});

  @override
  State<InventoryIPVReportScreen> createState() =>
      _InventoryIPVReportScreenState();
}

enum Moneda { usd, cup }

class _InventoryIPVReportScreenState extends State<InventoryIPVReportScreen> {
  List<Map<String, dynamic>> _reportData = [];
  bool _isLoading = true;
  String _errorMessage = '';
  int? _idTienda;
  int? _selectedWarehouseId;
  String _selectedWarehouseName = 'Todos los almacenes';
  DateTime? _fechaDesde = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  DateTime? _fechaHasta = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day, 23, 59, 59);
  bool _includeZero = true;
  Moneda _monedaSeleccionada = Moneda.cup;
  double _tasaConversion = 1.0; // USD a CUP
  List<Map<String, dynamic>> _warehouses = [];

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userPrefs = UserPreferencesService();
      final userData = await userPrefs.getUserData();
      final idTiendaNum = userData['idTienda'];
      final idTienda = idTiendaNum != null ? (idTiendaNum as num).toInt() : null;

      if (idTienda == null) {
        setState(() {
          _errorMessage = 'No se encontró información de la tienda';
          _isLoading = false;
        });
        return;
      }

      setState(() => _idTienda = idTienda);
      await _loadWarehouses();
      await _loadReportData();
    } catch (e) {
      setState(() {
        _errorMessage = 'Error al cargar datos del usuario: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadWarehouses() async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_dat_almacen')
          .select('id, nombre')
          .eq('id_tienda', _idTienda!)
          .order('nombre');

      if (mounted) {
        setState(() {
          _warehouses = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      print('Error al cargar almacenes: $e');
    }
  }

  Future<void> _loadReportData() async {
    try {
      setState(() => _isLoading = true);

      final data = await InventoryService.getIPVReport(
        idTienda: _idTienda,
        idAlmacen: _selectedWarehouseId,
        fechaDesde: _fechaDesde,
        fechaHasta: _fechaHasta,
        includeZero: _includeZero,
      );

      if (!mounted) return;

      // Obtener tasa de conversión independientemente
      double tasa = await _obtenerTasaConversion();

      setState(() {
        _reportData = data;
        _tasaConversion = tasa;
        _isLoading = false;
        _errorMessage = '';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Error al cargar reporte: $e';
        _isLoading = false;
      });
    }
  }

  Future<double> _obtenerTasaConversion() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Obtener códigos de moneda dinámicamente
      print('🔍 Obteniendo códigos de monedas desde tabla monedas');
      
      // Obtener USD
      final usdResponse = await supabase
          .from('monedas')
          .select('codigo')
          .eq('nombre', 'USD')
          .limit(1);
      
      // Obtener CUP
      final cupResponse = await supabase
          .from('monedas')
          .select('codigo')
          .eq('nombre', 'CUP')
          .limit(1);
      
      print('📦 USD Response: $usdResponse');
      print('📦 CUP Response: $cupResponse');
      
      if (usdResponse.isEmpty || cupResponse.isEmpty) {
        print('⚠️ No se encontraron monedas USD o CUP en la tabla monedas');
        return 1.0;
      }
      
      // Extraer códigos de moneda (trim para eliminar espacios de bpchar)
      final codigoUSD = (usdResponse[0]['codigo'] as String).trim();
      final codigoCUP = (cupResponse[0]['codigo'] as String).trim();
      
      print('🔍 Códigos obtenidos - USD: "$codigoUSD", CUP: "$codigoCUP"');
      
      // Buscar tasa de conversión con los códigos dinámicos
      print('🔍 Buscando tasa de conversión: moneda_origen=$codigoUSD, moneda_destino=$codigoCUP');
      
      final tasaResponse = await supabase
          .from('tasas_conversion')
          .select('tasa, fecha_actualizacion')
          .eq('moneda_origen', codigoUSD)
          .eq('moneda_destino', codigoCUP)
          .order('fecha_actualizacion', ascending: false)
          .limit(1);

      print('📦 Respuesta de tasa: $tasaResponse');
      print('📦 Tipo de respuesta: ${tasaResponse.runtimeType}');
      print('📦 Longitud: ${tasaResponse.length}');
      
      if (tasaResponse.isNotEmpty) {
        print('📦 Primer registro: ${tasaResponse[0]}');
        final tasa = tasaResponse[0]['tasa'];
        final fecha = tasaResponse[0]['fecha_actualizacion'];
        print('📦 Valor de tasa: $tasa (tipo: ${tasa.runtimeType})');
        print('📦 Fecha actualización: $fecha');
        
        if (tasa != null) {
          final tasaDouble = (tasa as num).toDouble();
          print('📊 Tasa de conversión obtenida ($codigoUSD→$codigoCUP): $tasaDouble');
          return tasaDouble;
        }
      }
      print('⚠️ No se encontró tasa de conversión, usando 1.0 por defecto');
      return 1.0;
    } catch (e) {
      print('❌ Error al obtener tasa de conversión: $e');
      print('❌ Stack trace: ${StackTrace.current}');
      return 1.0;
    }
  }

  double _convertirValor(double valorUsd) {
    if (_monedaSeleccionada == Moneda.cup) {
      return valorUsd * _tasaConversion;
    }
    return valorUsd;
  }

  Map<String, double> _calcularTotales() {
    double totalInvInicialCostoCant = 0;
    double totalInvInicialCostoImporte = 0;
    double totalInvInicialVentaCant = 0;
    double totalInvInicialVentaImporte = 0;
    double totalEntradas = 0;
    double totalReservados = 0;
    double totalDisponible = 0;
    double totalExtracciones = 0;
    double totalVendido = 0;
    double totalInvFinalCant = 0;
    double totalInvFinalImporte = 0;
    double totalVentaPrecio = 0;
    double totalVentaImporte = 0;
    double totalCostoUnitario = 0;
    double totalCostoTotal = 0;

    for (final item in _reportData) {
      final cantidadInicial = (item['cantidad_inicial'] as num?)?.toDouble() ?? 0;
      final cantidadFinal = (item['cantidad_final'] as num?)?.toDouble() ?? 0;
      final cantidadVendida = (item['cantidad_ventas'] as num?)?.toDouble() ?? 0;
      final cantidadEntradas = (item['cantidad_entradas'] as num?)?.toDouble() ?? 0;
      // Costo promedio en USD
      final costoPromedioUsd = (item['costo_promedio_usd'] as num?)?.toDouble() ?? 0;
      // Precio de venta en CUP
      final precioVentaCup = (item['precio_venta'] as num?)?.toDouble() ?? 0;
      final reservado = (item['reservado'] as num?)?.toDouble() ?? 0;
      final extracciones = (item['extracciones'] as num?)?.toDouble() ?? 0;

      totalInvInicialCostoCant += cantidadInicial;
      totalInvInicialCostoImporte += cantidadInicial * costoPromedioUsd;
      totalInvInicialVentaCant += cantidadInicial;
      totalInvInicialVentaImporte += cantidadInicial * precioVentaCup;
      totalEntradas += cantidadEntradas;
      totalReservados += reservado;
      totalDisponible += (cantidadInicial + cantidadEntradas - extracciones);
      totalExtracciones += extracciones;
      totalVendido += cantidadVendida;
      totalInvFinalCant += cantidadFinal;
      totalInvFinalImporte += cantidadFinal * costoPromedioUsd;
      totalVentaPrecio += precioVentaCup;
      totalVentaImporte += cantidadVendida * precioVentaCup;
      totalCostoUnitario += costoPromedioUsd;
      totalCostoTotal += cantidadFinal * costoPromedioUsd;
    }

    return {
      'invInicialCostoCant': totalInvInicialCostoCant,
      'invInicialCostoImporte': totalInvInicialCostoImporte,
      'invInicialVentaCant': totalInvInicialVentaCant,
      'invInicialVentaImporte': totalInvInicialVentaImporte,
      'entradas': totalEntradas,
      'reservados': totalReservados,
      'disponible': totalDisponible,
      'extracciones': totalExtracciones,
      'vendido': totalVendido,
      'invFinalCant': totalInvFinalCant,
      'invFinalImporte': totalInvFinalImporte,
      'ventaPrecio': totalVentaPrecio,
      'ventaImporte': totalVentaImporte,
      'costoUnitario': totalCostoUnitario,
      'costoTotal': totalCostoTotal,
    };
  }

  void _showFilterBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.7,
            maxChildSize: 0.95,
            minChildSize: 0.5,
            builder: (context, scrollController) => SingleChildScrollView(
              controller: scrollController,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Encabezado
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Filtros y Opciones',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Selector de Almacén
                    const Text(
                      'Almacén',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
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
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todos los almacenes'),
                        ),
                        ..._warehouses.map((warehouse) {
                          return DropdownMenuItem<int?>(
                            value: (warehouse['id'] as num?)?.toInt(),
                            child: Text(warehouse['nombre'] ?? 'N/A'),
                          );
                        }),
                      ],
                      onChanged: (int? value) {
                        setModalState(() {
                          _selectedWarehouseId = value;
                          _selectedWarehouseName = value == null
                              ? 'Todos los almacenes'
                              : _warehouses
                                  .firstWhere(
                                    (w) => w['id'] == value,
                                    orElse: () => {'nombre': 'N/A'},
                                  )['nombre'] ??
                                  'N/A';
                        });
                        setState(() {});
                      },
                    ),
                    const SizedBox(height: 24),

                    // Selector de Moneda
                    const Text(
                      'Moneda',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<Moneda>(
                            segments: const [
                              ButtonSegment(
                                value: Moneda.cup,
                                label: Text('CUP (₡)'),
                              ),
                              ButtonSegment(
                                value: Moneda.usd,
                                label: Text('USD (\$)'),
                              ),
                            ],
                            selected: {_monedaSeleccionada},
                            onSelectionChanged: (Set<Moneda> newSelection) {
                              setModalState(() {
                                _monedaSeleccionada = newSelection.first;
                              });
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Filtro de Fechas
                    const Text(
                      'Filtro de Fechas (Opcional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _fechaDesde ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setModalState(() => _fechaDesde = date);
                          setState(() {});
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: AppColors.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _fechaDesde != null
                                    ? 'Desde: ${_fechaDesde!.day}/${_fechaDesde!.month}/${_fechaDesde!.year}'
                                    : 'Seleccionar fecha desde',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _fechaDesde != null
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (_fechaDesde != null)
                              IconButton(
                                onPressed: () {
                                  setModalState(() => _fechaDesde = null);
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear,
                                    color: AppColors.textSecondary, size: 20),
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
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _fechaHasta ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime.now(),
                        );
                        if (date != null) {
                          setModalState(() => _fechaHasta = DateTime(date.year, date.month, date.day, 23, 59, 59));
                          setState(() {});
                        }
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.calendar_today,
                                color: AppColors.primary, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _fechaHasta != null
                                    ? 'Hasta: ${_fechaHasta!.day}/${_fechaHasta!.month}/${_fechaHasta!.year}'
                                    : 'Seleccionar fecha hasta',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: _fechaHasta != null
                                      ? AppColors.textPrimary
                                      : AppColors.textSecondary,
                                ),
                              ),
                            ),
                            if (_fechaHasta != null)
                              IconButton(
                                onPressed: () {
                                  setModalState(() => _fechaHasta = null);
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear,
                                    color: AppColors.textSecondary, size: 20),
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

                    // Botones de Exportación
                    const Text(
                      'Exportar',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _exportToPDF,
                            icon: const Icon(Icons.picture_as_pdf),
                            label: const Text('PDF'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.red,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _exportToExcel,
                            icon: const Icon(Icons.table_chart),
                            label: const Text('Excel'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // Botones de Acción
                    Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            onPressed: () {
                              setModalState(() {
                                _selectedWarehouseId = null;
                                _selectedWarehouseName = 'Todos los almacenes';
                                final now = DateTime.now();
                                _fechaDesde = DateTime(now.year, now.month, now.day);
                                _fechaHasta = DateTime(now.year, now.month, now.day, 23, 59, 59);
                                _includeZero = true;
                                _monedaSeleccionada = Moneda.cup;
                              });
                              setState(() {});
                            },
                            child: const Text('Limpiar Filtros'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              _loadReportData();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Aplicar'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('🔨 BUILD called - Moneda actual: ${_monedaSeleccionada.name}, Tasa: $_tasaConversion');
    final totales = _calcularTotales();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reporte IPV'),
        backgroundColor: AppColors.primary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showFilterBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReportData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline,
                          size: 64, color: AppColors.error),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadReportData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : _reportData.isEmpty
                  ? const Center(
                      child: Text('No hay datos disponibles'),
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.vertical,
                        child: Table(
                          key: ValueKey<Moneda>(_monedaSeleccionada),
                          border: TableBorder.all(color: Colors.grey[400]!),
                          columnWidths: const {
                            0: FixedColumnWidth(90),
                            1: FixedColumnWidth(90),
                            2: FixedColumnWidth(90),
                            3: FixedColumnWidth(90),
                            4: FixedColumnWidth(90),
                            5: FixedColumnWidth(90),
                            6: FixedColumnWidth(90),
                            7: FixedColumnWidth(90),
                            8: FixedColumnWidth(90),
                            9: FixedColumnWidth(90),
                            10: FixedColumnWidth(90),
                            11: FixedColumnWidth(90),
                            12: FixedColumnWidth(90),
                            13: FixedColumnWidth(90),
                            14: FixedColumnWidth(90),
                            15: FixedColumnWidth(90),
                            16: FixedColumnWidth(90),
                          },
                          children: [
                            // Encabezado Fila 1 (Títulos principales)
                            TableRow(
                              decoration: BoxDecoration(color: Colors.grey[300]),
                              children: [
                                _buildTableHeaderCell('PRODUCTO'),
                                _buildTableHeaderCell('UM'),
                                _buildTableHeaderCell('INV. INICIAL\nCOSTO'),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell('INV. INICIAL\nVENTA'),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell('CANTIDAD'),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell('INV. FINAL'),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell('VENTA'),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell('COSTO'),
                                _buildTableHeaderCell(''),
                              ],
                            ),
                            // Encabezado Fila 2 (Subencabezados)
                            TableRow(
                              decoration: BoxDecoration(color: Colors.grey[300]),
                              children: [
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell(''),
                                _buildTableHeaderCell('Cant.'),
                                _buildTableHeaderCell('Importe'),
                                _buildTableHeaderCell('Cant.'),
                                _buildTableHeaderCell('Importe'),
                                _buildTableHeaderCell('Entrada'),
                                _buildTableHeaderCell('Reservados'),
                                _buildTableHeaderCell('Disponible'),
                                _buildTableHeaderCell('Vendido'),
                                _buildTableHeaderCell('Extracciones'),
                                _buildTableHeaderCell('Cant.'),
                                _buildTableHeaderCell('Importe'),
                                _buildTableHeaderCell('Precio'),
                                _buildTableHeaderCell('Importe'),
                                _buildTableHeaderCell('Unitario'),
                                _buildTableHeaderCell('Costo Total'),
                              ],
                            ),
                            // Filas de datos
                            ..._buildTableDataRows(totales),
                            // Fila de totales
                            _buildTableTotalesRow(totales),
                          ],
                        ),
                      ),
                    ),
    );
  }

  Widget _buildHeaderCell(String text, {bool isBold = true}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildTableDataCell(String text, {bool isBold = false, bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: isTotal ? 11 : 9,
          fontWeight: isTotal ? FontWeight.bold : (isBold ? FontWeight.bold : FontWeight.normal),
        ),
        textAlign: TextAlign.right,
      ),
    );
  }

  List<TableRow> _buildTableDataRows(Map<String, double> totales) {
    return _reportData.map((item) {
      final cantidadInicial =
          (item['cantidad_inicial'] as num?)?.toDouble() ?? 0;
      final cantidadFinal =
          (item['cantidad_final'] as num?)?.toDouble() ?? 0;
      final cantidadVendida =
          (item['cantidad_ventas'] as num?)?.toDouble() ?? 0;
      final cantidadEntradas =
          (item['cantidad_entradas'] as num?)?.toDouble() ?? 0;
      final costoPromedioUsd =
          (item['costo_promedio_usd'] as num?)?.toDouble() ?? 0;
      final precioVentaCup =
          (item['precio_venta'] as num?)?.toDouble() ?? 0;
      final reservado =
          (item['reservado'] as num?)?.toDouble() ?? 0;
      final extracciones =
          (item['extracciones'] as num?)?.toDouble() ?? 0;

      final costoUnitarioConvertido = _convertirValor(costoPromedioUsd);
      final ventaPrecioConvertido = _monedaSeleccionada == Moneda.cup
          ? precioVentaCup
          : precioVentaCup / _tasaConversion;

      final invInicialCostoImporte =
          _convertirValor(cantidadInicial * costoPromedioUsd);
      final invInicialVentaImporte = _monedaSeleccionada == Moneda.cup
          ? cantidadInicial * precioVentaCup
          : cantidadInicial * (precioVentaCup / _tasaConversion);
      final invFinalImporte =
          _convertirValor(cantidadFinal * costoPromedioUsd);
      final ventaImporte = _monedaSeleccionada == Moneda.cup
          ? cantidadVendida * precioVentaCup
          : cantidadVendida * (precioVentaCup / _tasaConversion);
      final costoTotal = _convertirValor(cantidadFinal * costoPromedioUsd);

      final disponible = cantidadInicial + cantidadEntradas - extracciones;

      return TableRow(
        children: [
          _buildTableDataCell(item['nombre_producto'] ?? 'N/A'),
          _buildTableDataCell(item['um'] ?? ''),
          _buildTableDataCell(cantidadInicial.toStringAsFixed(2)),
          _buildTableDataCell(invInicialCostoImporte.toStringAsFixed(2)),
          _buildTableDataCell(cantidadInicial.toStringAsFixed(2)),
          _buildTableDataCell(invInicialVentaImporte.toStringAsFixed(2)),
          _buildTableDataCell(cantidadEntradas.toStringAsFixed(2)),
          _buildTableDataCell(reservado.toStringAsFixed(2)),
          _buildTableDataCell(disponible.toStringAsFixed(2)),
          _buildTableDataCell(cantidadVendida.toStringAsFixed(2)),
          _buildTableDataCell(extracciones.toStringAsFixed(2)),
          _buildTableDataCell(cantidadFinal.toStringAsFixed(2)),
          _buildTableDataCell(invFinalImporte.toStringAsFixed(2)),
          _buildTableDataCell(ventaPrecioConvertido.toStringAsFixed(2)),
          _buildTableDataCell(ventaImporte.toStringAsFixed(2)),
          _buildTableDataCell(costoUnitarioConvertido.toStringAsFixed(2)),
          _buildTableDataCell(costoTotal.toStringAsFixed(2)),
        ],
      );
    }).toList();
  }

  TableRow _buildTableTotalesRow(Map<String, double> totales) {
    return TableRow(
      decoration: BoxDecoration(color: Colors.yellow[200]),
      children: [
        _buildTableDataCell('TOTALES', isTotal: true),
        _buildTableDataCell('', isTotal: true),
        _buildTableDataCell(totales['invInicialCostoCant']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            _convertirValor(totales['invInicialCostoImporte']!)
                .toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['invInicialVentaCant']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            (_monedaSeleccionada == Moneda.cup
                    ? totales['invInicialVentaImporte']!
                    : totales['invInicialVentaImporte']! / _tasaConversion)
                .toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['entradas']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['reservados']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['disponible']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['vendido']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['extracciones']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(totales['invFinalCant']!.toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            _convertirValor(totales['invFinalImporte']!).toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            (_monedaSeleccionada == Moneda.cup
                    ? totales['ventaPrecio']!
                    : totales['ventaPrecio']! / _tasaConversion)
                .toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            (_monedaSeleccionada == Moneda.cup
                    ? totales['ventaImporte']!
                    : totales['ventaImporte']! / _tasaConversion)
                .toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            _convertirValor(totales['costoUnitario']!).toStringAsFixed(2),
            isTotal: true),
        _buildTableDataCell(
            _convertirValor(totales['costoTotal']!).toStringAsFixed(2),
            isTotal: true),
      ],
    );
  }

  Future<void> _exportToPDF() async {
    try {
      final pdf = pw.Document();
      final totales = _calcularTotales();
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final almacenStr = _selectedWarehouseName.replaceAll(' ', '_');
      final fileName = 'Reporte_IPV_${almacenStr}_${_monedaSeleccionada.name.toUpperCase()}_$dateStr.pdf';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return [
              pw.Text('Reporte IPV - ${_monedaSeleccionada.name.toUpperCase()}',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 10),
              pw.Table(
                border: pw.TableBorder.all(),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1),
                  3: const pw.FlexColumnWidth(1),
                  4: const pw.FlexColumnWidth(1),
                  5: const pw.FlexColumnWidth(1),
                  6: const pw.FlexColumnWidth(1),
                  7: const pw.FlexColumnWidth(1),
                  8: const pw.FlexColumnWidth(1),
                  9: const pw.FlexColumnWidth(1),
                  10: const pw.FlexColumnWidth(1),
                  11: const pw.FlexColumnWidth(1),
                  12: const pw.FlexColumnWidth(1),
                  13: const pw.FlexColumnWidth(1),
                  14: const pw.FlexColumnWidth(1),
                },
                children: [
                  // Encabezado Fila 1
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFCCCCCC)),
                    children: [
                      _pdfHeaderCell('PRODUCTO'),
                      _pdfHeaderCell('UM'),
                      _pdfHeaderCell('INV. INICIAL\nCOSTO'),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell('INV. INICIAL\nVENTA'),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell('CANTIDAD'),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell('INV. FINAL'),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell('VENTA'),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell('COSTO'),
                      _pdfHeaderCell(''),
                    ],
                  ),
                  // Encabezado Fila 2
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFCCCCCC)),
                    children: [
                      _pdfHeaderCell(''),
                      _pdfHeaderCell(''),
                      _pdfHeaderCell('Cant.'),
                      _pdfHeaderCell('Importe'),
                      _pdfHeaderCell('Cant.'),
                      _pdfHeaderCell('Importe'),
                      _pdfHeaderCell('Entrada'),
                      _pdfHeaderCell('Disponible'),
                      _pdfHeaderCell('Vendido'),
                      _pdfHeaderCell('Cant.'),
                      _pdfHeaderCell('Importe'),
                      _pdfHeaderCell('Precio'),
                      _pdfHeaderCell('Importe'),
                      _pdfHeaderCell('Unitario'),
                      _pdfHeaderCell('Costo Total'),
                    ],
                  ),
                  // Filas de datos
                  ..._reportData.map((item) {
                    final cantidadInicial =
                        (item['cantidad_inicial'] as num?)?.toDouble() ?? 0;
                    final cantidadFinal =
                        (item['cantidad_final'] as num?)?.toDouble() ?? 0;
                    final cantidadVendida =
                        (item['cantidad_ventas'] as num?)?.toDouble() ?? 0;
                    final cantidadEntradas =
                        (item['cantidad_entradas'] as num?)?.toDouble() ?? 0;
                    final costoPromedioUsd =
                        (item['costo_promedio_usd'] as num?)?.toDouble() ?? 0;
                    final precioVentaCup =
                        (item['precio_venta'] as num?)?.toDouble() ?? 0;
                    final reservado =
                        (item['reservado'] as num?)?.toDouble() ?? 0;

                    final costoUnitarioConvertido =
                        _convertirValor(costoPromedioUsd);
                    final ventaPrecioConvertido =
                        _monedaSeleccionada == Moneda.cup
                            ? precioVentaCup
                            : precioVentaCup / _tasaConversion;

                    final invInicialCostoImporte =
                        _convertirValor(cantidadInicial * costoPromedioUsd);
                    final invInicialVentaImporte =
                        _monedaSeleccionada == Moneda.cup
                            ? cantidadInicial * precioVentaCup
                            : cantidadInicial * (precioVentaCup / _tasaConversion);
                    final invFinalImporte = _convertirValor(
                        cantidadFinal * costoPromedioUsd);
                    final ventaImporte = _monedaSeleccionada == Moneda.cup
                        ? cantidadVendida * precioVentaCup
                        : cantidadVendida * (precioVentaCup / _tasaConversion);
                    final costoTotal = _convertirValor(
                        cantidadFinal * costoPromedioUsd);

                    return pw.TableRow(
                      children: [
                        _pdfDataCell(item['nombre_producto'] ?? 'N/A'),
                        _pdfDataCell(item['um'] ?? ''),
                        _pdfDataCell(cantidadInicial.toStringAsFixed(2)),
                        _pdfDataCell(invInicialCostoImporte.toStringAsFixed(2)),
                        _pdfDataCell(cantidadInicial.toStringAsFixed(2)),
                        _pdfDataCell(invInicialVentaImporte.toStringAsFixed(2)),
                        _pdfDataCell(cantidadEntradas.toStringAsFixed(2)),
                        _pdfDataCell(
                            (cantidadFinal - reservado).toStringAsFixed(2)),
                        _pdfDataCell(cantidadVendida.toStringAsFixed(2)),
                        _pdfDataCell(cantidadFinal.toStringAsFixed(2)),
                        _pdfDataCell(invFinalImporte.toStringAsFixed(2)),
                        _pdfDataCell(ventaPrecioConvertido.toStringAsFixed(2)),
                        _pdfDataCell(ventaImporte.toStringAsFixed(2)),
                        _pdfDataCell(costoUnitarioConvertido.toStringAsFixed(2)),
                        _pdfDataCell(costoTotal.toStringAsFixed(2)),
                      ],
                    );
                  }).toList(),
                  // Fila de totales
                  pw.TableRow(
                    decoration: pw.BoxDecoration(
                        color: PdfColor.fromInt(0xFFFFFF00)),
                    children: [
                      _pdfDataCell('TOTALES', isBold: true),
                      _pdfDataCell('', isBold: true),
                      _pdfDataCell(
                          totales['invInicialCostoCant']!.toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          _convertirValor(totales['invInicialCostoImporte']!)
                              .toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          totales['invInicialVentaCant']!.toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          (_monedaSeleccionada == Moneda.cup
                                  ? totales['invInicialVentaImporte']!
                                  : totales['invInicialVentaImporte']! /
                                      _tasaConversion)
                              .toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(totales['entradas']!.toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(totales['disponible']!.toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(totales['vendido']!.toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(totales['invFinalCant']!.toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          _convertirValor(totales['invFinalImporte']!)
                              .toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          (_monedaSeleccionada == Moneda.cup
                                  ? totales['ventaPrecio']!
                                  : totales['ventaPrecio']! / _tasaConversion)
                              .toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          (_monedaSeleccionada == Moneda.cup
                                  ? totales['ventaImporte']!
                                  : totales['ventaImporte']! / _tasaConversion)
                              .toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          _convertirValor(totales['costoUnitario']!)
                              .toStringAsFixed(2),
                          isBold: true),
                      _pdfDataCell(
                          _convertirValor(totales['costoTotal']!)
                              .toStringAsFixed(2),
                          isBold: true),
                    ],
                  ),
                ],
              ),
            ];
          },
        ),
      );

      final fileBytes = Uint8List.fromList(await pdf.save());
      const mimeType = 'application/pdf';

      if (kIsWeb) {
        // Descarga directa en web
        try {
          web_download.downloadFileWeb(fileBytes, fileName, mimeType);
        } catch (webError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Problema de compatibilidad del navegador. Intenta con Edge o actualiza tu navegador.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      } else {
        // Compartir en APK
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(fileBytes);

        await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: 'Reporte IPV - ${_monedaSeleccionada.name.toUpperCase()}',
          text:
              'Reporte IPV generado el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        );
      }

      if (mounted) {
        final message = kIsWeb
            ? 'PDF descargado exitosamente'
            : 'PDF generado y compartido exitosamente';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar PDF: $e'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _exportToExcel() async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      final totales = _calcularTotales();
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final almacenStr = _selectedWarehouseName.replaceAll(' ', '_');
      final fileName = 'Reporte_IPV_${almacenStr}_${_monedaSeleccionada.name.toUpperCase()}_$dateStr.xlsx';

      // Encabezado Fila 1
      sheet.appendRow([
        TextCellValue('PRODUCTO'),
        TextCellValue('UM'),
        TextCellValue('INV. INICIAL COSTO'),
        TextCellValue(''),
        TextCellValue('INV. INICIAL VENTA'),
        TextCellValue(''),
        TextCellValue('CANTIDAD'),
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('INV. FINAL'),
        TextCellValue(''),
        TextCellValue('VENTA'),
        TextCellValue(''),
        TextCellValue('COSTO'),
        TextCellValue(''),
      ]);

      // Encabezado Fila 2
      sheet.appendRow([
        TextCellValue(''),
        TextCellValue(''),
        TextCellValue('Cant.'),
        TextCellValue('Importe'),
        TextCellValue('Cant.'),
        TextCellValue('Importe'),
        TextCellValue('Entrada'),
        TextCellValue('Disponible'),
        TextCellValue('Vendido'),
        TextCellValue('Cant.'),
        TextCellValue('Importe'),
        TextCellValue('Precio'),
        TextCellValue('Importe'),
        TextCellValue('Unitario'),
        TextCellValue('Costo Total'),
      ]);

      // Filas de datos
      for (var item in _reportData) {
        final cantidadInicial =
            (item['cantidad_inicial'] as num?)?.toDouble() ?? 0;
        final cantidadFinal =
            (item['cantidad_final'] as num?)?.toDouble() ?? 0;
        final cantidadVendida =
            (item['cantidad_ventas'] as num?)?.toDouble() ?? 0;
        final cantidadEntradas =
            (item['cantidad_entradas'] as num?)?.toDouble() ?? 0;
        final costoPromedioUsd =
            (item['costo_promedio_usd'] as num?)?.toDouble() ?? 0;
        final precioVentaCup =
            (item['precio_venta'] as num?)?.toDouble() ?? 0;
        final reservado = (item['reservado'] as num?)?.toDouble() ?? 0;

        final costoUnitarioConvertido = _convertirValor(costoPromedioUsd);
        final ventaPrecioConvertido = _monedaSeleccionada == Moneda.cup
            ? precioVentaCup
            : precioVentaCup / _tasaConversion;

        final invInicialCostoImporte =
            _convertirValor(cantidadInicial * costoPromedioUsd);
        final invInicialVentaImporte = _monedaSeleccionada == Moneda.cup
            ? cantidadInicial * precioVentaCup
            : cantidadInicial * (precioVentaCup / _tasaConversion);
        final invFinalImporte =
            _convertirValor(cantidadFinal * costoPromedioUsd);
        final ventaImporte = _monedaSeleccionada == Moneda.cup
            ? cantidadVendida * precioVentaCup
            : cantidadVendida * (precioVentaCup / _tasaConversion);
        final costoTotal = _convertirValor(cantidadFinal * costoPromedioUsd);

        sheet.appendRow([
          TextCellValue(item['nombre_producto'] ?? 'N/A'),
          TextCellValue(item['um'] ?? ''),
          TextCellValue(cantidadInicial.toStringAsFixed(2)),
          TextCellValue(invInicialCostoImporte.toStringAsFixed(2)),
          TextCellValue(cantidadInicial.toStringAsFixed(2)),
          TextCellValue(invInicialVentaImporte.toStringAsFixed(2)),
          TextCellValue(cantidadEntradas.toStringAsFixed(2)),
          TextCellValue((cantidadFinal - reservado).toStringAsFixed(2)),
          TextCellValue(cantidadVendida.toStringAsFixed(2)),
          TextCellValue(cantidadFinal.toStringAsFixed(2)),
          TextCellValue(invFinalImporte.toStringAsFixed(2)),
          TextCellValue(ventaPrecioConvertido.toStringAsFixed(2)),
          TextCellValue(ventaImporte.toStringAsFixed(2)),
          TextCellValue(costoUnitarioConvertido.toStringAsFixed(2)),
          TextCellValue(costoTotal.toStringAsFixed(2)),
        ]);
      }

      // Fila de totales
      sheet.appendRow([
        TextCellValue('TOTALES'),
        TextCellValue(''),
        TextCellValue(totales['invInicialCostoCant']!.toStringAsFixed(2)),
        TextCellValue(
            _convertirValor(totales['invInicialCostoImporte']!).toStringAsFixed(2)),
        TextCellValue(totales['invInicialVentaCant']!.toStringAsFixed(2)),
        TextCellValue(
            (_monedaSeleccionada == Moneda.cup
                    ? totales['invInicialVentaImporte']!
                    : totales['invInicialVentaImporte']! / _tasaConversion)
                .toStringAsFixed(2)),
        TextCellValue(totales['entradas']!.toStringAsFixed(2)),
        TextCellValue(totales['disponible']!.toStringAsFixed(2)),
        TextCellValue(totales['vendido']!.toStringAsFixed(2)),
        TextCellValue(totales['invFinalCant']!.toStringAsFixed(2)),
        TextCellValue(
            _convertirValor(totales['invFinalImporte']!).toStringAsFixed(2)),
        TextCellValue(
            (_monedaSeleccionada == Moneda.cup
                    ? totales['ventaPrecio']!
                    : totales['ventaPrecio']! / _tasaConversion)
                .toStringAsFixed(2)),
        TextCellValue(
            (_monedaSeleccionada == Moneda.cup
                    ? totales['ventaImporte']!
                    : totales['ventaImporte']! / _tasaConversion)
                .toStringAsFixed(2)),
        TextCellValue(
            _convertirValor(totales['costoUnitario']!).toStringAsFixed(2)),
        TextCellValue(
            _convertirValor(totales['costoTotal']!).toStringAsFixed(2)),
      ]);

      final encodedBytes = excel.encode();
      if (encodedBytes == null) throw Exception('Error al codificar Excel');
      final fileBytes = Uint8List.fromList(encodedBytes);

      const mimeType =
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

      if (kIsWeb) {
        // Descarga directa en web
        try {
          web_download.downloadFileWeb(fileBytes, fileName, mimeType);
        } catch (webError) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Problema de compatibilidad del navegador. Intenta con Edge o actualiza tu navegador.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
              ),
            );
          }
          return;
        }
      } else {
        // Compartir en APK
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(fileBytes);

        await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: 'Reporte IPV - ${_monedaSeleccionada.name.toUpperCase()}',
          text:
              'Reporte IPV generado el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        );
      }

      if (mounted) {
        final message = kIsWeb
            ? 'Excel descargado exitosamente'
            : 'Excel generado y compartido exitosamente';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar Excel: $e'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  pw.Widget _pdfDataCell(String text, {bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: 7,
        ),
        textAlign: pw.TextAlign.right,
      ),
    );
  }

}
