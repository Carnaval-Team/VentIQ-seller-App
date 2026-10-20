import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/wapi_envio_log.dart';
import 'package:ventiq_admin_app/models/wapi_envio_tanda.dart';
import 'package:ventiq_admin_app/widgets/wapi_envio_tanda_card.dart';

/// Pruebas de la tarjeta de tanda: lo que el cliente final ve cuando un envío
/// queda a medias. Lo importante aquí es que **se pueda reintentar sin buscar**
/// y que el motivo esté en castellano.
///
/// OJO: estas tarjetas animan en bucle (parpadeo del botón), así que hay que
/// usar `pump()` y nunca `pumpAndSettle()`.
void main() {
  WapiEnvioLog log(
    int id,
    WapiEnvioEstado estado, {
    String? code,
    String? msg,
  }) =>
      WapiEnvioLog(
        id: id,
        idTienda: 177,
        idSesion: 22,
        idProducto: 100 + id,
        chatId: '120363000000@g.us',
        tipoEnvio: 'manual',
        estado: estado,
        errorCode: code,
        errorMessage: msg,
        sentAt: estado == WapiEnvioEstado.enviado ? DateTime(2026, 10, 14, 12) : null,
        createdAt: DateTime(2026, 10, 14, 11),
      );

  WapiEnvioTanda tanda(List<WapiEnvioLog> logs, {DateTime? ultimaActividad}) =>
      WapiEnvioTanda(
        id: 't1',
        tipoEnvio: 'manual',
        idProgramacion: null,
        inicio: DateTime(2026, 10, 14, 11),
        // Hace una hora: por defecto la tanda se considera "interrumpida", no
        // "en curso" (el umbral de inactividad son 10 min).
        ultimaActividad: ultimaActividad ?? DateTime.now().subtract(
          const Duration(hours: 1),
        ),
        logs: logs,
      );

  Future<void> montar(
    WidgetTester tester,
    WapiEnvioTanda t, {
    Future<void> Function(WapiEnvioTanda)? onReanudar,
    Future<void> Function()? onReconectar,
  }) async {
    // Superficie alta: la tarjeta expandida no cabe en el 800x600 por defecto y
    // los taps sobre elementos fuera de la vista no llegan (hit test falla).
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WapiEnvioTandaCard(
              tanda: t,
              destacada: false,
              productoNombre: (id) => 'Producto $id',
              onReanudar: onReanudar ?? (_) async {},
              onReconectar: onReconectar,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('tanda interrumpida: el botón de reintentar se ve SIN expandir',
      (tester) async {
    var reanudada = false;
    await montar(
      tester,
      tanda([
        log(1, WapiEnvioEstado.enviado),
        log(2, WapiEnvioEstado.pendiente),
        log(3, WapiEnvioEstado.pendiente),
      ]),
      onReanudar: (_) async => reanudada = true,
    );

    // Ni un solo tap de expansión: la acción está a la vista.
    expect(find.text('Reintentar 2 mensajes'), findsOneWidget);
    expect(find.textContaining('sin despachar'), findsNothing); // detalle cerrado

    await tester.tap(find.text('Reintentar 2 mensajes'));
    await tester.pump();
    expect(reanudada, isTrue);
  });

  testWidgets('fallo de sesión: diagnóstico traducido y botón de reconectar',
      (tester) async {
    var reconectado = false;
    await montar(
      tester,
      tanda([
        log(1, WapiEnvioEstado.enviado),
        log(2, WapiEnvioEstado.fallido,
            code: 'HTTP_409',
            msg: 'Session is not connected. The WhatsApp client is not ready. '
                '(tras 3 intento(s))'),
        log(3, WapiEnvioEstado.fallido,
            code: 'HTTP_409',
            msg: 'Session is not connected. The WhatsApp client is not ready. '
                '(tras 3 intento(s))'),
      ]),
      onReconectar: () async => reconectado = true,
    );

    // El motivo en castellano, en la tarjeta y sin expandir.
    expect(find.textContaining('El bot se desconectó'), findsWidgets);
    // Y NUNCA el texto crudo del servidor.
    expect(find.textContaining('Session is not connected'), findsNothing);
    expect(find.textContaining('tras 3 intento'), findsNothing);

    // Como el origen es la sesión, se ofrece reconectar en la misma tarjeta.
    expect(find.text('Reconectar bot'), findsOneWidget);
    await tester.tap(find.text('Reconectar bot'));
    await tester.pump();
    expect(reconectado, isTrue);
  });

  testWidgets('sin callback de reconexión no se ofrece ese botón',
      (tester) async {
    await montar(
      tester,
      tanda([
        log(1, WapiEnvioEstado.fallido, code: 'HTTP_409', msg: 'not connected'),
      ]),
    );

    expect(find.textContaining('El bot se desconectó'), findsWidgets);
    expect(find.text('Reconectar bot'), findsNothing);
  });

  testWidgets('corte por tiempo: se explica que NO fue un fallo real',
      (tester) async {
    await montar(
      tester,
      tanda([
        log(1, WapiEnvioEstado.fallido, code: 'PRODUCT_TIMEOUT'),
        log(2, WapiEnvioEstado.fallido, code: 'PRODUCT_TIMEOUT'),
        log(3, WapiEnvioEstado.enviado),
      ]),
    );

    expect(
      find.textContaining('Se cortó por tiempo (no fue un error)'),
      findsWidgets,
    );
    expect(find.text('Reintentar 2 mensajes'), findsOneWidget);
  });

  testWidgets('tanda completada: no hay nada que reintentar', (tester) async {
    await montar(
      tester,
      tanda([log(1, WapiEnvioEstado.enviado), log(2, WapiEnvioEstado.enviado)]),
    );

    expect(find.textContaining('Reintentar'), findsNothing);
    expect(find.text('Completado'), findsOneWidget);
  });

  testWidgets('el detalle técnico está disponible pero no invade',
      (tester) async {
    await montar(
      tester,
      tanda([log(1, WapiEnvioEstado.fallido, code: 'HTTP_500', msg: 'Internal server error')]),
    );

    // Plegado por defecto: nada de ruido técnico a primera vista...
    expect(find.textContaining('HTTP_500'), findsNothing);
    // ...pero el diagnóstico humano sí está, sin necesidad de expandir.
    expect(find.textContaining('El servidor del bot falló'), findsWidgets);

    // Al expandir aparece la puerta al detalle técnico para soporte.
    await tester.tap(find.text('No se envió nada'));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Ver detalle técnico'), findsOneWidget);
    expect(find.textContaining('HTTP_500'), findsNothing);
  });
}