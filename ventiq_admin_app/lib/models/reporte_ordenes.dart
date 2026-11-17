import 'report_envelope.dart';

/// Lectura de `reporte_ordenes_json` y de `reporte_ordenes_json_v2`.
///
/// La v2 añade el envelope y, en cada línea producto-v1, el neto nativo.
/// La pantalla de auditoría sigue leyendo `created_at`, `ordenes_completas`
/// y `ordenes_incompletas`: este adaptador rellena `created_at` desde
/// `fecha_operacion` y deja el resto del documento para esa pantalla.
class ReporteOrdenes {
  /// Valida el envelope cuando la respuesta es v2 y normaliza la fecha
  /// que ya pinta la auditoría. Una v1 sin `version_reporte` se devuelve
  /// igual. Un v2 malformado lanza [ReporteContratoException].
  static Map<String, dynamic> adaptar(Map<String, dynamic> raw) {
    final datos = Map<String, dynamic>.from(raw);
    if (datos['version_reporte'] != null) {
      ReporteEnvelope.parse(datos);
    }
    for (final clave in ['ordenes_completas', 'ordenes_incompletas']) {
      final lista = datos[clave];
      if (lista is! List) continue;
      datos[clave] = lista.map(_conFecha).toList(growable: false);
    }
    return datos;
  }

  static Map<String, dynamic> _conFecha(dynamic orden) {
    if (orden is! Map) return <String, dynamic>{};
    final copia = Map<String, dynamic>.from(orden);
    if (copia['created_at'] == null && copia['fecha_operacion'] != null) {
      copia['created_at'] = copia['fecha_operacion'];
    }
    return copia;
  }

  /// Neto nativo de la línea, con su moneda, tal como lo persistió la
  /// venta. Null si la línea es legacy: el llamador sigue formateando
  /// `importe` como CUP.
  static String? importeLineaNativo(Map item) {
    return _campoNativo(item['linea_v1'], 'importe_neto_nativo');
  }

  /// Precio unitario neto de la línea v1. Null en legacy.
  static String? precioUnitarioNativo(Map item) {
    return _campoNativo(item['linea_v1'], 'precio_unitario_neto_nativo');
  }

  /// Totales de la orden por moneda nativa (`12.50 USD · 500 CUP`).
  /// Null si la orden no trae el desglose v1: el llamador usa
  /// `total_operacion`.
  static String? totalesNativos(Map orden) {
    final venta = orden['venta'];
    if (venta is! Map) return null;
    final totales = venta['totales_por_moneda'];
    if (totales is! List || totales.isEmpty) return null;
    final partes = <String>[];
    for (final fila in totales) {
      if (fila is! Map) continue;
      final texto = _montoConMoneda(fila, 'neto_nativo', 'moneda');
      if (texto != null) partes.add(texto);
    }
    if (partes.isEmpty) return null;
    return partes.join(' · ');
  }

  static String? _campoNativo(dynamic linea, String campo) {
    if (linea is! Map) return null;
    return _montoConMoneda(linea, campo, 'moneda_venta');
  }

  static String? _montoConMoneda(Map fila, String campo, String claveMoneda) {
    final moneda = (fila[claveMoneda] ?? '').toString().trim();
    final monto = fila[campo];
    if (moneda.isEmpty || monto == null) return null;
    final texto = monto.toString().trim();
    if (texto.isEmpty) return null;
    return '$texto $moneda';
  }
}
