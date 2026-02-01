class CategoryGenerationPlan {
  final List<CategoryGenerationCategory> categories;

  const CategoryGenerationPlan({
    required this.categories,
  });

  bool get isEmpty => categories.isEmpty;

  factory CategoryGenerationPlan.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    final List<CategoryGenerationCategory> parsedCategories = [];

    if (rawCategories is List) {
      for (final item in rawCategories) {
        if (item is Map<String, dynamic>) {
          parsedCategories.add(CategoryGenerationCategory.fromJson(item));
        }
      }
    }

    return CategoryGenerationPlan(categories: parsedCategories);
  }
}

class CategoryGenerationCategory {
  final String name;
  final String description;
  final String skuCodigo;
  final bool visibleVendedor;
  final List<CategoryGenerationSubcategory> subcategories;

  const CategoryGenerationCategory({
    required this.name,
    required this.description,
    required this.skuCodigo,
    required this.visibleVendedor,
    required this.subcategories,
  });

  factory CategoryGenerationCategory.fromJson(Map<String, dynamic> json) {
    final rawSubcategories = json['subcategories'];
    final List<CategoryGenerationSubcategory> parsedSubcategories = [];

    if (rawSubcategories is List) {
      for (final item in rawSubcategories) {
        if (item is Map<String, dynamic>) {
          parsedSubcategories.add(CategoryGenerationSubcategory.fromJson(item));
        }
      }
    }

    return CategoryGenerationCategory(
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      skuCodigo: json['sku_codigo']?.toString() ?? json['skuCodigo']?.toString() ?? '',
      visibleVendedor: json['visible_vendedor'] is bool
          ? json['visible_vendedor'] as bool
          : true,
      subcategories: parsedSubcategories,
    );
  }
}

class CategoryGenerationSubcategory {
  final String name;
  final String skuCodigo;

  const CategoryGenerationSubcategory({
    required this.name,
    required this.skuCodigo,
  });

  factory CategoryGenerationSubcategory.fromJson(Map<String, dynamic> json) {
    return CategoryGenerationSubcategory(
      name: json['name']?.toString() ?? '',
      skuCodigo: json['sku_codigo']?.toString() ?? json['skuCodigo']?.toString() ?? '',
    );
  }
}
