import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import '../models/ai_product_models.dart';
import '../services/product_service.dart';
import '../services/supplier_service.dart';
import '../services/user_preferences_service.dart';

class AiProductGenerationService {
  String? validatePrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return 'Escribe un prompt para generar productos.';
    }
    if (trimmed.length < 8) {
      return 'El prompt es muy corto. Describe mejor los productos.';
    }
    return null;
  }

  Future<ProductAiReferenceData> loadReferenceData() async {
    final categories = await ProductService.getCategorias();
    final presentations = await ProductService.getPresentaciones();
    final units = await ProductService.getUnidadesMedida();

    final subcategoryFutures =
        categories.map((category) async {
          final id = category['id'];
          if (id is! int) return <Map<String, dynamic>>[];
          final subcategories = await ProductService.getSubcategorias(id);
          return subcategories
              .map((subcat) => {...subcat, 'idcategoria': id})
              .toList();
        }).toList();

    final subcategoriesNested = await Future.wait(subcategoryFutures);
    final subcategories = subcategoriesNested.expand((items) => items).toList();

    final suppliers = await SupplierService.getAllSuppliers();
    final supplierMaps =
        suppliers
            .map(
              (supplier) => <String, dynamic>{
                'id': supplier.id,
                'denominacion': supplier.denominacion,
                'sku_codigo': supplier.skuCodigo,
              },
            )
            .toList();

    return ProductAiReferenceData(
      categories: List<Map<String, dynamic>>.from(categories),
      subcategories: List<Map<String, dynamic>>.from(subcategories),
      presentations: List<Map<String, dynamic>>.from(presentations),
      units: List<Map<String, dynamic>>.from(units),
      suppliers: supplierMaps,
    );
  }

  Future<List<AiProductDraft>> generateDrafts({
    required String prompt,
    required ProductAiReferenceData referenceData,
  }) async {
    final validationError = validatePrompt(prompt);
    if (validationError != null) {
      throw Exception(validationError);
    }

    final config = await GeminiConfig.load();
    if (!config.hasApiKey) {
      throw Exception(
        'Configura api_key en la tabla config_asistant_model para usar la IA.',
      );
    }

    final requestBody = config.applyAuthToBody(
      config.isMuleRouter
          ? {
            'model': config.model,
            'messages': [
              {'role': 'system', 'content': 'You are a helpful assistant.'},
              {
                'role': 'user',
                'content': _buildPrompt(prompt.trim(), referenceData),
              },
            ],
          }
          : {
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {'text': _buildPrompt(prompt.trim(), referenceData)},
                ],
              },
            ],
            'generationConfig': {
              'temperature': 0.35,
              'maxOutputTokens': 1400,
              'response_mime_type': 'application/json',
            },
          },
    );

    final uri = config.buildUri(endpoint: 'generateContent');
    final headers = config.buildHeaders();

    final response = await http
        .post(uri, headers: headers, body: jsonEncode(requestBody))
        .timeout(const Duration(seconds: 40));

    if (response.statusCode != 200) {
      throw Exception('Error en IA (${response.statusCode}): ${response.body}');
    }

    final data = jsonDecode(response.body);
    final text = _extractResponseText(data);
    final jsonText = _extractJson(text);
    final parsed = jsonDecode(jsonText);

    if (parsed is Map<String, dynamic> && parsed['error'] != null) {
      throw Exception(parsed['error'].toString());
    }

    if (parsed is! Map<String, dynamic>) {
      throw Exception('Respuesta de IA inválida.');
    }

    return _parseDrafts(parsed, referenceData);
  }

  Future<AiProductCreationResult> createProducts(
    List<AiProductDraft> drafts,
  ) async {
    final userPrefs = UserPreferencesService();
    final idTienda = await userPrefs.getIdTienda();
    if (idTienda == null) {
      throw Exception('No se encontró ID de tienda');
    }

    int createdCount = 0;
    final errors = <String>[];

    for (final draft in drafts) {
      if (!draft.isValid) {
        final name =
            draft.denominacion.isNotEmpty
                ? draft.denominacion
                : 'Producto sin nombre';
        errors.add('Faltan datos para "$name"');
        continue;
      }

      try {
        final productoData = draft.buildProductoData(idTienda: idTienda);
        final subcategoriasData = draft.buildSubcategoriasData();
        final presentacionesData = draft.buildPresentacionesData();
        final preciosData = draft.buildPreciosData();

        final result = await ProductService.insertProductoCompleto(
          productoData: productoData,
          subcategoriasData: subcategoriasData,
          presentacionesData: presentacionesData,
          preciosData: preciosData,
        );

        final productId = _extractProductId(result);
        if (productId == null) {
          errors.add('No se pudo obtener ID para ${draft.denominacion}');
          continue;
        }

        final presentacionUnidadMedidaData =
            draft.buildPresentacionUnidadMedidaData();
        if (presentacionUnidadMedidaData.isNotEmpty) {
          await ProductService.insertPresentacionUnidadMedida(
            productId: productId,
            presentacionUnidadMedidaData: presentacionUnidadMedidaData,
          );
        }

        createdCount += 1;
      } catch (e) {
        errors.add(
          'Error creando ${draft.denominacion.isNotEmpty ? draft.denominacion : 'producto'}: $e',
        );
      }
    }

    return AiProductCreationResult(createdCount: createdCount, errors: errors);
  }

  List<AiProductDraft> _parseDrafts(
    Map<String, dynamic> parsed,
    ProductAiReferenceData referenceData,
  ) {
    final productsRaw = parsed['productos'] ?? parsed['products'] ?? [];
    if (productsRaw is! List) {
      throw Exception('La IA no devolvió una lista de productos válida.');
    }

    final drafts = <AiProductDraft>[];
    for (int index = 0; index < productsRaw.length; index++) {
      final raw = productsRaw[index];
      if (raw is! Map<String, dynamic>) continue;
      drafts.add(_mapToDraft(raw, referenceData, index));
    }

    if (drafts.isEmpty) {
      throw Exception('No se generaron productos válidos.');
    }

    return drafts;
  }

  AiProductDraft _mapToDraft(
    Map<String, dynamic> raw,
    ProductAiReferenceData referenceData,
    int index,
  ) {
    final denominacion = _string(raw['denominacion'] ?? raw['nombre']) ?? '';
    String? sku = _string(raw['sku']);
    if (sku == null || sku.trim().isEmpty) {
      sku = _generateSku(denominacion, index);
    }

    final categoryData = raw['categoria'] ?? raw['category'];
    int? categoryId =
        _extractId(categoryData) ?? _extractId(raw['id_categoria']);
    final categoryName =
        _string(_extractField(categoryData, 'denominacion')) ??
        _string(raw['categoria_nombre']);
    if (categoryId == null && categoryName != null) {
      categoryId =
          referenceData.findCategoryByName(categoryName)?['id'] as int?;
    }
    if (categoryId != null &&
        referenceData.findCategoryById(categoryId)?['id'] == null) {
      categoryId = null;
    }

    final subcategoriesRaw = raw['subcategorias'] ?? raw['subcategories'] ?? [];
    final subcategoryIds = _parseSubcategoryIds(
      subcategoriesRaw,
      referenceData,
      categoryId,
    );

    final presentationData =
        raw['presentacion_base'] ??
        raw['presentacion'] ??
        raw['base_presentacion'];
    int? presentationId =
        _extractId(presentationData) ?? _extractId(raw['id_presentacion']);
    final presentationName =
        _string(_extractField(presentationData, 'denominacion')) ??
        _string(raw['presentacion_nombre']);
    if (presentationId == null && presentationName != null) {
      presentationId =
          referenceData.findPresentationByName(presentationName)?['id'] as int?;
    }
    if (presentationId != null &&
        referenceData.findPresentationById(presentationId)?['id'] == null) {
      presentationId = null;
    }
    final cantidadPresentacion = _double(
      _extractField(presentationData, 'cantidad') ??
          raw['cantidad_presentacion'],
    );
    final precioCostoUsd = _double(
      _extractField(presentationData, 'precio_costo_usd') ??
          _extractField(presentationData, 'precio_promedio') ??
          _extractField(presentationData, 'costo_usd') ??
          raw['precio_costo_usd'] ??
          raw['precio_costo'] ??
          raw['costo_usd'] ??
          raw['precio_promedio'],
    );

    final unidadData = raw['unidad_medida'] ?? raw['unidad'] ?? raw['um'];
    int? unidadId =
        _extractId(unidadData) ?? _extractId(raw['id_unidad_medida']);
    String? unidadAbreviatura =
        _string(_extractField(unidadData, 'abreviatura')) ??
        _string(_extractField(unidadData, 'um')) ??
        _string(raw['um']);

    if (unidadId == null && unidadAbreviatura != null) {
      final unidadRef = referenceData.findUnitByKey(unidadAbreviatura);
      unidadId = unidadRef?['id'] as int?;
      unidadAbreviatura = unidadRef?['abreviatura']?.toString();
    }
    if (unidadId != null &&
        referenceData.findUnitById(unidadId)?['id'] == null) {
      unidadId = null;
      unidadAbreviatura = null;
    }

    final cantidadUm = _double(
      _extractField(unidadData, 'cantidad_um') ?? raw['cantidad_um'],
    );

    final supplierData = raw['proveedor'] ?? raw['supplier'];
    int? supplierId =
        _extractId(supplierData) ?? _extractId(raw['id_proveedor']);
    final supplierName =
        _string(_extractField(supplierData, 'denominacion')) ??
        _string(raw['proveedor_nombre']);
    if (supplierId == null && supplierName != null) {
      supplierId =
          referenceData.findSupplierByName(supplierName)?['id'] as int?;
    }
    if (supplierId != null &&
        referenceData.findSupplierById(supplierId)?['id'] == null) {
      supplierId = null;
    }

    final flags =
        (raw['flags'] is Map<String, dynamic>)
            ? raw['flags'] as Map<String, dynamic>
            : <String, dynamic>{};

    return AiProductDraft(
      localId: 'draft_${DateTime.now().millisecondsSinceEpoch}_$index',
      denominacion: denominacion,
      sku: sku,
      nombreComercial: _string(raw['nombre_comercial']),
      denominacionCorta: _string(raw['denominacion_corta']),
      descripcion: _string(raw['descripcion']),
      descripcionCorta: _string(raw['descripcion_corta']),
      codigoBarras: _string(raw['codigo_barras']),
      categoryId: categoryId,
      subcategoryIds: subcategoryIds,
      basePresentationId: presentationId,
      cantidadPresentacion: cantidadPresentacion,
      unidadMedidaId: unidadId,
      unidadMedidaAbreviatura: unidadAbreviatura,
      cantidadUm: cantidadUm,
      precioVenta: _double(raw['precio_venta'] ?? raw['precio']),
      precioCostoUsd: precioCostoUsd,
      supplierId: supplierId,
      esVendible: _bool(raw['es_vendible'] ?? flags['es_vendible'], true),
      esComprable: _bool(raw['es_comprable'] ?? flags['es_comprable'], true),
      esInventariable: _bool(
        raw['es_inventariable'] ?? flags['es_inventariable'],
        true,
      ),
      esRefrigerado: _bool(
        raw['es_refrigerado'] ?? flags['es_refrigerado'],
        false,
      ),
      esFragil: _bool(raw['es_fragil'] ?? flags['es_fragil'], false),
      esPeligroso: _bool(raw['es_peligroso'] ?? flags['es_peligroso'], false),
      esPorLotes: _bool(raw['es_por_lotes'] ?? flags['es_por_lotes'], false),
      esElaborado: _bool(raw['es_elaborado'] ?? flags['es_elaborado'], false),
      esServicio: _bool(raw['es_servicio'] ?? flags['es_servicio'], false),
      diasAlertCaducidad: _int(raw['dias_alert_caducidad']),
    );
  }

  List<int> _parseSubcategoryIds(
    dynamic raw,
    ProductAiReferenceData referenceData,
    int? categoryId,
  ) {
    final ids = <int>[];
    if (raw is List) {
      for (final item in raw) {
        final subId = _extractId(item);
        final subName =
            _string(_extractField(item, 'denominacion')) ??
            _string(_extractField(item, 'name'));
        final resolvedId =
            subId ??
            (subName != null
                ? referenceData.subcategories.firstWhere(
                      (subcat) =>
                          _normalizeKey(subcat['denominacion']) ==
                          _normalizeKey(subName),
                      orElse: () => {},
                    )['id']
                    as int?
                : null);

        if (resolvedId != null) {
          final subcategory = referenceData.subcategories.firstWhere(
            (subcat) => subcat['id'] == resolvedId,
            orElse: () => {},
          );
          if (categoryId == null || subcategory['idcategoria'] == categoryId) {
            ids.add(resolvedId);
          }
        }
      }
    }
    return ids;
  }

  String _buildPrompt(String prompt, ProductAiReferenceData referenceData) {
    final referencePayload = const JsonEncoder.withIndent('  ').convert({
      'categorias': referenceData.categories,
      'subcategorias': referenceData.subcategories,
      'presentaciones': referenceData.presentations,
      'unidades_medida': referenceData.units,
      'proveedores': referenceData.suppliers,
    });

    return '''Eres un asistente que genera productos para una tienda.
Responde SOLO con JSON válido, sin markdown ni texto adicional.

Formato requerido:
{
  "productos": [
    {
      "denominacion": "Nombre del producto",
      "sku": "SKU",
      "nombre_comercial": "Marca o nombre comercial",
      "denominacion_corta": "Nombre corto",
      "descripcion": "Descripción",
      "descripcion_corta": "Descripción corta",
      "codigo_barras": "Codigo de barras",
      "precio_venta": 0,
      "categoria": {"id": 1, "denominacion": "Categoria"},
      "subcategorias": [{"id": 10, "denominacion": "Subcategoria"}],
      "presentacion_base": {"id": 2, "denominacion": "Unidad", "cantidad": 1, "precio_costo_usd": 0.0},
      "unidad_medida": {"id": 1, "abreviatura": "und", "cantidad_um": 1},
      "proveedor": {"id": 5, "denominacion": "Proveedor"},
      "flags": {
        "es_vendible": true,
        "es_comprable": true,
        "es_inventariable": true,
        "es_refrigerado": false,
        "es_fragil": false,
        "es_peligroso": false,
        "es_por_lotes": false
      },
      "dias_alert_caducidad": null
    }
  ]
}

Reglas:
- Usa los IDs del listado de referencia.
- Si no puedes asignar un ID, deja el id en null y proporciona la denominación.
- Genera entre 1 y 12 productos coherentes.
- precio_venta debe ser mayor a 0.
- precio_costo_usd (si se incluye) debe ser mayor o igual a 0 y esta en USD.
- cantidad (presentacion_base) y cantidad_um deben ser >= 1.
- No inventes categorías/subcategorías fuera del listado.

Referencia (JSON con IDs reales):
$referencePayload

Prompt del usuario:
$prompt''';
  }

  String _extractResponseText(dynamic data) {
    if (data is Map<String, dynamic>) {
      final choices = data['choices'];
      if (choices is List && choices.isNotEmpty) {
        final message = choices.first['message'];
        if (message is Map<String, dynamic>) {
          final content = message['content'];
          if (content != null) {
            return content.toString();
          }
        }
      }

      final candidates = data['candidates'];
      if (candidates is List && candidates.isNotEmpty) {
        final content = candidates.first['content'];
        if (content is Map<String, dynamic>) {
          final parts = content['parts'];
          if (parts is List && parts.isNotEmpty) {
            final text = parts.first['text'];
            if (text != null) {
              return text.toString();
            }
          }
        }
      }
    }

    throw Exception('Respuesta de IA vacía o inválida.');
  }

  String _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');

    if (start == -1 || end == -1 || end <= start) {
      throw Exception('La IA no devolvió JSON válido.');
    }

    return text.substring(start, end + 1);
  }

  static String _normalizeKey(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }

  static String? _string(dynamic value) {
    if (value == null) return null;
    final parsed = value.toString().trim();
    return parsed.isEmpty ? null : parsed;
  }

  static int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static double? _double(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static bool _bool(dynamic value, bool fallback) {
    if (value is bool) return value;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (['true', 'si', 'sí', '1'].contains(normalized)) return true;
      if (['false', 'no', '0'].contains(normalized)) return false;
    }
    if (value is num) return value != 0;
    return fallback;
  }

  static int? _extractId(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is Map<String, dynamic>) {
      final idValue = value['id'] ?? value['value'];
      return _extractId(idValue);
    }
    return int.tryParse(value?.toString() ?? '');
  }

  static dynamic _extractField(dynamic value, String key) {
    if (value is Map<String, dynamic>) {
      return value[key];
    }
    return null;
  }

  static int? _extractProductId(Map<String, dynamic> result) {
    int? productId = result['producto_id'] as int?;

    if (productId == null) {
      final data = result['data'];
      if (data is Map<String, dynamic>) {
        productId =
            data['producto_id'] as int? ??
            data['id_producto'] as int? ??
            data['id'] as int?;
      }
    }

    if (productId == null) {
      final resultData = result['result'];
      if (resultData is Map<String, dynamic>) {
        productId =
            resultData['producto_id'] as int? ??
            resultData['id_producto'] as int? ??
            resultData['id'] as int?;
      }
    }

    return productId ?? result['id'] as int? ?? result['id_producto'] as int?;
  }

  static String _generateSku(String name, int index) {
    final clean = name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final prefix =
        clean.isNotEmpty ? clean.substring(0, min(6, clean.length)) : 'PROD';
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final suffix = timestamp.substring(max(0, timestamp.length - 4));
    return '$prefix$suffix$index';
  }
}
