import 'package:supabase_flutter/supabase_flutter.dart';

import 'politica_moneda.dart';
import '../services/user_preferences_service.dart';

class PoliticaMonedaStore {
  static final _prefs = UserPreferencesService();

  /// Auth de Supabase si hay sesión; si no (login offline), el userId en prefs.
  static Future<String?> resolverUsuarioSesion([
    UserPreferencesService? prefs,
  ]) async {
    try {
      final authId = Supabase.instance.client.auth.currentUser?.id;
      if (authId != null && authId.isNotEmpty) return authId;
    } catch (_) {}
    final p = prefs ?? _prefs;
    final cached = await p.getUserId();
    if (cached != null && cached.isNotEmpty) return cached;
    return null;
  }

  static Future<PoliticaMonedaEstado> leer() async {
    final cache = await _prefs.getPoliticaMoneda();
    final tienda = await _prefs.getIdTienda();
    final usuario = await resolverUsuarioSesion(_prefs);
    return PoliticaMonedaEstado.interpretar(
      cache: cache,
      tiendaSesion: tienda,
      usuario: usuario,
    );
  }
}
