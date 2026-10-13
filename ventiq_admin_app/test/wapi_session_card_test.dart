import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/models/wapi_session.dart';
import 'package:ventiq_admin_app/widgets/wapi_session_card.dart';

void main() {
  WapiSession session(WapiStatus status) => WapiSession(
    id: 22,
    idTienda: 1,
    nombre: 'Bot ventas',
    wapiSessionId: 'session-id',
    status: status,
    lastStatusAt: DateTime(2026),
    createdAt: DateTime(2026),
  );

  testWidgets('muestra un botón directo para abrir el QR en estado scanQr', (
    tester,
  ) async {
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

    expect(find.text('Mostrar QR'), findsOneWidget);
    await tester.tap(find.text('Mostrar QR'));
    expect(selectedAction, 'qr');
  });

  testWidgets('no muestra el botón directo si la sesión está conectada', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WapiSessionCard(
            session: session(WapiStatus.connected),
            onAction: (_) {},
          ),
        ),
      ),
    );

    expect(find.text('Mostrar QR'), findsNothing);
  });
}
