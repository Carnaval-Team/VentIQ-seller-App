// Rieles del Home: mapeo puro de las RPC nuevas y caché offline, sin Supabase.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ventiq_app/services/home_extras_service.dart';

void main() {
  test('mapea las filas de fn_top_productos_tpv', () {
    final List<HomeRielProducto> riel = HomeExtrasService.mapearRespuesta(
      <dynamic>[
        <String, dynamic>{
          'id_producto': 10800,
          'denominacion': 'tacos',
          'imagen': null,
          'precio_venta': 12.5,
          'precio_descuento': null,
          'unidades_vendidas': 7,
          'operaciones': 3,
          'total_vendido': 87.5,
        },
      ],
    );

    expect(riel, hasLength(1));
    expect(riel.single.id, 10800);
    expect(riel.single.nombre, 'tacos');
    expect(riel.single.precio, 12.5);
    expect(riel.single.precioOferta, isNull);
    expect(riel.single.unidadesVendidas, 7);
  });

  test('mapea ofertas y detecta el descuento', () {
    final List<HomeRielProducto> riel = HomeExtrasService.mapearRespuesta(
      <dynamic>[
        <String, dynamic>{
          'id_producto': 3851,
          'denominacion': 'Producto con oferta',
          'imagen': 'https://ejemplo/img.png',
          'precio_venta': 5350,
          'precio_descuento': 4800,
          'porcentaje': 10.28,
          'categoria_nombre': 'Alimentos',
        },
      ],
    );

    expect(riel.single.tieneOferta, isTrue);
    expect(riel.single.precioOferta, 4800);
    expect(riel.single.porcentajeDescuento, closeTo(10.28, 0.001));
    expect(riel.single.categoria, 'Alimentos');
  });

  test('descarta filas sin id/nombre y respuestas que no son lista', () {
    expect(HomeExtrasService.mapearRespuesta(null), isEmpty);
    expect(HomeExtrasService.mapearRespuesta('error'), isEmpty);
    expect(
      HomeExtrasService.mapearRespuesta(<dynamic>[
        <String, dynamic>{'id_producto': 0, 'denominacion': 'x'},
        <String, dynamic>{'id_producto': 5, 'denominacion': '  '},
        <String, dynamic>{'id_producto': 6, 'denominacion': 'ok'},
      ]).map((HomeRielProducto p) => p.id),
      <int>[6],
    );
  });

  test('la caché offline guarda y devuelve el riel completo', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    const String clave = 'home_rail_top_224';

    expect(await HomeExtrasService.leerCacheRiel(clave), isEmpty);

    await HomeExtrasService.guardarCacheRiel(clave, <HomeRielProducto>[
      const HomeRielProducto(
        id: 10800,
        nombre: 'tacos',
        precio: 12.5,
        precioOferta: 10,
        unidadesVendidas: 7,
        categoria: 'Alimentos',
      ),
      const HomeRielProducto(id: 10801, nombre: 'cerdo grille'),
    ]);

    final List<HomeRielProducto> leido = await HomeExtrasService.leerCacheRiel(
      clave,
    );
    expect(leido, hasLength(2));
    expect(leido.first.id, 10800);
    expect(leido.first.nombre, 'tacos');
    expect(leido.first.precioOferta, 10);
    expect(leido.first.unidadesVendidas, 7);
    expect(leido.last.id, 10801);
  });
}
