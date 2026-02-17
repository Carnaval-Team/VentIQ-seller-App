import 'package:flutter/material.dart';

enum EstadoRepartidor { activo, estacionado, inactivo }

class RepartidorFlota {
  final int id;
  final int? repartidorId;
  final String nombre;
  final String? telefono;
  final String? correo;
  final double latitud;
  final double longitud;
  final DateTime ultimaActualizacion;
  final EstadoRepartidor estado;
  final List<OrdenAsignada> ordenesAsignadas;

  RepartidorFlota({
    required this.id,
    this.repartidorId,
    required this.nombre,
    this.telefono,
    this.correo,
    required this.latitud,
    required this.longitud,
    required this.ultimaActualizacion,
    required this.estado,
    this.ordenesAsignadas = const [],
  });

  factory RepartidorFlota.fromMap(
    Map<String, dynamic> posicion, {
    List<OrdenAsignada> ordenes = const [],
  }) {
    final ultimaAct = DateTime.tryParse(
          posicion['ultima_actualizacion']?.toString() ?? '',
        ) ??
        DateTime.now();

    final diff = DateTime.now().difference(ultimaAct);
    EstadoRepartidor estado;
    if (diff.inHours >= 3) {
      estado = EstadoRepartidor.inactivo;
    } else if (diff.inHours >= 1) {
      estado = EstadoRepartidor.estacionado;
    } else {
      estado = EstadoRepartidor.activo;
    }

    final repartidorData = posicion['repartidores'] as Map<String, dynamic>?;

    return RepartidorFlota(
      id: posicion['id'] is int
          ? posicion['id']
          : int.tryParse(posicion['id'].toString()) ?? 0,
      repartidorId: posicion['repartidor_id'] is int
          ? posicion['repartidor_id']
          : int.tryParse(posicion['repartidor_id']?.toString() ?? ''),
      nombre: repartidorData?['nombre']?.toString() ??
          posicion['nombre']?.toString() ??
          'Sin nombre',
      telefono: repartidorData?['telefono']?.toString(),
      correo: repartidorData?['correo']?.toString(),
      latitud: (posicion['latitud'] as num).toDouble(),
      longitud: (posicion['longitud'] as num).toDouble(),
      ultimaActualizacion: ultimaAct,
      estado: estado,
      ordenesAsignadas: ordenes,
    );
  }

  Color get colorEstado {
    switch (estado) {
      case EstadoRepartidor.activo:
        return const Color(0xFF4CAF50);
      case EstadoRepartidor.estacionado:
        return const Color(0xFFFF9800);
      case EstadoRepartidor.inactivo:
        return const Color(0xFFF44336);
    }
  }

  String get estadoLabel {
    switch (estado) {
      case EstadoRepartidor.activo:
        return 'Activo';
      case EstadoRepartidor.estacionado:
        return 'Estacionado';
      case EstadoRepartidor.inactivo:
        return 'Inactivo';
    }
  }

  IconData get estadoIcon {
    switch (estado) {
      case EstadoRepartidor.activo:
        return Icons.directions_bike;
      case EstadoRepartidor.estacionado:
        return Icons.local_parking;
      case EstadoRepartidor.inactivo:
        return Icons.power_settings_new;
    }
  }

  String get tiempoDesdeUltimaActualizacion {
    final diff = DateTime.now().difference(ultimaActualizacion);
    if (diff.inDays > 0) return 'hace ${diff.inDays}d';
    if (diff.inHours > 0) return 'hace ${diff.inHours}h';
    if (diff.inMinutes > 0) return 'hace ${diff.inMinutes}min';
    return 'ahora';
  }
}

class OrdenAsignada {
  final int id;
  final double total;
  final String? direccion;
  final DateTime createdAt;
  final List<DetalleOrden> detalles;

  OrdenAsignada({
    required this.id,
    required this.total,
    this.direccion,
    required this.createdAt,
    this.detalles = const [],
  });

  factory OrdenAsignada.fromMap(Map<String, dynamic> map) {
    final detallesRaw = map['OrderDetails'] as List<dynamic>? ?? [];
    final detalles = detallesRaw
        .map((d) => DetalleOrden.fromMap(d as Map<String, dynamic>))
        .toList();

    return OrdenAsignada(
      id: map['id'] is int
          ? map['id']
          : int.tryParse(map['id'].toString()) ?? 0,
      total: (map['total'] as num?)?.toDouble() ?? 0,
      direccion: map['direccion']?.toString(),
      createdAt:
          DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
      detalles: detalles,
    );
  }

  int get totalProductos => detalles.fold(0, (sum, d) => sum + d.cantidad);
}

class DetalleOrden {
  final int id;
  final int cantidad;
  final double precio;
  final String productoNombre;
  final String? productoImagen;

  DetalleOrden({
    required this.id,
    required this.cantidad,
    required this.precio,
    required this.productoNombre,
    this.productoImagen,
  });

  factory DetalleOrden.fromMap(Map<String, dynamic> map) {
    final producto = map['Productos'] as Map<String, dynamic>?;

    return DetalleOrden(
      id: map['id'] is int
          ? map['id']
          : int.tryParse(map['id'].toString()) ?? 0,
      cantidad: (map['quantity'] as num?)?.toInt() ?? 0,
      precio: (map['price'] as num?)?.toDouble() ?? 0,
      productoNombre: producto?['name']?.toString() ?? 'Producto',
      productoImagen: producto?['image']?.toString(),
    );
  }
}
