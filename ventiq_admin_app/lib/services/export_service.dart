import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import '../models/inventory.dart';
import '../models/warehouse.dart';
import '../config/app_colors.dart';

class ExportService {
  static const String _appName = 'VentIQ Admin';
  
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
          mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
          break;
      }
      
      // Guardar archivo temporalmente
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      
      // Compartir archivo
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        subject: 'Inventario - $warehouseName - $zoneName',
        text: 'Reporte de inventario generado el ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}',
      );
      
      // Mostrar mensaje de éxito
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archivo ${format.displayName} generado exitosamente'),
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
  String _generateFileName(String warehouseName, String zoneName, ExportFormat format) {
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
  Future<Uint8List> _generatePDF(String warehouseName, String zoneName, List<InventoryProduct> products) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final dateFormatter = DateFormat('dd/MM/yyyy');
    final timeFormatter = DateFormat('HH:mm');
    
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
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 8),
                
                // Subtítulo con almacén
                pw.Text(
                  'Almacén: $warehouseName',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 4),
                
                // Subtítulo con zona/área
                pw.Text(
                  'Área: $zoneName',
                  style: pw.TextStyle(
                    fontSize: 16,
                    fontWeight: pw.FontWeight.normal,
                  ),
                ),
                pw.SizedBox(height: 16),
                
                // Información adicional
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'Total de productos: ${products.length}',
                      style: const pw.TextStyle(fontSize: 12),
                    ),
                    pw.Text(
                      'Generado por: $_appName',
                      style: const pw.TextStyle(fontSize: 12),
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
                1: const pw.FlexColumnWidth(2), // SKU
                2: const pw.FlexColumnWidth(1.5), // Cant. Inicial
                3: const pw.FlexColumnWidth(1.5), // Cant. Actual
                4: const pw.FlexColumnWidth(2), // Precio Unitario
                5: const pw.FlexColumnWidth(1.5), // Presentación
              },
              children: [
                // Encabezado de la tabla
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  children: [
                    _buildTableHeader('Nombre del Producto'),
                    _buildTableHeader('SKU'),
                    _buildTableHeader('Cant. Inicial'),
                    _buildTableHeader('Cant. Actual'),
                    _buildTableHeader('Precio Unitario'),
                    _buildTableHeader('Presentación'),
                  ],
                ),
                
                // Filas de productos
                ...products.map((product) => pw.TableRow(
                  children: [
                    _buildTableCell(product.nombreProducto),
                    _buildTableCell(product.skuProducto.isNotEmpty ? product.skuProducto : 'N/A'),
                    _buildTableCell(product.cantidadInicial.toStringAsFixed(0)),
                    _buildTableCell(product.cantidadFinal.toStringAsFixed(0)),
                    _buildTableCell(product.precioVenta != null 
                        ? '\$${product.precioVenta!.toStringAsFixed(2)}' 
                        : 'N/A'),
                    _buildTableCell(product.presentacion),
                  ],
                )),
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
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text('• Total de productos: ${products.length}'),
                  pw.Text('• Productos con stock: ${products.where((p) => p.cantidadFinal > 0).length}'),
                  pw.Text('• Productos sin stock: ${products.where((p) => p.cantidadFinal <= 0).length}'),
                  pw.Text('• Stock total: ${products.fold<double>(0, (sum, p) => sum + p.cantidadFinal).toStringAsFixed(0)} unidades'),
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
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                ),
                pw.Text(
                  'Página ${context.pageNumber} de ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
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
  Future<Uint8List> _generateExcel(String warehouseName, String zoneName, List<InventoryProduct> products) async {
    final excel = Excel.createExcel();
    final sheet = excel['Inventario'];
    
    // Configurar el ancho de las columnas
    sheet.setColumnWidth(0, 30); // Nombre
    sheet.setColumnWidth(1, 15); // SKU
    sheet.setColumnWidth(2, 12); // Cant. Inicial
    sheet.setColumnWidth(3, 12); // Cant. Actual
    sheet.setColumnWidth(4, 15); // Precio Unitario
    sheet.setColumnWidth(5, 15); // Presentación
    sheet.setColumnWidth(6, 15); // Categoría
    sheet.setColumnWidth(7, 15); // Subcategoría
    sheet.setColumnWidth(8, 15); // Variante
    
    int currentRow = 0;
    
    // Título principal
    final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    titleCell.value =  TextCellValue('REPORTE DE INVENTARIO');
    titleCell.cellStyle = CellStyle(
      bold: true,
      fontSize: 16,
      horizontalAlign: HorizontalAlign.Left,
    );
    currentRow += 2;
    
    // Información del almacén y zona
    final warehouseCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    warehouseCell.value = TextCellValue('Almacén: $warehouseName');
    warehouseCell.cellStyle = CellStyle(bold: true, fontSize: 14);
    currentRow++;
    
    final zoneCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    zoneCell.value = TextCellValue('Área: $zoneName');
    zoneCell.cellStyle = CellStyle(bold: true, fontSize: 12);
    currentRow += 2;
    
    // Información adicional
    final infoCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    infoCell.value = TextCellValue('Total de productos: ${products.length}');
    currentRow++;
    
    final dateCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
    dateCell.value = TextCellValue('Fecha: ${DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now())}');
    currentRow += 2;
    
    // Encabezados de la tabla
    final headers = [
      'Nombre del Producto',
      'SKU',
      'Cantidad Inicial',
      'Cantidad Actual',
      'Precio Unitario',
      'Presentación',
      'Categoría',
      'Subcategoría',
      'Variante',
    ];
    
    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
      cell.value = TextCellValue(headers[i]);
      cell.cellStyle = CellStyle(
        bold: true,
        backgroundColorHex: ExcelColor.grey50,
        horizontalAlign: HorizontalAlign.Center,
      );
    }
    currentRow++;
    
    // Datos de los productos
    for (final product in products) {
      final rowData = [
        product.nombreProducto,
        product.skuProducto.isNotEmpty ? product.skuProducto : 'N/A',
        product.cantidadInicial.toStringAsFixed(0),
        product.cantidadFinal.toStringAsFixed(0),
        product.precioVenta != null ? '\$${product.precioVenta!.toStringAsFixed(2)}' : 'N/A',
        product.presentacion,
        product.categoria,
        product.subcategoria,
        product.variante,
      ];
      
      for (int i = 0; i < rowData.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
        cell.value = TextCellValue(rowData[i]);
        
        // Aplicar color basado en el stock
        if (i == 3) { // Columna de cantidad actual
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
    final summaryCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
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
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      cell.value = TextCellValue(summary);
      currentRow++;
    }
    
    // excel.encode() devuelve List<int>, convertimos a Uint8List
    return Uint8List.fromList(excel.encode()!);
  }
  
  /// Construye una celda de encabezado para la tabla PDF
  pw.Widget _buildTableHeader(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }
  
  /// Construye una celda de datos para la tabla PDF
  pw.Widget _buildTableCell(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        text,
        style: const pw.TextStyle(fontSize: 9),
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
      final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      titleCell.value = TextCellValue('REPORTE DE INVENTARIO');
      titleCell.cellStyle = CellStyle(
        bold: true,
        fontSize: 16,
        horizontalAlign: HorizontalAlign.Left,
      );
      currentRow += 2;
      
      // Información del almacén
      final warehouseCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      warehouseCell.value = TextCellValue('Almacén: $warehouseName');
      warehouseCell.cellStyle = CellStyle(bold: true, fontSize: 14);
      currentRow++;
      
      // Fecha del filtro o fecha actual
      final dateCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
      final dateStr = filterDate != null 
          ? DateFormat('dd/MM/yyyy').format(filterDate)
          : DateFormat('dd/MM/yyyy').format(DateTime.now());
      dateCell.value = TextCellValue('Fecha: $dateStr');
      dateCell.cellStyle = CellStyle(bold: true, fontSize: 12);
      currentRow += 2;
      
      // Agrupar por almacén y ubicación
      final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};
      
      for (final item in inventoryData) {
        final almacen = item['almacen']?.toString() ?? 'Sin almacén';
        final ubicacion = item['ubicacion']?.toString() ?? 'Sin ubicación';
        
        if (!groupedData.containsKey(almacen)) {
          groupedData[almacen] = {};
        }
        if (!groupedData[almacen]!.containsKey(ubicacion)) {
          groupedData[almacen]![ubicacion] = [];
        }
        groupedData[almacen]![ubicacion]!.add(item);
      }
      
      // Generar contenido por almacén y ubicación
      for (final almacenEntry in groupedData.entries) {
        final almacenName = almacenEntry.key;
        
        // Título del almacén
        final almacenTitleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
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
          final ubicacionTitleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
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
            'Stock Disponible',
            'Cantidad Inicial',
            'Cantidad Final',
            'Precio Venta',
            'Costo Promedio',
          ];
          
          for (int i = 0; i < headers.length; i++) {
            final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
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
              (producto['cantidad_final'] ?? 0).toString(),
              '\$${(producto['precio_venta'] ?? 0).toStringAsFixed(2)}',
              '\$${(producto['costo_promedio'] ?? 0).toStringAsFixed(2)}',
            ];
            
            for (int i = 0; i < rowData.length; i++) {
              final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
              cell.value = TextCellValue(rowData[i]);
              
              // Aplicar color basado en el stock disponible
              if (i == 1) { // Columna de stock disponible
                final stock = double.tryParse(producto['stock_disponible']?.toString() ?? '0') ?? 0;
                if (stock <= 0) {
                  cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.red);
                } else if (stock <= 10) {
                  cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.orange);
                } else {
                  cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.green);
                }
              }
            }
            currentRow++;
          }
          
          currentRow += 1; // Espacio entre ubicaciones
        }
        
        currentRow += 1; // Espacio entre almacenes
      }
      
      // Guardar archivo
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'inventario_${_cleanFileName(warehouseName)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
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
      
      // Agrupar por almacén y ubicación
      final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};
      
      for (final item in inventoryData) {
        final almacen = item['almacen']?.toString() ?? 'Sin almacén';
        final ubicacion = item['ubicacion']?.toString() ?? 'Sin ubicación';
        
        if (!groupedData.containsKey(almacen)) {
          groupedData[almacen] = {};
        }
        if (!groupedData[almacen]!.containsKey(ubicacion)) {
          groupedData[almacen]![ubicacion] = [];
        }
        groupedData[almacen]![ubicacion]!.add(item);
      }
      
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
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Almacén: $warehouseName',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    'Fecha: ${filterDate != null ? dateFormatter.format(filterDate) : dateFormatter.format(now)}',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.normal,
                    ),
                  ),
                  pw.SizedBox(height: 16),
                  pw.Text(
                    'Total de productos: ${inventoryData.length}',
                    style: const pw.TextStyle(fontSize: 12),
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
                      fontWeight: pw.FontWeight.bold,
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
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                );
                
                widgets.add(pw.SizedBox(height: 4));
                
                // Tabla de productos
                widgets.add(
                  pw.Table(
                    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
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
                        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                        children: [
                          _buildTableHeader('Nombre'),
                          _buildTableHeader('Stock Disponible'),
                          _buildTableHeader('Cant. Inicial'),
                          _buildTableHeader('Cant. Final'),
                          _buildTableHeader('Precio Venta'),
                          _buildTableHeader('Costo Promedio'),
                        ],
                      ),
                      
                      // Filas de productos
                      ...productos.map((producto) => pw.TableRow(
                        children: [
                          _buildTableCell(producto['nombre_producto']?.toString() ?? 'Sin nombre'),
                          _buildTableCell((producto['stock_disponible'] ?? 0).toString()),
                          _buildTableCell((producto['cantidad_inicial'] ?? 0).toString()),
                          _buildTableCell((producto['cantidad_final'] ?? 0).toString()),
                          _buildTableCell('\$${(producto['precio_venta'] ?? 0).toStringAsFixed(2)}'),
                          _buildTableCell('\$${(producto['costo_promedio'] ?? 0).toStringAsFixed(2)}'),
                        ],
                      )),
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
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                  pw.Text(
                    'Página ${context.pageNumber} de ${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                  ),
                ],
              ),
            );
          },
        ),
      );
      
      // Guardar archivo
      final directory = await getApplicationDocumentsDirectory();
      final fileName = 'inventario_${_cleanFileName(warehouseName)}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
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
    DateTime? filterDate,
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
        // Generar Excel
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
        final titleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
        titleCell.value = TextCellValue('REPORTE DE INVENTARIO');
        titleCell.cellStyle = CellStyle(
          bold: true,
          fontSize: 16,
          horizontalAlign: HorizontalAlign.Left,
        );
        currentRow += 2;
        
        // Información del almacén
        final warehouseCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
        warehouseCell.value = TextCellValue('Almacén: $warehouseName');
        warehouseCell.cellStyle = CellStyle(bold: true, fontSize: 14);
        currentRow++;
        
        // Fecha del filtro o fecha actual
        final dateCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
        final dateStrFormatted = filterDate != null 
            ? DateFormat('dd/MM/yyyy').format(filterDate)
            : DateFormat('dd/MM/yyyy').format(DateTime.now());
        dateCell.value = TextCellValue('Fecha: $dateStrFormatted');
        dateCell.cellStyle = CellStyle(bold: true, fontSize: 12);
        currentRow += 2;
        
        // Agrupar por almacén y ubicación
        final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};
        
        for (final item in inventoryData) {
          final almacen = item['almacen']?.toString() ?? 'Sin almacén';
          final ubicacion = item['ubicacion']?.toString() ?? 'Sin ubicación';
          
          if (!groupedData.containsKey(almacen)) {
            groupedData[almacen] = {};
          }
          if (!groupedData[almacen]!.containsKey(ubicacion)) {
            groupedData[almacen]![ubicacion] = [];
          }
          groupedData[almacen]![ubicacion]!.add(item);
        }
        
        // Generar contenido por almacén y ubicación
        for (final almacenEntry in groupedData.entries) {
          final almacenName = almacenEntry.key;
          
          // Título del almacén
          final almacenTitleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
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
            final ubicacionTitleCell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
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
              'Stock Disponible',
              'Cantidad Inicial',
              'Cantidad Final',
              'Precio Venta',
              'Costo Promedio',
            ];
            
            for (int i = 0; i < headers.length; i++) {
              final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
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
                (producto['cantidad_final'] ?? 0).toString(),
                '\$${(producto['precio_venta'] ?? 0).toStringAsFixed(2)}',
                '\$${(producto['costo_promedio'] ?? 0).toStringAsFixed(2)}',
              ];
              
              for (int i = 0; i < rowData.length; i++) {
                final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: currentRow));
                cell.value = TextCellValue(rowData[i]);
                
                // Aplicar color basado en el stock disponible
                if (i == 1) { // Columna de stock disponible
                  final stock = double.tryParse(producto['stock_disponible']?.toString() ?? '0') ?? 0;
                  if (stock <= 0) {
                    cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.red);
                  } else if (stock <= 10) {
                    cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.orange);
                  } else {
                    cell.cellStyle = CellStyle(backgroundColorHex: ExcelColor.green);
                  }
                }
              }
              currentRow++;
            }
            
            currentRow += 1; // Espacio entre ubicaciones
          }
          
          currentRow += 1; // Espacio entre almacenes
        }
        
        fileBytes = Uint8List.fromList(excel.encode()!);
        mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
        fileName = 'inventario_${cleanWarehouse}_$dateStr.xlsx';
      } else {
        // Generar PDF
        final pdf = pw.Document();
        final dateFormatter = DateFormat('dd/MM/yyyy');
        final timeFormatter = DateFormat('HH:mm');
        
        // Agrupar por almacén y ubicación
        final groupedData = <String, Map<String, List<Map<String, dynamic>>>>{};
        
        for (final item in inventoryData) {
          final almacen = item['almacen']?.toString() ?? 'Sin almacén';
          final ubicacion = item['ubicacion']?.toString() ?? 'Sin ubicación';
          
          if (!groupedData.containsKey(almacen)) {
            groupedData[almacen] = {};
          }
          if (!groupedData[almacen]!.containsKey(ubicacion)) {
            groupedData[almacen]![ubicacion] = [];
          }
          groupedData[almacen]![ubicacion]!.add(item);
        }
        
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
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Almacén: $warehouseName',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Fecha: ${filterDate != null ? dateFormatter.format(filterDate) : dateFormatter.format(now)}',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.normal,
                      ),
                    ),
                    pw.SizedBox(height: 16),
                    pw.Text(
                      'Total de productos: ${inventoryData.length}',
                      style: const pw.TextStyle(fontSize: 12),
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
                        fontWeight: pw.FontWeight.bold,
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
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                  );
                  
                  widgets.add(pw.SizedBox(height: 4));
                  
                  // Tabla de productos
                  widgets.add(
                    pw.Table(
                      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
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
                          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                          children: [
                            _buildTableHeader('Nombre'),
                            _buildTableHeader('Stock Disponible'),
                            _buildTableHeader('Cant. Inicial'),
                            _buildTableHeader('Cant. Final'),
                            _buildTableHeader('Precio Venta'),
                            _buildTableHeader('Costo Promedio'),
                          ],
                        ),
                        
                        // Filas de productos
                        ...productos.map((producto) => pw.TableRow(
                          children: [
                            _buildTableCell(producto['nombre_producto']?.toString() ?? 'Sin nombre'),
                            _buildTableCell((producto['stock_disponible'] ?? 0).toString()),
                            _buildTableCell((producto['cantidad_inicial'] ?? 0).toString()),
                            _buildTableCell((producto['cantidad_final'] ?? 0).toString()),
                            _buildTableCell('\$${(producto['precio_venta'] ?? 0).toStringAsFixed(2)}'),
                            _buildTableCell('\$${(producto['costo_promedio'] ?? 0).toStringAsFixed(2)}'),
                          ],
                        )),
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
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                    ),
                    pw.Text(
                      'Página ${context.pageNumber} de ${context.pagesCount}',
                      style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
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
      
      // Guardar archivo temporalmente
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(fileBytes);
      
      // Compartir archivo
      await Share.shareXFiles(
        [XFile(file.path, mimeType: mimeType)],
        subject: 'Inventario - $warehouseName',
        text: 'Reporte de inventario generado el ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
      );
      
      // Mostrar mensaje de éxito
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Archivo ${format.toUpperCase()} generado y compartido exitosamente'),
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

  /// Abre un archivo usando el visor predeterminado del sistema
  Future<void> openFile(String filePath) async {
    try {
      await Share.shareXFiles([XFile(filePath)]);
    } catch (e) {
      print('Error abriendo archivo: $e');
      rethrow;
    }
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
