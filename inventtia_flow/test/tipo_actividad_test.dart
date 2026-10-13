import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/tipo_actividad_service.dart';

/// El código es la clave estable que viaja al cliente dentro de
/// `cliente_obtener_servicios` y la que valida `admin_guardar_tipo_actividad`,
/// así que la propuesta automática y la validación deben coincidir.
void main() {
  group('codigoDesdeNombre', () {
    test('pasa a minúsculas y separa con guion bajo', () {
      expect(
        TipoActividad.codigoDesdeNombre('Cejas y Pestañas'),
        'cejas_y_pestanas',
      );
      expect(
        TipoActividad.codigoDesdeNombre('Hogar y Reparaciones'),
        'hogar_y_reparaciones',
      );
    });

    test('quita acentos y eñes', () {
      expect(TipoActividad.codigoDesdeNombre('Uñas'), 'unas');
      expect(TipoActividad.codigoDesdeNombre('Peluquería'), 'peluqueria');
      expect(
        TipoActividad.codigoDesdeNombre('Estética y Spa'),
        'estetica_y_spa',
      );
    });

    test('no deja guiones bajos al principio ni al final', () {
      expect(TipoActividad.codigoDesdeNombre('  Salud  '), 'salud');
      expect(TipoActividad.codigoDesdeNombre('¡Eventos!'), 'eventos');
    });

    test('colapsa signos repetidos en un solo guion bajo', () {
      expect(TipoActividad.codigoDesdeNombre('A -- B'), 'a_b');
      expect(TipoActividad.codigoDesdeNombre('A / B'), 'a_b');
    });

    test('replica la cadena de normalización del SQL', () {
      // `admin_guardar_tipo_actividad` hace:
      //   lower → translate(acentos) → regexp_replace('[^a-z0-9]+','_','g')
      //   → trim(both '_' from …)
      // Si las dos normalizaciones divergen, el usuario ve un código y se
      // guarda otro distinto.
      expect(
        TipoActividad.codigoDesdeNombre('  Cejas & Pestañas!!!  '),
        'cejas_pestanas',
      );
      expect(TipoActividad.codigoDesdeNombre('__ya_limpio__'), 'ya_limpio');
      expect(TipoActividad.codigoDesdeNombre('A.B/C'), 'a_b_c');
    });

    test('el resultado siempre supera la validación del RPC', () {
      for (final nombre in [
        'Cejas y Pestañas',
        'Uñas',
        'Peluquería y Barbería',
        'Estética y Spa',
        'Transporte en ómnibus',
        'Tecnología',
      ]) {
        final codigo = TipoActividad.codigoDesdeNombre(nombre);
        expect(
          TipoActividad.codigoValido(codigo),
          isTrue,
          reason: '«$nombre» generó «$codigo»',
        );
      }
    });
  });

  group('codigoValido', () {
    test('acepta el formato del RPC', () {
      expect(TipoActividad.codigoValido('unas'), isTrue);
      expect(TipoActividad.codigoValido('transporte_omnibus'), isTrue);
      expect(TipoActividad.codigoValido('a1b2c3'), isTrue);
    });

    test('rechaza lo que el RPC rechazaría', () {
      expect(TipoActividad.codigoValido('ab'), isFalse); // < 3 caracteres
      expect(TipoActividad.codigoValido('Uñas'), isFalse); // mayúscula/acento
      expect(TipoActividad.codigoValido('con espacio'), isFalse);
      expect(TipoActividad.codigoValido('con-guion'), isFalse);
      expect(TipoActividad.codigoValido(''), isFalse);
      expect(TipoActividad.codigoValido('a' * 65), isFalse); // > 64 caracteres
    });
  });

  group('fromJson', () {
    test('lee las filas del nomenclador', () {
      final tipo = TipoActividad.fromJson({
        'id': 4,
        'codigo': 'cejas_pestanas',
        'nombre': 'Cejas y Pestañas',
        'activo': true,
      });
      expect(tipo.id, 4);
      expect(tipo.codigo, 'cejas_pestanas');
      expect(tipo.nombre, 'Cejas y Pestañas');
      expect(tipo.activo, isTrue);
    });

    test('tolera columnas ausentes sin lanzar', () {
      final tipo = TipoActividad.fromJson({'id': 1});
      expect(tipo.codigo, '');
      expect(tipo.nombre, '');
      expect(tipo.activo, isTrue);
    });

    test('lee `id_padre` y `orden` de la migración 47', () {
      final sub = TipoActividad.fromJson({
        'id': 7,
        'codigo': 'unas',
        'nombre': 'Uñas / Manicure',
        'activo': true,
        'id_padre': 6,
        'orden': 20,
      });
      expect(sub.idPadre, 6);
      expect(sub.orden, 20);
      expect(sub.esSubcategoria, isTrue);
    });

    test('sin `id_padre` es categoría raíz (payload de la migración 22)', () {
      final raiz = TipoActividad.fromJson({
        'id': 6,
        'codigo': 'belleza',
        'nombre': 'Belleza',
        'activo': true,
      });
      expect(raiz.idPadre, isNull);
      expect(raiz.esSubcategoria, isFalse);
      expect(raiz.orden, 0);
    });
  });

  group('TipoActividad.copyWith', () {
    test('conserva el padre cuando no se menciona', () {
      const sub = TipoActividad(
        id: 7,
        codigo: 'unas',
        nombre: 'Uñas',
        idPadre: 6,
      );
      final editada = sub.copyWith(nombre: 'Uñas / Manicure');
      expect(editada.idPadre, 6);
      expect(editada.nombre, 'Uñas / Manicure');
    });

    test('permite convertir una subcategoría en categoría con `idPadre: null`',
        () {
      // El parámetro es `Object?` con centinela justo para esto: con `int?` y
      // `??` no habría forma de distinguir "no lo toques" de "ponlo en null".
      const sub = TipoActividad(
        id: 7,
        codigo: 'unas',
        nombre: 'Uñas',
        idPadre: 6,
      );
      final raiz = sub.copyWith(idPadre: null);
      expect(raiz.idPadre, isNull);
      expect(raiz.esSubcategoria, isFalse);
    });
  });

  group('Taxonomia', () {
    // Taxonomía de prueba con la forma real: 2 categorías con hijas (una de
    // ellas con una sola) y una categoría sin hijas.
    const alojamiento = TipoActividad(
      id: 10,
      codigo: 'alojamiento',
      nombre: 'Alojamiento',
      orden: 10,
    );
    const belleza = TipoActividad(
      id: 6,
      codigo: 'belleza',
      nombre: 'Belleza',
      orden: 30,
    );
    // Mismo `orden` que `unas`: el desempate debe ser por nombre.
    const cejas = TipoActividad(
      id: 8,
      codigo: 'cejas_pestanas',
      nombre: 'Cejas y Pestañas',
      idPadre: 6,
      orden: 20,
    );
    const unas = TipoActividad(
      id: 7,
      codigo: 'unas',
      nombre: 'Uñas / Manicure',
      idPadre: 6,
      orden: 20,
    );
    const hoteleria = TipoActividad(
      id: 20,
      codigo: 'hoteleria_hostal',
      nombre: 'Hotelería / Hostal',
      idPadre: 10,
      orden: 10,
      activo: false,
    );
    // Categoría SIN hijas: sigue siendo asignable.
    const juridicos = TipoActividad(
      id: 11,
      codigo: 'juridicos',
      nombre: 'Jurídicos',
      orden: 60,
    );

    final taxonomia = Taxonomia(const [
      belleza,
      unas,
      cejas,
      alojamiento,
      hoteleria,
      juridicos,
    ]);

    test('estaVacia solo con la lista vacía', () {
      expect(Taxonomia.vacia.estaVacia, isTrue);
      expect(taxonomia.estaVacia, isFalse);
    });

    test('raices devuelve solo el nivel 1, ordenado por `orden`', () {
      expect(
        taxonomia.raices.map((t) => t.codigo).toList(),
        ['alojamiento', 'belleza', 'juridicos'],
      );
    });

    test('raices desempata por nombre cuando el orden empata', () {
      const a = TipoActividad(id: 1, codigo: 'zeta', nombre: 'Zeta', orden: 5);
      const b = TipoActividad(id: 2, codigo: 'alfa', nombre: 'Alfa', orden: 5);
      expect(
        Taxonomia(const [a, b]).raices.map((t) => t.codigo).toList(),
        ['alfa', 'zeta'],
      );
    });

    test('subcategoriasDe ordena por `orden` y luego por nombre', () {
      expect(
        taxonomia.subcategoriasDe(6).map((t) => t.codigo).toList(),
        // `cejas_pestanas` y `unas` comparten orden 20: gana "Cejas…".
        ['cejas_pestanas', 'unas'],
      );
      expect(taxonomia.subcategoriasDe(10).single.codigo, 'hoteleria_hostal');
      // Una categoría sin hijas devuelve vacío, no null.
      expect(taxonomia.subcategoriasDe(11), isEmpty);
      expect(taxonomia.subcategoriasDe(null), isEmpty);
      // Un id que no es categoría tampoco tiene hijas.
      expect(taxonomia.subcategoriasDe(7), isEmpty);
    });

    test('subcategoriasDe incluye inactivas (las pantallas de gestión las ven)',
        () {
      expect(taxonomia.subcategoriasDe(10).single.activo, isFalse);
    });

    test('categoriaDe sube un nivel y deja las raíces como están', () {
      expect(taxonomia.categoriaDe(7)?.codigo, 'belleza');
      expect(taxonomia.categoriaDe(20)?.codigo, 'alojamiento');
      expect(taxonomia.categoriaDe(6)?.codigo, 'belleza');
      expect(taxonomia.categoriaDe(null), isNull);
      expect(taxonomia.categoriaDe(999), isNull);
    });

    test('categoriaNombre y subcategoriaNombre', () {
      expect(taxonomia.categoriaNombre(7), 'Belleza');
      expect(taxonomia.subcategoriaNombre(7), 'Uñas / Manicure');
      // Una raíz no tiene subcategoría…
      expect(taxonomia.categoriaNombre(6), 'Belleza');
      expect(taxonomia.subcategoriaNombre(6), isNull);
      // …y algo que no está en la taxonomía no inventa nombres.
      expect(taxonomia.categoriaNombre(999), isNull);
      expect(taxonomia.subcategoriaNombre(999), isNull);
    });

    test('etiquetaCompleta usa "›" y no repite el nombre en las raíces', () {
      expect(taxonomia.etiquetaCompleta(7), 'Belleza › Uñas / Manicure');
      expect(taxonomia.etiquetaCompleta(6), 'Belleza');
      expect(taxonomia.etiquetaCompleta(999), '');
      expect(taxonomia.etiquetaCompleta(null), '');
    });

    test('asignables deja fuera las categorías que ya tienen hijas', () {
      final codigos = taxonomia.asignables.map((t) => t.codigo).toList();
      // `alojamiento` y `belleza` tienen hijas: no se asignan directamente.
      expect(codigos, isNot(contains('alojamiento')));
      expect(codigos, isNot(contains('belleza')));
      // `juridicos` no tiene hijas: sí.
      expect(codigos, contains('juridicos'));
      expect(codigos, contains('unas'));
      expect(codigos, contains('hoteleria_hostal'));
    });

    test('asignables agrupa por categoría y respeta el orden', () {
      // Belleza (orden 30) va después de Alojamiento (10), y dentro de cada
      // categoría manda el orden de la hoja.
      final codigos = taxonomia.asignables.map((t) => t.codigo).toList();
      expect(
        codigos,
        ['hoteleria_hostal', 'cejas_pestanas', 'unas', 'juridicos'],
      );
    });

    test('sinJerarquia detecta una lectura sin `id_padre`', () {
      // Migración 47 sin aplicar: todas las filas son raíces.
      expect(taxonomia.sinJerarquia, isFalse);
      expect(
        Taxonomia(const [
          TipoActividad(id: 1, codigo: 'belleza', nombre: 'Belleza'),
          TipoActividad(id: 2, codigo: 'unas', nombre: 'Uñas'),
        ]).sinJerarquia,
        isTrue,
      );
      // Vacía no es "sin jerarquía": no hay nada que mostrar.
      expect(Taxonomia.vacia.sinJerarquia, isFalse);
    });

    test('porId resuelve cualquier nivel', () {
      expect(taxonomia.porId(6)?.nombre, 'Belleza');
      expect(taxonomia.porId(7)?.nombre, 'Uñas / Manicure');
      expect(taxonomia.porId(null), isNull);
      expect(taxonomia.porId(999), isNull);
    });
  });
}
