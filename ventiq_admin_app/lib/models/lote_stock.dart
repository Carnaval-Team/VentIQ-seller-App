/// Saldo de un lote en una ubicación (RPC `fn_stock_lotes_en_ubicacion`).
class LoteStockInfo {
  final int idProducto;
  final int? idVariante;
  final int? idOpcionVariante;
  final int? idPresentacion;
  final int idLote;
  final String codigoLote;
  final DateTime? fechaVencimiento;
  final double cantidadFinal;
  final double? diasAlertCaducidad;
  final bool esPorLotes;
  final String estadoCaducidad; // ok | expiring | expired | sin_lote
  final int? idUbicacion;
  final String? ubicacionLabel;
  final String? productoNombre;

  const LoteStockInfo({
    required this.idProducto,
    this.idVariante,
    this.idOpcionVariante,
    this.idPresentacion,
    required this.idLote,
    required this.codigoLote,
    this.fechaVencimiento,
    required this.cantidadFinal,
    this.diasAlertCaducidad,
    this.esPorLotes = true,
    required this.estadoCaducidad,
    this.idUbicacion,
    this.ubicacionLabel,
    this.productoNombre,
  });

  factory LoteStockInfo.fromJson(
    Map<String, dynamic> json, {
    int? idUbicacion,
    String? ubicacionLabel,
    String? productoNombre,
  }) {
    DateTime? parseDate(dynamic v) {
      if (v == null) return null;
      if (v is DateTime) return v;
      return DateTime.tryParse(v.toString());
    }

    int? parseInt(dynamic v) {
      if (v == null) return null;
      if (v is num) return v.toInt();
      return int.tryParse(v.toString());
    }

    return LoteStockInfo(
      idProducto: parseInt(json['id_producto']) ?? 0,
      idVariante: parseInt(json['id_variante']),
      idOpcionVariante: parseInt(json['id_opcion_variante']),
      idPresentacion: parseInt(json['id_presentacion']),
      idLote: parseInt(json['id_lote']) ?? 0,
      codigoLote: () {
        final code = json['codigo_lote']?.toString() ??
            json['codigo']?.toString() ??
            '';
        final idLote = parseInt(json['id_lote']) ?? 0;
        if (code.isNotEmpty) return code;
        if (idLote <= 0) return 'Sin lote';
        return '';
      }(),
      fechaVencimiento: parseDate(json['fecha_vencimiento']),
      cantidadFinal: (json['cantidad_final'] as num?)?.toDouble() ?? 0,
      diasAlertCaducidad: (json['dias_alert_caducidad'] as num?)?.toDouble(),
      esPorLotes: json['es_por_lotes'] == true,
      estadoCaducidad: json['estado_caducidad']?.toString() ??
          ((parseInt(json['id_lote']) ?? 0) <= 0 ? 'sin_lote' : 'ok'),
      idUbicacion: idUbicacion ?? parseInt(json['id_ubicacion']),
      ubicacionLabel: ubicacionLabel ?? json['ubicacion']?.toString(),
      productoNombre: productoNombre ?? json['producto_nombre']?.toString(),
    );
  }

  int? get diasRestantes {
    final f = fechaVencimiento;
    if (f == null) return null;
    final today = DateTime.now();
    final a = DateTime(today.year, today.month, today.day);
    final b = DateTime(f.year, f.month, f.day);
    return b.difference(a).inDays;
  }

  String get fechaLabel {
    final f = fechaVencimiento;
    if (f == null) return '—';
    final d = f.day.toString().padLeft(2, '0');
    final m = f.month.toString().padLeft(2, '0');
    return '$d/$m/${f.year}';
  }

  String get resumenCorto {
    final dias = diasRestantes;
    final diasTxt = dias == null
        ? ''
        : dias < 0
            ? ' · vencido'
            : ' · ${dias}d';
    return 'Lote $codigoLote · vence $fechaLabel$diasTxt';
  }

  /// Comparador FEFO: vence antes primero; nulls al final.
  static int compareFefo(LoteStockInfo a, LoteStockInfo b) {
    final fa = a.fechaVencimiento;
    final fb = b.fechaVencimiento;
    if (fa == null && fb == null) return a.idLote.compareTo(b.idLote);
    if (fa == null) return 1;
    if (fb == null) return -1;
    final byDate = fa.compareTo(fb);
    if (byDate != 0) return byDate;
    return a.idLote.compareTo(b.idLote);
  }

  /// Lote que vence primero (FEFO).
  static LoteStockInfo? proximoAVencer(Iterable<LoteStockInfo> lotes) {
    final list = lotes.toList();
    if (list.isEmpty) return null;
    list.sort(compareFefo);
    return list.first;
  }

  static List<LoteStockInfo> ordenadosFefo(Iterable<LoteStockInfo> lotes) {
    final list = lotes.toList()..sort(compareFefo);
    return list;
  }
}
