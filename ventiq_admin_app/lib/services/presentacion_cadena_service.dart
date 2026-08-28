import 'package:supabase_flutter/supabase_flutter.dart';

/// Un eslabon de la cadena de presentaciones de un producto.
///
/// Viene de la RPC `fn_presentaciones_producto`, que es la unica fuente
/// autorizada del orden y de los factores (aguanta los productos sin `es_base`,
/// los que tienen la base con factor distinto de 1, y las cadenas de 3+
/// niveles). No reimplementar este orden en Dart.
class PresentacionCadena {
  /// `app_dat_producto_presentacion.id`. Es el id que viaja en los payloads de
  /// inventario. NO es el id del catalogo.
  final int idPresentacion;

  /// `app_nom_presentacion.id`, solo para el catalogo.
  final int idNomPresentacion;

  /// 'Caja', 'Bolsa', 'Unidad', ...
  final String nombre;

  /// `app_dat_producto_presentacion.cantidad` tal como se guardo.
  final double factor;

  /// Factor relativo a la presentacion base. **Este** es el que sirve para
  /// calcular equivalencias.
  ///
  /// No es lo mismo que [factor]: hay 131 filas en produccion cuya presentacion
  /// base tiene `cantidad` 12 o 24, y ahi `factor = 24` pero `factorRel = 1`.
  final double factorRel;

  final bool esBase;
  final bool esFraccionable;

  /// 1 = el empaque mas grande de la cadena.
  final int nivel;

  const PresentacionCadena({
    required this.idPresentacion,
    required this.idNomPresentacion,
    required this.nombre,
    required this.factor,
    required this.factorRel,
    required this.esBase,
    required this.esFraccionable,
    required this.nivel,
  });

  factory PresentacionCadena.fromJson(Map<String, dynamic> json) {
    return PresentacionCadena(
      idPresentacion: (json['id_presentacion'] as num).toInt(),
      idNomPresentacion: (json['id_nom_presentacion'] as num?)?.toInt() ?? 0,
      nombre: json['nombre']?.toString() ?? 'Presentación',
      factor: (json['factor'] as num?)?.toDouble() ?? 1.0,
      factorRel: (json['factor_rel'] as num?)?.toDouble() ?? 1.0,
      esBase: json['es_base'] == true,
      esFraccionable: json['es_fraccionable'] == true,
      nivel: (json['nivel'] as num?)?.toInt() ?? 0,
    );
  }

  /// Mapa con la forma que esperan `PresentationConverter` y los payloads de las
  /// RPC de recepcion/extraccion.
  Map<String, dynamic> toPresentationMap() => {
        'id': idPresentacion,
        'id_presentacion': idNomPresentacion,
        'denominacion': nombre,
        'cantidad': factor,
        'es_base': esBase,
      };
}

/// Saldo de un producto expresado por presentacion.
///
/// Viene de `fn_stock_mixto_json`. El texto lo arma el SQL (`fn_formatear_stock_mixto`)
/// para que diga lo mismo en la app, en los reportes y en el kardex.
class StockMixto {
  /// '4 Cajas + 4 Unidades'. Vacio si no hay stock.
  final String texto;

  /// '4 CJ + 4 U', para celdas angostas.
  final String textoCorto;

  /// Total en unidades de la presentacion base.
  final double equivalenteBase;

  /// Una entrada por presentacion con saldo.
  final List<Map<String, dynamic>> desglose;

  const StockMixto({
    required this.texto,
    required this.textoCorto,
    required this.equivalenteBase,
    required this.desglose,
  });

  static const vacio = StockMixto(
    texto: 'Sin stock',
    textoCorto: '—',
    equivalenteBase: 0,
    desglose: [],
  );

  factory StockMixto.fromJson(Map<String, dynamic> json) {
    return StockMixto(
      texto: json['texto']?.toString() ?? 'Sin stock',
      textoCorto: json['texto_corto']?.toString() ?? '—',
      equivalenteBase: (json['equivalente_base'] as num?)?.toDouble() ?? 0.0,
      desglose: (json['desglose'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .toList() ??
          const [],
    );
  }

  /// Saldo propio de una presentacion concreta (sin convertir nada).
  double saldoDe(int idPresentacion) {
    for (final d in desglose) {
      if ((d['id_presentacion'] as num?)?.toInt() == idPresentacion) {
        return (d['cantidad'] as num?)?.toDouble() ?? 0.0;
      }
    }
    return 0.0;
  }
}

/// Lee la cadena de presentaciones y el stock mixto de un producto.
///
/// FASE 2 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md). Existe
/// para que la UI deje de adivinar factores y de tratar cada presentacion como
/// un SKU aparte.
class PresentacionCadenaService {
  static final _supabase = Supabase.instance.client;

  /// Cache por producto: la cadena no cambia mientras el usuario llena un
  /// formulario, y el dialogo la pide en cada rebuild.
  static final Map<int, List<PresentacionCadena>> _cache = {};

  /// Cadena completa, de mayor a menor factor.
  ///
  /// Devuelve lista vacia si el producto no tiene presentaciones o si la RPC
  /// falla. El llamador debe tratar la lista vacia como "no hay cadena
  /// conocida" y caer al comportamiento de una sola cantidad.
  static Future<List<PresentacionCadena>> cadena(
    int idProducto, {
    bool forzarRecarga = false,
  }) async {
    if (!forzarRecarga && _cache.containsKey(idProducto)) {
      return _cache[idProducto]!;
    }

    try {
      final response = await _supabase.rpc(
        'fn_presentaciones_producto',
        params: {'p_id_producto': idProducto},
      );

      if (response == null) return const [];

      final lista = (response as List)
          .whereType<Map<String, dynamic>>()
          .map(PresentacionCadena.fromJson)
          .toList();

      _cache[idProducto] = lista;
      return lista;
    } catch (e) {
      print('❌ fn_presentaciones_producto($idProducto): $e');
      return const [];
    }
  }

  /// Saldo mixto del producto, filtrable por almacen y/o ubicacion.
  ///
  /// OJO con la firma real de la RPC: es
  /// `fn_stock_mixto_json(p_id_producto, p_id_almacen, p_id_ubicacion)`.
  /// **No** hay parametro de variante — verificado contra produccion. Si algun
  /// dia hace falta filtrar por variante hay que cambiar la funcion SQL, no
  /// pasarle el id de variante en la posicion del almacen.
  static Future<StockMixto> stockMixto(
    int idProducto, {
    int? idAlmacen,
    int? idUbicacion,
  }) async {
    try {
      final response = await _supabase.rpc(
        'fn_stock_mixto_json',
        params: {
          'p_id_producto': idProducto,
          'p_id_almacen': idAlmacen,
          'p_id_ubicacion': idUbicacion,
        },
      );

      if (response is Map<String, dynamic>) {
        return StockMixto.fromJson(response);
      }
      return StockMixto.vacio;
    } catch (e) {
      print('❌ fn_stock_mixto_json($idProducto): $e');
      return StockMixto.vacio;
    }
  }

  static void limpiarCache([int? idProducto]) {
    if (idProducto == null) {
      _cache.clear();
    } else {
      _cache.remove(idProducto);
    }
  }
}
