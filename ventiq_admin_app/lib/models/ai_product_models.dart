import 'dart:math';

class ProductAiReferenceData {
  final List<Map<String, dynamic>> categories;
  final List<Map<String, dynamic>> subcategories;
  final List<Map<String, dynamic>> presentations;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> suppliers;

  const ProductAiReferenceData({
    required this.categories,
    required this.subcategories,
    required this.presentations,
    required this.units,
    required this.suppliers,
  });

  List<Map<String, dynamic>> subcategoriesForCategory(int? categoryId) {
    if (categoryId == null) return [];
    return subcategories
        .where((subcat) => subcat['idcategoria'] == categoryId)
        .toList();
  }

  Map<String, dynamic>? findCategoryById(int? id) {
    if (id == null) return null;
    return categories.firstWhere((item) => item['id'] == id, orElse: () => {});
  }

  Map<String, dynamic>? findCategoryByName(String? name) {
    final normalized = _normalizeKey(name);
    if (normalized.isEmpty) return null;
    return categories.firstWhere(
      (item) => _normalizeKey(item['denominacion']) == normalized,
      orElse: () => {},
    );
  }

  Map<String, dynamic>? findPresentationById(int? id) {
    if (id == null) return null;
    return presentations.firstWhere(
      (item) => item['id'] == id,
      orElse: () => {},
    );
  }

  Map<String, dynamic>? findPresentationByName(String? name) {
    final normalized = _normalizeKey(name);
    if (normalized.isEmpty) return null;
    return presentations.firstWhere(
      (item) => _normalizeKey(item['denominacion']) == normalized,
      orElse: () => {},
    );
  }

  Map<String, dynamic>? findUnitById(int? id) {
    if (id == null) return null;
    return units.firstWhere((item) => item['id'] == id, orElse: () => {});
  }

  Map<String, dynamic>? findUnitByKey(String? value) {
    final normalized = _normalizeKey(value);
    if (normalized.isEmpty) return null;
    return units.firstWhere((item) {
      return _normalizeKey(item['abreviatura']) == normalized ||
          _normalizeKey(item['denominacion']) == normalized;
    }, orElse: () => {});
  }

  Map<String, dynamic>? findSupplierById(int? id) {
    if (id == null) return null;
    return suppliers.firstWhere((item) => item['id'] == id, orElse: () => {});
  }

  Map<String, dynamic>? findSupplierByName(String? name) {
    final normalized = _normalizeKey(name);
    if (normalized.isEmpty) return null;
    return suppliers.firstWhere(
      (item) => _normalizeKey(item['denominacion']) == normalized,
      orElse: () => {},
    );
  }

  static String _normalizeKey(dynamic value) {
    return (value ?? '').toString().trim().toLowerCase();
  }
}

class AiProductDraft {
  final String localId;
  final String denominacion;
  final String? sku;
  final String? nombreComercial;
  final String? denominacionCorta;
  final String? descripcion;
  final String? descripcionCorta;
  final String? codigoBarras;
  final int? categoryId;
  final List<int> subcategoryIds;
  final int? basePresentationId;
  final double? cantidadPresentacion;
  final int? unidadMedidaId;
  final String? unidadMedidaAbreviatura;
  final double? cantidadUm;
  final double? precioVenta;
  final double? precioCostoUsd;
  final int? supplierId;
  final bool esVendible;
  final bool esComprable;
  final bool esInventariable;
  final bool esRefrigerado;
  final bool esFragil;
  final bool esPeligroso;
  final bool esPorLotes;
  final bool esElaborado;
  final bool esServicio;
  final int? diasAlertCaducidad;

  const AiProductDraft({
    required this.localId,
    required this.denominacion,
    this.sku,
    this.nombreComercial,
    this.denominacionCorta,
    this.descripcion,
    this.descripcionCorta,
    this.codigoBarras,
    this.categoryId,
    this.subcategoryIds = const [],
    this.basePresentationId,
    this.cantidadPresentacion,
    this.unidadMedidaId,
    this.unidadMedidaAbreviatura,
    this.cantidadUm,
    this.precioVenta,
    this.precioCostoUsd,
    this.supplierId,
    this.esVendible = true,
    this.esComprable = true,
    this.esInventariable = true,
    this.esRefrigerado = false,
    this.esFragil = false,
    this.esPeligroso = false,
    this.esPorLotes = false,
    this.esElaborado = false,
    this.esServicio = false,
    this.diasAlertCaducidad,
  });

  AiProductDraft copyWith({
    String? denominacion,
    String? sku,
    String? nombreComercial,
    String? denominacionCorta,
    String? descripcion,
    String? descripcionCorta,
    String? codigoBarras,
    int? categoryId,
    List<int>? subcategoryIds,
    int? basePresentationId,
    double? cantidadPresentacion,
    int? unidadMedidaId,
    String? unidadMedidaAbreviatura,
    double? cantidadUm,
    double? precioVenta,
    double? precioCostoUsd,
    int? supplierId,
    bool? esVendible,
    bool? esComprable,
    bool? esInventariable,
    bool? esRefrigerado,
    bool? esFragil,
    bool? esPeligroso,
    bool? esPorLotes,
    bool? esElaborado,
    bool? esServicio,
    int? diasAlertCaducidad,
  }) {
    return AiProductDraft(
      localId: localId,
      denominacion: denominacion ?? this.denominacion,
      sku: sku ?? this.sku,
      nombreComercial: nombreComercial ?? this.nombreComercial,
      denominacionCorta: denominacionCorta ?? this.denominacionCorta,
      descripcion: descripcion ?? this.descripcion,
      descripcionCorta: descripcionCorta ?? this.descripcionCorta,
      codigoBarras: codigoBarras ?? this.codigoBarras,
      categoryId: categoryId ?? this.categoryId,
      subcategoryIds: subcategoryIds ?? this.subcategoryIds,
      basePresentationId: basePresentationId ?? this.basePresentationId,
      cantidadPresentacion: cantidadPresentacion ?? this.cantidadPresentacion,
      unidadMedidaId: unidadMedidaId ?? this.unidadMedidaId,
      unidadMedidaAbreviatura:
          unidadMedidaAbreviatura ?? this.unidadMedidaAbreviatura,
      cantidadUm: cantidadUm ?? this.cantidadUm,
      precioVenta: precioVenta ?? this.precioVenta,
      precioCostoUsd: precioCostoUsd ?? this.precioCostoUsd,
      supplierId: supplierId ?? this.supplierId,
      esVendible: esVendible ?? this.esVendible,
      esComprable: esComprable ?? this.esComprable,
      esInventariable: esInventariable ?? this.esInventariable,
      esRefrigerado: esRefrigerado ?? this.esRefrigerado,
      esFragil: esFragil ?? this.esFragil,
      esPeligroso: esPeligroso ?? this.esPeligroso,
      esPorLotes: esPorLotes ?? this.esPorLotes,
      esElaborado: esElaborado ?? this.esElaborado,
      esServicio: esServicio ?? this.esServicio,
      diasAlertCaducidad: diasAlertCaducidad ?? this.diasAlertCaducidad,
    );
  }

  List<String> getMissingFields() {
    final missing = <String>[];

    if (denominacion.trim().isEmpty) {
      missing.add('denominacion');
    }
    if (sku == null || sku!.trim().isEmpty) {
      missing.add('sku');
    }
    if (precioVenta == null || (precioVenta ?? 0) <= 0) {
      missing.add('precio');
    }
    if (categoryId == null) {
      missing.add('categoria');
    }
    if (subcategoryIds.isEmpty) {
      missing.add('subcategorias');
    }
    if (basePresentationId == null) {
      missing.add('presentacion');
    }
    if (cantidadPresentacion == null || (cantidadPresentacion ?? 0) <= 0) {
      missing.add('cantidad_presentacion');
    }
    if (unidadMedidaId == null) {
      missing.add('unidad_medida');
    }
    if (cantidadUm == null || (cantidadUm ?? 0) <= 0) {
      missing.add('cantidad_um');
    }

    return missing;
  }

  bool get isValid => getMissingFields().isEmpty;

  Map<String, dynamic> buildProductoData({required int idTienda}) {
    final denominacionTrim = denominacion.trim();
    final nombreComercialResolved =
        (nombreComercial ?? '').trim().isNotEmpty
            ? nombreComercial!.trim()
            : denominacionTrim;
    final denominacionCortaResolved =
        (denominacionCorta ?? '').trim().isNotEmpty
            ? denominacionCorta!.trim()
            : denominacionTrim.substring(0, min(20, denominacionTrim.length));

    return {
      'id_tienda': idTienda,
      'sku': sku?.trim() ?? '',
      'id_categoria': categoryId,
      'denominacion': denominacionTrim,
      'nombre_comercial': nombreComercialResolved,
      'denominacion_corta': denominacionCortaResolved,
      'descripcion': (descripcion ?? '').trim(),
      'descripcion_corta': (descripcionCorta ?? '').trim(),
      'um':
          (unidadMedidaAbreviatura ?? '').trim().isNotEmpty
              ? unidadMedidaAbreviatura!.trim()
              : 'und',
      'es_refrigerado': esRefrigerado,
      'es_fragil': esFragil,
      'es_peligroso': esPeligroso,
      'es_vendible': esVendible,
      'es_comprable': esComprable,
      'es_inventariable': esInventariable,
      'es_elaborado': esElaborado,
      'es_servicio': esServicio,
      'es_por_lotes': esPorLotes,
      'dias_alert_caducidad': diasAlertCaducidad,
      'codigo_barras': codigoBarras ?? '',
      if (supplierId != null) 'id_proveedor': supplierId,
    };
  }

  List<Map<String, dynamic>> buildSubcategoriasData() {
    return subcategoryIds.map((id) => {'id_sub_categoria': id}).toList();
  }

  List<Map<String, dynamic>> buildPresentacionesData() {
    if (basePresentationId == null) {
      return [];
    }
    final costoUsd = precioCostoUsd;
    return [
      {
        'id_presentacion': basePresentationId,
        'cantidad': cantidadPresentacion ?? 1,
        'es_base': true,
        if (costoUsd != null && costoUsd > 0) 'precio_promedio': costoUsd,
      },
    ];
  }

  List<Map<String, dynamic>> buildPreciosData() {
    if (precioVenta == null) {
      return [];
    }
    return [
      {
        'precio_venta_cup': precioVenta,
        'fecha_desde': DateTime.now().toIso8601String().substring(0, 10),
        'id_variante': null,
      },
    ];
  }

  List<Map<String, dynamic>> buildPresentacionUnidadMedidaData() {
    if (basePresentationId == null || unidadMedidaId == null) {
      return [];
    }
    return [
      {
        'id_presentacion': basePresentationId,
        'id_unidad_medida': unidadMedidaId,
        'cantidad_um': cantidadUm ?? 1,
      },
    ];
  }
}

class AiProductCreationResult {
  final int createdCount;
  final List<String> errors;

  const AiProductCreationResult({
    required this.createdCount,
    required this.errors,
  });

  bool get hasErrors => errors.isNotEmpty;
}
