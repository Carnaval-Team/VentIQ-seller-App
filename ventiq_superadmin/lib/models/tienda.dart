class Tienda {
  final int id;
  final String nombre;
  final String direccion;
  final String ubicacion;
  final String estado; // activa, inactiva, suspendida
  final DateTime fechaCreacion;
  final DateTime? fechaVencimientoLicencia;
  final String tipoLicencia; // gratuita, premium, enterprise
  final int totalProductos;
  final double ventasMes;
  final int totalEmpleados;

  Tienda({
    required this.id,
    required this.nombre,
    required this.direccion,
    required this.ubicacion,
    required this.estado,
    required this.fechaCreacion,
    this.fechaVencimientoLicencia,
    required this.tipoLicencia,
    required this.totalProductos,
    required this.ventasMes,
    required this.totalEmpleados,
  });

  bool get licenciaVencida {
    if (fechaVencimientoLicencia == null) return false;
    return DateTime.now().isAfter(fechaVencimientoLicencia!);
  }

  int get diasParaVencimiento {
    if (fechaVencimientoLicencia == null) return -1;
    return fechaVencimientoLicencia!.difference(DateTime.now()).inDays;
  }

  bool get necesitaRenovacion {
    return diasParaVencimiento >= 0 && diasParaVencimiento <= 30;
  }

  factory Tienda.fromJson(Map<String, dynamic> json) {
    return Tienda(
      id: json['id'],
      nombre: json['nombre'],
      direccion: json['direccion'],
      ubicacion: json['ubicacion'],
      estado: json['estado'],
      fechaCreacion: DateTime.parse(json['fecha_creacion']),
      fechaVencimientoLicencia: json['fecha_vencimiento_licencia'] != null
          ? DateTime.parse(json['fecha_vencimiento_licencia'])
          : null,
      tipoLicencia: json['tipo_licencia'],
      totalProductos: json['total_productos'] ?? 0,
      ventasMes: (json['ventas_mes'] ?? 0.0).toDouble(),
      totalEmpleados: json['total_empleados'] ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'nombre': nombre,
      'direccion': direccion,
      'ubicacion': ubicacion,
      'estado': estado,
      'fecha_creacion': fechaCreacion.toIso8601String(),
      'fecha_vencimiento_licencia': fechaVencimientoLicencia?.toIso8601String(),
      'tipo_licencia': tipoLicencia,
      'total_productos': totalProductos,
      'ventas_mes': ventasMes,
      'total_empleados': totalEmpleados,
    };
  }

  static List<Tienda> getMockData() {
    return [
      Tienda(
        id: 1,
        nombre: 'Supermercado Central',
        direccion: 'Av. Principal 123',
        ubicacion: 'Santo Domingo, RD',
        estado: 'activa',
        fechaCreacion: DateTime.now().subtract(const Duration(days: 180)),
        fechaVencimientoLicencia: DateTime.now().add(const Duration(days: 45)),
        tipoLicencia: 'premium',
        totalProductos: 1250,
        ventasMes: 45000.00,
        totalEmpleados: 12,
      ),
      Tienda(
        id: 2,
        nombre: 'Minimarket La Esquina',
        direccion: 'Calle 5ta #45',
        ubicacion: 'Santiago, RD',
        estado: 'activa',
        fechaCreacion: DateTime.now().subtract(const Duration(days: 90)),
        fechaVencimientoLicencia: DateTime.now().add(const Duration(days: 15)),
        tipoLicencia: 'gratuita',
        totalProductos: 350,
        ventasMes: 12000.00,
        totalEmpleados: 4,
      ),
      Tienda(
        id: 3,
        nombre: 'Farmacia San Miguel',
        direccion: 'Av. Independencia 789',
        ubicacion: 'La Vega, RD',
        estado: 'activa',
        fechaCreacion: DateTime.now().subtract(const Duration(days: 365)),
        fechaVencimientoLicencia: DateTime.now().add(const Duration(days: 120)),
        tipoLicencia: 'enterprise',
        totalProductos: 2100,
        ventasMes: 78000.00,
        totalEmpleados: 18,
      ),
      Tienda(
        id: 4,
        nombre: 'Colmado Don Juan',
        direccion: 'Calle Duarte 234',
        ubicacion: 'San Pedro de Macorís, RD',
        estado: 'suspendida',
        fechaCreacion: DateTime.now().subtract(const Duration(days: 60)),
        fechaVencimientoLicencia: DateTime.now().subtract(const Duration(days: 5)),
        tipoLicencia: 'gratuita',
        totalProductos: 180,
        ventasMes: 5000.00,
        totalEmpleados: 2,
      ),
    ];
  }
}
