import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config/gemini_config.dart';
import '../models/category_generation_plan.dart';
import 'category_service.dart';
import 'subcategory_service.dart';

class CategoryGenerationResult {
  final int createdCategories;
  final int createdSubcategories;
  final List<String> errors;

  const CategoryGenerationResult({
    required this.createdCategories,
    required this.createdSubcategories,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
}

class CategoryGenerationService {
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models';
  static const int _maxCategories = 12;
  static const int _maxSubcategories = 12;

  final CategoryService _categoryService;
  final SubcategoryService _subcategoryService;

  CategoryGenerationService({
    CategoryService? categoryService,
    SubcategoryService? subcategoryService,
  })  : _categoryService = categoryService ?? CategoryService(),
        _subcategoryService = subcategoryService ?? SubcategoryService();

  String? validatePrompt(String prompt) {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return 'Escribe un prompt para generar categorías de la tienda.';
    }

    if (trimmed.length < 8) {
      return 'El prompt es muy corto. Describe mejor las categorías.';
    }

    final hasCategoryKeyword =
        RegExp(r'categor', caseSensitive: false).hasMatch(trimmed) ||
            RegExp(r'subcategor', caseSensitive: false).hasMatch(trimmed);
    if (!hasCategoryKeyword) {
      return 'El prompt debe estar relacionado con categorías o subcategorías.';
    }

    return null;
  }

  Future<CategoryGenerationPlan> generatePlan(String prompt) async {
    final validationError = validatePrompt(prompt);
    if (validationError != null) {
      throw Exception(validationError);
    }

    if (GeminiConfig.apiKey.isEmpty) {
      throw Exception(
        'Configura GEMINI_API_KEY con --dart-define para usar la IA.',
      );
    }

    final requestBody = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {
              'text': _buildPrompt(prompt.trim()),
            }
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 1200,
        'response_mime_type': 'application/json',
      },
    };

    final response = await http
        .post(
          Uri.parse(
            '$_baseUrl/${GeminiConfig.model}:generateContent?key=${GeminiConfig.apiKey}',
          ),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: 35));

    if (response.statusCode != 200) {
      throw Exception(
        'Error en Gemini (${response.statusCode}): ${response.body}',
      );
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

    final plan = CategoryGenerationPlan.fromJson(parsed);
    if (plan.categories.isEmpty) {
      throw Exception('No se generaron categorías válidas.');
    }

    return plan;
  }

  Future<CategoryGenerationResult> createCategories(
    CategoryGenerationPlan plan,
  ) async {
    final errors = <String>[];
    int createdCategories = 0;
    int createdSubcategories = 0;

    final categories = plan.categories.take(_maxCategories);

    for (final category in categories) {
      final name = _normalizeText(category.name);
      final description = _normalizeDescription(category.description);
      final skuCodigo = _resolveSku(category.skuCodigo, name);

      if (name.isEmpty || description.isEmpty || skuCodigo.isEmpty) {
        errors.add('Categoría inválida: "${category.name}"');
        continue;
      }

      final categoryId = await _categoryService.createCategoryWithId(
        denominacion: name,
        descripcion: description,
        skuCodigo: skuCodigo,
        visibleVendedor: category.visibleVendedor,
      );

      if (categoryId == null) {
        errors.add('No se pudo crear la categoría "$name"');
        continue;
      }

      createdCategories += 1;

      final subcategories = category.subcategories.take(_maxSubcategories);
      for (final subcategory in subcategories) {
        final subName = _normalizeText(subcategory.name);
        final subSku = _resolveSku(subcategory.skuCodigo, subName);

        if (subName.isEmpty || subSku.isEmpty) {
          errors.add('Subcategoría inválida en "$name"');
          continue;
        }

        final success = await _subcategoryService.createSubcategory(
          categoryId: categoryId,
          denominacion: subName,
          skuCodigo: subSku,
        );

        if (success) {
          createdSubcategories += 1;
        } else {
          errors.add('No se pudo crear subcategoría "$subName"');
        }
      }
    }

    return CategoryGenerationResult(
      createdCategories: createdCategories,
      createdSubcategories: createdSubcategories,
      errors: errors,
    );
  }

  String _buildPrompt(String prompt) {
    return '''Eres un asistente que genera categorías y subcategorías para una tienda.
Responde SOLO con JSON válido, sin markdown ni texto adicional.

Formato exacto:
{
  "categories": [
    {
      "name": "Nombre",
      "description": "Descripción corta",
      "sku_codigo": "SKU",
      "visible_vendedor": true,
      "subcategories": [
        {"name": "Subcat", "sku_codigo": "SKU"}
      ]
    }
  ]
}

Reglas:
- El contenido debe estar relacionado únicamente con categorías/subcategorías de la tienda.
- Genera entre 3 y 8 categorías (máximo 12).
- Cada categoría puede tener 0 a 6 subcategorías (máximo 12).
- sku_codigo: máximo 8 caracteres, en mayúsculas, sin espacios.
- description: máximo 120 caracteres.
- No agregues productos, precios, ni comentarios.

Prompt del usuario:
$prompt''';
  }

  String _extractResponseText(dynamic data) {
    if (data is Map<String, dynamic>) {
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

  String _normalizeText(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeDescription(String value) {
    final normalized = _normalizeText(value);
    if (normalized.length <= 120) {
      return normalized;
    }
    return normalized.substring(0, 120);
  }

  String _resolveSku(String sku, String name) {
    final normalizedSku = _normalizeSku(sku);
    if (normalizedSku.isNotEmpty) {
      return normalizedSku;
    }

    final fallback = _normalizeSku(name.replaceAll(' ', ''));
    return fallback;
  }

  String _normalizeSku(String sku) {
    final normalized = sku.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (normalized.isEmpty) {
      return '';
    }
    return normalized.substring(0, min(8, normalized.length));
  }
}
