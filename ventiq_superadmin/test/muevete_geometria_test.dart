import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:ventiq_superadmin/utils/muevete_geometria.dart';

/// Pruebas de la geometría de zonas tarifarias (H6, segunda mitad).
///
/// Cubren el contrato con la base de datos: GeoJSON Polygon, orden
/// `[longitud, latitud]`, anillos cerrados, huecos y las tres validaciones del
/// editor (≥ 3 vértices, sin duplicados consecutivos, sin auto-intersección).
void main() {
  group('serialización', () {
    test('cierra el anillo y escribe [lon, lat]', () {
      const poligono = PoligonoZona(
        exterior: [
          LatLng(22.400, -79.970),
          LatLng(22.400, -79.950),
          LatLng(22.420, -79.950),
          LatLng(22.420, -79.970),
        ],
      );

      final geo = poligono.aGeoJson();
      expect(geo['type'], 'Polygon');

      final coordenadas = geo['coordinates'] as List<Object?>;
      expect(coordenadas.length, 1);

      final anillo = coordenadas.first as List<Object?>;
      expect(anillo.length, 5, reason: '4 vértices + cierre');
      expect(anillo.first, [-79.97, 22.4]);
      expect(anillo.last, anillo.first, reason: 'el anillo va cerrado');
    });

    test('lee un anillo abierto como el del seed', () {
      final poligono = PoligonoZona.desdeGeoJson(
        '{"type":"Polygon","coordinates":'
        '[[[-79.975,22.400],[-79.955,22.400],'
        '[-79.955,22.415],[-79.975,22.415]]]}',
      );

      expect(poligono, isNotNull);
      expect(poligono!.exterior.length, 4);
      expect(poligono.exterior.first.latitude, 22.400);
      expect(poligono.exterior.first.longitude, -79.975);
      expect(poligono.huecos, isEmpty);
    });

    test('acepta el Map que devuelve PostgREST y descarta el cierre', () {
      final poligono = PoligonoZona.desdeGeoJson(<String, dynamic>{
        'type': 'Polygon',
        'coordinates': [
          [
            [-79.97, 22.40],
            [-79.95, 22.40],
            [-79.95, 22.42],
            [-79.97, 22.42],
            [-79.97, 22.40],
          ],
        ],
      });

      expect(poligono!.exterior.length, 4);
    });

    test('devuelve null con geometría ausente o inválida', () {
      expect(PoligonoZona.desdeGeoJson(null), isNull);
      expect(PoligonoZona.desdeGeoJson('no es json'), isNull);
      expect(PoligonoZona.desdeGeoJson(<String, dynamic>{}), isNull);
      expect(
        PoligonoZona.desdeGeoJson(<String, dynamic>{
          'type': 'Point',
          'coordinates': [1, 2],
        }),
        isNull,
      );
    });

    test('serializa huecos como coordinates[1..]', () {
      const poligono = PoligonoZona(
        exterior: [LatLng(0, 0), LatLng(0, 4), LatLng(4, 4), LatLng(4, 0)],
        huecos: [
          [LatLng(1, 1), LatLng(1, 2), LatLng(2, 2), LatLng(2, 1)],
        ],
      );

      final coordenadas = poligono.aGeoJson()['coordinates'] as List<Object?>;
      expect(coordenadas.length, 2);
      expect((coordenadas[1] as List<Object?>).length, 5);
    });
  });

  group('validación', () {
    test('exige 3 vértices', () {
      const poligono = PoligonoZona(
        exterior: [LatLng(22.40, -79.97), LatLng(22.40, -79.95)],
      );
      expect(poligono.validar(), contains('al menos 3 vértices'));
      expect(PoligonoZona.vacio.validar(), contains('Dibuja al menos 3'));
    });

    test('rechaza vértices duplicados consecutivos', () {
      const poligono = PoligonoZona(
        exterior: [
          LatLng(22.40, -79.97),
          LatLng(22.40, -79.97),
          LatLng(22.42, -79.95),
        ],
      );
      expect(poligono.validar(), contains('mismo punto'));
    });

    test('rechaza auto-intersección (mariposa)', () {
      const poligono = PoligonoZona(
        exterior: [LatLng(0, 0), LatLng(1, 1), LatLng(1, 0), LatLng(0, 1)],
      );
      expect(poligono.validar(), contains('se cruza consigo mismo'));
    });

    test('acepta un triángulo y un cuadrado simples', () {
      const triangulo = PoligonoZona(
        exterior: [LatLng(0, 0), LatLng(0, 1), LatLng(1, 0)],
      );
      expect(triangulo.validar(), isNull);

      const cuadrado = PoligonoZona(
        exterior: [
          LatLng(22.400, -79.970),
          LatLng(22.400, -79.950),
          LatLng(22.420, -79.950),
          LatLng(22.420, -79.970),
        ],
      );
      expect(cuadrado.validar(), isNull);
    });

    test('acepta un hueco interior y rechaza uno fuera o que cruce', () {
      const exterior = [LatLng(0, 0), LatLng(0, 4), LatLng(4, 4), LatLng(4, 0)];

      const huecoInterior = PoligonoZona(
        exterior: exterior,
        huecos: [
          [LatLng(1, 1), LatLng(1, 2), LatLng(2, 2), LatLng(2, 1)],
        ],
      );
      expect(huecoInterior.validar(), isNull);

      const huecoFuera = PoligonoZona(
        exterior: exterior,
        huecos: [
          [LatLng(10, 10), LatLng(10, 11), LatLng(11, 11), LatLng(11, 10)],
        ],
      );
      expect(huecoFuera.validar(), contains('debe quedar dentro'));

      const huecoQueCorta = PoligonoZona(
        exterior: exterior,
        huecos: [
          [LatLng(3, 3), LatLng(3, 5), LatLng(5, 5), LatLng(5, 3)],
        ],
      );
      expect(huecoQueCorta.validar(), contains('se cruza con el borde'));
    });
  });

  group('métricas', () {
    test('área, perímetro y centroide de un cuadrado de ~2 km', () {
      const poligono = PoligonoZona(
        exterior: [
          LatLng(22.400, -79.970),
          LatLng(22.400, -79.950),
          LatLng(22.420, -79.950),
          LatLng(22.420, -79.970),
        ],
      );

      expect(poligono.areaKm2, greaterThan(4));
      expect(poligono.areaKm2, lessThan(5.5));
      expect(poligono.perimetroKm, greaterThan(8));
      expect(poligono.centroide.latitude, closeTo(22.410, 0.0001));
      expect(poligono.centroide.longitude, closeTo(-79.960, 0.0001));
      expect(poligono.totalVertices, 4);
    });

    test('el área resta los huecos', () {
      const sinHueco = PoligonoZona(
        exterior: [
          LatLng(0, 0),
          LatLng(0, 0.04),
          LatLng(0.04, 0.04),
          LatLng(0.04, 0),
        ],
      );
      const conHueco = PoligonoZona(
        exterior: [
          LatLng(0, 0),
          LatLng(0, 0.04),
          LatLng(0.04, 0.04),
          LatLng(0.04, 0),
        ],
        huecos: [
          [LatLng(0.01, 0.01), LatLng(0.01, 0.02), LatLng(0.02, 0.02)],
        ],
      );

      expect(conHueco.areaKm2, lessThan(sinHueco.areaKm2));
      expect(conHueco.areaKm2, greaterThan(0));
    });
  });
}
