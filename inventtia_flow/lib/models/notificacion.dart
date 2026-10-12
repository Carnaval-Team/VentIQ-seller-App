import 'package:flutter/material.dart';
import '../config/app_theme.dart';

class Notificacion {
  final int id;
  final String uuidUsuario;
  /// 'sala_espera' | 'reserva' | 'promo' | 'sistema' | 'suscripcion'
  final String tipo;
  final String titulo;
  final String mensaje;
  final bool leida;
  final DateTime? leidaAt;
  final int? idLocalServicio;
  final int? idReferencia;
  final Map<String, dynamic>? data;
  final DateTime createdAt;

  Notificacion({
    required this.id,
    required this.uuidUsuario,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    this.leidaAt,
    this.idLocalServicio,
    this.idReferencia,
    this.data,
    required this.createdAt,
  });

  factory Notificacion.fromJson(Map<String, dynamic> json) => Notificacion(
        id: (json['id'] as num).toInt(),
        uuidUsuario: json['uuid_usuario'] as String,
        tipo: (json['tipo'] as String?) ?? 'sistema',
        titulo: (json['titulo'] as String?) ?? '',
        mensaje: (json['mensaje'] as String?) ?? '',
        leida: json['leida'] as bool? ?? false,
        leidaAt: json['leida_at'] != null
            ? DateTime.parse(json['leida_at'] as String)
            : null,
        idLocalServicio: (json['id_local_servicio'] as num?)?.toInt(),
        idReferencia: (json['id_referencia'] as num?)?.toInt(),
        data: json['data'] as Map<String, dynamic>?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Notificacion copyWith({bool? leida, DateTime? leidaAt}) => Notificacion(
        id: id,
        uuidUsuario: uuidUsuario,
        tipo: tipo,
        titulo: titulo,
        mensaje: mensaje,
        leida: leida ?? this.leida,
        leidaAt: leidaAt ?? this.leidaAt,
        idLocalServicio: idLocalServicio,
        idReferencia: idReferencia,
        data: data,
        createdAt: createdAt,
      );

  // ── Helpers de presentación por tipo ──
  IconData get icono {
    switch (tipo) {
      case 'sala_espera':
        return Icons.event_seat;
      case 'reserva':
        return Icons.confirmation_number;
      case 'promo':
        return Icons.campaign;
      // Avisos de suscripción: pago reportado y plan acreditado. Se distinguen
      // del aviso genérico porque son los que el admin tiene que leer para saber
      // si su entidad sigue activa.
      case 'suscripcion':
        return Icons.workspace_premium;
      case 'sistema':
      default:
        return Icons.notifications;
    }
  }

  Color get color {
    switch (tipo) {
      case 'sala_espera':
        return AppTheme.accent;
      case 'reserva':
        return AppTheme.success;
      case 'promo':
        return AppTheme.warning;
      case 'sistema':
      default:
        return AppTheme.primary;
    }
  }
}
