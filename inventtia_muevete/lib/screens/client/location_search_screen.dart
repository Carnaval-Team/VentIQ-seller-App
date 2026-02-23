import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../config/app_theme.dart';
import '../../providers/location_provider.dart';
import '../../providers/theme_provider.dart';
import '../../providers/transport_provider.dart';
import '../../widgets/map_widget.dart';
import 'route_preview_screen.dart';

class LocationSearchScreen extends StatefulWidget {
  const LocationSearchScreen({super.key});

  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final MapController _mapController = MapController();
  final TextEditingController _originController = TextEditingController();
  final TextEditingController _destController = TextEditingController();

  // Which field is active: 'origin' or 'dest'
  String _activeField = 'dest';

  List<_NominatimResult> _suggestions = [];
  bool _loadingSuggestions = false;
  Timer? _debounce;

  // Confirmed points
  LatLng? _originPoint;
  LatLng? _destPoint;

  @override
  void initState() {
    super.initState();
    final transportProvider = context.read<TransportProvider>();
    final locationProvider = context.read<LocationProvider>();

    // Pre-fill from existing provider state
    _originPoint =
        transportProvider.pickupLocation ?? locationProvider.locationOrDefault;
    _destPoint = transportProvider.dropoffLocation;

    _originController.text =
        transportProvider.pickupAddress ?? 'Ubicación actual';
    _destController.text = transportProvider.dropoffAddress ?? '';

    // Focus destination field if origin is already set
    if (_originPoint != null) _activeField = 'dest';
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _originController.dispose();
    _destController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // ── Nominatim search ──────────────────────────────────────────────────────

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
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/search'
        '?q=${Uri.encodeComponent(query)}'
        '&format=json&limit=6&addressdetails=1',
      );
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'inventtia_muevete/1.0'},
      );
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _suggestions = data
              .map((e) => _NominatimResult.fromJson(e))
              .toList();
        });
      }
    } catch (_) {
      // silently ignore network errors
    } finally {
      setState(() => _loadingSuggestions = false);
    }
  }

  void _selectSuggestion(_NominatimResult result) {
    final point = LatLng(result.lat, result.lon);
    setState(() {
      _suggestions = [];
      if (_activeField == 'origin') {
        _originPoint = point;
        _originController.text = result.displayName;
      } else {
        _destPoint = point;
        _destController.text = result.displayName;
      }
    });
    _mapController.move(point, 15.0);
  }

  // ── Map tap to set point ──────────────────────────────────────────────────

  void _onMapTap(TapPosition _, LatLng point) {
    setState(() {
      if (_activeField == 'origin') {
        _originPoint = point;
        _originController.text = 'Punto seleccionado en mapa';
      } else {
        _destPoint = point;
        _destController.text = 'Destino en mapa';
      }
      _suggestions = [];
    });
  }

  // ── Confirm route ─────────────────────────────────────────────────────────

  void _confirmRoute() {
    if (_originPoint == null || _destPoint == null) return;

    final transportProvider = context.read<TransportProvider>();
    transportProvider.setPickup(
      _originPoint!,
      address: _originController.text.isNotEmpty
          ? _originController.text
          : 'Origen',
    );
    transportProvider.setDropoff(
      _destPoint!,
      address: _destController.text.isNotEmpty
          ? _destController.text
          : 'Destino',
    );

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const RoutePreviewScreen()),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = context.watch<ThemeProvider>().isDark;

    final markers = <Marker>[
      if (_originPoint != null)
        Marker(
          point: _originPoint!,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.success,
              border: Border.all(color: Colors.white, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.success.withValues(alpha: 0.4),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(Icons.my_location, color: Colors.white, size: 16),
          ),
        ),
      if (_destPoint != null)
        Marker(
          point: _destPoint!,
          width: 36,
          height: 50,
          alignment: Alignment.topCenter,
          child: const Icon(Icons.location_on,
              color: AppTheme.error, size: 36),
        ),
    ];

    final canConfirm = _originPoint != null && _destPoint != null;

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
          'Elige tu trayecto',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : Colors.black87,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Search fields ──────────────────────────────────────────────
          Container(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                // Origin field
                _SearchField(
                  controller: _originController,
                  hint: 'Origen',
                  icon: Icons.radio_button_checked,
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
                // Dest field
                _SearchField(
                  controller: _destController,
                  hint: '¿A dónde vas?',
                  icon: Icons.location_on,
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

          // ── Suggestions list ───────────────────────────────────────────
          if (_loadingSuggestions)
            LinearProgressIndicator(
              color: AppTheme.primaryColor,
              backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.15),
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
                itemBuilder: (context, i) {
                  final r = _suggestions[i];
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.place_outlined,
                      color: AppTheme.primaryColor,
                      size: 20,
                    ),
                    title: Text(
                      r.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    onTap: () => _selectSuggestion(r),
                  );
                },
              ),
            ),

          // ── Map (tap to set point) ─────────────────────────────────────
          Expanded(
            child: Stack(
              children: [
                MapWidget(
                  isDark: isDark,
                  mapController: _mapController,
                  center: _originPoint ??
                      context.read<LocationProvider>().locationOrDefault,
                  zoom: 14.0,
                  markers: markers,
                  onTap: _onMapTap,
                ),
                // Hint overlay
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
                            ? 'Toca el mapa para fijar el origen'
                            : 'Toca el mapa para fijar el destino',
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

          // ── Confirm button ─────────────────────────────────────────────
          Container(
            color: isDark ? AppTheme.darkSurface : Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: canConfirm ? _confirmRoute : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    disabledBackgroundColor:
                        AppTheme.primaryColor.withValues(alpha: 0.4),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Confirmar trayecto',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
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

// ── Reusable search field ──────────────────────────────────────────────────

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final bool isActive;
  final bool isDark;
  final VoidCallback onTap;
  final ValueChanged<String> onChanged;

  const _SearchField({
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
          prefixIcon: Icon(icon, color: iconColor, size: 20),
          suffixIcon: controller.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.close,
                      size: 18,
                      color: isDark ? Colors.white38 : Colors.grey),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                )
              : null,
          filled: true,
          fillColor: isActive
              ? (isDark
                  ? AppTheme.primaryColor.withValues(alpha: 0.12)
                  : AppTheme.primaryColor.withValues(alpha: 0.06))
              : (isDark ? AppTheme.darkCard : Colors.grey[100]),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isActive
                  ? AppTheme.primaryColor
                  : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
              width: isActive ? 2 : 1,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: isActive
                  ? AppTheme.primaryColor
                  : (isDark ? AppTheme.darkBorder : Colors.grey[300]!),
              width: isActive ? 2 : 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide:
                const BorderSide(color: AppTheme.primaryColor, width: 2),
          ),
        ),
      ),
    );
  }
}

// ── Nominatim result model ─────────────────────────────────────────────────

class _NominatimResult {
  final String displayName;
  final double lat;
  final double lon;

  _NominatimResult({
    required this.displayName,
    required this.lat,
    required this.lon,
  });

  factory _NominatimResult.fromJson(Map<String, dynamic> json) {
    return _NominatimResult(
      displayName: json['display_name'] as String,
      lat: double.parse(json['lat'] as String),
      lon: double.parse(json['lon'] as String),
    );
  }
}
