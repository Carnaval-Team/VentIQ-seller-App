import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/wapi_session.dart';
import 'package:ventiq_admin_app/widgets/wapi_session_card.dart';

void main() {
  WapiSession session(
    WapiStatus status, {
    String? phone,
    String? lastErrorCode,
    String? lastErrorMessage,
    int recoveryAttempts = 0,
    bool watchdogEnabled = true,
  }) =>
      WapiSession(
        id: 22,
        idTienda: 1,
        nombre: 'Bot ventas',
        wapiSessionId: 'session-id',
        status: status,
        phoneNumber: phone,
        lastStatusAt: DateTime.now(),
        createdAt: DateTime(2026),
        lastErrorCode: lastErrorCode,
        lastErrorMessage: lastErrorMessage,
        recoveryAttempts: recoveryAttempts,
        watchdogEnabled: watchdogEnabled,
      );

  testWidgets('scanQr: botón directo para vincular el teléfono', (tester) async {
    String? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WapiSessionCard(
            session: session(WapiStatus.scanQr),
            onAction: (action) => selectedAction = action,
          ),
        ),
      ),
    );

    expect(find.text('Mostrar QR para vincular'), findsOneWidget);
    // El estado viene explicado, no solo con un punto de color.
    expect(find.textContaining('Falta vincular el teléfono'), findsOneWidget);
    await tester.tap(find.text('Mostrar QR para vincular'));
    expect(selectedAction, 'qr');
  });

  testWidgets('connected: no ofrece ninguna acción correctiva', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WapiSessionCard(
            session: session(WapiStatus.connected, phone: '5355555555'),
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Mostrar QR para vincular'), findsNothing);
    expect(find.text('Reconectar ahora'), findsNothing);
    expect(find.textContaining('Todo listo'), findsOneWidget);
  });

  testWidgets('disconnected: botón de reconectar + cuantifica la cola',
      (tester) async {
    String? selectedAction;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WapiSessionCard(
            session: session(
              WapiStatus.disconnected,
              phone: '5355555555',
              lastErrorCode: 'HTTP_409',
              lastErrorMessage:
                  'Session is not connected. The WhatsApp client is not ready.',
            ),
            mensajesEnEspera: 3,
            onAction: (action) => selectedAction = action,
          ),
        ),
      ),
    );

    expect(find.text('Reconectar ahora'), findsOneWidget);
    // El daño cuantificado: qué se pierde mientras siga caído.
    expect(find.textContaining('3 mensajes en cola no saldrán'), findsOneWidget);
    // Y el motivo traducido, no el texto crudo en inglés.
    expect(find.textContaining('el bot se desconectó'), findsOneWidget);
    expect(find.textContaining('Session is not connected'), findsNothing);

    await tester.tap(find.text('Reconectar ahora'));
    expect(selectedAction, 'restart');
  });

  testWidgets('sin teléfono vinculado lo dice explícitamente', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WapiSessionCard(
            session: session(WapiStatus.scanQr),
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Sin teléfono vinculado'), findsOneWidget);
  });

  testWidgets('avisa cuando la vigilancia automática está apagada',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WapiSessionCard(
            session: session(WapiStatus.disconnected, watchdogEnabled: false),
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(
      find.text('Vigilancia automática desactivada'),
      findsOneWidget,
    );
  });
}