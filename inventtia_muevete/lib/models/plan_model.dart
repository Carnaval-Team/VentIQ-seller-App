class PlanModel {
  final int id;
  final String codigo;
  final String tipoUsuario; // 'shipper' | 'carrier' | 'dispatcher'
  final String nombre;
  final double precioMensual;
  final int? cargasMesMax; // null = ilimitado
  final int? contactosMesMax;
  final bool matchingAuto;
  final int? matchingDiarioMax;
  final double? escrowComision;
  final bool escrowIncluido;
  final bool alertasPush;
  final int? ventanaExclusivaHoras;
  final bool gpsBasico;
  final bool gpsAvanzado;
  final bool eldIntegrado;
  final int multiUsuarios;
  final bool apiAcceso;
  final bool factoraje;
  final String dashboardNivel; // 'ninguno' | 'basico' | 'avanzado'
  final String soporteNivel;   // 'email' | 'chat' | 'telefono'
  final int? soporteSlaH;
  final bool activo;
  final DateTime? createdAt;

  const PlanModel({
    required this.id,
    required this.codigo,
    required this.tipoUsuario,
    required this.nombre,
    required this.precioMensual,
    this.cargasMesMax,
    this.contactosMesMax,
    this.matchingAuto = false,
    this.matchingDiarioMax,
    this.escrowComision,
    this.escrowIncluido = false,
    this.alertasPush = false,
    this.ventanaExclusivaHoras,
    this.gpsBasico = false,
    this.gpsAvanzado = false,
    this.eldIntegrado = false,
    this.multiUsuarios = 1,
    this.apiAcceso = false,
    this.factoraje = false,
    this.dashboardNivel = 'ninguno',
    this.soporteNivel = 'email',
    this.soporteSlaH,
    this.activo = true,
    this.createdAt,
  });

  bool get esGratis => precioMensual == 0;
  bool get esIlimitado => cargasMesMax == null;

  factory PlanModel.fromJson(Map<String, dynamic> json) {
    return PlanModel(
      id: json['id'] as int,
      codigo: json['codigo'] as String,
      tipoUsuario: json['tipo_usuario'] as String,
      nombre: json['nombre'] as String,
      precioMensual: (json['precio_mensual'] as num).toDouble(),
      cargasMesMax: json['cargas_mes_max'] as int?,
      contactosMesMax: json['contactos_mes_max'] as int?,
      matchingAuto: json['matching_auto'] as bool? ?? false,
      matchingDiarioMax: json['matching_diario_max'] as int?,
      escrowComision: json['escrow_comision'] != null
          ? (json['escrow_comision'] as num).toDouble()
          : null,
      escrowIncluido: json['escrow_incluido'] as bool? ?? false,
      alertasPush: json['alertas_push'] as bool? ?? false,
      ventanaExclusivaHoras: json['ventana_exclusiva_horas'] as int?,
      gpsBasico: json['gps_basico'] as bool? ?? false,
      gpsAvanzado: json['gps_avanzado'] as bool? ?? false,
      eldIntegrado: json['eld_integrado'] as bool? ?? false,
      multiUsuarios: json['multi_usuarios'] as int? ?? 1,
      apiAcceso: json['api_acceso'] as bool? ?? false,
      factoraje: json['factoraje'] as bool? ?? false,
      dashboardNivel: json['dashboard_nivel'] as String? ?? 'ninguno',
      soporteNivel: json['soporte_nivel'] as String? ?? 'email',
      soporteSlaH: json['soporte_sla_h'] as int?,
      activo: json['activo'] as bool? ?? true,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'codigo': codigo,
        'tipo_usuario': tipoUsuario,
        'nombre': nombre,
        'precio_mensual': precioMensual,
        'cargas_mes_max': cargasMesMax,
        'contactos_mes_max': contactosMesMax,
        'matching_auto': matchingAuto,
        'matching_diario_max': matchingDiarioMax,
        'escrow_comision': escrowComision,
        'escrow_incluido': escrowIncluido,
        'alertas_push': alertasPush,
        'ventana_exclusiva_horas': ventanaExclusivaHoras,
        'gps_basico': gpsBasico,
        'gps_avanzado': gpsAvanzado,
        'eld_integrado': eldIntegrado,
        'multi_usuarios': multiUsuarios,
        'api_acceso': apiAcceso,
        'factoraje': factoraje,
        'dashboard_nivel': dashboardNivel,
        'soporte_nivel': soporteNivel,
        'soporte_sla_h': soporteSlaH,
        'activo': activo,
      };
}
