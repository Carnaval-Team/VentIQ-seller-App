/// Moneda de la cuenta predeterminada de Fondo de Caja y si un egreso en cierta
/// moneda puede contabilizarse en ella. No se convierte: el egreso cuenta tal
/// cual en el fondo, así que las monedas deben coincidir.
class FondoCajaMoneda {
  /// Columnas de `dep_dat_banco` + el código de su moneda (`dep_nom_moneda`).
  static const String selectCuenta =
      'id, idtienda, denominacion, id_moneda, activo, '
      'moneda:dep_nom_moneda(codigo)';

  /// Código de la moneda de la cuenta (`CUP`, `USD`…), o null si el caché es
  /// anterior a que se guardara (hay que sincronizar online para conocerla).
  static String? codigo(Map<String, dynamic>? cuenta) {
    final moneda = cuenta?['moneda'];
    final raw = moneda is Map ? moneda['codigo'] : cuenta?['moneda_codigo'];
    final texto = raw?.toString().trim().toUpperCase() ?? '';
    return texto.isEmpty ? null : texto;
  }

  /// Mensaje de rechazo si el egreso en [moneda] no puede ir al fondo.
  static String? rechazo(Map<String, dynamic>? cuenta, String moneda) {
    if (cuenta == null) return 'No hay cuenta de Fondo de Caja';
    final cuentaMoneda = codigo(cuenta);
    final nombre = cuenta['denominacion'] ?? 'Fondo de Caja';
    if (cuentaMoneda == null) {
      return 'No se conoce la moneda de $nombre. Sincronice online antes de '
          'contabilizar en el Fondo de Caja.';
    }
    if (cuentaMoneda != moneda.trim().toUpperCase()) {
      return '$nombre es una cuenta en $cuentaMoneda: solo admite egresos en '
          '$cuentaMoneda.';
    }
    return null;
  }
}
