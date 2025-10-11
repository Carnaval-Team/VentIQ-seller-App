import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';

class ExcelImportService {
  static const int maxBatchSize = 50; // Procesar en lotes de 50 productos

  /// Campos obligatorios para importación
  static const List<String> requiredFields = [
    'denominacion',
    'descripcion',
    'categoria_id',
    'sku',
    'precio_venta',
  ];

  /// Mapeo de columnas Excel a campos del modelo Product
  static const Map<String, String> columnMapping = {
    // Campos básicos obligatorios
    'denominacion': 'denominacion',
    'nombre': 'denominacion', // Alias
    'descripcion': 'descripcion',
    'categoria_id': 'categoria_id',
    'categoria': 'categoria_id', // Se resolverá por nombre
    'sku': 'sku',
    'codigo': 'sku', // Alias
    'precio_venta': 'precio_venta',
    'precio': 'precio_venta', // Alias
    // Campos opcionales
    'denominacion_corta': 'denominacion_corta',
    'descripcion_corta': 'descripcion_corta',
    'nombre_comercial': 'nombre_comercial',
    'marca': 'nombre_comercial', // Alias
    'codigo_barras': 'codigo_barras',
    'barcode': 'codigo_barras', // Alias
    'unidad_medida': 'um',
    'um': 'um',

    // Propiedades booleanas
    'es_refrigerado': 'es_refrigerado',
    'refrigerado': 'es_refrigerado', // Alias
    'es_fragil': 'es_fragil',
    'fragil': 'es_fragil', // Alias
    'es_peligroso': 'es_peligroso',
    'peligroso': 'es_peligroso', // Alias
    'es_vendible': 'es_vendible',
    'vendible': 'es_vendible', // Alias
    'es_comprable': 'es_comprable',
    'comprable': 'es_comprable', // Alias
    'es_inventariable': 'es_inventariable',
    'inventariable': 'es_inventariable', // Alias
    'es_por_lotes': 'es_por_lotes',
    'por_lotes': 'es_por_lotes', // Alias
    'es_servicio': 'es_servicio',
    'servicio': 'es_servicio', // Alias
    // Stock y límites
    'stock_minimo': 'stock_minimo',
    'stock_maximo': 'stock_maximo',
    'dias_alert_caducidad': 'dias_alert_caducidad',

    // Ofertas
    'es_oferta': 'es_oferta',
    'oferta': 'es_oferta', // Alias
    'precio_oferta': 'precio_oferta',
    'fecha_inicio_oferta': 'fecha_inicio_oferta',
    'fecha_fin_oferta': 'fecha_fin_oferta',

    // Productos elaborados
    'es_elaborado': 'es_elaborado',
    'elaborado': 'es_elaborado', // Alias
    'costo_produccion': 'costo_produccion',
  };

  /// Selecciona archivo Excel
  static Future<File?> pickExcelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        return File(result.files.single.path!);
      }
      return null;
    } catch (e) {
      throw Exception('Error al seleccionar archivo: $e');
    }
  }

  /// Lee y analiza el archivo Excel
  static Future<ExcelAnalysisResult> analyzeExcelFile(File file) async {
    try {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        throw Exception('El archivo Excel no contiene hojas de cálculo');
      }

      // Usar la primera hoja
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;

      if (sheet.rows.isEmpty) {
        throw Exception('La hoja de cálculo está vacía');
      }

      // Obtener encabezados (primera fila)
      final headerRow = sheet.rows.first;
      final headers =
          headerRow
              .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
              .toList();

      // Validar que hay encabezados
      if (headers.isEmpty || headers.every((h) => h.isEmpty)) {
        throw Exception('No se encontraron encabezados en la primera fila');
      }

      // Obtener datos (resto de filas)
      final dataRows =
          sheet.rows
              .skip(1)
              .where(
                (row) => row.any(
                  (cell) =>
                      cell?.value != null &&
                      cell!.value.toString().trim().isNotEmpty,
                ),
              )
              .toList();

      // Analizar mapeo de columnas
      final columnAnalysis = _analyzeColumns(headers);

      // Validar campos obligatorios
      final missingRequired = _validateRequiredFields(
        columnAnalysis.mappedColumns,
      );

      return ExcelAnalysisResult(
        fileName: file.path.split('/').last,
        totalRows: dataRows.length,
        headers: headers,
        columnAnalysis: columnAnalysis,
        missingRequiredFields: missingRequired,
        sampleData: _extractSampleData(dataRows, headers),
        isValid: missingRequired.isEmpty,
      );
    } catch (e) {
      throw Exception('Error al analizar archivo Excel: $e');
    }
  }

  /// Analiza las columnas y sugiere mapeos
  static ColumnAnalysisResult _analyzeColumns(List<String> headers) {
    final mappedColumns = <String, String>{};
    final unmappedColumns = <String>[];
    final suggestions = <String, List<String>>{};

    for (int i = 0; i < headers.length; i++) {
      final header = headers[i].toLowerCase().trim();

      // Debug: mostrar qué headers se están procesando
      print('Procesando header: "$header" (original: "${headers[i]}")');
      if (columnMapping.containsKey(header)) {
        // Mapeo directo encontrado
        mappedColumns[header] = columnMapping[header]!;
      } else {
        // Buscar similitudes
        final similarColumns = _findSimilarColumns(header);
        if (similarColumns.isNotEmpty) {
          suggestions[header] = similarColumns;
        } else {
          unmappedColumns.add(header);
        }
      }
    }

    return ColumnAnalysisResult(
      mappedColumns: mappedColumns,
      unmappedColumns: unmappedColumns,
      suggestions: suggestions,
    );
  }

  /// Busca columnas similares para sugerir mapeos
  static List<String> _findSimilarColumns(String header) {
    if (header.isEmpty) return [];

    final suggestions = <String>{}; // Usar Set para evitar duplicados

    for (final mapping in columnMapping.entries) {
      final key = mapping.key;
      final value = mapping.value;

      // Buscar coincidencias más específicas
      if (header.contains(key) || key.contains(header)) {
        suggestions.add(value);
      }
    }

    return suggestions.take(3).toList(); // Máximo 3 sugerencias únicas
  }

  /// Valida que estén presentes los campos obligatorios
  static List<String> _validateRequiredFields(
    Map<String, String> mappedColumns,
  ) {
    final mappedValues = mappedColumns.values.toSet();
    return requiredFields
        .where((field) => !mappedValues.contains(field))
        .toList();
  }

  /// Extrae datos de muestra para preview
  static List<Map<String, dynamic>> _extractSampleData(
    List<List<Data?>> dataRows,
    List<String> headers,
  ) {
    final sampleSize = dataRows.length > 5 ? 5 : dataRows.length;
    final sampleData = <Map<String, dynamic>>[];

    for (int i = 0; i < sampleSize; i++) {
      final row = dataRows[i];
      final rowData = <String, dynamic>{};

      for (int j = 0; j < headers.length && j < row.length; j++) {
        final cellValue = row[j]?.value;
        rowData[headers[j]] = cellValue?.toString() ?? '';
      }

      sampleData.add(rowData);
    }

    return sampleData;
  }

  /// Procesa e importa los productos
  static Future<ImportResult> importProducts(
    File file,
    Map<String, String> finalColumnMapping, {
    Map<String, dynamic>? defaultValues, // AGREGAR
    Function(int, int)? onProgress,
  }) async {
    try {
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;

      final headerRow = sheet.rows.first;
      final headers =
          headerRow
              .map((cell) => cell?.value?.toString().toLowerCase().trim() ?? '')
              .toList();

      final dataRows =
          sheet.rows
              .skip(1)
              .where(
                (row) => row.any(
                  (cell) =>
                      cell?.value != null &&
                      cell!.value.toString().trim().isNotEmpty,
                ),
              )
              .toList();

      // Obtener categorías para mapeo
      final categories = await ProductService.getCategorias();
      final categoryMap = <String, int>{};
      for (final cat in categories) {
        categoryMap[cat['denominacion'].toString().toLowerCase()] = cat['id'];
      }

      // Obtener ID de tienda
      final userPrefs = UserPreferencesService();
      final idTienda = await userPrefs.getIdTienda();
      if (idTienda == null) {
        throw Exception('No se encontró ID de tienda');
      }

      final results = ImportResult();
      final totalRows = dataRows.length;

      // Procesar en lotes
      for (
        int batchStart = 0;
        batchStart < totalRows;
        batchStart += maxBatchSize
      ) {
        final batchEnd =
            (batchStart + maxBatchSize > totalRows)
                ? totalRows
                : batchStart + maxBatchSize;

        final batch = dataRows.sublist(batchStart, batchEnd);

        for (int i = 0; i < batch.length; i++) {
          final rowIndex = batchStart + i;
          final row = batch[i];

          try {
            final productData = _convertRowToProductData(
              row,
              headers,
              finalColumnMapping,
              categoryMap,
              idTienda,
              defaultValues: defaultValues, // AGREGAR
            );

            // Preparar datos de precios
            List<Map<String, dynamic>>? preciosData;
            if (productData.containsKey('precio_venta')) {
              preciosData = [
                {
                  'precio_venta_cup': productData['precio_venta'],
                  'fecha_desde': DateTime.now().toIso8601String().substring(
                    0,
                    10,
                  ),
                  'es_activo': true,
                },
              ];
            }

            // Preparar datos de subcategorías
            List<Map<String, dynamic>>? subcategoriasData;
            if (productData.containsKey('id_categoria')) {
              subcategoriasData = [
                {
                  'id_sub_categoria': productData['id_categoria'],
                  'es_principal': true,
                },
              ];
            }

            // Insertar producto
            await ProductService.insertProductoCompleto(
              productoData: productData,
              preciosData: preciosData,
              subcategoriasData: subcategoriasData,
            );

            results.successCount++;
            results.successfulProducts.add(
              productData['denominacion'] ?? 'Producto ${rowIndex + 1}',
            );
          } catch (e) {
            results.errorCount++;
            results.errors.add(
              ImportError(
                row:
                    rowIndex +
                    2, // +2 porque empezamos en fila 1 y saltamos header
                message: e.toString(),
                data: _extractRowData(row, headers),
              ),
            );
          }

          // Reportar progreso
          onProgress?.call(rowIndex + 1, totalRows);
        }
      }

      return results;
    } catch (e) {
      throw Exception('Error durante la importación: $e');
    }
  }

  /// Convierte una fila de Excel a datos de producto
  static Map<String, dynamic> _convertRowToProductData(
    List<Data?> row,
    List<String> headers,
    Map<String, String> columnMapping,
    Map<String, int> categoryMap,
    int idTienda, {
    Map<String, dynamic>? defaultValues, // AGREGAR
  }) {
    final productData = <String, dynamic>{'id_tienda': idTienda};

    // AGREGAR: Aplicar valores por defecto PRIMERO
    if (defaultValues != null) {
      for (final entry in defaultValues.entries) {
        if (entry.key == 'categoria_id') {
          productData['id_categoria'] = entry.value;
        } else {
          productData[entry.key] = entry.value;
        }
      }
    }
    for (int i = 0; i < headers.length && i < row.length; i++) {
      final header = headers[i];
      final cellValue = row[i]?.value;

      if (cellValue == null || cellValue.toString().trim().isEmpty) continue;

      final mappedField = columnMapping[header];
      if (mappedField == null) continue;

      // Procesar según el tipo de campo
      switch (mappedField) {
        case 'categoria_id':
          // Resolver categoría por nombre o ID
          final categoryValue = cellValue.toString().toLowerCase().trim();
          if (categoryMap.containsKey(categoryValue)) {
            productData['id_categoria'] = categoryMap[categoryValue];
          } else {
            // Intentar parsear como ID directo
            final categoryId = int.tryParse(cellValue.toString());
            if (categoryId != null) {
              productData['id_categoria'] = categoryId;
            } else {
              throw Exception('Categoría no encontrada: $cellValue');
            }
          }
          break;

        case 'precio_venta':
        case 'precio_oferta':
        case 'costo_produccion':
          final doubleValue = double.tryParse(cellValue.toString());
          if (doubleValue != null) {
            productData[mappedField] = doubleValue;
          }
          break;

        case 'stock_minimo':
        case 'stock_maximo':
        case 'dias_alert_caducidad':
          final intValue = int.tryParse(cellValue.toString());
          if (intValue != null) {
            productData[mappedField] = intValue;
          }
          break;

        case 'es_refrigerado':
        case 'es_fragil':
        case 'es_peligroso':
        case 'es_vendible':
        case 'es_comprable':
        case 'es_inventariable':
        case 'es_por_lotes':
        case 'es_servicio':
        case 'es_oferta':
        case 'es_elaborado':
          productData[mappedField] = _parseBooleanValue(cellValue.toString());
          break;

        case 'fecha_inicio_oferta':
        case 'fecha_fin_oferta':
          final dateValue = _parseDateValue(cellValue.toString());
          if (dateValue != null) {
            productData[mappedField] = dateValue.toIso8601String().substring(
              0,
              10,
            );
          }
          break;

        default:
          productData[mappedField] = cellValue.toString().trim();
      }
    }

    // Validar campos obligatorios
    if (!productData.containsKey('denominacion') ||
        productData['denominacion'].toString().isEmpty) {
      throw Exception('Denominación es obligatoria');
    }
    if (!productData.containsKey('id_categoria')) {
      throw Exception('Categoría es obligatoria');
    }
    if (!productData.containsKey('sku') ||
        productData['sku'].toString().isEmpty) {
      throw Exception('SKU es obligatorio');
    }

    // Valores por defecto
    productData['descripcion'] ??= productData['denominacion'];
    productData['es_vendible'] ??= true;
    productData['es_comprable'] ??= true;
    productData['es_inventariable'] ??= true;
    productData['precio_venta'] ??= 0.0;

    return productData;
  }

  /// Parsea valores booleanos desde Excel
  static bool _parseBooleanValue(String value) {
    final lowerValue = value.toLowerCase().trim();
    return lowerValue == 'true' ||
        lowerValue == 'sí' ||
        lowerValue == 'si' ||
        lowerValue == 'yes' ||
        lowerValue == '1' ||
        lowerValue == 'verdadero';
  }

  /// Parsea fechas desde Excel
  static DateTime? _parseDateValue(String value) {
    try {
      // Intentar varios formatos de fecha
      final formats = [
        RegExp(r'^\d{4}-\d{2}-\d{2}$'), // YYYY-MM-DD
        RegExp(r'^\d{2}/\d{2}/\d{4}$'), // DD/MM/YYYY
        RegExp(r'^\d{2}-\d{2}-\d{4}$'), // DD-MM-YYYY
      ];

      for (final format in formats) {
        if (format.hasMatch(value)) {
          if (value.contains('/')) {
            final parts = value.split('/');
            return DateTime(
              int.parse(parts[2]),
              int.parse(parts[1]),
              int.parse(parts[0]),
            );
          } else if (value.contains('-') && value.length == 10) {
            if (value.startsWith('20')) {
              return DateTime.parse(value);
            } else {
              final parts = value.split('-');
              return DateTime(
                int.parse(parts[2]),
                int.parse(parts[1]),
                int.parse(parts[0]),
              );
            }
          }
        }
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  /// Extrae datos de una fila para reporte de errores
  static Map<String, dynamic> _extractRowData(
    List<Data?> row,
    List<String> headers,
  ) {
    final rowData = <String, dynamic>{};
    for (int i = 0; i < headers.length && i < row.length; i++) {
      rowData[headers[i]] = row[i]?.value?.toString() ?? '';
    }
    return rowData;
  }

  /*/// Genera template Excel para descarga
  static Future<Uint8List> generateTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Productos'];
    
    // Encabezados del template
    final headers = [
      'denominacion',
      'descripcion',
      'categoria_id',
      'sku',
      'precio_venta',
      'denominacion_corta',
      'nombre_comercial',
      'codigo_barras',
      'unidad_medida',
      'es_refrigerado',
      'es_fragil',
      'es_peligroso',
      'es_vendible',
      'es_comprable',
      'stock_minimo',
      'stock_maximo',
      'es_oferta',
      'precio_oferta',
      'es_elaborado',
    ];
    
    // Agregar encabezados
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = headers[i];
    }
    
    // Agregar fila de ejemplo
    final exampleData = [
      'Producto Ejemplo',
      'Descripción del producto ejemplo',
      '1',
      'PROD001',
      '25.50',
      'Prod Ej',
      'Marca Ejemplo',
      '1234567890123',
      'Unidad',
      'false',
      'false',
      'false',
      'true',
      'true',
      '10',
      '100',
      'false',
      '0',
      'false',
    ];
    
    for (int i = 0; i < exampleData.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = exampleData[i];
    }
    
    return excel.encode()!;
  }
*/
}

/// Resultado del análisis del archivo Excel
class ExcelAnalysisResult {
  final String fileName;
  final int totalRows;
  final List<String> headers;
  final ColumnAnalysisResult columnAnalysis;
  final List<String> missingRequiredFields;
  final List<Map<String, dynamic>> sampleData;
  final bool isValid;

  ExcelAnalysisResult({
    required this.fileName,
    required this.totalRows,
    required this.headers,
    required this.columnAnalysis,
    required this.missingRequiredFields,
    required this.sampleData,
    required this.isValid,
  });
}

/// Resultado del análisis de columnas
class ColumnAnalysisResult {
  final Map<String, String> mappedColumns;
  final List<String> unmappedColumns;
  final Map<String, List<String>> suggestions;

  ColumnAnalysisResult({
    required this.mappedColumns,
    required this.unmappedColumns,
    required this.suggestions,
  });
}

/// Resultado de la importación
class ImportResult {
  int successCount = 0;
  int errorCount = 0;
  List<String> successfulProducts = [];
  List<ImportError> errors = [];

  int get totalProcessed => successCount + errorCount;
  double get successRate =>
      totalProcessed > 0 ? (successCount / totalProcessed) * 100 : 0;
}

/// Error de importación
class ImportError {
  final int row;
  final String message;
  final Map<String, dynamic> data;

  ImportError({required this.row, required this.message, required this.data});
}
