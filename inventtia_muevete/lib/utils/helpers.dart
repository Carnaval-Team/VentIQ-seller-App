import 'package:intl/intl.dart';

class Helpers {
  /// Format currency amount
  static String formatCurrency(double amount) {
    final formatter = NumberFormat.currency(symbol: '\$', decimalDigits: 2);
    return formatter.format(amount);
  }

  /// Formatea un monto en CUP con separador de miles: `1 500 CUP`.
  ///
  /// Los montos enteros se muestran sin decimales (uso normal del peso
  /// cubano); si el monto trae centavos se añaden con coma decimal.
  static String formatCup(num amount) {
    final value = amount.toDouble();
    final negative = value < 0;
    final totalCents = (value.abs() * 100).round();
    final integerPart = totalCents ~/ 100;
    final cents = totalCents % 100;

    final digits = integerPart.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }

    final centsText = cents == 0 ? '' : ',${cents.toString().padLeft(2, '0')}';
    return '${negative ? '-' : ''}$buffer$centsText CUP';
  }

  /// Igual que [formatCup] pero con signo explícito: `+225 CUP` / `-225 CUP`.
  static String formatCupSigned(num amount) {
    final prefix = amount < 0 ? '-' : '+';
    return '$prefix${formatCup(amount.abs())}';
  }

  /// Format distance in km
  static String formatDistance(double km) {
    if (km < 1) {
      return '${(km * 1000).toStringAsFixed(0)} m';
    }
    return '${km.toStringAsFixed(1)} km';
  }

  /// Format duration in minutes
  static String formatDuration(double seconds) {
    final minutes = (seconds / 60).round();
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    return '${hours}h ${remaining}min';
  }

  /// Format date/time
  static String formatDateTime(DateTime dt) {
    return DateFormat('dd/MM/yyyy HH:mm').format(dt);
  }

  /// Format relative time (e.g., "hace 5 min")
  static String formatRelativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Ahora';
    if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Hace ${diff.inHours}h';
    return DateFormat('dd/MM').format(dt);
  }

  /// Calculate estimated price based on distance and price per km
  static double calculateEstimatedPrice(
      double distanceKm, double pricePerKm) {
    return distanceKm * pricePerKm;
  }

  /// Validate email format
  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }

  /// Validate phone number (basic)
  static bool isValidPhone(String phone) {
    return RegExp(r'^\+?[\d\s-]{8,15}$').hasMatch(phone);
  }

  /// Build WhatsApp URL
  static String buildWhatsAppUrl(String phone, {String? message}) {
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri(
      scheme: 'https',
      host: 'wa.me',
      path: cleanPhone,
      queryParameters: message != null ? {'text': message} : null,
    );
    return uri.toString();
  }

  /// Build phone call URL
  static String buildPhoneUrl(String phone) {
    return 'tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}';
  }
}
