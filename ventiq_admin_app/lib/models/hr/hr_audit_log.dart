class HRAuditLog {
  final int id;
  final int idTrabajador;
  final int idTienda;
  final String campoModificado;
  final String? valorAnterior;
  final String? valorNuevo;
  final String modificadoPor;
  final String? motivo;
  final DateTime createdAt;

  HRAuditLog({
    required this.id,
    required this.idTrabajador,
    required this.idTienda,
    required this.campoModificado,
    this.valorAnterior,
    this.valorNuevo,
    required this.modificadoPor,
    this.motivo,
    required this.createdAt,
  });

  String get campoLabel {
    switch (campoModificado) {
      case 'salario_horas':
        return 'Salario por hora';
      case 'pago_por_resultado':
        return 'Pago por resultado';
      default:
        return campoModificado;
    }
  }

  factory HRAuditLog.fromJson(Map<String, dynamic> json) {
    return HRAuditLog(
      id: json['id'] as int,
      idTrabajador: json['id_trabajador'] as int,
      idTienda: json['id_tienda'] as int,
      campoModificado: json['campo_modificado'] as String,
      valorAnterior: json['valor_anterior'] as String?,
      valorNuevo: json['valor_nuevo'] as String?,
      modificadoPor: json['modificado_por'] as String? ?? '',
      motivo: json['motivo'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
