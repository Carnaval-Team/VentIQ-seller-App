import 'package:supabase_flutter/supabase_flutter.dart';

/// Una presentacion de un producto con las banderas de edicion ya resueltas.
///
/// Viene de la RPC `fn_presentaciones_producto_editable`
/// (presentaciones_inventario/14_presentaciones_editable.sql).
class PresentacionEditable {
  /// `app_dat_producto_presentacion.id`. **Este** es el id que va en los
  /// payloads de inventario, no el del catalogo.
  final int idProductoPresentacion;

  /// `app_nom_presentacion.id`. Solo para el dropdown del catalogo.
  final int idNomPresentacion;

  /// 'Caja', 'Bolsa', 'Unidad', ...
  final String nombre;

  /// 1 = el empaque mas grande de la cadena.
  final int nivel;

  /// `app_dat_producto_presentacion.cantidad`, tal como se guardo. Es lo que hay
  /// que MOSTRAR en el campo.
  final double factor;

  /// Factor relativo a la presentacion base. Es lo que hay que usar para
  /// CALCULAR equivalencias.
  ///
  /// No son lo mismo: el producto 7075 "Cerveza Coronita" tiene la base con
  /// `factor = 24` y `factorRel = 1`. Mostrar `factorRel` en el campo le
  /// cambiaria el dato al usuario.
  final double factorRel;

  final bool esBase;

  /// Aparece en el ledger, en un detalle de operacion o en una conversion.
  final bool tieneMovimientos;

  /// Tiene historial en `app_dat_precio_costo`.
  final bool tienePrecioCosto;

  /// Se puede cambiar `cantidad`, `es_base` o `id_presentacion`.
  ///
  /// false cuando ya hay movimientos: el factor se interpreta al leer, asi que
  /// cambiarlo reinterpretaria todo el historico. Lo impone el trigger
  /// `trg_congelar_factor_presentacion` en la base (SQLSTATE 23001), esto solo
  /// lo anticipa para no dejar al usuario escribir en vano.
  final bool factorEditable;

  /// Se puede borrar la fila.
  ///
  /// Es un candado DISTINTO de [factorEditable]: una presentacion sin
  /// movimientos pero con historial de precio de costo se puede editar y NO se
  /// puede borrar (la FK de `app_dat_precio_costo` es NO ACTION). En produccion
  /// hay 87 asi.
  final bool puedeBorrarse;

  /// Texto listo para mostrar cuando algo esta bloqueado; null si no lo esta.
  ///
  /// Viene del SQL a proposito: tiene que decir lo mismo que el trigger cuando
  /// rechaza, y mantener dos redacciones sincronizadas a mano no funciona.
  final String? motivoBloqueo;

  const PresentacionEditable({
    required this.idProductoPresentacion,
    required this.idNomPresentacion,
    required this.nombre,
    required this.nivel,
    required this.factor,
    required this.factorRel,
    required this.esBase,
    required this.tieneMovimientos,
    required this.tienePrecioCosto,
    required this.factorEditable,
    required this.puedeBorrarse,
    this.motivoBloqueo,
  });

  factory PresentacionEditable.fromJson(Map<String, dynamic> json) {
    return PresentacionEditable(
      idProductoPresentacion: (json['id_producto_presentacion'] as num).toInt(),
      idNomPresentacion: (json['id_nom_presentacion'] as num).toInt(),
      nombre: json['nombre']?.toString() ?? 'Presentación',
      nivel: (json['nivel'] as num?)?.toInt() ?? 0,
      factor: (json['factor'] as num?)?.toDouble() ?? 1.0,
      factorRel: (json['factor_rel'] as num?)?.toDouble() ?? 1.0,
      esBase: json['es_base'] == true,
      tieneMovimientos: json['tiene_movimientos'] == true,
      tienePrecioCosto: json['tiene_precio_costo'] == true,
      // Ojo con el default: si la RPC no contesta, se asume BLOQUEADO. Es la
      // opcion segura — dejar editar por un fallo de red terminaria en un
      // error 23001 al guardar.
      factorEditable: json['factor_editable'] == true,
      puedeBorrarse: json['puede_borrarse'] == true,
      motivoBloqueo: json['motivo_bloqueo']?.toString(),
    );
  }

  /// Etiqueta para el desplegable: "Caja (12)" / "Bolsa (base)".
  String get etiqueta {
    final f = factor == factor.roundToDouble()
        ? factor.toStringAsFixed(0)
        : factor.toString();
    return esBase ? '$nombre (base)' : '$nombre ($f)';
  }
}

/// Consulta que presentaciones de un producto se pueden editar o borrar.
///
/// FASE 2.0 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md).
///
/// El trigger `trg_congelar_factor_presentacion` ya impide en la base cambiar el
/// factor de una presentacion con movimientos, pero lo hace cuando el usuario ya
/// escribio y ya apreto Guardar: ve un error de Postgres por algo que se sabia
/// al abrir la pantalla. Este servicio existe para preguntarlo ANTES.
class PresentacionEditableService {
  static final _supabase = Supabase.instance.client;

  /// Cadena completa del producto, de mayor a menor factor, con las banderas.
  ///
  /// UNA llamada por producto. No iterar llamando a
  /// `fn_presentacion_tiene_movimientos` por presentacion: son N viajes de red
  /// y la RPC ya lo resuelve en una pasada.
  ///
  /// Si algo falla devuelve lista vacia y lo registra; el llamador debe tratar
  /// la lista vacia como "no se pudo saber" y NO como "todo editable".
  static Future<List<PresentacionEditable>> listar(int idProducto) async {
    try {
      final response = await _supabase.rpc(
        'fn_presentaciones_producto_editable',
        params: {'p_id_producto': idProducto},
      );

      if (response == null) return const [];

      return (response as List)
          .whereType<Map<String, dynamic>>()
          .map(PresentacionEditable.fromJson)
          .toList();
    } catch (e) {
      print('❌ fn_presentaciones_producto_editable($idProducto): $e');
      return const [];
    }
  }

  /// Mapa `id_producto_presentacion -> PresentacionEditable`, para que la UI
  /// consulte por id sin recorrer la lista en cada `build`.
  static Future<Map<int, PresentacionEditable>> mapaPorId(
    int idProducto,
  ) async {
    final lista = await listar(idProducto);
    return {for (final p in lista) p.idProductoPresentacion: p};
  }

  /// Traduce el error de Postgres a algo que el usuario entienda.
  ///
  /// Los dos codigos que puede devolver esta ruta:
  ///   23001 restrict_violation -> lo lanza nuestro trigger, y su mensaje ya
  ///         esta escrito para leerse; se devuelve tal cual.
  ///   23503 foreign_key_violation -> la FK de app_dat_precio_costo al borrar.
  ///         El mensaje crudo de Postgres no le dice nada a nadie.
  static String mensajeDeError(Object error) {
    if (error is PostgrestException) {
      if (error.code == '23001') {
        return error.message;
      }
      if (error.code == '23503' &&
          error.message.contains('app_dat_precio_costo')) {
        return 'No se puede borrar esta presentación: tiene historial de precio '
            'de costo registrado. Puede dejar de usarla, pero no eliminarla.';
      }
    }
    return 'No se pudo guardar el cambio: $error';
  }
}
