import 'package:flutter/material.dart';

class VehicleTypeModel {
  final int id;
  final String tipo;
  final double precioKmDefault;
  final double tiempoMinPorKm;
  final bool status;

  const VehicleTypeModel({
    required this.id,
    required this.tipo,
    required this.precioKmDefault,
    required this.tiempoMinPorKm,
    required this.status,
  });

  factory VehicleTypeModel.fromJson(Map<String, dynamic> json) {
    return VehicleTypeModel(
      id: (json['id'] as num).toInt(),
      tipo: json['tipo'] as String,
      precioKmDefault: (json['precio_km_default'] as num).toDouble(),
      tiempoMinPorKm: json['tiempo_min_por_km'] != null
          ? (json['tiempo_min_por_km'] as num).toDouble()
          : 2.0,
      status: json['status'] as bool? ?? false,
    );
  }

  /// Estimated travel time in minutes for a given distance in km.
  double estimatedMinutes(double distanceKm) => tiempoMinPorKm * distanceKm;

  /// Formatted ETA string: "X min" or "Xh Ymin".
  String etaString(double distanceKm) {
    final mins = estimatedMinutes(distanceKm).round();
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m > 0 ? '${h}h ${m}min' : '${h}h';
  }

  /// Display name with first letter uppercase.
  String get displayName =>
      tipo[0].toUpperCase() + tipo.substring(1).toLowerCase();

  /// Icon for this vehicle type based on the tipo string.
  IconData get icon {
    switch (tipo.toLowerCase()) {
      case 'moto':
        return Icons.two_wheeler;
      case 'auto':
        return Icons.directions_car;
      case 'microbus':
        return Icons.directions_bus;
      case 'camioneta':
        return Icons.airport_shuttle;
      case 'bicicleta':
        return Icons.pedal_bike;
      case 'tuktuk':
        return Icons.electric_rickshaw;
      case 'minivan':
        return Icons.directions_bus_filled;
      case 'camion':
        return Icons.local_shipping;
      default:
        return Icons.directions_car;
    }
  }

  /// Passenger capacity hint for display.
  int get passengerCount {
    switch (tipo.toLowerCase()) {
      case 'moto':
        return 1;
      case 'auto':
        return 4;
      case 'microbus':
        return 12;
      case 'camioneta':
        return 6;
      case 'bicicleta':
        return 1;
      case 'tuktuk':
        return 3;
      case 'minivan':
        return 8;
      case 'camion':
        return 1;
      default:
        return 4;
    }
  }
}
