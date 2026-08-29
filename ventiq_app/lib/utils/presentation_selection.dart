/// Resolucion de la presentacion de inventario en el cliente vendedor.
///
/// FASE 1 de presentaciones (docs/PLAN_PRESENTACIONES_INVENTARIO.md).
///
/// Antes cada pantalla admin (extraccion, transferencia, ajuste, venta por
/// acuerdo) repetia este bloque para forzar la presentacion base:
///
///     final base = presentaciones.cast<Map>().firstWhere(
///           (x) => x['es_base'] == true,
///           orElse: () => presentaciones.first as Map,
///         );
///     presentationId = (base['id'] as num?)?.toInt();
///
/// Tiene dos fallos comprobados contra produccion:
///
///  1. `orElse: presentaciones.first` elige la PRIMERA fila cuando el producto
///     no tiene ninguna marcada `es_base`. Hay 9 productos asi, y el orden de
///     `presentaciones` no esta garantizado: puede caer la Caja y entonces una
///     extraccion de 3 unidades se registra como 3 CAJAS.
///  2. Fuerza la base incluso cuando el usuario tenia otra presentacion en
///     mente, que es justo lo que la Fase 1 elimina.
///
/// La resolucion correcta vive en el SQL: `fn_presentaciones_producto` ordena la
/// cadena y resuelve la base con una cascada (es_base de menor id; si no hay,
/// la presentacion de menor factor). Todas las RPC de la Fase 1
/// (`fn_registrar_recepcion_con_inventario`, `fn_crear_extraccion_con_movimiento`,
/// `fn_insertar_ajuste_inventario2`) usan esa cascada cuando `id_presentacion`
/// llega en null.
///
/// Por eso aqui NO se adivina: se devuelve null y decide el servidor. Cuando la
/// Fase 2 agregue el selector de presentacion en la UI, esa pantalla pasara el
/// id elegido y este helper dejara de hacer falta en ese flujo.
class PresentationSelection {
  /// Presentacion a enviar en el payload de inventario.
  ///
  /// Devuelve null a proposito: la RPC resuelve la base del producto con la
  /// cascada correcta. Nunca inventar un id (el viejo `?? 1` de la pantalla de
  /// venta por acuerdo apuntaba a la presentacion de OTRO producto, y ahora la
  /// validacion del servidor lo rechaza con un error explicito).
  static int? forInventoryPayload() => null;

  /// Nombre de la presentacion base segun el cache local, SOLO para mostrar.
  ///
  /// Sirve para etiquetar cantidades en pantalla mientras la Fase 2 no trae el
  /// desglose mixto. No usar para armar payloads.
  static String? baseNameForDisplay(Map<String, dynamic>? detallesCompletos) {
    if (detallesCompletos == null) return null;

    final presentaciones = detallesCompletos['presentaciones'];
    if (presentaciones is! List || presentaciones.isEmpty) return null;

    final base = presentaciones.cast<Map?>().firstWhere(
      (x) => x?['es_base'] == true,
      orElse: () => null,
    );
    if (base == null) return null;

    final pres = base['presentacion'];
    if (pres is Map && pres['denominacion'] != null) {
      return pres['denominacion'].toString();
    }
    return base['denominacion']?.toString();
  }
}
