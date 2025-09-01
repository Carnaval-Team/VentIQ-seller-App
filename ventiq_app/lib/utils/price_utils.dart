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
      // Descuento fijo
      discountedPrice = originalPrice - valorDescuento;
      discountedPrice = discountedPrice > 0 ? discountedPrice : 0.0;
    } else {
      return null;
    }
    
    return roundDiscountPrice(discountedPrice);
  }
}
