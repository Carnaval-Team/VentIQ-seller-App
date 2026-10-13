/// Detección de "esta tabla o función todavía no existe en la base".
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
/// [tabla] (opcional) restringe la detección a esa tabla concreta. Es lo que
/// evita que el fallo de una sección oculte otra: si el Home pregunta por
/// `resena` y el error habla de `favorito`, no es su problema.
///
/// Cuando se pasa [tabla] y el mensaje nombra una tabla **distinta**, devuelve
/// `false` aunque el código sea `PGRST205`: el error es real y hay que
/// mostrarlo, no ocultar la sección.
bool esErrorDeEsquemaAusente(Object error, {String? tabla}) {
  final texto = error.toString();

  if (tabla != null) {
    if (texto.contains("Could not find the table 'flow.$tabla'")) return true;
    // El mensaje nombra otra tabla (o una que no es la nuestra): no aplica.
    if (texto.contains('Could not find the table')) return false;
  }

  // Códigos genéricos, sin nombre de tabla:
  //   PGRST205 -> tabla ausente del schema cache
  //   PGRST202 -> función ausente del schema cache
  //   42P01    -> undefined_table de Postgres
  return texto.contains('PGRST205') ||
      texto.contains('PGRST202') ||
      texto.contains('42P01');
}

/// Detección usada por los favoritos, atada a `flow.favorito`.
bool esErrorDeTablaAusente(Object error) =>
    esErrorDeEsquemaAusente(error, tabla: 'favorito');
