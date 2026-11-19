/// Ejecuta tareas de la misma clave una detrás de otra (nunca a la vez).
///
/// Claves distintas siguen en paralelo. Si una tarea falla, la siguiente de
/// la misma clave igual corre. Solo protege dentro de un isolate.
class CadenaPorClave {
  final Map<String, Future<void>> _colas = {};

  Future<T> ejecutar<T>(String clave, Future<T> Function() tarea) {
    final previa = _colas[clave] ?? Future<void>.value();
    final actual = previa.then((_) => tarea());
    final marca = actual.then<void>((_) {}, onError: (_) {});
    _colas[clave] = marca;
    return actual.whenComplete(() {
      if (identical(_colas[clave], marca)) _colas.remove(clave);
    });
  }

  bool get vacia => _colas.isEmpty;
}
