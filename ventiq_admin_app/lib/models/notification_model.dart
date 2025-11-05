import 'package:flutter/material.dart';

/// Tipos de notificación disponibles
enum NotificationType {
  alerta,
  info,
  warning,
  success,
  error,
  promocion,
  sistema,
  pedido,
  inventario,
  venta,
}

/// Prioridades de notificación
enum NotificationPriority {
  baja,
  normal,
  alta,
  urgente,
}

/// Modelo de notificación
class NotificationModel {
  final int id;
  final String userId;
  final NotificationType tipo;
  final String titulo;
  final String mensaje;
  final Map<String, dynamic>? data;
  final NotificationPriority prioridad;
  final bool leida;
  final bool archivada;
  final String? accion;
  final String? icono;
  final String? color;
  final DateTime? fechaExpiracion;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? leidaAt;

  NotificationModel({
    required this.id,
    required this.userId,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    this.data,
    required this.prioridad,
    required this.leida,
    required this.archivada,
    this.accion,
    this.icono,
    this.color,
    this.fechaExpiracion,
    required this.createdAt,
    required this.updatedAt,
    this.leidaAt,
  });

  /// Crear desde JSON de Supabase
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int,
      userId: json['user_id'] as String? ?? '',
      tipo: _parseNotificationType(json['tipo'] as String?),
      titulo: json['titulo'] as String? ?? '',
      mensaje: json['mensaje'] as String? ?? '',
      data: json['data'] as Map<String, dynamic>?,
      prioridad: _parseNotificationPriority(json['prioridad'] as String?),
      leida: json['leida'] as bool? ?? false,
      archivada: json['archivada'] as bool? ?? false,
      accion: json['accion'] as String?,
      icono: json['icono'] as String?,
      color: json['color'] as String?,
      fechaExpiracion: json['fecha_expiracion'] != null
          ? DateTime.parse(json['fecha_expiracion'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      leidaAt: json['leida_at'] != null
          ? DateTime.parse(json['leida_at'] as String)
          : null,
    );
  }

  /// Convertir a JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'tipo': tipo.name,
      'titulo': titulo,
      'mensaje': mensaje,
      'data': data,
      'prioridad': prioridad.name,
      'leida': leida,
      'archivada': archivada,
      'accion': accion,
      'icono': icono,
      'color': color,
      'fecha_expiracion': fechaExpiracion?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'leida_at': leidaAt?.toIso8601String(),
    };
  }

  /// Parsear tipo de notificación desde string
  static NotificationType _parseNotificationType(String? tipo) {
    if (tipo == null) return NotificationType.info;
    try {
      return NotificationType.values.firstWhere(
        (e) => e.name == tipo,
        orElse: () => NotificationType.info,
      );
    } catch (e) {
      return NotificationType.info;
    }
  }

  /// Parsear prioridad desde string
  static NotificationPriority _parseNotificationPriority(String? prioridad) {
    if (prioridad == null) return NotificationPriority.normal;
    try {
      return NotificationPriority.values.firstWhere(
        (e) => e.name == prioridad,
        orElse: () => NotificationPriority.normal,
      );
    } catch (e) {
      return NotificationPriority.normal;
    }
  }

  /// Obtener color según tipo de notificación
  Color getColor() {
    if (color != null && color!.isNotEmpty) {
      try {
        return Color(int.parse(color!.replaceFirst('#', '0xFF')));
      } catch (e) {
        // Si hay error parseando el color, usar color por defecto
      }
    }

    // Colores por defecto según tipo
    switch (tipo) {
      case NotificationType.alerta:
        return const Color(0xFFFF9800); // Naranja
      case NotificationType.info:
        return const Color(0xFF2196F3); // Azul
      case NotificationType.warning:
        return const Color(0xFFFFC107); // Amarillo
      case NotificationType.success:
        return const Color(0xFF4CAF50); // Verde
      case NotificationType.error:
        return const Color(0xFFF44336); // Rojo
      case NotificationType.promocion:
        return const Color(0xFF9C27B0); // Púrpura
      case NotificationType.sistema:
        return const Color(0xFF607D8B); // Gris azulado
      case NotificationType.pedido:
        return const Color(0xFF00BCD4); // Cyan
      case NotificationType.inventario:
        return const Color(0xFFFF5722); // Naranja profundo
      case NotificationType.venta:
        return const Color(0xFF8BC34A); // Verde claro
    }
  }

  /// Obtener icono según tipo de notificación
  IconData getIcon() {
    if (icono != null && icono!.isNotEmpty) {
      // Aquí podrías mapear nombres de iconos a IconData
      // Por ahora usamos el icono por defecto del tipo
    }

    switch (tipo) {
      case NotificationType.alerta:
        return Icons.warning_amber_rounded;
      case NotificationType.info:
        return Icons.info_outline_rounded;
      case NotificationType.warning:
        return Icons.warning_outlined;
      case NotificationType.success:
        return Icons.check_circle_outline_rounded;
      case NotificationType.error:
        return Icons.error_outline_rounded;
      case NotificationType.promocion:
        return Icons.local_offer_outlined;
      case NotificationType.sistema:
        return Icons.settings_outlined;
      case NotificationType.pedido:
        return Icons.shopping_bag_outlined;
      case NotificationType.inventario:
        return Icons.inventory_2_outlined;
      case NotificationType.venta:
        return Icons.point_of_sale_outlined;
    }
  }

  /// Verificar si la notificación está expirada
  bool get isExpired {
    if (fechaExpiracion == null) return false;
    return DateTime.now().isAfter(fechaExpiracion!);
  }

  /// Verificar si es urgente
  bool get isUrgent {
    return prioridad == NotificationPriority.urgente;
  }

  /// Copiar con modificaciones
  NotificationModel copyWith({
    int? id,
    String? userId,
    NotificationType? tipo,
    String? titulo,
    String? mensaje,
    Map<String, dynamic>? data,
    NotificationPriority? prioridad,
    bool? leida,
    bool? archivada,
    String? accion,
    String? icono,
    String? color,
    DateTime? fechaExpiracion,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? leidaAt,
  }) {
    return NotificationModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      tipo: tipo ?? this.tipo,
      titulo: titulo ?? this.titulo,
      mensaje: mensaje ?? this.mensaje,
      data: data ?? this.data,
      prioridad: prioridad ?? this.prioridad,
      leida: leida ?? this.leida,
      archivada: archivada ?? this.archivada,
      accion: accion ?? this.accion,
      icono: icono ?? this.icono,
      color: color ?? this.color,
      fechaExpiracion: fechaExpiracion ?? this.fechaExpiracion,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      leidaAt: leidaAt ?? this.leidaAt,
    );
  }

  @override
  String toString() {
    return 'NotificationModel(id: $id, tipo: ${tipo.name}, titulo: $titulo, leida: $leida)';
  }
}
