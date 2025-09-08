import '../models/promotion.dart';
import '../services/promotion_service.dart';
import '../services/user_preferences_service.dart';

class PromotionValidator {
  final PromotionService _promotionService = PromotionService();
  final UserPreferencesService _prefsService = UserPreferencesService();

  /// Valida un código de promoción para una venta específica
  Future<PromotionValidationResult> validatePromotionCode({
    required String codigoPromocion,
    required List<Map<String, dynamic>> productos,
    double? totalVenta,
  }) async {
    try {
      // Obtener ID de tienda del usuario
      final storeId = await _prefsService.getIdTienda();
      if (storeId == null) {
        return PromotionValidationResult(
          valida: false,
          mensaje: 'No se encontró información de tienda del usuario',
        );
      }

      // Validar usando el servicio de promociones
      final result = await _promotionService.validatePromotion(
        codigoPromocion: codigoPromocion,
        idTienda: storeId.toString(),
        productos: productos,
      );

      // Validaciones adicionales del lado cliente
      if (result.valida && result.promocion != null) {
        final clientValidation = _performClientSideValidation(
          result.promocion!,
          productos,
          totalVenta,
        );

        if (!clientValidation.valida) {
          return clientValidation;
        }
      }

      return result;
    } catch (e) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'Error al validar promoción: $e',
      );
    }
  }

  /// Validaciones del lado cliente para complementar la validación del servidor
  PromotionValidationResult _performClientSideValidation(
    Promotion promotion,
    List<Map<String, dynamic>> productos,
    double? totalVenta,
  ) {
    // Verificar si la promoción está activa
    if (!promotion.estado) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'La promoción está desactivada',
      );
    }

    // Verificar fechas de vigencia
    final now = DateTime.now();
    if (now.isBefore(promotion.fechaInicio)) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'La promoción aún no está vigente',
      );
    }

    // Check expiration only if fechaFin is not null (permanent promotions don't expire)
    if (promotion.fechaFin != null && now.isAfter(promotion.fechaFin!)) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'La promoción ha expirado',
      );
    }

    // Verificar límite de usos
    if (promotion.limiteUsos != null &&
        (promotion.usosActuales ?? 0) >= promotion.limiteUsos!) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'La promoción ha alcanzado su límite de usos',
      );
    }

    // Verificar compra mínima
    if (promotion.minCompra != null && totalVenta != null) {
      if (totalVenta < promotion.minCompra!) {
        return PromotionValidationResult(
          valida: false,
          mensaje:
              'La compra mínima requerida es \$${promotion.minCompra!.toStringAsFixed(0)}',
        );
      }
    }

    // Verificar productos aplicables
    if (!promotion.aplicaTodo &&
        (promotion.productos == null || promotion.productos!.isEmpty)) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'La promoción no tiene productos configurados',
      );
    }

    return PromotionValidationResult(
      valida: true,
      mensaje: 'Promoción válida',
      promocion: promotion,
    );
  }

  /// Calcula el descuento aplicable para una venta
  double calculateDiscount({
    required Promotion promotion,
    required double totalVenta,
    required List<Map<String, dynamic>> productos,
  }) {
    if (!promotion.estado) return 0.0;

    double descuento = 0.0;

    if (promotion.aplicaTodo) {
      // Aplicar descuento al total de la venta
      descuento = totalVenta * (promotion.valorDescuento / 100);
    } else {
      // Aplicar descuento solo a productos específicos
      final productosAplicables = _getApplicableProducts(promotion, productos);
      final subtotalAplicable = productosAplicables.fold<double>(
        0.0,
        (sum, producto) => sum + (producto['precio'] * producto['cantidad']),
      );
      descuento = subtotalAplicable * (promotion.valorDescuento / 100);
    }

    return descuento;
  }

  /// Obtiene los productos a los que aplica la promoción
  List<Map<String, dynamic>> _getApplicableProducts(
    Promotion promotion,
    List<Map<String, dynamic>> productos,
  ) {
    if (promotion.aplicaTodo) {
      return productos;
    }

    final productosPromocion =
        promotion.productos?.map((p) => p.idProducto).toSet() ?? {};

    return productos.where((producto) {
      final idProducto = producto['id_producto']?.toString();
      return idProducto != null && productosPromocion.contains(idProducto);
    }).toList();
  }

  /// Valida múltiples promociones y devuelve la mejor opción
  Future<PromotionValidationResult> findBestPromotion({
    required List<String> codigosPromocion,
    required List<Map<String, dynamic>> productos,
    required double totalVenta,
  }) async {
    final validPromotions = <PromotionValidationResult>[];

    // Validar cada promoción
    for (final codigo in codigosPromocion) {
      final result = await validatePromotionCode(
        codigoPromocion: codigo,
        productos: productos,
        totalVenta: totalVenta,
      );

      if (result.valida && result.promocion != null) {
        // Calcular descuento para comparar
        final descuento = calculateDiscount(
          promotion: result.promocion!,
          totalVenta: totalVenta,
          productos: productos,
        );

        validPromotions.add(result.copyWith(descuentoCalculado: descuento));
      }
    }

    if (validPromotions.isEmpty) {
      return PromotionValidationResult(
        valida: false,
        mensaje: 'No se encontraron promociones válidas',
      );
    }

    // Devolver la promoción con mayor descuento
    validPromotions.sort(
      (a, b) =>
          (b.descuentoCalculado ?? 0.0).compareTo(a.descuentoCalculado ?? 0.0),
    );

    return validPromotions.first;
  }

  /// Aplica una promoción a una venta y devuelve el resumen
  Map<String, dynamic> applyPromotionToSale({
    required Promotion promotion,
    required List<Map<String, dynamic>> productos,
    required double totalVenta,
  }) {
    final productosAplicables = _getApplicableProducts(promotion, productos);
    final descuento = calculateDiscount(
      promotion: promotion,
      totalVenta: totalVenta,
      productos: productos,
    );

    final totalConDescuento = totalVenta - descuento;

    return {
      'promocion': promotion,
      'productos_aplicables': productosAplicables,
      'descuento_aplicado': descuento,
      'total_original': totalVenta,
      'total_con_descuento': totalConDescuento,
      'porcentaje_descuento': promotion.valorDescuento,
      'ahorro_total': descuento,
      'codigo_promocion': promotion.codigoPromocion,
    };
  }

  /// Verifica si una promoción puede combinarse con otras
  bool canCombinePromotions(Promotion promotion1, Promotion promotion2) {
    // Por defecto, no permitir combinación de promociones
    // Esta lógica puede expandirse según las reglas de negocio
    return false;
  }

  /// Obtiene un resumen de promociones disponibles para un conjunto de productos
  Future<List<Promotion>> getAvailablePromotions({
    required List<Map<String, dynamic>> productos,
    double? totalVenta,
  }) async {
    try {
      final allPromotions = await _promotionService.listPromotions(
        estado: true, // Solo promociones activas
        limit: 100,
      );

      final availablePromotions = <Promotion>[];

      for (final promotion in allPromotions) {
        final validation = _performClientSideValidation(
          promotion,
          productos,
          totalVenta,
        );

        if (validation.valida) {
          availablePromotions.add(promotion);
        }
      }

      // Ordenar por valor de descuento (mayor a menor)
      availablePromotions.sort(
        (a, b) => b.valorDescuento.compareTo(a.valorDescuento),
      );

      return availablePromotions;
    } catch (e) {
      print('Error obteniendo promociones disponibles: $e');
      return [];
    }
  }

  /// Genera un código QR para una promoción
  String generatePromotionQR(Promotion promotion) {
    return 'VENTIQ_PROMO:${promotion.codigoPromocion}:${promotion.id}';
  }

  /// Parsea un código QR de promoción
  Map<String, String>? parsePromotionQR(String qrCode) {
    if (!qrCode.startsWith('VENTIQ_PROMO:')) {
      return null;
    }

    final parts = qrCode.split(':');
    if (parts.length != 3) {
      return null;
    }

    return {'codigo': parts[1], 'id': parts[2]};
  }
}
