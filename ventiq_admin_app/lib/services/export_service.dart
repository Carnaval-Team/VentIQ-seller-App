import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../config/app_colors.dart';

// Importación condicional para web
import 'web_download_stub.dart' 
  if (dart.library.html) 'web_download_web.dart' as web_download;

class ExportService {
  static const String _appName = 'Vendedor Cuba Admin';
  
  // Cache para las fuentes
  static pw.Font? _regularFont;
  static pw.Font? _boldFont;
  
  /// Obtiene la fuente regular con soporte Unicode
  static Future<pw.Font> _getRegularFont() async {
    if (_regularFont == null) {
      _regularFont = await PdfGoogleFonts.robotoRegular();
    }
    return _regularFont!;
  }
  
  /// Obtiene la fuente bold con soporte Unicode
  static Future<pw.Font> _getBoldFont() async {
    if (_boldFont == null) {
      _boldFont = await PdfGoogleFonts.robotoBold();
    }
    return _boldFont!;
  }

  /// Exporta la lista de productos de un almacén y zona específica
  Future<void> exportInventoryProducts({
    required BuildContext context,
    required String warehouseName,
    required String zoneName,
    required List<InventoryProduct> products,
    required ExportFormat format,
  }) async {
    try {
      final fileName = _generateFileName(warehouseName, zoneName, format);

      late Uint8List fileBytes;
      late String mimeType;

      switch (format) {
        case ExportFormat.pdf:
          fileBytes = await _generatePDF(warehouseName, zoneName, products);
          mimeType = 'application/pdf';
          break;
        case ExportFormat.excel:
          fileBytes = await _generateExcel(warehouseName, zoneName, products);
          mimeType =
              'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
      }

      // Manejar descarga según la plataforma
      if (kIsWeb) {
        // Descarga directa en web con manejo de errores mejorado
        try {
          _downloadFileWeb(fileBytes, fileName, mimeType);
        } catch (webError) {
          print('Error específico de descarga web: $webError');
          // Mostrar mensaje específico para problemas de navegador
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Problema de compatibilidad del navegador. Intenta con Edge o actualiza tu navegador.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Reintentar',
                  onPressed: () => _downloadFileWeb(fileBytes, fileName, mimeType),
                ),
              ),
            );
          }
          return; // Salir temprano si hay error web
        }
      } else {
        // Guardar archivo temporalmente y compartir en móvil
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(fileBytes);

        // Compartir archivo
        await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: 'Inventario - $warehouseName - $zoneName',
          text:
              'Reporte de inventario generado el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
        );
      }

      // Mostrar mensaje de éxito
      if (context.mounted) {
        final message = kIsWeb 
            ? 'Archivo ${format.displayName} descargado exitosamente'
            : 'Archivo ${format.displayName} generado y compartido exitosamente';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error al exportar: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el archivo: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  /// Genera el nombre del archivo basado en los parámetros
  String _generateFileName(
    String warehouseName,
    String zoneName,
    ExportFormat format,
  ) {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
    final cleanWarehouse = _cleanFileName(warehouseName);
    final cleanZone = _cleanFileName(zoneName);

    return 'Inventario_${cleanWarehouse}_${cleanZone}_$dateStr.${format.extension}';
  }

  /// Limpia el nombre del archivo de caracteres especiales
  String _cleanFileName(String name) {
    return name
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .trim();
  }

  /// Genera un archivo PDF con el inventario
  Future<Uint8List> _generatePDF(
    String warehouseName,
    String zoneName,
    List<InventoryProduct> products,
  ) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateFormatter = DateFormat('dd/MM/yyyy');
    final timeFormatter = DateFormat('HH:mm');
    
    // Cargar fuentes Unicode
    final regularFont = await _getRegularFont();
    final boldFont = await _getBoldFont();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Encabezado
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Título principal
                pw.Text(
                  'REPORTE DE INVENTARIO',
                  style: pw.TextStyle(
                    fontSize: 24,
                    font: boldFont,
                  ),
                ),
                pw.SizedBox(height: 8),

                // Subtítulo con almacén
                pw.Text(
                  'Almacén: $warehouseName',
                  style: pw.TextStyle(
                    fontSize: 18,
                    font: boldFont,
                  ),
                ),
                pw.SizedBox(height: 4),

                // Subtítulo con zona/área
                pw.Text(
                  'Área: $zoneName',
                  style: pw.TextStyle(
                    fontSize: 16,
                    font: regularFont,
                  ),
                ),
                pw.SizedBox(height: 16),

                // Información adicional
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total de productos: ${products.length}',
                      style: pw.TextStyle(fontSize: 12, font: regularFont),
                    ),
                    pw.Text(
                      'Generado por: $_appName',
                      style: pw.TextStyle(fontSize: 12, font: regularFont),
                    ),
                  ],
                ),
                pw.SizedBox(height: 24),
              ],
            ),

            // Tabla de productos
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3), // Nombre
                1: const pw.FlexColumnWidth(1.5), // Cant. Inicial
                2: const pw.FlexColumnWidth(1.5), // Entradas
                3: const pw.FlexColumnWidth(1.5), // Extracciones
                4: const pw.FlexColumnWidth(1.5), // Ventas
                5: const pw.FlexColumnWidth(1.5), // Cant. Final
              },
              children: [
                // Encabezado de la tabla
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableHeader('Nombre del Producto', font: boldFont),
                    _buildTableHeader('Cantidad Inicial', font: boldFont),
                    _buildTableHeader('Entradas', font: boldFont),
                    _buildTableHeader('Extracciones', font: boldFont),
                    _buildTableHeader('Ventas', font: boldFont),
                    _buildTableHeader('Cantidad Final', font: boldFont),
                  ],
                ),

                // Filas de productos
                ...products.map(
                  (product) {
                    // Calcular movimientos basados en los datos disponibles
                    final entradas = 0.0; // Por ahora 0, se puede calcular si hay datos de movimientos
                    final extracciones = 0.0; // Por ahora 0, se puede calcular si hay datos de movimientos
                    final ventas = product.cantidadInicial > product.cantidadFinal 
                        ? product.cantidadInicial - product.cantidadFinal 
                        : 0.0; // Diferencia como aproximación de ventas
                    
                    return pw.TableRow(
                      children: [
                        _buildTableCell(product.nombreProducto, font: regularFont),
                        _buildTableCell(
                          product.cantidadInicial.toStringAsFixed(0),
                          font: regularFont,
                        ),
                        _buildTableCell(
                          entradas.toStringAsFixed(0),
                          font: regularFont,
                        ),
                        _buildTableCell(
                          extracciones.toStringAsFixed(0),
                          font: regularFont,
                        ),
                        _buildTableCell(
                          ventas.toStringAsFixed(0),
                          font: regularFont,
                        ),
                        _buildTableCell(
                          product.cantidadFinal.toStringAsFixed(0),
                          font: regularFont,
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),

            pw.SizedBox(height: 24),

            // Resumen
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'RESUMEN',
                    style: pw.TextStyle(
                      fontSize: 14,
                      font: boldFont,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('• Total de productos: ${products.length}', style: pw.TextStyle(font: regularFont)),
                  pw.Text(
                    '• Productos con stock: ${products.where((p) => p.cantidadFinal > 0).length}',
                    style: pw.TextStyle(font: regularFont),
                  ),
                  pw.Text(
                    '• Productos sin stock: ${products.where((p) => p.cantidadFinal <= 0).length}',
                    style: pw.TextStyle(font: regularFont),
                  ),
                  pw.Text(
                    '• Stock total: ${products.fold<double>(0, (sum, p) => sum + p.cantidadFinal).toStringAsFixed(0)} unidades',
                    style: pw.TextStyle(font: regularFont),
                  ),
                ],
              ),
            ),
          ];
        },
        footer: (pw.Context context) {
          return pw.Container(
            alignment: pw.Alignment.centerRight,
            margin: const pw.EdgeInsets.only(top: 16),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Fecha: ${dateFormatter.format(now)} - ${timeFormatter.format(now)}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                    font: regularFont,
                  ),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey600,
                    font: regularFont,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  /// Genera un archivo Excel con el inventario
  Future<Uint8List> _generateExcel(
    String warehouseName,
    String zoneName,
    List<InventoryProduct> products,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Inventario'];

    // Configurar el ancho de las columnas (nuevas 6 columnas solicitadas)
    sheet.setColumnWidth(0, 30); // Nombre
    sheet.setColumnWidth(1, 15); // Cantidad Inicial
    sheet.setColumnWidth(2, 12); // Entradas
    sheet.setColumnWidth(3, 12); // Extracciones
    sheet.setColumnWidth(4, 12); // Ventas
    sheet.setColumnWidth(5, 15); // Cantidad Final

    int currentRow = 0;

    // Título principal
    final titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    titleCell.value = TextCellValue('REPORTE DE INVENTARIO');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Left,
    );
    currentRow += 2;

    // Información del almacén y zona
    final warehouseCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    warehouseCell.value = TextCellValue('Almacén: $warehouseName');
    warehouseCell.cellStyle = CellStyle(bold: true, fontSize: 14);
    currentRow++;

    final zoneCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    zoneCell.value = TextCellValue('Área: $zoneName');
    zoneCell.cellStyle = CellStyle(bold: true, fontSize: 12);
    currentRow += 2;

    // Información adicional
    final infoCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    infoCell.value = TextCellValue('Total de productos: ${products.length}');
    currentRow++;

    final dateCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    dateCell.value = TextCellValue(
      'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
    );
    currentRow += 2;

    // Encabezados de la tabla (nuevas 6 columnas solicitadas)
    final headers = [
      'Nombre del Producto',
      'Cantidad Inicial',
      'Entradas',
      'Extracciones',
      'Ventas',
      'Cantidad Final',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.grey50,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    currentRow++;

    // Datos de los productos (nuevas 6 columnas solicitadas)
    for (final product in products) {
      // Calcular movimientos basados en los datos disponibles
      final entradas = 0.0; // Por ahora 0, se puede calcular si hay datos de movimientos
      final extracciones = 0.0; // Por ahora 0, se puede calcular si hay datos de movimientos
      final ventas = product.cantidadInicial > product.cantidadFinal 
          ? product.cantidadInicial - product.cantidadFinal 
          : 0.0; // Diferencia como aproximación de ventas
      
      final rowData = [
        product.nombreProducto,
        product.cantidadInicial.toStringAsFixed(0),
        entradas.toStringAsFixed(0),
        extracciones.toStringAsFixed(0),
        ventas.toStringAsFixed(0),
        product.cantidadFinal.toStringAsFixed(0),
      ];

      for (int i = 0; i < rowData.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow),
        );
        cell.value = TextCellValue(rowData[i]);

        // Aplicar color basado en el stock
        if (i == 5) {
          // Columna de cantidad final (índice 5)
          final cantidad = product.cantidadFinal;
          if (cantidad <= 0) {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.red);
          } else if (cantidad <= 10) {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.orange);
          } else {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.green);
          }
        }
      }
      currentRow++;
    }

    // Resumen al final
    currentRow += 2;
    final summaryCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    summaryCell.value = TextCellValue('RESUMEN');
    summaryCell.cellStyle = CellStyle(bold: true, fontSize: 14);
    currentRow++;

    final summaryData = [
      'Total de productos: ${products.length}',
      'Productos con stock: ${products.where((p) => p.cantidadFinal > 0).length}',
      'Productos sin stock: ${products.where((p) => p.cantidadFinal <= 0).length}',
      'Stock total: ${products.fold<double>(0, (sum, p) => sum + p.cantidadFinal).toStringAsFixed(0)} unidades',
    ];

    for (final summary in summaryData) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      );
      cell.value = TextCellValue(summary);
      currentRow++;
    }

    // excel.encode() devuelve List<int>, convertimos a Uint8List
    return Uint8List.fromList(excel.encode()!);
  }

  /// Construye una celda de encabezado para la tabla PDF
  pw.Widget _buildTableHeader(String text, {PdfColor? color, pw.Font? font}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10, 
          font: font,
          color: color,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Construye una celda de datos para la tabla PDF
  pw.Widget _buildTableCell(String text, {pw.Font? font}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 9, font: font),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// Genera un archivo Excel para inventario simple
  Future<String?> generateInventoryExcel({
    required List<Map<String, dynamic>> inventoryData,
    required String warehouseName,
    DateTime? filterDate,
  }) async {
    try {
      final excel = Excel.createExcel();
      final sheet = excel['Inventario'];

      // Configurar el ancho de las columnas
      sheet.setColumnWidth(0, 25); // Nombre
      sheet.setColumnWidth(1, 15); // Stock Disponible
      sheet.setColumnWidth(2, 15); // Cantidad Inicial
      sheet.setColumnWidth(3, 15); // Cantidad Final
      sheet.setColumnWidth(4, 15); // Precio Venta
      sheet.setColumnWidth(5, 15); // Costo Promedio

      int currentRow = 0;

      // Título principal
      final titleCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      );
      titleCell.value = TextCellValue('REPORTE DE INVENTARIO');
      titleCell.cellStyle = CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: HorizontalAlign.Left,
      );
      currentRow += 2;

      // Información del almacén
      final warehouseCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      );
      warehouseCell.value = TextCellValue('Almacén: $warehouseName');
      warehouseCell.cellStyle = CellStyle(bold: true, fontSize: 14);
      currentRow++;

      // Fecha del filtro o histórico
      final dateCell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
      );
      final dateStr = filterDate != null
          ? 'Fecha: ${DateFormat('dd/MM/yyyy').format(filterDate)}'
          : 'Período: Histórico';
      dateCell.value = TextCellValue(dateStr);
      dateCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      currentRow += 2;

      // Agrupar por almacén y ubicación usando método común
      final groupedData = _groupInventoryData(inventoryData);

      // Generar contenido por almacén y ubicación
      for (final almacenEntry in groupedData.entries) {
        final almacenName = almacenEntry.key;

        // Título del almacén
        final almacenTitleCell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
        );
        almacenTitleCell.value = TextCellValue('ALMACÉN: $almacenName');
        almacenTitleCell.cellStyle = CellStyle(
          bold: true,
          fontSize: 14,
          backgroundColorHex: ExcelColor.blue,
        );
        currentRow += 2;

        for (final ubicacionEntry in almacenEntry.value.entries) {
          final ubicacionName = ubicacionEntry.key;
          final productos = ubicacionEntry.value;

          // Subtítulo de ubicación
          final ubicacionTitleCell = sheet.cell(
            CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
          );
          ubicacionTitleCell.value = TextCellValue('Ubicación: $ubicacionName');
          ubicacionTitleCell.cellStyle = CellStyle(
            bold: true,
            fontSize: 12,
            backgroundColorHex: ExcelColor.lightBlue,
          );
          currentRow += 1;

          // Encabezados de la tabla
          final headers = [
            'Nombre',
            'Cantidad Final',
            'Cantidad Inicial',
            'Vendido',
            'Precio Venta',
            'Costo Promedio',
          ];

          for (int i = 0; i < headers.length; i++) {
            final cell = sheet.cell(
              CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow),
            );
            cell.value = TextCellValue(headers[i]);
            cell.cellStyle = CellStyle(
              bold: true,
              backgroundColorHex: ExcelColor.grey50,
              horizontalAlign: HorizontalAlign.Center,
            );
          }
          currentRow++;

          // Datos de los productos
          for (final producto in productos) {
            final rowData = [
              producto['nombre_producto']?.toString() ?? 'Sin nombre',
              (producto['stock_disponible'] ?? 0).toString(),
              (producto['cantidad_inicial'] ?? 0).toString(),
              ((producto['cantidad_inicial'] ?? 0) -
                      (producto['stock_disponible'] ?? 0))
                  .toString(),
              '\$${(producto['precio_venta'] ?? 0).toStringAsFixed(2)}',
              '\$${(producto['costo_promedio'] ?? 0).toStringAsFixed(2)}',
            ];

            for (int i = 0; i < rowData.length; i++) {
              final cell = sheet.cell(
                CellIndex.indexByColumnRow(
                  columnIndex: i,
                  rowIndex: currentRow,
                ),
              );
              cell.value = TextCellValue(rowData[i]);

              // No color coding for stock levels
            }
            currentRow++;
          }

          currentRow += 1; // Espacio entre ubicaciones
        }

        currentRow += 1; // Espacio entre almacenes
      }

      // Guardar archivo
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'inventario_${_cleanFileName(warehouseName)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
      final file = File('${directory.path}/$fileName');

      final bytes = excel.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        return file.path;
      }

      return null;
    } catch (e) {
      print('Error generando Excel: $e');
      rethrow;
    }
  }

  /// Genera un archivo PDF para inventario simple
  Future<String?> generateInventoryPdf({
    required List<Map<String, dynamic>> inventoryData,
    required String warehouseName,
    DateTime? filterDate,
  }) async {
    try {
      final pdf = pw.Document();
      final now = DateTime.now();
      final dateFormatter = DateFormat('dd/MM/yyyy');
      final timeFormatter = DateFormat('HH:mm');
      
      // Cargar fuentes Unicode
      final regularFont = await _getRegularFont();
      final boldFont = await _getBoldFont();

      // Agrupar por almacén y ubicación usando método común
      final groupedData = _groupInventoryData(inventoryData);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            final widgets = <pw.Widget>[];

            // Encabezado
            widgets.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'REPORTE DE INVENTARIO',
                    style: pw.TextStyle(
                      fontSize: 24,
                      font: boldFont,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Almacén: $warehouseName',
                    style: pw.TextStyle(
                      fontSize: 18,
                      font: boldFont,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    filterDate != null 
                        ? 'Fecha: ${dateFormatter.format(filterDate)}'
                        : 'Período: Histórico',
                    style: pw.TextStyle(
                      fontSize: 16,
                      font: regularFont,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'Total de productos: ${inventoryData.length}',
                    style: pw.TextStyle(fontSize: 12, font: regularFont),
                  ),
                  pw.SizedBox(height: 24),
                ],
              ),
            );

            // Contenido por almacén y ubicación
            for (final almacenEntry in groupedData.entries) {
              final almacenName = almacenEntry.key;

              widgets.add(
                pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.all(8),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.blue100,
                    border: pw.Border.all(color: PdfColors.blue),
                  ),
                  child: pw.Text(
                    'ALMACÉN: $almacenName',
                    style: pw.TextStyle(
                      fontSize: 14,
                      font: boldFont,
                    ),
                  ),
                ),
              );

              widgets.add(pw.SizedBox(height: 8));

              for (final ubicacionEntry in almacenEntry.value.entries) {
                final ubicacionName = ubicacionEntry.key;
                final productos = ubicacionEntry.value;

                widgets.add(
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.all(6),
                    decoration: pw.BoxDecoration(
                      color: PdfColors.grey200,
                      border: pw.Border.all(color: PdfColors.grey400),
                    ),
                    child: pw.Text(
                      'Ubicación: $ubicacionName',
                      style: pw.TextStyle(
                        fontSize: 12,
                        font: boldFont,
                      ),
                    ),
                  ),
                );

                widgets.add(pw.SizedBox(height: 4));

                // Tabla de productos
                widgets.add(
                  pw.Table(
                    border: pw.TableBorder.all(
                      color: PdfColors.grey400,
                      width: 0.5,
                    ),
                    columnWidths: {
                      0: const pw.FlexColumnWidth(3), // Nombre
                      1: const pw.FlexColumnWidth(1.5), // Stock Disponible
                      2: const pw.FlexColumnWidth(1.5), // Cant. Inicial
                      3: const pw.FlexColumnWidth(1.5), // Cant. Final
                      4: const pw.FlexColumnWidth(1.5), // Precio Venta
                      5: const pw.FlexColumnWidth(1.5), // Costo Promedio
                    },
                    children: [
                      // Encabezado de la tabla
                      pw.TableRow(
                        decoration: const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        children: [
                          _buildTableHeader('Nombre', font: boldFont),
                          _buildTableHeader('Cantidad final', font: boldFont),
                          _buildTableHeader('Cant. Inicial', font: boldFont),
                          _buildTableHeader('Vendido', font: boldFont),
                          _buildTableHeader('Precio Venta', font: boldFont),
                          _buildTableHeader('Costo Promedio', font: boldFont),
                        ],
                      ),

                      // Filas de productos
                      ...productos.map(
                        (producto) => pw.TableRow(
                          children: [
                            _buildTableCell(
                              producto['nombre_producto']?.toString() ??
                                  'Sin nombre',
                              font: regularFont,
                            ),
                            _buildTableCell(
                              (producto['stock_disponible'] ?? 0).toString(),
                              font: regularFont,
                            ),
                            _buildTableCell(
                              (producto['cantidad_inicial'] ?? 0).toString(),
                              font: regularFont,
                            ),
                            _buildTableCell(
                              ((producto['cantidad_inicial'] ?? 0) -
                                      (producto['stock_disponible'] ?? 0))
                                  .toString(),
                              font: regularFont,
                            ),
                            _buildTableCell(
                              '\$${(producto['precio_venta'] ?? 0).toStringAsFixed(2)}',
                              font: regularFont,
                            ),
                            _buildTableCell(
                              '\$${(producto['costo_promedio'] ?? 0).toStringAsFixed(2)}',
                              font: regularFont,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );

                widgets.add(pw.SizedBox(height: 16));
              }
            }

            return widgets;
          },
          footer: (pw.Context context) {
            return pw.Container(
              alignment: pw.Alignment.centerRight,
              margin: const pw.EdgeInsets.only(top: 16),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Fecha: ${dateFormatter.format(now)} - ${timeFormatter.format(now)}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                      font: regularFont,
                    ),
                  ),
                  pw.Text(
                    'Página ${context.pageNumber} de ${context.pagesCount}',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey600,
                      font: regularFont,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );

      // Guardar archivo
      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'inventario_${_cleanFileName(warehouseName)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
      final file = File('${directory.path}/$fileName');

      final bytes = await pdf.save();
      await file.writeAsBytes(bytes);

      return file.path;
    } catch (e) {
      print('Error generando PDF: $e');
      rethrow;
    }
  }

  /// Exporta inventario simple y lo comparte directamente
  Future<void> exportInventorySimple({
    required BuildContext context,
    required List<Map<String, dynamic>> inventoryData,
    required String warehouseName,
    DateTime? filterDateFrom,
    DateTime? filterDateTo,
    required String format,
  }) async {
    try {
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final cleanWarehouse = _cleanFileName(warehouseName);

      late Uint8List fileBytes;
      late String mimeType;
      late String fileName;

      if (format == 'excel') {
        // Convertir datos a InventoryProduct para usar la misma estructura que PDF
        final products = _convertMapDataToInventoryProducts(inventoryData);
        
        // Generar Excel con la misma estructura que PDF
        fileBytes = await _generateSimpleExcel(warehouseName, products);
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        fileName = 'inventario_${cleanWarehouse}_$dateStr.xlsx';
      } else {
        // Generar PDF
        final pdf = pw.Document();
        final dateFormatter = DateFormat('dd/MM/yyyy');
        final timeFormatter = DateFormat('HH:mm');
        
        // Cargar fuentes Unicode
        final regularFont = await _getRegularFont();
        final boldFont = await _getBoldFont();


        // Agrupar por almacén y ubicación usando método común
        final groupedDataPdf = _groupInventoryData(inventoryData);

        // Crear PDF completo siempre (sin verificación de cantidad)
        pdf.addPage(
            pw.MultiPage(
              pageFormat: PdfPageFormat.a4,
              margin: const pw.EdgeInsets.all(32),
              build: (pw.Context context) {
                final widgets = <pw.Widget>[];

                // Encabezado
                widgets.add(
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'REPORTE DE INVENTARIO',
                        style: pw.TextStyle(fontSize: 24, font: boldFont),
                      ),
                      pw.SizedBox(height: 8),
                      pw.Text(
                        'Almacén: $warehouseName',
                        style: pw.TextStyle(fontSize: 18, font: boldFont),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        _buildPeriodText(filterDateFrom, filterDateTo, dateFormatter, now),
                        style: pw.TextStyle(fontSize: 16, font: regularFont),
                      ),
                      pw.SizedBox(height: 16),
                      pw.Text(
                        'Total de productos: ${inventoryData.length}',
                        style: pw.TextStyle(fontSize: 12, font: regularFont),
                      ),
                      pw.SizedBox(height: 24),
                    ],
                  ),
                );

                // Contenido limitado por almacén y ubicación
                for (final almacenEntry in groupedDataPdf.entries) {
                  final almacenName = almacenEntry.key;

                  widgets.add(
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue100,
                        border: pw.Border.all(color: PdfColors.blue300),
                      ),
                      child: pw.Text(
                        'ALMACÉN: $almacenName',
                        style: pw.TextStyle(fontSize: 14, font: boldFont),
                      ),
                    ),
                  );

                  widgets.add(pw.SizedBox(height: 8));

                  for (final ubicacionEntry in almacenEntry.value.entries) {
                    final ubicacionName = ubicacionEntry.key;
                    final productos = ubicacionEntry.value;

                    widgets.add(
                      pw.Container(
                        width: double.infinity,
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(
                          color: PdfColors.grey200,
                          border: pw.Border.all(color: PdfColors.grey400),
                        ),
                        child: pw.Text(
                          'Ubicación: $ubicacionName',
                          style: pw.TextStyle(fontSize: 12, font: boldFont),
                        ),
                      ),
                    );

                    widgets.add(pw.SizedBox(height: 4));

                    // Tabla de productos
                    
                    widgets.add(
                      pw.Table(
                        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
                        columnWidths: {
                          0: const pw.FlexColumnWidth(2.5),
                          1: const pw.FlexColumnWidth(1),
                          2: const pw.FlexColumnWidth(1),
                          3: const pw.FlexColumnWidth(1),
                          4: const pw.FlexColumnWidth(1),
                          5: const pw.FlexColumnWidth(1),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                            children: [
                              _buildTableHeader('Nombre', font: boldFont),
                              _buildTableHeader('Cant. Inicial', font: boldFont),
                              _buildTableHeader('Entradas', font: boldFont),
                              _buildTableHeader('Extracciones', font: boldFont),
                              _buildTableHeader('Ventas', font: boldFont),
                              _buildTableHeader('Cant. Final', font: boldFont),
                            ],
                          ),
                          ...productos.map(
                            (producto) => pw.TableRow(
                              children: [
                                _buildTableCell(
                                  producto['nombre_producto']?.toString() ?? 'Sin nombre',
                                  font: regularFont,
                                ),
                                _buildTableCell(
                                  (double.tryParse(producto['cantidad_inicial']?.toString() ?? '0') ?? 0).toStringAsFixed(1),
                                  font: regularFont,
                                ),
                                _buildTableCell(
                                  (double.tryParse(producto['entradas_periodo']?.toString() ?? '0') ?? 0).toStringAsFixed(1),
                                  font: regularFont,
                                ),
                                _buildTableCell(
                                  (double.tryParse(producto['extracciones_periodo']?.toString() ?? '0') ?? 0).toStringAsFixed(1),
                                  font: regularFont,
                                ),
                                _buildTableCell(
                                  (double.tryParse(producto['ventas_periodo']?.toString() ?? '0') ?? 0).toStringAsFixed(1),
                                  font: regularFont,
                                ),
                                _buildTableCell(
                                  (double.tryParse(producto['cantidad_final']?.toString() ?? '0') ?? 0).toStringAsFixed(1),
                                  font: regularFont,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );

                    widgets.add(pw.SizedBox(height: 16));
                  }
                }

                return widgets;
              },
              footer: (pw.Context context) {
                return pw.Container(
                  alignment: pw.Alignment.centerRight,
                  margin: const pw.EdgeInsets.only(top: 16),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'Fecha: ${dateFormatter.format(now)} - ${timeFormatter.format(now)}',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                          font: regularFont,
                        ),
                      ),
                      pw.Text(
                        'Página ${context.pageNumber} de ${context.pagesCount}',
                        style: pw.TextStyle(
                          fontSize: 10,
                          color: PdfColors.grey600,
                          font: regularFont,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );

        fileBytes = await pdf.save();
        mimeType = 'application/pdf';
        fileName = 'inventario_${cleanWarehouse}_$dateStr.pdf';
      }

      // Manejar descarga según la plataforma
      if (kIsWeb) {
        // Descarga directa en web con manejo de errores mejorado
        try {
          _downloadFileWeb(fileBytes, fileName, mimeType);
        } catch (webError) {
          print('Error específico de descarga web: $webError');
          // Mostrar mensaje específico para problemas de navegador
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Problema de compatibilidad del navegador. Intenta con Edge o actualiza tu navegador.',
                ),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'Reintentar',
                  onPressed: () => _downloadFileWeb(fileBytes, fileName, mimeType),
                ),
              ),
            );
          }
          return; // Salir temprano si hay error web
        }
      } else {
        // Guardar archivo temporalmente y compartir en móvil
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(fileBytes);

        // Compartir archivo
        await Share.shareXFiles(
          [XFile(file.path, mimeType: mimeType)],
          subject: 'Inventario - $warehouseName',
          text:
              'Reporte de inventario generado el ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
        );
      }

      // Mostrar mensaje de éxito
      if (context.mounted) {
        final message = kIsWeb 
            ? 'Archivo ${format.toUpperCase()} descargado exitosamente'
            : 'Archivo ${format.toUpperCase()} generado y compartido exitosamente';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      print('Error al exportar inventario simple: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al generar el archivo: $e'),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      rethrow;
    }
  }

  /// Descarga un archivo en web usando AnchorElement
  void _downloadFileWeb(Uint8List bytes, String fileName, String mimeType) {
    if (kIsWeb) {
      web_download.downloadFileWeb(bytes, fileName, mimeType);
    }
  }

  /// Abre un archivo usando el visor predeterminado del sistema
  Future<void> openFile(String filePath) async {
    try {
      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      print('Error abriendo archivo: $e');
      rethrow;
    }
  }

  /// Helper method to build period text for date range display
  String _buildPeriodText(DateTime? filterDateFrom, DateTime? filterDateTo, DateFormat dateFormatter, DateTime now) {
    if (filterDateFrom != null && filterDateTo != null) {
      return 'Período: ${dateFormatter.format(filterDateFrom)} - ${dateFormatter.format(filterDateTo)}';
    } else if (filterDateFrom != null) {
      return 'Desde: ${dateFormatter.format(filterDateFrom)}';
    } else if (filterDateTo != null) {
      return 'Hasta: ${dateFormatter.format(filterDateTo)}';
    } else {
      return 'Período: Histórico';
    }
  }
  
  /// Método común para agrupar datos de inventario por almacén y ubicación
  Map<String, Map<String, List<Map<String, dynamic>>>> _groupInventoryData(
    List<Map<String, dynamic>> inventoryData,
  ) {
    final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};

    for (final item in inventoryData) {
      final almacen = item['almacen']?.toString() ?? 'Sin almacén';
      final ubicacion = item['ubicacion']?.toString() ?? 'Sin ubicación';
      final idUbicacion = item['id_ubicacion'];

      // Skip items without location or with null id_ubicacion
      if (ubicacion == 'Sin ubicación' || ubicacion == 'SIN UBICACIÓN' || idUbicacion == null) continue;

      if (!groupedData.containsKey(almacen)) {
        groupedData[almacen] = {};
      }
      if (!groupedData[almacen]!.containsKey(ubicacion)) {
        groupedData[almacen]![ubicacion] = [];
      }
      groupedData[almacen]![ubicacion]!.add(item);
    }
    
    return groupedData;
  }
  
  /// Convierte datos Map a InventoryProduct para usar la misma estructura que PDF
  List<InventoryProduct> _convertMapDataToInventoryProducts(
    List<Map<String, dynamic>> inventoryData,
  ) {
    return inventoryData.map((item) {
      return InventoryProduct(
        id: int.tryParse(item['id']?.toString() ?? '0') ?? 0,
        skuProducto: item['sku_producto']?.toString() ?? '',
        nombreProducto: item['nombre_producto']?.toString() ?? 'Sin nombre',
        idCategoria: int.tryParse(item['id_categoria']?.toString() ?? '0') ?? 0,
        categoria: item['categoria']?.toString() ?? '',
        idSubcategoria: int.tryParse(item['id_subcategoria']?.toString() ?? '0') ?? 0,
        subcategoria: item['subcategoria']?.toString() ?? '',
        idTienda: int.tryParse(item['id_tienda']?.toString() ?? '0') ?? 0,
        tienda: item['tienda']?.toString() ?? '',
        idAlmacen: int.tryParse(item['id_almacen']?.toString() ?? '0') ?? 0,
        almacen: item['almacen']?.toString() ?? '',
        idUbicacion: int.tryParse(item['id_ubicacion']?.toString() ?? '0') ?? 0,
        ubicacion: item['ubicacion']?.toString() ?? '',
        idVariante: int.tryParse(item['id_variante']?.toString() ?? ''),
        variante: item['variante']?.toString() ?? '',
        idOpcionVariante: int.tryParse(item['id_opcion_variante']?.toString() ?? ''),
        opcionVariante: item['opcion_variante']?.toString() ?? '',
        idPresentacion: int.tryParse(item['id_presentacion']?.toString() ?? ''),
        presentacion: item['presentacion']?.toString() ?? 'N/A',
        cantidadInicial: double.tryParse(item['cantidad_inicial']?.toString() ?? '0') ?? 0,
        cantidadFinal: double.tryParse(item['cantidad_final']?.toString() ?? '0') ?? 0,
        entradasPeriodo: double.tryParse(item['entradas_periodo']?.toString() ?? '0') ?? 0,
        extraccionesPeriodo: double.tryParse(item['extracciones_periodo']?.toString() ?? '0') ?? 0,
        ventasPeriodo: double.tryParse(item['ventas_periodo']?.toString() ?? '0') ?? 0,
        stockDisponible: double.tryParse(item['stock_disponible']?.toString() ?? '0') ?? 0,
        stockReservado: double.tryParse(item['stock_reservado']?.toString() ?? '0') ?? 0,
        stockDisponibleAjustado: double.tryParse(item['stock_disponible_ajustado']?.toString() ?? '0') ?? 0,
        esVendible: item['es_vendible'] == true || item['es_vendible']?.toString().toLowerCase() == 'true',
        esInventariable: item['es_inventariable'] == true || item['es_inventariable']?.toString().toLowerCase() == 'true',
        esElaborado: item['es_elaborado'] == true || item['es_elaborado']?.toString().toLowerCase() == 'true',
        precioVenta: double.tryParse(item['precio_venta']?.toString() ?? '0'),
        costoPromedio: double.tryParse(item['costo_promedio']?.toString() ?? '0'),
        margenActual: double.tryParse(item['margen_actual']?.toString() ?? '0'),
        clasificacionAbc: int.tryParse(item['clasificacion_abc']?.toString() ?? '0') ?? 0,
        abcDescripcion: item['abc_descripcion']?.toString() ?? '',
        fechaUltimaActualizacion: DateTime.tryParse(item['fecha_ultima_actualizacion']?.toString() ?? '') ?? DateTime.now(),
        totalCount: int.tryParse(item['total_count']?.toString() ?? '0') ?? 0,
      );
    }).toList();
  }
  
  /// Genera Excel con la misma estructura que PDF (6 columnas)
  Future<Uint8List> _generateSimpleExcel(
    String warehouseName,
    List<InventoryProduct> products,
  ) async {
    final excel = Excel.createExcel();
    final sheet = excel['Inventario'];

    // Configurar el ancho de las columnas (igual que PDF)
    sheet.setColumnWidth(0, 30); // Nombre del Producto
    sheet.setColumnWidth(1, 15); // SKU
    sheet.setColumnWidth(2, 12); // Cant. Inicial
    sheet.setColumnWidth(3, 12); // Cant. Actual
    sheet.setColumnWidth(4, 15); // Precio Unitario
    sheet.setColumnWidth(5, 15); // Presentación

    int currentRow = 0;

    // Título principal
    final titleCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    titleCell.value = TextCellValue('REPORTE DE INVENTARIO');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Left,
    );
    currentRow += 2;

    // Información del almacén
    final warehouseCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    warehouseCell.value = TextCellValue('Almacén: $warehouseName');
    warehouseCell.cellStyle = CellStyle(bold: true, fontSize: 14);
    currentRow += 2;

    // Información adicional
    final infoCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    infoCell.value = TextCellValue('Total de productos: ${products.length}');
    currentRow++;

    final dateCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    dateCell.value = TextCellValue(
      'Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
    );
    currentRow += 2;

    // Encabezados de la tabla actualizados
    final headers = [
      'Nombre',
      'Cant. Inicial',
      'Entradas',
      'Extracciones',
      'Ventas',
      'Cant. Final',
    ];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow),
      );
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.grey50,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    currentRow++;

    // Datos de los productos con los nuevos campos
    for (final product in products) {
      final rowData = [
        product.nombreProducto,
        product.cantidadInicial.toStringAsFixed(1),
        (product.entradasPeriodo ?? 0).toStringAsFixed(1),
        (product.extraccionesPeriodo ?? 0).toStringAsFixed(1),
        (product.ventasPeriodo ?? 0).toStringAsFixed(1),
        product.cantidadFinal.toStringAsFixed(1),
      ];

      for (int i = 0; i < rowData.length; i++) {
        final cell = sheet.cell(
          CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow),
        );
        cell.value = TextCellValue(rowData[i]);

        // Aplicar color basado en el stock en la columna Cant. Final
        if (i == 5) {
          // Columna de cantidad final (índice 5)
          final cantidad = product.cantidadFinal;
          if (cantidad <= 0) {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.red);
          } else if (cantidad <= 10) {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.orange);
          } else {
            cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.green);
          }
        }
      }
      currentRow++;
    }

    // Resumen al final
    currentRow += 2;
    final summaryCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    summaryCell.value = TextCellValue('RESUMEN');
    summaryCell.cellStyle = CellStyle(bold: true, fontSize: 14);
    currentRow++;

    final totalCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    totalCell.value = TextCellValue('• Total de productos: ${products.length}');
    currentRow++;

    final stockCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    stockCell.value = TextCellValue(
      '• Productos con stock: ${products.where((p) => p.cantidadFinal > 0).length}',
    );
    currentRow++;

    final noStockCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    noStockCell.value = TextCellValue(
      '• Productos sin stock: ${products.where((p) => p.cantidadFinal <= 0).length}',
    );
    currentRow++;

    final totalStockCell = sheet.cell(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow),
    );
    totalStockCell.value = TextCellValue(
      '• Stock total: ${products.fold<double>(0, (sum, p) => sum + p.cantidadFinal).toStringAsFixed(0)} unidades',
    );

    return Uint8List.fromList(excel.encode()!);
  }
}

/// Enumeración para los formatos de exportación
enum ExportFormat {
  pdf('PDF', 'pdf'),
  excel('Excel', 'xlsx');

  const ExportFormat(this.displayName, this.extension);

  final String displayName;
  final String extension;
}
