import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi, sin, cos, atan2, sqrt;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../widgets/map_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Result
// ─────────────────────────────────────────────────────────────────────────────

class CargoLocationResult {
  final double latOrigen;
  final double lonOrigen;
  final String dirOrigen;
  final String? ciudadOrigen;
  final String? provinciaOrigen;
  final String? paisOrigen;

  final double latDestino;
  final double lonDestino;
  final String dirDestino;
  final String? ciudadDestino;
  final String? provinciaDestino;
  final String? paisDestino;
  final double? distanciaKm;

  const CargoLocationResult({
    required this.latOrigen,
    required this.lonOrigen,
    required this.dirOrigen,
    this.ciudadOrigen,
    this.provinciaOrigen,
    this.paisOrigen,
    required this.latDestino,
    required this.lonDestino,
    required this.dirDestino,
    this.ciudadDestino,
    this.provinciaDestino,
    this.paisDestino,
    this.distanciaKm,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

/// Full-screen cargo route picker: origin + destination via map tap or search.
/// Push and await a [CargoLocationResult?].
class CargoLocationPickerScreen extends StatefulWidget {
  /// Country name from user profile – used to bias Nominatim searches.
  final String? perfilPais;

  /// Province from user profile – used to bias the initial map center.
  final String? perfilProvincia;

  const CargoLocationPickerScreen({
    super.key,
    this.perfilPais,
    this.perfilProvincia,
  });

  @override
  State<CargoLocationPickerScreen> createState() =>
      _CargoLocationPickerScreenState();
}

class _CargoLocationPickerScreenState
    extends State<CargoLocationPickerScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _origenCtrl = TextEditingController();
  final TextEditingController _destinoCtrl = TextEditingController();

  // 'origin' | 'dest'
  String _activeField = 'origin';

  LatLng? _origenPoint;
  _GeoResult? _origenGeo;

  LatLng? _destinoPoint;
  _GeoResult? _destinoGeo;

  List<_NominatimResult> _suggestions = [];
  bool _loadingSuggestions = false;
  bool _resolving = false;
  bool _calculatingRoute = false;
  Timer? _debounce;

  double? _distanciaKm;
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _fitMap());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mapController.dispose();
    _origenCtrl.dispose();
    _destinoCtrl.dispose();
    super.dispose();
  }

  // ── Map helpers ────────────────────────────────────────────────────────────

  void _fitMap() {
    if (!mounted) return;
    if (_origenPoint != null && _destinoPoint != null) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints([_origenPoint!, _destinoPoint!]),
          padding: const EdgeInsets.all(60),
        ),
      );
    } else {
      final p = _origenPoint ??
          _destinoPoint ??
          context.read<LocationProvider>().locationOrDefault;
      _mapController.move(p, 12.0);
    }
  }

  Future<void> _calcRoute() async {
    if (_origenPoint == null || _destinoPoint == null) {
      if (mounted) setState(() { _distanciaKm = null; _routePoints = []; });
      return;
    }
    if (mounted) setState(() => _calculatingRoute = true);
    try {
      final url = 'https://router.project-osrm.org/route/v1/driving/'
          '${_origenPoint!.longitude},${_origenPoint!.latitude};'
          '${_destinoPoint!.longitude},${_destinoPoint!.latitude}'
          '?overview=full&geometries=geojson';
      final response = await http
          .get(Uri.parse(url), headers: {'User-Agent': 'inventtia_muevete/1.0'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final route = routes.first as Map<String, dynamic>;
          final distM = (route['distance'] as num).toDouble();
          final geometry = route['geometry'] as Map<String, dynamic>;
          final coords = geometry['coordinates'] as List;
          if (mounted) {
            setState(() {
              _distanciaKm = distM / 1000.0;
              _routePoints = coords
                  .map((c) => LatLng(
                      (c[1] as num).toDouble(), (c[0] as num).toDouble()))
                  .toList();
              _calculatingRoute = false;
            });
          }
          return;
        }
      }
    } catch (_) {}
    // Fallback: straight-line Haversine distance
    if (mounted && _origenPoint != null && _destinoPoint != null) {
      setState(() {
        _distanciaKm = _haversine(_origenPoint!, _destinoPoint!);
        _routePoints = [_origenPoint!, _destinoPoint!];
        _calculatingRoute = false;
      });
    } else if (mounted) {
      setState(() => _calculatingRoute = false);
    }
  }

  double _haversine(LatLng a, LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * pi / 180;
    final dLon = (b.longitude - a.longitude) * pi / 180;
    final s = sin(dLat / 2) * sin(dLat / 2) +
        cos(a.latitude * pi / 180) *
            cos(b.latitude * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(s), sqrt(1 - s));
  }

  // ── Map tap ────────────────────────────────────────────────────────────────

  Future<void> _onMapTap(TapPosition _, LatLng point) async {
    setState(() {
      _resolving = true;
      if (_activeField == 'origin') {
        _origenPoint = point;
        _origenCtrl.text = 'Resolviendo dirección…';
      } else {
        _destinoPoint = point;
        _destinoCtrl.text = 'Resolviendo dirección…';
      }
      _suggestions = [];
    });

    final geo = await _reverseGeocode(point);

    if (!mounted) return;
    setState(() {
      _resolving = false;
      if (_activeField == 'origin') {
        _origenGeo = geo;
        _origenCtrl.text = geo?.displayName ??
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
      } else {
        _destinoGeo = geo;
        _destinoCtrl.text = geo?.displayName ??
            '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}';
        // After setting destination, switch focus back to origin if not set
        if (_origenPoint == null) _activeField = 'origin';
      }
    });
    _fitMap();
    _calcRoute();
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().length < 3) {
      setState(() => _suggestions = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(query.trim());
    });
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _loadingSuggestions = true);
    try {
      final countryFilter = widget.perfilPais != null
          ? '&countrycodes=${_isoCode(widget.perfilPais!)}'
          : '';
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=6&addressdetails=1$countryFilter',
      );
      final response =
          await http.get(uri, headers: {'User-Agent': 'inventtia_muevete/1.0'});
      if (response.statusCode == 200) {
        final List data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _suggestions = data.map((e) => _NominatimResult.fromJson(e)).toList();
          });
        }
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingSuggestions = false);
    }
  }

  void _selectSuggestion(_NominatimResult result) {
    final point = LatLng(result.lat, result.lon);
    final geo = _GeoResult(
      displayName: result.shortName,
      ciudad: result.city,
      provincia: result.state,
      pais: result.country,
    );
    setState(() {
      _suggestions = [];
      if (_activeField == 'origin') {
        _origenPoint = point;
        _origenGeo = geo;
        _origenCtrl.text = result.shortName;
        _activeField = 'dest'; // advance to destination
      } else {
        _destinoPoint = point;
        _destinoGeo = geo;
        _destinoCtrl.text = result.shortName;
      }
    });
    _fitMap();
    _calcRoute();
  }

  // ── Reverse geocode ────────────────────────────────────────────────────────

  Future<_GeoResult?> _reverseGeocode(LatLng point) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=${point.latitude}&lon=${point.longitude}'
        '&format=json&addressdetails=1',
      );
      final response =
          await http.get(uri, headers: {'User-Agent': 'inventtia_muevete/1.0'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final city = (addr['city'] ?? addr['town'] ?? addr['village'] ??
                addr['municipality'] ?? addr['county']) as String?;
        final state = addr['state'] as String?;
        final country = addr['country'] as String?;
        final road = addr['road'] as String?;
        final shortParts = [
          if (road != null) road,
          if (city != null) city,
        ];
        return _GeoResult(
          displayName: shortParts.isNotEmpty
              ? shortParts.join(', ')
              : (data['display_name'] as String? ?? ''),
          ciudad: city,
          provincia: state,
          pais: country,
        );
      }
    } catch (_) {}
    return null;
  }

  // ── Confirm ────────────────────────────────────────────────────────────────

  void _confirm() {
    if (_origenPoint == null || _destinoPoint == null) return;
    Navigator.pop(
      context,
      CargoLocationResult(
        latOrigen: _origenPoint!.latitude,
        lonOrigen: _origenPoint!.longitude,
        dirOrigen: _origenCtrl.text.isNotEmpty
            ? _origenCtrl.text
            : '${_origenPoint!.latitude.toStringAsFixed(5)}, ${_origenPoint!.longitude.toStringAsFixed(5)}',
        ciudadOrigen: _origenGeo?.ciudad,
        provinciaOrigen: _origenGeo?.provincia,
        paisOrigen: _origenGeo?.pais,
        latDestino: _destinoPoint!.latitude,
        lonDestino: _destinoPoint!.longitude,
        dirDestino: _destinoCtrl.text.isNotEmpty
            ? _destinoCtrl.text
            : '${_destinoPoint!.latitude.toStringAsFixed(5)}, ${_destinoPoint!.longitude.toStringAsFixed(5)}',
        ciudadDestino: _destinoGeo?.ciudad,
        provinciaDestino: _destinoGeo?.provincia,
        paisDestino: _destinoGeo?.pais,
        distanciaKm: _distanciaKm,
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;
    final userLoc = context.read<LocationProvider>().locationOrDefault;
    final canConfirm = _origenPoint != null && _destinoPoint != null;

    final markers = <Marker>[
      if (_origenPoint != null)
        Marker(
          point: _origenPoint!,
          width: 44,
          height: 44,
          child: GestureDetector(
            onTap: () => setState(() {
              _activeField = 'origin';
              _suggestions = [];
            }),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.success,
                border: Border.all(
                    color: Colors.white,
                    width: _activeField == 'origin' ? 3.5 : 2),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.success.withValues(alpha: 0.4),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child:
                  const Icon(Icons.local_shipping, color: Colors.white, size: 16),
            ),
          ),
        ),
      if (_destinoPoint != null)
        Marker(
          point: _destinoPoint!,
          width: 44,
          height: 56,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () => setState(() {
              _activeField = 'dest';
              _suggestions = [];
            }),
            child: Icon(
              Icons.location_on,
              color: AppTheme.error,
              size: _activeField == 'dest' ? 44 : 36,
            ),
          ),
        ),
    ];

    return Scaffold(
      backgroundColor: isDark ? AppTheme.darkBg : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: isDark ? AppTheme.darkBg : Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back,
              color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Seleccionar Ruta de Carga',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Search fields ────────────────────────────────────────────────
          Container(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                _LocationField(
                  controller: _origenCtrl,
                  hint: 'Punto de recogida',
                  icon: Icons.local_shipping_outlined,
                  iconColor: AppTheme.success,
                  isActive: _activeField == 'origin',
                  isDark: isDark,
                  onTap: () => setState(() {
                    _activeField = 'origin';
                    _suggestions = [];
                  }),
                  onChanged: (v) {
                    if (_activeField == 'origin') _onSearchChanged(v);
                  },
                ),
                const SizedBox(height: 8),
                _LocationField(
                  controller: _destinoCtrl,
                  hint: 'Punto de entrega',
                  icon: Icons.flag_outlined,
                  iconColor: AppTheme.error,
                  isActive: _activeField == 'dest',
                  isDark: isDark,
                  onTap: () => setState(() {
                    _activeField = 'dest';
                    _suggestions = [];
                  }),
                  onChanged: (v) {
                    if (_activeField == 'dest') _onSearchChanged(v);
                  },
                ),
              ],
            ),
          ),

          // ── Loading / suggestions ─────────────────────────────────────────
          if (_loadingSuggestions || _resolving)
            LinearProgressIndicator(
              color: AppTheme.primaryColor,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
              minHeight: 2,
            ),
          if (_suggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              color: isDark ? AppTheme.darkCard : Colors.white,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) => Divider(
                  height: 1,
                  color: isDark ? AppTheme.darkBorder : Colors.grey[200],
                ),
                itemBuilder: (_, i) {
                  final r = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.place_outlined,
                        color: AppTheme.primaryColor, size: 20),
                    title: Text(
                      r.shortName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    subtitle: r.state != null || r.country != null
                        ? Text(
                            [r.state, r.country]
                                .where((e) => e != null)
                                .join(', '),
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 11,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          )
                        : null,
                    onTap: () => _selectSuggestion(r),
                  );
                },
              ),
            ),

          // ── Map ───────────────────────────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                MapWidget(
                  isDark: isDark,
                  mapController: _mapController,
                  center: _origenPoint ?? _destinoPoint ?? userLoc,
                  zoom: 13.0,
                  markers: markers,
                  polylines: _routePoints.length >= 2
                      ? [
                          Polyline(
                            points: _routePoints,
                            color: AppTheme.primaryColor.withValues(alpha: 0.75),
                            strokeWidth: 3.5,
                          )
                        ]
                      : const [],
                  onTap: _onMapTap,
                ),
                // Active field hint
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _activeField == 'origin'
                            ? 'Toca el mapa para fijar el punto de recogida'
                            : 'Toca el mapa para fijar el punto de entrega',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Status pills ──────────────────────────────────────────────────
          if (_origenGeo != null || _destinoGeo != null || _distanciaKm != null)
            Container(
              color: isDark ? AppTheme.darkSurface : Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_origenGeo != null)
                    _LocationPill(
                      icon: Icons.local_shipping,
                      color: AppTheme.success,
                      label: [
                        if (_origenGeo!.ciudad != null) _origenGeo!.ciudad!,
                        if (_origenGeo!.provincia != null)
                          _origenGeo!.provincia!,
                        if (_origenGeo!.pais != null) _origenGeo!.pais!,
                      ].join(' · '),
                      isDark: isDark,
                    ),
                  if (_origenGeo != null && _destinoGeo != null)
                    const SizedBox(height: 4),
                  if (_destinoGeo != null)
                    _LocationPill(
                      icon: Icons.flag,
                      color: AppTheme.error,
                      label: [
                        if (_destinoGeo!.ciudad != null) _destinoGeo!.ciudad!,
                        if (_destinoGeo!.provincia != null)
                          _destinoGeo!.provincia!,
                        if (_destinoGeo!.pais != null) _destinoGeo!.pais!,
                      ].join(' · '),
                      isDark: isDark,
                    ),
                  if (_distanciaKm != null) ...[  
                    const SizedBox(height: 4),
                    _LocationPill(
                      icon: _calculatingRoute
                          ? Icons.sync_outlined
                          : Icons.straighten_outlined,
                      color: AppTheme.primaryColor,
                      label: _calculatingRoute
                          ? 'Calculando ruta…'
                          : 'Distancia aprox. ${_distanciaKm!.toStringAsFixed(1)} km',
                      isDark: isDark,
                    ),
                  ] else if (_calculatingRoute) ...[  
                    const SizedBox(height: 4),
                    _LocationPill(
                      icon: Icons.sync_outlined,
                      color: AppTheme.primaryColor,
                      label: 'Calculando ruta…',
                      isDark: isDark,
                    ),
                  ],
                ],
              ),
            ),

          // ── Confirm button ────────────────────────────────────────────────
          Container(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canConfirm ? _confirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    disabledBackgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.35),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text(
                    canConfirm
                        ? 'Confirmar Ruta'
                        : (_origenPoint == null
                            ? 'Selecciona el origen primero'
                            : 'Selecciona el destino'),
                    style: GoogleFonts.plusJakartaSans(
                        fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

class _GeoResult {
  final String displayName;
  final String? ciudad;
  final String? provincia;
  final String? pais;
  const _GeoResult(
      {required this.displayName, this.ciudad, this.provincia, this.pais});
}

class _NominatimResult {
  final double lat;
  final double lon;
  final String shortName;
  final String? city;
  final String? state;
  final String? country;

  const _NominatimResult({
    required this.lat,
    required this.lon,
    required this.shortName,
    this.city,
    this.state,
    this.country,
  });

  factory _NominatimResult.fromJson(Map<String, dynamic> j) {
    final addr = j['address'] as Map<String, dynamic>? ?? {};
    final city = (addr['city'] ?? addr['town'] ?? addr['village'] ??
        addr['municipality'] ?? addr['county']) as String?;
    final state = addr['state'] as String?;
    final country = addr['country'] as String?;
    final road = addr['road'] as String?;
    final shortParts = [
      if (road != null) road,
      if (city != null) city,
    ];
    return _NominatimResult(
      lat: double.parse(j['lat'] as String),
      lon: double.parse(j['lon'] as String),
      shortName: shortParts.isNotEmpty
          ? shortParts.join(', ')
          : (j['display_name'] as String? ?? ''),
      city: city,
      state: state,
      country: country,
    );
  }
}

/// Rough ISO-3166-1 alpha-2 lookup for common countries.
String _isoCode(String country) {
  const map = {
    'cuba': 'cu',
    'mexico': 'mx',
    'united states': 'us',
    'estados unidos': 'us',
    'colombia': 'co',
    'venezuela': 've',
    'argentina': 'ar',
    'brasil': 'br',
    'brazil': 'br',
    'chile': 'cl',
    'peru': 'pe',
    'ecuador': 'ec',
    'bolivia': 'bo',
    'paraguay': 'py',
    'uruguay': 'uy',
    'españa': 'es',
    'spain': 'es',
    'panama': 'pa',
    'costa rica': 'cr',
    'guatemala': 'gt',
    'honduras': 'hn',
    'nicaragua': 'ni',
    'el salvador': 'sv',
    'dominican republic': 'do',
    'republica dominicana': 'do',
    'puerto rico': 'pr',
  };
  return map[country.toLowerCase()] ?? '';
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LocationField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  const _LocationField({
    required this.controller,
    required this.hint,
    required this.icon,
    required this.iconColor,
    required this.isActive,
    required this.isDark,
    required this.onTap,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: isDark ? AppTheme.darkCard : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive
                ? iconColor
                : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
            width: isActive ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            const SizedBox(width: 12),
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                onTap: onTap,
                onChanged: onChanged,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: GoogleFonts.plusJakartaSans(
                    fontSize: 14,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            if (controller.text.isNotEmpty)
              IconButton(
                icon: Icon(Icons.clear,
                    size: 18,
                    color: isDark ? Colors.white38 : Colors.grey[400]),
                onPressed: () {
                  controller.clear();
                  onTap();
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _LocationPill extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool isDark;

  const _LocationPill({
    required this.icon,
    required this.color,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: isDark ? Colors.white70 : Colors.grey[700],
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
