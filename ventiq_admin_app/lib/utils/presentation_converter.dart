import '../services/product_service.dart';

/// Prepara las lineas de producto para las RPC de recepcion y extraccion.
///
/// FASE 1 de presentaciones (ver docs/PLAN_PRESENTACIONES_INVENTARIO.md):
/// esta clase YA NO CONVIERTE la cantidad a la presentacion base.
///
/// Antes hacia esto antes de guardar:
///
///     cantidad        = cantidad * factor_de_la_presentacion
///     id_presentacion = id de la presentacion base
///
/// o sea que "4 cajas de 12" llegaba al inventario como "48 unidades" y el
/// empaque fisico se perdia para siempre. Ahora la presentacion elegida y su
/// cantidad viajan tal cual: el SQL escribe 4 en la fila de Caja.
///
/// Quien resuelve el resto:
///   - si la linea no trae presentacion, la RPC resuelve la base con la cascada
///     de fn_presentaciones_producto (que aguanta los productos sin es_base);
///   - si en un egreso falta saldo de la presentacion pedida,
///     fn_descontar_con_rebalanceo abre cajas o empaqueta sueltas.
///
/// Se conservan las claves de metadatos que ya consumen las pantallas
/// (`conversion_applied`, `cantidad_original`, `presentacion_original_info`,
/// `presentation_info`) para no romper conversion_info_widget.dart ni
/// inventory_reception_screen.dart. `conversion_applied` ahora es siempre false,
/// asi que el aviso naranja de "Conversiones Aplicadas" simplemente no aparece.
class PresentationConverter {
  /// Normaliza la denominacion de una presentacion venida de cualquier pantalla.
  ///
  /// Las distintas UI mandan el nombre en `denominacion`, `presentacion`,
  /// `nombre` o `tipo` segun de donde salga el mapa.
  static Map<String, dynamic>? _normalizePresentation(
    Map<String, dynamic>? selectedPresentation,
  ) {
    if (selectedPresentation == null) return null;

    final normalized = Map<String, dynamic>.from(selectedPresentation);
    normalized['denominacion'] ??=
        normalized['presentacion'] ??
        normalized['nombre'] ??
        normalized['tipo'] ??
        'Presentación';
    return normalized;
  }

  /// Arma la linea de recepcion en la presentacion elegida, sin convertir.
  ///
  /// `precioUnitario` se interpreta como precio de UNA unidad de la
  /// presentacion de esta linea (el precio de una caja, si la linea es en
  /// cajas). La conversion a costo base la hace el SQL al ponderar el
  /// precio_promedio; ver el contrato en el plan.
  static Future<Map<String, dynamic>> processProductForReception({
    required String productId,
    required Map<String, dynamic>? selectedPresentation,
    required double cantidad,
    required double precioUnitario,
    required Map<String, dynamic> baseProductData,
  }) async {
    final normalizedPresentation = _normalizePresentation(selectedPresentation);

    // Si la pantalla no eligio presentacion, se manda null a proposito: la RPC
    // resuelve la base del producto. Antes se adivinaba aqui con una consulta
    // extra y se elegia mal en los productos sin fila es_base.
    final int? idPresentacion = normalizedPresentation?['id'] as int?;

    print('📦 Recepción producto $productId: $cantidad '
        '${normalizedPresentation?['denominacion'] ?? 'presentación base'} '
        '(id_presentacion: ${idPresentacion ?? 'null → base'}) '
        'precio ${precioUnitario.toStringAsFixed(2)} — sin conversión');

    final processedData = Map<String, dynamic>.from(baseProductData);
    processedData.addAll({
      'cantidad': cantidad,
      'precio_unitario': precioUnitario,
      'id_presentacion': idPresentacion,

      // Metadatos que ya consumen las pantallas. Se mantienen por
      // compatibilidad; conversion_applied es false porque ya no convertimos.
      'cantidad_original': cantidad,
      'presentacion_original': idPresentacion,
      'precio_original': precioUnitario,
      'conversion_applied': false,
      'presentacion_original_info': normalizedPresentation,
      'presentation_info': normalizedPresentation,
    });

    return processedData;
  }

  /// Arma la linea de extraccion en la presentacion elegida, sin convertir.
  ///
  /// Si el saldo de esa presentacion no alcanza, NO se convierte aqui: lo
  /// resuelve fn_descontar_con_rebalanceo en el SQL, que abre el empaque mayor
  /// y deja constancia de la conversion en el kardex.
  static Future<Map<String, dynamic>> processProductForExtraction({
    required String productId,
    required Map<String, dynamic>? selectedPresentation,
    required double cantidad,
    required Map<String, dynamic> baseProductData,
  }) async {
    final normalizedPresentation = _normalizePresentation(selectedPresentation);
    final int? idPresentacion = normalizedPresentation?['id'] as int?;

    print('📤 Extracción producto $productId: $cantidad '
        '${normalizedPresentation?['denominacion'] ?? 'presentación base'} '
        '(id_presentacion: ${idPresentacion ?? 'null → base'}) — sin conversión');

    final processedData = Map<String, dynamic>.from(baseProductData);
    processedData.addAll({
      'cantidad': cantidad,
      'id_presentacion': idPresentacion,
      'cantidad_original': cantidad,
      'presentacion_original': idPresentacion,
      'conversion_applied': false,
      'presentacion_original_info': normalizedPresentation,
      'presentation_info': normalizedPresentation,
    });

    return processedData;
  }

  /// Presentacion base de un producto, solo para MOSTRAR equivalencias.
  ///
  /// No usar para armar payloads de escritura: la presentacion que se guarda es
  /// la que eligio el usuario. Sirve para textos tipo "1 Caja = 12 Unidades".
  static Future<Map<String, dynamic>?> basePresentationForDisplay(
    int productId,
  ) => ProductService.getBasePresentacion(productId);
}
