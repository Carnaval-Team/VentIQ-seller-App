import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/home_catalog_service.dart';
import 'package:inventtia_flow/services/promocion_service.dart';

/// La regla que evita el descuadre que motivó este paso: el precio que se
/// **muestra** y el que se **cobra** salen de la misma función del servidor.
///
/// En Dart solo queda el cálculo *de referencia* de la tarjeta del Home, que se
/// hace sobre el precio base porque ahí no se conocen las opciones que elegirá
/// el cliente. Estas pruebas fijan ese contrato y, sobre todo, que **sin
/// promoción no se invente un descuento**.
void main() {
  const categoria = HomeCatalogCategory(
    id: 1,
    codigo: 'general',
    nombre: 'General',
  );

  Promocion promo({
    required String tipo,
    required double valor,
    String? moneda,
    int? cupoTotal,
    int cupoUsado = 0,
    int? cuposRestantes,
  }) => Promocion(
    id: 1,
    titulo: 'Promo',
    tipo: tipo,
    valor: valor,
    moneda: moneda,
    cupoTotal: cupoTotal,
    cupoUsado: cupoUsado,
    cuposRestantes: cuposRestantes,
  );

  HomeCatalogItem item({double? price, Promocion? promocion}) =>
      HomeCatalogItem(
        id: 1,
        title: 'Servicio',
        venue: 'Local',
        category: categoria,
        price: price,
        currency: 'USD',
        promocion: promocion,
      );

  group('descuento porcentual', () {
    test('calcula el precio rebajado sobre el precio base', () {
      final i = item(
        price: 100,
        promocion: promo(tipo: 'porcentaje', valor: 20),
      );
      expect(i.tieneDescuento, isTrue);
      expect(i.precioConPromocion, 80);
    });

    test('un porcentaje parcial no redondea a entero por accidente', () {
      final i = item(
        price: 60,
        promocion: promo(tipo: 'porcentaje', valor: 15),
      );
      expect(i.precioConPromocion, closeTo(51, 0.001));
    });
  });

  group('descuento de monto', () {
    test('resta el monto indicado', () {
      final i = item(
        price: 50,
        promocion: promo(tipo: 'monto', valor: 5, moneda: 'USD'),
      );
      expect(i.precioConPromocion, 45);
    });

    test('no deja el precio en negativo si el monto supera el precio', () {
      // Un descuento de 80 sobre un precio de 50 no puede cobrar -30.
      final i = item(
        price: 50,
        promocion: promo(tipo: 'monto', valor: 80, moneda: 'USD'),
      );
      expect(i.precioConPromocion, 0);
      expect(i.tieneDescuento, isTrue);
    });
  });

  group('sin promoción no se inventa descuento', () {
    test('sin promo no hay descuento aunque haya precio', () {
      final i = item(price: 100);
      expect(i.tieneDescuento, isFalse);
      expect(i.precioConPromocion, isNull);
    });

    test('con promo pero sin precio configurado no hay descuento', () {
      // Caso real: servicios con `config_precio = '{}'`.
      final i = item(promocion: promo(tipo: 'porcentaje', valor: 20));
      expect(i.tieneDescuento, isFalse);
      expect(i.precioConPromocion, isNull);
    });

    test('un porcentaje de 0 no cuenta como descuento', () {
      final i = item(
        price: 100,
        promocion: promo(tipo: 'porcentaje', valor: 0),
      );
      // `valor > 0` lo exige el CHECK de la tabla, pero por si acaso: 0 no
      // debe pintar un tachado.
      expect(i.tieneDescuento, isFalse);
    });
  });

  group('Promocion.etiquetaDescuento', () {
    test('porcentaje sin decimales', () {
      expect(promo(tipo: 'porcentaje', valor: 20).etiquetaDescuento, '-20 %');
    });

    test('monto incluye la moneda', () {
      expect(
        promo(tipo: 'monto', valor: 5, moneda: 'USD').etiquetaDescuento,
        '-5 USD',
      );
    });

    test('conserva decimales cuando el valor los tiene', () {
      expect(
        promo(tipo: 'porcentaje', valor: 12.5).etiquetaDescuento,
        '-12.50 %',
      );
    });
  });

  group('CotizacionReserva', () {
    test('detecta que hay descuento real', () {
      final c = CotizacionReserva.fromJson({
        'ok': true,
        'precio_lista': 100,
        'precio_total': 80,
        'descuento': 20,
        'moneda': 'USD',
        'precio_unit': 80,
        'id_promocion': 3,
        'promo_titulo': 'Verano',
      });
      expect(c.tieneDescuento, isTrue);
      expect(c.precioLista, 100);
      expect(c.precioTotal, 80);
      expect(c.promoTitulo, 'Verano');
    });

    test('ok:false se trata como vacío, no como precio 0 cobrable', () {
      final c = CotizacionReserva.fromJson({
        'ok': false,
        'error': 'Sesion no valida',
      });
      expect(c.hayPrecio, isFalse);
      expect(c.tieneDescuento, isFalse);
    });

    test('null se trata como vacío', () {
      expect(CotizacionReserva.fromJson(null).hayPrecio, isFalse);
    });

    test('un descuento de 0 no se considera descuento', () {
      // Blindaje: sin esto, la UI pintaría un precio tachado idéntico al total.
      final c = CotizacionReserva.fromJson({
        'ok': true,
        'precio_lista': 50,
        'precio_total': 50,
        'descuento': 0,
        'moneda': 'USD',
        'precio_unit': 50,
      });
      expect(c.tieneDescuento, isFalse);
    });
  });

  group('Promocion.fromJson', () {
    test('lee la fila de promociones_por_servicio', () {
      final p = Promocion.fromJson({
        'id_local_servicio': 12,
        'id': 4,
        'titulo': 'Black Friday',
        'tipo': 'porcentaje',
        'valor': 25,
        'moneda': null,
        'hasta': '2026-12-01T23:59:59',
        'cupos_restantes': 3,
      });
      expect(p.id, 4);
      expect(p.titulo, 'Black Friday');
      expect(p.cuposRestantes, 3);
      expect(p.tieneCupo, isFalse);
      expect(p.esPorcentaje, isTrue);
      expect(p.hasta, DateTime(2026, 12, 1, 23, 59, 59));
    });

    test('tolera campos ausentes', () {
      final p = Promocion.fromJson({'id': 1});
      expect(p.titulo, 'Promoción');
      expect(p.tipo, 'porcentaje');
      expect(p.valor, 0);
      expect(p.cuposRestantes, isNull);
    });
  });
}
