/// Caché genérica con TTL (tiempo de vida) e inyección de reloj.
///
/// Se usa para no repetir la RPC `get_detalle_producto` al cerrar y reabrir el
/// mismo producto en un turno (R13 del plan: el listado entrega
/// `variantes: []`, así que el detalle siempre re-consulta si no hay caché).
///
/// El reloj es inyectable para poder probar la expiración sin `sleep`.
class TtlCache<K, V> {
  TtlCache({required this.ttl, DateTime Function()? reloj})
    : _ahora = reloj ?? DateTime.now;

  final Duration ttl;
  final DateTime Function() _ahora;
  final Map<K, _Entrada<V>> _entradas = <K, _Entrada<V>>{};

  /// Valor vigente, o `null` si no está o ya expiró.
  V? get(K clave) {
    final _Entrada<V>? entrada = _entradas[clave];
    if (entrada == null) return null;
    if (_ahora().difference(entrada.momento) >= ttl) {
      _entradas.remove(clave);
      return null;
    }
    return entrada.valor;
  }

  void put(K clave, V valor) {
    _entradas[clave] = _Entrada<V>(valor, _ahora());
  }

  void remove(K clave) => _entradas.remove(clave);

  /// Borra las entradas que cumplan el predicado.
  void removeWhere(bool Function(K clave, V valor) prueba) {
    _entradas.removeWhere(
      (K clave, _Entrada<V> entrada) => prueba(clave, entrada.valor),
    );
  }

  void clear() => _entradas.clear();

  int get length => _entradas.length;
}

class _Entrada<V> {
  const _Entrada(this.valor, this.momento);

  final V valor;
  final DateTime momento;
}
