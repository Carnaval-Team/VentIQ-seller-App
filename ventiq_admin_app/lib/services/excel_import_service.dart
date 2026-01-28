import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:ventiq_admin_app/services/inventory_service.dart';
import '../services/product_service.dart';
import '../services/user_preferences_service.dart';
import '../services/currency_service.dart';

/// Clase para manejar archivos de forma compatible con web y escritorio
class ExcelFileWrapper {
  final String name;
  final Uint8List bytes;
  final File? file; // Solo disponible en escritorio

  ExcelFileWrapper({
    required this.name,
    required this.bytes,
    this.file,
  });

  factory ExcelFileWrapper.fromPlatformFile(PlatformFile platformFile) {
    return ExcelFileWrapper(
      name: platformFile.name,
      bytes: platformFile.bytes!,
      file: kIsWeb ? null : File(platformFile.path!),
    );
  }
}

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
    // ========== CAMPOS BÁSICOS OBLIGATORIOS ==========
    'denominacion': 'denominacion',
    'nombre': 'denominacion', // Alias
    'nombre_producto': 'denominacion', // Alias
    'descripcion': 'descripcion',
    'categoria_id': 'categoria_id',
    'categoria': 'categoria_id', // Se resolverá por nombre
    'sku': 'sku',
    'codigo': 'sku', // Alias
    'codigo_producto': 'sku', // Alias
    'precio_venta': 'precio_venta',
    'precio': 'precio_venta', // Alias
    'precio_venta_cup': 'precio_venta', // Alias
    
    // ========== INFORMACIÓN ADICIONAL ==========
    'denominacion_corta': 'denominacion_corta',
    'nombre_corto': 'denominacion_corta', // Alias
    'descripcion_corta': 'descripcion_corta',
    'nombre_comercial': 'nombre_comercial',
    'marca': 'nombre_comercial', // Alias
    'codigo_barras': 'codigo_barras',
    'barcode': 'codigo_barras', // Alias
    'ean': 'codigo_barras', // Alias
    'imagen': 'imagen',
    'url_imagen': 'imagen', // Alias
    'foto': 'imagen', // Alias
    
    // ========== UNIDADES DE MEDIDA ==========
    'unidad_medida': 'um',
    'um': 'um',
    'unidad': 'um', // Alias

    // ========== PROPIEDADES DE ALMACENAMIENTO ==========
    'es_refrigerado': 'es_refrigerado',
    'refrigerado': 'es_refrigerado', // Alias
    'requiere_refrigeracion': 'es_refrigerado', // Alias
    'es_fragil': 'es_fragil',
    'fragil': 'es_fragil', // Alias
    'es_peligroso': 'es_peligroso',
    'peligroso': 'es_peligroso', // Alias
    'es_por_lotes': 'es_por_lotes',
    'por_lotes': 'es_por_lotes', // Alias
    'manejo_lotes': 'es_por_lotes', // Alias
    
    // ========== PROPIEDADES COMERCIALES ==========
    'es_vendible': 'es_vendible',
    'vendible': 'es_vendible', // Alias
    'se_vende': 'es_vendible', // Alias
    'es_comprable': 'es_comprable',
    'comprable': 'es_comprable', // Alias
    'se_compra': 'es_comprable', // Alias
    'es_inventariable': 'es_inventariable',
    'inventariable': 'es_inventariable', // Alias
    'controla_inventario': 'es_inventariable', // Alias
    'es_servicio': 'es_servicio',
    'servicio': 'es_servicio', // Alias
    'es_producto_servicio': 'es_servicio', // Alias
    
    // ========== CONTROL DE STOCK ==========
    'stock_minimo': 'stock_minimo',
    'minimo': 'stock_minimo', // Alias
    'stock_min': 'stock_minimo', // Alias
    'stock_maximo': 'stock_maximo',
    'maximo': 'stock_maximo', // Alias
    'stock_max': 'stock_maximo', // Alias
    'dias_alert_caducidad': 'dias_alert_caducidad',
    'dias_alerta': 'dias_alert_caducidad', // Alias
    'alerta_caducidad': 'dias_alert_caducidad', // Alias

    // ========== OFERTAS Y PROMOCIONES ==========
    'es_oferta': 'es_oferta',
    'oferta': 'es_oferta', // Alias
    'en_oferta': 'es_oferta', // Alias
    'precio_oferta': 'precio_oferta',
    'precio_promocion': 'precio_oferta', // Alias
    'fecha_inicio_oferta': 'fecha_inicio_oferta',
    'inicio_oferta': 'fecha_inicio_oferta', // Alias
    'fecha_fin_oferta': 'fecha_fin_oferta',
    'fin_oferta': 'fecha_fin_oferta', // Alias

    // ========== PRODUCTOS ELABORADOS ==========
    'es_elaborado': 'es_elaborado',
    'elaborado': 'es_elaborado', // Alias
    'producto_elaborado': 'es_elaborado', // Alias
    'costo_produccion': 'costo_produccion',
    'costo_elaboracion': 'costo_produccion', // Alias
    
    // ========== PRECIOS Y COSTOS ==========
    'precio_costo': 'precio_costo',
    'costo': 'precio_costo', // Alias
    'costo_unitario': 'precio_costo', // Alias
    'precio_costo_cup': 'precio_costo', // Alias
    'costo_cup': 'precio_costo', // Alias
    'costo_real': 'precio_costo', // Alias para recepción (se mapea como precio_costo)
    'precio_compra': 'precio_costo', // Alias para recepción
    
    // ========== PROVEEDOR ==========
    'proveedor': 'proveedor',
    'nombre_proveedor': 'proveedor', // Alias
    'proveedor_nombre': 'proveedor', // Alias
    'id_proveedor': 'proveedor', // Alias
  };

  /// Selecciona archivo Excel
  static Future<ExcelFileWrapper?> pickExcelFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        allowMultiple: false,
      );

      if (result != null && result.files.isNotEmpty) {
        final platformFile = result.files.single;
        
        // En web, bytes siempre está disponible
        // En escritorio, necesitamos leer los bytes si no están disponibles
        Uint8List bytes;
        if (platformFile.bytes != null) {
          bytes = platformFile.bytes!;
        } else if (platformFile.path != null && !kIsWeb) {
          // Solo en escritorio, leer desde el path
          final file = File(platformFile.path!);
          bytes = await file.readAsBytes();
        } else {
          throw Exception('No se pudieron obtener los datos del archivo');
        }
        
        return ExcelFileWrapper(
          name: platformFile.name,
          bytes: bytes,
          file: kIsWeb ? null : (platformFile.path != null ? File(platformFile.path!) : null),
        );
      }
      return null;
    } catch (e) {
      throw Exception('Error al seleccionar archivo: $e');
    }
  }

  /// Lee y analiza el archivo Excel
  static Future<ExcelAnalysisResult> analyzeExcelFile(ExcelFileWrapper fileWrapper) async {
    try {
      print('📊 Analizando archivo: ${fileWrapper.name}');
      
      // Decodificar archivo Excel con máxima tolerancia
      final excel = _decodeExcelWithTolerance(fileWrapper.bytes);


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
        fileName: fileWrapper.name,
        totalRows: dataRows.length,
        headers: headers,
        columnAnalysis: columnAnalysis,
        missingRequiredFields: missingRequired,
        sampleData: _extractSampleData(dataRows, headers),
        isValid: missingRequired.isEmpty,
      );
    } catch (e) {
      print(e);
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
    ExcelFileWrapper fileWrapper,
    Map<String, String> finalColumnMapping, {
    Map<String, dynamic>? defaultValues,
    bool importWithStock = false,
    Map<String, dynamic>? stockConfig,
    String priceCurrency = 'USD',
    double? exchangeRate,
    Function(int, int)? onProgress,
  }) async {
    try {
      print('📦 Importando productos desde: ${fileWrapper.name}');
      
      // Decodificar archivo Excel con máxima tolerancia
      final excel = _decodeExcelWithTolerance(fileWrapper.bytes);
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
      
      // ✅ NUEVO: Obtener tasa de cambio SIEMPRE (necesaria para ambas direcciones de conversión)
      double? finalExchangeRate = exchangeRate;
      if (finalExchangeRate == null) {
        try {
          print('💱 Obteniendo tasa de cambio desde CurrencyService...');
          print('   - Moneda seleccionada en Excel: $priceCurrency');
          final rates = await CurrencyService.getCurrentRatesFromDatabase();
          
          print('   - Tasas obtenidas de BD: ${rates.length} registros');
          for (final rate in rates) {
            print('     • ${rate['moneda_origen']} → ${rate['tasa']} USD');
          }
          
          // Buscar la tasa correcta según la moneda seleccionada
          // La tasa en BD puede estar en dos formatos:
          // Formato 1: moneda_origen='CUP', tasa=0.002061855670103093 (1 CUP = X USD)
          // Formato 2: moneda_origen='USD', tasa=485 (1 USD = X CUP)
          
          var rateData = rates.firstWhere(
            (rate) => rate['moneda_origen'] == 'CUP',
            orElse: () => <String, dynamic>{},
          );
          
          if (rateData.isEmpty) {
            // Si no está en formato CUP→USD, buscar en formato USD→CUP
            rateData = rates.firstWhere(
              (rate) => rate['moneda_origen'] == 'USD',
              orElse: () => <String, dynamic>{},
            );
            
            if (rateData.isNotEmpty) {
              // Invertir la tasa: si 1 USD = 485 CUP, entonces 1 CUP = 1/485 USD
              final tasaUsdACup = (rateData['tasa'] as num?)?.toDouble() ?? 0;
              finalExchangeRate = 1.0 / tasaUsdACup;
              print('✅ Tasa invertida de BD: 1 USD = $tasaUsdACup CUP → 1 CUP = $finalExchangeRate USD');
            }
          } else {
            finalExchangeRate = (rateData['tasa'] as num?)?.toDouble();
            print('✅ Tasa obtenida de BD: 1 CUP = $finalExchangeRate USD');
          }
          
          if (finalExchangeRate == null || finalExchangeRate == 0) {
            print('⚠️ No se pudo obtener tasa válida de BD');
            print('   - Tasas disponibles: ${rates.map((r) => '${r['moneda_origen']}=${r['tasa']}').toList()}');
          }
        } catch (e) {
          print('❌ Error obteniendo tasa de cambio: $e');
        }
      }

      final results = ImportResult();
      final totalRows = dataRows.length;
      
      // Lista para almacenar productos importados con stock
      final List<Map<String, dynamic>> productosConStock = [];

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
              defaultValues: defaultValues,
              rowIndex: rowIndex,
              warnings: results.warnings,
            );

            // ✅ NUEVO: Convertir precio si es necesario usando CurrencyService
            // IMPORTANTE: Guardar valores ORIGINALES antes de convertir
            final precioVentaOriginal = (productData['precio_venta'] as num?)?.toDouble() ?? 0.0;
            final precioCostoOriginal = (productData['precio_costo'] as num?)?.toDouble();
            
            double precioVentaConvertido = precioVentaOriginal;
            double? precioCostoConvertido = precioCostoOriginal;
            
            if (priceCurrency == 'CUP' && finalExchangeRate != null && finalExchangeRate > 0) {
              // ✅ CORRECCIÓN: Excel en CUP
              // - precio_venta: guardar como está (ya en CUP)
              // - precio_costo: convertir a USD (CUP × tasa = USD)
              print('💱 Excel en CUP - Conversión de costo a USD:');
              print('   - Precio venta: $precioVentaOriginal CUP (se guarda como está)');
              
              if (precioCostoOriginal != null && precioCostoOriginal > 0) {
                precioCostoConvertido = precioCostoOriginal * finalExchangeRate;
                print('   - Precio costo: $precioCostoOriginal CUP → \$${precioCostoConvertido.toStringAsFixed(2)} USD');
              }
              
              productData['precio_venta_original_cup'] = precioVentaOriginal;  // CUP como está
              productData['precio_costo'] = precioCostoConvertido;  // Convertido a USD
              
            } else if (priceCurrency == 'USD' && finalExchangeRate != null && finalExchangeRate > 0) {
              // ✅ CORRECCIÓN: Excel en USD
              // - precio_venta: convertir a CUP (USD ÷ tasa = CUP)
              // - precio_costo: guardar como está (ya en USD)
              print('💱 Excel en USD - Conversión de venta a CUP:');
              
              precioVentaConvertido = precioVentaOriginal / finalExchangeRate;
              print('   - Precio venta: \$${precioVentaOriginal.toStringAsFixed(2)} USD → ${precioVentaConvertido.toStringAsFixed(2)} CUP');
              print('   - Precio costo: \$${precioCostoOriginal?.toStringAsFixed(2)} USD (se guarda como está)');
              
              productData['precio_venta_original_cup'] = precioVentaConvertido;  // Convertido a CUP
              // precioCostoUsd ya tiene el valor correcto (no necesita conversión)
              
            } else {
              // Sin tasa de conversión disponible
              print('⚠️ Sin tasa de conversión disponible para $priceCurrency');
              productData['precio_venta_original_cup'] = precioVentaOriginal;
            }

            // ✅ VALIDAR SI EL PRODUCTO YA EXISTE POR NOMBRE
            final denominacion = productData['denominacion'] as String;
            final productoExistente = await ProductService.findProductByNameAndStore(
              denominacion: denominacion,
              idTienda: idTienda,
            );
            
            int? productoId;
            
            if (productoExistente != null) {
              // ✅ PRODUCTO EXISTENTE: Reutilizar
              productoId = productoExistente['id'] as int;
              
              print('♻️ PRODUCTO EXISTENTE REUTILIZADO:');
              print('   - ID: $productoId');
              print('   - Nombre: $denominacion');
              print('   - SKU existente: ${productoExistente['sku']}');
              
              // ✅ NUEVO: Actualizar precio de costo en presentación base si está disponible
              if (productData.containsKey('precio_costo') && productData['precio_costo'] != null) {
                try {
                  final precioCosto = (productData['precio_costo'] as num?)?.toDouble() ?? 0.0;
                  print('💰 Actualizando precio de costo para producto existente: \$${precioCosto.toStringAsFixed(2)}');
                  
                  // Actualizar el precio_promedio en la presentación base (id_presentacion = 1)
                  await Supabase.instance.client
                      .from('app_dat_producto_presentacion')
                      .update({'precio_promedio': precioCosto})
                      .eq('id_producto', productoId)
                      .eq('id_presentacion', 1);
                  
                  print('✅ Precio de costo actualizado exitosamente');
                } catch (e) {
                  print('⚠️ Error actualizando precio de costo: $e');
                  results.warnings.add(ImportWarning(
                    row: rowIndex + 2,
                    message: 'Error actualizando precio de costo del producto: $e',
                    type: 'cost_price_update_error',
                  ));
                }
              }
              
              // Agregar warning informativo
              results.warnings.add(ImportWarning(
                row: rowIndex + 2,
                message: 'Producto "$denominacion" ya existe (ID: $productoId). Se reutilizó el producto existente.',
                type: 'product_reused',
              ));
              
              results.successCount++;
              results.successfulProducts.add(
                '$denominacion (Existente)',
              );
            } else {
              // ✅ PRODUCTO NUEVO: Insertar
              print('🆕 PRODUCTO NUEVO: Insertando "$denominacion"');
              
              // ✅ NUEVO: Buscar proveedor si está disponible
              int? idProveedor;
              if (productData.containsKey('proveedor') && productData['proveedor'] != null) {
                final nombreProveedor = productData['proveedor'].toString().trim();
                if (nombreProveedor.isNotEmpty) {
                  try {
                    print('🔍 Buscando proveedor: "$nombreProveedor"');
                    // Buscar proveedor por nombre en la tienda
                    final proveedoresResponse = await Supabase.instance.client
                        .from('app_dat_proveedor')
                        .select('id')
                        .eq('idtienda', idTienda)
                        .ilike('denominacion', '%$nombreProveedor%')
                        .limit(1);
                    
                    if (proveedoresResponse.isNotEmpty) {
                      idProveedor = proveedoresResponse.first['id'] as int;
                      print('✅ Proveedor encontrado: ID=$idProveedor');
                    } else {
                      print('⚠️ Proveedor no encontrado: "$nombreProveedor"');
                      results.warnings.add(ImportWarning(
                        row: rowIndex + 2,
                        message: 'Proveedor "$nombreProveedor" no encontrado en la tienda. Se dejará sin asignar.',
                        type: 'provider_not_found',
                      ));
                    }
                  } catch (e) {
                    print('❌ Error buscando proveedor: $e');
                    results.warnings.add(ImportWarning(
                      row: rowIndex + 2,
                      message: 'Error buscando proveedor: $e',
                      type: 'provider_search_error',
                    ));
                  }
                }
              }
              
              // Agregar proveedor a productData si se encontró
              if (idProveedor != null) {
                productData['id_proveedor'] = idProveedor;
              }
              
              // ✅ CRÍTICO: Preparar datos de precios con valor ORIGINAL en CUP
              // precio_venta_cup SIEMPRE debe estar en CUP (valor original del Excel)
              List<Map<String, dynamic>>? preciosData;
              if (productData.containsKey('precio_venta_original_cup')) {
                final precioVentaCup = (productData['precio_venta_original_cup'] as num?)?.toDouble() ?? 0.0;
                print('💾 Guardando precio_venta_cup: $precioVentaCup CUP (valor original)');
                preciosData = [
                  {
                    'precio_venta_cup': precioVentaCup,  // ✅ ORIGINAL en CUP
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
              
              // ✅ NUEVO: Preparar datos de presentación base con precio de costo EN USD
              // El precio_costo ya fue convertido en productData en la sección anterior
              // IMPORTANTE: precio_promedio SIEMPRE debe estar en USD
              // ✅ VALIDACIÓN: Mismo criterio que en SQL
              dynamic precioCostoFinal;
              
              if (productData.containsKey('precio_costo')) {
                final precioCostoRaw = (productData['precio_costo'] as num?)?.toDouble();
                
                // ✅ MISMO CRITERIO QUE SQL:
                // - No null
                // - No string 'null'
                // - Mayor a 0
                if (precioCostoRaw != null && precioCostoRaw > 0) {
                  precioCostoFinal = precioCostoRaw;
                  print('💾 Guardando precio_promedio en USD: \$${precioCostoRaw.toStringAsFixed(2)}');
                } else {
                  precioCostoFinal = null;
                  print('⚠️ precio_costo es null o <= 0, precio_promedio será null');
                }
              } else {
                precioCostoFinal = null;
                print('⚠️ No hay precio_costo en productData, precio_promedio será null');
              }
              
              List<Map<String, dynamic>>? presentacionesData = [
                {
                  'id_presentacion': 1, // ID 1 = Presentación "Unidad"
                  'cantidad': 1.0, // 1 unidad base = 1 unidad
                  'es_base': true,
                  'precio_promedio': precioCostoFinal, // En USD (puede ser null)
                },
              ];

              // Insertar producto
              print('\n📦 ===== DATOS FINALES ANTES DE INSERTAR =====');
              print('📦 productData: $productData');
              print('📦 preciosData: $preciosData');
              print('📦 presentacionesData: $presentacionesData');
              print('📦 subcategoriasData: $subcategoriasData');
              
              final insertResult = await ProductService.insertProductoCompleto(
                productoData: productData,
                preciosData: preciosData,
                subcategoriasData: subcategoriasData,
                presentacionesData: presentacionesData,
              );
              
              print('\n📦 ===== RESULTADO DE INSERCIÓN =====');
              print('🔍 Estructura completa de insertResult: $insertResult');
              print('🔍 Claves disponibles: ${insertResult.keys.toList()}');
              
              // Intentar obtener el ID del producto de diferentes ubicaciones posibles
              productoId = (insertResult['id_producto'] ?? 
                                 insertResult['producto_id'] ?? 
                                 insertResult['data']?['id_producto'] ??
                                 insertResult['data']?['producto_id']) as int?;
              
              print('🎯 ID del producto obtenido: $productoId');

              results.successCount++;
              results.successfulProducts.add(
                productData['denominacion'] ?? 'Producto ${rowIndex + 1}',
              );
            }
            
            // Si se importa con stock, guardar info del producto
            print('🔍 Verificando si agregar producto a lista de stock (fila ${rowIndex + 2}):');
            print('   - importWithStock: $importWithStock');
            print('   - productoId: $productoId');
            print('   - stockConfig: ${stockConfig != null ? "presente" : "null"}');
            
            if (importWithStock && productoId != null && stockConfig != null) {
              // ✅ NUEVO: Pasar precio_costo convertido a USD para recepción
              final precioCostoParaRecepcion = (productData['precio_costo'] as num?)?.toDouble() ?? 0.0;
              productosConStock.add({
                'id_producto': productoId,
                'row': row,
                'rowIndex': rowIndex,
                'precio_costo_usd': precioCostoParaRecepcion,  // ✅ NUEVO: Precio convertido a USD
                'precio_venta_original_cup': precioVentaOriginal,  // ✅ NUEVO: Precio venta original en CUP
              });
              print('   ✅ Producto $productoId agregado a lista de stock (total: ${productosConStock.length})');
            } else {
              print('   ❌ NO agregado - Razones:');
              if (!importWithStock) print('      - importWithStock es false');
              if (productoId == null) print('      - productoId es null');
              if (stockConfig == null) print('      - stockConfig es null');
            }
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

      // Crear recepción masiva si hay productos con stock
      print('🔍 Verificando creación de recepción masiva...');
      print('   - importWithStock: $importWithStock');
      print('   - productosConStock.length: ${productosConStock.length}');
      print('   - stockConfig: $stockConfig');
      
      if (importWithStock && productosConStock.isNotEmpty && stockConfig != null) {
        print('✅ Condiciones cumplidas, creando recepción masiva...');
        try {
          await _createBulkStockReception(
            productosConStock: productosConStock,
            headers: headers,
            stockConfig: stockConfig,
            idTienda: idTienda,
            warnings: results.warnings,
            priceCurrency: priceCurrency,
            exchangeRate: finalExchangeRate,
          );
          print('✅ Recepción masiva creada exitosamente');
        } catch (e, stackTrace) {
          print('❌ Error creando recepción masiva: $e');
          print('❌ StackTrace: $stackTrace');
          results.errors.add(
            ImportError(
              row: 0,
              message: 'Error creando recepción de inventario: $e',
              data: {},
            ),
          );
        }
      } else {
        print('⚠️ No se creará recepción masiva:');
        if (!importWithStock) print('   - importWithStock es false');
        if (productosConStock.isEmpty) print('   - productosConStock está vacío');
        if (stockConfig == null) print('   - stockConfig es null');
      }

      return results;
    } catch (e) {
      throw Exception('Error durante la importación: $e');
    }
  }

  /// Decodifica un archivo Excel con máxima tolerancia a errores de formato
  static Excel _decodeExcelWithTolerance(Uint8List bytes) {
    try {
      // Intento 1: Decodificación normal
      return Excel.decodeBytes(bytes);
    } catch (e) {
      final errorMsg = e.toString();
      print('⚠️ Advertencia al decodificar Excel: $errorMsg');
      
      // Si es un error de formato, intentar con estrategias alternativas
      if (errorMsg.contains('numFmtId') || 
          errorMsg.contains('custom') || 
          errorMsg.contains('format')) {
        print('🔄 Intentando decodificación tolerante...');
        
        try {
          // Intento 2: Decodificar de nuevo (a veces funciona en el segundo intento)
          return Excel.decodeBytes(bytes);
        } catch (e2) {
          print('⚠️ Segundo intento falló: ${e2.toString()}');
          
          // Intento 3: Si todo falla, lanzar error con mensaje claro
          throw Exception(
            'No se pudo leer el archivo Excel debido a formatos incompatibles.\n\n'
            'Soluciones recomendadas:\n'
            '1. Guarda el archivo como CSV y ábrelo de nuevo en Excel\n'
            '2. Copia los datos a un nuevo libro de Excel en blanco\n'
            '3. Usa "Pegado Especial > Valores" al copiar los datos\n\n'
            'Error técnico: $errorMsg'
          );
        }
      }
      
      // Si no es un error de formato conocido, relanzar
      rethrow;
    }
  }

  /// Obtiene el valor de una celda, manejando fórmulas correctamente
  /// Este método es extremadamente tolerante y maneja cualquier tipo de celda
  static String? _getCellValue(Data? cell, {bool returnZeroOnError = false}) {
    if (cell == null) return returnZeroOnError ? '0' : null;
    
    try {
      final cellValue = cell.value;
      
      if (cellValue == null) {
        return returnZeroOnError ? '0' : null;
      }
      
      // Intentar manejar diferentes tipos de valores con máxima tolerancia
      try {
        // Tipo 1: TextCellValue
        if (cellValue is TextCellValue) {
          try {
            // TextCellValue.value es un TextSpan, convertir a String
            final textValue = cellValue.value.toString();
            return textValue.isNotEmpty ? textValue.trim() : null;
          } catch (e) {
            // Fallback: intentar toString directo
            return cellValue.toString().trim();
          }
        }
        
        // Tipo 2: IntCellValue
        if (cellValue is IntCellValue) {
          try {
            return cellValue.value.toString();
          } catch (e) {
            return cellValue.toString();
          }
        }
        
        // Tipo 3: DoubleCellValue
        if (cellValue is DoubleCellValue) {
          try {
            final doubleVal = cellValue.value;
            // Si es entero, mostrarlo sin decimales
            if (doubleVal == doubleVal.toInt()) {
              return doubleVal.toInt().toString();
            }
            // Si tiene decimales, preservarlos
            return doubleVal.toString();
          } catch (e) {
            return cellValue.toString();
          }
        }
        
        // Tipo 4: FormulaCellValue
        if (cellValue is FormulaCellValue) {
          try {
            final formulaStr = cellValue.toString();
            return formulaStr.isNotEmpty ? formulaStr.trim() : null;
          } catch (e) {
            return cellValue.toString();
          }
        }
        
        // Tipo 5: BoolCellValue u otros
        try {
          final strValue = cellValue.toString();
          return strValue.isNotEmpty ? strValue.trim() : null;
        } catch (e) {
          // Último recurso: intentar obtener cualquier representación
          return cellValue.runtimeType.toString();
        }
      } catch (e) {
        // Si falla el manejo de tipos, intentar toString directo
        try {
          return cellValue.toString().trim();
        } catch (e2) {
          print('⚠️ Error crítico leyendo celda: $e2');
          return returnZeroOnError ? '0' : null;
        }
      }
    } catch (e) {
      print('⚠️ Error general leyendo celda: $e');
      if (returnZeroOnError) {
        return '0';
      }
    }
    
    return returnZeroOnError ? '0' : null;
  }

  /// Convierte una fila de Excel a datos de producto
  static Map<String, dynamic> _convertRowToProductData(
    List<Data?> row,
    List<String> headers,
    Map<String, String> columnMapping,
    Map<String, int> categoryMap,
    int idTienda, {
    Map<String, dynamic>? defaultValues,
    int? rowIndex,
    List<ImportWarning>? warnings,
  }) {
    final productData = <String, dynamic>{'id_tienda': idTienda};

    // PRIMERO: Leer valores del Excel
    for (int i = 0; i < headers.length && i < row.length; i++) {
      final header = headers[i];
      final cellValueStr = _getCellValue(row[i]);

      if (cellValueStr == null || cellValueStr.trim().isEmpty) continue;

      final mappedField = columnMapping[header];
      if (mappedField == null) continue;

      // Procesar según el tipo de campo
      switch (mappedField) {
        case 'categoria_id':
          // Resolver categoría por nombre o ID
          final categoryValue = cellValueStr.toLowerCase().trim();
          print('📖 PASO 1 - Leyendo categoría del Excel: "$cellValueStr"');
          if (categoryMap.containsKey(categoryValue)) {
            productData['id_categoria'] = categoryMap[categoryValue];
            print('   ✅ Categoría encontrada por nombre: ${categoryMap[categoryValue]}');
          } else {
            // Intentar parsear como ID directo
            final categoryId = int.tryParse(cellValueStr);
            if (categoryId != null) {
              productData['id_categoria'] = categoryId;
              print('   ✅ Categoría parseada como ID: $categoryId');
            } else {
              throw Exception('Categoría no encontrada: $cellValueStr');
            }
          }
          print('   💾 productData["id_categoria"] después del Excel = ${productData['id_categoria']}');
          break;

        case 'precio_venta':
        case 'precio_oferta':
        case 'costo_produccion':
        case 'precio_costo':
          // Usar _parseNumericValue para manejar formatos de moneda
          final doubleValue = _parseNumericValue(cellValueStr);
          if (doubleValue != null) {
            productData[mappedField] = doubleValue;
            // ✅ NUEVO: Si es precio_costo, también guardarlo como costo_real para recepción
            if (mappedField == 'precio_costo') {
              productData['costo_real'] = doubleValue;
            }
          } else {
            // No se pudo parsear, usar 0 y agregar warning
            productData[mappedField] = 0.0;
            if (mappedField == 'precio_costo') {
              productData['costo_real'] = 0.0;
            }
            warnings?.add(ImportWarning(
              row: rowIndex ?? 0,
              message: 'Campo "$mappedField" no pudo parsearse ("$cellValueStr"), se cambió a 0',
              type: 'value_changed',
            ));
          }
          break;

        case 'stock_minimo':
        case 'stock_maximo':
        case 'dias_alert_caducidad':
          final intValue = int.tryParse(cellValueStr);
          if (intValue != null) {
            productData[mappedField] = intValue;
          } else {
            // No se pudo parsear, usar 0 y agregar warning
            productData[mappedField] = 0;
            warnings?.add(ImportWarning(
              row: rowIndex ?? 0,
              message: 'Campo "$mappedField" no pudo parsearse ("$cellValueStr"), se cambió a 0',
              type: 'value_changed',
            ));
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
          productData[mappedField] = _parseBooleanValue(cellValueStr);
          break;

        case 'fecha_inicio_oferta':
        case 'fecha_fin_oferta':
          final dateValue = _parseDateValue(cellValueStr);
          if (dateValue != null) {
            productData[mappedField] = dateValue.toIso8601String().substring(
              0,
              10,
            );
          }
          break;

        default:
          productData[mappedField] = cellValueStr.trim();
      }
    }
    
    // SEGUNDO: Aplicar valores por defecto
    if (defaultValues != null) {
      print('📏 PASO 2 - Aplicando valores por defecto...');
      print('   📝 defaultValues completo: $defaultValues');
      for (final entry in defaultValues.entries) {
        final key = entry.key == 'categoria_id' ? 'id_categoria' : entry.key;
        print('   🔑 Procesando: ${entry.key} -> $key = ${entry.value}');
        
        // CATEGORÍA: Siempre sobrescribir si el usuario la seleccionó en el menú
        if (key == 'id_categoria') {
          final oldValue = productData[key];
          print('   🔍 Valor anterior en productData: $oldValue');
          print('   🔍 Valor nuevo de defaultValues: ${entry.value}');
          productData[key] = entry.value;
          print('   💾 productData["id_categoria"] después de sobrescribir = ${productData[key]}');
          if (oldValue != null && oldValue != entry.value) {
            print('   🔄 Sobrescrito $key: $oldValue -> ${entry.value} (selección del usuario)');
            warnings?.add(ImportWarning(
              row: rowIndex ?? 0,
              message: 'Categoría del Excel ($oldValue) sobrescrita por selección del usuario (${entry.value})',
              type: 'category_override',
            ));
          } else {
            print('   ✅ Aplicado $key = ${entry.value} (selección del usuario)');
          }
        }
        // OTROS CAMPOS: Solo aplicar si no existen en Excel
        else if (!productData.containsKey(key)) {
          productData[key] = entry.value;
          print('   ✅ Aplicado $key = ${entry.value} (no existía en Excel)');
        } else {
          print('   ⏭️ Omitido $key (ya existe con valor: ${productData[key]})');
        }
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

    // ✅ NUEVO: Generar SKU automáticamente si no está disponible
    if (!productData.containsKey('sku') || 
        productData['sku'].toString().isEmpty) {
      print('🏷️ SKU no disponible en Excel, generando automáticamente...');
      
      final denominacion = productData['denominacion'].toString();
      final idCategoria = productData['id_categoria'];
      
      // Generar SKU basado en: Categoría + Subcategoría + Denominación + Timestamp
      final generatedSku = _generateSkuForProduct(
        denominacion: denominacion,
        idCategoria: idCategoria,
      );
      
      productData['sku'] = generatedSku;
      
      print('✅ SKU generado automáticamente: $generatedSku');
      
      // Agregar warning informativo
      warnings?.add(ImportWarning(
        row: rowIndex ?? 0,
        message: 'SKU no proporcionado en Excel. Se generó automáticamente: $generatedSku',
        type: 'sku_generated',
      ));
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

  /// Genera template Excel para descarga con todos los campos disponibles
  static Future<Uint8List> generateTemplate() async {
    final excel = Excel.createExcel();
    final sheet = excel['Productos'];
    
    // Encabezados del template - CAMPOS COMPLETOS
    final headers = [
      // Obligatorios
      'denominacion',
      'descripcion',
      'categoria_id',
      'sku',
      'precio_venta',
      // Información adicional
      'denominacion_corta',
      'descripcion_corta',
      'nombre_comercial',
      'codigo_barras',
      'imagen',
      // Unidad de medida
      'unidad_medida',
      // Propiedades de almacenamiento
      'es_refrigerado',
      'es_fragil',
      'es_peligroso',
      'es_por_lotes',
      // Propiedades comerciales
      'es_vendible',
      'es_comprable',
      'es_inventariable',
      'es_servicio',
      // Control de stock
      'stock_minimo',
      'stock_maximo',
      'dias_alert_caducidad',
      // Ofertas
      'es_oferta',
      'precio_oferta',
      'fecha_inicio_oferta',
      'fecha_fin_oferta',
      // Productos elaborados
      'es_elaborado',
      'costo_produccion',
    ];
    
    // Agregar encabezados
    for (int i = 0; i < headers.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
    }
    
    // Agregar fila de ejemplo
    final exampleData = [
      // Obligatorios
      'Producto Ejemplo',
      'Descripción completa del producto ejemplo',
      '1',
      'PROD001',
      '25.50',
      // Información adicional
      'Prod Ej',
      'Desc corta',
      'Marca Ejemplo',
      '1234567890123',
      'https://ejemplo.com/imagen.jpg',
      // Unidad de medida
      'und',
      // Propiedades de almacenamiento
      'false',
      'false',
      'false',
      'false',
      // Propiedades comerciales
      'true',
      'true',
      'true',
      'false',
      // Control de stock
      '10',
      '100',
      '30',
      // Ofertas
      'false',
      '0',
      '',
      '',
      // Productos elaborados
      'false',
      '0',
    ];
    
    for (int i = 0; i < exampleData.length; i++) {
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 1)).value = TextCellValue(exampleData[i]);
    }
    
    return Uint8List.fromList(excel.encode()!);
  }

  /// Limpia un valor numérico eliminando símbolos de moneda, comas, espacios, etc.
  static double? _parseNumericValue(String value) {
    if (value.isEmpty) return null;
    
    // Eliminar espacios en blanco
    String cleaned = value.trim();
    
    // Eliminar símbolos de moneda comunes
    cleaned = cleaned.replaceAll(RegExp(r'[\$€£¥₩₽₹CUP]'), '');
    
    // Eliminar espacios adicionales
    cleaned = cleaned.replaceAll(' ', '');
    
    // Reemplazar comas por puntos (formato decimal)
    // Si hay múltiples comas, asumir que son separadores de miles
    if (cleaned.contains(',')) {
      final commaCount = ','.allMatches(cleaned).length;
      if (commaCount == 1 && cleaned.indexOf(',') > cleaned.length - 4) {
        // Única coma cerca del final = separador decimal
        cleaned = cleaned.replaceAll(',', '.');
      } else {
        // Múltiples comas = separadores de miles, eliminarlas
        cleaned = cleaned.replaceAll(',', '');
      }
    }
    
    // Intentar parsear
    return double.tryParse(cleaned);
  }

  /// Crea una operación de recepción masiva con todos los productos importados
  static Future<void> _createBulkStockReception({
    required List<Map<String, dynamic>> productosConStock,
    required List<String> headers,
    required Map<String, dynamic> stockConfig,
    required int idTienda,
    List<ImportWarning>? warnings,
    String priceCurrency = 'USD',
    double? exchangeRate,
  }) async {
    final columnMapping = stockConfig['columnMapping'] as Map<String, String>;
    final locationId = stockConfig['locationId'] as int;
    
    print('📦 Creando recepción masiva para ${productosConStock.length} productos');
    print('📍 Ubicación ID: $locationId');
    print('🗺️ Mapeo de columnas: $columnMapping');
    
    List<Map<String, dynamic>> productos = [];
    int productosDescartados = 0;
    
    for (final productoInfo in productosConStock) {
      final productoId = productoInfo['id_producto'] as int;
      final row = productoInfo['row'] as List<Data?>;
      final rowIndex = productoInfo['rowIndex'] as int;
      
      print('\n🔍 Procesando producto ID=$productoId (fila ${rowIndex + 2})');
      
      double? cantidad;
      double? precioCompra;
      String? cantidadRaw;
      String? precioRaw;
      
      // Extraer valores de la fila usando _getCellValue para manejar fórmulas
      for (int j = 0; j < headers.length && j < row.length; j++) {
        final header = headers[j];
        final cellValueStr = _getCellValue(row[j]);
        
        if (cellValueStr == null || cellValueStr.trim().isEmpty) continue;
        
        if (columnMapping['cantidad'] == header) {
          cantidadRaw = cellValueStr;
          cantidad = _parseNumericValue(cantidadRaw);
          print('   📦 Cantidad: "$cantidadRaw" -> $cantidad');
        } else if (columnMapping['precio_compra'] == header || columnMapping['precio_costo'] == header) {
          // Aceptar tanto 'precio_compra' como 'precio_costo'
          precioRaw = cellValueStr;
          precioCompra = _parseNumericValue(precioRaw);
          print('   💵 Precio: "$precioRaw" -> $precioCompra');
          
          // ✅ NUEVO: Convertir precio si es necesario
          if (priceCurrency != 'USD' && exchangeRate != null && exchangeRate > 0 && precioCompra != null) {
            final precioOriginal = precioCompra;
            precioCompra = precioCompra * exchangeRate;  // ✅ Convertir a USD
            print('   💱 Precio convertido: $precioOriginal $priceCurrency → \$${precioCompra.toStringAsFixed(2)} USD');
          } else if (priceCurrency == 'USD') {
            print('   💵 Precio ya está en USD: \$${precioCompra?.toStringAsFixed(2)}');
          }
        }
      }
      
      // Validar datos con logs detallados
      // ✅ NUEVO: Obtener precio final para validación
      double precioValidacion = precioCompra ?? 0.0;
      if (precioValidacion == 0.0) {
        final productoInfo = productosConStock.firstWhere(
          (p) => p['id_producto'] == productoId,
          orElse: () => <String, dynamic>{},
        );
        if (productoInfo.containsKey('precio_costo_usd')) {
          precioValidacion = (productoInfo['precio_costo_usd'] as num?)?.toDouble() ?? 0.0;
        }
      }
      
      print('   ✅ Validación:');
      print('      - Cantidad: $cantidad ${cantidad != null && cantidad > 0 ? "✅" : "❌ (debe ser > 0)"}');
      print('      - Precio: $precioValidacion ${precioValidacion > 0 ? "✅" : "❌ (debe ser > 0)"}');
      
      if (cantidad != null && cantidad > 0 && precioValidacion > 0) {
        // Obtener el ID del registro de presentación base (PK de app_dat_producto_presentacion)
        int? idProductoPresentacion;
        try {
          final basePresentation = await ProductService.getBasePresentacion(productoId);
          if (basePresentation != null) {
            // getBasePresentacion retorna 'id_presentacion' que es el PK del registro
            idProductoPresentacion = basePresentation['id_presentacion'] as int?;
            print('  📦 ID presentación obtenido para producto $productoId: $idProductoPresentacion');
          } else {
            print('  ⚠️ Producto $productoId no tiene presentación base');
          }
        } catch (e) {
          print('  ❌ Error obteniendo presentación para producto $productoId: $e');
        }
        
        // ✅ NUEVO: Obtener precio_costo_usd y precio_venta_original_cup del producto
        double precioFinal = precioCompra ?? 0.0;
        double precioVentaCup = 0.0;
        
        // Si el precio no se encontró en la fila, intentar obtener del productosConStock
        final productoInfo = productosConStock.firstWhere(
          (p) => p['id_producto'] == productoId,
          orElse: () => <String, dynamic>{},
        );
        
        if (precioFinal == 0.0 && productoInfo.containsKey('precio_costo_usd')) {
          precioFinal = (productoInfo['precio_costo_usd'] as num?)?.toDouble() ?? 0.0;
          print('   💰 Usando precio_costo_usd del producto: \$${precioFinal.toStringAsFixed(2)}');
        }
        
        if (productoInfo.containsKey('precio_venta_original_cup')) {
          precioVentaCup = (productoInfo['precio_venta_original_cup'] as num?)?.toDouble() ?? 0.0;
          print('   💾 Usando precio_venta_original_cup del producto: $precioVentaCup CUP');
        }
        
        productos.add({
          'id_producto': productoId,
          'id_presentacion': idProductoPresentacion,
          'id_ubicacion': locationId,
          'cantidad': cantidad,
          'precio_unitario': precioFinal,  // ✅ En USD (convertido si era necesario)
        });
        print('   ✅ AGREGADO - Cantidad: $cantidad, Precio: \$$precioFinal, Subtotal: \$${cantidad * precioFinal}');
      } else {
        productosDescartados++;
        print('   ❌ DESCARTADO - Razones:');
        
        String razon = '';
        if (cantidad == null || cantidad <= 0) {
          razon = cantidad == null ? 'Cantidad no pudo parsearse ("$cantidadRaw")' : 'Cantidad es 0 o negativa: $cantidad';
          print('      - $razon');
        }
        if (precioValidacion <= 0) {
          final precioRazon = 'Precio es 0 o negativo: $precioValidacion';
          razon = razon.isEmpty ? precioRazon : '$razon, $precioRazon';
          print('      - $precioRazon');
        }
        
        warnings?.add(ImportWarning(
          row: rowIndex + 2,
          message: 'Producto ID=$productoId no se agregó al inventario: $razon',
          type: 'stock_skipped',
        ));
      }
    }
    
    if (productos.isEmpty) {
      print('⚠️ No hay productos válidos para crear recepción');
      return;
    }
    
    print('📦 Creando operación de recepción con ${productos.length} productos válidos');
    
    // Obtener UUID del usuario
    final userPrefs = UserPreferencesService();
    final userUuid = await userPrefs.getUserId();
    
    if (userUuid == null) {
      throw Exception('No se pudo obtener UUID del usuario');
    }
    
    // Calcular monto total
    final montoTotal = productos.fold<double>(
      0.0,
      (sum, p) => sum + (((p['precio_unitario'] as num?)?.toDouble() ?? 0.0) * ((p['cantidad'] as num?)?.toDouble() ?? 0.0)),
    );
    
    // Crear operación de recepción
    final result = await InventoryService.insertInventoryReception(
      entregadoPor: 'Importación Excel',
      recibidoPor: 'Sistema',
      idTienda: idTienda,
      montoTotal: montoTotal,
      motivo: 1, // Motivo: Importación
      observaciones: 'Importación masiva desde Excel - ${productos.length} productos',
      productos: productos,
      uuid: userUuid,
      monedaFactura: 'USD',
    );
    
    final idOperacion = result['id_operacion'] as int?;
    
    if (idOperacion == null) {
      throw Exception('No se obtuvo ID de operación');
    }
    
    print('📦 Operación de recepción creada: ID=$idOperacion');
    
    // Completar operación automáticamente
    await InventoryService.completeOperation(
      idOperacion: idOperacion,
      comentario: 'Importación automática completada',
      uuid: userUuid,
    );
    
    print('✅ Recepción masiva completada exitosamente');
  }

  /// Genera un SKU automáticamente basado en categoría y denominación del producto
  static String _generateSkuForProduct({
    required String denominacion,
    required int idCategoria,
  }) {
    try {
      print('🏷️ Generando SKU automáticamente...');
      print('   - Denominación: $denominacion');
      print('   - ID Categoría: $idCategoria');

      // Limpiar denominación: solo letras y números, convertir a mayúsculas
      final cleanDenom = denominacion
          .replaceAll(RegExp(r'[^a-zA-Z0-9\s]'), '') // Remover caracteres especiales
          .trim()
          .toUpperCase();

      // Tomar primeras 3 letras de la denominación
      String skuPart1 = cleanDenom.length >= 3 
          ? cleanDenom.substring(0, 3) 
          : cleanDenom.padRight(3, 'X');

      // Usar ID de categoría (máximo 3 dígitos)
      String skuPart2 = idCategoria.toString().padLeft(3, '0').substring(0, 3);

      // Agregar timestamp para unicidad (últimos 3 dígitos)
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      String skuPart3 = timestamp.substring(timestamp.length - 3);

      // Combinar: DDD-CCC-TTT (Denominación-Categoría-Timestamp)
      final generatedSku = '$skuPart1$skuPart2$skuPart3';

      print('✅ SKU generado: $generatedSku');
      print('   - Parte 1 (Denominación): $skuPart1');
      print('   - Parte 2 (Categoría): $skuPart2');
      print('   - Parte 3 (Timestamp): $skuPart3');

      return generatedSku;
    } catch (e) {
      print('❌ Error generando SKU: $e');
      // Fallback: usar timestamp simple
      return 'SKU${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}';
    }
  }
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
  List<ImportWarning> warnings = []; // Eventos alternativos

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

/// Warning de importación (eventos alternativos)
class ImportWarning {
  final int row;
  final String message;
  final String type; // 'value_changed', 'category_override', 'stock_skipped', 'product_reused', etc.

  ImportWarning({required this.row, required this.message, required this.type});
}
