// Guardia de compilación de la app completa del admin.
//
// Importar `main.dart` arrastra todas las rutas y pantallas (incluida la
// pestaña de categorías), así que este test detecta errores de compilación en
// cualquier pantalla. No monta la app: solo referencia la clase raíz, igual que
// `ventiq_app/test/home/app_compile_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ventiq_admin_app/main.dart';

void main() {
  test('la app completa compila', () {
    expect(const MyApp(), isA<Widget>());
  });
}