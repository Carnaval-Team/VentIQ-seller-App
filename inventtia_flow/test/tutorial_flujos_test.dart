import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/tutorial/tutorial_destino.dart';
import 'package:inventtia_flow/tutorial/tutorial_flujos.dart';
import 'package:inventtia_flow/tutorial/tutorial_paso.dart';

/// Guardas sobre los guiones: los `id` de los pasos son la única unión entre el
/// guion y las anclas que se colocan en las pantallas. Un id repetido (dentro de
/// un flujo o entre los dos) haría que el registro de anclas se pisara y el
/// tutorial resaltaría el elemento equivocado, así que se comprueba aquí.
void main() {
  final List<TutorialPaso> cliente = TutorialFlujos.pasosCliente();
  final List<TutorialPaso> admin = TutorialFlujos.pasosAdmin();

  test('ningún flujo está vacío y todos los pasos tienen texto', () {
    expect(cliente, isNotEmpty);
    expect(admin, isNotEmpty);
    for (final paso in <TutorialPaso>[...cliente, ...admin]) {
      expect(paso.id.trim(), isNotEmpty);
      expect(paso.titulo.trim(), isNotEmpty);
      expect(paso.mensaje.trim(), isNotEmpty);
    }
  });

  test('los ids son únicos dentro de cada flujo', () {
    for (final pasos in <List<TutorialPaso>>[cliente, admin]) {
      final ids = pasos.map((p) => p.id).toList();
      expect(ids.toSet().length, ids.length,
          reason: 'hay un id repetido en ${ids.toSet().length} ids únicos');
    }
  });

  test('no hay ids compartidos entre el flujo de cliente y el de admin', () {
    final idsCliente = cliente.map((p) => p.id).toSet();
    final idsAdmin = admin.map((p) => p.id).toSet();
    expect(idsCliente.intersection(idsAdmin), isEmpty);
  });

  test('los pasos con ancla no garantizada van marcados como opcionales', () {
    // `opcional` = el ancla puede no llegar a montarse (vive en una tarjeta
    // plegable, en otro módulo o en una sección que el negocio puede no usar).
    // Esos pasos se explican igual, pero la burbuja permite avanzar sin salir a
    // buscarlos, así que el recorrido siempre se puede terminar.
    final opcionales = admin
        .where((p) => p.opcional)
        .map((p) => p.id)
        .toSet();

    expect(
      opcionales,
      containsAll(<String>[
        'admin_reserva_directa', // solo existe con un servicio en un local
        'admin_capacidades', // ídem
        'admin_reservas', // módulo del dashboard
        'admin_categorias', // módulo del dashboard
      ]),
    );
    expect(admin.last.opcional, isTrue);
  });

  test('el paso de datos adicionales del cliente es opcional', () {
    // El formulario solo existe si el servicio tiene campos configurados: sin
    // ellos no hay nada que resaltar, así que el paso se explica pero permite
    // avanzar sin ir a buscarlo.
    //
    // Desde v2 también son opcionales los dos pasos que dependen de que haya
    // datos: sin establecimientos publicados no hay ficha que abrir y sin
    // reservas esta semana el ranking está vacío.
    final opcionales = cliente.where((p) => p.opcional).map((p) => p.id).toSet();
    expect(opcionales, <String>{
      'detalle_datos',
      'ficha_local_servicios',
      'top_servicios',
    });
  });

  test('el recorrido del cliente es el v2, con el acceso rápido explicado', () {
    // La lista completa se fija aquí a propósito: es la única unión entre el
    // guion y las anclas reales, y el orden es el del recorrido.
    expect(cliente.map((p) => p.id).toList(), <String>[
      'home_buscar',
      'home_exploracion',
      'home_ver_todo',
      'home_card_categorias',
      'categorias_lista',
      'establecimientos_lista',
      'ficha_local_servicios',
      'top_servicios',
      'catalogo_tarjeta',
      'detalle_acciones',
      'detalle_calendario',
      'detalle_datos',
      'detalle_continuar',
    ]);
    expect(cliente.length, 13);

    // El bloque de acceso rápido tiene que explicarse con sus propias palabras:
    // es lo primero que ve el cliente en el Home nuevo.
    final rejilla = cliente.firstWhere((p) => p.id == 'home_exploracion');
    expect(rejilla.titulo, contains('Exploración rápida'));
    expect(rejilla.mensaje, contains('Categorías'));
    expect(rejilla.mensaje, contains('Servicios'));
    expect(rejilla.mensaje, contains('Establecimientos'));
    expect(rejilla.mensaje, contains('Más populares'));
  });

  test('los pasos que salen de la pantalla declaran su destino', () {
    // Cliente: Home → acceso rápido → catálogo → detalle del primer servicio.
    expect(_destinoDe(cliente, 'home_buscar'), TutorialDestino.home);
    expect(_destinoDe(cliente, 'home_exploracion'), TutorialDestino.home);
    expect(_destinoDe(cliente, 'home_card_categorias'), TutorialDestino.home);
    expect(
      _destinoDe(cliente, 'categorias_lista'),
      TutorialDestino.listaCategorias,
    );
    expect(
      _destinoDe(cliente, 'establecimientos_lista'),
      TutorialDestino.listaEstablecimientos,
    );
    expect(
      _destinoDe(cliente, 'ficha_local_servicios'),
      TutorialDestino.fichaEstablecimiento,
    );
    expect(_destinoDe(cliente, 'top_servicios'), TutorialDestino.topServicios);
    expect(_destinoDe(cliente, 'catalogo_tarjeta'), TutorialDestino.catalogo);
    expect(_destinoDe(cliente, 'detalle_acciones'), TutorialDestino.servicio);

    // Admin: módulos y pantallas del recorrido.
    expect(_destinoDe(admin, 'admin_nuevo_local'), TutorialDestino.locales);
    expect(_destinoDe(admin, 'admin_nuevo_servicio'), TutorialDestino.servicios);
    expect(
      _destinoDe(admin, 'admin_precio'),
      TutorialDestino.serviciosFormulario,
    );
    expect(
      _destinoDe(admin, 'admin_reglas_precio'),
      TutorialDestino.serviciosFormulario,
    );
    expect(
      _destinoDe(admin, 'admin_anadir_servicio'),
      TutorialDestino.localDetalle,
    );
    expect(
      _destinoDe(admin, 'admin_reserva_directa'),
      TutorialDestino.servicioLocal,
    );
    expect(
      _destinoDe(admin, 'admin_recursos_turnos'),
      TutorialDestino.servicioLocal,
    );
    expect(_destinoDe(admin, 'admin_reservas'), TutorialDestino.reservas);
    expect(_destinoDe(admin, 'admin_categorias'), TutorialDestino.categorias);
  });

  test('cliente y admin no comparten destinos', () {
    final delCliente = cliente
        .map((p) => p.destino)
        .whereType<TutorialDestino>()
        .toSet();
    final delAdmin = admin
        .map((p) => p.destino)
        .whereType<TutorialDestino>()
        .toSet();

    expect(delCliente, isNotEmpty);
    expect(delAdmin, isNotEmpty);
    // Los del cliente: las pestañas del shell y, desde v2, las pantallas
    // apiladas de «Exploración rápida».
    expect(
      delCliente.difference(<TutorialDestino>{
        TutorialDestino.home,
        TutorialDestino.catalogo,
        TutorialDestino.servicio,
        TutorialDestino.listaCategorias,
        TutorialDestino.listaEstablecimientos,
        TutorialDestino.fichaEstablecimiento,
        TutorialDestino.topServicios,
      }),
      isEmpty,
    );
    expect(
      delAdmin.intersection(<TutorialDestino>{
        TutorialDestino.home,
        TutorialDestino.catalogo,
        TutorialDestino.servicio,
        TutorialDestino.listaCategorias,
        TutorialDestino.listaEstablecimientos,
        TutorialDestino.fichaEstablecimiento,
        TutorialDestino.topServicios,
      }),
      isEmpty,
    );
  });

  test('las hojas que abre el usuario no declaran destino', () {
    // El calendario y el formulario de la reserva solo existen al tocar el
    // elemento resaltado: los abre el usuario, el tutorial no navega hacia
    // ellos (espera al ancla y sigue).
    for (final id in <String>[
      'detalle_calendario',
      'detalle_datos',
      'detalle_continuar',
    ]) {
      expect(_destinoDe(cliente, id), isNull, reason: '$id no debe navegar');
    }
  });
}

/// Destino declarado por el paso [id] del recorrido.
TutorialDestino? _destinoDe(List<TutorialPaso> pasos, String id) =>
    pasos.firstWhere((p) => p.id == id).destino;