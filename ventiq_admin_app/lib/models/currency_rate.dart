class CurrencyRate {
  final String currency;
  final double value;
  final DateTime lastUpdate;
  final DateTime timestamp;

  CurrencyRate({
    required this.currency,
    required this.value,
    required this.lastUpdate,
    required this.timestamp,
  });

  factory CurrencyRate.fromJson(Map<String, dynamic> json) {
    return CurrencyRate(
      currency: json['currency'] ?? '',
      value: (json['value'] as num?)?.toDouble() ?? 0.0,
      lastUpdate: DateTime.parse(json['lastUpdate'] ?? DateTime.now().toIso8601String()),
      timestamp: DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'currency': currency,
      'value': value,
      'lastUpdate': lastUpdate.toIso8601String(),
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class CurrencyRatesResponse {
  final CurrencyRate usd;
  final CurrencyRate eur;
  final CurrencyRate mlc;
  final DateTime lastUpdate;
  final DateTime timestamp;

  CurrencyRatesResponse({
    required this.usd,
    required this.eur,
    required this.mlc,
    required this.lastUpdate,
    required this.timestamp,
  });

  factory CurrencyRatesResponse.fromJson(Map<String, dynamic> json) {
    final lastUpdate = DateTime.parse(json['lastUpdate'] ?? DateTime.now().toIso8601String());
    final timestamp = DateTime.parse(json['timestamp'] ?? DateTime.now().toIso8601String());

    return CurrencyRatesResponse(
      usd: CurrencyRate(
        currency: 'USD',
        value: (json['USD']?['value'] as num?)?.toDouble() ?? 420.0,
        lastUpdate: lastUpdate,
        timestamp: timestamp,
      ),
      eur: CurrencyRate(
        currency: 'EUR',
        value: (json['EUR']?['value'] as num?)?.toDouble() ?? 470.0,
        lastUpdate: lastUpdate,
        timestamp: timestamp,
      ),
      mlc: CurrencyRate(
        currency: 'MLC',
        value: (json['MLC']?['value'] as num?)?.toDouble() ?? 60.0,
        lastUpdate: lastUpdate,
        timestamp: timestamp,
      ),
      lastUpdate: lastUpdate,
      timestamp: timestamp,
    );
  }

  // Default rates to use when API and database both fail
  factory CurrencyRatesResponse.defaultRates() {
    final now = DateTime.now();
    print('⚠️ Using hardcoded default rates as final fallback');
    print('💡 These values should only be used when both API and database fail');
    return CurrencyRatesResponse(
      usd: CurrencyRate(
        currency: 'USD',
        value: 440.0, // Hardcoded fallback - should be rare
        lastUpdate: now,
        timestamp: now,
      ),
      eur: CurrencyRate(
        currency: 'EUR',
        value: 495.0, // Hardcoded fallback - should be rare
        lastUpdate: now,
        timestamp: now,
      ),
      mlc: CurrencyRate(
        currency: 'MLC',
        value: 210.0, // Hardcoded fallback - should be rare
        lastUpdate: now,
        timestamp: now,
      ),
      lastUpdate: now,
      timestamp: now,
    );
  }

  List<CurrencyRate> get rates => [usd, eur, mlc];
}
