import 'package:flutter/material.dart';

/// Configuración de envío diario automático (Plan Avanzado).
class WapiProgramacion {
  final int id;
  final int idTienda;
  final int idSesion;
  final String nombre;
  final TimeOfDay horaEnvio;
  final String timezone;
  final bool activa;
  final int delayMinSeconds;
  final int delayMaxSeconds;
  final DateTime? lastRunAt;
  final DateTime? nextRunAt;
  final List<int> productIds;
  final List<int> destinatarioIds;

  WapiProgramacion({
    required this.id,
    required this.idTienda,
    required this.idSesion,
    required this.nombre,
    required this.horaEnvio,
    required this.timezone,
    required this.activa,
    required this.delayMinSeconds,
    required this.delayMaxSeconds,
    this.lastRunAt,
    this.nextRunAt,
    this.productIds = const [],
    this.destinatarioIds = const [],
  });

  factory WapiProgramacion.fromJson(
    Map<String, dynamic> j, {
    List<int>? productIds,
    List<int>? destinatarioIds,
  }) {
    TimeOfDay parseHora(String? s) {
      if (s == null) return const TimeOfDay(hour: 9, minute: 0);
      final parts = s.split(':');
      if (parts.length < 2) return const TimeOfDay(hour: 9, minute: 0);
      return TimeOfDay(
        hour: int.tryParse(parts[0]) ?? 9,
        minute: int.tryParse(parts[1]) ?? 0,
      );
    }

    return WapiProgramacion(
      id: (j['id'] as num).toInt(),
      idTienda: (j['id_tienda'] as num).toInt(),
      idSesion: (j['id_sesion'] as num).toInt(),
      nombre: (j['nombre'] ?? 'Difusión diaria') as String,
      horaEnvio: parseHora(j['hora_envio'] as String?),
      timezone: (j['timezone'] ?? 'America/Mexico_City') as String,
      activa: (j['activa'] ?? true) as bool,
      delayMinSeconds: (j['delay_min_seconds'] as num?)?.toInt() ?? 5,
      delayMaxSeconds: (j['delay_max_seconds'] as num?)?.toInt() ?? 10,
      lastRunAt:
          j['last_run_at'] != null ? DateTime.tryParse(j['last_run_at']) : null,
      nextRunAt:
          j['next_run_at'] != null ? DateTime.tryParse(j['next_run_at']) : null,
      productIds: productIds ?? const [],
      destinatarioIds: destinatarioIds ?? const [],
    );
  }
}
