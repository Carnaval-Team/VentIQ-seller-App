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
      case 'salario_dia':
        return 'Salario por día';
      case 'tipo_salario':
        return 'Modalidad de pago';
      case 'pago_por_resultado':
        return 'Pago por resultado';
      default:
        return campoModificado;
    }
  }

  /// Los valores de modalidad se guardan como 'hora'/'dia' en la auditoría;
  /// aquí se traducen para mostrarlos legibles en el historial.
  String _formatValor(String? valor) {
    if (valor == null || valor.isEmpty) return 'N/A';
    if (campoModificado != 'tipo_salario') return valor;
    return valor == 'dia' ? 'Por día' : 'Por hora';
  }

  String get valorAnteriorLabel => _formatValor(valorAnterior);
  String get valorNuevoLabel => _formatValor(valorNuevo);

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
