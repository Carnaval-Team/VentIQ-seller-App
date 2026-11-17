import 'package:supabase_flutter/supabase_flutter.dart';

import 'politica_moneda.dart';
import '../services/user_preferences_service.dart';

class PoliticaMonedaStore {
  static final _prefs = UserPreferencesService();

  static Future<PoliticaMonedaEstado> leer() async {
    final cache = await _prefs.getPoliticaMoneda();
    final tienda = await _prefs.getIdTienda();
    String? usuario;
    try {
      usuario = Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      usuario = null;
    }
    return PoliticaMonedaEstado.interpretar(
      cache: cache,
      tiendaSesion: tienda,
      usuario: usuario,
    );
  }
}
