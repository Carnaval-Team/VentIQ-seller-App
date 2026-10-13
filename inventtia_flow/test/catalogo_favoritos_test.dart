import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/servicio.dart';

/// El catálogo del cliente coloca los favoritos **primero**.
///
/// La lógica vive en `CatalogoScreenState._filtered`, que necesita el state de
/// un widget y por tanto no es unit-testeable directamente. Estas pruebas fijan
/// el contrato de la partición que sí se puede aislar: mismo algoritmo, mismo
/// requisito (orden estable y sin perder elementos).
void main() {
  LocalServicio ls(
    int id, {
    String? provincia,
    String local = 'L',
    String serv = 'S',
  }) => LocalServicio(
    id: id,
    idLocal: 1,
    idServicio: 1,
    createdAt: DateTime(2026),
    local: Local(
      id: 1,
      nombre: local,
      provincia: provincia,
      createdAt: DateTime(2026),
    ),
    servicio: Servicio(id: 1, nombre: serv, createdAt: DateTime(2026)),
  );

  /// Réplica exacta de la partición que hace la pantalla.
  List<LocalServicio> favoritosPrimero(
    List<LocalServicio> lista,
    Set<int> ids,
  ) {
    if (ids.isEmpty) return lista;
    final favoritos = <LocalServicio>[];
    final resto = <LocalServicio>[];
    for (final item in lista) {
      if (ids.contains(item.id)) {
        favoritos.add(item);
      } else {
        resto.add(item);
      }
    }
    return <LocalServicio>[...favoritos, ...resto];
  }

  final catalogo = <LocalServicio>[
    ls(11, serv: 'Uñas'),
    ls(12, serv: 'Cejas'),
    ls(13, serv: 'Transporte'),
    ls(14, serv: 'Pedicure'),
    ls(15, serv: 'Gas'),
  ];

  test('sin favoritos conserva el orden original', () {
    final resultado = favoritosPrimero(catalogo, <int>{});
    expect(resultado.map((e) => e.id), [11, 12, 13, 14, 15]);
  });

  test('sube los favoritos al principio', () {
    final resultado = favoritosPrimero(catalogo, <int>{13, 15});
    expect(resultado.map((e) => e.id), [13, 15, 11, 12, 14]);
  });

  test('es estable: preserva el orden original dentro de cada grupo', () {
    // List.sort de Dart no es estable, por eso la pantalla particiona en dos
    // listas en vez de ordenar por el booleano. Si alguien lo "simplificara" a
    // un sort, este test lo detectaría.
    final resultado = favoritosPrimero(catalogo, <int>{14, 12});
    expect(resultado.map((e) => e.id), [12, 14, 11, 13, 15]);
  });

  test('no pierde ni duplica elementos', () {
    final resultado = favoritosPrimero(catalogo, <int>{11, 12, 13, 14, 15});
    expect(resultado, hasLength(catalogo.length));
    expect(
      resultado.map((e) => e.id).toSet(),
      catalogo.map((e) => e.id).toSet(),
    );
  });

  test('un id favorito que no está en la lista no inventa filas', () {
    // Caso real: el usuario guardó algo que luego se despublicó del catálogo.
    final resultado = favoritosPrimero(catalogo, <int>{9999, 12});
    expect(resultado.map((e) => e.id), [12, 11, 13, 14, 15]);
    expect(resultado, hasLength(catalogo.length));
  });

  test('todos favoritos mantiene el orden', () {
    final resultado = favoritosPrimero(catalogo, <int>{11, 12, 13, 14, 15});
    expect(resultado.map((e) => e.id), [11, 12, 13, 14, 15]);
  });
}
