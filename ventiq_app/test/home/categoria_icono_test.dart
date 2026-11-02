import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/utils/categoria_icono.dart';

void main() {
  group('iconoCategoria reconoce el catálogo real', () {
    test('combustible y sus variantes', () {
      for (final String nombre in <String>[
        'Combustibles',
        'combustible',
        'GASOLINA ESPECIAL',
        'Diésel',
        'Servicentro',
      ]) {
        expect(
          iconoCategoria(nombre),
          Icons.local_gas_station_rounded,
          reason: 'no reconoció "$nombre"',
        );
      }
    });

    test('servicios', () {
      expect(iconoCategoria('Servicios'), Icons.room_service_rounded);
      expect(iconoCategoria('Servicio de reparación'),
          Icons.room_service_rounded);
    });

    test('alimentos y bebidas', () {
      expect(iconoCategoria('Alimentos'), Icons.restaurant_rounded);
      expect(iconoCategoria('Comida'), Icons.restaurant_rounded);
      expect(iconoCategoria('Bebidas'), Icons.local_drink_rounded);
      expect(iconoCategoria('Confituras'), Icons.cake_rounded);
      expect(iconoCategoria('Productos Panaderia'), Icons.bakery_dining_rounded);
      expect(iconoCategoria('Lácteos'), Icons.icecream_rounded);
    });

    test('aseo, hogar y electrónica', () {
      expect(iconoCategoria('Aseo Personal'),
          Icons.face_retouching_natural_rounded);
      expect(iconoCategoria('Limpieza'), Icons.cleaning_services_rounded);
      expect(iconoCategoria('Hogar Y Oficinas'), Icons.chair_rounded);
      expect(iconoCategoria('Electrodomesticos'), Icons.kitchen_rounded);
      expect(iconoCategoria('Electrónica'), Icons.devices_other_rounded);
    });
  });

  group('normalización', () {
    test('los acentos y las mayúsculas no cambian el icono', () {
      expect(iconoCategoria('Electrónica'), iconoCategoria('electronica'));
      expect(iconoCategoria('LÁCTEOS'), iconoCategoria('lacteos'));
      expect(iconoCategoria('Joyería'), iconoCategoria('joyeria'));
    });

    test('`pañales` no se confunde con `pan`', () {
      // "pan" está dentro de "pañales"; la regla de panadería exige "panader",
      // "panificad" o "reposter", así que no debe caer ahí.
      expect(iconoCategoria('Pañales'), isNot(Icons.bakery_dining_rounded));
    });

    test('un fragmento corto NO casa dentro de otra palabra', () {
      // Regresión: "ron" (Ron) casa dentro de "electRÓNica" y "te" (Té) dentro
      // de "textil". Los dos se vieron de verdad antes de exigir límite de
      // palabra a los fragmentos de menos de 5 letras.
      expect(iconoCategoria('Electrónica'), Icons.devices_other_rounded);
      expect(iconoCategoria('Textil'), Icons.checkroom_rounded);
      expect(iconoCategoria('Papelería'), Icons.menu_book_rounded);
    });

    test('...pero sí casa cuando es palabra suelta', () {
      expect(iconoCategoria('Ron añejo'), Icons.liquor_rounded);
      expect(iconoCategoria('Café y Té'), Icons.local_cafe_rounded);
      expect(iconoCategoria('Estética y Spa'), Icons.spa_outlined);
    });
  });

  group('fallbacks', () {
    test('un nombre desconocido cae al icono genérico, no revienta', () {
      expect(iconoCategoria('Zzz categoría rarísima'),
          Icons.category_outlined);
      expect(iconoCategoria(null), Icons.category_outlined);
      expect(iconoCategoria(''), Icons.category_outlined);
      expect(iconoCategoria('   '), Icons.category_outlined);
    });

    test('si el nombre no dice nada, prueba con el sku', () {
      expect(
        iconoCategoria('Categoría 12', skuCodigo: 'BEBIDAS-01'),
        Icons.local_drink_rounded,
      );
    });

    test('un sku que no reconoce no impide caer al genérico', () {
      expect(iconoCategoria('Categoría 12', skuCodigo: 'XYZ-01'),
          Icons.category_outlined);
    });

    test('el nombre tiene prioridad sobre el sku', () {
      expect(
        iconoCategoria('Bebidas', skuCodigo: 'COMB'),
        Icons.local_drink_rounded,
      );
    });
  });

  test('cada regla del catálogo devuelve algo distinto de null', () {
    const List<String> muestras = <String>[
      'Combustibles', 'Servicios', 'Alimentos', 'Bebidas', 'Confituras',
      'Aseo Personal', 'Cuidado Personal', 'Hogar Y Oficinas', 'Electrónica',
      'Ferretería', 'Textil', 'Joyería', 'Juguetería', 'Mascotas',
      'Papelería', 'Paquetería', 'Gasto', 'Alojamiento', 'Transporte',
      'Recreación', 'Eventos', 'Salud', 'Panadería', 'Lácteos', 'Snacks',
      'Café e Infuciones', 'Carnicería', 'Frutas y Vegetales', 'Calzado',
    ];
    for (final String m in muestras) {
      expect(iconoCategoria(m), isNot(Icons.category_outlined),
          reason: '"$m" no tiene regla propia');
    }
  });
}
