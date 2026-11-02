// Guardia de compilación de la app completa.
//
// Importar `main.dart` arrastra todas las rutas y pantallas, así que este test
// detecta errores de compilación en cualquier pantalla (el analizador ya se ha
// demostrado poco fiable en este repo). No monta la app: solo referencia la
// clase raíz.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_app/main.dart';

void main() {
  test('la app completa compila', () {
    expect(const MyApp(), isA<Widget>());
  });
}
