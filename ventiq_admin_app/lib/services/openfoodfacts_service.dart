import 'dart:convert';
import 'package:http/http.dart' as http;

class OpenFoodFactsService {
  static const String baseUrl = 'https://world.openfoodfacts.org/api/v0/product';

  /// Busca un producto en OpenFoodFacts por código de barras
  static Future<OpenFoodFactsResponse> getProductByBarcode(String barcode) async {
    try {
      print('🔍 Buscando producto en OpenFoodFacts: $barcode');
      
      final url = '$baseUrl/$barcode.json';
      final response = await http.get(
        Uri.parse(url),
        headers: {
          'User-Agent': 'Inventtia-Gestion/1.0 (contact@inventtia.com)',
        },
      ).timeout(const Duration(seconds: 10));

      print('📡 Respuesta OpenFoodFacts - Status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        print('✅ Datos recibidos de OpenFoodFacts');
        return OpenFoodFactsResponse.fromJson(jsonData);
      } else {
        print('❌ Error HTTP: ${response.statusCode}');
        return OpenFoodFactsResponse.notFound(barcode);
      }
    } catch (e) {
      print('❌ Error al consultar OpenFoodFacts: $e');
      return OpenFoodFactsResponse.error(barcode, e.toString());
    }
  }
}

class OpenFoodFactsResponse {
  final String code;
  final int status;
  final String? statusVerbose;
  final OpenFoodFactsProduct? product;
  final String? error;

  OpenFoodFactsResponse({
    required this.code,
    required this.status,
    this.statusVerbose,
    this.product,
    this.error,
  });

  factory OpenFoodFactsResponse.fromJson(Map<String, dynamic> json) {
    return OpenFoodFactsResponse(
      code: json['code'] ?? '',
      status: json['status'] ?? 0,
      statusVerbose: json['status_verbose'],
      product: json['status'] == 1 && json['product'] != null
          ? OpenFoodFactsProduct.fromJson(json['product'])
          : null,
    );
  }

  factory OpenFoodFactsResponse.notFound(String barcode) {
    return OpenFoodFactsResponse(
      code: barcode,
      status: 0,
      statusVerbose: 'product not found',
    );
  }

  factory OpenFoodFactsResponse.error(String barcode, String error) {
    return OpenFoodFactsResponse(
      code: barcode,
      status: -1,
      error: error,
    );
  }

  bool get isSuccess => status == 1 && product != null;
  bool get isNotFound => status == 0;
  bool get hasError => status == -1 || error != null;
}

class OpenFoodFactsProduct {
  final String? productName;
  final String? productNameEs;
  final String? genericName;
  final String? genericNameEs;
  final String? brands;
  final String? categories;
  final String? categoriesEs;
  final String? description;
  final String? ingredients;
  final String? ingredientsEs;
  final String? quantity;
  final String? packaging;
  final String? packagingEs;
  final String? imageUrl;
  final String? imageFrontUrl;
  final List<String> allergens;
  final Map<String, dynamic>? nutriments;
  final String? servingSize;
  final String? countries;
  final String? manufacturingPlaces;
  final String? origins;
  final String? stores;

  OpenFoodFactsProduct({
    this.productName,
    this.productNameEs,
    this.genericName,
    this.genericNameEs,
    this.brands,
    this.categories,
    this.categoriesEs,
    this.description,
    this.ingredients,
    this.ingredientsEs,
    this.quantity,
    this.packaging,
    this.packagingEs,
    this.imageUrl,
    this.imageFrontUrl,
    this.allergens = const [],
    this.nutriments,
    this.servingSize,
    this.countries,
    this.manufacturingPlaces,
    this.origins,
    this.stores,
  });

  factory OpenFoodFactsProduct.fromJson(Map<String, dynamic> json) {
    // Obtener nombre del producto (priorizar español)
    String? productName = json['product_name_es'] ?? 
                         json['product_name'] ?? 
                         json['abbreviated_product_name'];

    // Obtener nombre genérico
    String? genericName = json['generic_name_es'] ?? 
                         json['generic_name'];

    // Obtener categorías (priorizar español)
    String? categories = json['categories_es'] ?? 
                        json['categories'];

    // Obtener ingredientes (priorizar español)
    String? ingredients = json['ingredients_text_es'] ?? 
                         json['ingredients_text'];

    // Obtener packaging (priorizar español)
    String? packaging = json['packaging_es'] ?? 
                       json['packaging'];

    // Obtener imágenes
    String? imageUrl;
    String? imageFrontUrl;
    
    if (json['images'] != null) {
      final images = json['images'] as Map<String, dynamic>;
      if (images['front'] != null) {
        final front = images['front'] as Map<String, dynamic>;
        imageFrontUrl = front['display_es'] ?? front['display'] ?? front['small'];
      }
      
      // Buscar cualquier imagen disponible
      if (imageUrl == null) {
        for (final key in images.keys) {
          if (images[key] is Map<String, dynamic>) {
            final img = images[key] as Map<String, dynamic>;
            imageUrl = img['display'] ?? img['small'];
            if (imageUrl != null) break;
          }
        }
      }
    }

    // Obtener alérgenos
    List<String> allergens = [];
    if (json['allergens_tags'] != null) {
      allergens = (json['allergens_tags'] as List)
          .map((e) => e.toString().replaceAll('en:', ''))
          .toList();
    }

    return OpenFoodFactsProduct(
      productName: productName,
      productNameEs: json['product_name_es'],
      genericName: genericName,
      genericNameEs: json['generic_name_es'],
      brands: json['brands'],
      categories: categories,
      categoriesEs: json['categories_es'],
      description: json['description'],
      ingredients: ingredients,
      ingredientsEs: json['ingredients_text_es'],
      quantity: json['quantity'],
      packaging: packaging,
      packagingEs: json['packaging_es'],
      imageUrl: imageUrl,
      imageFrontUrl: imageFrontUrl,
      allergens: allergens,
      nutriments: json['nutriments'],
      servingSize: json['serving_size'],
      countries: json['countries'],
      manufacturingPlaces: json['manufacturing_places'],
      origins: json['origins'],
      stores: json['stores'],
    );
  }

  /// Obtiene el mejor nombre disponible para el producto
  String get bestProductName {
    return productNameEs ?? productName ?? genericNameEs ?? genericName ?? 'Producto sin nombre';
  }

  /// Obtiene la mejor descripción disponible
  String get bestDescription {
    return description ?? genericNameEs ?? genericName ?? '';
  }

  /// Obtiene las mejores categorías disponibles
  String get bestCategories {
    return categoriesEs ?? categories ?? '';
  }

  /// Obtiene los mejores ingredientes disponibles
  String get bestIngredients {
    return ingredientsEs ?? ingredients ?? '';
  }

  /// Obtiene el mejor packaging disponible
  String get bestPackaging {
    return packagingEs ?? packaging ?? '';
  }

  /// Obtiene la mejor imagen disponible
  String? get bestImageUrl {
    return imageFrontUrl ?? imageUrl;
  }

  /// Convierte el producto a Map para compatibilidad
  Map<String, dynamic> toJson() {
    return {
      'product_name': bestProductName,
      'product_name_es': productNameEs,
      'generic_name': genericName,
      'generic_name_es': genericNameEs,
      'brands': brands,
      'categories': bestCategories,
      'categories_es': categoriesEs,
      'description': bestDescription,
      'ingredients_text': bestIngredients,
      'ingredients_text_es': ingredientsEs,
      'quantity': quantity,
      'packaging': bestPackaging,
      'packaging_es': packagingEs,
      'image_url': bestImageUrl,
      'image_front_url': imageFrontUrl,
      'allergens': allergens,
      'nutriments': nutriments,
      'serving_size': servingSize,
      'countries': countries,
      'manufacturing_places': manufacturingPlaces,
      'origins': origins,
      'stores': stores,
    };
  }
}
