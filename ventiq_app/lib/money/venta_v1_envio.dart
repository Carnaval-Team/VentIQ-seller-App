import 'line_money.dart';
import 'product_currency_order.dart';
import 'exact_money.dart';

enum RutaEnvio { legacy, productoV1, retener, rechazar }

class DecisionEnvio {
  final RutaEnvio ruta;
  final String motivo;
  const DecisionEnvio(this.ruta, this.motivo);
}

class LineaCobro {
  final String idLinea;
  final String moneda;
  final int? medio;
  final bool pendiente;
  final String neto;
  final String cup;
  final bool tasaDisponible;

  const LineaCobro({
    required this.idLinea,
    required this.moneda,
    required this.medio,
    required this.pendiente,
    required this.neto,
    required this.cup,
    required this.tasaDisponible,
  });
}

class GrupoCobro {
  final String moneda;
  final int? medio;
  final String neto;
  final String cup;
  final List<Map<String, dynamic>> aplicaciones;

  const GrupoCobro({
    required this.moneda,
    required this.medio,
    required this.neto,
    required this.cup,
    required this.aplicaciones,
  });
}

/// Cobro de la venta nueva: suma netos ya fijados y no redistribuye.
class CheckoutV1 {
  static List<GrupoCobro> agrupar(List<LineaCobro> lineas) {
    final totales = <String, ExactMoney>{};
    final cups = <String, ExactMoney>{};
    final medios = <String, int?>{};
    final monedas = <String, String>{};
    final aplicaciones = <String, List<Map<String, dynamic>>>{};
    for (final linea in lineas) {
      if (linea.pendiente || linea.neto == '0' || linea.neto == '0.00') continue;
      if (!linea.tasaDisponible) continue;
      final clave = '${linea.moneda}|${linea.medio}';
      totales[clave] =
          (totales[clave] ?? ExactMoney.cero) + ExactMoney.parse(linea.neto);
      cups[clave] = (cups[clave] ?? ExactMoney.cero) + ExactMoney.parse(linea.cup);
      medios[clave] = linea.medio;
      monedas[clave] = linea.moneda;
      aplicaciones.putIfAbsent(clave, () => []).add({
        'id_linea_cliente': linea.idLinea,
        'monto_nativo': linea.neto,
      });
    }
    return [
      for (final clave in totales.keys)
        GrupoCobro(
          moneda: monedas[clave]!,
          medio: medios[clave],
          neto: totales[clave]!.toFixed(2),
          cup: cups[clave]!.toFixed(2),
          aplicaciones: aplicaciones[clave]!,
        ),
    ];
  }

  /// Una edición que no coincide con los grupos vuelve al detalle.
  static String? rechazoEdicion(
    List<GrupoCobro> grupos,
    List<Map<String, dynamic>> pagos,
  ) {
    if (pagos.length != grupos.length) {
      return 'El cobro no se redistribuye. Vuelve al detalle.';
    }
    for (final grupo in grupos) {
      final pago = pagos.cast<Map<String, dynamic>?>().firstWhere(
        (p) =>
            p?['moneda'] == grupo.moneda &&
            p?['id_medio_pago'] == grupo.medio &&
            p?['monto_nativo'] == grupo.neto,
        orElse: () => null,
      );
      if (pago == null) {
        return 'El cobro no se redistribuye. Vuelve al detalle.';
      }
    }
    return null;
  }
}

class EnvioV1 {
  static DecisionEnvio decidir({
    required String? version,
    required bool modoActivo,
    required bool bloqueaOrdenNueva,
    required bool tieneTasa,
    required bool lineasCompletas,
    required String origen,
  }) {
    if (version == null) {
      if (bloqueaOrdenNueva || modoActivo) {
        return const DecisionEnvio(
          RutaEnvio.rechazar,
          'Una orden nueva no puede omitir la moneda para usar el cobro anterior.',
        );
      }
      return const DecisionEnvio(RutaEnvio.legacy, 'Cobro anterior');
    }
    if (version != 'producto-v1') {
      return const DecisionEnvio(
        RutaEnvio.rechazar,
        'La version de la orden no se reconoce y no se convierte.',
      );
    }
    if (!lineasCompletas) {
      return const DecisionEnvio(
        RutaEnvio.retener,
        'Falta la moneda de una linea. La orden se conserva.',
      );
    }
    if (!tieneTasa) {
      return const DecisionEnvio(
        RutaEnvio.retener,
        'Falta la tasa. La orden se conserva para revision y no se inventa CUP.',
      );
    }
    // Mostrador y preorden comparten el alta v1: la preorden es un borrador
    // local del mismo mostrador. Mesa sigue retenida: exige cuenta valida.
    if (origen != 'mostrador' && origen != 'preorden') {
      return const DecisionEnvio(
        RutaEnvio.retener,
        'La mesa conserva su contrato y no se envia como mostrador.',
      );
    }
    return const DecisionEnvio(RutaEnvio.productoV1, 'Alta producto-v1');
  }

  static String origenDe(Map<String, dynamic> orderData, {bool mesa = false}) {
    if (mesa || orderData['id_mesa'] != null) return 'mesa';
    final raw = orderData['origen'];
    if (raw is Map && raw['tipo'] != null) return raw['tipo'].toString();
    return 'mostrador';
  }
}

class VentaV1Lineas {
  static bool todasConTasa(List<Map<String, dynamic>> selecciones) {
    if (selecciones.isEmpty) return false;
    return selecciones.every((s) => desdeMapa(s)?.tasaDisponible == true);
  }

  static List<LineaCobro> desdeMapas(List<Map<String, dynamic>> selecciones) {
    final lineas = <LineaCobro>[];
    for (final seleccion in selecciones) {
      final linea = desdeMapa(seleccion);
      if (linea != null) lineas.add(linea);
    }
    return lineas;
  }

  static LineaCobro? desdeMapa(Map<String, dynamic> json) {
    try {
      final seleccion = ProductCurrencySeleccion.fromJson(json);
      final ajuste = seleccion.ajustesAutomaticos.isEmpty
          ? null
          : seleccion.ajustesAutomaticos.first;
      final tasa = seleccion.monedaVenta == 'CUP'
          ? '1'
          : seleccion.snapshotTasa?['valor_publicado']?.toString();
      final calculo = LineMoneyCalculator.calcular(
        moneda: seleccion.monedaVenta,
        cantidad: seleccion.cantidad,
        precioUnitario: seleccion.precioUnitarioNativo,
        automaticoTipo: ajuste?['tipo']?.toString() ?? 'none',
        automaticoValor: ajuste?['valor']?.toString() ?? '0',
        manualUnitario: seleccion.descuentoManualUnitario,
        tasaCup: tasa,
      );
      return LineaCobro(
        idLinea: seleccion.idLineaCliente,
        moneda: seleccion.monedaVenta,
        medio: seleccion.idMedioPago,
        pendiente: seleccion.tipoCobro == 'pendiente',
        neto: calculo.neto.toFixed(2),
        cup: calculo.equivalenteCup.toFixed(2),
        tasaDisponible: true,
      );
    } on ProductCurrencyException catch (error) {
      if (error.code != 'SNAPSHOT_EVIDENCE_REQUIRED') return null;
      return LineaCobro(
        idLinea: json['id_linea_cliente']?.toString() ?? '',
        moneda: json['moneda_venta']?.toString() ?? '',
        medio: null,
        pendiente: false,
        neto: '0.00',
        cup: '0.00',
        tasaDisponible: false,
      );
    }
  }
}

class SolicitudV1 {
  static Map<String, dynamic>? venta({
    required String clientUuid,
    required int idTienda,
    required int idTpv,
    required int idVendedor,
    required Map<String, dynamic> politica,
    required List<Map<String, dynamic>> lineas,
    required String origen,
  }) {
    final revision = politica['revision'];
    final constancia = politica['constancia'];
    if (revision is! Map || constancia is! Map) return null;
    if (constancia['dispositivo'] == null || constancia['huella'] == null) {
      return null;
    }
    return {
      'version_monetaria': 'producto-v1',
      'client_uuid': clientUuid,
      'id_tienda': '$idTienda',
      'id_tpv': '$idTpv',
      'id_vendedor': '$idVendedor',
      'origen': {'tipo': origen, 'id_cuenta': null},
      'politica': {
        'id_revision': '${revision['id']}',
        'id_constancia': '${constancia['id']}',
        'dispositivo': constancia['dispositivo'],
        'huella': constancia['huella'],
      },
      'lineas': lineas,
    };
  }

  static Map<String, dynamic> pagos({
    required String clientUuid,
    required String pagoUuid,
    required List<GrupoCobro> grupos,
  }) {
    return {
      'version_monetaria': 'producto-v1',
      'client_uuid': pagoUuid,
      'client_uuid_venta': clientUuid,
      'pagos': [
        for (final grupo in grupos)
          {
            'monto_nativo': grupo.neto,
            'moneda': grupo.moneda,
            'id_medio_pago': grupo.medio,
            'aplicaciones': grupo.aplicaciones,
          },
      ],
    };
  }
}

/// Una orden sin version no se toca. La venta nueva no hereda el CUP implícito.
class ContratoPendiente {
  static void aplicar({
    required Map<String, dynamic> pending,
    required String? version,
    required String origen,
    required List<Map<String, dynamic>?> selecciones,
  }) {
    if (version == null) return;
    pending['version_monetaria'] = version;
    pending['origen'] = {'tipo': origen};
    final items = pending['items'];
    if (items is List) {
      for (var i = 0; i < items.length && i < selecciones.length; i++) {
        final seleccion = selecciones[i];
        final item = items[i];
        if (seleccion != null && item is Map) item['seleccion'] = seleccion;
      }
    }
    if (version == 'producto-v1') pending.remove('desglose_pagos');
  }
}
