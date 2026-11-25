import 'politica_moneda.dart';
import 'politica_moneda_store.dart';
import '../services/user_preferences_service.dart';
import '../utils/price_utils.dart';

/// Qué le falta al TPV para vender offline (incl. multimoneda).
///
/// Los módulos de sync pueden marcar «OK» aunque tasas, monedas o la política
/// hayan fallado en silencio; este informe mira el **cache real** que usa el
/// cobro offline.
class OfflineReadiness {
  const OfflineReadiness(this.faltantes);

  /// Ítems faltantes, en español, listos para mostrar al usuario.
  final List<String> faltantes;

  bool get listo => faltantes.isEmpty;

  /// Texto listo para snackbar / diálogo.
  String get mensaje {
    if (listo) return 'Datos listos para trabajar offline.';
    return 'Falta para trabajar offline:\n'
        '${faltantes.map((f) => '• $f').join('\n')}';
  }

  static Future<OfflineReadiness> inspeccionar([
    UserPreferencesService? prefs,
  ]) async {
    final p = prefs ?? UserPreferencesService();
    final faltan = <String>[];

    final data = await p.getOfflineData();
    final hasCredentials = data?['credentials'] != null;
    final categories = data?['categories'];
    final hasCategories =
        categories is List && categories.isNotEmpty;
    final products = data?['products'];
    final hasProducts = products is Map && products.isNotEmpty;

    if (!hasCredentials) {
      faltan.add('Credenciales del vendedor (vuelve a sincronizar online)');
    }
    if (!hasCategories) {
      faltan.add('Categorías de productos');
    }
    if (!hasProducts) {
      faltan.add('Catálogo de productos');
    }

    final medios = await p.getPaymentMethodsOffline();
    if (medios.isEmpty) {
      faltan.add('Métodos de pago');
    }

    final monedas = await p.getMonedasTiendaCache();
    if (monedas.isEmpty) {
      faltan.add(
        'Monedas de la tienda (multimoneda). Sincroniza online y vuelve a intentar.',
      );
    } else {
      final tasas = await p.getTasasTiendaCache();
      final usdBackup = await p.getCambioCupUsd();
      for (final m in monedas) {
        final codigo = (m['codigo'] ?? '').toString().trim().toUpperCase();
        if (codigo.isEmpty || codigo == PriceUtils.baseCurrency) continue;
        final tasa = tasas[codigo] ?? 0;
        final okUsd =
            codigo == 'USD' && usdBackup > 0;
        if (tasa <= 0 && !okUsd) {
          faltan.add(
            'Tasa $codigo→${PriceUtils.baseCurrency} (necesaria para cobros offline)',
          );
        }
      }
    }

    faltan.addAll(await _faltantesPolitica(p));

    return OfflineReadiness(faltan);
  }

  static Future<List<String>> _faltantesPolitica(
    UserPreferencesService p,
  ) async {
    final cache = await p.getPoliticaMoneda();
    if (cache == null || cache['flag'] != true) return const [];

    final tienda = await p.getIdTienda();
    // Login offline no tiene sesión Supabase: usar userId restaurado en prefs.
    final usuario = await PoliticaMonedaStore.resolverUsuarioSesion(p);

    final estado = PoliticaMonedaEstado.interpretar(
      cache: cache,
      tiendaSesion: tienda,
      usuario: usuario,
    );
    if (estado.fase == PoliticaMonedaFase.lista) return const [];

    final detalle = <String>[];
    if (cache['denegada'] == true) {
      detalle.add(
        'Política de moneda denegada en este dispositivo (sincroniza online)',
      );
      return detalle;
    }
    final tiendaCache = cache['id_tienda'];
    if (tiendaCache is! int || tienda == null || tiendaCache != tienda) {
      detalle.add(
        'Política de moneda de otra tienda o sin tienda en sesión',
      );
    }
    final revision = cache['revision'];
    final constancia = cache['constancia'];
    final sujeto = constancia is Map
        ? constancia['uuid_sujeto']?.toString()
        : null;
    if (revision is! Map || constancia is! Map) {
      detalle.add(
        'Revisión/constancia de moneda por producto (sincroniza online con el mismo usuario)',
      );
    } else if (usuario == null) {
      detalle.add(
        'Sin usuario en sesión para validar la política de moneda',
      );
    } else if (sujeto == null || sujeto != usuario) {
      detalle.add(
        'Constancia de moneda de otro usuario: entra online con este usuario y sincroniza',
      );
    } else {
      detalle.add(
        'Política de moneda incompleta: sincroniza online y no cambies de usuario',
      );
    }
    return detalle;
  }
}
