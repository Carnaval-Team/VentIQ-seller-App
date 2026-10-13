import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/services/resena_service.dart';
import 'package:inventtia_flow/widgets/resenas.dart';
import 'package:inventtia_flow/widgets/tarjeta_resena_reciente.dart';

/// La tarjeta del carrusel "Lo que dicen los clientes" tiene medidas fijas
/// (250×178 en el Home), así que el riesgo real no es de lógica sino de orden y
/// de desborde: aquí se pinta de verdad y se comprueba el orden pedido (autor y
/// servicio arriba, comentario debajo y la nota en la esquina inferior derecha)
/// y que con textos largos ni la cabecera ni el comentario se salen.
void main() {
  const comentario =
      'Me atendieron a la hora exacta y el resultado quedó '
      'impecable. Repetiré sin dudarlo la próxima vez que venga a La Habana.';

  // Medidas de la tarjeta tal como la pinta el Home. La esquina del contenido no
  // es 250-13: el borde de 1px del `Border.all` también recorta, así que el
  // borde interior queda en 236×164.
  const ancho = 250.0;
  const alto = 178.0;
  const relleno = 13.0;
  const borde = 1.0;
  final esquinaDerecha = ancho - relleno - borde;
  final esquinaAbajo = alto - relleno - borde;

  Resena resena({
    int puntuacion = 4,
    String autor = 'Ana R.',
    String? servicio = 'Depilación de cejas',
    String? texto = comentario,
  }) => Resena(
    id: 1,
    puntuacion: puntuacion,
    autor: autor,
    servicio: servicio,
    comentario: texto,
  );

  Widget envolver(
    Widget child, {
    double conAncho = ancho,
    double conAlto = alto,
  }) => MaterialApp(
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: conAncho, height: conAlto, child: child),
      ),
    ),
  );

  testWidgets('autor y servicio arriba, comentario debajo y nota abajo a la '
      'derecha', (tester) async {
    await tester.pumpWidget(
      envolver(TarjetaResenaReciente(resena: resena(), onTap: () {})),
    );
    await tester.pump();

    final autor = tester.getRect(find.text('Ana R.'));
    final servicio = tester.getRect(find.text('Depilación de cejas'));
    final texto = tester.getRect(find.text(comentario));
    final estrellas = tester.getRect(find.byType(Estrellas));
    final nota = tester.getRect(find.text('4.0'));

    // Arriba: autor y, justo debajo suyo, el servicio.
    expect(autor.top, lessThan(texto.top));
    expect(servicio.top, greaterThanOrEqualTo(autor.bottom - 1));
    expect(servicio.bottom, lessThanOrEqualTo(texto.top));

    // Debajo: el comentario, y por debajo de él la nota.
    expect(estrellas.top, greaterThanOrEqualTo(texto.bottom - 1));
    expect(nota.top, greaterThanOrEqualTo(texto.bottom - 1));

    // Esquina inferior derecha: la fila de la nota acaba exactamente en el borde
    // del contenido de la tarjeta.
    final esquina = tester.getRect(find.byKey(TarjetaResenaReciente.claveNota));
    expect(esquina.right, closeTo(esquinaDerecha, 0.01));
    expect(esquina.bottom, closeTo(esquinaAbajo, 0.01));
    // La nota, a la derecha de las estrellas y dentro de la esquina.
    expect(nota.left, greaterThan(estrellas.right));
    expect(nota.right, lessThanOrEqualTo(esquinaDerecha));

    // Y la nota es la de la reseña, no un valor inventado.
    expect(
      tester.widget<Estrellas>(find.byType(Estrellas)).promedio,
      resena().puntuacion.toDouble(),
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('con autor, servicio y comentario largos no se desborda ni '
      'corta el texto', (tester) async {
    final largo =
        'Escribo una reseña bastante larga para que no quepa ni de '
        'lejos en el comentario, y así comprobar que se recorta con puntos '
        'suspensivos en vez de desbordar o quedar cortada por la mitad. Sigue '
        'el texto de relleno hasta pasarme bien de largo, y un poco más.';

    await tester.pumpWidget(
      envolver(
        TarjetaResenaReciente(
          resena: resena(
            autor: 'reserv@gmail.com R.',
            servicio: 'Depilación De Cejas Extendida Y Diseño',
            texto: largo,
          ),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    // La tarjeta conserva su tamaño y el comentario se recorta con puntos.
    expect(
      tester.getSize(find.byType(TarjetaResenaReciente)),
      const Size(ancho, alto),
    );
    final texto = tester.widget<Text>(find.text(largo));
    expect(texto.maxLines, 5);
    expect(texto.overflow, TextOverflow.ellipsis);

    // Y caben de verdad las 5 líneas: si el hueco fuera más corto, el texto
    // quedaría recortado a media altura (rect más bajo que 5 líneas).
    final rectTexto = tester.getRect(find.text(largo));
    expect(rectTexto.height, greaterThanOrEqualTo(5 * 12.5 * 1.4 - 1));
    final estrellas = tester.getRect(find.byType(Estrellas));
    expect(rectTexto.bottom, lessThanOrEqualTo(estrellas.top));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sin servicio ni comentario la tarjeta no deja huecos raros', (
    tester,
  ) async {
    await tester.pumpWidget(
      envolver(
        TarjetaResenaReciente(
          resena: resena(servicio: null, texto: null, puntuacion: 5),
          onTap: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Ana R.'), findsOneWidget);
    expect(find.text('5.0'), findsOneWidget);
    // Aunque falte el comentario, la nota sigue en su esquina.
    expect(
      tester.getRect(find.byKey(TarjetaResenaReciente.claveNota)).bottom,
      closeTo(esquinaAbajo, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tocar la tarjeta avisa al Home', (tester) async {
    var tocada = false;
    await tester.pumpWidget(
      envolver(
        TarjetaResenaReciente(resena: resena(), onTap: () => tocada = true),
      ),
    );
    await tester.pump();

    await tester.tap(find.byType(TarjetaResenaReciente));
    expect(tocada, isTrue);
  });
}
