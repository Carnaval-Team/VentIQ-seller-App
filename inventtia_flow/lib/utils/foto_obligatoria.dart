/// Regla de la **foto obligatoria** del local y del servicio en el panel.
///
/// Es una decisión de producto **temporal**: mientras el catálogo se termina de
/// poblar, un local o un servicio sin foto no debería salir al cliente (el Home
/// pinta un degradado de relleno en su lugar). Vive aquí, y no dentro de cada
/// formulario, porque es la MISMA regla en cuatro sitios —crear y editar local,
/// crear y editar servicio— y porque así se puede probar sin montar la interfaz.
///
/// La regla no cambia entre crear y editar: **el registro tiene que quedar con
/// foto**. Por eso en editar basta con que ya tenga una; no se obliga a volver a
/// subirla (sería castigar al admin por un dato que ya está bien).
library;

/// `true` cuando el formulario ya tiene foto: una guardada o una recién elegida
/// y pendiente de subir.
bool tieneFoto({required String? fotoGuardada, required bool archivoElegido}) {
  if (archivoElegido) return true;
  return fotoGuardada != null && fotoGuardada.trim().isNotEmpty;
}

/// Mensaje del requisito incumplido, o `null` si la foto está.
///
/// [queEs] entra en el texto ('local' / 'servicio') para que el error diga de
/// qué campo se trata cuando el formulario enseña los dos a la vez.
String? errorFotoObligatoria({
  required String queEs,
  required String? fotoGuardada,
  required bool archivoElegido,
}) {
  if (tieneFoto(fotoGuardada: fotoGuardada, archivoElegido: archivoElegido)) {
    return null;
  }
  return 'La foto del $queEs es obligatoria';
}
