/// Formateo de cantidades por presentacion, identico al del servidor.
///
/// FASE 2 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md).
///
/// Estas funciones replican **exactamente** `fn_plural_presentacion` y
/// `fn_formatear_stock_mixto` de `presentaciones_inventario/02_helpers_lectura_mixta.sql`.
/// El SQL las declaro IMMUTABLE y sin consultar la base justamente para que el
/// cliente pudiera replicarlas: asi un ticket impreso offline dice lo mismo que
/// el reporte generado en el servidor.
///
/// Si cambia la regla en SQL, hay que cambiarla aca tambien. No inventar una
/// variante "parecida": el objetivo es que las dos digan lo mismo, letra por
/// letra.
class StockMixtoFormatter {
  StockMixtoFormatter._();

  /// Pluralizacion cosmetica del nombre de una presentacion.
  ///
  /// Replica `fn_plural_presentacion(text, numeric)`. El orden de los casos
  /// importa: "Bolsas" ya termina en s y no se toca, "Cartón" va antes que la
  /// regla de vocales.
  static String plural(String? nombre, num cantidad) {
    if (nombre == null || nombre.trim().isEmpty) return '';
    if (cantidad.abs() == 1) return nombre;

    final lower = nombre.toLowerCase();

    if (lower.endsWith('s')) return nombre;

    if (lower.endsWith('on') || lower.endsWith('ón')) {
      return '${nombre.substring(0, nombre.length - 2)}ones';
    }

    if (RegExp(r'[aeiou]$').hasMatch(lower)) return '${nombre}s';

    return '${nombre}es';
  }

  /// Formatea una cantidad sin ceros ni punto colgando.
  ///
  /// Replica `fn_fmt_cantidad(numeric)`, que nacio de un bug real: `to_char`
  /// con FM dejaba "4." en los enteros y salia "4. Cajas".
  ///
  /// Acepta null y devuelve "0" porque el SQL hace lo mismo
  /// (`fn_fmt_cantidad(null)` → `'0'`, verificado contra produccion): las filas
  /// del ledger pueden traer `cantidad` nula y las dos capas tienen que decidir
  /// igual.
  ///
  /// Redondea a 3 decimales como el SQL: `0.0005` → `0.001`, `1.9999` → `2`.
  static String cantidad(num? valor) {
    final v = valor ?? 0;
    if (v == v.roundToDouble()) return v.toInt().toString();

    // Hasta 3 decimales, sin ceros de relleno.
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// "4 Cajas + 4 Unidades". Omite las presentaciones con saldo 0.
  ///
  /// Replica `fn_formatear_stock_mixto(jsonb, boolean, text)`. Cada entrada
  /// necesita `nombre` y `cantidad`; `sku_codigo` es opcional y solo se usa con
  /// [abreviar].
  ///
  /// **El orden del array manda**: se respeta tal cual llega. Quien consulta lo
  /// ordena de mayor a menor factor (eso hace `fn_stock_mixto_json`).
  static String mixto(
    List<Map<String, dynamic>>? saldos, {
    bool abreviar = false,
    String vacio = 'Sin stock',
  }) {
    if (saldos == null || saldos.isEmpty) return vacio;

    final partes = <String>[];

    for (final s in saldos) {
      final cant = (s['cantidad'] as num?) ?? 0;
      if (cant == 0) continue;

      final nombre = s['nombre']?.toString() ?? 'Presentacion';
      final sku = s['sku_codigo']?.toString() ?? '';

      final etiqueta =
          (abreviar && sku.isNotEmpty) ? sku : plural(nombre, cant);

      partes.add('${cantidad(cant)} $etiqueta');
    }

    if (partes.isEmpty) return vacio;
    return partes.join(' + ');
  }

  /// Una sola linea de operacion: "4 Cajas" / "1 Bulto".
  ///
  /// Para las listas de operaciones, donde cada fila ya es de una presentacion.
  /// Cuando la presentacion no vino (operaciones viejas con `id_presentacion`
  /// nulo) devuelve solo la cantidad, sin inventar "unidades": el ledger no
  /// sabe en que estaba expresada esa fila.
  static String linea(num cant, String? nombrePresentacion) {
    final n = cantidad(cant);
    if (nombrePresentacion == null || nombrePresentacion.trim().isEmpty) {
      return n;
    }
    return '$n ${plural(nombrePresentacion, cant)}';
  }

  /// "4 Cajas + 4 u  ·  = 52 u" — el formato acordado en el plan.
  ///
  /// Se muestra el mixto y el equivalente juntos porque el modelo de VentIQ
  /// (saldos fisicos por presentacion) no es el de los ERP grandes, y sin el
  /// equivalente el usuario no puede comparar dos saldos de un vistazo.
  static String mixtoConEquivalente(
    List<Map<String, dynamic>>? saldos,
    num equivalenteBase,
    String nombreBase, {
    bool abreviar = false,
  }) {
    final m = mixto(saldos, abreviar: abreviar);
    if (saldos == null || saldos.isEmpty) return m;

    // Con una sola presentacion el equivalente repetiria lo mismo.
    final conSaldo = saldos.where((s) => ((s['cantidad'] as num?) ?? 0) != 0);
    if (conSaldo.length <= 1) return m;

    return '$m  ·  = ${cantidad(equivalenteBase)} '
        '${plural(nombreBase, equivalenteBase)}';
  }
}
