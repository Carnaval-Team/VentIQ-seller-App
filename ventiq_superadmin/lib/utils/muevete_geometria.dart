import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Utilidades de geometría para `muevete.zonas_tarifa.geometria`.
///
/// La columna guarda un **GeoJSON Polygon** con esta forma exacta:
///
/// ```json
/// {
///   "type": "Polygon",
///   "coordinates": [
///     [[-79.9645, 22.40689], [-79.9601, 22.40689],
///      [-79.9601, 22.41052], [-79.9645, 22.41052], [-79.9645, 22.40689]]
///   ]
/// }
/// ```
///
/// Reglas duras que respeta este archivo (verificadas contra la BD de pruebas):
///
/// * cada vértice es **[longitud, latitud]** — el índice 0 es `lon` y el 1 es
///   `lat`, igual que en `muevete.fn_punto_en_anillo`;
/// * `coordinates[0]` es el anillo exterior y `coordinates[1..]` son huecos o
///   exclusiones (`fn_punto_en_poligono` resta los que contienen el punto);
/// * los anillos se guardan **cerrados** (el primer punto repetido al final).
///
/// En memoria se trabaja siempre con anillos *abiertos* (`List<LatLng>` sin el
/// punto de cierre duplicado) para que el editor no tenga que distinguir entre
/// "el último vértice" y "el cierre"; el cierre se añade sólo al serializar.
class PoligonoZona {
  const PoligonoZona({required this.exterior, this.huecos = const []});

  /// Anillo exterior, sin el punto de cierre duplicado.
  final List<LatLng> exterior;

  /// Huecos/exclusiones, cada uno sin el punto de cierre duplicado.
  final List<List<LatLng>> huecos;

  /// Polígono vacío (zona recién creada, sin dibujar).
  static const PoligonoZona vacio = PoligonoZona(exterior: []);

  bool get vacioSinVertices => exterior.isEmpty;

  bool get tieneVerticesSuficientes => exterior.length >= 3;

  int get totalVertices =>
      exterior.length + huecos.fold<int>(0, (suma, h) => suma + h.length);

  /// Anillos no vacíos, útil para dibujar y para serializar.
  List<List<LatLng>> get anillos => [
    if (exterior.isNotEmpty) exterior,
    for (final hueco in huecos)
      if (hueco.isNotEmpty) hueco,
  ];

  // ───────────────────────────────────────────────────────────────────────
  // Lectura tolerante desde PostgREST
  // ───────────────────────────────────────────────────────────────────────

  /// Convierte lo que devuelve PostgREST (`Map`, texto JSON o `null`) en un
  /// polígono utilizable. Devuelve `null` si no hay geometría reconocible.
  ///
  /// Es tolerante a propósito: las filas del seed guardan anillos **abiertos**
  /// (4 vértices sin el cierre repetido), así que el cierre y los duplicados
  /// consecutivos se normalizan aquí.
  static PoligonoZona? desdeGeoJson(Object? valor) {
    Object? crudo = valor;
    if (crudo is String) {
      final texto = crudo.trim();
      if (texto.isEmpty) return null;
      try {
        crudo = jsonDecode(texto);
      } on FormatException {
        return null;
      }
    }
    if (crudo is! Map) return null;

    final tipo = crudo['type']?.toString().toLowerCase();
    if (tipo != null && tipo != 'polygon') return null;

    final coordinates = crudo['coordinates'];
    if (coordinates is! List || coordinates.isEmpty) return null;

    final anillos = <List<LatLng>>[];
    for (final anilloCrudo in coordinates) {
      final anillo = _leerAnillo(anilloCrudo);
      if (anillo != null && anillo.length >= 3) anillos.add(anillo);
    }
    if (anillos.isEmpty) return null;

    return PoligonoZona(
      exterior: anillos.first,
      huecos: anillos.skip(1).toList(growable: false),
    );
  }

  static List<LatLng>? _leerAnillo(Object? anilloCrudo) {
    if (anilloCrudo is! List) return null;
    final puntos = <LatLng>[];
    for (final par in anilloCrudo) {
      if (par is! List || par.length < 2) continue;
      final lon = _aDouble(par[0]);
      final lat = _aDouble(par[1]);
      if (lon == null || lat == null) continue;
      if (lon.abs() > 180 || lat.abs() > 90) continue;
      puntos.add(LatLng(lat, lon));
    }
    return _sinCierre(_sinDuplicadosConsecutivos(puntos));
  }

  // ───────────────────────────────────────────────────────────────────────
  // Escritura
  // ───────────────────────────────────────────────────────────────────────

  /// Serializa a GeoJSON listo para `jsonb`: `[lon, lat]`, 7 decimales y cada
  /// anillo cerrado repitiendo el primer punto al final.
  Map<String, dynamic> aGeoJson() {
    final coordenadas = <List<List<double>>>[];
    for (final anillo in anillos) {
      coordenadas.add(_anilloGeoJson(anillo));
    }
    return {'type': 'Polygon', 'coordinates': coordenadas};
  }

  static List<List<double>> _anilloGeoJson(List<LatLng> anillo) {
    final puntos = _sinCierre(_sinDuplicadosConsecutivos(anillo));
    if (puntos.isEmpty) return const [];
    final cerrado = [...puntos, puntos.first];
    return [
      for (final p in cerrado)
        [_redondear(p.longitude), _redondear(p.latitude)],
    ];
  }

  // ───────────────────────────────────────────────────────────────────────
  // Validación
  // ───────────────────────────────────────────────────────────────────────

  /// Devuelve el primer motivo de rechazo en español, o `null` si el polígono
  /// se puede guardar.
  String? validar() {
    if (exterior.isEmpty) {
      return 'Dibuja al menos 3 vértices en el mapa para formar el polígono.';
    }
    final errorExterior = validarAnillo(exterior, 'El polígono exterior');
    if (errorExterior != null) return errorExterior;

    for (var i = 0; i < huecos.length; i++) {
      final hueco = huecos[i];
      if (hueco.isEmpty) continue;
      final numero = i + 1;
      final errorHueco = validarAnillo(hueco, 'El hueco $numero');
      if (errorHueco != null) return errorHueco;
      if (!puntoEnAnillo(hueco.first, exterior)) {
        return 'El hueco $numero debe quedar dentro del polígono exterior.';
      }
      if (_huecoCruceExterior(hueco, exterior)) {
        return 'El hueco $numero se cruza con el borde del polígono exterior.';
      }
    }
    return null;
  }

  /// Valida un anillo suelto: ≥ 3 vértices distintos, sin duplicados
  /// consecutivos y sin auto-intersecciones (ignorando el vértice de cierre).
  static String? validarAnillo(List<LatLng> puntos, String etiqueta) {
    if (puntos.length < 3) {
      return '$etiqueta necesita al menos 3 vértices (tiene ${puntos.length}).';
    }

    // Duplicados consecutivos: se comparan las coordenadas redondeadas a 7
    // decimales para no arrastrar ruido de coma flotante.
    for (var i = 0; i < puntos.length; i++) {
      final actual = puntos[i];
      final siguiente = puntos[(i + 1) % puntos.length];
      if (_mismoPunto(actual, siguiente)) {
        return '$etiqueta tiene dos vértices consecutivos en el mismo punto.';
      }
    }

    final distintos = <String>{};
    for (final p in puntos) {
      distintos.add(_clave(p));
    }
    if (distintos.length < 3) {
      return '$etiqueta necesita al menos 3 vértices distintos.';
    }

    // Auto-intersección: se recorren todos los pares de segmentos que no
    // comparten vértice. El último segmento es el de cierre (n-1 → 0).
    final n = puntos.length;
    for (var i = 0; i < n; i++) {
      final a1 = puntos[i];
      final a2 = puntos[(i + 1) % n];
      for (var j = i + 2; j < n; j++) {
        if (i == 0 && j == n - 1) continue; // comparten el primer vértice
        final b1 = puntos[j];
        final b2 = puntos[(j + 1) % n];
        if (_segmentosSeCruzan(a1, a2, b1, b2)) {
          return '$etiqueta se cruza consigo mismo entre los vértices '
              '${i + 1} y ${j + 1}. Mueve o borra uno de esos vértices.';
        }
      }
    }
    return null;
  }

  // ───────────────────────────────────────────────────────────────────────
  // Métricas informativas
  // ───────────────────────────────────────────────────────────────────────

  /// Área aproximada en km² (exterior menos huecos), por exceso esférico.
  double get areaKm2 {
    if (!tieneVerticesSuficientes) return 0;
    var area = _areaAnilloKm2(exterior);
    for (final hueco in huecos) {
      area -= _areaAnilloKm2(hueco);
    }
    return area < 0 ? 0 : area;
  }

  double get perimetroKm {
    if (!tieneVerticesSuficientes) return 0;
    // `roundResult: false` evita que latlong2 redondee a km enteros.
    final distancia = const Distance(roundResult: false);
    var total = 0.0;
    final puntos = _sinCierre(exterior);
    for (var i = 0; i < puntos.length; i++) {
      total += distancia.as(
        LengthUnit.Kilometer,
        puntos[i],
        puntos[(i + 1) % puntos.length],
      );
    }
    return total;
  }

  /// Centroide aproximado (informativo) del anillo exterior.
  LatLng get centroide {
    if (exterior.isEmpty) {
      return LatLng(
        MueveteZonaGeometria.santaClaraLat,
        MueveteZonaGeometria.santaClaraLon,
      );
    }
    final puntos = _sinCierre(exterior);
    if (puntos.length < 3) return _promedio(puntos);

    var dobleArea = 0.0;
    var cx = 0.0;
    var cy = 0.0;
    for (var i = 0; i < puntos.length; i++) {
      final x1 = puntos[i].longitude;
      final y1 = puntos[i].latitude;
      final x2 = puntos[(i + 1) % puntos.length].longitude;
      final y2 = puntos[(i + 1) % puntos.length].latitude;
      final cruz = x1 * y2 - x2 * y1;
      dobleArea += cruz;
      cx += (x1 + x2) * cruz;
      cy += (y1 + y2) * cruz;
    }
    if (dobleArea.abs() < 1e-12) return _promedio(puntos);
    final area = dobleArea / 2;
    return LatLng(cy / (6 * area), cx / (6 * area));
  }

  // ───────────────────────────────────────────────────────────────────────
  // Geometría de apoyo (pública donde el editor la necesita)
  // ───────────────────────────────────────────────────────────────────────

  /// Ray-casting en [lon, lat], igual que `muevete.fn_punto_en_anillo`.
  static bool puntoEnAnillo(LatLng punto, List<LatLng> anillo) {
    final puntos = _sinCierre(anillo);
    if (puntos.length < 3) return false;
    var dentro = false;
    var j = puntos.length - 1;
    for (var i = 0; i < puntos.length; i++) {
      final xi = puntos[i].longitude;
      final yi = puntos[i].latitude;
      final xj = puntos[j].longitude;
      final yj = puntos[j].latitude;
      final corta = (yi > punto.latitude) != (yj > punto.latitude);
      if (!corta) {
        j = i;
        continue;
      }
      final denominador = yj - yi;
      if (denominador == 0) {
        j = i;
        continue;
      }
      final xInterseccion =
          (xj - xi) * (punto.latitude - yi) / denominador + xi;
      if (punto.longitude < xInterseccion) dentro = !dentro;
      j = i;
    }
    return dentro;
  }

  /// Elimina el punto de cierre si el anillo viene cerrado.
  static List<LatLng> _sinCierre(List<LatLng> puntos) {
    if (puntos.length > 1 && _puntosIguales(puntos.first, puntos.last)) {
      return puntos.sublist(0, puntos.length - 1);
    }
    return puntos;
  }

  static List<LatLng> _sinDuplicadosConsecutivos(List<LatLng> puntos) {
    final salida = <LatLng>[];
    for (final p in puntos) {
      if (salida.isEmpty || !_puntosIguales(salida.last, p)) salida.add(p);
    }
    return salida;
  }

  static bool _mismoPunto(LatLng a, LatLng b) => _puntosIguales(a, b);

  static bool _puntosIguales(LatLng a, LatLng b) =>
      (a.latitude - b.latitude).abs() < 1e-9 &&
      (a.longitude - b.longitude).abs() < 1e-9;

  static String _clave(LatLng p) =>
      '${_redondear(p.latitude)},${_redondear(p.longitude)}';

  static bool _huecoCruceExterior(List<LatLng> hueco, List<LatLng> exterior) {
    final a = _sinCierre(hueco);
    final b = _sinCierre(exterior);
    if (a.length < 3 || b.length < 3) return false;
    for (var i = 0; i < a.length; i++) {
      for (var j = 0; j < b.length; j++) {
        final cruce = _segmentosSeCruzan(
          a[i],
          a[(i + 1) % a.length],
          b[j],
          b[(j + 1) % b.length],
        );
        if (cruce) return true;
      }
    }
    return false;
  }

  // ─── Intersección de segmentos ────────────────────────────────────────

  /// `true` si los segmentos `p1-p2` y `q1-q2` se cortan o se tocan.
  static bool _segmentosSeCruzan(LatLng p1, LatLng p2, LatLng q1, LatLng q2) {
    final d1 = _orientacion(q1, q2, p1);
    final d2 = _orientacion(q1, q2, p2);
    final d3 = _orientacion(p1, p2, q1);
    final d4 = _orientacion(p1, p2, q2);

    final cruzan =
        ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) &&
        ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0));
    if (cruzan) return true;

    // Casos colineales: un extremo apoyado sobre el otro segmento.
    if (d1 == 0 && _enSegmento(q1, q2, p1)) return true;
    if (d2 == 0 && _enSegmento(q1, q2, p2)) return true;
    if (d3 == 0 && _enSegmento(p1, p2, q1)) return true;
    if (d4 == 0 && _enSegmento(p1, p2, q2)) return true;
    return false;
  }

  /// Signo del producto vectorial `(b - a) × (c - a)` con x = lon, y = lat.
  static int _orientacion(LatLng a, LatLng b, LatLng c) {
    final valor =
        (b.longitude - a.longitude) * (c.latitude - a.latitude) -
        (b.latitude - a.latitude) * (c.longitude - a.longitude);
    if (valor.abs() < 1e-12) return 0;
    return valor > 0 ? 1 : -1;
  }

  static bool _enSegmento(LatLng a, LatLng b, LatLng p) {
    final entreLon =
        p.longitude >= math.min(a.longitude, b.longitude) - 1e-12 &&
        p.longitude <= math.max(a.longitude, b.longitude) + 1e-12;
    final entreLat =
        p.latitude >= math.min(a.latitude, b.latitude) - 1e-12 &&
        p.latitude <= math.max(a.latitude, b.latitude) + 1e-12;
    return entreLon && entreLat;
  }

  // ─── Área / centroide ─────────────────────────────────────────────────

  static double _areaAnilloKm2(List<LatLng> anillo) {
    final puntos = _sinCierre(_sinDuplicadosConsecutivos(anillo));
    if (puntos.length < 3) return 0;
    var suma = 0.0;
    for (var i = 0; i < puntos.length; i++) {
      final p1 = puntos[i];
      final p2 = puntos[(i + 1) % puntos.length];
      // Exceso esférico: las longitudes deben ir en radianes.
      suma +=
          (_radianes(p2.longitude) - _radianes(p1.longitude)) *
          (2 +
              math.sin(_radianes(p1.latitude)) +
              math.sin(_radianes(p2.latitude)));
    }
    return (suma *
            MueveteZonaGeometria.radioTierraKm *
            MueveteZonaGeometria.radioTierraKm /
            2)
        .abs();
  }

  static double _radianes(double grados) => grados * math.pi / 180;

  static LatLng _promedio(List<LatLng> puntos) {
    if (puntos.isEmpty) {
      return LatLng(
        MueveteZonaGeometria.santaClaraLat,
        MueveteZonaGeometria.santaClaraLon,
      );
    }
    var lat = 0.0;
    var lon = 0.0;
    for (final p in puntos) {
      lat += p.latitude;
      lon += p.longitude;
    }
    return LatLng(lat / puntos.length, lon / puntos.length);
  }

  static double _redondear(double valor) =>
      (valor * 10000000).roundToDouble() / 10000000;

  static double? _aDouble(Object? valor) {
    if (valor == null) return null;
    if (valor is num) return valor.toDouble();
    return double.tryParse(valor.toString().replaceAll(',', '.'));
  }
}

/// Constantes compartidas por el editor y la lista de zonas.
class MueveteZonaGeometria {
  const MueveteZonaGeometria._();

  /// Radio medio terrestre (km) usado para el área aproximada.
  static const double radioTierraKm = 6371.0088;

  /// Centro de Santa Clara: encuadre inicial cuando la zona no tiene polígono.
  static const double santaClaraLat = 22.40689;
  static const double santaClaraLon = -79.96450;

  /// Plantilla de tiles de OpenStreetMap (misma que usa la app del cliente).
  static const String urlTilesOsm =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

  /// `22.40689, -79.96450` — formato de coordenada para la UI.
  static String formatearCoordenada(LatLng punto) =>
      '${punto.latitude.toStringAsFixed(5)}, '
      '${punto.longitude.toStringAsFixed(5)}';
}
