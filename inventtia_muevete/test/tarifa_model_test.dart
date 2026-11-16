import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_muevete/models/tarifa_model.dart';

/// Fixtures con la forma REAL del jsonb de `muevete.fn_cotizar_viaje`
/// (verificado contra producción; claves aditivas de las migraciones 053/054).
void main() {
  // Placetas -> Parque Vidal, p_km = 42, auto, 12:00.
  // Esperado por la regla: 1.500 + 120 × (42 + 42) + 500 de prima = 12.100.
  final cotizacionPlacetas = <String, dynamic>{
    'precio_plataforma': 12100,
    'moneda': 'CUP',
    'comision_pct': 15,
    'comision_monto': 1815,
    'precio_chofer': 10285,
    'zona_id': null,
    'zona_nombre': 'Fuera de zona',
    'tarifa_modo': 'fijo_mas_km',
    'km_total': 42,
    'km_fuente': 'ruta',
    'tipo_vehiculo': 'auto',
    'multiplicador_tipo': 1,
    'es_nocturno': false,
    'precio_corto': false,
    'base_nombre': 'Base Santa Clara (Parque Vidal)',
    'en_base_origen': false,
    'en_base_destino': true,
    'tramo_recogida_km': 42,
    'tramo_viaje_km': 42,
    'km_cobrados': 84,
    'detalle': <String, dynamic>{
      'dentro_de_zona': false,
      'fallback_municipio': true,
      'modo': 'fijo_mas_km',
      'monto_fijo': 1500,
      'precio_km': 120,
      'base': 11580,
      'km_lineal': 33.982,
      'km_total': 42,
      'recargo_nocturno': 0,
      'recargo_prima_distancia': 500,
      'precio_antes_redondeo': 12080,
      'redondeo_cup': 50,
      'precio_corto_aplicado': false,
      'base_nombre': 'Base Santa Clara (Parque Vidal)',
      'en_base_origen': false,
      'en_base_destino': true,
      'tramo_recogida_km': 42,
      'tramo_viaje_km': 42,
      'tramo_recogida_cup': 5040,
      'tramo_viaje_cup': 5040,
      'km_cobrados': 84,
      'factor_rodeo': 1.2359,
      'base_sc_cup': 1500,
      'precio_km_sc': 120,
    },
  };

  // Dentro del área base: 2 km, auto, plano.
  final cotizacionCentro = <String, dynamic>{
    'precio_plataforma': 1500,
    'moneda': 'CUP',
    'comision_pct': 15,
    'comision_monto': 225,
    'precio_chofer': 1275,
    'zona_id': 1,
    'zona_nombre': 'Municipio Santa Clara (perímetro de emparejamiento)',
    'tarifa_modo': 'fijo',
    'km_total': 1.998,
    'tipo_vehiculo': 'auto',
    'multiplicador_tipo': 1,
    'es_nocturno': false,
    'precio_corto': false,
    'base_nombre': 'Base Santa Clara (Parque Vidal)',
    'en_base_origen': true,
    'en_base_destino': true,
    'tramo_recogida_km': 0,
    'tramo_viaje_km': 0,
    'km_cobrados': 0,
    'detalle': <String, dynamic>{
      'dentro_de_zona': true,
      'fallback_municipio': false,
      'modo': 'fijo',
      'monto_fijo': 1500,
      'precio_km': 120,
      'base': 1500,
      'km_lineal': 1.998,
      'recargo_nocturno': 0,
      'recargo_prima_distancia': 0,
      'precio_antes_redondeo': 1500,
      'redondeo_cup': 50,
      'precio_corto_aplicado': false,
      'base_nombre': 'Base Santa Clara (Parque Vidal)',
      'en_base_origen': true,
      'en_base_destino': true,
      'tramo_recogida_km': 0,
      'tramo_viaje_km': 0,
      'km_cobrados': 0,
      'base_sc_cup': 1500,
      'precio_km_sc': 120,
    },
  };

  group('Cotización con área base (053/054)', () {
    test('Placetas → Santa Clara cotiza base + recogida + viaje, no el plano',
        () {
      final c = Cotizacion.fromJson(cotizacionPlacetas);

      expect(c.precioPlataforma, 12100);
      expect(c.tarifaModo, 'fijo_mas_km');
      expect(c.esTarifaBase, isTrue);
      expect(c.baseNombre, 'Base Santa Clara (Parque Vidal)');
      expect(c.enBaseOrigen, isFalse);
      expect(c.enBaseDestino, isTrue);
      expect(c.tramoRecogidaKm, 42);
      expect(c.tramoViajeKm, 42);
      expect(c.kmCobrados, 84);
      expect(c.dentroDeZona, isFalse);

      // Lo que el dueño rechazaba: 1.500 planos por 34 km.
      expect(c.precioPlataforma, greaterThan(10000));

      expect(c.zonaEtiqueta, 'Tarifa base + recogida + km');
      expect(c.tarifaModoEtiqueta, 'Base + por km');
      expect(c.recogidaEtiqueta, contains('42.0 km'));
    });

    test('Viaje dentro del área base se mantiene plano en 1.500', () {
      final c = Cotizacion.fromJson(cotizacionCentro);

      expect(c.precioPlataforma, 1500);
      expect(c.esTarifaBase, isTrue);
      expect(c.dentroDeZona, isTrue);
      expect(c.tramoRecogidaKm, 0);
      expect(c.recogidaEtiqueta, isNull);
      expect(c.zonaEtiqueta, 'Tarifa base · área SC');
      expect(c.tarifaModoEtiqueta, 'Base SC');
    });
  });

  group('Compatibilidad con respuestas sin área base', () {
    test('Un jsonb antiguo sigue produciendo las etiquetas de siempre', () {
      final c = Cotizacion.fromJson(<String, dynamic>{
        'precio_plataforma': 2000,
        'tarifa_modo': 'fijo',
        'km_total': 9.99,
        'zona_nombre': 'Municipio Santa Clara',
        'detalle': <String, dynamic>{
          'dentro_de_zona': true,
          'base': 1500,
        },
      });

      expect(c.esTarifaBase, isFalse);
      expect(c.zonaEtiqueta, 'Tarifa de Municipio Santa Clara');
      expect(c.tarifaModoEtiqueta, 'Tarifa fija por zona');
      expect(c.recogidaEtiqueta, isNull);
    });

    test('La forma de 053 (km_recogida / km_cobrables) también se parsea', () {
      // La 053 publica `km_recogida` y `km_cobrables` (sin base_nombre).
      final c = Cotizacion.fromJson(<String, dynamic>{
        'precio_plataforma': 10400,
        'tarifa_modo': 'fijo_mas_km',
        'km_total': 40,
        'km_recogida': 33.982,
        'km_cobrables': 73.982,
        'zona_nombre': 'Fuera de zona',
        'detalle': <String, dynamic>{
          'dentro_de_zona': false,
          'fallback_municipio': true,
          'base': 10377.84,
          'km_recogida': 33.982,
          'km_cobrables': 73.982,
        },
      });

      expect(c.precioPlataforma, 10400);
      expect(c.tramoRecogidaKm, 33.982);
      expect(c.kmCobrados, 73.982);
      // Sin `base_nombre` cae en las etiquetas heredadas, no revienta.
      expect(c.esTarifaBase, isFalse);
      expect(c.tarifaModoEtiqueta, 'Tarifa fija + km');
      expect(c.recogidaEtiqueta, isNull);
    });
  });
}