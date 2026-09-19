import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/carnaval_provider_dashboard_data.dart';

void main() {
  group('CarnavalProviderDashboardData', () {
    test('parses the complete RPC response', () {
      final data = CarnavalProviderDashboardData.fromJson({
        'id_proveedor_carnaval': 42,
        'desde': '2026-09-01',
        'hasta': '2026-09-17',
        'resumen': {
          'ordenes_count': 3,
          'ordenes_completadas': 2,
          'productos_vendidos': 7.5,
          'monto_total': 1250.75,
          'ticket_promedio': 416.92,
        },
        'por_estado': [
          {'status': 'Completado', 'count': 2},
        ],
        'por_metodo_pago': [
          {'metodo_pago': 'Efectivo', 'ordenes_count': 3, 'monto': 1250.75},
        ],
        'evolucion_diaria': [
          {
            'fecha': '2026-09-17',
            'ordenes_count': 3,
            'productos_vendidos': 7.5,
            'monto': 1250.75,
          },
        ],
        'top_productos': [
          {'id': 9, 'nombre': 'Producto', 'cantidad': 7.5, 'monto': 1250.75},
        ],
      });

      expect(data.hasError, isFalse);
      expect(data.idProveedorCarnaval, 42);
      expect(data.desde, DateTime(2026, 9, 1));
      expect(data.hasta, DateTime(2026, 9, 17));
      expect(data.resumen.ordenesCount, 3);
      expect(data.resumen.montoTotal, 1250.75);
      expect(data.porEstado.single.status, 'Completado');
      expect(data.porMetodoPago.single.metodoPago, 'Efectivo');
      expect(data.evolucionDiaria.single.fecha, '2026-09-17');
      expect(data.topProductos.single.nombre, 'Producto');
    });

    test('returns safe defaults for an error response', () {
      final data = CarnavalProviderDashboardData.fromJson({
        'error': 'Tienda no sincronizada con Carnaval App',
      });

      expect(data.hasError, isTrue);
      expect(data.error, 'Tienda no sincronizada con Carnaval App');
      expect(data.resumen.ordenesCount, 0);
      expect(data.porEstado, isEmpty);
      expect(data.porMetodoPago, isEmpty);
      expect(data.evolucionDiaria, isEmpty);
      expect(data.topProductos, isEmpty);
    });
  });
}
