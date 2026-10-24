import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/config/app_theme.dart';
import 'package:inventtia_flow/models/establecimiento_resumen.dart';
import 'package:inventtia_flow/models/ficha_local.dart';
import 'package:inventtia_flow/models/servicio.dart';
import 'package:inventtia_flow/screens/espacio_patrocinado_screen.dart';
import 'package:inventtia_flow/screens/ficha_local_screen.dart';
import 'package:inventtia_flow/services/campana_service.dart';
import 'package:inventtia_flow/tutorial/tutorial_anchor.dart';
import 'package:inventtia_flow/widgets/resenas.dart';

/// Pruebas de la ficha compartida de un establecimiento (F5).
///
/// Cubren lo que `flutter analyze` no ve:
///   * que `FichaLocal.desdeCampana` / `.desdeEstablecimiento` normalicen los
///     campos (nombre, titular, ubicación, vigencia, valoración),
///   * que los DOS modos se pinten distinto: sello y degradado de la campaña
///     frente a sello de establecimiento y degradado de marca,
///   * que sin campaña NO aparezca nada de campaña («ESPACIO PATROCINADO» ni
///     «DESTACADO DEL MOMENTO») y que sin reseñas no aparezcan estrellas,
///   * que la lista de servicios caiga en su estado vacío sin tocar red,
///   * que el envoltorio `EspacioPatrocinadoScreen` abra exactamente la misma
///     vista con la firma pública de siempre.
///
/// La pantalla pide los servicios a `flow.cliente_obtener_servicios`: aquí se
/// inyectan con `serviciosIniciales` (para lo único que existe ese parámetro), de
/// modo que ninguna prueba necesita Supabase.
const Color _campanaInicio = Color(0xFF4F5C8B);
const Color _campanaFin = Color(0xFF1FA8B8);

/// Campaña de prueba construida como llega del RPC (`campanas_activas`).
///
/// Sin `local_foto`/`image_url` a propósito: así la cabecera cae en el degradado
/// que se quiere medir en vez de intentar descargar una imagen.
CampanaPatrocinada _campana({
  String titulo = 'Relájate este mes',
  String? subtitulo = 'Masajes con descuento',
  String? descripcion = 'Temporada de spa: reserva y ahorra.',
  String? local = 'Spa Aurora',
  String? localDescripcion = 'Un spa de barrio con 20 años de historia.',
  String? localDireccion = 'Calle 12 #45',
  String? localProvincia = 'Villa Clara',
  String? localPais = 'Cuba',
  String? localHorario = '9:00 - 18:00',
  String? entidad = 'Entidad Aurora',
  String? entidadTelefono = '555-0101',
  String? localFoto,
  String? imageUrl,
}) {
  return CampanaPatrocinada.fromJson(<String, dynamic>{
    'id': 5,
    'titulo': titulo,
    'subtitulo': subtitulo,
    'descripcion': descripcion,
    'id_local': local == null ? null : 7,
    'id_local_servicio': 99,
    'id_entidad': 3,
    'id_entidad_real': 3,
    'color_inicio': '#4F5C8B',
    'color_fin': '#1FA8B8',
    'icono': 'spa',
    'prioridad': 1,
    'hasta': '2026-12-31T00:00:00Z',
    'local': local,
    'entidad': entidad,
    'local_foto': localFoto,
    'image_url': imageUrl,
    'local_descripcion': localDescripcion,
    'local_direccion': localDireccion,
    'local_provincia': localProvincia,
    'local_pais': localPais,
    'local_horario_atencion': localHorario,
    'entidad_telefono': entidadTelefono,
  });
}

EstablecimientoResumen _establecimiento({
  String nombre = 'Bar La Terraza',
  String? descripcion = 'Coctelería con vista al mar.',
  String? direccion = 'Malecón 101',
  String? provincia = 'La Habana',
  String? pais = 'Cuba',
  int totalServicios = 0,
  int totalResenas = 0,
  double? rating,
  String? entidad = 'Entidad Terraza',
  String? entidadTelefono = '555-0202',
  String? horario = '10:00 - 22:00',
}) {
  return EstablecimientoResumen(
    idLocal: 3,
    nombre: nombre,
    descripcion: descripcion,
    direccion: direccion,
    provincia: provincia,
    pais: pais,
    horarioTexto: horario,
    entidad: entidad,
    entidadTelefono: entidadTelefono,
    totalServicios: totalServicios,
    totalResenas: totalResenas,
    rating: rating,
  );
}

LocalServicio _servicioLocal({
  int id = 11,
  String nombre = 'Masaje relajante',
  bool permiteDirecta = true,
}) {
  return LocalServicio(
    id: id,
    idLocal: 3,
    idServicio: id * 10,
    servicio: Servicio.fromJson(<String, dynamic>{
      'id': id * 10,
      'nombre': nombre,
    }),
    createdAt: DateTime(2026, 1, 1),
    permiteReservaDirecta: permiteDirecta,
  );
}

/// Monta una pantalla a tamaño de móvil real (360×800 lógicos) y la deja lista.
///
/// `serviciosIniciales` va siempre con valor: en test el RPC no puede responder,
/// así que un descuido no debe acabar en una petición a Supabase.
Future<void> _montar(WidgetTester tester, Widget pantalla) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: pantalla));
  await tester.pump();
}

/// Degradados lineales montados en pantalla, en orden de árbol.
///
/// Se leen del render, no del código: si alguien cambia el degradado de la
/// cabecera, esto se pone rojo.
List<List<Color>> _degradados(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .map((d) => d.decoration)
    .whereType<BoxDecoration>()
    .map((d) => d.gradient)
    .whereType<LinearGradient>()
    .map((g) => g.colors)
    .toList();

void main() {
  group('FichaLocal: normalización de los datos', () {
    test('desdeCampana pone el local de nombre y la campaña debajo', () {
      final ficha = FichaLocal.desdeCampana(
        _campana(
          localFoto: 'https://cdn.test/local.jpg',
          imageUrl: 'https://cdn.test/marca.jpg',
        ),
      );

      // El nombre grande es el del establecimiento; el titular de la campaña va
      // en la segunda línea.
      expect(ficha.nombre, 'Spa Aurora');
      expect(ficha.titular, 'Relájate este mes');
      expect(ficha.subtitulo, 'Masajes con descuento');
      expect(ficha.idLocal, 7);
      expect(ficha.destacado, isTrue);

      // Textos recortados: la ficha no debe pintar espacios sobrantes.
      expect(ficha.descripcion, 'Un spa de barrio con 20 años de historia.');
      expect(ficha.descripcionDestacada, 'Temporada de spa: reserva y ahorra.');
      expect(ficha.direccion, 'Calle 12 #45');
      expect(ficha.ubicacion, 'Villa Clara, Cuba');
      expect(ficha.horarioTexto, '9:00 - 18:00');
      expect(ficha.entidad, 'Entidad Aurora');
      expect(ficha.entidadTelefono, '555-0101');

      // La foto del local manda sobre la de la campaña (misma regla que el
      // carrusel del Home).
      expect(ficha.foto, 'https://cdn.test/local.jpg');

      expect(ficha.icono, 'spa');
      expect(ficha.colorInicio, '#4F5C8B');
      expect(ficha.colorFin, '#1FA8B8');
      expect(ficha.hasta, DateTime.utc(2026, 12, 31));

      // Una campaña no trae reseñas: no se le supone valoración al local.
      expect(ficha.tieneValoracion, isFalse);
      expect(ficha.totalServicios, isNull);
    });

    test('desdeCampana sin local usa el título y el subtítulo', () {
      final ficha = FichaLocal.desdeCampana(
        _campana(
          local: null,
          titulo: 'Semana de la entidad',
          subtitulo: 'Todo con 15% off',
          localProvincia: null,
          localPais: null,
        ),
      );

      expect(ficha.nombre, 'Semana de la entidad');
      expect(ficha.titular, 'Todo con 15% off');
      expect(ficha.idLocal, isNull);
      expect(ficha.ubicacion, isNull);
      expect(ficha.destacado, isTrue);
    });

    test('desdeEstablecimiento trae valoración y número de servicios', () {
      final ficha = FichaLocal.desdeEstablecimiento(
        _establecimiento(totalServicios: 5, totalResenas: 12, rating: 4.75),
      );

      expect(ficha.nombre, 'Bar La Terraza');
      expect(ficha.titular, 'Entidad Terraza');
      expect(ficha.idLocal, 3);
      expect(ficha.ubicacion, 'La Habana, Cuba');
      expect(ficha.tieneValoracion, isTrue);
      expect(ficha.rating, 4.75);
      expect(ficha.totalResenas, 12);
      expect(ficha.totalServicios, 5);

      // Nada de campaña: sin sello patrocinado, sin degradado de campaña.
      expect(ficha.destacado, isFalse);
      expect(ficha.colorInicio, isNull);
      expect(ficha.colorFin, isNull);
      expect(ficha.descripcionDestacada, isNull);
      expect(ficha.hasta, isNull);
    });

    test('sin reseñas no hay valoración', () {
      final ficha = FichaLocal.desdeEstablecimiento(
        _establecimiento(totalResenas: 0, rating: null),
      );

      expect(ficha.tieneValoracion, isFalse);
    });
  });

  group('FichaLocalScreen: modo espacio patrocinado', () {
    testWidgets('pinta sello, degradado y bloque de campaña', (tester) async {
      final campana = _campana();
      await _montar(
        tester,
        FichaLocalScreen(
          ficha: FichaLocal.desdeCampana(campana),
          campana: campana,
          serviciosIniciales: const <LocalServicio>[],
        ),
      );
      expect(tester.takeException(), isNull);

      // Sello y segunda línea.
      expect(find.text('ESPACIO PATROCINADO'), findsOneWidget);
      expect(find.text('ESTABLECIMIENTO'), findsNothing);
      expect(find.text('Spa Aurora'), findsOneWidget);
      expect(find.text('Relájate este mes'), findsOneWidget);

      // Bloque de campaña con su vigencia.
      expect(find.text('DESTACADO DEL MOMENTO'), findsOneWidget);
      expect(find.text('Temporada de spa: reserva y ahorra.'), findsOneWidget);
      expect(find.text('Vigente hasta 31/12/2026'), findsOneWidget);

      // Datos reales del local: chips, «Sobre» y contacto.
      expect(find.text('Villa Clara, Cuba'), findsWidgets);
      expect(find.text('9:00 - 18:00'), findsOneWidget);
      expect(find.text('Sobre Spa Aurora'), findsOneWidget);
      expect(find.text('Entidad Aurora'), findsOneWidget);
      expect(find.text('555-0101'), findsOneWidget);
      expect(
        find.text('Lo que puedes reservar en Spa Aurora.'),
        findsOneWidget,
      );

      // El degradado de la cabecera (y del bloque destacado) es el de la campaña.
      expect(
        _degradados(tester),
        contains(equals(<Color>[_campanaInicio, _campanaFin])),
      );
      expect(
        _degradados(tester),
        isNot(
          contains(equals(<Color>[AppTheme.primaryDark, AppTheme.primary])),
        ),
      );

      // Sin servicios cargados manda el estado vacío de siempre.
      expect(find.text('Todavía no hay servicios publicados'), findsOneWidget);

      // El ancla del tutorial existe una sola vez y sobre el encabezado.
      final ancla = tester.widget<TutorialAnchor>(find.byType(TutorialAnchor));
      expect(ancla.id, 'ficha_local_servicios');
      expect(find.text('Servicios disponibles'), findsOneWidget);
    });
  });

  group('FichaLocalScreen: modo establecimiento', () {
    testWidgets('pinta sello propio y valoración, sin nada de campaña', (
      tester,
    ) async {
      await _montar(
        tester,
        FichaLocalScreen(
          ficha: FichaLocal.desdeEstablecimiento(
            // 4.6 y no un valor con empate a media estrella: así el 1 decimal
            // del chip es el mismo en cualquier plataforma.
            _establecimiento(totalResenas: 12, rating: 4.6),
          ),
          serviciosIniciales: const <LocalServicio>[],
        ),
      );
      expect(tester.takeException(), isNull);

      expect(find.text('ESTABLECIMIENTO'), findsOneWidget);

      // Sin campaña no se anuncia NADA de campaña.
      expect(find.text('ESPACIO PATROCINADO'), findsNothing);
      expect(find.text('DESTACADO DEL MOMENTO'), findsNothing);
      expect(find.textContaining('Vigente hasta'), findsNothing);

      // Degradado de marca.
      expect(
        _degradados(tester),
        contains(equals(<Color>[AppTheme.primaryDark, AppTheme.primary])),
      );
      expect(
        _degradados(tester),
        isNot(contains(equals(<Color>[_campanaInicio, _campanaFin]))),
      );

      // Valoración real, con sus estrellas y su número de reseñas.
      expect(find.byType(Estrellas), findsOneWidget);
      expect(find.text('4.6 (12 reseñas)'), findsOneWidget);

      // Contacto y estado vacío. La entidad sale dos veces: como segunda línea
      // de la cabecera (es el titular del local) y en la fila «Publica».
      expect(find.text('Sobre Bar La Terraza'), findsOneWidget);
      expect(find.text('Entidad Terraza'), findsWidgets);
      expect(find.text('Todavía no hay servicios publicados'), findsOneWidget);
      expect(
        find.text('Lo que puedes reservar en Bar La Terraza.'),
        findsOneWidget,
      );
    });

    testWidgets('sin reseñas no pinta estrellas ni un «0.0»', (tester) async {
      await _montar(
        tester,
        FichaLocalScreen(
          ficha: FichaLocal.desdeEstablecimiento(
            _establecimiento(totalResenas: 0, rating: null),
          ),
          serviciosIniciales: const <LocalServicio>[],
        ),
      );
      expect(tester.takeException(), isNull);

      expect(find.byType(Estrellas), findsNothing);
      expect(find.textContaining('reseña'), findsNothing);
      expect(find.textContaining('0.0'), findsNothing);
      // El chip de servicios tampoco aparece si el local no tiene ninguno.
      expect(find.textContaining('servicios disponibles'), findsNothing);
    });

    testWidgets('lista los servicios reales que se le inyectan', (
      tester,
    ) async {
      await _montar(
        tester,
        FichaLocalScreen(
          ficha: FichaLocal.desdeEstablecimiento(
            _establecimiento(totalServicios: 1),
          ),
          serviciosIniciales: <LocalServicio>[_servicioLocal()],
        ),
      );
      expect(tester.takeException(), isNull);

      expect(find.text('Masaje relajante'), findsOneWidget);
      expect(find.text('Reserva directa'), findsOneWidget);
      expect(find.text('1 servicio disponible'), findsOneWidget);
      expect(find.text('Todavía no hay servicios publicados'), findsNothing);
    });
  });

  group('EspacioPatrocinadoScreen: envoltorio', () {
    testWidgets('abre la misma ficha en modo patrocinado', (tester) async {
      // La firma pública es la de siempre: si cambiara, esto no compilaría.
      await _montar(tester, EspacioPatrocinadoScreen(campana: _campana()));

      // La cabecera de campaña se pinta aunque los servicios aún no hayan
      // llegado (esta ruta sí consulta el RPC; lo que se comprueba aquí es el
      // enrutado del envoltorio, que es lo que no puede cambiar).
      expect(find.text('ESPACIO PATROCINADO'), findsOneWidget);
      expect(find.text('DESTACADO DEL MOMENTO'), findsOneWidget);
      expect(find.text('Spa Aurora'), findsOneWidget);
      expect(
        _degradados(tester),
        contains(equals(<Color>[_campanaInicio, _campanaFin])),
      );
    });
  });
}
