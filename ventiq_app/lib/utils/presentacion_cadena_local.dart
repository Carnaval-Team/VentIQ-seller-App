import 'dart:math' as math;

/// Un eslabon de la cadena de presentaciones, resuelto SIN llamar al servidor.
///
/// FASE 2 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md), lado
/// vendedor.
///
/// La app admin puede pedirle la cadena a `fn_presentaciones_producto`. Esta app
/// es offline-first: el vendedor entra mercancia sin red y el payload cacheado
/// en `offline_products` ya trae la lista cruda de presentaciones (la guarda
/// AutoSyncService._syncProducts). Lo que faltaba era ORDENARLA y calcular los
/// factores con la misma regla que el SQL.
///
/// Esta clase replica la cascada de `fn_presentaciones_producto` verificada
/// contra produccion (2026-08-27):
///
///   base   = ORDER BY es_base DESC, cantidad ASC, id ASC LIMIT 1
///   factorRel = round(cantidad / cantidad_de_la_base, 6)
///   nivel  = ROW_NUMBER() OVER (ORDER BY cantidad DESC, id ASC)
///
/// Los tres detalles que importan y que un "ordenar por es_base" ingenuo pierde:
///
///  1. La base NO es siempre la fila `es_base`: hay 9 productos sin ninguna
///     marcada. El SQL cae a la de menor factor, y desempata por menor id.
///  2. La base NO tiene factor 1: hay 131 filas `es_base` con cantidad 12, 24 o
///     30. Por eso todo se calcula con `factorRel`, nunca con `cantidad` cruda.
///  3. El orden de la cadena es por factor DESCENDENTE (empaque mayor primero),
///     no el orden en que vino el array.
class PresentacionLocal {
  /// `app_dat_producto_presentacion.id` — el id que viaja en los payloads de
  /// inventario. NO es el id del catalogo.
  final int idPresentacion;

  /// `app_nom_presentacion.id`, solo para el catalogo.
  final int idNomPresentacion;

  final String nombre;

  /// `app_dat_producto_presentacion.cantidad` tal como se guardo.
  final double factor;

  /// Factor relativo a la base. **Este** sirve para equivalencias.
  final double factorRel;

  final bool esBase;
  final String? skuCodigo;

  /// 1 = el empaque mas grande.
  final int nivel;

  const PresentacionLocal({
    required this.idPresentacion,
    required this.idNomPresentacion,
    required this.nombre,
    required this.factor,
    required this.factorRel,
    required this.esBase,
    required this.nivel,
    this.skuCodigo,
  });

  @override
  String toString() =>
      'PresentacionLocal($idPresentacion, $nombre, factor=$factor, '
      'rel=$factorRel, base=$esBase, nivel=$nivel)';
}

/// Resuelve la cadena de presentaciones desde el payload cacheado.
class PresentacionCadenaLocal {
  PresentacionCadenaLocal._();

  /// Saca la lista cruda de presentaciones de un producto cacheado.
  ///
  /// Prueba las mismas rutas que ya usaba admin_reception_screen, porque el
  /// payload cambia de forma segun de donde vino (sync completo, detalle batch o
  /// fallback).
  static List<Map<String, dynamic>> extraerCrudas(Map<String, dynamic> p) {
    final candidatos = [
      p['presentaciones'],
      p['detalles_completos']?['presentaciones'],
      p['detalles_producto']?['presentaciones'],
      p['producto_presentacion'],
      p['presentacion'],
    ];

    for (final raw in candidatos) {
      if (raw is List) {
        final list = raw
            .whereType<Map<dynamic, dynamic>>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        if (list.isNotEmpty) return list;
      }
      if (raw is Map) {
        return [Map<String, dynamic>.from(raw)];
      }
    }
    return [];
  }

  /// Cadena ordenada de mayor a menor factor, con `factorRel` y `nivel`.
  ///
  /// Devuelve lista vacia si el producto no tiene presentaciones utilizables.
  /// El llamador debe tratar eso como "no hay cadena conocida" y mandar
  /// `id_presentacion: null` para que la RPC resuelva la base.
  static List<PresentacionLocal> resolver(Map<String, dynamic> producto) {
    return resolverDesdeCrudas(extraerCrudas(producto));
  }

  /// Igual que [resolver] pero partiendo de la lista cruda ya extraida.
  static List<PresentacionLocal> resolverDesdeCrudas(
    List<Map<String, dynamic>> crudas,
  ) {
    final filas = <_Fila>[];

    for (final raw in crudas) {
      final id = _asInt(raw['id']);
      if (id == null) continue;

      // El nombre puede venir plano o anidado en el objeto del catalogo, segun
      // como se armo el payload.
      final pres = raw['presentacion'];
      String? nombre;
      String? sku;
      int? idNom;

      if (pres is Map) {
        nombre = pres['denominacion']?.toString();
        sku = pres['sku_codigo']?.toString();
        idNom = _asInt(pres['id']);
      }

      nombre ??= raw['denominacion']?.toString() ??
          raw['presentacion_nombre']?.toString();
      sku ??= raw['sku_codigo']?.toString();
      idNom ??= _asInt(raw['id_presentacion']);

      filas.add(_Fila(
        id: id,
        idNom: idNom ?? 0,
        nombre: (nombre == null || nombre.trim().isEmpty)
            ? 'Presentacion'
            : nombre,
        sku: sku,
        // Sin cantidad no se puede calcular nada: se asume 1, igual que el
        // COALESCE del SQL.
        cantidad: _asDouble(raw['cantidad']) ?? 1.0,
        esBaseMarcada: raw['es_base'] == true,
      ));
    }

    if (filas.isEmpty) return const [];

    // ── Cascada de la base: es_base DESC, cantidad ASC, id ASC ──────────────
    // Replica el ORDER BY del CTE `base` de fn_presentaciones_producto.
    final paraBase = List<_Fila>.from(filas)
      ..sort((a, b) {
        if (a.esBaseMarcada != b.esBaseMarcada) {
          return a.esBaseMarcada ? -1 : 1; // es_base DESC
        }
        final porCantidad = a.cantidad.compareTo(b.cantidad); // cantidad ASC
        if (porCantidad != 0) return porCantidad;
        return a.id.compareTo(b.id); // id ASC
      });

    final base = paraBase.first;

    // ── Orden de la cadena: cantidad DESC, id ASC ──────────────────────────
    final cadena = List<_Fila>.from(filas)
      ..sort((a, b) {
        final porCantidad = b.cantidad.compareTo(a.cantidad); // cantidad DESC
        if (porCantidad != 0) return porCantidad;
        return a.id.compareTo(b.id); // id ASC
      });

    final out = <PresentacionLocal>[];
    for (var i = 0; i < cadena.length; i++) {
      final f = cadena[i];
      out.add(PresentacionLocal(
        idPresentacion: f.id,
        idNomPresentacion: f.idNom,
        nombre: f.nombre,
        factor: f.cantidad,
        factorRel: _round6(
          base.cantidad == 0 ? 0 : f.cantidad / base.cantidad,
        ),
        // La base es la que gano la cascada, NO la que trae es_base=true: en un
        // producto con dos filas marcadas (hay 1 en produccion) solo una puede
        // ser la referencia.
        esBase: f.id == base.id,
        skuCodigo: f.sku,
        nivel: i + 1,
      ));
    }
    return out;
  }

  /// Presentacion base de la cadena, o null si no hay cadena.
  static PresentacionLocal? base(List<PresentacionLocal> cadena) {
    for (final p in cadena) {
      if (p.esBase) return p;
    }
    return null;
  }

  /// Equivalente en unidades base de un conjunto de cantidades por presentacion.
  static double equivalenteBase(
    List<PresentacionLocal> cadena,
    Map<int, double> cantidades,
  ) {
    var total = 0.0;
    for (final p in cadena) {
      final c = cantidades[p.idPresentacion];
      if (c != null) total += c * p.factorRel;
    }
    return total;
  }

  /// `round(x, 6)` como el SQL, para que el cliente y el servidor coincidan.
  static double _round6(double v) {
    const f = 1000000.0;
    return (v * f).roundToDouble() / f;
  }

  static int? _asInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString());
  }

  static double? _asDouble(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

class _Fila {
  final int id;
  final int idNom;
  final String nombre;
  final String? sku;
  final double cantidad;
  final bool esBaseMarcada;

  const _Fila({
    required this.id,
    required this.idNom,
    required this.nombre,
    required this.cantidad,
    required this.esBaseMarcada,
    this.sku,
  });
}

/// Formateo de cantidades, identico a `fn_plural_presentacion` /
/// `fn_formatear_stock_mixto` del servidor.
///
/// Gemelo de ventiq_admin_app/lib/utils/stock_mixto_formatter.dart. Se duplica
/// porque las dos apps no comparten paquete; si cambia una, cambiar la otra.
/// Las reglas estan verificadas una por una contra las funciones vivas.
class FormatoPresentacion {
  FormatoPresentacion._();

  /// Pluralizacion cosmetica. Replica `fn_plural_presentacion(text, numeric)`.
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

  /// Replica `fn_fmt_cantidad(numeric)`. null → "0", como el SQL.
  static String cantidad(num? valor) {
    final v = valor ?? 0;
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    s = s.replaceFirst(RegExp(r'\.$'), '');
    return s;
  }

  /// "4 Cajas + 4 Unidades" a partir de la cadena y las cantidades escritas.
  ///
  /// Respeta el orden de la cadena (mayor a menor factor) y omite los ceros,
  /// igual que `fn_formatear_stock_mixto`.
  static String mixto(
    List<PresentacionLocal> cadena,
    Map<int, double> cantidades, {
    String vacio = 'Sin cantidad',
  }) {
    final partes = <String>[];
    for (final p in cadena) {
      final c = cantidades[p.idPresentacion];
      if (c == null || c == 0) continue;
      partes.add('${cantidad(c)} ${plural(p.nombre, c)}');
    }
    if (partes.isEmpty) return vacio;
    return partes.join(' + ');
  }

  /// "1 Caja = 12 Unidades" para el subtitulo de cada campo.
  static String equivalencia(PresentacionLocal p, String nombreBase) {
    if (p.esBase) return 'presentación base';
    return '1 ${p.nombre} = ${cantidad(p.factorRel)} '
        '${plural(nombreBase, p.factorRel)}';
  }

  /// Redondeo defensivo para comparar equivalentes sin arrastrar ruido binario.
  static double redondear(double v, [int decimales = 6]) {
    final f = math.pow(10, decimales);
    return (v * f).roundToDouble() / f;
  }
}
