// Guardia de compilación del armazón del Home.
//
// Este test no monta la pantalla (montarla obliga a inicializar Supabase y
// cuelga el runner, ver §16 del plan), pero **importa y referencia**
// `HomeShellScreen`, así que el compilador tiene que compilar el archivo y todo
// su árbol de imports. Es la única verificación real que se ha demostrado
// capaz de detectar errores de compilación en el armazón:
//
//  * la Fase 3 se cerró con «128 tests en verde» mientras
//    `home_shell_screen.dart` no compilaba (un import olvidado), y
//  * `mcp__dart__analyze_files` respondió «No errors» sobre ese mismo archivo.
//
// Si alguien rompe un import del armazón, esto pasa a rojo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/screens/home_shell_screen.dart';

void main() {
  test('el armazón del Home compila y es un widget', () {
    expect(const HomeShellScreen(), isA<Widget>());
  });

  test('el saludo usa el nombre del trabajador logueado', () {
    expect(HomeShellScreen.saludoCon('perlanegraco'), 'Hola, perlanegraco');
    expect(HomeShellScreen.saludoCon('  perlanegraco  '), 'Hola, perlanegraco');
  });

  test('sin nombre guardado el saludo no se queda vacío', () {
    expect(HomeShellScreen.saludoCon(null), 'Hola 👋');
    expect(HomeShellScreen.saludoCon(''), 'Hola 👋');
    expect(HomeShellScreen.saludoCon('   '), 'Hola 👋');
  });

  test('«Solo con stock» no sustituye el lienzo del Home', () {
    // Regresión: el chip activaba el lienzo de resultados con la consulta
    // vacía y el Home aparecía en blanco con «no hay productos que coincidan».
    expect(HomeShellScreen.hayBusquedaCon(''), isFalse);
    expect(HomeShellScreen.hayBusquedaCon('   '), isFalse);
    expect(HomeShellScreen.hayBusquedaCon('arroz'), isTrue);
  });
}