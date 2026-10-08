/// Detección de "esta tabla/función todavía no existe en la base".
///
/// El agente no aplica migraciones: las pega el usuario. Eso significa que el
/// código tiene que funcionar **antes y después** de que se apliquen, sin
/// recompilar ni voltear banderas.
///
/// Distinguir "falta la migración" de "fallo de red" es lo que permite hacerlo
/// bien: ante una tabla ausente la UI oculta la función en silencio; ante un
/// corte de red mantiene el botón y ofrece reintentar.
library;

/// `true` si el error indica que la tabla o función consultada no existe.
///
/// [tabla] es opcional y solo sirve para reconocer el mensaje con nombre que
/// devuelve PostgREST ("Could not find the table 'flow.resena'").
bool esErrorDeEsquemaAusente(Object error, {String? tabla}) {
  final texto = error.toString();
  if (texto.contains('PGRST205') || texto.contains('42P01')) return true;
  // PGRST202: "Could not find the function public.x in the schema cache".
  if (texto.contains('PGRST202')) return true;
  if (tabla != null) {
    final patron = "Could not find the table 'flow.$tabla'";
    if (texto.contains(patron)) return true;
  }
  return false;
}

/// Compatibilidad: la detección usada por los favoritos.
bool esErrorDeTablaAusente(Object error) =>
    esErrorDeEsquemaAusente(error, tabla: 'favorito');