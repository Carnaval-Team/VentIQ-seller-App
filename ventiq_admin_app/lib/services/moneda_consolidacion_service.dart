import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Moneda en la que el admin consolida las ventas de una tienda.
///
/// No la elige quien mira la pantalla: la impone la tienda con
/// `forzar_moneda_venta` + `moneda_venta_forzada`, y cuando no fuerza nada se
/// consolida en CUP. Quien resuelve las dos cosas —y la tasa— es el backend
/// (`fn_moneda_consolidacion`); aquí solo se transporta lo que ya resolvió, sin
/// volver a decidir ninguna divisa.
class MonedaConsolidacion {
  const MonedaConsolidacion({
    required this.moneda,
    required this.tasaCup,
    required this.esBase,
  });

  /// Código ISO de la divisa de consolidación (`CUP` por defecto).
  final String moneda;

  /// Multiplicador **CUP → [moneda]**: `importeMoneda = importeCup * tasaCup`.
  /// Vale `1` cuando se consolida en CUP.
  final double tasaCup;

  /// `true` cuando el backend se quedó en el caso base (CUP con tasa 1) en vez
  /// de una divisa forzada con tasa propia. Es informativo y **no** se deduce de
  /// [moneda]: la decisión la toma el RPC y aquí solo se refleja.
  final bool esBase;

  /// Caso base: CUP sin conversión.
  ///
  /// Es con lo que arranca el servicio y a lo que cae ante cualquier fallo, que
  /// es exactamente lo que la pantalla muestra hoy sin esta funcionalidad.
  static const MonedaConsolidacion cup = MonedaConsolidacion(
    moneda: 'CUP',
    tasaCup: 1,
    esBase: true,
  );

  @override
  String toString() =>
      'MonedaConsolidacion($moneda, tasaCup: $tasaCup, esBase: $esBase)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MonedaConsolidacion &&
          other.moneda == moneda &&
          other.tasaCup == tasaCup &&
          other.esBase == esBase;

  @override
  int get hashCode => Object.hash(moneda, tasaCup, esBase);
}

/// Moneda de consolidación del admin, resuelta por el backend **por tienda**.
///
/// En Ventas los importes se totalizan en una sola divisa; cuál es esa divisa lo
/// decide la configuración de la tienda y `fn_moneda_consolidacion` la devuelve
/// junto con su tasa. Este servicio la cachea por tienda y ofrece las tres
/// operaciones que la UI necesita —[convertir], [formatear] y [actual]—
/// **síncronas**, porque se usan dentro de `build()` y ahí no se puede esperar a
/// la red.
///
/// Fail-safe en todo el camino: si la RPC falla, no está desplegada o devuelve
/// algo inservible, el resultado es CUP con tasa 1. Nunca se deja el formateador
/// apuntando a una divisa que no se puede convertir.
class MonedaConsolidacionService {
  static final SupabaseClient _supabase = Supabase.instance.client;

  /// Mismo formateo que `_formatCurrency` de `sales_screen.dart`, que es el que
  /// ya usa la pestaña «Por moneda». Reutilizarlo es lo que garantiza que una
  /// tienda que consolida en CUP siga viendo exactamente el texto de hoy.
  static final NumberFormat _formatoMoneda = NumberFormat.currency(
    locale: 'es',
    symbol: '\$',
  );

  static const String _rpc = 'fn_moneda_consolidacion';

  /// Resuelto por tienda: la consulta se paga una vez por sesión.
  static final Map<int, MonedaConsolidacion> _cache =
      <int, MonedaConsolidacion>{};

  /// Consultas en vuelo, para que dos sitios que piden la misma tienda a la vez
  /// (la pestaña y el bloque compartido de «Tiempo Real» lo hacen) no dupliquen
  /// la llamada.
  static final Map<int, Future<MonedaConsolidacion>> _enVuelo =
      <int, Future<MonedaConsolidacion>>{};

  /// Se incrementa en [limpiar]. Una consulta que ya estaba en vuelo no puede
  /// cambiar la divisa vigente después de un cambio de tienda: su resultado
  /// llegaría tarde y pintaría los importes en la divisa de la tienda anterior.
  static int _generacion = 0;

  static MonedaConsolidacion _actual = MonedaConsolidacion.cup;

  /// Moneda de consolidación vigente. CUP/1/true hasta que [cargar] resuelva.
  static MonedaConsolidacion get actual => _actual;

  /// Resuelve (y cachea) la moneda de consolidación de [idTienda].
  ///
  /// **Nunca lanza.** Si la RPC no está desplegada, falla o no devuelve fila, se
  /// deja el caso base y se registra el motivo. El fallo no se cachea, así que un
  /// reintento posterior vuelve a preguntar al backend en vez de arrastrar el CUP
  /// de un error de red durante toda la sesión.
  static Future<MonedaConsolidacion> cargar(int idTienda) {
    final cacheada = _cache[idTienda];
    if (cacheada != null) {
      // Leer la caché también fija la divisa vigente: `actual` es siempre la
      // última tienda consultada.
      _actual = cacheada;
      return Future.value(cacheada);
    }
    return _enVuelo.putIfAbsent(
      idTienda,
      () => _consultar(idTienda, _generacion),
    );
  }

  /// Convierte un importe **en CUP** a la moneda de consolidación vigente.
  static double convertir(double importeCup) => importeCup * _actual.tasaCup;

  /// Formatea un importe **en CUP** en la moneda de consolidación vigente.
  ///
  /// [conCodigo] añade el código ISO al lado. **Por defecto solo cuando la
  /// tienda consolida en una divisa que no es la base**: así el texto de una
  /// tienda normal (CUP) queda byte a byte como estaba —`$45.000,00`, sin
  /// código— y en cambio una tienda que fuerza USD sí lo lleva, que es donde
  /// hace falta: un `$` suelto no distingue CUP de USD y esas columnas no se
  /// pueden sumar entre sí.
  static String formatear(double importeCup, {bool? conCodigo}) {
    final conCodigoEfectivo = conCodigo ?? !_actual.esBase;
    final texto = _formatoMoneda.format(convertir(importeCup));
    return conCodigoEfectivo ? '$texto ${_actual.moneda}' : texto;
  }

  /// Vuelve al caso base y olvida lo cacheado.
  ///
  /// Para el cambio de tienda y el logout: el valor cacheado deja de ser el
  /// correcto y seguir usándolo mostraría los importes en la divisa de la tienda
  /// anterior.
  static void limpiar() {
    _generacion++;
    _cache.clear();
    _enVuelo.clear();
    _actual = MonedaConsolidacion.cup;
  }

  static Future<MonedaConsolidacion> _consultar(
    int idTienda,
    int generacion,
  ) async {
    try {
      final response = await _supabase.rpc(
        _rpc,
        params: {'p_id_tienda': idTienda},
      );

      final resuelta = _parsear(response);
      if (resuelta == null) {
        return _degradar(
          generacion,
          'la RPC no devolvió una fila utilizable para la tienda $idTienda',
        );
      }

      // El valor cacheado sí vale para su tienda aunque la consulta haya
      // quedado obsoleta; lo que no puede es cambiar la divisa vigente.
      _cache[idTienda] = resuelta;
      if (generacion == _generacion) _actual = resuelta;
      return resuelta;
    } catch (e) {
      return _degradar(generacion, e.toString());
    } finally {
      // Solo retira su propia entrada: tras un [limpiar] puede haber ya otra
      // consulta en vuelo para la misma tienda y no es esta la que debe borrarla.
      if (generacion == _generacion) _enVuelo.remove(idTienda);
    }
  }

  /// Deja el caso base, lo registra y **no** cachea el fallo.
  static MonedaConsolidacion _degradar(int generacion, String motivo) {
    if (generacion == _generacion) _actual = MonedaConsolidacion.cup;
    print(
      '⚠️ [MonedaConsolidacionService] No se pudo resolver la moneda de '
      'consolidación ($motivo). Se consolida en ${MonedaConsolidacion.cup.moneda}.',
    );
    return MonedaConsolidacion.cup;
  }

  /// Normaliza la fila de `fn_moneda_consolidacion`.
  ///
  /// Devuelve `null` tanto si no hay fila como si la que vino no se puede usar:
  /// las dos cosas significan lo mismo para el llamador —no se pudo resolver— y
  /// ninguna de las dos se cachea.
  static MonedaConsolidacion? _parsear(dynamic response) {
    final Map<String, dynamic> fila;
    if (response is List) {
      if (response.isEmpty || response.first is! Map) return null;
      fila = Map<String, dynamic>.from(response.first as Map);
    } else if (response is Map) {
      // `returns table` llega como lista; se acepta el mapa suelto por si el
      // cliente cambia de forma y así el fallo no depende de eso.
      fila = Map<String, dynamic>.from(response);
    } else {
      return null;
    }

    final moneda = (fila['moneda'] ?? '').toString().trim().toUpperCase();
    final tasa = _asDouble(fila['tasa_cup']);

    // Sin divisa o sin una tasa positiva no se cambia de divisa: multiplicar por
    // 0 borraría los importes de la pantalla y una divisa sin tasa no se puede
    // convertir. Es la misma regla que aplica el SQL («solo se cambia de moneda
    // si la tasa se pudo resolver»); aquí se resuelve igual, cayendo al caso base.
    if (moneda.isEmpty || tasa <= 0) return null;

    final esBase = fila['es_base'];

    return MonedaConsolidacion(
      moneda: moneda,
      tasaCup: tasa,
      // `es_base` viaja como `boolean`; si no viene se asume el caso base.
      esBase: esBase is bool ? esBase : MonedaConsolidacion.cup.esBase,
    );
  }

  /// `numeric` de Postgres llega como int, double o texto según cómo lo
  /// serialice PostgREST: se acepta cualquiera en vez de asumir un subtipo.
  static double _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }
}
