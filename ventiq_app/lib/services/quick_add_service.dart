import 'package:flutter/foundation.dart';

import '../models/product.dart';
import '../utils/promotion_rules.dart';
import 'elaborated_availability_service.dart';
import 'order_service.dart';
import 'product_detail_service.dart';
import 'promotion_service.dart';
import 'user_preferences_service.dart';

/// Estados posibles del alta rápida desde el listado del Home.
enum QuickAddEstado {
  /// Se puede añadir sin abrir el detalle.
  listo,

  /// El producto no es inequívoco (varias presentaciones/ubicaciones,
  /// promoción, elaborado...): hay que abrir el detalle para elegir.
  requiereDetalle,

  /// Hay una ubicación única pero no queda stock.
  sinStock,
}

/// Promociones que afectan a un producto.
class QuickAddPromociones {
  const QuickAddPromociones({
    this.producto = const <Map<String, dynamic>>[],
    this.global,
  });

  final List<Map<String, dynamic>> producto;
  final Map<String, dynamic>? global;
}

/// Todo lo necesario para añadir una unidad de un producto inequívoco.
///
/// Lo calcula [QuickAddService.decidir] y lo consume la hoja de cantidad.
@immutable
class QuickAddPreparado {
  const QuickAddPreparado({
    required this.producto,
    required this.variante,
    required this.promociones,
    required this.factorPresentacion,
    required this.precioUnitario,
    required this.stockDisponible,
    required this.ubicacion,
    required this.inventoryData,
  });

  final Product producto;

  /// Puede ser `null` en un **elaborado**: su venta consume materia prima, no
  /// una fila de inventario propia.
  final ProductVariant? variante;
  final QuickAddPromociones promociones;

  /// Factor de la presentación (1 = unidad base). El precio unitario que se
  /// manda a la orden ya lo lleva aplicado, igual que el detalle.
  final double factorPresentacion;

  final double precioUnitario;

  /// Cuántas unidades (en la presentación única) hay disponibles.
  final double stockDisponible;

  /// Texto de la ubicación, para mostrarlo y para la orden.
  final String ubicacion;

  /// `inventoryData` con los ids que espera `fn_registrar_venta`.
  final Map<String, dynamic> inventoryData;
}

/// Resultado de evaluar un producto para el alta rápida.
@immutable
class QuickAddEvaluacion {
  const QuickAddEvaluacion({
    required this.estado,
    required this.producto,
    this.preparado,
    this.motivo,
  });

  final QuickAddEstado estado;

  /// Producto completo ya cargado: si hay que abrir el detalle, se abre con
  /// este objeto y no se vuelve a pedir.
  final Product producto;

  final QuickAddPreparado? preparado;

  /// Explicación corta de por qué no se puede añadir directo.
  final String? motivo;
}

/// Resultado de intentar agregar al carrito.
@immutable
class QuickAddResultado {
  const QuickAddResultado._(this.estado, {this.mensaje, this.producto});

  /// Se agregó al carrito.
  factory QuickAddResultado.agregado(Product producto) =>
      QuickAddResultado._(QuickAddEstado.listo, producto: producto);

  /// Hay que abrir el detalle (promoción aparecida con la cantidad final).
  factory QuickAddResultado.detalleRequerido(
    Product producto, {
    String? mensaje,
  }) => QuickAddResultado._(
    QuickAddEstado.requiereDetalle,
    producto: producto,
    mensaje: mensaje,
  );

  final QuickAddEstado estado;
  final String? mensaje;
  final Product? producto;

  bool get agregado => estado == QuickAddEstado.listo;
  bool get requiereDetalle => estado == QuickAddEstado.requiereDetalle;
}

/// Error de negocio del alta rápida (stock, órdenes pendientes...).
class QuickAddException implements Exception {
  QuickAddException(this.mensaje);

  final String mensaje;

  @override
  String toString() => mensaje;
}

/// Alta rápida de productos desde el listado del Home.
///
/// Regla del encargo: si el producto tiene **una sola presentación y una sola
/// ubicación** (y no hay promoción ni nada que elegir), se puede añadir al
/// carrito desde la fila del drawer sin abrir el detalle. Si no, se abre el
/// detalle como siempre.
///
/// El "una sola ubicación" sale de `get_detalle_producto`: esa RPC ya filtra el
/// inventario al almacén del TPV del vendedor y solo devuelve filas con
/// `cantidad_final > 0`. Por eso `variantes.length == 1` significa exactamente
/// "una única combinación presentación/ubicación con stock".
///
/// La lógica de decisión es estática y pura ([decidir]) para poder probarla sin
/// Supabase; las cargas y el alta real son inyectables.
class QuickAddService {
  QuickAddService({
    Future<Product> Function(int idProducto, double? fallbackStock)?
    cargarDetalle,
    Future<QuickAddPromociones> Function(int idProducto)? cargarPromociones,
    Future<double?> Function(int idProducto, int idTpv)? cargarElaborable,
    Future<List<ProductPresentation>> Function(int idProducto)?
    cargarPresentaciones,
    AgregarItemOrden? agregarItem,
    Future<Map<String, dynamic>?> Function()? cargarStoreConfig,
    Future<bool> Function()? hayOrdenesPendientes,
  }) : _cargarDetalle = cargarDetalle ?? _detalleReal,
       _cargarPromociones = cargarPromociones ?? _promocionesReales,
       _cargarElaborable = cargarElaborable ?? _elaborableReal,
       _cargarPresentaciones = cargarPresentaciones ?? _presentacionesReales,
       _agregarItem = agregarItem ?? _agregarReal,
       _cargarStoreConfig =
           cargarStoreConfig ??
           (() => UserPreferencesService().getStoreConfig()),
       _hayOrdenesPendientes = hayOrdenesPendientes ?? _pendientesReales;

  final Future<Product> Function(int idProducto, double? fallbackStock)
  _cargarDetalle;
  final Future<QuickAddPromociones> Function(int idProducto) _cargarPromociones;

  /// Disponibilidad de un elaborado para un TPV (materia prima de su cocina).
  final Future<double?> Function(int idProducto, int idTpv) _cargarElaborable;
  final Future<List<ProductPresentation>> Function(int idProducto)
  _cargarPresentaciones;

  final AgregarItemOrden _agregarItem;
  final Future<Map<String, dynamic>?> Function() _cargarStoreConfig;
  final Future<bool> Function() _hayOrdenesPendientes;

  /// El detalle se reutiliza unos segundos: tocar «+» dos veces en el mismo
  /// producto no debe pagar dos veces la RPC.
  static const Duration _ttlDetalle = Duration(seconds: 60);

  final Map<int, _DetalleCache> _cacheDetalle = <int, _DetalleCache>{};
  final Map<int, QuickAddPromociones> _cachePromos =
      <int, QuickAddPromociones>{};
  final Map<int, List<ProductPresentation>> _cachePresentaciones =
      <int, List<ProductPresentation>>{};

  // ── Evaluación ─────────────────────────────────────────────────────────

  /// Carga los datos del producto y decide si se puede añadir directo.
  ///
  /// [esServicio] / [esElaborado] vienen de la fila del listado
  /// (`metadata.es_servicio` / `metadata.es_elaborado`): `get_detalle_producto`
  /// mezcla ambos flags en `es_elaborado`, y aquí sí hay que distinguirlos.
  ///
  /// [idTpv] permite calcular la **disponibilidad real de un elaborado**
  /// (materia prima de su cocina) con `fn_disponibilidad_plato`. Sin él, un
  /// elaborado se evalúa con el stock propio de siempre.
  Future<QuickAddEvaluacion> evaluar(
    int idProducto, {
    double? fallbackStock,
    bool esServicio = false,
    bool esElaborado = false,
    int? idTpv,
  }) async {
    final Product producto = await _detalle(idProducto, fallbackStock);
    final QuickAddPromociones promos = await _promos(idProducto);

    final bool elaborado = esElaborado || producto.esElaborado;
    double? elaborable;
    List<ProductPresentation>? presentaciones;

    if (elaborado &&
        !esServicio &&
        !producto.esServicio &&
        !producto.esPaquete &&
        idTpv != null) {
      elaborable = await _elaborable(idProducto, idTpv);
      if (elaborable != null) {
        presentaciones = await _presentaciones(idProducto);
      }
    }

    return decidir(
      producto: producto,
      promociones: promos,
      cantidad: 1,
      esServicio: esServicio,
      esElaborado: elaborado,
      elaborable: elaborable,
      presentaciones: presentaciones,
    );
  }

  /// Regla pura. No toca red ni preferencias.
  ///
  /// [elaborable] = cuántas unidades se pueden preparar con la materia prima
  /// (lo devuelve `fn_disponibilidad_plato`). Cuando viene informado, el
  /// elaborado se evalúa **por esa cantidad**, no por su stock propio.
  static QuickAddEvaluacion decidir({
    required Product producto,
    required QuickAddPromociones promociones,
    required double cantidad,
    bool esServicio = false,
    bool esElaborado = false,
    double? elaborable,
    List<ProductPresentation>? presentaciones,
  }) {
    // Servicios y paquetes tienen invariantes propios (no gastan stock,
    // explotan en varios componentes...) y se quedan en el detalle.
    if (esServicio || producto.esServicio || producto.esPaquete) {
      return QuickAddEvaluacion(
        estado: QuickAddEstado.requiereDetalle,
        producto: producto,
        motivo: 'Servicio o paquete: elige en el detalle',
      );
    }

    // Con promoción el precio depende de la cantidad y de reglas que el detalle
    // ya sabe aplicar: mejor no duplicar esa lógica en un alta rápida.
    if (promocionActiva(promociones, cantidad) != null) {
      return QuickAddEvaluacion(
        estado: QuickAddEstado.requiereDetalle,
        producto: producto,
        motivo: 'Tiene una promoción activa',
      );
    }

    final bool elaborado = esElaborado || producto.esElaborado;
    if (elaborado && elaborable != null) {
      return _decidirElaborado(
        producto: producto,
        promociones: promociones,
        elaborable: elaborable,
        presentaciones: presentaciones,
      );
    }

    if (producto.variantes.length != 1) {
      return QuickAddEvaluacion(
        estado: QuickAddEstado.requiereDetalle,
        producto: producto,
        motivo:
            producto.variantes.isEmpty
                ? 'Sin stock en este TPV'
                : 'Tiene varias ubicaciones o variantes',
      );
    }

    if (producto.presentacionesCount > 1) {
      return QuickAddEvaluacion(
        estado: QuickAddEstado.requiereDetalle,
        producto: producto,
        motivo: 'Tiene varias presentaciones',
      );
    }

    final ProductVariant variante = producto.variantes.single;
    final double stock = variante.cantidadReal.toDouble();
    if (stock <= 0) {
      // Sin disponibilidad calculada (offline/sin RPC) un elaborado puede
      // seguir siendo vendible por ingredientes: solo el detalle lo evalúa.
      if (elaborado) {
        return QuickAddEvaluacion(
          estado: QuickAddEstado.requiereDetalle,
          producto: producto,
          motivo: 'Elaborado sin saldo propio: revisa ingredientes',
        );
      }
      return QuickAddEvaluacion(
        estado: QuickAddEstado.sinStock,
        producto: producto,
        motivo: 'Sin stock',
      );
    }

    final Map<String, dynamic>? meta = variante.inventoryMetadata;
    final double factor =
        (meta?['presentacion_factor_rel'] as num?)?.toDouble() ?? 1.0;
    final double precioUnitario = variante.precio * factor;

    return QuickAddEvaluacion(
      estado: QuickAddEstado.listo,
      producto: producto,
      preparado: QuickAddPreparado(
        producto: producto,
        variante: variante,
        promociones: promociones,
        factorPresentacion: factor,
        precioUnitario: precioUnitario,
        stockDisponible: stock,
        ubicacion: ubicacionDe(variante),
        inventoryData: inventoryDataDe(producto, variante, factor),
      ),
    );
  }

  /// Rama de un **elaborado con receta**: vende materia prima, no fila propia.
  ///
  /// - Con más de una presentación se va al detalle (hay que elegir).
  /// - `inventoryData` va sin ubicación a propósito: el servidor enruta al
  ///   almacén de la cocina y resuelve la ubicación; mandar la de la barra
  ///   dejaría la extracción apuntando al sitio equivocado.
  static QuickAddEvaluacion _decidirElaborado({
    required Product producto,
    required QuickAddPromociones promociones,
    required double elaborable,
    List<ProductPresentation>? presentaciones,
  }) {
    if (presentaciones != null && presentaciones.length > 1) {
      return QuickAddEvaluacion(
        estado: QuickAddEstado.requiereDetalle,
        producto: producto,
        motivo: 'Tiene varias presentaciones',
      );
    }

    if (elaborable <= 0) {
      return QuickAddEvaluacion(
        estado: QuickAddEstado.sinStock,
        producto: producto,
        motivo: 'Sin materia prima suficiente para prepararlo',
      );
    }

    final ProductVariant? variante =
        producto.variantes.length == 1 ? producto.variantes.single : null;
    final ProductPresentation? presentacion =
        (presentaciones != null && presentaciones.length == 1)
            ? presentaciones.single
            : null;
    final Map<String, dynamic>? meta = variante?.inventoryMetadata;

    final double factor =
        presentacion?.cantidad ??
        (meta?['presentacion_factor_rel'] as num?)?.toDouble() ??
        1.0;
    final double precioUnitario = producto.precio * factor;

    return QuickAddEvaluacion(
      estado: QuickAddEstado.listo,
      producto: producto,
      preparado: QuickAddPreparado(
        producto: producto,
        variante: variante,
        promociones: promociones,
        factorPresentacion: factor,
        precioUnitario: precioUnitario,
        stockDisponible: elaborable,
        ubicacion: variante != null ? ubicacionDe(variante) : 'Cocina',
        inventoryData: <String, dynamic>{
          'id_producto': producto.id,
          'id_variante': null,
          'id_opcion_variante': null,
          // El servidor resuelve la ubicación dentro del almacén de la cocina.
          'id_ubicacion': null,
          'id_presentacion': presentacion?.id ?? meta?['id_presentacion'],
          'presentacion_nombre':
              presentacion?.presentacion.denominacion ??
              meta?['presentacion_nombre'],
          'presentacion_factor_rel': factor,
          'sku_producto': meta?['sku_producto'] ?? producto.id.toString(),
          'sku_ubicacion': meta?['sku_ubicacion'],
        },
      ),
    );
  }

  /// Promoción que aplica a esa cantidad, si hay alguna.
  static Map<String, dynamic>? promocionActiva(
    QuickAddPromociones promociones,
    double cantidad,
  ) {
    return PromotionRules.pickPromotionForDisplay(
      productPromotions:
          promociones.producto.isEmpty ? null : promociones.producto,
      globalPromotion: promociones.global,
      quantity: cantidad,
    );
  }

  /// Texto de la ubicación de una variante: "Almacén - Ubicación".
  static String ubicacionDe(ProductVariant variante) {
    final Map<String, dynamic>? meta = variante.inventoryMetadata;
    final String? ubicacion = meta?['ubicacion_nombre'] as String?;
    final String? almacen = meta?['almacen_nombre'] as String?;
    if (ubicacion != null &&
        ubicacion.isNotEmpty &&
        almacen != null &&
        almacen.isNotEmpty) {
      return '$almacen - $ubicacion';
    }
    if (ubicacion != null && ubicacion.isNotEmpty) return ubicacion;
    if (almacen != null && almacen.isNotEmpty) return almacen;
    return 'Almacén';
  }

  /// `inventoryData` que espera `fn_registrar_venta`, con la presentación de la
  /// única fila de inventario. Se construye igual que en el detalle.
  static Map<String, dynamic> inventoryDataDe(
    Product producto,
    ProductVariant variante,
    double factor,
  ) {
    final Map<String, dynamic>? meta = variante.inventoryMetadata;
    return <String, dynamic>{
      'id_producto': producto.id,
      'id_variante': meta?['id_variante'],
      'id_opcion_variante': meta?['id_opcion_variante'],
      'id_ubicacion': meta?['id_ubicacion'],
      'id_presentacion': meta?['id_presentacion'],
      'presentacion_nombre': meta?['presentacion_nombre'],
      'presentacion_factor_rel': factor,
      'sku_producto': meta?['sku_producto'] ?? producto.id.toString(),
      'sku_ubicacion': meta?['sku_ubicacion'],
    };
  }

  // ── Alta en el carrito ─────────────────────────────────────────────────

  /// Añade [cantidad] al carrito con los datos del producto pequeño.
  ///
  /// Vuelve a comprobar stock y promoción con la cantidad definitiva: una
  /// promoción "3x2" no aplica con 1 unidad, pero sí con 3.
  Future<QuickAddResultado> agregar(
    QuickAddPreparado preparado,
    double cantidad,
  ) async {
    if (cantidad <= 0) {
      throw QuickAddException('La cantidad debe ser mayor que cero.');
    }

    if (cantidad > preparado.stockDisponible + 1e-9) {
      throw QuickAddException(
        'Solo hay ${_cantidad(preparado.stockDisponible)} disponibles.',
      );
    }

    if (promocionActiva(preparado.promociones, cantidad) != null) {
      return QuickAddResultado._(
        QuickAddEstado.requiereDetalle,
        producto: preparado.producto,
        mensaje: 'Con esa cantidad aplica una promoción. Elige en el detalle.',
      );
    }

    await _verificarConfiguracion();

    await _agregarItem(
      producto: preparado.producto,
      variante: preparado.variante,
      cantidad: cantidad,
      ubicacionAlmacen: preparado.ubicacion,
      inventoryData: preparado.inventoryData,
      precioUnitario: preparado.precioUnitario,
      precioBase: preparado.precioUnitario,
      promotionData: null,
    );

    // El stock acaba de cambiar: la próxima hoja del mismo producto debe releer
    // el detalle en vez de enseñar el saldo de hace un minuto.
    _cacheDetalle.remove(preparado.producto.id);
    _cachePromos.remove(preparado.producto.id);
    _cachePresentaciones.remove(preparado.producto.id);

    return QuickAddResultado._(
      QuickAddEstado.listo,
      producto: preparado.producto,
    );
  }

  /// Misma guarda que el detalle: si la tienda exige terminar las órdenes
  /// pendientes antes de vender, el alta rápida no puede saltársela.
  Future<void> _verificarConfiguracion() async {
    try {
      final Map<String, dynamic>? config = await _cargarStoreConfig();
      if (config != null &&
          config['need_all_orders_completed_to_continue'] == true &&
          await _hayOrdenesPendientes()) {
        throw QuickAddException(
          'Hay órdenes pendientes. Termínalas antes de seguir vendiendo.',
        );
      }
    } on QuickAddException {
      rethrow;
    } catch (e) {
      // Sin configuración (offline/legacy) se sigue vendiendo: la guarda es una
      // regla de la tienda, no un requisito técnico.
      debugPrint('⚠️ Alta rápida sin guarda de configuración: $e');
    }
  }

  // ── Cargas reales ──────────────────────────────────────────────────────

  Future<Product> _detalle(int idProducto, double? fallbackStock) async {
    final _DetalleCache? cache = _cacheDetalle[idProducto];
    if (cache != null && cache.vigente) return cache.producto;

    final Product producto = await _cargarDetalle(idProducto, fallbackStock);
    _cacheDetalle[idProducto] = _DetalleCache(producto);
    return producto;
  }

  Future<QuickAddPromociones> _promos(int idProducto) async {
    final QuickAddPromociones? cache = _cachePromos[idProducto];
    if (cache != null) return cache;

    final QuickAddPromociones promos = await _cargarPromociones(idProducto);
    _cachePromos[idProducto] = promos;
    return promos;
  }

  /// Disponibilidad de un elaborado. Un fallo no bloquea: se evalúa como antes.
  Future<double?> _elaborable(int idProducto, int idTpv) async {
    try {
      return await _cargarElaborable(idProducto, idTpv);
    } catch (e) {
      debugPrint(
        '⚠️ No se pudo calcular la disponibilidad del elaborado $idProducto: $e',
      );
      return null;
    }
  }

  Future<List<ProductPresentation>> _presentaciones(int idProducto) async {
    final List<ProductPresentation>? cache = _cachePresentaciones[idProducto];
    if (cache != null) return cache;

    final List<ProductPresentation> presentaciones =
        await _cargarPresentaciones(idProducto);
    _cachePresentaciones[idProducto] = presentaciones;
    return presentaciones;
  }

  static Future<double?> _elaborableReal(int idProducto, int idTpv) {
    return ElaboratedAvailabilityService().disponible(
      idProducto: idProducto,
      idTpv: idTpv,
    );
  }

  static Future<List<ProductPresentation>> _presentacionesReales(
    int idProducto,
  ) {
    return ProductDetailService().getProductPresentations(idProducto);
  }

  static Future<Product> _detalleReal(int idProducto, double? fallbackStock) {
    return ProductDetailService().getProductDetail(
      idProducto,
      fallbackStock: fallbackStock,
    );
  }

  static Future<QuickAddPromociones> _promocionesReales(int idProducto) async {
    final UserPreferencesService prefs = UserPreferencesService();

    // Offline: lo cacheado. Si no hay caché, se asume "sin promoción" para no
    // bloquear la venta; el detalle hace lo mismo con sus promociones.
    if (await prefs.shouldUseLocalData()) {
      return QuickAddPromociones(
        producto:
            await prefs.getProductPromotions(idProducto) ??
            const <Map<String, dynamic>>[],
        global: await prefs.getPromotionData(),
      );
    }

    final int? idTienda = await prefs.getIdTienda();
    final Map<String, dynamic>? global =
        idTienda == null
            ? null
            : await PromotionService().getGlobalPromotion(idTienda);
    final List<Map<String, dynamic>> producto = await PromotionService()
        .getProductPromotions(idProducto);

    if (producto.isNotEmpty) {
      await prefs.saveProductPromotions(idProducto, producto);
    }

    return QuickAddPromociones(producto: producto, global: global);
  }

  static Future<void> _agregarReal({
    required Product producto,
    required ProductVariant? variante,
    required double cantidad,
    required String ubicacionAlmacen,
    required Map<String, dynamic> inventoryData,
    required double precioUnitario,
    required double precioBase,
    Map<String, dynamic>? promotionData,
  }) {
    return OrderService()
        .addItemToCurrentOrder(
          producto: producto,
          variante: variante,
          cantidad: cantidad,
          ubicacionAlmacen: ubicacionAlmacen,
          inventoryData: inventoryData,
          precioUnitario: precioUnitario,
          precioBase: precioBase,
          promotionData: promotionData,
        )
        .then((_) {
          // El stock cambió: que el próximo detalle no salga de la caché de 60 s.
          ProductDetailService().invalidarDetalle(producto.id);
        });
  }

  static Future<bool> _pendientesReales() async {
    // Mismo criterio que el detalle (`_addToCart`): estado index 1.
    return OrderService().orders.any((order) => order.status.index == 1);
  }

  static String _cantidad(double valor) =>
      valor == valor.roundToDouble()
          ? valor.toStringAsFixed(0)
          : valor.toStringAsFixed(2);
}

/// Firma del alta en la orden, para poder inyectar un doble en tests.
typedef AgregarItemOrden =
    Future<void> Function({
      required Product producto,
      required ProductVariant? variante,
      required double cantidad,
      required String ubicacionAlmacen,
      required Map<String, dynamic> inventoryData,
      required double precioUnitario,
      required double precioBase,
      Map<String, dynamic>? promotionData,
    });

class _DetalleCache {
  _DetalleCache(this.producto) : _momento = DateTime.now();

  final Product producto;
  final DateTime _momento;

  bool get vigente =>
      DateTime.now().difference(_momento) < QuickAddService._ttlDetalle;
}
