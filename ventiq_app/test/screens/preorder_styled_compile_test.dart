// Guardia de compilación de la variante visual de la pre-orden.
//
// `PreorderScreenStyled` es una copia de `preorder_screen.dart`; si nadie la
// importa, `flutter test` no la compila y podría quedarse rota sin que la suite
// se entere (es lo que pasó con `session_refresh_service`, ver
// `test/services/session_refresh_compile_test.dart`).
//
// Construir el widget basta: el constructor es `const` y el `State` no se crea
// hasta que el widget se monta, así que aquí no se toca Supabase ni red.
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/screens/preorder_screen_styled.dart';

void main() {
  test('PreorderScreenStyled compila y se construye', () {
    const PreorderScreenStyled pantalla = PreorderScreenStyled();
    expect(pantalla, isA<PreorderScreenStyled>());
  });

  test('el interruptor de la variante está declarado', () {
    // Solo comprueba que el flag que usa main.dart existe y es un bool.
    expect(kPreorderStyled, isA<bool>());
  });
}