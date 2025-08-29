import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/order.dart';
import '../services/user_preferences_service.dart';

class PdfService {
  static final UserPreferencesService _userPreferencesService = UserPreferencesService();

  /// Solicita permisos de almacenamiento
  static Future<bool> _requestStoragePermissions() async {
    try {
      // Para Android 13+ (API 33+) no necesitamos permisos para archivos de la app
      if (Platform.isAndroid) {
        // Verificar versión de Android
        final androidInfo = await _getAndroidVersion();
        if (androidInfo >= 33) {
          // Android 13+ - No necesita permisos para archivos de la app
          return true;
        }
        
        // Android 12 y anteriores - Solicitar permisos de almacenamiento
        var status = await Permission.storage.status;
        if (status.isDenied) {
          status = await Permission.storage.request();
        }
        
        if (status.isPermanentlyDenied) {
          // Mostrar diálogo para ir a configuración
          return false;
        }
        
        return status.isGranted;
      }
      
      // iOS no necesita permisos para archivos de la app
      return true;
    } catch (e) {
      print('❌ Error al solicitar permisos: $e');
      return false;
    }
  }

  static Future<int> _getAndroidVersion() async {
    try {
      // Simulamos obtener la versión de Android
      // En una implementación real, usarías device_info_plus
      return 30; // Asumimos Android 11 por defecto para solicitar permisos
    } catch (e) {
      return 30;
    }
  }

  /// Genera un PDF del resumen detallado de ventas
  static Future<String?> generateSalesReportPdf({
    required List<OrderItem> productosVendidos,
    required List<Order> ordenesVendidas,
    required double totalVentas,
    required int totalProductos,
    required double totalCosto,
    required double totalDescuentos,
  }) async {
    try {
      // Solicitar permisos de almacenamiento
      bool hasPermission = await _requestStoragePermissions();
      if (!hasPermission) {
        print('❌ No se otorgaron permisos de almacenamiento');
        return null;
      }
      // Crear el documento PDF
      final pdf = pw.Document();
      
      // Obtener información del vendedor
      final workerProfile = await _userPreferencesService.getWorkerProfile();
      final userEmail = await _userPreferencesService.getUserEmail();
      
      final sellerName = '${workerProfile['nombres'] ?? ''} ${workerProfile['apellidos'] ?? ''}'.trim();
      final sellerEmail = userEmail ?? 'Sin email';
      final now = DateTime.now();

      // Agrupar productos por nombre
      final productosAgrupados = <String, Map<String, dynamic>>{};
      
      for (final item in productosVendidos) {
        final key = item.nombre;
        if (productosAgrupados.containsKey(key)) {
          productosAgrupados[key]!['cantidad'] += item.cantidad;
          productosAgrupados[key]!['subtotal'] += item.subtotal;
          productosAgrupados[key]!['costo'] += (item.precioUnitario * 0.6) * item.cantidad;
          productosAgrupados[key]!['descuento'] += (item.precioUnitario * 0.1) * item.cantidad;
        } else {
          productosAgrupados[key] = {
            'item': item,
            'cantidad': item.cantidad,
            'subtotal': item.subtotal,
            'costo': (item.precioUnitario * 0.6) * item.cantidad,
            'descuento': (item.precioUnitario * 0.1) * item.cantidad,
          };
        }
      }

      final productosFinales = productosAgrupados.values.toList();

      // Crear página del PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          build: (pw.Context context) {
            return [
              // Header
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Text(
                      'VENTIQ',
                      style: pw.TextStyle(
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'RESUMEN DETALLADO DE VENTAS',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Container(
                      height: 2,
                      width: 200,
                      color: PdfColors.blue800,
                      margin: const pw.EdgeInsets.symmetric(vertical: 16),
                    ),
                  ],
                ),
              ),

              // Información del vendedor y fecha
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  color: PdfColors.grey100,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'INFORMACIÓN DEL REPORTE',
                      style: pw.TextStyle(
                        fontSize: 14,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Vendedor: $sellerName'),
                            pw.Text('Email: $sellerEmail'),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Fecha: ${_formatDate(now)}'),
                            pw.Text('Hora: ${_formatTime(now)}'),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 24),

              // Resumen general
              pw.Container(
                padding: const pw.EdgeInsets.all(16),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue800, width: 2),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'RESUMEN GENERAL',
                      style: pw.TextStyle(
                        fontSize: 16,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue800,
                      ),
                    ),
                    pw.SizedBox(height: 12),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Total Productos: $totalProductos'),
                            pw.Text('Órdenes Procesadas: ${ordenesVendidas.length}'),
                          ],
                        ),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.end,
                          children: [
                            pw.Text('Costo Total: \$${totalCosto.toStringAsFixed(0)}'),
                            pw.Text('Descuentos: \$${totalDescuentos.toStringAsFixed(0)}'),
                          ],
                        ),
                      ],
                    ),
                    pw.SizedBox(height: 8),
                    pw.Container(
                      width: double.infinity,
                      padding: const pw.EdgeInsets.all(8),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.blue50,
                        borderRadius: pw.BorderRadius.circular(4),
                      ),
                      child: pw.Text(
                        'TOTAL VENTAS: \$${totalVentas.toStringAsFixed(0)}',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.blue800,
                        ),
                        textAlign: pw.TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),

              pw.SizedBox(height: 24),

              // Tabla de productos detallada
              pw.Text(
                'DETALLE POR PRODUCTO',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue800,
                ),
              ),
              pw.SizedBox(height: 12),

              pw.Table(
                border: pw.TableBorder.all(color: PdfColors.grey400),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FlexColumnWidth(1),
                  2: const pw.FlexColumnWidth(1.5),
                  3: const pw.FlexColumnWidth(1.5),
                  4: const pw.FlexColumnWidth(1.5),
                  5: const pw.FlexColumnWidth(1.5),
                },
                children: [
                  // Header de la tabla
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(
                      color: PdfColors.blue800,
                    ),
                    children: [
                      _buildTableCell('Producto', isHeader: true),
                      _buildTableCell('Cant.', isHeader: true),
                      _buildTableCell('Precio Unit.', isHeader: true),
                      _buildTableCell('Costo', isHeader: true),
                      _buildTableCell('Descuento', isHeader: true),
                      _buildTableCell('Total', isHeader: true),
                    ],
                  ),
                  
                  // Filas de productos
                  ...productosFinales.map((producto) {
                    final item = producto['item'] as OrderItem;
                    final cantidad = producto['cantidad'] as int;
                    final subtotal = producto['subtotal'] as double;
                    final costo = producto['costo'] as double;
                    final descuento = producto['descuento'] as double;

                    return pw.TableRow(
                      children: [
                        _buildTableCell(item.nombre),
                        _buildTableCell(cantidad.toString()),
                        _buildTableCell('\$${item.precioUnitario.toStringAsFixed(0)}'),
                        _buildTableCell('\$${costo.toStringAsFixed(0)}'),
                        _buildTableCell('\$${descuento.toStringAsFixed(0)}'),
                        _buildTableCell('\$${subtotal.toStringAsFixed(0)}', isBold: true),
                      ],
                    );
                  }).toList(),
                ],
              ),

              pw.SizedBox(height: 24),

              // Footer
              pw.Container(
                alignment: pw.Alignment.center,
                child: pw.Column(
                  children: [
                    pw.Container(
                      height: 1,
                      width: 200,
                      color: PdfColors.grey400,
                    ),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'Generado por VentIQ - Sistema de Ventas',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                    pw.Text(
                      'Fecha de generación: ${_formatDate(now)} ${_formatTime(now)}',
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
            ];
          },
        ),
      );

      // Guardar el PDF en el dispositivo
      final output = await getApplicationDocumentsDirectory();
      final fileName = 'resumen_ventas_${_formatDateForFile(now)}.pdf';
      final file = File('${output.path}/$fileName');
      
      final pdfBytes = await pdf.save();
      await file.writeAsBytes(pdfBytes);

      print('📄 PDF generado exitosamente: ${file.path}');
      return file.path;

    } catch (e) {
      print('❌ Error al generar PDF: $e');
      return null;
    }
  }

  /// Comparte el archivo PDF generado
  static Future<void> sharePdf(String filePath, BuildContext context) async {
    try {
      // Verificar permisos antes de compartir
      bool hasPermission = await _requestStoragePermissions();
      if (!hasPermission) {
        _showPermissionDialog(context);
        return;
      }

      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Resumen detallado de ventas - VentIQ',
          subject: 'Reporte de Ventas',
        );
      } else {
        _showErrorDialog(context, 'Error', 'El archivo PDF no existe.');
      }
    } catch (e) {
      print('❌ Error al compartir PDF: $e');
      _showErrorDialog(context, 'Error', 'No se pudo compartir el archivo: $e');
    }
  }

  /// Abre el archivo PDF en el visor predeterminado
  static Future<void> openPdf(String filePath, BuildContext context) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await Share.shareXFiles(
          [XFile(filePath)],
          text: 'Abrir con...',
        );
      } else {
        _showErrorDialog(context, 'Error', 'El archivo PDF no existe.');
      }
    } catch (e) {
      print('❌ Error al abrir PDF: $e');
      _showErrorDialog(context, 'Error', 'No se pudo abrir el archivo: $e');
    }
  }

  // Helper methods
  static pw.Widget _buildTableCell(String text, {bool isHeader = false, bool isBold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 12 : 10,
          fontWeight: (isHeader || isBold) ? pw.FontWeight.bold : pw.FontWeight.normal,
          color: isHeader ? PdfColors.white : PdfColors.black,
        ),
        textAlign: isHeader ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
  }

  static String _formatDate(DateTime date) {
    return "${date.day.toString().padLeft(2, '0')}/"
           "${date.month.toString().padLeft(2, '0')}/"
           "${date.year}";
  }

  static String _formatTime(DateTime date) {
    return "${date.hour.toString().padLeft(2, '0')}:"
           "${date.minute.toString().padLeft(2, '0')}";
  }

  static String _formatDateForFile(DateTime date) {
    return "${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}_"
           "${date.hour.toString().padLeft(2, '0')}${date.minute.toString().padLeft(2, '0')}";
  }

  /// Muestra un diálogo de error
  static void _showErrorDialog(BuildContext context, String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Muestra un diálogo de permisos denegados
  static void _showPermissionDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Permisos Requeridos'),
          content: const Text(
            'La aplicación necesita permisos de almacenamiento para guardar y compartir archivos PDF.\n\n'
            '¿Deseas ir a la configuración para otorgar los permisos?'
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A90E2),
                foregroundColor: Colors.white,
              ),
              child: const Text('Configuración'),
            ),
          ],
        );
      },
    );
  }
}
