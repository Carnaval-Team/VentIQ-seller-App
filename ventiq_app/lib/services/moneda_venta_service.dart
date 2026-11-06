import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/price_utils.dart';
import 'currency_service.dart';
import 'store_config_service.dart';
import 'user_preferences_service.dart';

/// Moneda de venta elegida por el usuario en **este teléfono**.
///
/// Decisión B de la Fase 3: la moneda elegida al entrar fija **la visualización
/// de los precios y la moneda de cobro por defecto** del checkout. Se guarda
/// localmente para sobrevivir a reinicios de la app y cambios de turno sin
/// obligar a volver a elegirla.
class MonedaVentaService {
  static const String _clave = 'moneda_venta';

  /// Clave en SharedPreferences (útil para limpiarla en el logout).
  static String get clave => _clave;

  /// Código guardado, o `null` si nunca se eligió.
  static Future<String?> leer() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_clave)?.trim().toUpperCase();
    if (raw == null || raw.isEmpty) return null;
    return RegExp(r'^[A-Z]{3}$').hasMatch(raw) ? raw : null;
  }

  static Future<void> guardar(String codigo) async {
    final limpio = codigo.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(limpio)) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, limpio);
  }

  static Future<void> limpiar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_clave);
    // Al cerrar sesión o cambiar de tienda el estado en memoria también se
    // resetea: si no, la siguiente pantalla seguiría formateando en la moneda
    // del usuario anterior y arrastraría el bloqueo de la tienda anterior.
    actual = PriceUtils.baseCurrency;
    tasas = const {};
    _forzada = null;
  }

  /// Resuelve la moneda efectiva para una tienda concreta.
  ///
  /// Garantiza que el resultado está en [disponibles] (divisas que la tienda
  /// acepta **y** tienen tasa). Si la guardada ya no sirve —la tienda la
  /// desactivó, o el vendedor cambió de tienda— cae a la moneda base y
  /// **persiste** el cambio, para no volver a resolverlo mal en la siguiente
  /// pantalla.
  static Future<String> resolver({required List<String> disponibles}) async {
    final guardada = await leer();
    final efectiva = resolverCodigo(
      guardada: guardada,
      disponibles: disponibles,
    );
    if (guardada != efectiva) await guardar(efectiva);
    return efectiva;
  }

  /// Lógica pura (sin SharedPreferences) para poder probarla.
  ///
  /// Reglas:
  /// 1. Si no hay divisas disponibles, la base.
  /// 2. Si la guardada está entre las disponibles, se respeta.
  /// 3. Si no, la base (CUP) cuando la tienda la acepte.
  /// 4. En último caso, la primera disponible.
  static String resolverCodigo({
    required String? guardada,
    required List<String> disponibles,
  }) {
    final base = PriceUtils.baseCurrency;
    if (disponibles.isEmpty) return base;

    final normalizadas = disponibles
        .map((c) => c.trim().toUpperCase())
        .where((c) => RegExp(r'^[A-Z]{3}$').hasMatch(c))
        .toList();
    if (normalizadas.isEmpty) return base;

    final guardadaNorm = guardada?.trim().toUpperCase();
    if (guardadaNorm != null && normalizadas.contains(guardadaNorm)) {
      return guardadaNorm;
    }
    if (normalizadas.contains(base)) return base;
    return normalizadas.first;
  }

  /// Divisa impuesta por la tienda **si se puede usar**, o `null`.
  ///
  /// Lógica pura (sin red ni disco) para poder probarla. La regla es la misma
  /// que la de [resolverCodigo]: la forzada solo vale si está entre las
  /// disponibles, que ya vienen filtradas por «la tienda la acepta **y** tiene
  /// tasa». Si no, se devuelve `null` y el llamador cae al comportamiento de
  /// siempre: una divisa inconvertible nunca debe quedar fijada, porque el
  /// cobro la rechazaría y el vendedor no tendría forma de salir de ella.
  static String? resolverForzada({
    required String? forzada,
    required List<String> disponibles,
  }) {
    final f = forzada?.trim().toUpperCase();
    if (f == null || !RegExp(r'^[A-Z]{3}$').hasMatch(f)) return null;

    final normalizadas = disponibles
        .map((c) => c.trim().toUpperCase())
        .where((c) => RegExp(r'^[A-Z]{3}$').hasMatch(c));
    return normalizadas.contains(f) ? f : null;
  }

  /// Factor de conversión de la moneda base (CUP) a [codigo].
  ///
  /// Los precios de catálogo están en CUP (`precio_venta_cup`), así que para
  /// mostrarlos en otra divisa hay que dividir por su tasa. Devuelve 0 si no
  /// hay tasa, para que el llamador decida (no se inventa una conversión).
  static double factorDesdeBase({
    required String codigo,
    required Map<String, double> tasas,
  }) {
    final c = codigo.trim().toUpperCase();
    if (c == PriceUtils.baseCurrency) return 1;
    final tasa = tasas[c] ?? 0;
    return tasa > 0 ? tasa : 0;
  }

  /// Convierte un importe en moneda base a [codigo]. Devuelve `null` si no hay
  /// tasa: nunca se inventa una conversión.
  static double? convertirDesdeBase(
    double importeBase, {
    required String codigo,
    required Map<String, double> tasas,
  }) {
    final factor = factorDesdeBase(codigo: codigo, tasas: tasas);
    if (factor <= 0) return null;
    return importeBase / factor;
  }

  /// Redondea **hacia arriba** a los decimales de la divisa.
  ///
  /// Decisión (b): al cobrar en una divisa distinta de la base el importe se
  /// redondea hacia arriba a los céntimos de esa divisa, de modo que el
  /// equivalente en moneda base nunca quede por debajo del total de la venta y
  /// `es_pagada` se cumpla siempre.
  ///
  /// El ruido de coma flotante se limpia antes del `ceil`: sin eso,
  /// `50.0 * 100 = 5000.000000000001` subiría un céntimo de más.
  static double redondearAlza(double importe, {int decimales = 2}) {
    if (importe <= 0) return 0;
    var factor = 1.0;
    for (var i = 0; i < decimales; i++) {
      factor *= 10;
    }
    final escalado = double.parse(
      (importe * factor).toStringAsFixed(6),
    );
    return escalado.ceilToDouble() / factor;
  }

  /// Importe a cobrar en [codigo] para cubrir [totalBase] (en moneda base) y
  /// su equivalente base resultante.
  ///
  /// Devuelve `null` si no hay tasa: no se inventa la conversión.
  /// Con la moneda base devuelve los dos importes iguales (sin redondeo).
  static ({double montoNativo, double equivalenteBase})? montoParaCubrir(
    double totalBase, {
    required String codigo,
    required Map<String, double> tasas,
    int decimales = 2,
  }) {
    final c = codigo.trim().toUpperCase();
    final factor = factorDesdeBase(codigo: c, tasas: tasas);
    if (factor <= 0) return null;

    if (c == PriceUtils.baseCurrency) {
      return (montoNativo: totalBase, equivalenteBase: totalBase);
    }

    final monto = redondearAlza(totalBase / factor, decimales: decimales);
    // El equivalente se recalcula desde el importe YA redondeado: así es
    // exactamente lo que la base guardará (monto × tasa) y no puede quedar
    // por debajo del total.
    return (montoNativo: monto, equivalenteBase: monto * factor);
  }

  // ==========================================================================
  // Estado en memoria para formateo SÍNCRONO
  // ==========================================================================
  //
  // Las pantallas formatean precios dentro de `build()`, donde no se puede
  // esperar a SharedPreferences ni a la red. Por eso la moneda activa y sus
  // tasas se cargan UNA vez (al entrar, al cambiar de tienda y al cambiar la
  // moneda) y quedan aquí.

  /// Moneda de venta activa en este momento.
  static String actual = PriceUtils.baseCurrency;

  /// Tasas a moneda base de las divisas disponibles.
  static Map<String, double> tasas = const {};

  /// Divisa que la tienda impone, o `null` si el vendedor puede elegir.
  ///
  /// Solo tiene valor cuando la forzada es **además** utilizable en esta tienda
  /// (aceptada y con tasa). Es la señal que usa la UI para bloquear el chip y
  /// el selector del cobro sin volver a leer la configuración.
  static String? _forzada;
  static String? get forzada => _forzada;

  /// ¿Hay más de una divisa utilizable? Si no, nada debe mostrar selector.
  static bool get hayVariasDivisas =>
      tasas.keys.any((c) => c != PriceUtils.baseCurrency);

  /// Fija el estado en memoria. Llamar al arrancar, al cambiar de tienda y al
  /// cambiar la moneda de venta.
  ///
  /// Si la moneda pedida no es válida o no tiene tasa, cae a la base: nunca se
  /// deja el formateador apuntando a una divisa que no se puede convertir.
  ///
  /// [forzada] marca la divisa como impuesta por la tienda, y solo se conserva
  /// si de verdad es la que quedó activa: si la validación cayó a la base, un
  /// chip bloqueado estaría mintiendo sobre la divisa del cobro.
  static void configurar({
    required String moneda,
    required Map<String, double> tasasDisponibles,
    String? forzada,
  }) {
    final m = moneda.trim().toUpperCase();
    tasas = Map<String, double>.unmodifiable(tasasDisponibles);
    final valida =
        RegExp(r'^[A-Z]{3}$').hasMatch(m) &&
        (m == PriceUtils.baseCurrency || (tasas[m] ?? 0) > 0);
    actual = valida ? m : PriceUtils.baseCurrency;

    final f = forzada?.trim().toUpperCase();
    _forzada = (valida && f != null && f == actual) ? f : null;
  }

  /// Formatea un importe **en moneda base** según la moneda de venta activa.
  ///
  /// Síncrono a propósito: se usa dentro de `build()`. Si no hay tasa para la
  /// moneda activa cae a la moneda base, en vez de mostrar un importe falso.
  ///
  /// Dos formatos, para no cambiar lo que ya ve una tienda de una sola divisa:
  ///
  /// * `conSimbolo: false` (por defecto) → `45.000,00 CUP` / `45,46 EUR`.
  ///   Es el formato explícito, sin ambigüedad de símbolo.
  /// * `conSimbolo: true` → `$45.000,00` en moneda base (idéntico a lo que
  ///   pintaban las pantallas antes de esta funcionalidad) y `45,46 EUR`
  ///   cuando hay una divisa activa (el símbolo `$` solo representa CUP).
  ///
  /// Así, una tienda que solo cobra en CUP **no ve ningún cambio visual** al
  /// migrar una pantalla: el texto sale byte a byte como antes.
  static String formatearPrecio(
    double importeBase, {
    int decimales = 2,
    bool conSimbolo = false,
  }) {
    final moneda = actual;
    final factor = moneda == PriceUtils.baseCurrency
        ? 1.0
        : (tasas[moneda] ?? 0.0);

    if (moneda == PriceUtils.baseCurrency || factor <= 0) {
      final numero = PriceUtils.formatAmount(importeBase, decimals: decimales);
      return conSimbolo
          ? '\$$numero'
          : '$numero ${PriceUtils.baseCurrency}';
    }
    return '${PriceUtils.formatAmount(importeBase / factor, decimals: decimales)} '
        '$moneda';
  }

  /// ¿La moneda de venta activa **no** es la base? Útil para las pantallas que
  /// quieren esconder un importe secundario (p. ej. el equivalente USD) cuando
  /// ya se está mostrando en esa misma divisa.
  static bool get enDivisaAlternativa =>
      actual != PriceUtils.baseCurrency && (tasas[actual] ?? 0) > 0;

  /// Importe convertido a la moneda de venta activa (sin formatear).
  /// Devuelve el mismo importe si la moneda activa es la base o no hay tasa.
  static double convertirPrecio(double importeBase) {
    final moneda = actual;
    if (moneda == PriceUtils.baseCurrency) return importeBase;
    final factor = tasas[moneda] ?? 0;
    return factor > 0 ? importeBase / factor : importeBase;
  }

  /// Carga TODO desde la tienda actual y deja el formateador listo.
  ///
  /// **Una sola llamada** en el arranque, al cambiar de tienda y tras un
  /// logout. Hace: divisas aceptadas por la tienda → tasas resueltas →
  /// moneda forzada por la tienda o, si no hay, la guardada (con caída segura
  /// a CUP) → estado en memoria.
  ///
  /// Devuelve la moneda efectiva aplicada. Ante cualquier fallo de red deja el
  /// formateador en CUP, que es el comportamiento de siempre.
  static Future<String> cargarDesdeTienda() async {
    try {
      final monedas = await CurrencyService.getMonedasTienda();
      final tasasTienda = await CurrencyService.getRatesForStore();

      final disponibles = monedas
          .map((m) => (m['codigo'] ?? '').toString().trim().toUpperCase())
          .where(
            (c) =>
                c.isNotEmpty &&
                (c == PriceUtils.baseCurrency || (tasasTienda[c] ?? 0) > 0),
          )
          .toList();

      return await aplicarParaTienda(
        disponibles: disponibles,
        tasasDisponibles: tasasTienda,
      );
    } catch (_) {
      // Sin conexión o sin catálogo: CUP, como antes de esta funcionalidad.
      configurar(moneda: PriceUtils.baseCurrency, tasasDisponibles: const {});
      return PriceUtils.baseCurrency;
    }
  }

  /// Resuelve e instala la moneda efectiva con lo que ya se cargó de la tienda.
  ///
  /// Punto único de decisión para el arranque del Home y para el chip: primero
  /// manda la divisa forzada por la tienda; si no hay —o no se puede usar—, se
  /// respeta la preferencia del teléfono. Así el formateador y la UI no pueden
  /// acabar en divisas distintas.
  static Future<String> aplicarParaTienda({
    required List<String> disponibles,
    required Map<String, double> tasasDisponibles,
  }) async {
    final forzadaTienda = await _leerForzada(disponibles: disponibles);
    if (forzadaTienda != null) {
      // La preferencia guardada del teléfono se ignora A PROPÓSITO mientras el
      // bloqueo esté activo, y **no** se pisa: si la tienda deja de forzar, el
      // vendedor recupera la divisa que había elegido.
      configurar(
        moneda: forzadaTienda,
        tasasDisponibles: tasasDisponibles,
        forzada: forzadaTienda,
      );
      return forzadaTienda;
    }

    final moneda = await resolver(disponibles: disponibles);
    configurar(moneda: moneda, tasasDisponibles: tasasDisponibles);
    return moneda;
  }

  /// Lee la configuración de la tienda y devuelve su divisa forzada solo si es
  /// utilizable; `null` en cualquier otro caso (no hay bloqueo, la divisa ya no
  /// sirve, o no se pudo leer la configuración).
  ///
  /// Un fallo al leer la tienda no puede tumbar la moneda de venta: se anota y
  /// se sigue con la preferencia del teléfono, que es lo que hacía la app antes
  /// de que existiera este bloqueo.
  static Future<String?> _leerForzada({
    required List<String> disponibles,
  }) async {
    try {
      final storeId = await UserPreferencesService().getIdTienda();
      if (storeId == null) return null;

      final config = await StoreConfigService.getMonedaVentaForzadaConfig(
        storeId,
      );
      if (!config.forzar) return null;

      final valida = resolverForzada(
        forzada: config.moneda,
        disponibles: disponibles,
      );
      if (valida == null) {
        debugPrint(
          '⚠️ La tienda fuerza ${config.moneda ?? '(sin divisa declarada)'}, '
          'pero no es una divisa aceptada con tasa: se usa la preferencia del '
          'teléfono.',
        );
      }
      return valida;
    } catch (e) {
      debugPrint('⚠️ No se pudo leer la moneda forzada de la tienda: $e');
      return null;
    }
  }
}