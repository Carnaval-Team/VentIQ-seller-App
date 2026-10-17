import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventtia_flow/models/entidad.dart';
import 'package:inventtia_flow/screens/admin/config_categorias_screen.dart';

/// La pantalla de Categorías del admin de entidad dejó de ser un CRUD: crear,
/// editar, eliminar y desactivar categorías es exclusivo del superadmin. Lo
/// único que queda es ocultar/mostrar categorías para los servicios de la
/// entidad.
///
/// Estas pruebas fijan esa frontera a nivel de UI: si alguien vuelve a poner el
/// botón de alta o el menú de borrado, fallan.
///
/// Se monta la pantalla **sin Supabase a propósito** (como
/// `coleccion_widgets_test`): las lecturas fallan y la pantalla tiene que
/// quedarse en pie mostrando el aviso, no romperse.
void main() {
  final entidad = Entidad(
    id: 7,
    denominacion: 'Salon Cejas',
    ownerUuid: 'uuid-owner',
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Future<void> montar(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ConfigCategoriasScreen(entidad: entidad)),
    );
    // Un pump para que arranque `_cargar` y otro para que llegue el fallo de la
    // lectura (sin Supabase inicializado) y se repinte con el aviso.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('no ofrece crear, editar ni eliminar categorías', (tester) async {
    await montar(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.more_vert), findsNothing);
    expect(find.textContaining('Nueva categoría'), findsNothing);
    expect(find.textContaining('Crear categoría'), findsNothing);
  });

  testWidgets('explica que la taxonomía la gestiona el superadmin', (
    tester,
  ) async {
    await montar(tester);

    expect(find.text('Categorías'), findsOneWidget);
    expect(find.text('Cómo se usan'), findsOneWidget);
    expect(
      find.textContaining('las crea, edita y desactiva el superadmin'),
      findsOneWidget,
    );
    expect(find.textContaining('Salon Cejas'), findsOneWidget);
  });

  testWidgets('sin Supabase avisa en vez de romperse', (tester) async {
    await montar(tester);

    expect(find.text('No se pudo leer'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
