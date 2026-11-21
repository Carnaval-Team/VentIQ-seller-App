import '../models/order.dart';
import '../services/store_config_service.dart';
import 'receipt_options.dart';

/// Tickets que puede imprimir una venta, en el orden en que salen.
enum TicketTipo {
  /// Factura del cliente. En `tickets_a_imprimir` es `cliente`.
  factura('cliente'),

  /// Guía de almacén. En `tickets_a_imprimir` es `almacen`.
  almacen('almacen'),

  /// Recibo de caja (copia del vendedor). En `tickets_a_imprimir` es `caja`.
  caja('caja');

  const TicketTipo(this.clave);

  /// Valor guardado en `app_dat_configuracion_tienda.tickets_a_imprimir`.
  final String clave;
}

/// Qué tickets imprimir para una venta según la configuración de la tienda
/// (`tickets_a_imprimir`, que gestiona el admin).
///
/// - Sin configuración (caché vacío, columna ausente o con otro tipo): los tres,
///   como siempre se imprimió.
/// - Lista vacía: ninguno. Es lo que el admin avisa al desmarcar todo
///   («No se imprimirá ningún ticket»).
/// - La guía de almacén solo sale si la tienda no está en modo restaurante o la
///   orden no es de mesa (`ReceiptOptions.includeWarehouseSlip`), aunque la
///   configuración la pida.
///
/// La configuración llega al TPV con `select('*')` + `syncStoreConfig` (caché
/// `store_config`), así que también funciona sin conexión.
class TicketPlan {
  const TicketPlan(this.secuencia);

  /// Tickets a imprimir, en orden.
  final List<TicketTipo> secuencia;

  bool get vacio => secuencia.isEmpty;

  bool incluye(TicketTipo tipo) => secuencia.contains(tipo);

  /// Todos los tickets, para cuando no hay configuración.
  static const List<String> clavesPorDefecto = ['cliente', 'almacen', 'caja'];

  static TicketPlan desdeConfig(
    Map<String, dynamic>? config, {
    required bool incluyeAlmacen,
  }) {
    final raw = config?['tickets_a_imprimir'];
    final claves =
        raw is List
            ? raw.map((e) => e.toString()).toSet()
            : clavesPorDefecto.toSet();
    return TicketPlan([
      for (final tipo in TicketTipo.values)
        if (claves.contains(tipo.clave) &&
            (tipo != TicketTipo.almacen || incluyeAlmacen))
          tipo,
    ]);
  }

  /// Plan de [order] con la configuración de la tienda de la sesión (online, o
  /// caché sin conexión). Si no se puede leer, imprime los tres.
  static Future<TicketPlan> cargar(
    Order order, {
    Map<String, dynamic>? config,
  }) async {
    Map<String, dynamic>? cfg = config;
    if (cfg == null) {
      try {
        cfg = await StoreConfigService.getStoreConfigForSession();
      } catch (_) {
        cfg = null;
      }
    }
    final options = ReceiptOptions(
      order,
      restaurantMode: StoreConfigService.modoRestauranteSync,
    );
    return desdeConfig(cfg, incluyeAlmacen: options.includeWarehouseSlip);
  }
}
