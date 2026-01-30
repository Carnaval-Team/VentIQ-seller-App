import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as excel;
import '../config/app_colors.dart';
import '../widgets/admin_drawer.dart';
import '../widgets/admin_bottom_navigation.dart';
import '../models/sales.dart';
import '../models/sales_analyst_models.dart';
import '../services/sales_service.dart';
import '../services/sales_analyst_controller.dart';
import '../services/subscription_service.dart';
import '../services/user_preferences_service.dart';

// Importación condicional para descargas en web
import '../services/web_download_stub.dart'
    if (dart.library.html) '../services/web_download_web.dart'
    as web_download;

class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;
  List<Sale> _sales = [];
  List<SalesVendorReport> _vendorReports = [];
  List<ProductSalesReport> _productSalesReports = [];
  bool _isLoading = true;
  bool _isLoadingProducts = true;
  bool _isLoadingVendors = true;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();
  DateTime? _pdfStartDate;
  DateTime? _pdfEndDate;
  bool _isGeneratingPdf = false;
  bool _isPdfFabExpanded = false;
  String _selectedTPV = 'Todos';
  double _totalSales = 0.0;
  int _totalProductsSold = 0;
  bool _isLoadingMetrics = false;
  List<ProductAnalysis> _productAnalysis = [];
  bool _isLoadingAnalysis = false;
  late final SalesAnalystController _analystController;
  final SubscriptionService _subscriptionService = SubscriptionService();
  final TextEditingController _analystQuestionController =
      TextEditingController();
  final ScrollController _analystScrollController = ScrollController();
  final FocusNode _analystFocusNode = FocusNode();
  final List<String> _analystSuggestions = [
    '¿Cuáles productos dejan más ganancia?',
    'Muéstrame las ventas por proveedor.',
    'Top 5 productos más vendidos del período.',
    '¿Cómo evolucionaron las ventas en el rango?',
  ];
  int _analystMessageCount = 0;
  bool _hasAdvancedPlan = false;
  bool _isLoadingAdvancedPlan = true;

  // Generación de PDF
  Future<void> _pickPdfDateRange(BuildContext context) async {
    final startBase = _pdfStartDate ?? _startDate;
    final endBase = _pdfEndDate ?? _endDate;
    final initialRange = DateTimeRange(
      start: startBase.isBefore(endBase) ? startBase : endBase,
      end: endBase.isAfter(startBase) ? endBase : startBase,
    );

    final DateTimeRange? range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: initialRange,
      helpText: 'Selecciona rango de fechas',
      saveText: 'Aplicar',
    );
    if (range == null) return;

    setState(() {
      _pdfStartDate = DateTime(
        range.start.year,
        range.start.month,
        range.start.day,
        0,
        0,
        0,
      );
      _pdfEndDate = DateTime(
        range.end.year,
        range.end.month,
        range.end.day,
        23,
        59,
        59,
      );
    });
  }

  double _calculateOrderCost(
    List<dynamic> items, {
    Map<int, double>? costById,
    Map<String, double>? costByName,
  }) {
    double totalCost = 0.0;
    for (final item in items) {
      final qty = _toDoubleSafe(item['cantidad']);
      final unitCost = _getItemUnitCost(
        item,
        costById: costById,
        costByName: costByName,
      );
      totalCost += qty * unitCost;
    }
    return totalCost;
  }

  double _getItemUnitCost(
    Map<String, dynamic> item, {
    Map<int, double>? costById,
    Map<String, double>? costByName,
  }) {
    final costo =
        item['precio_costo'] ??
        item['costo_unitario'] ??
        item['costo'] ??
        item['precio_costo_unitario'] ??
        0.0;
    final directCost = _toDoubleSafe(costo);
    if (directCost > 0) return directCost;

    final productId = _toIntSafe(
      item['id_producto'] ?? item['producto_id'] ?? item['id'],
    );
    if (productId != null) {
      final mappedCost = costById?[productId];
      if (mappedCost != null && mappedCost > 0) return mappedCost;
    }

    final rawName =
        item['producto_nombre'] ?? item['nombre'] ?? item['producto'] ?? '';
    final normalizedName = _normalizeProductName(rawName.toString());
    if (normalizedName.isNotEmpty) {
      final mappedCost = costByName?[normalizedName];
      if (mappedCost != null && mappedCost > 0) return mappedCost;
    }

    return directCost;
  }

  String _normalizeProductName(String name) {
    return name.trim().toLowerCase();
  }

  String _getAddonName(Map<String, dynamic> ad, String parentName) {
    final raw =
        (ad['nombre_ingrediente'] ??
                ad['nombre'] ??
                ad['descripcion'] ??
                ad['item'] ??
                '')
            .toString()
            .trim();
    if (raw.isEmpty) return 'Aditamento';
    if (raw.toLowerCase() == parentName.toLowerCase()) return 'Aditamento';
    return raw;
  }

  Widget _buildGeneratePdfFab() {
    if (_tabController.index == 4) {
      return const SizedBox.shrink();
    }
    // Un solo botón con opciones según el tab activo
    bool isLoading = false;
    bool isPdfAction = false;
    String label = 'Opciones';
    IconData icon = Icons.more_vert;
    Future<void> Function()? action;

    debugPrint(
      '🔍 FAB: Tab ${_tabController.index}, SupplierReports: ${_supplierReports.length}',
    );

    switch (_tabController.index) {
      case 0: // Tiempo Real
        isPdfAction = true;
        isLoading = _isGeneratingPdf;
        label = _isGeneratingPdf ? 'Generando...' : 'Exportar factura PDF';
        icon = Icons.picture_as_pdf_outlined;
        action =
            _isGeneratingPdf
                ? null
                : () async {
                  await _pickPdfDateRange(context);
                  if (_pdfStartDate != null && _pdfEndDate != null) {
                    await _generateInvoicesPdf(
                      start: _pdfStartDate!,
                      end: _pdfEndDate!,
                    );
                  }
                };
        break;

      case 1: // TPVs
        isPdfAction = true;
        isLoading = _isGeneratingPdf;
        label = _isGeneratingPdf ? 'Generando...' : 'Exportar factura PDF';
        icon = Icons.picture_as_pdf_outlined;
        action =
            _isGeneratingPdf
                ? null
                : () async {
                  await _pickPdfDateRange(context);
                  if (_pdfStartDate != null && _pdfEndDate != null) {
                    await _generateInvoicesPdf(
                      start: _pdfStartDate!,
                      end: _pdfEndDate!,
                    );
                  }
                };
        break;

      case 2: // Proveedores
        debugPrint(
          '🔍 FAB: En tab Proveedores, _supplierReports.isNotEmpty: ${_supplierReports.isNotEmpty}',
        );
        isLoading = _isExportingPDF;
        label = _isExportingPDF ? 'Exportando...' : 'Exportar Resumen';
        icon = Icons.download_outlined;
        action =
            _supplierReports.isNotEmpty && !_isExportingPDF
                ? () async => _showExportMenu()
                : null;
        break;

      case 3: // Análisis
        isPdfAction = true;
        isLoading = _isGeneratingPdf;
        label = _isGeneratingPdf ? 'Generando...' : 'Exportar factura PDF';
        icon = Icons.picture_as_pdf_outlined;
        action =
            _isGeneratingPdf
                ? null
                : () async {
                  await _pickPdfDateRange(context);
                  if (_pdfStartDate != null && _pdfEndDate != null) {
                    await _generateInvoicesPdf(
                      start: _pdfStartDate!,
                      end: _pdfEndDate!,
                    );
                  }
                };
        break;
    }

    VoidCallback? onPressed;
    if (action != null) {
      if (isPdfAction) {
        onPressed = () async {
          if (!_isPdfFabExpanded) {
            setState(() => _isPdfFabExpanded = true);
            return;
          }
          setState(() => _isPdfFabExpanded = false);
          await action!();
        };
      } else {
        onPressed = action;
      }
    }

    debugPrint(
      '🔍 FAB: onPressed=$onPressed, isLoading=$isLoading, label=$label',
    );

    final isDisabled = onPressed == null && !isLoading;
    final backgroundColor = isDisabled ? Colors.grey : AppColors.primary;
    final fabIcon =
        isLoading
            ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
            : Icon(icon);

    if (isPdfAction && !_isPdfFabExpanded) {
      return FloatingActionButton(
        backgroundColor: backgroundColor,
        foregroundColor: Colors.white,
        onPressed: onPressed,
        child: fabIcon,
      );
    }

    // Mostrar el botón siempre (deshabilitado si no hay acción)
    return FloatingActionButton.extended(
      backgroundColor: backgroundColor,
      foregroundColor: Colors.white,
      icon: fabIcon,
      label: Text(label),
      onPressed: onPressed,
    );
  }

  Future<void> _generateInvoicesPdf({
    required DateTime start,
    required DateTime end,
  }) async {
    setState(() => _isGeneratingPdf = true);

    try {
      final storeId = await UserPreferencesService().getIdTienda();
      Map<String, dynamic>? storeData;
      if (storeId != null) {
        storeData =
            await Supabase.instance.client
                .from('app_dat_tienda')
                .select('denominacion, direccion, ubicacion, phone, imagen_url')
                .eq('id', storeId)
                .maybeSingle();
      }

      final storeName = storeData?['denominacion'] as String? ?? 'VentIQ';
      final storeAddress = storeData?['direccion'] as String? ?? '';
      final storeLocation = storeData?['ubicacion'] as String? ?? '';
      final storePhone = storeData?['phone'] as String? ?? '';
      final storeLogoUrl = storeData?['imagen_url'] as String?;
      final logoBytes = await _downloadImageBytes(storeLogoUrl);

      final orders = await _fetchOrdersForPdf(start: start, end: end);
      final productReports = await SalesService.getProductSalesReport(
        fechaDesde: start,
        fechaHasta: end,
      );
      final productAnalysis = await SalesService.getProductAnalysis(
        fechaDesde: start,
        fechaHasta: end,
      );

      final Map<int, double> costById = {};
      final Map<String, double> costByName = {};

      void addCostEntry({
        required int? productId,
        required String? productName,
        required double costCup,
      }) {
        if (costCup <= 0) return;
        if (productId != null && productId > 0) {
          costById[productId] = costCup;
        }
        final normalizedName = _normalizeProductName(
          productName?.toString() ?? '',
        );
        if (normalizedName.isNotEmpty) {
          costByName[normalizedName] = costCup;
        }
      }

      double resolveReportCost(ProductSalesReport report) {
        if (report.precioCostoCup > 0) return report.precioCostoCup;
        if (report.precioCosto > 0 && report.valorUsd > 0) {
          return report.precioCosto * report.valorUsd;
        }
        return report.precioCosto;
      }

      double resolveAnalysisCost(ProductAnalysis analysis) {
        if (analysis.precioCostoCup > 0) return analysis.precioCostoCup;
        if (analysis.precioCosto > 0 && analysis.valorUsd > 0) {
          return analysis.precioCosto * analysis.valorUsd;
        }
        return analysis.precioCosto;
      }

      for (final analysis in productAnalysis) {
        addCostEntry(
          productId: analysis.idProducto,
          productName: analysis.nombreProducto,
          costCup: resolveAnalysisCost(analysis),
        );
      }

      for (final report in productReports) {
        addCostEntry(
          productId: report.idProducto,
          productName: report.nombreProducto,
          costCup: resolveReportCost(report),
        );
      }

      double ventaTotal = 0.0;
      double descuentoTotal = 0.0;
      double pagoTotal = 0.0;

      for (final order in orders) {
        final summary = _calculateDiscountSummary(order);
        ventaTotal += summary['cobrado'] ?? 0.0;
        descuentoTotal += summary['descuento'] ?? 0.0;

        final pagos = (order.detalles['pagos'] as List?) ?? [];
        for (final pago in pagos) {
          pagoTotal += _toDoubleSafe(pago['total']);
        }
      }

      final costoTotal = productReports.fold<double>(
        0.0,
        (sum, p) => sum + p.costoTotalVendido,
      );
      final gananciaTotal = productReports.fold<double>(
        0.0,
        (sum, p) => sum + p.gananciaTotal,
      );
      final gananciasReales = (ventaTotal - descuentoTotal) - costoTotal;

      final pdf = pw.Document();
      final dateLabel =
          '${_formatDateForPdf(start)} - ${_formatDateForPdf(end)}';

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          build:
              (context) => [
                _buildPdfHeader(
                  logoBytes: logoBytes,
                  storeName: storeName,
                  storeAddress: storeAddress,
                  storeLocation: storeLocation,
                  storePhone: storePhone,
                  dateLabel: dateLabel,
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Facturas',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 8),
                ...orders.map(
                  (order) => pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 12),
                    padding: const pw.EdgeInsets.all(12),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromHex('#F8FAFC'),
                      borderRadius: pw.BorderRadius.circular(10),
                      border: pw.Border.all(
                        color: PdfColors.grey300,
                        width: 0.8,
                      ),
                    ),
                    child: _buildOrderPdfSection(
                      order,
                      costById: costById,
                      costByName: costByName,
                    ),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Costos y Ganancias (por producto)',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 6),
                _buildProductCostsTable(productReports),
                pw.SizedBox(height: 16),
                _buildPdfSummaryTotals(
                  ventaTotal: ventaTotal,
                  descuentoTotal: descuentoTotal,
                  costoTotal: costoTotal,
                  gananciaTotal: gananciaTotal,
                  gananciasReales: gananciasReales,
                  pagoTotal: pagoTotal,
                ),
              ],
        ),
      );

      final pdfBytes = await pdf.save();
      final fileName =
          'reporte_facturas_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: pdfBytes, filename: fileName);
      } else {
        final output = await getTemporaryDirectory();
        final file = File('${output.path}/$fileName');
        await file.writeAsBytes(pdfBytes);

        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/pdf'),
        ], text: 'Reporte de facturas $dateLabel');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar PDF: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingPdf = false);
      }
    }
  }

  Future<List<VendorOrder>> _fetchOrdersForPdf({
    required DateTime start,
    required DateTime end,
  }) async {
    try {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) return [];

      debugPrint(
        '[PDF] Preparando listar_ordenes | tienda=$storeId | '
        'desde=${start.toIso8601String()} | hasta=${end.toIso8601String()}',
      );

      // obtener lista de vendedores/TPVs (uuid_usuario) como en la vista de órdenes
      final vendorReports = await SalesService.getSalesVendorReport(
        fechaDesde: start,
        fechaHasta: end,
      );
      final vendorUuids = vendorReports.map((v) => v.uuidUsuario).toSet();

      debugPrint('[PDF] UUIDs de vendedores/TPVs: $vendorUuids');

      final List<VendorOrder> orders = [];
      final Set<int> uniqueOrderIds = {};

      Future<void> fetchForUser(String? uuidUsuario) async {
        final response = await Supabase.instance.client.rpc(
          'listar_ordenes',
          params: {
            'con_inventario_param': false,
            'fecha_desde_param': start.toIso8601String().split('T')[0],
            'fecha_hasta_param': end.toIso8601String().split('T')[0],
            'id_estado_param': null,
            'id_tienda_param': storeId,
            'id_tipo_operacion_param': null,
            'id_tpv_param': null,
            'id_usuario_param': uuidUsuario,
            'limite_param': null,
            'pagina_param': null,
            'solo_pendientes_param': false,
          },
        );

        final label = uuidUsuario ?? 'ALL';
        if (response == null) {
          debugPrint('[PDF] listar_ordenes user=$label -> respuesta null');
          return;
        }
        debugPrint(
          '[PDF] listar_ordenes user=$label -> ${response.length} registros',
        );

        for (final item in response) {
          try {
            final order = VendorOrder.fromJson(item);
            final tipoOperacion = item['tipo_operacion']?.toString() ?? '';
            if (tipoOperacion.toLowerCase().contains('venta')) {
              if (uniqueOrderIds.add(order.idOperacion)) {
                orders.add(order);
              }
              debugPrint(
                '[PDF] user=$label Orden #${order.idOperacion} tipo=$tipoOperacion total=${order.totalOperacion} items=${order.cantidadItems}',
              );
            }
          } catch (e) {
            debugPrint('[PDF] Error parseando orden user=$label: $e');
          }
        }
      }

      if (vendorUuids.isNotEmpty) {
        for (final uuid in vendorUuids) {
          await fetchForUser(uuid);
        }
      } else {
        // fallback sin filtro de usuario
        await fetchForUser(null);
      }

      debugPrint('[PDF] Órdenes Venta después de filtrar: ${orders.length}');
      return orders;
    } catch (e) {
      debugPrint('Error fetching orders for PDF: $e');
      return [];
    }
  }

  Future<Uint8List?> _downloadImageBytes(String? url) async {
    if (url == null || url.isEmpty) return null;

    const objectPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/object/public/images_back/';
    const renderPrefix =
        'https://vsieeihstajlrdvpuooh.supabase.co/storage/v1/render/image/public/images_back/';

    // Construir URL de render con dimensiones fijas para supabase
    final renderUrl =
        url.contains(objectPrefix)
            ? '${url.replaceFirst(objectPrefix, renderPrefix)}?width=500&height=600'
            : url;

    try {
      final response = await http.get(Uri.parse(renderUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
      return null;
    } catch (e) {
      print('⚠️ No se pudo descargar imagen de tienda: $e');
      return null;
    }
  }

  pw.Widget _buildPdfHeader({
    required Uint8List? logoBytes,
    required String storeName,
    required String storeAddress,
    required String storeLocation,
    required String storePhone,
    required String dateLabel,
  }) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (logoBytes != null)
          pw.Container(
            width: 64,
            height: 64,
            decoration: pw.BoxDecoration(
              borderRadius: pw.BorderRadius.circular(12),
              border: pw.Border.all(color: PdfColors.grey300, width: 1),
            ),
            child: pw.ClipRRect(
              horizontalRadius: 12,
              verticalRadius: 12,
              child: pw.Image(pw.MemoryImage(logoBytes), fit: pw.BoxFit.cover),
            ),
          ),
        if (logoBytes != null) pw.SizedBox(width: 12),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                storeName,
                style: pw.TextStyle(
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromHex('#0F172A'),
                ),
              ),
              if (storeAddress.isNotEmpty || storeLocation.isNotEmpty)
                pw.Text(
                  [
                    if (storeAddress.isNotEmpty) storeAddress,
                    if (storeLocation.isNotEmpty) storeLocation,
                  ].join(' · '),
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#475569'),
                  ),
                ),
              if (storePhone.isNotEmpty)
                pw.Text(
                  'Tel: $storePhone',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColor.fromHex('#475569'),
                  ),
                ),
            ],
          ),
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Reporte de Facturas',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#0F172A'),
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              dateLabel,
              style: pw.TextStyle(
                fontSize: 11,
                color: PdfColor.fromHex('#475569'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildOrderPdfSection(
    VendorOrder order, {
    Map<int, double>? costById,
    Map<String, double>? costByName,
  }) {
    final summary = _calculateDiscountSummary(order);
    final double original = summary['original'] ?? order.totalOperacion;
    final double cobrado = summary['cobrado'] ?? order.totalOperacion;
    final double descuento = summary['descuento'] ?? 0.0;

    final cliente = order.detalles['cliente'] as Map<String, dynamic>?;
    final clienteNombre =
        cliente != null ? (cliente['nombre_completo'] ?? 'Cliente') : 'Cliente';
    final pagos = (order.detalles['pagos'] as List?) ?? [];

    final items = (order.detalles['items'] as List?) ?? [];

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Orden #${order.idOperacion}',
              style: pw.TextStyle(
                fontSize: 12,
                fontWeight: pw.FontWeight.bold,
                color: PdfColor.fromHex('#0F172A'),
              ),
            ),
            pw.Text(
              _formatDateTime(order.fechaOperacion),
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColor.fromHex('#475569'),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Cliente: $clienteNombre',
          style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#334155')),
        ),
        pw.SizedBox(height: 8),
        _buildItemsTable(items, costById: costById, costByName: costByName),
        pw.SizedBox(height: 8),
        _buildPaymentsTable(pagos),
        pw.SizedBox(height: 6),
        _buildOrderTotals(
          original: original,
          descuento: descuento,
          total: cobrado,
          costo: _calculateOrderCost(
            items,
            costById: costById,
            costByName: costByName,
          ),
        ),
      ],
    );
  }

  pw.Widget _buildItemsTable(
    List<dynamic> items, {
    Map<int, double>? costById,
    Map<String, double>? costByName,
  }) {
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1),
        2: const pw.FlexColumnWidth(1.2),
        3: const pw.FlexColumnWidth(1.1),
        4: const pw.FlexColumnWidth(1.2),
        5: const pw.FlexColumnWidth(1.3),
        6: const pw.FlexColumnWidth(1.3),
      },
      children: [
        pw.TableRow(
          children: [
            _pdfHeaderCell('Producto'),
            _pdfHeaderCell('Cant.'),
            _pdfHeaderCell('Precio'),
            _pdfHeaderCell('Costo'),
            _pdfHeaderCell('Costo total'),
            _pdfHeaderCell('Subtotal'),
            _pdfHeaderCell('Ganancia'),
          ],
        ),
        ...items
            .map((item) {
              final nombre = item['producto_nombre']?.toString() ?? 'Producto';
              final cantidad = _toDoubleSafe(
                item['cantidad'],
              ).toStringAsFixed(0);
              final precio = _toDoubleSafe(
                item['precio_unitario'],
              ).toStringAsFixed(2);
              final costoUnitario = _getItemUnitCost(
                item,
                costById: costById,
                costByName: costByName,
              );
              final costoTotal = (costoUnitario *
                      _toDoubleSafe(item['cantidad']))
                  .toStringAsFixed(2);
              final subtotal = _toDoubleSafe(
                item['importe'],
              ).toStringAsFixed(2);
              final gananciaValue =
                  _toDoubleSafe(item['importe']) -
                  (costoUnitario * _toDoubleSafe(item['cantidad']));
              final ganancia = gananciaValue.toStringAsFixed(2);
              final gananciaColor =
                  gananciaValue < 0
                      ? PdfColor.fromHex('#DC2626')
                      : gananciaValue > 0
                      ? PdfColor.fromHex('#15803D')
                      : PdfColor.fromHex('#334155');

              final aditamentos =
                  (item['aditamentos'] as List?) ??
                  (item['ingredientes'] as List?);

              final rows = <pw.TableRow>[
                pw.TableRow(
                  children: [
                    _pdfBodyCell(nombre),
                    _pdfBodyCell(cantidad),
                    _pdfBodyCell('\$$precio'),
                    _pdfBodyCell('\$${costoUnitario.toStringAsFixed(2)}'),
                    _pdfBodyCell('\$$costoTotal'),
                    _pdfBodyCell('\$$subtotal'),
                    _pdfBodyCell(
                      '\$$ganancia',
                      isBold: true,
                      color: gananciaColor,
                    ),
                  ],
                ),
              ];

              if (aditamentos != null && aditamentos.isNotEmpty) {
                rows.add(
                  pw.TableRow(
                    children: [
                      _pdfBodyCell(
                        '   Aditamentos',
                        isBold: true,
                        isIngredient: true,
                      ),
                      _pdfBodyCell('', isIngredient: true),
                      _pdfBodyCell('', isIngredient: true),
                      _pdfBodyCell('', isIngredient: true),
                      _pdfBodyCell('', isIngredient: true),
                      _pdfBodyCell('', isIngredient: true),
                      _pdfBodyCell('', isIngredient: true),
                    ],
                  ),
                );
                rows.addAll(
                  aditamentos.map<pw.TableRow>((ad) {
                    final nombreAd = _getAddonName(ad, nombre);
                    final cantidadAd = _toDoubleSafe(
                      ad['cantidad'] ??
                          ad['cantidad_vendida'] ??
                          ad['cantidad_necesaria'],
                    ).toStringAsFixed(2);
                    final unidad = (ad['unidad_medida'] ?? '').toString();
                    return pw.TableRow(
                      children: [
                        _pdfBodyCell('   $nombreAd', isIngredient: true),
                        _pdfBodyCell(
                          unidad.isNotEmpty
                              ? '$cantidadAd $unidad'
                              : cantidadAd,
                          isIngredient: true,
                        ),
                        _pdfBodyCell('', isIngredient: true),
                        _pdfBodyCell('', isIngredient: true),
                        _pdfBodyCell('', isIngredient: true),
                        _pdfBodyCell('', isIngredient: true),
                        _pdfBodyCell('', isIngredient: true),
                      ],
                    );
                  }),
                );
              }

              return rows;
            })
            .expand((e) => e),
      ],
    );
  }

  pw.Widget _buildPaymentsTable(List<dynamic> pagos) {
    if (pagos.isEmpty) return pw.SizedBox.shrink();
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Pagos',
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: PdfColor.fromHex('#0F172A'),
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder(
            horizontalInside: pw.BorderSide(
              color: PdfColors.grey300,
              width: 0.3,
            ),
            bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(
              children: [_pdfHeaderCell('Medio'), _pdfHeaderCell('Monto')],
            ),
            ...pagos.map((p) {
              final medio = p['medio_pago']?.toString() ?? 'N/A';
              final total = _toDoubleSafe(p['total']).toStringAsFixed(2);
              return pw.TableRow(
                children: [
                  _pdfBodyCell(medio),
                  _pdfBodyCell('\$$total', isBold: true),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  pw.Widget _buildOrderTotals({
    required double original,
    required double descuento,
    required double total,
    required double costo,
  }) {
    final ganancia = total - costo;
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#EEF2FF'),
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: PdfColor.fromHex('#CBD5E1'), width: 0.8),
      ),
      child: pw.Column(
        children: [
          _pdfSummaryRow('Subtotal', original),
          if (descuento > 0) _pdfSummaryRow('Descuento', -descuento),
          _pdfSummaryRow('Costo', -costo),
          pw.Divider(height: 8, color: PdfColors.grey500, thickness: 0.5),
          _pdfSummaryRow('Total', total, isBold: true, fontSize: 12),
          _pdfSummaryRow(
            'Ganancia orden',
            ganancia,
            isBold: true,
            positiveColor: PdfColor.fromHex('#15803D'),
            negativeColor: PdfColor.fromHex('#DC2626'),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildProductCostsTable(List<ProductSalesReport> reports) {
    if (reports.isEmpty) {
      return pw.Text(
        'No hay datos de productos en el rango seleccionado.',
        style: pw.TextStyle(fontSize: 10, color: PdfColor.fromHex('#6B7280')),
      );
    }
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.3),
        bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
      columnWidths: {
        0: const pw.FlexColumnWidth(4),
        1: const pw.FlexColumnWidth(1.5),
        2: const pw.FlexColumnWidth(1.5),
        3: const pw.FlexColumnWidth(1.5),
      },
      children: [
        pw.TableRow(
          children: [
            _pdfHeaderCell('Producto'),
            _pdfHeaderCell('Precio'),
            _pdfHeaderCell('Costo'),
            _pdfHeaderCell('Ganancia'),
          ],
        ),
        ...reports.map((p) {
          final gananciaColor =
              p.gananciaUnitaria < 0
                  ? PdfColor.fromHex('#DC2626')
                  : p.gananciaUnitaria > 0
                  ? PdfColor.fromHex('#15803D')
                  : PdfColor.fromHex('#334155');
          return pw.TableRow(
            children: [
              _pdfBodyCell(p.nombreProducto),
              _pdfBodyCell('\$${p.precioVentaCup.toStringAsFixed(2)}'),
              _pdfBodyCell('\$${p.precioCostoCup.toStringAsFixed(2)}'),
              _pdfBodyCell(
                '\$${p.gananciaUnitaria.toStringAsFixed(2)}',
                color: gananciaColor,
              ),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _buildPdfSummaryTotals({
    required double ventaTotal,
    required double descuentoTotal,
    required double costoTotal,
    required double gananciaTotal,
    required double gananciasReales,
    required double pagoTotal,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#F1F5F9'),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColors.grey300, width: 1),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Resumen',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              color: PdfColor.fromHex('#0F172A'),
            ),
          ),
          pw.SizedBox(height: 8),
          _pdfSummaryRow('Venta total', ventaTotal),
          _pdfSummaryRow('Descuento total', -descuentoTotal),
          _pdfSummaryRow('Costo total', -costoTotal),
          _pdfSummaryRow(
            'Ganancia total',
            gananciaTotal,
            positiveColor: PdfColor.fromHex('#15803D'),
            negativeColor: PdfColor.fromHex('#DC2626'),
          ),
          _pdfSummaryRow(
            'Ganancias reales',
            gananciasReales,
            isBold: true,
            positiveColor: PdfColor.fromHex('#15803D'),
            negativeColor: PdfColor.fromHex('#DC2626'),
          ),
          _pdfSummaryRow('Pago total (pagos)', pagoTotal),
        ],
      ),
    );
  }

  pw.Widget _pdfHeaderCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColor.fromHex('#1F2937'),
        ),
      ),
    );
  }

  pw.Widget _pdfBodyCell(
    String text, {
    bool isBold = false,
    bool isIngredient = false,
    PdfColor? color,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isIngredient ? 9 : 10,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          color:
              color ??
              (isIngredient
                  ? PdfColor.fromHex('#6B7280')
                  : PdfColor.fromHex('#334155')),
        ),
      ),
    );
  }

  pw.Widget _pdfSummaryRow(
    String label,
    double value, {
    bool isBold = false,
    double fontSize = 11,
    PdfColor? positiveColor,
    PdfColor? negativeColor,
  }) {
    final isNegative = value < 0;
    final display =
        isNegative
            ? '- \$${value.abs().toStringAsFixed(2)}'
            : '\$${value.toStringAsFixed(2)}';
    final defaultPositive = PdfColor.fromHex('#0F172A');
    final defaultNegative = PdfColor.fromHex('#DC2626');
    final valueColor =
        isNegative
            ? (negativeColor ?? defaultNegative)
            : (positiveColor ?? defaultPositive);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: PdfColor.fromHex('#475569'),
          ),
        ),
        pw.Text(
          display,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  String _formatDateForPdf(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  List<SupplierSalesReport> _supplierReports = [];
  bool _isLoadingSuppliers = false;
  bool _isExportingPDF = false;

  // Filtro por almacén
  int? _selectedWarehouseId;
  String? _selectedWarehouseName;
  List<Map<String, dynamic>> _warehouses = [];
  bool _isLoadingWarehouses = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    _tabController.addListener(_onTabChanged);
    _analystController = SalesAnalystController();
    _analystController.addListener(_handleAnalystUpdates);
    _analystMessageCount = _analystController.messages.length;
    _loadAdvancedPlanStatus();
    _initializeDateRange();
    _loadWarehouses();
    _loadSalesData();
  }

  void _initializeDateRange() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day, 0, 0, 0);
    _endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging || !_tabController.indexIsChanging) {
      // Forzar reconstrucción del FAB cuando cambias de tab
      setState(() {
        _isPdfFabExpanded = false;
      });

      switch (_tabController.index) {
        case 2: // Suppliers
          _loadSupplierReports();
          break;
        case 3: // Analysis
          _loadProductAnalysis();
          break;
        case 4: // Analyst
          if (_hasAdvancedPlan) {
            if (!_isLoadingAnalysis && _productAnalysis.isEmpty) {
              _loadProductAnalysis();
            }
            if (!_isLoadingSuppliers && _supplierReports.isEmpty) {
              _loadSupplierReports();
            }
          }
          break;
      }
    }
  }

  void _handleAnalystUpdates() {
    if (!mounted) return;
    final messageCount = _analystController.messages.length;
    if (messageCount != _analystMessageCount) {
      _analystMessageCount = messageCount;
      _scrollAnalystToBottom();
    }
  }

  void _scrollAnalystToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_analystScrollController.hasClients) return;
      final target = _analystScrollController.position.maxScrollExtent + 120;
      _analystScrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _analystController.removeListener(_handleAnalystUpdates);
    _analystController.dispose();
    _analystQuestionController.dispose();
    _analystScrollController.dispose();
    _analystFocusNode.dispose();
    super.dispose();
  }

  void _loadSalesData() {
    setState(() => _isLoading = true);
    _loadProductSalesData();
    _loadVendorReports();
    _loadAdvancedPlanStatus();
    // El análisis de productos se carga solo cuando se selecciona el tab de análisis
  }

  Future<void> _loadAdvancedPlanStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingAdvancedPlan = true);
    try {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) {
        if (mounted) {
          setState(() {
            _hasAdvancedPlan = false;
            _isLoadingAdvancedPlan = false;
          });
        }
        return;
      }

      final hasPlan = await _subscriptionService.hasAdvancedPlan(storeId);
      if (mounted) {
        setState(() {
          _hasAdvancedPlan = hasPlan;
          _isLoadingAdvancedPlan = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasAdvancedPlan = false;
          _isLoadingAdvancedPlan = false;
        });
      }
      debugPrint('❌ Error verificando plan avanzado: $e');
    }
  }

  void _loadProductSalesData() async {
    setState(() {
      _isLoadingProducts = true;
      _isLoadingMetrics = true;
    });

    try {
      // Use the selected date range
      final dateRange = {'start': _startDate, 'end': _endDate};

      // Load product sales data
      final productSales = await SalesService.getProductSalesReport(
        fechaDesde: dateRange['start'],
        fechaHasta: dateRange['end'],
      );

      setState(() {
        _productSalesReports = productSales;
        // Calculate total sales from product sales reports
        _totalSales = productSales.fold<double>(
          0.0,
          (sum, report) => sum + report.ingresosTotales,
        );
        // Calculate total products sold from product sales reports
        _totalProductsSold = productSales.fold<int>(
          0,
          (sum, report) => sum + report.totalVendido.toInt(),
        );
        _isLoadingProducts = false;
        _isLoadingMetrics = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingProducts = false;
        _isLoadingMetrics = false;
      });
      print('Error loading sales data: $e');
    }
  }

  void _loadVendorReports() async {
    setState(() {
      _isLoadingVendors = true;
    });

    try {
      final reports = await SalesService.getSalesVendorReport(
        fechaDesde: _startDate,
        fechaHasta: _endDate,
      );

      // Load egresos for each vendor
      final List<SalesVendorReport> reportsWithEgresos = [];
      for (final report in reports) {
        final totalEgresos = await SalesService.getTotalEgresosByVendor(
          fechaInicio: _startDate,
          fechaFin: _endDate,
          uuidUsuario: report.uuidUsuario,
        );

        final updatedReport = report.copyWith(totalEgresos: totalEgresos);
        reportsWithEgresos.add(updatedReport);
      }

      // Filtrar vendedores que tengan ventas reales (productos > 0 o dinero > 0)
      final filteredReports =
          reportsWithEgresos
              .where(
                (report) =>
                    report.totalProductosVendidos > 0 ||
                    report.totalDineroGeneral > 0,
              )
              .toList();

      setState(() {
        _vendorReports = filteredReports;
        _isLoadingVendors = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingVendors = false;
      });
      print('Error loading vendor reports: $e');
    }
  }

  void _loadProductAnalysis() async {
    setState(() {
      _isLoadingAnalysis = true;
    });

    try {
      final analysis = await SalesService.getProductAnalysis(
        fechaDesde: _startDate,
        fechaHasta: _endDate,
      );

      setState(() {
        _productAnalysis = analysis;
        _isLoadingAnalysis = false;
      });
    } catch (e) {
      setState(() => _isLoadingAnalysis = false);
      print('Error loading analysis: $e');
    }
  }

  Future<void> _loadWarehouses() async {
    if (!mounted) return;
    setState(() => _isLoadingWarehouses = true);
    try {
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) return;

      final response = await Supabase.instance.client
          .from('app_dat_almacen')
          .select('id, denominacion')
          .eq('id_tienda', idTienda)
          .order('denominacion');

      if (mounted) {
        setState(() {
          _warehouses = List<Map<String, dynamic>>.from(response);
          _isLoadingWarehouses = false;
        });
      }
    } catch (e) {
      print('Error loading warehouses: $e');
      if (mounted) {
        setState(() => _isLoadingWarehouses = false);
      }
    }
  }

  Future<void> _loadSupplierReports() async {
    if (!mounted) return;
    setState(() => _isLoadingSuppliers = true);
    try {
      final detailedSales = await SalesService.getProductSalesWithSupplier(
        fechaDesde: _startDate,
        fechaHasta: _endDate,
        idAlmacen: _selectedWarehouseId,
      );

      // Agrupación local por proveedor
      final Map<int, SupplierSalesReport> groupedReports = {};

      for (var sale in detailedSales) {
        if (groupedReports.containsKey(sale.idProveedor)) {
          final current = groupedReports[sale.idProveedor]!;
          groupedReports[sale.idProveedor] = SupplierSalesReport(
            idProveedor: current.idProveedor,
            nombreProveedor: current.nombreProveedor,
            totalVentas: current.totalVentas + sale.ingresosTotales,
            totalCosto: current.totalCosto + sale.costoTotalVendido,
            totalGanancia: current.totalGanancia + sale.gananciaTotal,
            cantidadProductos: current.cantidadProductos + sale.totalVendido,
            margenPorcentaje: 0,
          );
        } else {
          groupedReports[sale.idProveedor] = SupplierSalesReport(
            idProveedor: sale.idProveedor,
            nombreProveedor: sale.nombreProveedor,
            totalVentas: sale.ingresosTotales,
            totalCosto: sale.costoTotalVendido,
            totalGanancia: sale.gananciaTotal,
            cantidadProductos: sale.totalVendido,
            margenPorcentaje: 0,
          );
        }
      }

      // Calcular márgenes finales y convertir a lista
      final List<SupplierSalesReport> reports =
          groupedReports.values.map((item) {
            double margen = 0;
            if (item.totalVentas > 0) {
              margen = (item.totalGanancia / item.totalVentas) * 100;
            }
            return SupplierSalesReport(
              idProveedor: item.idProveedor,
              nombreProveedor: item.nombreProveedor,
              totalVentas: item.totalVentas,
              totalCosto: item.totalCosto,
              totalGanancia: item.totalGanancia,
              cantidadProductos: item.cantidadProductos,
              margenPorcentaje: margen,
            );
          }).toList();

      // Ordenar por total ventas descendente
      reports.sort((a, b) => b.totalVentas.compareTo(a.totalVentas));

      if (mounted) {
        setState(() {
          _supplierReports = reports;
          _isLoadingSuppliers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingSuppliers = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cargar reporte de proveedores: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Monitoreo de Ventas',
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
            onPressed: _loadSalesData,
            tooltip: 'Actualizar',
          ),
          Builder(
            builder:
                (context) => IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  onPressed: () => Scaffold.of(context).openEndDrawer(),
                  tooltip: 'Menú',
                ),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            const Tab(
              text: 'Tiempo Real',
              icon: Icon(Icons.timeline, size: 18),
            ),
            const Tab(text: 'TPVs', icon: Icon(Icons.point_of_sale, size: 18)),
            const Tab(
              text: 'Proveedores',
              icon: Icon(Icons.inventory, size: 18),
            ),
            const Tab(text: 'Análisis', icon: Icon(Icons.analytics, size: 18)),
            Tab(
              text: _hasAdvancedPlan ? 'Analista' : 'Analista (Avanzado)',
              icon:
                  _isLoadingAdvancedPlan
                      ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Icon(
                        _hasAdvancedPlan ? Icons.smart_toy : Icons.lock,
                        size: 18,
                      ),
            ),
          ],
        ),
      ),
      body:
          (_isLoadingProducts || _isLoadingVendors)
              ? _buildLoadingState()
              : TabBarView(
                controller: _tabController,
                children: [
                  _buildRealTimeTab(),
                  _buildTPVsTab(),
                  _buildSuppliersTab(),
                  _buildAnalyticsTab(),
                  _buildAnalystGateTab(),
                ],
              ),
      floatingActionButton: _buildGeneratePdfFab(),
      endDrawer: const AdminDrawer(),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: 1,
        onTap: _onBottomNavTap,
      ),
    );
  }

  Widget _buildLoadingState() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  Widget _buildRealTimeTab() {
    final todaySales =
        _sales
            .where((sale) => sale.saleDate.day == DateTime.now().day)
            .toList();
    final totalToday = todaySales.fold(0.0, (sum, sale) => sum + sale.total);
    final salesCount = todaySales.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          _buildRealTimeMetrics(_totalSales, _totalProductsSold),
          const SizedBox(height: 20),
          _buildProductSalesReport(),
        ],
      ),
    );
  }

  Widget _buildTPVsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ✅ GESTIÓN DE TPVs
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  'Gestión de TPVs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () =>
                                Navigator.pushNamed(context, '/tpv-management'),
                        icon: Icon(Icons.devices),
                        label: Text('TPVs y Vendedores'),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () => Navigator.pushNamed(context, '/tpv-prices'),
                        icon: Icon(Icons.attach_money),
                        label: Text('Precios TPV'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(height: 16),

          _buildPeriodSelector(),
          const SizedBox(height: 16),
          if (_isLoadingVendors)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_vendorReports.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No hay datos de vendedores para el período seleccionado',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _vendorReports.length,
              itemBuilder:
                  (context, index) => _buildVendorCard(_vendorReports[index]),
            ),
        ],
      ),
    );
  }

  Widget _buildWarehouseFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warehouse, color: AppColors.primary),
              const SizedBox(width: 12),
              const Text(
                'Almacén: ',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              Expanded(
                child:
                    _isLoadingWarehouses
                        ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                        : DropdownButton<int?>(
                          isExpanded: true,
                          value: _selectedWarehouseId,
                          underline: const SizedBox(),
                          items: [
                            DropdownMenuItem<int?>(
                              value: null,
                              child: const Text('Todos los almacenes'),
                            ),
                            ..._warehouses.map((warehouse) {
                              return DropdownMenuItem<int?>(
                                value: warehouse['id'] as int?,
                                child: Text(
                                  warehouse['denominacion'] as String? ??
                                      'Sin nombre',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _selectedWarehouseId = value;
                              _selectedWarehouseName =
                                  value != null
                                      ? _warehouses.firstWhere(
                                        (w) => w['id'] == value,
                                        orElse:
                                            () => {
                                              'denominacion': 'Desconocido',
                                            },
                                      )['denominacion']
                                      : null;
                            });
                            _loadSupplierReports();
                          },
                        ),
              ),
            ],
          ),
          if (_selectedWarehouseId != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Filtrado por: $_selectedWarehouseName',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuppliersTab() {
    // Calcular totales generales
    double totalVentas = 0;
    double totalCosto = 0;
    double totalGanancia = 0;

    for (var report in _supplierReports) {
      totalVentas += report.totalVentas;
      totalCosto += report.totalCosto;
      totalGanancia += report.totalGanancia;
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 12),
          _buildWarehouseFilter(),
          const SizedBox(height: 16),

          // Resumen General Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: _buildSummaryColumn(
                    'Ventas Totales',
                    totalVentas,
                    AppColors.success,
                  ),
                ),
                Expanded(
                  child: _buildSummaryColumn(
                    'Costo Total',
                    totalCosto,
                    AppColors.warning,
                  ),
                ),
                Expanded(
                  child: _buildSummaryColumn(
                    'Ganancia Total',
                    totalGanancia,
                    AppColors.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          _isLoadingSuppliers
              ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              )
              : _supplierReports.isEmpty
              ? const Padding(
                padding: EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No hay datos de proveedores para el período',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ),
              )
              : Card(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: const [
                      DataColumn(
                        label: Text(
                          'Proveedor',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Ventas',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Costo',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Ganancia',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'Acciones',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: [
                      ..._supplierReports.map((report) {
                        return DataRow(
                          cells: [
                            DataCell(Text(report.nombreProveedor)),
                            DataCell(
                              Text(
                                '\$${report.totalVentas.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.success,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                '\$${report.totalCosto.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.warning,
                                ),
                              ),
                            ),
                            DataCell(
                              Text(
                                '\$${report.totalGanancia.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            DataCell(
                              ElevatedButton.icon(
                                onPressed:
                                    () => _showSupplierDetailDialog(report),
                                icon: const Icon(Icons.info_outline, size: 16),
                                label: const Text('Detalles'),
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                      // Fila de TOTALES
                      DataRow(
                        color: MaterialStateProperty.all(Colors.grey.shade100),
                        cells: [
                          const DataCell(
                            Text(
                              'TOTAL',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${totalVentas.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.success,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${totalCosto.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.warning,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${totalGanancia.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const DataCell(Text('')),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPeriodSelector(),
          const SizedBox(height: 16),
          _buildProductAnalysisTable(),
        ],
      ),
    );
  }

  Widget _buildAnalystTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: _buildAnalystHeader(),
        ),
        Expanded(
          child: AnimatedBuilder(
            animation: _analystController,
            builder: (context, _) {
              return _buildAnalystConversation(
                context,
                _analystController.messages,
                _analystController.isLoading,
              );
            },
          ),
        ),
        _buildAnalystComposer(),
      ],
    );
  }

  Widget _buildAnalystGateTab() {
    if (_isLoadingAdvancedPlan) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (_hasAdvancedPlan) {
      return _buildAnalystTab();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Analista IA disponible solo en Plan Avanzado',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Desbloquea recomendaciones, insights y proyecciones inteligentes con tu información de ventas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: const [
                    _AnalystFeatureChip(
                      icon: Icons.lightbulb_outline,
                      label: 'Insights rápidos',
                    ),
                    _AnalystFeatureChip(
                      icon: Icons.trending_up,
                      label: 'Tendencias',
                    ),
                    _AnalystFeatureChip(
                      icon: Icons.table_chart_outlined,
                      label: 'Tablas claras',
                    ),
                    _AnalystFeatureChip(
                      icon: Icons.auto_graph,
                      label: 'Gráficas dinámicas',
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/subscription-detail');
                    },
                    icon: const Icon(Icons.workspace_premium),
                    label: const Text('Ver Plan Avanzado'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalystHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.smart_toy, color: Colors.white, size: 22),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Analista IA de Ventas',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _resetAnalystConversation,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 16),
                label: const Text(
                  'Nuevo chat',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Pregunta sobre ventas, proveedores, TPVs o tendencias. La IA usa tus datos actuales para responder.',
            style: TextStyle(color: Colors.white70, height: 1.3, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildAnalystInfoChip(Icons.date_range, _formatDateRangeLabel()),
              _buildAnalystInfoChip(
                Icons.attach_money,
                _formatCurrency(_totalSales),
              ),
              _buildAnalystInfoChip(
                Icons.inventory_2,
                '${_totalProductsSold} productos',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAnalystInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 14),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalystConversation(
    BuildContext context,
    List<SalesAnalystMessage> messages,
    bool isLoading,
  ) {
    return ListView(
      controller: _analystScrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        if (messages.length <= 1) _buildAnalystSuggestions(),
        ...messages.map(
          (message) => _buildAnalystMessageBubble(context, message),
        ),
        if (isLoading) _buildAnalystTypingIndicator(),
      ],
    );
  }

  Widget _buildAnalystSuggestions() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome, size: 16, color: AppColors.primary),
              SizedBox(width: 6),
              Text(
                'Ideas rápidas',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children:
                _analystSuggestions
                    .map(
                      (suggestion) => ActionChip(
                        label: Text(
                          suggestion,
                          style: const TextStyle(fontSize: 12),
                        ),
                        backgroundColor: AppColors.primary.withOpacity(0.08),
                        onPressed:
                            _analystController.isLoading
                                ? null
                                : () => _sendAnalystQuestion(suggestion),
                      ),
                    )
                    .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalystMessageBubble(
    BuildContext context,
    SalesAnalystMessage message,
  ) {
    final isUser = message.isUser;
    final bubbleColor =
        message.isError
            ? AppColors.error.withOpacity(0.08)
            : isUser
            ? AppColors.primary
            : Colors.white;
    final textColor = isUser ? Colors.white : AppColors.textPrimary;
    final borderColor = message.isError ? AppColors.error : AppColors.border;
    final maxWidth = MediaQuery.of(context).size.width * 0.75;

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor, width: 1),
                boxShadow:
                    isUser
                        ? null
                        : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
              ),
              child: Text(
                message.text,
                style: TextStyle(color: textColor, height: 1.4, fontSize: 13),
              ),
            ),
          ),
        ),
        if (!isUser && message.response?.hasStructuredContent == true) ...[
          const SizedBox(height: 8),
          _buildAnalystResponseSections(message.response!),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildAnalystTypingIndicator() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: const [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Analizando...'),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalystResponseSections(SalesAnalystResponse response) {
    final sections = <Widget>[];

    if (response.cards.isNotEmpty) {
      sections.add(_buildAnalystCardsSection(response.cards));
    }
    if (response.insights.isNotEmpty) {
      sections.add(
        _buildAnalystBulletSection(
          'Insights',
          response.insights,
          icon: Icons.lightbulb_outline,
        ),
      );
    }
    if (response.formulas.isNotEmpty) {
      sections.add(
        _buildAnalystBulletSection(
          'Fórmulas',
          response.formulas,
          icon: Icons.calculate_outlined,
          isFormula: true,
        ),
      );
    }
    if (response.projections.isNotEmpty) {
      sections.add(
        _buildAnalystBulletSection(
          'Proyecciones',
          response.projections,
          icon: Icons.trending_up,
        ),
      );
    }
    if (response.recommendations.isNotEmpty) {
      sections.add(
        _buildAnalystBulletSection(
          'Recomendaciones',
          response.recommendations,
          icon: Icons.task_alt,
        ),
      );
    }

    for (final table in response.tables) {
      sections.add(_buildAnalystTableSection(table));
    }
    for (final chart in response.charts) {
      sections.add(_buildAnalystChartSection(chart));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children:
          sections
              .map(
                (section) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: section,
                ),
              )
              .toList(),
    );
  }

  Widget _buildAnalystSection({
    required String title,
    required Widget child,
    IconData? icon,
    Color? accent,
  }) {
    final accentColor = accent ?? AppColors.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 16, color: accentColor),
                const SizedBox(width: 6),
              ],
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: accentColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _buildAnalystCardsSection(List<SalesAnalystCard> cards) {
    return _buildAnalystSection(
      title: 'Indicadores',
      icon: Icons.insights,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: cards.map(_buildAnalystMetricCard).toList(),
      ),
    );
  }

  Widget _buildAnalystMetricCard(SalesAnalystCard card) {
    final toneColor = _toneColor(card.tone);
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: toneColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: toneColor.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.title,
            style: TextStyle(
              fontSize: 12,
              color: toneColor,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            card.value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: toneColor,
            ),
          ),
          if (card.subtitle.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              card.subtitle,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAnalystBulletSection(
    String title,
    List<String> items, {
    IconData? icon,
    bool isFormula = false,
  }) {
    return _buildAnalystSection(
      title: title,
      icon: icon,
      accent: isFormula ? AppColors.info : null,
      child: Column(
        children:
            items
                .map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color:
                                isFormula ? AppColors.info : AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            item,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontFamily: isFormula ? 'Courier' : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
                .toList(),
      ),
    );
  }

  Widget _buildAnalystTableSection(SalesAnalystTable table) {
    return _buildAnalystSection(
      title: table.title,
      icon: Icons.table_chart_outlined,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columnSpacing: 12,
          headingTextStyle: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
          columns:
              table.columns
                  .map((column) => DataColumn(label: Text(column)))
                  .toList(),
          rows:
              table.rows.map((row) {
                final cells = List<String>.generate(
                  table.columns.length,
                  (index) => index < row.length ? row[index] : '',
                );
                return DataRow(
                  cells:
                      cells
                          .map(
                            (cell) => DataCell(
                              Text(cell, style: const TextStyle(fontSize: 12)),
                            ),
                          )
                          .toList(),
                );
              }).toList(),
        ),
      ),
    );
  }

  Widget _buildAnalystChartSection(SalesAnalystChart chart) {
    return _buildAnalystSection(
      title: chart.title.isNotEmpty ? chart.title : 'Gráfico',
      icon: Icons.bar_chart,
      child: _buildAnalystChart(chart),
    );
  }

  Widget _buildAnalystChart(SalesAnalystChart chart) {
    if (chart.labels.isEmpty || chart.series.isEmpty) {
      return const Text(
        'No hay datos suficientes para graficar.',
        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
      );
    }

    final type = chart.type.toLowerCase();
    if (type == 'line') {
      return _buildAnalystLineChart(chart);
    }
    if (type == 'pie') {
      return _buildAnalystPieChart(chart);
    }
    return _buildAnalystBarChart(chart);
  }

  Widget _buildAnalystBarChart(SalesAnalystChart chart) {
    final values = chart.series.first.values;
    final length =
        chart.labels.length < values.length
            ? chart.labels.length
            : values.length;
    if (length == 0) {
      return const SizedBox.shrink();
    }
    final maxValue = values
        .take(length)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.2,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: maxValue == 0 ? 1 : (maxValue / 4).ceilToDouble(),
              ),
            ),
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      chart.labels[index],
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(
            length,
            (index) => BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: values[index],
                  width: 14,
                  borderRadius: BorderRadius.circular(6),
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAnalystLineChart(SalesAnalystChart chart) {
    final values = chart.series.first.values;
    final length =
        chart.labels.length < values.length
            ? chart.labels.length
            : values.length;
    if (length == 0) {
      return const SizedBox.shrink();
    }
    final maxValue = values
        .take(length)
        .fold<double>(0, (max, value) => value > max ? value : max);

    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          maxY: maxValue == 0 ? 1 : maxValue * 1.2,
          gridData: FlGridData(show: true, drawVerticalLine: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 36,
                interval: maxValue == 0 ? 1 : (maxValue / 4).ceilToDouble(),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      chart.labels[index],
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: List.generate(
                length,
                (index) => FlSpot(index.toDouble(), values[index]),
              ),
              isCurved: true,
              color: AppColors.primary,
              barWidth: 3,
              dotData: FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalystPieChart(SalesAnalystChart chart) {
    final values = chart.series.first.values;
    final length =
        chart.labels.length < values.length
            ? chart.labels.length
            : values.length;
    if (length == 0) {
      return const SizedBox.shrink();
    }

    final colors = [
      AppColors.primary,
      AppColors.success,
      AppColors.warning,
      AppColors.info,
      Colors.purple,
      Colors.teal,
    ];

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 32,
              sections: List.generate(
                length,
                (index) => PieChartSectionData(
                  color: colors[index % colors.length],
                  value: values[index],
                  title: '${values[index].toStringAsFixed(0)}',
                  radius: 45,
                  titleStyle: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: List.generate(
            length,
            (index) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: colors[index % colors.length],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(chart.labels[index], style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAnalystComposer() {
    return AnimatedBuilder(
      animation: _analystController,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _analystQuestionController,
                  focusNode: _analystFocusNode,
                  minLines: 1,
                  maxLines: 3,
                  textInputAction: TextInputAction.send,
                  onSubmitted:
                      _analystController.isLoading
                          ? null
                          : (_) => _sendAnalystQuestion(),
                  decoration: InputDecoration(
                    hintText: 'Ej: ¿Qué proveedor genera más ganancias?',
                    filled: true,
                    fillColor: AppColors.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppColors.border),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed:
                    _analystController.isLoading
                        ? null
                        : () => _sendAnalystQuestion(),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.all(14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  backgroundColor: AppColors.primary,
                ),
                child:
                    _analystController.isLoading
                        ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                        : const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendAnalystQuestion([String? suggestion]) async {
    final question = (suggestion ?? _analystQuestionController.text).trim();
    final context = _buildAnalystContextSnapshot();
    _analystQuestionController.clear();
    _analystFocusNode.requestFocus();
    await _analystController.sendQuestion(question: question, context: context);
  }

  void _resetAnalystConversation() {
    _analystController.resetConversation();
    _analystQuestionController.clear();
    _analystFocusNode.requestFocus();
    _scrollAnalystToBottom();
  }

  SalesAnalystContextSnapshot _buildAnalystContextSnapshot() {
    return SalesAnalystContextSnapshot(
      startDate: _startDate,
      endDate: _endDate,
      totalSales: _totalSales,
      totalProductsSold: _totalProductsSold,
      productSalesReports: _productSalesReports,
      vendorReports: _vendorReports,
      supplierReports: _supplierReports,
      selectedTpv: _selectedTPV,
      selectedWarehouseId: _selectedWarehouseId,
      selectedWarehouseName: _selectedWarehouseName,
      productAnalysis: _productAnalysis,
    );
  }

  String _formatCurrency(double value) {
    return NumberFormat.currency(locale: 'es', symbol: '\$').format(value);
  }

  Color _toneColor(String tone) {
    switch (tone.toLowerCase()) {
      case 'success':
        return AppColors.success;
      case 'warning':
        return AppColors.warning;
      case 'danger':
        return AppColors.error;
      default:
        return AppColors.info;
    }
  }

  Widget _buildSummaryColumn(String label, double value, Color color) {
    return Column(
      children: [
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  String _formatDateRangeLabel() {
    final startFormatted =
        '${_startDate.day.toString().padLeft(2, '0')}/${_startDate.month.toString().padLeft(2, '0')}/${_startDate.year}';
    final endFormatted =
        '${_endDate.day.toString().padLeft(2, '0')}/${_endDate.month.toString().padLeft(2, '0')}/${_endDate.year}';

    if (_startDate.day == _endDate.day &&
        _startDate.month == _endDate.month &&
        _startDate.year == _endDate.year) {
      return startFormatted;
    } else {
      return '$startFormatted - $endFormatted';
    }
  }

  Widget _buildRealTimeMetrics(double totalSales, int totalProducts) {
    String periodLabel = _formatDateRangeLabel();
    return Row(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.attach_money,
                  color: AppColors.success,
                  size: 32,
                ),
                const SizedBox(height: 8),
                _isLoadingMetrics
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(
                      '\$${totalSales.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.success,
                      ),
                    ),
                Text(
                  'Ventas',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                const Icon(Icons.receipt, color: AppColors.info, size: 32),
                const SizedBox(height: 8),
                _isLoadingMetrics
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : Text(
                      '$totalProducts',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                Text(
                  'Productos',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProductSalesReport() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Reporte de Ventas por Producto',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (_isLoadingProducts)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_productSalesReports.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No hay datos de ventas para el período seleccionado',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 12,
                columns: const [
                  DataColumn(
                    label: Text(
                      'Producto',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio (u)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Cant Vendidos',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Total Venta',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Costo (u)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Total Costo',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Ganancias',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows: [
                  // Product rows
                  ..._productSalesReports.map((report) {
                    // Calculate total cost CUP and profit
                    final totalCostoCup =
                        report.precioCostoCup * report.totalVendido;
                    final ganancias = report.ingresosTotales - totalCostoCup;

                    return DataRow(
                      cells: [
                        DataCell(
                          SizedBox(
                            width: 180,
                            child: Text(
                              report.nombreProducto,
                              overflow: TextOverflow.visible,
                              softWrap: true,
                              maxLines: 2,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${report.precioVentaCup.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.info),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${report.totalVendido.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.primary),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${report.ingresosTotales.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${report.precioCostoCup.toStringAsFixed(0)}',
                            style: const TextStyle(color: AppColors.warning),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${totalCostoCup.toStringAsFixed(0)}',
                            style: const TextStyle(
                              color: AppColors.warning,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${ganancias.toStringAsFixed(0)}',
                            style: TextStyle(
                              color:
                                  ganancias >= 0
                                      ? AppColors.success
                                      : AppColors.error,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  // Totals row
                  if (_productSalesReports.isNotEmpty)
                    DataRow(
                      color: MaterialStateProperty.all(
                        AppColors.primary.withOpacity(0.1),
                      ),
                      cells: [
                        const DataCell(
                          Text(
                            'TOTALES',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        const DataCell(Text('-')), // No average price
                        DataCell(
                          Text(
                            '${_productSalesReports.fold(0.0, (sum, report) => sum + report.totalVendido).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${_productSalesReports.fold(0.0, (sum, report) => sum + report.ingresosTotales).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.success,
                            ),
                          ),
                        ),
                        const DataCell(Text('-')), // No average cost
                        DataCell(
                          Text(
                            '\$${_productSalesReports.fold(0.0, (sum, report) => sum + (report.precioCostoCup * report.totalVendido)).toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '\$${(_productSalesReports.fold(0.0, (sum, report) => sum + report.ingresosTotales) - _productSalesReports.fold(0.0, (sum, report) => sum + (report.precioCostoCup * report.totalVendido))).toStringAsFixed(0)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color:
                                  (_productSalesReports.fold(
                                                0.0,
                                                (sum, report) =>
                                                    sum +
                                                    report.ingresosTotales,
                                              ) -
                                              _productSalesReports.fold(
                                                0.0,
                                                (sum, report) =>
                                                    sum +
                                                    (report.precioCostoCup *
                                                        report.totalVendido),
                                              )) >=
                                          0
                                      ? AppColors.success
                                      : AppColors.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductAnalysisTable() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Análisis de Productos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (_isLoadingAnalysis)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            )
          else if (_productAnalysis.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'No hay datos de productos disponibles',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(
                    label: Text(
                      'Producto',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Tasa de Cambio USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Costo USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Venta USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Costo CUP',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Precio Venta CUP',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Ganancia USD',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Ganancia CUP',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                  DataColumn(
                    label: Text(
                      '% Ganancia',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
                rows:
                    _productAnalysis.map((analysis) {
                      return DataRow(
                        cells: [
                          DataCell(
                            SizedBox(
                              width: 200,
                              child: Text(
                                analysis.nombreProducto,
                                overflow: TextOverflow.visible,
                                softWrap: true,
                                maxLines: 2,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.valorUsd.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.precioCostoUsd.toStringAsFixed(4)}',
                              style: const TextStyle(color: AppColors.warning),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.precioVentaUsd.toStringAsFixed(4)}',
                              style: const TextStyle(color: AppColors.info),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.precioCostoCup.toStringAsFixed(2)}',
                              style: const TextStyle(color: AppColors.warning),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.precioVentaCup.toStringAsFixed(2)}',
                              style: const TextStyle(color: AppColors.success),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.gananciaUsd.toStringAsFixed(4)}',
                              style: TextStyle(
                                color:
                                    analysis.gananciaUsd >= 0
                                        ? AppColors.success
                                        : AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '\$${analysis.gananciaCup.toStringAsFixed(2)}',
                              style: TextStyle(
                                color:
                                    analysis.gananciaCup >= 0
                                        ? AppColors.success
                                        : AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          DataCell(
                            Text(
                              '${analysis.porcGananciaCup.toStringAsFixed(1)}%',
                              style: TextStyle(
                                color:
                                    analysis.porcGananciaCup >= 0
                                        ? AppColors.success
                                        : AppColors.error,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVendorCard(SalesVendorReport vendor) {
    final statusColor = _getVendorStatusColor(vendor.status);
    final statusIcon = _getVendorStatusIcon(vendor.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withOpacity(0.1),
          child: Icon(Icons.person, color: statusColor),
        ),
        title: Text(
          vendor.nombreCompleto,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${vendor.totalVentas} ventas • \$${vendor.totalDineroGeneral.toStringAsFixed(2)}',
            ),
            Text(
              '${vendor.totalProductosVendidos.toStringAsFixed(0)} productos vendidos',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        trailing: Icon(statusIcon, color: statusColor),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildVendorDetailRow(
                  'Efectivo en Caja',
                  '\$${(vendor.totalDineroEfectivo - vendor.totalEgresos).toStringAsFixed(2)}',
                  AppColors.success,
                ),
                _buildVendorDetailRow(
                  'Transferencia',
                  '\$${vendor.totalDineroTransferencia.toStringAsFixed(2)}',
                  AppColors.info,
                ),
                _buildVendorDetailRow(
                  'Productos diferentes',
                  '${vendor.productosDiferentesVendidos}',
                  AppColors.primary,
                ),
                _buildVendorDetailRow(
                  'Primera venta',
                  _formatDateTime(vendor.primeraVenta),
                  AppColors.textSecondary,
                ),
                _buildVendorDetailRow(
                  'Última venta',
                  _formatDateTime(vendor.ultimaVenta),
                  AppColors.textSecondary,
                ),
                _buildVendorDetailRow(
                  'Total Egresos',
                  '\$${vendor.totalEgresos.toStringAsFixed(2)}',
                  AppColors.error,
                ),
                const SizedBox(height: 8),
                // Primera fila de botones
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showVendorEgresosDetail(vendor),
                        icon: const Icon(Icons.receipt_long, size: 16),
                        label: const Text(
                          'Egresos',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => _showVendorOrdersDetail(vendor),
                        icon: const Icon(Icons.shopping_cart, size: 16),
                        label: const Text(
                          'Órdenes',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.info,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Segunda fila - botones de transferencias y órdenes pendientes
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () => _showVendorTransferenciasDetail(vendor),
                        icon: const Icon(Icons.account_balance, size: 16),
                        label: const Text(
                          'Transferencias',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed:
                            () => _showVendorOrdenesPendientesDetail(vendor),
                        icon: const Icon(Icons.pending_actions, size: 16),
                        label: const Text(
                          'Órdenes Pendientes',
                          style: TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.warning,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVendorDetailRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Color _getVendorStatusColor(String status) {
    switch (status) {
      case 'activo':
        return AppColors.success;
      case 'reciente':
        return AppColors.warning;
      case 'inactivo':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getVendorStatusIcon(String status) {
    switch (status) {
      case 'activo':
        return Icons.check_circle;
      case 'reciente':
        return Icons.schedule;
      case 'inactivo':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    final localDateTime = dateTime.toLocal();
    return DateFormat('dd/MM/yyyy HH:mm').format(localDateTime);
  }

  Widget _buildSalesChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Tendencia de Ventas',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(show: false),
                titlesData: FlTitlesData(show: false),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(
                      7,
                      (index) => FlSpot(
                        index.toDouble(),
                        (index * 100 + 200).toDouble(),
                      ),
                    ),
                    isCurved: true,
                    color: AppColors.primary,
                    barWidth: 3,
                    dotData: FlDotData(show: false),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopProducts() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Productos Más Vendidos',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ...List.generate(
            5,
            (index) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.1),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text('Producto ${index + 1}'),
              subtitle: Text('${50 - index * 5} unidades vendidas'),
              trailing: Text(
                '\$${(1000 - index * 100).toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.date_range, color: AppColors.primary),
          const SizedBox(width: 12),
          const Text('Fecha: ', style: TextStyle(fontWeight: FontWeight.w600)),
          Expanded(
            child: GestureDetector(
              onTap: _showDateRangePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDateRangeLabel(),
                      style: const TextStyle(fontSize: 14),
                    ),
                    const Icon(Icons.arrow_drop_down, color: AppColors.primary),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(
              context,
            ).colorScheme.copyWith(primary: AppColors.primary),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        // Ensure start date is at 00:00:00
        _startDate = DateTime(
          picked.start.year,
          picked.start.month,
          picked.start.day,
          0,
          0,
          0,
        );
        // Ensure end date is at 23:59:59
        _endDate = DateTime(
          picked.end.year,
          picked.end.month,
          picked.end.day,
          23,
          59,
          59,
        );
      });

      // Reload data with new date range
      _loadProductSalesData();
      _loadVendorReports();
      _loadSupplierReports();
      _loadProductAnalysis();
    }
  }

  void _showVendorEgresosDetail(SalesVendorReport vendor) async {
    try {
      final deliveries = await SalesService.getCashDeliveries(
        fechaInicio: _startDate,
        fechaFin: _endDate,
        uuidUsuario: vendor.uuidUsuario,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder:
            (context) => AlertDialog(
              title: Text(
                'Egresos de ${vendor.nombreCompleto}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 400,
                child:
                    deliveries.isEmpty
                        ? const Center(
                          child: Text(
                            'No hay egresos registrados para este vendedor en el período seleccionado',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                        : ListView.builder(
                          itemCount: deliveries.length,
                          itemBuilder: (context, index) {
                            final delivery = deliveries[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.error.withOpacity(
                                    0.1,
                                  ),
                                  child: const Icon(
                                    Icons.money_off,
                                    color: AppColors.error,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  '\$${delivery.montoEntrega.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.error,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      delivery.motivoEntrega,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    Text(
                                      'Recibe: ${delivery.nombreRecibe}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      'Autoriza: ${delivery.nombreAutoriza}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                                trailing: Text(
                                  _formatDateTime(delivery.fechaEntrega),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cerrar'),
                ),
              ],
            ),
      );
    } catch (e) {
      print('Error loading vendor egresos detail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar los egresos del vendedor'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showVendorOrdersDetail(SalesVendorReport vendor) async {
    try {
      final dateRange = _getDateRange();
      final orders = await SalesService.getVendorOrders(
        fechaDesde: dateRange['start']!,
        fechaHasta: dateRange['end']!,
        uuidUsuario: vendor.uuidUsuario,
      );

      if (!mounted) return;

      // Calcular totales separados por tipo de pago
      double totalEfectivoOferta = 0.0; // tipo_pago = 1
      double totalEfectivoRegular = 0.0; // tipo_pago = 2
      double totalTransferencias = 0.0;

      for (final order in orders) {
        if (order.detalles['pagos'] != null) {
          final pagos = order.detalles['pagos'] as List;
          for (final pago in pagos) {
            final metodoPago =
                pago['medio_pago']?.toString().toLowerCase() ?? '';
            final total = (pago['total'] ?? 0.0).toDouble();
            final esEfectivo = pago['es_efectivo'] ?? false;
            final tipoPago = pago['tipo_pago'] ?? 1;

            if (esEfectivo && metodoPago.contains('efectivo')) {
              // Separar efectivo por tipo_pago
              if (tipoPago == 1) {
                totalEfectivoOferta += total;
              } else if (tipoPago == 2) {
                totalEfectivoRegular += total;
              }
            } else if (metodoPago.contains('transferencia')) {
              totalTransferencias += total;
            }
          }
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder:
            (context) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder:
                  (context, scrollController) => Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Handle
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Órdenes de ${vendor.nombreCompleto}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      '${orders.length} órdenes encontradas',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Totales separados por tipo de pago
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        // Efectivo Oferta (tipo_pago = 1)
                                        if (totalEfectivoOferta > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade700
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.green.shade700
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.local_offer,
                                                  size: 16,
                                                  color: Colors.green.shade700,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Efectivo (Oferta): \$${totalEfectivoOferta.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        Colors.green.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Efectivo Regular (tipo_pago = 2)
                                        if (totalEfectivoRegular > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.success
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.success
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.attach_money,
                                                  size: 16,
                                                  color: AppColors.success,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Efectivo (Regular): \$${totalEfectivoRegular.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Transferencias
                                        if (totalTransferencias > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.info.withOpacity(
                                                0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.info
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.account_balance,
                                                  size: 16,
                                                  color: AppColors.info,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Transfer: \$${totalTransferencias.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.info,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Content
                        Expanded(
                          child:
                              orders.isEmpty
                                  ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.shopping_cart_outlined,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No hay órdenes',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'No se encontraron órdenes para este vendedor\nen el período seleccionado',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: orders.length,
                                    itemBuilder: (context, index) {
                                      final order = orders[index];
                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[200]!,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ExpansionTile(
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                          childrenPadding:
                                              const EdgeInsets.fromLTRB(
                                                16,
                                                0,
                                                16,
                                                16,
                                              ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Orden #${order.idOperacion}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _getStatusColor(
                                                    order.estadoNombre,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Text(
                                                  order.estadoNombre,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                _buildDiscountRow(order),
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Row(
                                                        children: [
                                                          Icon(
                                                            Icons.attach_money,
                                                            size: 16,
                                                            color:
                                                                AppColors
                                                                    .success,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '\$${order.totalOperacion.toStringAsFixed(2)}',
                                                            style:
                                                                const TextStyle(
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w600,
                                                                  fontSize: 15,
                                                                ),
                                                          ),
                                                          const SizedBox(
                                                            width: 16,
                                                          ),
                                                          Icon(
                                                            Icons.shopping_bag,
                                                            size: 16,
                                                            color:
                                                                AppColors.info,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            '${order.cantidadItems} prod.',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 14,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Text(
                                                      _formatOrderDate(
                                                        order.fechaOperacion,
                                                      ),
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // Medios de pago
                                                if (order.detalles['pagos'] !=
                                                        null &&
                                                    (order.detalles['pagos']
                                                            as List)
                                                        .isNotEmpty) ...[
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children:
                                                        _buildPaymentMethodChips(
                                                          order.detalles['pagos']
                                                              as List,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          children: [
                                            const Divider(),
                                            const SizedBox(height: 8),

                                            // Cliente
                                            if (order.detalles['cliente'] !=
                                                null) ...[
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.person,
                                                    size: 20,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Cliente:',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 2,
                                                        ),
                                                        Text(
                                                          order.detalles['cliente']['nombre_completo'] ??
                                                              'N/A',
                                                          style:
                                                              const TextStyle(
                                                                fontSize: 14,
                                                              ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 16),
                                            ],

                                            // Productos
                                            Row(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Icon(
                                                  Icons.inventory_2,
                                                  size: 20,
                                                  color: AppColors.primary,
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      const Text(
                                                        'Productos:',
                                                        style: TextStyle(
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 8),
                                                      if (order
                                                              .detalles['items'] !=
                                                          null)
                                                        ...() {
                                                          // Obtener lista de items
                                                          final items =
                                                              order.detalles['items']
                                                                  as List;

                                                          // Filtrar productos con precio_unitario = 0.0 y eliminar duplicados
                                                          final seenProductIds =
                                                              <dynamic>{};
                                                          final uniqueItems =
                                                              items.where((
                                                                item,
                                                              ) {
                                                                final precioUnitario =
                                                                    (item['precio_unitario'] ??
                                                                            0.0)
                                                                        .toDouble();

                                                                // Filtrar productos con precio 0
                                                                if (precioUnitario ==
                                                                    0.0) {
                                                                  return false;
                                                                }

                                                                // Obtener ID del producto para verificar duplicados
                                                                final productId =
                                                                    item['id_producto'] ??
                                                                    item['producto_id'] ??
                                                                    item['id'];

                                                                // Si ya vimos este producto, no lo incluimos
                                                                if (seenProductIds
                                                                    .contains(
                                                                      productId,
                                                                    )) {
                                                                  return false;
                                                                }

                                                                // Agregar a la lista de vistos
                                                                seenProductIds
                                                                    .add(
                                                                      productId,
                                                                    );
                                                                return true;
                                                              }).toList();

                                                          // Generar widgets para items únicos
                                                          return uniqueItems.map((
                                                            item,
                                                          ) {
                                                            return Container(
                                                              margin:
                                                                  const EdgeInsets.only(
                                                                    bottom: 6,
                                                                  ),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    12,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    Colors
                                                                        .grey[50],
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: Border.all(
                                                                  color:
                                                                      Colors
                                                                          .grey[200]!,
                                                                ),
                                                              ),
                                                              child: Row(
                                                                children: [
                                                                  Expanded(
                                                                    flex: 3,
                                                                    child: Text(
                                                                      item['producto_nombre'] ??
                                                                          item['nombre'] ??
                                                                          'Producto',
                                                                      style: const TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Expanded(
                                                                    flex: 1,
                                                                    child: Text(
                                                                      'x${item['cantidad']}',
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        color:
                                                                            Colors.grey[600],
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Expanded(
                                                                    flex: 1,
                                                                    child: Text(
                                                                      '\$${(item['importe'] ?? 0.0).toStringAsFixed(2)}',
                                                                      textAlign:
                                                                          TextAlign
                                                                              .right,
                                                                      style: const TextStyle(
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                        fontSize:
                                                                            13,
                                                                        color: Color(
                                                                          0xFF4A90E2,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          }).toList();
                                                        }(),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),

                                            // Desglose de Pagos
                                            if (order.detalles['pagos'] !=
                                                    null &&
                                                (order.detalles['pagos']
                                                        as List)
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.payment,
                                                    size: 20,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Desglose de Pagos:',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 8,
                                                        ),
                                                        ...List.generate(
                                                          (order.detalles['pagos']
                                                                  as List)
                                                              .length,
                                                          (paymentIndex) {
                                                            final payment =
                                                                order
                                                                    .detalles['pagos'][paymentIndex];
                                                            return Container(
                                                              margin:
                                                                  const EdgeInsets.only(
                                                                    bottom: 6,
                                                                  ),
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    12,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color: _getPaymentColorByType(
                                                                  payment['es_efectivo'] ??
                                                                      false,
                                                                  payment['es_digital'] ??
                                                                      false,
                                                                ).withOpacity(
                                                                  0.1,
                                                                ),
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                                border: Border.all(
                                                                  color: _getPaymentColorByType(
                                                                    payment['es_efectivo'] ??
                                                                        false,
                                                                    payment['es_digital'] ??
                                                                        false,
                                                                  ).withOpacity(
                                                                    0.3,
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Row(
                                                                children: [
                                                                  Icon(
                                                                    _getPaymentIconByType(
                                                                      payment['es_efectivo'] ??
                                                                          false,
                                                                      payment['es_digital'] ??
                                                                          false,
                                                                    ),
                                                                    size: 16,
                                                                    color: _getPaymentColorByType(
                                                                      payment['es_efectivo'] ??
                                                                          false,
                                                                      payment['es_digital'] ??
                                                                          false,
                                                                    ),
                                                                  ),
                                                                  const SizedBox(
                                                                    width: 8,
                                                                  ),
                                                                  Expanded(
                                                                    child: Text(
                                                                      () {
                                                                        String
                                                                        metodoPago =
                                                                            payment['medio_pago'] ??
                                                                            'N/A';
                                                                        bool
                                                                        esEfectivo =
                                                                            payment['es_efectivo'] ??
                                                                            false;
                                                                        int
                                                                        tipoPago =
                                                                            payment['tipo_pago'] ??
                                                                            1;

                                                                        // Si es efectivo, diferenciar según tipo_pago
                                                                        if (esEfectivo &&
                                                                            metodoPago.toLowerCase().contains(
                                                                              'efectivo',
                                                                            )) {
                                                                          if (tipoPago ==
                                                                              1) {
                                                                            return 'Pago Oferta (Efectivo)';
                                                                          } else if (tipoPago ==
                                                                              2) {
                                                                            return 'Pago Regular (Efectivo)';
                                                                          }
                                                                        }
                                                                        return metodoPago;
                                                                      }(),
                                                                      style: TextStyle(
                                                                        fontSize:
                                                                            13,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                        color: _getPaymentColorByType(
                                                                          payment['es_efectivo'] ??
                                                                              false,
                                                                          payment['es_digital'] ??
                                                                              false,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                  Text(
                                                                    '\$${(payment['total'] ?? 0.0).toStringAsFixed(2)}',
                                                                    style: TextStyle(
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      fontSize:
                                                                          13,
                                                                      color: _getPaymentColorByType(
                                                                        payment['es_efectivo'] ??
                                                                            false,
                                                                        payment['es_digital'] ??
                                                                            false,
                                                                      ),
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            );
                                                          },
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],

                                            // Observaciones
                                            if (order.observaciones != null &&
                                                order
                                                    .observaciones!
                                                    .isNotEmpty) ...[
                                              const SizedBox(height: 16),
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.note,
                                                    size: 20,
                                                    color: AppColors.primary,
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        const Text(
                                                          'Observaciones:',
                                                          style: TextStyle(
                                                            fontWeight:
                                                                FontWeight.w600,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          height: 4,
                                                        ),
                                                        Container(
                                                          width:
                                                              double.infinity,
                                                          padding:
                                                              const EdgeInsets.all(
                                                                12,
                                                              ),
                                                          decoration: BoxDecoration(
                                                            color:
                                                                Colors.blue[50],
                                                            borderRadius:
                                                                BorderRadius.circular(
                                                                  8,
                                                                ),
                                                            border: Border.all(
                                                              color:
                                                                  Colors
                                                                      .blue[200]!,
                                                            ),
                                                          ),
                                                          child: Text(
                                                            order.observaciones ??
                                                                '',
                                                            style:
                                                                const TextStyle(
                                                                  fontSize: 13,
                                                                ),
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
            ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar órdenes: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Color _getStatusColor(String estadoNombre) {
    switch (estadoNombre) {
      case 'Pendiente':
        return AppColors.warning;
      case 'Completado':
      case 'Completada':
        return AppColors.success;
      case 'Cancelado':
        return AppColors.error;
      default:
        return AppColors.textSecondary;
    }
  }

  String _formatOrderDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Map<String, DateTime> _getDateRange() {
    return {'start': _startDate, 'end': _endDate};
  }

  List<Widget> _buildPaymentMethodChips(List<dynamic> pagos) {
    // Agrupar pagos por método de pago y tipo
    Map<String, Map<String, dynamic>> paymentSummary = {};
    for (var pago in pagos) {
      String metodoPago = pago['medio_pago'] ?? 'N/A';
      double monto = (pago['total'] ?? 0.0).toDouble();
      bool esEfectivo = pago['es_efectivo'] ?? false;
      bool esDigital = pago['es_digital'] ?? false;
      int tipoPago = pago['tipo_pago'] ?? 1; // Obtener tipo_pago, por defecto 1

      // Si es efectivo, diferenciar según tipo_pago
      if (esEfectivo && metodoPago.toLowerCase().contains('efectivo')) {
        if (tipoPago == 1) {
          metodoPago = 'Pago Oferta (Efectivo)';
        } else if (tipoPago == 2) {
          metodoPago = 'Pago Regular (Efectivo)';
        }
      }

      String key = '$metodoPago-$esEfectivo-$esDigital-$tipoPago';
      if (paymentSummary.containsKey(key)) {
        paymentSummary[key]!['total'] += monto;
      } else {
        paymentSummary[key] = {
          'medio_pago': metodoPago,
          'total': monto,
          'es_efectivo': esEfectivo,
          'es_digital': esDigital,
          'tipo_pago': tipoPago,
        };
      }
    }

    return paymentSummary.values.map((payment) {
      Color color = _getPaymentColorByType(
        payment['es_efectivo'],
        payment['es_digital'],
      );
      IconData icon = _getPaymentIconByType(
        payment['es_efectivo'],
        payment['es_digital'],
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
            Text(
              payment['medio_pago'],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: color,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  // Nuevos métodos basados en los campos es_efectivo y es_digital
  Color _getPaymentColorByType(bool esEfectivo, bool esDigital) {
    if (esEfectivo) {
      return AppColors.success; // Verde para efectivo
    } else if (esDigital) {
      return Colors.teal; // Verde azulado para pagos digitales
    } else {
      return AppColors.info; // Azul para transferencias/otros
    }
  }

  IconData _getPaymentIconByType(bool esEfectivo, bool esDigital) {
    if (esEfectivo) {
      return Icons.money; // Ícono de dinero en efectivo
    } else if (esDigital) {
      return Icons.smartphone; // Ícono de smartphone para pagos digitales
    } else {
      return Icons.account_balance; // Ícono de banco para transferencias
    }
  }

  // Métodos legacy mantenidos por compatibilidad
  Color _getPaymentMethodColor(String? metodoPago) {
    switch (metodoPago?.toLowerCase()) {
      case 'efectivo':
        return AppColors.success;
      case 'transferencia':
      case 'transferencia bancaria':
        return AppColors.info;
      case 'tarjeta de crédito':
      case 'tarjeta de credito':
      case 'tarjeta credito':
        return AppColors.warning;
      case 'tarjeta de débito':
      case 'tarjeta de debito':
      case 'tarjeta debito':
        return AppColors.primary;
      case 'cheque':
        return Colors.purple;
      case 'digital':
      case 'pago digital':
        return Colors.teal;
      default:
        return AppColors.textSecondary;
    }
  }

  IconData _getPaymentMethodIcon(String? metodoPago) {
    switch (metodoPago?.toLowerCase()) {
      case 'efectivo':
        return Icons.money;
      case 'transferencia':
      case 'transferencia bancaria':
        return Icons.account_balance;
      case 'tarjeta de crédito':
      case 'tarjeta de credito':
      case 'tarjeta credito':
        return Icons.credit_card;
      case 'tarjeta de débito':
      case 'tarjeta de debito':
      case 'tarjeta debito':
        return Icons.payment;
      case 'cheque':
        return Icons.receipt;
      case 'digital':
      case 'pago digital':
        return Icons.smartphone;
      default:
        return Icons.payment;
    }
  }

  /// Construye una fila resumen de descuentos por orden.
  /// Muestra total original, total cobrado, total descontado y tipo de descuento.
  Widget _buildDiscountRow(VendorOrder order) {
    final summary = _calculateDiscountSummary(order);
    if (summary['visible'] != true) return const SizedBox.shrink();

    final double original = summary['original'] ?? 0.0;
    final double cobrado = summary['cobrado'] ?? 0.0;
    final double descuento = summary['descuento'] ?? 0.0;
    final String tipo = summary['tipo'] ?? 'N/A';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          _buildDiscountChip(
            label: 'Cobrado',
            value: cobrado,
            color: AppColors.success,
          ),
          _buildDiscountChip(
            label: 'Descuento',
            value: descuento,
            color: AppColors.warning,
          ),
          _buildDiscountChip(
            label: 'Original',
            value: original,
            color: AppColors.info,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sell, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  'Tipo: $tipo',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF4B5563),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _calculateDiscountSummary(VendorOrder order) {
    final detalles = order.detalles;
    final pagos = (detalles['pagos'] as List?) ?? [];
    // Nuevo campo plural "descuentos" o fallback al campo anterior "descuento"
    Map<String, dynamic>? descuentoDetalle;
    final dynamic descuentos = detalles['descuentos'] ?? detalles['descuento'];
    if (descuentos is Map<String, dynamic>) {
      descuentoDetalle = descuentos;
    } else if (descuentos is List && descuentos.isNotEmpty) {
      // Tomar el primero de la lista si viene como arreglo
      final first = descuentos.first;
      if (first is Map<String, dynamic>) {
        descuentoDetalle = first;
      }
    }

    double cobrado = 0.0;
    double originalPagos = 0.0;
    bool hasTotalSinDescuento = false;

    for (final pago in pagos) {
      cobrado += _toDoubleSafe(pago['total']);
      final tsd = _toDoubleSafe(pago['total_sin_descuento']);
      originalPagos += tsd;
      if (tsd > 0) hasTotalSinDescuento = true;
    }

    double original = 0.0;
    if (hasTotalSinDescuento) {
      original = originalPagos;
    } else if (descuentoDetalle != null) {
      original = _toDoubleSafe(descuentoDetalle['monto_real']);
    }

    double descuento = 0.0;
    if (original > 0) {
      descuento = original - cobrado;
    }
    if (descuento <= 0 && descuentoDetalle != null) {
      descuento = _toDoubleSafe(descuentoDetalle['monto_descontado']);
    }
    if (descuento < 0) descuento = 0.0;

    String tipo = 'N/A';
    final tipoDescuento = descuentoDetalle?['tipo_descuento'];
    if (tipoDescuento != null) {
      switch (tipoDescuento) {
        case 1:
          tipo = 'Porcentaje';
          break;
        case 2:
          tipo = 'Monto fijo';
          break;
        default:
          tipo = 'Personalizado';
      }
    }

    final bool shouldShow =
        hasTotalSinDescuento || descuentoDetalle != null || descuento > 0;

    return {
      'original': original,
      'cobrado': cobrado == 0 ? order.totalOperacion : cobrado,
      'descuento': descuento,
      'tipo': tipo,
      'visible': shouldShow && (original > 0 || descuento > 0),
    };
  }

  Widget _buildDiscountChip({
    required String label,
    required double value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.price_check, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$label: \$${value.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  double _toDoubleSafe(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  int? _toIntSafe(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  void _showVendorOrdenesPendientesDetail(SalesVendorReport vendor) async {
    try {
      final dateRange = _getDateRange();

      // Llamar al método getVendorOrders con id_estado_param = 1 para órdenes pendientes
      final response = await Supabase.instance.client.rpc(
        'listar_ordenes',
        params: {
          'con_inventario_param': false,
          'fecha_desde_param':
              dateRange['start']!.toIso8601String().split('T')[0],
          'fecha_hasta_param':
              dateRange['end']!.toIso8601String().split('T')[0],
          'id_estado_param': 1, // Solo órdenes pendientes
          'id_tienda_param': await UserPreferencesService().getIdTienda(),
          'id_tipo_operacion_param': null,
          'id_tpv_param': null,
          'id_usuario_param': vendor.uuidUsuario,
          'limite_param': null,
          'pagina_param': null,
          'solo_pendientes_param': false,
        },
      );

      if (!mounted) return;

      final List<VendorOrder> pendingOrders = [];
      if (response != null) {
        for (final item in response) {
          try {
            final order = VendorOrder.fromJson(item);
            print(order.detalles);
            // Filtrar solo órdenes que contengan "Venta" en tipo_operacion
            final tipoOperacion = item['tipo_operacion']?.toString() ?? '';
            if (tipoOperacion.toLowerCase().contains('venta')) {
              pendingOrders.add(order);
            }
          } catch (e) {
            print('Error parsing pending order: $e');
          }
        }
      }

      // Calcular totales separados por tipo de pago
      double totalEfectivoOferta = 0.0; // tipo_pago = 1
      double totalEfectivoRegular = 0.0; // tipo_pago = 2
      double totalTransferencias = 0.0;

      for (final order in pendingOrders) {
        if (order.detalles['pagos'] != null) {
          final pagos = order.detalles['pagos'] as List;
          for (final pago in pagos) {
            final metodoPago =
                pago['medio_pago']?.toString().toLowerCase() ?? '';
            final total = (pago['total'] ?? 0.0).toDouble();
            final esEfectivo = pago['es_efectivo'] ?? false;
            final tipoPago = pago['tipo_pago'] ?? 1;

            if (esEfectivo && metodoPago.contains('efectivo')) {
              // Separar efectivo por tipo_pago
              if (tipoPago == 1) {
                totalEfectivoOferta += total;
              } else if (tipoPago == 2) {
                totalEfectivoRegular += total;
              }
            } else if (metodoPago.contains('transferencia')) {
              totalTransferencias += total;
            }
          }
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder:
            (context) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder:
                  (context, scrollController) => Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Handle
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Órdenes Pendientes de ${vendor.nombreCompleto}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      '${pendingOrders.length} órdenes pendientes',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    // Totales separados por tipo de pago
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        // Efectivo Oferta (tipo_pago = 1)
                                        if (totalEfectivoOferta > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.green.shade700
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: Colors.green.shade700
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.local_offer,
                                                  size: 16,
                                                  color: Colors.green.shade700,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Efectivo (Oferta): \$${totalEfectivoOferta.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        Colors.green.shade700,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Efectivo Regular (tipo_pago = 2)
                                        if (totalEfectivoRegular > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.success
                                                  .withOpacity(0.1),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.success
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.attach_money,
                                                  size: 16,
                                                  color: AppColors.success,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Efectivo (Regular): \$${totalEfectivoRegular.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.success,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        // Transferencias
                                        if (totalTransferencias > 0)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.info.withOpacity(
                                                0.1,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              border: Border.all(
                                                color: AppColors.info
                                                    .withOpacity(0.3),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.account_balance,
                                                  size: 16,
                                                  color: AppColors.info,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  'Transfer: \$${totalTransferencias.toStringAsFixed(2)}',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.info,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Content
                        Expanded(
                          child:
                              pendingOrders.isEmpty
                                  ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.pending_actions_outlined,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No hay órdenes pendientes',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'No se encontraron órdenes pendientes\npara este vendedor en el período seleccionado',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: pendingOrders.length,
                                    itemBuilder: (context, index) {
                                      final order = pendingOrders[index];

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        padding: const EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: AppColors.warning
                                                .withOpacity(0.3),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.grey.withOpacity(
                                                0.1,
                                              ),
                                              spreadRadius: 1,
                                              blurRadius: 3,
                                              offset: const Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'Orden #${order.idOperacion}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF1F2937),
                                                  ),
                                                ),
                                                Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.warning
                                                        .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          6,
                                                        ),
                                                    border: Border.all(
                                                      color: AppColors.warning
                                                          .withOpacity(0.3),
                                                    ),
                                                  ),
                                                  child: Text(
                                                    order.estadoNombre,
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: AppColors.warning,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              children: [
                                                Icon(
                                                  Icons.access_time,
                                                  size: 16,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  _formatDateTime(
                                                    order.fechaOperacion,
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                                const SizedBox(width: 16),
                                                Icon(
                                                  Icons.shopping_cart,
                                                  size: 16,
                                                  color: Colors.grey[600],
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  '${order.cantidadItems} items',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[600],
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment
                                                      .spaceBetween,
                                              children: [
                                                Text(
                                                  'TPV: ${order.tpvNombre}',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    color: Colors.grey[700],
                                                  ),
                                                ),
                                                Text(
                                                  '\$${order.totalOperacion.toStringAsFixed(2)}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppColors.primary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 8),
                                            // Fila con observaciones y botón de productos
                                            Row(
                                              children: [
                                                // Observaciones (si existen)
                                                if (order.observaciones !=
                                                        null &&
                                                    order
                                                        .observaciones!
                                                        .isNotEmpty)
                                                  Expanded(
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            8,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: Colors.grey[100],
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              6,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        'Obs: ${order.observaciones}',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          color:
                                                              Colors.grey[700],
                                                          fontStyle:
                                                              FontStyle.italic,
                                                        ),
                                                      ),
                                                    ),
                                                  ),

                                                // Espaciado si hay observaciones
                                                if (order.observaciones !=
                                                        null &&
                                                    order
                                                        .observaciones!
                                                        .isNotEmpty)
                                                  const SizedBox(width: 8),

                                                // Botón de productos
                                                ElevatedButton.icon(
                                                  onPressed:
                                                      () =>
                                                          _showOrderProductsDetail(
                                                            order,
                                                          ),
                                                  icon: const Icon(
                                                    Icons.inventory_2,
                                                    size: 16,
                                                  ),
                                                  label: const Text(
                                                    'Productos',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                    ),
                                                  ),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor:
                                                        AppColors.primary,
                                                    foregroundColor:
                                                        Colors.white,
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 12,
                                                          vertical: 6,
                                                        ),
                                                    minimumSize: Size.zero,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
            ),
      );
    } catch (e) {
      print('Error loading pending orders: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar órdenes pendientes: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  void _showOrderProductsDetail(VendorOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.7,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            builder:
                (context, scrollController) => Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Handle
                      Container(
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      // Header
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Productos - Orden #${order.idOperacion}',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF1F2937),
                                    ),
                                  ),
                                  Text(
                                    'TPV: ${order.tpvNombre}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: AppColors.primary.withOpacity(
                                          0.3,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.attach_money,
                                          size: 16,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Total: \$${order.totalOperacion.toStringAsFixed(2)}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(context),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Content
                      Expanded(
                        child: _buildOrderProductsAccordion(
                          order,
                          scrollController,
                        ),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _buildOrderProductsAccordion(
    VendorOrder order,
    ScrollController scrollController,
  ) {
    // Extraer productos de order.detalles
    final items = order.detalles['items'] as List<dynamic>? ?? [];
    final pagos = order.detalles['pagos'] as List<dynamic>? ?? [];
    final cliente = order.detalles['cliente'] as Map<String, dynamic>? ?? {};

    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No hay productos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'No se encontraron productos en esta orden',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Información del cliente
          if (cliente.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.info.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.info.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: AppColors.info),
                      const SizedBox(width: 6),
                      Text(
                        'Cliente',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.info,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    cliente['nombre_completo']?.toString() ?? 'Sin nombre',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (cliente['telefono'] != null &&
                      cliente['telefono'].toString().isNotEmpty)
                    Text(
                      'Tel: ${cliente['telefono']}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Productos
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: Icon(Icons.inventory_2, color: AppColors.primary),
              title: Text(
                'Productos (${items.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              children: [
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder:
                      (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index] as Map<String, dynamic>;
                    final cantidad = (item['cantidad'] ?? 0).toDouble();
                    final precioUnitario =
                        (item['precio_unitario'] ?? 0.0).toDouble();
                    final importe = (item['importe'] ?? 0.0).toDouble();
                    final productoNombre =
                        item['producto_nombre']?.toString() ??
                        'Producto sin nombre';
                    final variante = item['variante']?.toString();
                    final presentacion = item['presentacion']?.toString();

                    return Container(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Cantidad en círculo
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                cantidad.toInt().toString(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          // Información del producto
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  productoNombre,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1F2937),
                                  ),
                                ),
                                if (variante != null &&
                                    variante.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Variante: $variante',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                                if (presentacion != null &&
                                    presentacion.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Presentación: $presentacion',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Precio unitario: \$${precioUnitario.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                    Text(
                                      '\$${importe.toStringAsFixed(2)}',
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Métodos de pago
          if (pagos.isNotEmpty) ...[
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: ExpansionTile(
                leading: Icon(Icons.payment, color: AppColors.success),
                title: Text(
                  'Métodos de Pago (${pagos.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                children: [
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: pagos.length,
                    separatorBuilder:
                        (context, index) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final pago = pagos[index] as Map<String, dynamic>;
                      final total = (pago['total'] ?? 0.0).toDouble();
                      final medioPago =
                          pago['medio_pago']?.toString() ?? 'Sin especificar';
                      final esEfectivo = pago['es_efectivo'] == true;
                      final esDigital = pago['es_digital'] == true;
                      final referencia = pago['referencia_pago']?.toString();
                      final fechaPago = pago['fecha_pago']?.toString();

                      return Container(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            // Ícono del método de pago
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color:
                                    esEfectivo
                                        ? AppColors.success.withOpacity(0.1)
                                        : esDigital
                                        ? AppColors.info.withOpacity(0.1)
                                        : AppColors.warning.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                esEfectivo
                                    ? Icons.attach_money
                                    : esDigital
                                    ? Icons.smartphone
                                    : Icons.account_balance,
                                color:
                                    esEfectivo
                                        ? AppColors.success
                                        : esDigital
                                        ? AppColors.info
                                        : AppColors.warning,
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Información del pago
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    medioPago,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (referencia != null &&
                                      referencia.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Ref: $referencia',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                  if (fechaPago != null &&
                                      fechaPago.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      'Fecha: ${_formatDateTime(DateTime.parse(fechaPago))}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            // Total del pago
                            Text(
                              '\$${total.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showVendorTransferenciasDetail(SalesVendorReport vendor) async {
    try {
      final dateRange = _getDateRange();
      final orders = await SalesService.getVendorOrders(
        fechaDesde: dateRange['start']!,
        fechaHasta: dateRange['end']!,
        uuidUsuario: vendor.uuidUsuario,
      );

      if (!mounted) return;

      // Filtrar solo órdenes que tengan transferencias como método de pago
      final transferOrders =
          orders.where((order) {
            if (order.detalles['pagos'] == null) return false;
            final pagos = order.detalles['pagos'] as List;
            return pagos.any((pago) {
              final metodoPago =
                  pago['medio_pago']?.toString().toLowerCase() ?? '';
              return metodoPago.contains('transferencia');
            });
          }).toList();

      // Calcular total de transferencias
      double totalTransferencias = 0.0;
      for (final order in transferOrders) {
        if (order.detalles['pagos'] != null) {
          final pagos = order.detalles['pagos'] as List;
          for (final pago in pagos) {
            final metodoPago =
                pago['medio_pago']?.toString().toLowerCase() ?? '';
            if (metodoPago.contains('transferencia')) {
              totalTransferencias += (pago['total'] ?? 0.0).toDouble();
            }
          }
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder:
            (context) => DraggableScrollableSheet(
              initialChildSize: 0.8,
              maxChildSize: 0.95,
              minChildSize: 0.5,
              builder:
                  (context, scrollController) => Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Handle
                        Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Header
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Transferencias de ${vendor.nombreCompleto}',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      '${transferOrders.length} órdenes con transferencias',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.success.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: AppColors.success.withOpacity(
                                            0.3,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.account_balance,
                                            size: 16,
                                            color: AppColors.success,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            'Total: \$${totalTransferencias.toStringAsFixed(2)}',
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.success,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Content
                        Expanded(
                          child:
                              transferOrders.isEmpty
                                  ? const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.account_balance_outlined,
                                          size: 64,
                                          color: Colors.grey,
                                        ),
                                        SizedBox(height: 16),
                                        Text(
                                          'No hay transferencias',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          'No se encontraron órdenes con transferencias\npara este vendedor en el período seleccionado',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Colors.grey),
                                        ),
                                      ],
                                    ),
                                  )
                                  : ListView.builder(
                                    controller: scrollController,
                                    padding: const EdgeInsets.all(16),
                                    itemCount: transferOrders.length,
                                    itemBuilder: (context, index) {
                                      final order = transferOrders[index];

                                      // Calcular total de transferencias para esta orden
                                      double orderTransferTotal = 0.0;
                                      if (order.detalles['pagos'] != null) {
                                        final pagos =
                                            order.detalles['pagos'] as List;
                                        for (final pago in pagos) {
                                          final metodoPago =
                                              pago['medio_pago']
                                                  ?.toString()
                                                  .toLowerCase() ??
                                              '';
                                          if (metodoPago.contains(
                                            'transferencia',
                                          )) {
                                            orderTransferTotal +=
                                                (pago['total'] ?? 0.0)
                                                    .toDouble();
                                          }
                                        }
                                      }

                                      return Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 12,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[200]!,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(
                                                0.05,
                                              ),
                                              blurRadius: 4,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: ExpansionTile(
                                          tilePadding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 8,
                                              ),
                                          childrenPadding:
                                              const EdgeInsets.fromLTRB(
                                                16,
                                                0,
                                                16,
                                                16,
                                              ),
                                          title: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Orden #${order.idOperacion}',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 16,
                                                  ),
                                                ),
                                              ),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 4,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: AppColors.success,
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.account_balance,
                                                      size: 12,
                                                      color: Colors.white,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '\$${orderTransferTotal.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 8,
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                // Primera fila: Total y productos
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.attach_money,
                                                      size: 16,
                                                      color:
                                                          AppColors
                                                              .textSecondary,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Total: \$${order.totalOperacion.toStringAsFixed(2)}',
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize: 15,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 16),
                                                    Icon(
                                                      Icons.shopping_bag,
                                                      size: 16,
                                                      color: AppColors.info,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '${order.cantidadItems} prod.',
                                                      style: const TextStyle(
                                                        fontSize: 14,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 6),
                                                // Segunda fila: Fecha
                                                Row(
                                                  children: [
                                                    Icon(
                                                      Icons.access_time,
                                                      size: 14,
                                                      color: Colors.grey[600],
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      _formatOrderDate(
                                                        order.fechaOperacion,
                                                      ),
                                                      style: TextStyle(
                                                        color: Colors.grey[600],
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                // Solo mostrar chips de transferencias
                                                if (order.detalles['pagos'] !=
                                                    null) ...[
                                                  const SizedBox(height: 8),
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children:
                                                        _buildTransferPaymentChips(
                                                          order.detalles['pagos']
                                                              as List,
                                                        ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                          children: [
                                            // Aquí se puede agregar más detalle de la orden si es necesario
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.all(12),
                                              decoration: BoxDecoration(
                                                color: Colors.grey[50],
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Estado: ${order.estadoNombre}',
                                                    style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    'TPV: ${order.tpvNombre}',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      color: Colors.grey[600],
                                                    ),
                                                  ),
                                                  if (order.observaciones !=
                                                      null) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Observaciones: ${order.observaciones}',
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        color: Colors.grey[600],
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                        ),
                      ],
                    ),
                  ),
            ),
      );
    } catch (e) {
      print('Error loading vendor transferencias detail: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error al cargar las transferencias del vendedor'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Método para construir chips solo de transferencias
  List<Widget> _buildTransferPaymentChips(List pagos) {
    final transferPayments =
        pagos.where((pago) {
          final metodoPago = pago['medio_pago']?.toString().toLowerCase() ?? '';
          return metodoPago.contains('transferencia');
        }).toList();

    return transferPayments.map<Widget>((payment) {
      final metodoPago = payment['medio_pago'] ?? 'N/A';
      final total = (payment['total'] ?? 0.0).toDouble();

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance, size: 12, color: AppColors.success),
            const SizedBox(width: 4),
            Text(
              metodoPago,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.success,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '\$${total.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.success,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  void _showExportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text('Exportar PDF'),
                onTap: () {
                  Navigator.pop(context);
                  _exportSupplierReportToPDF();
                },
              ),
              ListTile(
                leading: const Icon(Icons.table_chart, color: Colors.green),
                title: const Text('Exportar Excel'),
                onTap: () {
                  Navigator.pop(context);
                  _exportSupplierReportToExcel();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showSupplierDetailDialog(SupplierSalesReport supplier) async {
    try {
      final products = await SalesService.getSupplierProductReport(
        idProveedor: supplier.idProveedor,
        fechaDesde: _startDate,
        fechaHasta: _endDate,
        idAlmacen: _selectedWarehouseId,
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Detalle - ${supplier.nombreProveedor}'),
                if (_selectedWarehouseId != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Almacén: $_selectedWarehouseName',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columns: const [
                            DataColumn(
                              label: Text(
                                'Producto',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Cantidad',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                            DataColumn(
                              label: Text(
                                'Monto',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                          rows:
                              products.map((product) {
                                return DataRow(
                                  cells: [
                                    DataCell(Text(product.nombreProducto)),
                                    DataCell(
                                      Text(product.totalVendido.toString()),
                                    ),
                                    DataCell(
                                      Text(
                                        '\$${product.costoTotalVendido.toStringAsFixed(2)}',
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportSupplierDetailToPDF(
                            supplier,
                            products,
                            _selectedWarehouseName,
                          );
                        },
                        icon: const Icon(Icons.picture_as_pdf, size: 18),
                        label: const Text('PDF'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _exportSupplierDetailToExcel(
                            supplier,
                            products,
                            _selectedWarehouseName,
                          );
                        },
                        icon: const Icon(Icons.table_chart, size: 18),
                        label: const Text('Excel'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cerrar'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      print('Error al cargar detalles del proveedor: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al cargar detalles: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _exportSupplierDetailToPDF(
    SupplierSalesReport supplier,
    List<ProductSalesWithSupplier> products,
    String? warehouseName,
  ) async {
    try {
      setState(() => _isExportingPDF = true);

      final storeId = await UserPreferencesService().getIdTienda();
      Map<String, dynamic>? storeData;
      if (storeId != null) {
        storeData =
            await Supabase.instance.client
                .from('app_dat_tienda')
                .select('denominacion, direccion, ubicacion, phone, imagen_url')
                .eq('id', storeId)
                .maybeSingle();
      }

      final storeName = storeData?['denominacion'] as String? ?? 'VentIQ';
      final storeAddress = storeData?['direccion'] as String? ?? '';
      final storeLocation = storeData?['ubicacion'] as String? ?? '';
      final storePhone = storeData?['phone'] as String? ?? '';
      final storeLogoUrl = storeData?['imagen_url'] as String?;
      final logoBytes = await _downloadImageBytes(storeLogoUrl);

      final pdf = pw.Document();
      final dateLabel = _formatDateRangeLabel();

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _buildPdfHeader(
                  logoBytes: logoBytes,
                  storeName: storeName,
                  storeAddress: storeAddress,
                  storeLocation: storeLocation,
                  storePhone: storePhone,
                  dateLabel: dateLabel,
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Reporte de Proveedor',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 12),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F1F5F9'),
                    borderRadius: pw.BorderRadius.circular(6),
                    border: pw.Border.all(
                      color: PdfColor.fromHex('#CBD5E1'),
                      width: 0.8,
                    ),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Datos del Proveedor',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0F172A'),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      if (warehouseName != null) ...[
                        pw.Text(
                          'Almacén: $warehouseName',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: PdfColor.fromHex('#475569'),
                          ),
                        ),
                        pw.SizedBox(height: 8),
                      ],
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Nombre:',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                          pw.Text(
                            supplier.nombreProveedor,
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total Costo:',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                          pw.Text(
                            '\$${supplier.totalCosto.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Detalle de Productos',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Período: $dateLabel',
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 16),
                pw.Table(
                  border: pw.TableBorder(
                    horizontalInside: pw.BorderSide(
                      color: PdfColors.grey300,
                      width: 0.3,
                    ),
                    bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(4),
                    1: const pw.FlexColumnWidth(1.5),
                    2: const pw.FlexColumnWidth(1.5),
                  },
                  children: [
                    pw.TableRow(
                      children: [
                        _pdfHeaderCell('Producto'),
                        _pdfHeaderCell('Cantidad'),
                        _pdfHeaderCell('Monto'),
                      ],
                    ),
                    ...products.map((product) {
                      return pw.TableRow(
                        children: [
                          _pdfBodyCell(product.nombreProducto),
                          _pdfBodyCell(product.totalVendido.toStringAsFixed(0)),
                          _pdfBodyCell(
                            '\$${product.costoTotalVendido.toStringAsFixed(2)}',
                          ),
                        ],
                      );
                    }).toList(),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(10),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#EEF2FF'),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(
                      color: PdfColor.fromHex('#CBD5E1'),
                      width: 0.8,
                    ),
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text(
                        'TOTAL:',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      pw.Text(
                        '\$${supplier.totalCosto.toStringAsFixed(2)}',
                        style: pw.TextStyle(
                          fontWeight: pw.FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );

      final bytes = await pdf.save();
      final fileName =
          'detalle_proveedor_${supplier.idProveedor}_${DateTime.now().millisecondsSinceEpoch}.pdf';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: bytes, filename: fileName);
      } else {
        try {
          final output = await getTemporaryDirectory();
          final file = File('${output.path}/$fileName');
          await file.writeAsBytes(bytes);

          await Share.shareXFiles([
            XFile(file.path, mimeType: 'application/pdf'),
          ], text: 'Detalle de proveedor ${supplier.nombreProveedor}');
        } catch (e) {
          print('Error al guardar en directorio temporal: $e');
          await Printing.sharePdf(bytes: bytes, filename: fileName);
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF generado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error al exportar PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPDF = false);
      }
    }
  }

  Future<void> _exportSupplierDetailToExcel(
    SupplierSalesReport supplier,
    List<ProductSalesWithSupplier> products,
    String? warehouseName,
  ) async {
    try {
      setState(() => _isExportingPDF = true);

      final excelSheet = excel.Excel.createExcel();
      final sheet = excelSheet['Detalle'];

      // Agregar encabezado con información del almacén si está filtrado
      if (warehouseName != null) {
        sheet.appendRow([excel.TextCellValue('Almacén: $warehouseName')]);
        sheet.appendRow([]);
      }

      sheet.appendRow([
        excel.TextCellValue('Proveedor: ${supplier.nombreProveedor}'),
      ]);
      sheet.appendRow([]);

      sheet.appendRow([
        excel.TextCellValue('Producto'),
        excel.TextCellValue('Cantidad'),
        excel.TextCellValue('Monto'),
      ]);

      for (var product in products) {
        sheet.appendRow([
          excel.TextCellValue(product.nombreProducto),
          excel.IntCellValue(product.totalVendido.toInt()),
          excel.DoubleCellValue(product.costoTotalVendido),
        ]);
      }

      sheet.appendRow([]);
      sheet.appendRow([
        excel.TextCellValue('TOTAL'),
        excel.TextCellValue(''),
        excel.DoubleCellValue(supplier.totalCosto),
      ]);

      final fileName =
          'detalle_proveedor_${supplier.idProveedor}_${DateTime.now().millisecondsSinceEpoch}.xlsx';

      if (kIsWeb) {
        final bytes = excelSheet.encode();
        if (bytes != null) {
          web_download.downloadFileWeb(
            Uint8List.fromList(bytes),
            fileName,
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          );
        }
      } else {
        try {
          final output = await getApplicationDocumentsDirectory();
          final file = File('${output.path}/$fileName');
          await file.writeAsBytes(excelSheet.encode() ?? []);

          await Share.shareXFiles([
            XFile(
              file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ], text: 'Detalle de proveedor ${supplier.nombreProveedor}');
        } catch (e) {
          print('Error al guardar Excel: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Excel generado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error al exportar Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPDF = false);
      }
    }
  }

  Future<void> _exportSupplierReportToPDF() async {
    if (!mounted) return;

    setState(() => _isExportingPDF = true);

    try {
      final storeId = await UserPreferencesService().getIdTienda();
      Map<String, dynamic>? storeData;
      if (storeId != null) {
        storeData =
            await Supabase.instance.client
                .from('app_dat_tienda')
                .select('denominacion, direccion, ubicacion, phone, imagen_url')
                .eq('id', storeId)
                .maybeSingle();
      }

      final storeName = storeData?['denominacion'] as String? ?? 'VentIQ';
      final storeAddress = storeData?['direccion'] as String? ?? '';
      final storeLocation = storeData?['ubicacion'] as String? ?? '';
      final storePhone = storeData?['phone'] as String? ?? '';
      final storeLogoUrl = storeData?['imagen_url'] as String?;
      final logoBytes = await _downloadImageBytes(storeLogoUrl);

      // Calcular totales
      double totalVentas = 0;
      double totalCosto = 0;
      double totalGanancia = 0;

      for (var report in _supplierReports) {
        totalVentas += report.totalVentas;
        totalCosto += report.totalCosto;
        totalGanancia += report.totalGanancia;
      }

      final pdf = pw.Document();
      final dateLabel = _formatDateRangeLabel();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          build:
              (context) => [
                _buildPdfHeader(
                  logoBytes: logoBytes,
                  storeName: storeName,
                  storeAddress: storeAddress,
                  storeLocation: storeLocation,
                  storePhone: storePhone,
                  dateLabel: dateLabel,
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  'Resumen de Ventas por Proveedor',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColor.fromHex('#0F172A'),
                  ),
                ),
                if (_selectedWarehouseId != null) ...[
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Almacén: $_selectedWarehouseName',
                    style: pw.TextStyle(
                      fontSize: 11,
                      color: PdfColor.fromHex('#475569'),
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
                pw.SizedBox(height: 8),
                pw.Table(
                  border: pw.TableBorder.all(
                    color: PdfColors.grey300,
                    width: 0.8,
                  ),
                  columnWidths: {
                    0: const pw.FlexColumnWidth(3),
                    1: const pw.FlexColumnWidth(2),
                    2: const pw.FlexColumnWidth(2),
                    3: const pw.FlexColumnWidth(2),
                  },
                  children: [
                    // Encabezado
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#F1F5F9'),
                      ),
                      children: [
                        _pdfHeaderCell('Proveedor'),
                        _pdfHeaderCell('Ventas'),
                        _pdfHeaderCell('Costo'),
                        _pdfHeaderCell('Ganancia'),
                      ],
                    ),
                    // Filas de datos
                    ..._supplierReports.map((report) {
                      return pw.TableRow(
                        children: [
                          _pdfBodyCell(report.nombreProveedor),
                          _pdfBodyCell(
                            '\$${report.totalVentas.toStringAsFixed(2)}',
                          ),
                          _pdfBodyCell(
                            '\$${report.totalCosto.toStringAsFixed(2)}',
                          ),
                          _pdfBodyCell(
                            '\$${report.totalGanancia.toStringAsFixed(2)}',
                          ),
                        ],
                      );
                    }).toList(),
                    // Fila de TOTALES
                    pw.TableRow(
                      decoration: pw.BoxDecoration(
                        color: PdfColor.fromHex('#E2E8F0'),
                      ),
                      children: [
                        _pdfBodyCell('TOTAL', isBold: true),
                        _pdfBodyCell(
                          '\$${totalVentas.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                        _pdfBodyCell(
                          '\$${totalCosto.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                        _pdfBodyCell(
                          '\$${totalGanancia.toStringAsFixed(2)}',
                          isBold: true,
                        ),
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 8),
                pw.Container(
                  padding: const pw.EdgeInsets.all(12),
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromHex('#F8FAFC'),
                    borderRadius: pw.BorderRadius.circular(8),
                    border: pw.Border.all(color: PdfColors.grey300, width: 0.8),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Resumen General',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColor.fromHex('#0F172A'),
                        ),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total Ventas:',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                          pw.Text(
                            '\$${totalVentas.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total Costo:',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                          pw.Text(
                            '\$${totalCosto.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      pw.SizedBox(height: 4),
                      pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text(
                            'Total Ganancia:',
                            style: const pw.TextStyle(fontSize: 11),
                          ),
                          pw.Text(
                            '\$${totalGanancia.toStringAsFixed(2)}',
                            style: pw.TextStyle(
                              fontSize: 11,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColor.fromHex('#16A34A'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
        ),
      );

      final fileName =
          'Reporte_Proveedores_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf';

      if (kIsWeb) {
        await Printing.sharePdf(bytes: await pdf.save(), filename: fileName);
      } else {
        final output = await getTemporaryDirectory();
        final file = File('${output.path}/$fileName');
        await file.writeAsBytes(await pdf.save());

        await Share.shareXFiles([
          XFile(file.path, mimeType: 'application/pdf'),
        ], text: 'Reporte de proveedores $dateLabel');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Reporte exportado correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Error al exportar PDF: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPDF = false);
      }
    }
  }

  Future<void> _exportSupplierReportToExcel() async {
    if (!mounted) return;

    setState(() => _isExportingPDF = true);

    try {
      // Crear un nuevo Excel
      var excelSheet = excel.Excel.createExcel();
      var sheet = excelSheet['Sheet1'];

      // Calcular totales
      double totalVentas = 0;
      double totalCosto = 0;
      double totalGanancia = 0;

      for (var report in _supplierReports) {
        totalVentas += report.totalVentas;
        totalCosto += report.totalCosto;
        totalGanancia += report.totalGanancia;
      }

      // Agregar encabezado
      sheet.appendRow([excel.TextCellValue('Reporte de Ventas por Proveedor')]);
      sheet.appendRow([
        excel.TextCellValue(
          'Período: ${_startDate.day}/${_startDate.month}/${_startDate.year} - ${_endDate.day}/${_endDate.month}/${_endDate.year}',
        ),
      ]);
      if (_selectedWarehouseId != null) {
        sheet.appendRow([
          excel.TextCellValue('Almacén: $_selectedWarehouseName'),
        ]);
      }
      sheet.appendRow([]); // Fila vacía

      // Agregar encabezados de columnas
      sheet.appendRow([
        excel.TextCellValue('Proveedor'),
        excel.TextCellValue('Ventas'),
        excel.TextCellValue('Costo'),
        excel.TextCellValue('Ganancia'),
      ]);

      // Agregar datos de proveedores
      for (var report in _supplierReports) {
        sheet.appendRow([
          excel.TextCellValue(report.nombreProveedor),
          excel.DoubleCellValue(report.totalVentas),
          excel.DoubleCellValue(report.totalCosto),
          excel.DoubleCellValue(report.totalGanancia),
        ]);
      }

      // Agregar fila de totales
      sheet.appendRow([
        excel.TextCellValue('TOTAL'),
        excel.DoubleCellValue(totalVentas),
        excel.DoubleCellValue(totalCosto),
        excel.DoubleCellValue(totalGanancia),
      ]);

      // Guardar archivo
      final fileName =
          'Reporte_Proveedores_${DateTime.now().toString().split(' ')[0]}.xlsx';
      final bytes = excelSheet.encode();

      if (bytes != null) {
        // Convertir a Uint8List
        final uint8bytes = Uint8List.fromList(bytes);

        // Mostrar diálogo de guardado
        await Printing.sharePdf(bytes: uint8bytes, filename: fileName);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reporte exportado a Excel correctamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      print('Error al exportar Excel: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al exportar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExportingPDF = false);
      }
    }
  }

  void _onBottomNavTap(int index) {
    switch (index) {
      case 0: // Dashboard
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/dashboard',
          (route) => false,
        );
        break;
      case 1: // Ventas (current)
        break;
      case 2: // Productos
        Navigator.pushNamed(context, '/products-dashboard');
        break;
      case 3: // Inventario
        Navigator.pushNamed(context, '/inventory');
        break;
      case 4: // Configuración
        Navigator.pushNamed(context, '/settings');
        break;
    }
  }
}

class _AnalystFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AnalystFeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
