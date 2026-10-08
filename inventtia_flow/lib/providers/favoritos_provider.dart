import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../services/favorito_service.dart';
import '../utils/esquema_pendiente.dart';

/// Estado global de los favoritos del cliente.
///
/// Mantiene en memoria el conjunto de `local_servicio.id` guardados, que es lo
/// que necesitan las tarjetas del Home para pintar el corazón sin consultar la
/// base por cada una. Se carga una vez al iniciar sesión y se refresca al
/// cambiar a la pestaña de favoritos.
///
/// Las escrituras son **optimistas**: el corazón cambia al instante y, si la
/// base falla, se revierte. Así el gesto no se siente lento.
class FavoritosProvider extends ChangeNotifier {
  final Set<int> _ids = <int>{};
  bool _cargando = false;
  bool _disponible = true;
  String? _uuid;
  StreamSubscription<AuthState>? _authSub;

  /// Ids de `local_servicio` guardados por el usuario actual.
  Set<int> get ids => Set.unmodifiable(_ids);

  int get total => _ids.length;

  bool get cargando => _cargando;

  /// `false` cuando la tabla `flow.favorito` todavía no existe (migración
  /// `25_favoritos.sql` sin aplicar). En ese caso la UI oculta el corazón en
  /// lugar de mostrar un botón que siempre falla.
  bool get disponible => _disponible;

  FavoritosProvider() {
    final inicial = AuthService.currentUserId;
    if (inicial != null) recargar();
    _authSub = AuthService.authStateChanges.listen((state) {
      final nuevo = state.session?.user.id;
      if (nuevo == null) {
        limpiar();
      } else if (nuevo != _uuid) {
        recargar();
      }
    });
  }

  bool estaGuardado(int idLocalServicio) => _ids.contains(idLocalServicio);

  void limpiar() {
    _uuid = null;
    _ids.clear();
    _cargando = false;
    notifyListeners();
  }

  Future<void> recargar() async {
    final uuid = AuthService.currentUserId;
    if (uuid == null) {
      limpiar();
      return;
    }
    _uuid = uuid;
    _cargando = true;
    notifyListeners();
    try {
      final ids = await FavoritoService.getIdsFavoritos(uuid);
      if (_uuid != uuid) return;
      _ids
        ..clear()
        ..addAll(ids);
      _disponible = true;
    } catch (e) {
      debugPrint('[flow] FavoritosProvider.recargar ERROR: $e');
      if (esErrorDeTablaAusente(e)) _disponible = false;
      _ids.clear();
    } finally {
      _cargando = false;
      notifyListeners();
    }
  }

  /// Alterna un favorito. Devuelve el estado resultante, o `null` si falló.
  Future<bool?> alternar(int idLocalServicio) async {
    final uuid = AuthService.currentUserId;
    if (uuid == null || !_disponible) return null;

    final estaba = _ids.contains(idLocalServicio);
    // Optimista: pinta ya.
    if (estaba) {
      _ids.remove(idLocalServicio);
    } else {
      _ids.add(idLocalServicio);
    }
    notifyListeners();

    try {
      final resultado = await FavoritoService.alternar(
        uuidUsuario: uuid,
        idLocalServicio: idLocalServicio,
        estaGuardado: estaba,
      );
      // Reconciliar con lo que confirmó la base.
      if (resultado) {
        _ids.add(idLocalServicio);
      } else {
        _ids.remove(idLocalServicio);
      }
      notifyListeners();
      return resultado;
    } catch (e) {
      debugPrint('[flow] FavoritosProvider.alternar ERROR: $e');
      // Revertir: la UI no debe quedarse mintiendo.
      if (estaba) {
        _ids.add(idLocalServicio);
      } else {
        _ids.remove(idLocalServicio);
      }
      if (esErrorDeTablaAusente(e)) _disponible = false;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
