/// Utility functions for price formatting and calculations
class PriceUtils {
  /// Rounds a discount price to the nearest integer and formats it with .00
  /// This ensures all discount prices are displayed as whole numbers with .00
  static double roundDiscountPrice(double discountPrice) {
    return discountPrice.roundToDouble();
  }

  /// Formats a discount price as a string with .00 decimals
  static String formatDiscountPrice(double discountPrice) {
    final roundedPrice = roundDiscountPrice(discountPrice);
    return roundedPrice.toStringAsFixed(2);
  }

  /// Calculates and rounds discount price based on original price and discount parameters
  static double? calculateAndRoundDiscountPrice(
    double originalPrice,
    double? valorDescuento,
    int? tipoDescuento,
  ) {
    if (valorDescuento == null || tipoDescuento == null) return null;

    double discountedPrice;

    if (tipoDescuento == 1) {
      // Descuento porcentual
      discountedPrice = originalPrice - (originalPrice * valorDescuento / 100);
    } else if (tipoDescuento == 2) {
      // Descuento exacto (fijo)
      discountedPrice = originalPrice - valorDescuento;
      discountedPrice = discountedPrice > 0 ? discountedPrice : 0.0;
    } else if (tipoDescuento == 3) {
      // Recargo porcentual - aumenta el precio
      discountedPrice = originalPrice + (originalPrice * valorDescuento / 100);
    } else {
      return null;
    }

    return roundDiscountPrice(discountedPrice);
  }

  /// Calcula precios con promoción y maneja el intercambio de precios para "Recargo porcentual"
  /// Retorna un mapa con precio_venta y precio_oferta según el tipo de promoción
  static Map<String, double> calculatePromotionPrices(
    double originalPrice,
    double? valorDescuento,
    int? tipoDescuento,
  ) {
    if (valorDescuento == null || tipoDescuento == null) {
      return {
        'precio_venta': originalPrice,
        'precio_oferta': originalPrice,
      };
    }

    double calculatedPrice;

    if (tipoDescuento == 1) {
      // Descuento porcentual
      calculatedPrice = originalPrice - (originalPrice * valorDescuento / 100);
      return {
        'precio_venta': originalPrice,
        'precio_oferta': roundDiscountPrice(calculatedPrice),
      };
    } else if (tipoDescuento == 2) {
      // Descuento exacto
      calculatedPrice = originalPrice - valorDescuento;
      calculatedPrice = calculatedPrice > 0 ? calculatedPrice : 0.0;
      return {
        'precio_venta': originalPrice,
        'precio_oferta': roundDiscountPrice(calculatedPrice),
      };
    } else if (tipoDescuento == 3) {
      // Recargo porcentual - intercambiar precios
      calculatedPrice = originalPrice + (originalPrice * valorDescuento / 100);
      return {
        'precio_venta': roundDiscountPrice(calculatedPrice), // El precio mayor es ahora precio_venta
        'precio_oferta': originalPrice, // El precio original es ahora precio_oferta (menor)
      };
    }

    return {
      'precio_venta': originalPrice,
      'precio_oferta': originalPrice,
    };
  }

  /// Determina si hay promoción activa
  static bool hasActivePromotion(int? tipoDescuento) {
    return tipoDescuento != null && [1, 2, 3].contains(tipoDescuento);
  }

  /// Obtiene el texto descriptivo del tipo de promoción
  static String getPromotionTypeText(int? tipoDescuento) {
    switch (tipoDescuento) {
      case 1:
        return 'Descuento porcentual';
      case 2:
        return 'Descuento exacto';
      case 3:
        return 'Recargo porcentual';
      default:
        return '';
    }
  }
}
