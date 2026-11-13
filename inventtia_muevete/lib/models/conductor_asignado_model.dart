/// Conductor asignado a la solicitud activa del cliente.
///
/// En el flujo de precio fijo ya no existen "ofertas": cuando un chofer toma
/// el viaje (`fn_tomar_viaje`), la solicitud queda con `driver_id` y desde
/// ahí se leen los datos del conductor y de su vehículo.
///
/// Los datos personales/vehículo no vienen en el pago de `fn_viajes_disponibles`
/// ni en `fn_crear_solicitud`: se enriquecen con `drivers` + `vehiculos`
/// mediante [TransportRequestService.getDriverDetails].
class ConductorAsignado {
  final int? driverId;

  /// Precio que paga el cliente por el viaje (viene de la solicitud).
  final double? precio;

  final String? driverName;
  final String? driverImage;
  final String? driverPhone;

  /// El conductor tiene teléfono registrado (se muestra como "verificado").
  final bool driverKyc;

  final String? vehicleMarca;
  final String? vehicleModelo;
  final String? vehicleChapa;
  final String? vehicleColor;
  final int? tripCount;
  final double? driverRating;

  /// ETA estático (minutos) calculado a partir de la distancia.
  final int? tiempoEstimado;

  /// Mensaje del conductor. En el flujo nuevo no se usa; queda por
  /// compatibilidad con datos históricos.
  final String? mensaje;

  const ConductorAsignado({
    this.driverId,
    this.precio,
    this.driverName,
    this.driverImage,
    this.driverPhone,
    this.driverKyc = false,
    this.vehicleMarca,
    this.vehicleModelo,
    this.vehicleChapa,
    this.vehicleColor,
    this.tripCount,
    this.driverRating,
    this.tiempoEstimado,
    this.mensaje,
  });

  /// Construye el modelo con el mapa que devuelve
  /// `TransportRequestService.getDriverDetails` (claves `driver_*` /
  /// `vehicle_*` / `trip_count`).
  factory ConductorAsignado.fromDriverDetails(
    Map<String, dynamic>? data, {
    double? precio,
    int? tiempoEstimado,
  }) {
    final row = data ?? const <String, dynamic>{};
    return ConductorAsignado(
      driverId: _asInt(row['driver_id']),
      precio: precio,
      driverName: _asString(row['driver_name']),
      driverImage: _asString(row['driver_image']),
      driverPhone: _asString(row['driver_phone']),
      driverKyc: row['driver_kyc'] == true,
      vehicleMarca: _asString(row['vehicle_marca']),
      vehicleModelo: _asString(row['vehicle_modelo']),
      vehicleChapa: _asString(row['vehicle_chapa']),
      vehicleColor: _asString(row['vehicle_color']),
      tripCount: _asInt(row['trip_count']),
      driverRating: _asDouble(row['driver_rating']),
      tiempoEstimado: tiempoEstimado,
      mensaje: _asString(row['mensaje']),
    );
  }

  bool get tieneVehiculo =>
      (vehicleMarca ?? '').isNotEmpty ||
      (vehicleModelo ?? '').isNotEmpty ||
      (vehicleChapa ?? '').isNotEmpty;

  /// "Marca Modelo Color" sin espacios sobrantes.
  String get vehiculoDescripcion => [
        vehicleMarca ?? '',
        vehicleModelo ?? '',
        vehicleColor ?? '',
      ].where((s) => s.isNotEmpty).join(' ');

  static int? _asInt(Object? value) {
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }
}