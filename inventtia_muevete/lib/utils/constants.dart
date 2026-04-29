import 'package:flutter/material.dart';

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

  // Vehicle icons (Material Icons code points) — kept for legacy reference
  static const Map<String, int> vehicleIcons = {
    vehicleMoto: 0xe333, // two_wheeler
    vehicleAuto: 0xe531, // directions_car
    vehicleMicrobus: 0xe530, // directions_bus
  };

  /// Returns a constant IconData for a vehicle label.
  /// Use this instead of `IconData(codePoint)` to keep icons tree-shakeable.
  static IconData vehicleIconData(String vehicleLabel) {
    switch (vehicleLabel) {
      case vehicleMoto:
        return Icons.two_wheeler;
      case vehicleMicrobus:
        return Icons.directions_bus;
      case vehicleAuto:
      default:
        return Icons.directions_car;
    }
  }

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

  // After this delay without offers, requests become visible to ALL drivers
  static const Duration globalVisibilityDelay = Duration(minutes: 1);

  // Default search radius for nearby drivers (km)
  static const double defaultSearchRadiusKm = 50.0;
  static const double maxSearchRadiusKm = 100.0;

  // Expanding radius steps (km) and interval
  static const List<double> radiusSteps = [50, 75, 100];
  static const Duration radiusExpansionInterval = Duration(seconds: 30);

  // Default map center (Cuba)
  static const double defaultLat = 22.406959;
  static const double defaultLon = -79.965681;
  static const double defaultZoom = 14.0;

  // Santa Clara city zone pricing
  static const double cityCenterLat = 22.40689;
  static const double cityCenterLon = -79.96450;
  static const double cityRadiusKm = 2.53;
}
