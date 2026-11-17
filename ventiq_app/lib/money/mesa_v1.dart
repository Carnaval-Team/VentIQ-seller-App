class MesaV1Exception implements Exception {
  final String code;
  MesaV1Exception(this.code);
  @override
  String toString() => code;
}

/// La mesa nueva no se une por producto si la moneda o el medio cambian.
class MesaV1 {
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static bool puedeUnir({
    required bool mismaPresentacion,
    required bool mismaMoneda,
    required bool mismoMedio,
  }) {
    return mismaPresentacion && mismaMoneda && mismoMedio;
  }

  /// La cantidad y el borrado de una línea nueva no pasan por la cuenta vieja.
  static bool permiteEditar(String? version) => version != 'producto-v1';

  /// Si el pedido ya resolvió el inventario, el cierre no lo vuelve a descontar.
  static bool debeDescontarAlCerrar({required bool stockMovido}) => !stockMovido;

  static Map<String, dynamic> solicitudCierre({
    required String clientUuid,
    required String clientUuidPago,
    required int idCuenta,
    int? idCliente,
  }) {
    return {
      'version_monetaria': 'producto-v1',
      'client_uuid': clientUuid,
      'client_uuid_pago': clientUuidPago,
      'id_cuenta': '$idCuenta',
      if (idCliente != null) 'id_cliente': '$idCliente',
    };
  }

  static void validarCuenta(Map<String, dynamic> json) {
    if (!json.containsKey('version_monetaria') || json['version_monetaria'] == null) {
      return;
    }
    if (json['version_monetaria'] != 'producto-v1') {
      throw MesaV1Exception('CONTRACT_VERSION_UNSUPPORTED');
    }
  }

  /// Una cuenta vieja no exige los campos nuevos. Una versión desconocida no se convierte.
  static void validarFila(Map<String, dynamic> json) {
    if (!json.containsKey('version_monetaria') || json['version_monetaria'] == null) {
      return;
    }
    if (json['version_monetaria'] != 'producto-v1') {
      throw MesaV1Exception('CONTRACT_VERSION_UNSUPPORTED');
    }
    final linea = json['id_linea_cliente']?.toString() ?? '';
    if (!_uuid.hasMatch(linea)) {
      throw MesaV1Exception('CONTRACT_VERSION_UNSUPPORTED');
    }
    final moneda = json['moneda_venta'];
    if (moneda != 'CUP' && moneda != 'USD') {
      throw MesaV1Exception('UNSUPPORTED_CURRENCY');
    }
    if (json['snapshot_precio'] is! Map) {
      throw MesaV1Exception('SNAPSHOT_INVALID');
    }
  }
}
