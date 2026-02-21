class AppConstants {
  // Vehicle types
  static const String vehicleMoto = 'Moto';
  static const String vehicleAuto = 'Auto';
  static const String vehicleMicrobus = 'Microbus';

  static const List<String> vehicleTypes = [
    vehicleMoto,
    vehicleAuto,
    vehicleMicrobus,
  ];

  // Vehicle icons (Material Icons code points)
  static const Map<String, int> vehicleIcons = {
    vehicleMoto: 0xe333, // two_wheeler
    vehicleAuto: 0xe531, // directions_car
    vehicleMicrobus: 0xe530, // directions_bus
  };

  // Request states
  static const String estadoPendiente = 'pendiente';
  static const String estadoAceptada = 'aceptada';
  static const String estadoCancelada = 'cancelada';
  static const String estadoExpirada = 'expirada';
  static const String estadoRechazada = 'rechazada';

  // Wallet transaction types
  static const String txRecarga = 'recarga';
  static const String txCobroViaje = 'cobro_viaje';
  static const String txPagoViaje = 'pago_viaje';

  // User roles
  static const String roleClient = 'client';
  static const String roleDriver = 'driver';

  // Request TTL
  static const Duration requestTtl = Duration(hours: 1);

  // Default search radius for nearby drivers (km)
  static const double defaultSearchRadiusKm = 10.0;
  static const double maxSearchRadiusKm = 50.0;

  // Default map center (Cuba)
  static const double defaultLat = 22.406959;
  static const double defaultLon = -79.965681;
  static const double defaultZoom = 14.0;
}
